##########################################################################################################
# $Id: 93_DbRep.pm 28267 2024-01-09 21:52:20Z DS_Starter $
##########################################################################################################
#       93_DbRep.pm
#
#       (c) 2016-2024 by Heiko Maaz
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
#  - function reduceLog created by Claudiu Schuster (rapster) was copied from DbLog (Version 3.12.3 08.10.2018)
#    and changed to meet the requirements of DbRep
#
###########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 93_DbRep.pm
#
###########################################################################################################################
package main;

use strict;
use warnings;
use POSIX qw(strftime SIGALRM);
use Time::HiRes qw(gettimeofday tv_interval);
use Scalar::Util qw(looks_like_number);
eval "use DBI;1"                                or my $DbRepMMDBI    = "DBI";
eval "use FHEM::Meta;1"                         or my $modMetaAbsent = 1;
use DBI::Const::GetInfoType;
use Blocking;
use Color;                                                                       # colorpicker Widget
use Time::Local;
use HttpUtils;
use Encode;

use FHEM::SynoModules::SMUtils qw( evalDecodeJSON );

use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Version History intern
my %DbRep_vNotesIntern = (
  "8.53.0"  => "09.01.2024  new setter multiCmd, change DbRep_autoForward, fix reducelog Hash management ",
  "8.52.15" => "08.12.2023  fix use fhem default variables in attr executeBeforeProc/executeAfterProc ".
                            "forum: https://forum.fhem.de/index.php?msg=1296146 ",
  "8.52.14" => "08.11.2023  fix period calculation when using attr timeYearPeriod ",
  "8.52.13" => "07.11.2023  dumpMySQL clientSide: add create database to dump file ",
  "8.52.12" => "05.11.2023  dumpMySQL clientSide: change the dump file to stricter rights ",
  "8.52.11" => "17.09.2023  improve the markout in func DbRep_checkValidTimeSequence, Forum:#134973 ",
  "8.52.10" => "09.07.2023  fix wrong SQL syntax for PostgreSQL -> DbRep_createSelectSql, Forum:#134170 ",
  "8.52.9"  => "05.07.2023  fix wrong SQL syntax for PostgreSQL -> maxValue deleteOther, Forum:#134170 ",
  "8.52.8"  => "28.06.2023  fix check of DbRep_afterproc, DbRep_beforeproc if should exec PERL code ",
  "8.52.7"  => "16.05.2023  DbRep_afterproc, DbRep_beforeproc can execute FHEM commands as well as PERL code ",
  "8.52.6"  => "11.04.2023  change diffValue for aggr month ",
  "8.52.5"  => "10.04.2023  change diffValue, Forum: https://forum.fhem.de/index.php?msg=1271853 ",
  "8.52.4"  => "10.04.2023  fix perl warning ",
  "8.52.3"  => "04.04.2023  fix diffValue writeToDB: https://forum.fhem.de/index.php?topic=53584.msg1270905#msg1270905 ",
  "8.52.2"  => "28.03.2023  diffValue can operate positive and negative differences, sqlCmd can execute 'describe' statement ",
  "8.52.1"  => "19.03.2023  fix Perl Warnings ",
  "8.52.0"  => "17.02.2023  get utf8mb4 info by connect db and set connection collation accordingly, new setter migrateCollation ",
  "8.51.6"  => "11.02.2023  fix execute DbRep_afterproc after generating readings ".
                            "Forum: https://forum.fhem.de/index.php/topic,53584.msg1262970.html#msg1262970 ".
                            "fix MySQL 50mostFreqLogsLast2days ",
  "8.51.5"  => "05.02.2023  fix Perl Warning Forum: https://forum.fhem.de/index.php/topic,53584.msg1262032.html#msg1262032 ",
  "8.51.4"  => "01.02.2023  ignore non-numeric values in diffValue and output the erroneous record in the log ",
  "8.51.3"  => "22.01.2023  extend DbRep_averval avgTimeWeightMean by alkazaa, Restructuring of DbRep_averval ".
                            "DbRep_reduceLog -> Handling of field 'value' with NULL value ",
  "8.51.2"  => "13.01.2023  rewrite sub DbRep_OutputWriteToDB, new averageValue option writeToDBSingleStart ",
  "8.51.1"  => "11.01.2023  write TYPE uppercase with writeToDB option, Commandref edited, fix add SQL Cache History ".
                            "set PRAGMA auto_vacuum = FULL when execute SQLite vacuum command",
  "8.51.0"  => "02.01.2023  online formatting of sqlCmd, sqlCmdHistory, sqlSpecial, Commandref edited, get dbValue removed ".
                            "sqlCmdBlocking customized like sqlCmd, bugfix avgTimeWeightMean ",
  "8.50.10" => "01.01.2023  Commandref edited ",
  "8.50.9"  => "28.12.2022  Commandref changed to a id-links ",
  "8.50.8"  => "21.12.2022  add call to DbRep_sqlCmd, DbRep_sqlCmdBlocking ",
  "8.50.7"  => "17.12.2022  Commandref edited ",
  "8.50.6"  => "14.12.2022  remove ularm from Time::HiRes, Forum: https://forum.fhem.de/index.php/topic,53584.msg1251313.html#msg1251313 ",
  "8.50.5"  => "05.12.2022  fix diffValue problem (DbRep_diffval) for newer MariaDB versions: https://forum.fhem.de/index.php/topic,130697.0.html ",
  "8.50.4"  => "04.11.2022  fix daylight saving bug in aggregation eq 'month' (_DbRep_collaggstr) ",
  "8.50.3"  => "19.09.2022  reduce memory allocation of function DbRep_reduceLog ",
  "8.50.2"  => "17.09.2022  release setter 'index' for device model 'Agent' ",
  "8.50.1"  => "05.09.2022  DbRep_setLastCmd, change changeValue syntax, minor fixes ",
  "8.50.0"  => "20.08.2022  rework of DbRep_reduceLog - add max, max=day, min, min=day, sum, sum=day ",
  "8.49.1"  => "03.08.2022  fix DbRep_deleteOtherFromDB, Forum: https://forum.fhem.de/index.php/topic,128605.0.html ".
                            "some code changes and bug fixes ",
  "8.49.0"  => "16.05.2022  allow optionally set device / reading in the insert command ",
  "8.48.4"  => "16.05.2022  fix perl warning of set ... insert, Forum: topic,53584.msg1221588.html#msg1221588 ",
  "8.48.3"  => "09.04.2022  minor code fix in DbRep_reduceLog ",
  "8.48.2"  => "22.02.2022  more code refacturing ",
  "8.48.1"  => "31.01.2022  minor fixes e.g. in file size determination, dump routines ",
  "8.48.0"  => "29.01.2022  new sqlCmdHistory params ___restore_sqlhistory___ , ___save_sqlhistory___ ".
                            "change _DbRep_mysqlOptimizeTables, revise insert command ",
  "8.47.0"  => "17.01.2022  new design of sqlCmdHistory, minor fixes ",
  "8.46.13" => "12.01.2022  more code refacturing, minor fixes ",
  "8.46.12" => "10.01.2022  more code refacturing, minor fixes, change usage of placeholder §device§, §reading§ in sqlCmd ",
  "8.46.11" => "03.01.2022  more code refacturing, minor fixes ",
  "8.46.10" => "02.01.2022  more code refacturing, minor fixes ",
  "8.46.9"  => "01.01.2022  some more code refacturing, minor fixes ",
  "1.0.0"   => "19.05.2016  Initial"
);

# Version History extern:
my %DbRep_vNotesExtern = (
  "8.46.3"  => "12.12.2021 The new getter 'initData' is implemented. The command retrieves some relevant database properties for the module function. ",
  "8.46.2"  => "08.12.2021 Pragma query is now possible in sqlCmd. ",
  "8.46.0"  => "06.12.2021 Some reduceLog problems are fixed. ",
  "8.44.0"  => "21.11.2021 A new attribute 'numDecimalPlaces' for adjusting the decimal places in numeric results is implemented ",
  "8.42.3"  => "03.01.2021 The attribute fastStart is set now as default for TYPE Client. This way the DbRep device only connects to the database when it has to process a task and not immediately when FHEM is started. ",
  "8.40.7"  => "03.09.2020 The get Command \"dbValue\" has been renamed to \"sqlCmdBlocking\. You can use \"dbValue\" furthermore in your scripts, but it is ".
                           "deprecated and will be removed soon. Please change your scripts to use \"sqlCmdBlocking\" instead. ",
  "8.40.4"  => "23.07.2020 The new aggregation type 'minute' is now available. ",
  "8.40.0"  => "30.03.2020 The option 'writeToDBInTime' is provided for function 'sumValue' and 'averageValue'. ".
                           "A new attribute 'autoForward' is implemented. Now it is possible to transfer the results from the DbRep-Device to another one. ".
                           "Please see also this (german) <a href=\"https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#Readingwerte_von_DbRep_in_ein_anderes_Device_.C3.BCbertragen\">Wiki article</a> ",
  "8.36.0"  => "19.03.2020 Some simplifications for fast mutable module usage is built in, such as possible command option older than / newer than days for reduceLog and delEntries function. ".
                           "A new option \"writeToDBSingle\" for functions averageValue, sumValue is built in as well as a new sqlSpecial \"recentReadingsOfDevice\". ",
  "8.32.0"  => "29.01.2020 A new option \"deleteOther\" is available for commands \"maxValue\" and \"minValue\". Now it is possible to delete all values except the ".
                           "extreme values (max/min) from the database within the specified limits of time, device, reading and so on. ",
  "8.30.4"  => "22.01.2020 The behavior of write back values to database is changed for functions averageValue and sumValue. The solution values of that functions now are ".
                           "written at every begin and also at every end of specified aggregation period. ",
  "8.30.0"  => "14.11.2019 A new command \"set <name> adminCredentials\" and \"get <name> storedCredentials\" ist provided. ".
                           "Use it to store a database priviledged user. This user DbRep can utilize for several operations which are need more (administative) ".
                           "user rights (e.g. index, sqlCmd). ",
  "8.29.0"  => "08.11.2019 add option FullDay for timeDiffToNow and timeOlderThan, Forum: https://forum.fhem.de/index.php/topic,53584.msg991139.html#msg991139 ",
  "8.28.0"  => "30.09.2019 seqDoubletsVariance - separate specification of positive and negative variance possible, Forum: https://forum.fhem.de/index.php/topic,53584.msg959963.html#msg959963 ",
  "8.25.0"  => "29.08.2019 If a list of devices in attribute \"device\" contains a SQL wildcard (\%), this wildcard is now "
                           ."dissolved into separate devices if they are still existing in your FHEM configuration. "
                           ."Please see <a href=\"https://forum.fhem.de/index.php/topic,101756.0.html\">this Forum Thread</a> "
                           ."for further information. ",
  "8.24.0"  => "24.08.2019 Devices which are specified in attribute \"device\" are marked as \"Associated With\" if they are "
                           ."still existing in your FHEM configuration. At least fhem.pl 20069 2019-08-27 08:36:02 is needed. ",
  "8.22.0"  => "23.08.2019 A new attribute \"fetchValueFn\" is provided. When fetching the database content, you are able to manipulate ".
                           "the value displayed from the VALUE database field before create the appropriate reading. ",
  "8.21.0"  => "28.04.2019 FHEM command \"dbReadingsVal\" implemented.",
  "8.20.0"  => "27.04.2019 With the new set \"index\" command it is now possible to list and (re)create the indexes which are ".
                           "needed for DbLog and/or DbRep operation.",
  "8.19.0"  => "04.04.2019 The \"explain\" SQL-command is possible in sqlCmd ",
  "8.18.0"  => "01.04.2019 New aggregation type \"year\" ",
  "8.17.0"  => "20.03.2019 With new attribute \"sqlCmdVars\" you are able to set SQL session variables or SQLite PRAGMA every time ".
                           "before running a SQL-statement with sqlCmd command.",
  "8.16.0"  => "17.03.2019 allow SQLite PRAGMAS leading an SQLIte SQL-Statement in sqlCmd ",
  "8.15.0"  => "04.03.2019 readingsRename can now rename readings of a given (optional) device instead of all found readings specified in command ",
  "8.13.0"  => "11.02.2019 executeBeforeProc / executeAfterProc is now available for sqlCmd,sumValue, maxValue, minValue, diffValue, averageValue ",
  "8.11.0"  => "24.01.2019 command exportToFile or attribute \"expimpfile\" accepts option \"MAXLINES=\" ",
  "8.10.0"  => "19.01.2019 In commands sqlCmd, dbValue you may now use SQL session variables like \"SET \@open:=NULL,\@closed:=NULL; SELECT ...\", Forum:#96082 ",
  "8.9.0"   => "07.11.2018 new command set delDoublets added. This command allows to delete multiple occuring identical records. ",
  "8.8.0"   => "06.11.2018 new attribute 'fastStart'. Usually every DbRep-device is making a short connect to its database when "
                           ."FHEM is restarted. When this attribute is set, the initial connect is done when the DbRep-device is doing its "
                           ."first task. ",
  "8.7.0"   => "04.11.2018 attribute valueFilter applied to functions 'averageValue, changeValue, countEntries, delEntries, "
                           ."delSeqDoublets, diffValue, exportToFile, fetchrows, maxValue, minValue, reduceLog, sumValue, syncStandby' ,"
                           ." 'valueFilter' generally applied to database field 'VALUE' ",
  "8.6.0"   => "29.10.2018 reduceLog use attributes device/reading (can be overwritten by set-options) ",
  "8.5.0"   => "27.10.2018 devices and readings can be excluded by EXCLUDE-option in attributes \$reading/\$device ",
  "8.4.0"   => "22.10.2018 New attribute \"countEntriesDetail\". Function countEntries creates number of datasets for every ".
                           "reading separately if attribute \"countEntriesDetail\" is set. Get versionNotes changed to support en/de. ".
                           "Function \"get dbValue\" opens an editor window ",
  "8.3.0"   => "17.10.2018 reduceLog from DbLog integrated into DbRep, textField-long as default for sqlCmd, both attributes ".
                           "timeOlderThan and timeDiffToNow can be set at same time -> the selection time between timeOlderThan ".
                           "and timeDiffToNow can be calculated dynamically ",
  "8.2.2"   => "07.10.2018 fix don't get the real min timestamp in rare cases ",
  "8.2.0"   => "05.10.2018 direct help for attributes ",
  "8.1.0"   => "01.10.2018 new get versionNotes command ",
  "8.0.0"   => "11.09.2018 get filesize in DbRep_WriteToDumpFile corrected, restoreMySQL for clientSide dumps, minor fixes ",
  "7.20.0"  => "04.09.2018 deviceRename can operate a Device name with blank, e.g. 'current balance' as old device name ",
  "7.19.0"  => "25.08.2018 attribute 'valueFilter' to filter datasets in fetchrows ",
  "7.18.2"  => "02.08.2018 fix in fetchrow function (forum:#89886), fix highlighting ",
  "7.18.0"  => "02.06.2018 possible use of y:(\\d) for timeDiffToNow, timeOlderThan , minor fixes of timeOlderThan, delEntries considers executeBeforeDump,executeAfterDump ",
  "7.17.3"  => "30.04.2018 writeToDB - readingname can be replaced by the value of attribute 'readingNameMap' ",
  "7.17.0"  => "17.04.2018 new function DbReadingsVal ",
  "7.16.0"  => "13.04.2018 new function dbValue (blocking) ",
  "7.15.2"  => "12.04.2018 fix in setting MODEL, prevent fhem from crash if wrong timestamp '0000-00-00' found in db ",
  "7.15.1"  => "11.04.2018 sqlCmd accept widget textField-long, Internal MODEL is set ",
  "7.15.0"  => "24.03.2018 new command sqlSpecial ",
  "7.14.7"  => "21.03.2018 exportToFile,importFromFile can use file as an argument and executeBeforeDump, executeAfterDump is considered ",
  "7.14.6"  => "18.03.2018 attribute expimpfile can use some kinds of wildcards (exportToFile, importFromFile adapted) ",
  "7.14.3"  => "07.03.2018 DbRep_firstconnect changed - get lowest timestamp in database, DbRep_Connect deleted ",
  "7.14.0"  => "26.02.2018 new syncStandby command",
  "7.12.0"  => "16.02.2018 compression of dumpfile, restore of compressed files possible ",
  "7.11.0"  => "12.02.2018 new command 'repairSQLite' to repair a corrupted SQLite database ",
  "7.10.0"  => "10.02.2018 bugfix delete attr timeYearPeriod if set other time attributes, new 'changeValue' command ",
  "7.9.0"   => "09.02.2018 new attribute 'avgTimeWeightMean' (time weight mean calculation), code review of selection routines, maxValue handle negative values correctly, one security second for correct create TimeArray in DbRep_normRelTime ",
  "7.8.1"   => "04.02.2018 bugfix if IsDisabled (again), code review, bugfix last dataset is not selected if timestamp is fully set ('date time'), fix '\$runtime_string_next' = '\$runtime_string_next.999';' if \$runtime_string_next is part of sql-execute place holder AND contains date+time ",
  "7.8.0"   => "04.02.2018 new command 'eraseReadings' ",
  "7.7.1"   => "03.02.2018 minor fix in DbRep_firstconnect if IsDisabled ",
  "7.7.0"   => "29.01.2018 attribute 'averageCalcForm', calculation sceme 'avgDailyMeanGWS', 'avgArithmeticMean' for averageValue ",
  "7.6.1"   => "27.01.2018 new attribute 'sqlCmdHistoryLength' and 'fetchMarkDuplicates' for highlighting multiple datasets by fetchrows ",
  "7.5.3"   => "23.01.2018 new attribute 'ftpDumpFilesKeep', version management added to FTP-usage ",
  "7.4.1"   => "14.01.2018 fix old dumpfiles not deleted by dumpMySQL clientSide ",
  "7.4.0"   => "09.01.2018 dumpSQLite/restoreSQLite, backup/restore now available when DbLog-device has reopen xxxx running, executeBeforeDump executeAfterDump also available for optimizeTables, vacuum, restoreMySQL, restoreSQLite, attribute executeBeforeDump / executeAfterDump renamed to executeBeforeProc & executeAfterProc ",
  "7.3.1"   => "08.01.2018 fix syntax error for perl < 5.20 ",
  "7.3.0"   => "07.01.2018 charfilter avoid control characters in datasets to exportToFile / importFromFile, changed to use aggregation for split selects in timeslices by exportToFile (avoid heavy memory consumption) ",
  "7.1.0"   => "22.12.2017 new attribute timeYearPeriod for reports correspondig to e.g. electricity billing, bugfix connection check is running after restart allthough dev is disabled ",
  "6.4.1"   => "13.12.2017 new Attribute 'sqlResultFieldSep' for field separate options of sqlCmd result ",
  "6.4.0"   => "10.12.2017 prepare module for usage of datetime picker widget (Forum:#35736) ",
  "6.1.0"   => "29.11.2017 new command delSeqDoublets (adviceRemain,adviceDelete), add Option to LASTCMD ",
  "6.0.0"   => "18.11.2017 FTP transfer dumpfile after dump, delete old dumpfiles within Blockingcall (avoid freezes) commandref revised, minor fixes ",
  "5.6.4"   => "05.10.2017 abortFn's adapted to use abortArg (Forum:77472) ",
  "5.6.3"   => "01.10.2017 fix crash of fhem due to wrong rmday-calculation if month is changed, Forum:#77328 ",
  "5.6.0"   => "17.07.2017 default timeout changed to 86400, new get-command 'procinfo' (MySQL) ",
  "5.4.0"   => "03.07.2017 restoreMySQL - restore of csv-files (from dumpServerSide), RestoreRowsHistory/ DumpRowsHistory, Commandref revised ",
  "5.3.1"   => "28.06.2017 vacuum for SQLite added, readings enhanced for optimizeTables / vacuum, commandref revised ",
  "5.3.0"   => "26.06.2017 change of _DbRep_mysqlOptimizeTables, new command optimizeTables ",
  "5.0.6"   => "13.06.2017 add Aria engine to _DbRep_mysqlOptimizeTables ",
  "5.0.3"   => "07.06.2017 DbRep_mysql_DumpServerSide added ",
  "5.0.1"   => "05.06.2017 dependencies between dumpMemlimit and dumpSpeed created, enhanced verbose 5 logging ",
  "5.0.0"   => "04.06.2017 MySQL Dump nonblocking added ",
  "4.16.1"  => "22.05.2017 encode json without JSON module, requires at least fhem.pl 14348 2017-05-22 20:25:06Z ",
  "4.14.1"  => "16.05.2017 limitation of fetchrows result datasets to 1000 by attr limit ",
  "4.14.0"  => "15.05.2017 UserExitFn added as separate sub (DbRep_userexit) and attr userExitFn defined, new subs ReadingsBulkUpdateTimeState, ReadingsBulkUpdateValue, ReadingsSingleUpdateValue, commandref revised ",
  "4.13.4"  => "09.05.2017 attribute sqlResultSingleFormat: mline sline table, attribute 'allowDeletion' is now also valid for sqlResult, sqlResultSingle and delete command is forced ",
  "4.13.2"  => "09.05.2017 sqlResult, sqlResultSingle are able to execute delete, insert, update commands error corrections ",
  "4.12.0"  => "31.03.2017 support of primary key for insert functions ",
  "4.11.3"  => "26.03.2017 usage of daylight saving time changed to avoid wrong selection when wintertime switch to summertime, minor bug fixes ",
  "4.11.0"  => "18.02.2017 added [current|previous]_[month|week|day|hour]_begin and [current|previous]_[month|week|day|hour]_end as options of timestamp ",
  "4.9.0"   => "23.12.2016 function readingRename added ",
  "4.8.6"   => "17.12.2016 new bugfix group by-clause due to incompatible changes made in MyQL 5.7.5 (Forum #msg541103) ",
  "4.8.5"   => "16.12.2016 bugfix group by-clause due to Forum #msg540610 ",
  "4.7.6"   => "07.12.2016 DbRep version as internal, check if perl module DBI is installed ",
  "4.7.4"   => "28.11.2016 sub DbRep_calcount changed due to Forum #msg529312 ",
  "4.7.3"   => "20.11.2016 new diffValue function made suitable to SQLite ",
  "4.6.0"   => "31.10.2016 bugfix calc issue due to daylight saving time end (winter time) ",
  "4.5.1"   => "18.10.2016 get svrinfo contains SQLite database file size (MB), modified timeout routine ",
  "4.2.0"   => "10.10.2016 allow SQL-Wildcards in attr reading & attr device ",
  "4.1.3"   => "09.10.2016 bugfix delEntries running on SQLite ",
  "3.13.0"  => "03.10.2016 added deviceRename to rename devices in database, new Internal DATABASE ",
  "3.12.0"  => "02.10.2016 function minValue added ",
  "3.11.1"  => "30.09.2016 bugfix include first and next day in calculation if Timestamp is exactly 'YYYY-MM-DD 00:00:00' ",
  "3.9.0"   => "26.09.2016 new function importFromFile to import data from file (CSV format) ",
  "3.8.0"   => "16.09.2016 new attr readingPreventFromDel to prevent readings from deletion when a new operation starts ",
  "3.7.2"   => "04.09.2016 problem in diffValue fixed if if no value was selected ",
  "3.7.1"   => "31.08.2016 Reading 'errortext' added, commandref continued, exportToFile changed, diffValue changed to fix wrong timestamp if error occur ",
  "3.7.0"   => "30.08.2016 exportToFile added exports data to file (CSV format) ",
  "3.5.0"   => "18.08.2016 new attribute timeOlderThan ",
  "3.4.4"   => "12.08.2016 current_year_begin, previous_year_begin, current_year_end, previous_year_end added as possible values for timestamp attribute ",
  "3.4.0"   => "03.08.2016 function 'insert' added ",
  "3.3.1"   => "15.07.2016 function 'diffValue' changed, write '-' if no value ",
  "3.3.0"   => "12.07.2016 function 'diffValue' added ",
  "3.1.1"   => "10.07.2016 state turns to initialized and connected after attr 'disabled' is switched from '1' to '0' ",
  "3.1.0"   => "09.07.2016 new Attr 'timeDiffToNow' and change subs according to that ",
  "3.0.0"   => "04.07.2016 no selection if timestamp isn't set and aggregation isn't set with fetchrows, delEntries ",
  "2.9.8"   => "01.07.2016 changed fetchrows_ParseDone to handle readingvalues with whitespaces correctly ",
  "2.9.5"   => "30.06.2016 format of readingnames changed again (substitute ':' with '-' in time) ",
  "2.9.4"   => "30.06.2016 change readingmap to readingNameMap, prove of unsupported characters added ",
  "2.9.3"   => "27.06.2016 format of readingnames changed avoiding some problems after restart and splitting ",
  "2.9.0"   => "25.06.2016 attributes showproctime, timeout added ",
  "2.8.0"   => "24.06.2016 function averageValue changed to nonblocking function ",
  "2.7.0"   => "23.06.2016 changed function countEntries to nonblocking ",
  "2.6.2"   => "21.06.2016 aggregation week corrected ",
  "2.6.1"   => "20.06.2016 routine maxval_ParseDone corrected ",
  "2.6.0"   => "31.05.2016 maxValue changed to nonblocking function ",
  "2.4.0"   => "29.05.2016 changed to nonblocking function for sumValue ",
  "2.0.0"   => "24.05.2016 added nonblocking function for fetchrow ",
  "1.2.0"   => "21.05.2016 function and attribute for delEntries added ",
  "1.0.0"   => "19.05.2016 Initial"
);

# Hint Hash en
my %DbRep_vHintsExt_en = (
  "6" => "In some places in DbRep SQL wildcard characters can be used. It is explicitly pointed out. <br> ".
         "A wildcard character can be used to replace any other character(s) in a string.<br> ".
         "SQL wildcards are <a href=\"http://www.w3bai.com/en-US/sql/sql_wildcards.html\">described in more detail here</a>. ",
  "5" => "The grassland temperature sum (GTS) is a special form of the growth degree days, which is used in agricultural meteorology. ".
         "It is used to determine the date for the beginning of field work after winter in Central Europe.<br> ".
         "All positive daily averages are recorded from the beginning of the year. In January is multiplied by the factor 0.5, in February ".
         " by the factor 0.75, and from March onwards the „full“ daily value (times factor 1) is then included in the calculation.<br> ".
         "If the sum of 200 is exceeded in spring, the sustainable vegetation start is reached. The background is the ".
         " nitrogen uptake and processing of the soil, which is dependent on this temperature sum. In middle latitudes ".
         "this is usually achieved in the course of March, at the turn from early spring to mid-spring. <br>".
         "(see also <a href=\"https://de.wikipedia.org/wiki/Grünlandtemperatursumme\">Grünlandtemperatursumme in Wikipedia</a>) ",
  "4" => "The attribute 'valueFilter' can specify a REGEXP expression that is used for additional field selection as described in set-function. "
         ."If you need more assistance please to the manual of your used database. For example the overview about REGEXP for "
         ."MariaDB refer to <a href=\"https://mariadb.com/kb/en/library/regular-expressions-overview\">Regular Expressions "
         ."Overview</a>. ",
  "3" => "Features and restrictions of complex <a href=\"https://fhem.de/commandref.html#devspec\">device specifications (devspec) ",
  "2" => "With the set attribute <b>averageCalcForm = avgDailyMeanGWS</b> the average evaluation is calculated according to the specifications of the ".
         "German weather service.<br> Since the 01.04.2001 the standard was determined as follows: <br>".
         "<ul>".
         "  <li> Calcuation of the daily average from 24 hour values </li> ".
         "  <li>If more than 3 hourly values are missing -> calculation from the 4 main dates (00, 06, 12, 18 UTC) </li> ".
         "  <li>reference time for a day usually 23:51 UTC of the previous day until 23:50 UTC </li> ".
         "</ul>".
         "If the requirements are not met, the message <b>insufficient values</b> appears in the evaluation. <br>".
         "See also the information on <a href='https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html'>regulations</a> of the German weather service for the calculation of average temperatures. ",
  "1" => "Some helpful <a href=\"https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#Praxisbeispiele_.2F_Hinweise_und_L.C3.B6sungsans.C3.A4tze_f.C3.BCr_verschiedene_Aufgaben\">FHEM-Wiki</a> Entries."
);

# Hint Hash de
my %DbRep_vHintsExt_de = (
  "6" => "An einigen Stellen in DbRep können SQL Wildcard-Zeichen verwendet werden. Es wird explizit darauf hingewiesen. <br> ".
         "Ein Wildcard-Zeichen kann verwendet werden um jedes andere Zeichen in einer Zeichenfolge zu ersetzen.<br> ".
         "Die SQL-Wildcards sind <a href=\"http://www.w3bai.com/de/sql/sql_wildcards.html\">hier</a> näher beschrieben. ",
  "5" => "Die Grünlandtemperatursumme (GTS) ist eine Spezialform der Wachstumsgradtage, die in der Agrarmeteorologie verwendet wird. ".
         "Sie wird herangezogen, um in Mitteleuropa den Termin für das Einsetzen der Feldarbeit nach dem Winter zu bestimmen.<br> ".
         "Es werden ab Jahresbeginn alle positiven Tagesmittel erfasst. Im Januar wird mit dem Faktor 0,5 multipliziert, im Februar ".
         "mit dem Faktor 0,75, und ab März geht dann der „volle“ Tageswert (mal Faktor 1) in die Rechnung ein.<br> ".
         "Wird im Frühjahr die Summe von 200 überschritten, ist der nachhaltige Vegetationsbeginn erreicht. Hintergrund ist die ".
         "Stickstoffaufnahme und -verarbeitung des Bodens, welcher von dieser Temperatursumme abhängig ist. In mittleren Breiten ".
         "wird das meist im Laufe des März, an der Wende von Vorfrühling zu Mittfrühling erreicht. <br>".
         "(siehe auch <a href=\"https://de.wikipedia.org/wiki/Grünlandtemperatursumme\">Grünlandtemperatursumme in Wikipedia</a>) ",
  "4" => "Im Attribut 'valueFilter' können REGEXP zur erweiterten Feldselektion angegeben werden. Welche Felder berücksichtigt ".
         "werden, ist in der jeweiligen set-Funktion beschrieben. Für weitere Hilfe bitte die REGEXP-Dokumentation ihrer ".
         "verwendeten Datenbank konsultieren. Ein Überblick über REGEXP mit MariaDB ist zum Beispiel hier verfügbar:<br>".
         "<a href=\"https://mariadb.com/kb/en/library/regular-expressions-overview\">Regular Expressions Overview</a>. ",
  "3" => "Merkmale und Restriktionen von komplexen <a href=\"https://fhem.de/commandref_DE.html#devspec\">Geräte-Spezifikationen (devspec) ",
  "2" => "Mit dem gesetzten Attribut <b>averageCalcForm = avgDailyMeanGWS</b> wird die Durchschnittsauswertung nach den Vorgaben des ".
         "deutschen Wetterdienstes vorgenommen.<br> Seit dem 01.04.2001 wurde der Standard wie folgt festgelegt: <br>".
         "<ul>".
         "  <li>Berechnung der Tagesmittel aus 24 Stundenwerten </li> ".
         "  <li>Wenn mehr als 3 Stundenwerte fehlen -> Berechnung aus den 4 Hauptterminen (00, 06, 12, 18 UTC) </li> ".
         "  <li>Bezugszeit für einen Tag i.d.R. 23:51 UTC des Vortages bis 23:50 UTC </li> ".
         "</ul>".
         "Werden die Voraussetzungen nicht erfüllt, erscheint die Nachricht <b>insufficient values</b> in der Auswertung. <br>".
         "Siehe dazu auch die Informationen zu <a href='https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html'>Regularien</a> des deutschen Wetterdienstes zur Berechnung von Durchschnittstemperaturen. ",
  "1" => "Hilfreiche Hinweise zu DbRep im <a href=\"https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#Praxisbeispiele_.2F_Hinweise_und_L.C3.B6sungsans.C3.A4tze_f.C3.BCr_verschiedene_Aufgaben\">FHEM-Wiki</a>."
);

# Hash der Main-Grundfunktionen
# pk      = PID-Key
# timeset = einfügen Zeitgrenzen (ts,rsf,rsn) in den Übergabehash
# dobp    = executeBeforeProc auswerten
###################################################################
my %dbrep_hmainf = (
    eraseReadings      => { fn => 'DbRep_delread',       fndone => '',                        fnabort => '',                       pk => '',                  timeset => 0, dobp => 0, table => ''        },
    sumValue           => { fn => 'DbRep_sumval',        fndone => 'DbRep_sumvalDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    countEntries       => { fn => 'DbRep_count',         fndone => 'DbRep_countDone',         fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1                     },
    sqlCmd             => { fn => 'DbRep_sqlCmd',        fndone => 'DbRep_sqlCmdDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1                     },
    sqlCmdHistory      => { fn => 'DbRep_sqlCmd',        fndone => 'DbRep_sqlCmdDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1                     },
    sqlSpecial         => { fn => 'DbRep_sqlCmd',        fndone => 'DbRep_sqlCmdDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1                     },
    averageValue       => { fn => 'DbRep_averval',       fndone => 'DbRep_avervalDone',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    fetchrows          => { fn => 'DbRep_fetchrows',     fndone => 'DbRep_fetchrowsDone',     fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1                     },
    maxValue           => { fn => 'DbRep_maxval',        fndone => 'DbRep_maxvalDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    minValue           => { fn => 'DbRep_minval',        fndone => 'DbRep_minvalDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    exportToFile       => { fn => 'DbRep_expfile',       fndone => 'DbRep_expfile_Done',      fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    importFromFile     => { fn => 'DbRep_impfile',       fndone => 'DbRep_impfile_Done',      fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    tableCurrentFillup => { fn => 'DbRep_currentfillup', fndone => 'DbRep_currentfillupDone', fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'current' },
    diffValue          => { fn => 'DbRep_diffval',       fndone => 'DbRep_diffvalDone',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    delEntries         => { fn => 'DbRep_del',           fndone => 'DbRep_del_Done',          fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    syncStandby        => { fn => 'DbRep_syncStandby',   fndone => 'DbRep_syncStandbyDone',   fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    delSeqDoublets     => { fn => 'DbRep_delseqdoubl',   fndone => 'DbRep_deldoubl_Done',     fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    delDoublets        => { fn => 'DbRep_deldoublets',   fndone => 'DbRep_deldoubl_Done',     fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history' },
    reduceLog          => { fn => 'DbRep_reduceLog',     fndone => 'DbRep_reduceLogDone',     fnabort => 'DbRep_reduceLogAborted', pk => 'RUNNING_REDUCELOG', timeset => 1, dobp => 1, table => 'history' },
    tableCurrentPurge  => { fn => 'DbRep_del',           fndone => 'DbRep_del_Done',          fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 1, table => 'current' },
    dbvars             => { fn => 'DbRep_dbmeta',        fndone => 'DbRep_dbmeta_Done',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 0                     },
    dbstatus           => { fn => 'DbRep_dbmeta',        fndone => 'DbRep_dbmeta_Done',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 0                     },
    tableinfo          => { fn => 'DbRep_dbmeta',        fndone => 'DbRep_dbmeta_Done',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 0                     },
    procinfo           => { fn => 'DbRep_dbmeta',        fndone => 'DbRep_dbmeta_Done',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 0                     },
    svrinfo            => { fn => 'DbRep_dbmeta',        fndone => 'DbRep_dbmeta_Done',       fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 0                     },
    insert             => { fn => 'DbRep_insert',        fndone => 'DbRep_insertDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 1, table => 'history' },
    deviceRename       => { fn => 'DbRep_changeDevRead', fndone => 'DbRep_changeDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 1, table => 'history', renmode => 'devren'    },
    readingRename      => { fn => 'DbRep_changeDevRead', fndone => 'DbRep_changeDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 1, table => 'history', renmode => 'readren'   },
    changeValue        => { fn => 'DbRep_changeVal',     fndone => 'DbRep_changeDone',        fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 1, dobp => 1, table => 'history', renmode => 'changeval' },
    migrateCollation   => { fn => 'DbRep_migCollation',  fndone => 'DbRep_migCollation_Done', fnabort => 'DbRep_ParseAborted',     pk => 'RUNNING_PID',       timeset => 0, dobp => 1                     },
);

my %dbrep_havgfn = (                                                                   # Schemafunktionen von averageValue
  avgArithmeticMean       => { fn => \&_DbRep_avgArithmeticMean },
  avgDailyMeanGWS         => { fn => \&_DbRep_avgDailyMeanGWS   },
  avgDailyMeanGWSwithGTS  => { fn => \&_DbRep_avgDailyMeanGWS   },
  avgTimeWeightMean       => { fn => \&_DbRep_avgTimeWeightMean },
);


# Variablendefinitionen
my %dbrep_col                 = ("DEVICE"  => 64, "READING" => 64, );                  # Standard Feldbreiten falls noch nicht getInitData ausgeführt
my $dbrep_defdecplaces        = 4;                                                     # Nachkommastellen Standard
my $dbrep_dump_path_def       = $attr{global}{modpath}."/log/";                        # default Pfad für local Dumps
my $dbrep_dump_remotepath_def = "./";                                                  # default Pfad für remote Dumps
my $dbrep_fName               = $attr{global}{modpath}."/FHEM/FhemUtils/cacheDbRep";   # default Pfad/Name SQL Cache File
my $dbrep_deftonbl            = 86400;                                                 # default Timeout non-blocking Operationen
my $dbrep_deftobl             = 10;                                                    # default Timeout blocking Operationen


###################################################################################
# DbRep_Initialize
###################################################################################
sub DbRep_Initialize {
 my ($hash) = @_;
 $hash->{DefFn}        = "DbRep_Define";
 $hash->{UndefFn}      = "DbRep_Undef";
 $hash->{DeleteFn}     = "DbRep_Delete";
 $hash->{ShutdownFn}   = "DbRep_Shutdown";
 $hash->{NotifyFn}     = "DbRep_Notify";
 $hash->{SetFn}        = "DbRep_Set";
 $hash->{GetFn}        = "DbRep_Get";
 $hash->{AttrFn}       = "DbRep_Attr";
 $hash->{FW_deviceOverview} = 1;

 $hash->{AttrList} =   "aggregation:minute,hour,day,week,month,year,no ".
                       "disable:1,0 ".
                       "reading ".
                       "allowDeletion:1,0 ".
                       "autoForward:textField-long ".
                       "averageCalcForm:avgArithmeticMean,avgDailyMeanGWS,avgDailyMeanGWSwithGTS,avgTimeWeightMean ".
                       "countEntriesDetail:1,0 ".
                       "device " .
                       "dumpComment ".
                       "dumpCompress:1,0 ".
                       "dumpDirLocal ".
                       "dumpDirRemote ".
                       "dumpMemlimit ".
                       "dumpSpeed ".
                       "dumpFilesKeep:0,1,2,3,4,5,6,7,8,9,10 ".
                       "executeBeforeProc:textField-long ".
                       "executeAfterProc:textField-long ".
                       "expimpfile ".
                       "fastStart:0,1 ".
                       "fetchRoute:ascent,descent ".
                       "fetchMarkDuplicates:red,blue,brown,green,orange ".
                       "fetchValueFn:textField-long ".
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
                       "diffAccept ".
                       "limit ".
                       "numDecimalPlaces:0,1,2,3,4,5,6,7 ".
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
                       "sqlCmdHistoryLength:slider,0,1,200 ".
                       "sqlCmdVars ".
                       "sqlFormatService:https://sqlformat.org,none ".
                       "sqlResultFormat:separated,mline,sline,table,json ".
                       "sqlResultFieldSep:|,:,\/ ".
                       "timeYearPeriod ".
                       "timestamp_begin ".
                       "timestamp_end ".
                       "timeDiffToNow ".
                       "timeOlderThan ".
                       "timeout ".
                       "useAdminCredentials:1,0 ".
                       "userExitFn:textField-long ".
                       "valueFilter ".
                       $readingFnAttributes;

 my %hash = (
       Fn  => 'CommandDbReadingsVal',
       Hlp => '<name> <device:reading> <timestamp> <default>,Get the value of a device:reading combination from database.
               The value next to the timestamp is returned if found, otherwise the <default>.
               <name> = name of used DbRep device,
               <timestamp> = timestamp like YYYY-MM-DD_hh:mm:ss
               '
    );
    $cmds{dbReadingsVal} = \%hash;

 # Umbenennen von existierenden Attributen
 # $hash->{AttrRenameMap} = { "reading" => "readingFilter",
 #                            "device" => "deviceFilter",
 #                          };

 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;
}

###################################################################################
# DbRep_Define
###################################################################################
sub DbRep_Define {
  # define <name> DbRep <DbLog-Device>
  #       ($hash)  [1]        [2]
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

 return "Error: Perl module ".$DbRepMMDBI." is missing. Install it on Debian with: sudo apt-get install libdbi-perl" if($DbRepMMDBI);

  my @a = split("[ \t][ \t]*", $def);

  if(!$a[2]) {
      return "You need to specify more parameters.\n". "Format: define <name> DbRep <DbLog-Device>";
  } elsif (!$defs{$a[2]}) {
      return "The specified DbLog-Device \"$a[2]\" doesn't exist.";
  }

  $hash->{LASTCMD}               = " ";
  $hash->{ROLE}                  = AttrVal($name, "role", "Client");
  $hash->{MODEL}                 = $hash->{ROLE};
  $hash->{HELPER}{DBLOGDEVICE}   = $a[2];
  $hash->{HELPER}{IDRETRIES}     = 3;                                                      # Anzahl wie oft versucht wird initiale Daten zu holen
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                   # Modul Meta.pm nicht vorhanden
  $hash->{NOTIFYDEV}             = "global,".$name;                                        # nur Events dieser Devices an DbRep_Notify weiterleiten
  my $dbconn                     = $defs{$a[2]}{dbconn};
  $hash->{DATABASE}              = (split(/;|=/, $dbconn))[1];
  $hash->{UTF8}                  = defined($defs{$a[2]}{UTF8}) ? $defs{$a[2]}{UTF8} : 0;   # wird in DbRep_getInitData aus DB abgefragt und neu gesetzt

  DbRep_setVersionInfo  ($hash);                                                           # Versionsinformationen setzen
  DbRep_initSQLcmdCache ($name);                                                           # SQL Kommando Cache initialisieren

  Log3 ($name, 4, "DbRep $name - initialized");
  ReadingsSingleUpdateValue ($hash, 'state', 'initialized', 1);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+int(rand(45)), 'DbRep_firstconnect', "$name||onBoot|", 0);

return;
}

###################################################################################
#                                     Set
###################################################################################
sub DbRep_Set {
  my ($hash, @a) = @_;
  return qq{"set <command>" needs at least an argument} if(@a < 2);

  my $name        = $a[0];
  my $opt         = $a[1];
  my $prop        = $a[2];
  my $prop1       = $a[3];

  my $dblogdevice = $hash->{HELPER}{DBLOGDEVICE};
  my $dbloghash   = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel     = $dbloghash->{MODEL};
  my $dbname      = $hash->{DATABASE};

  my $sd = "";

  my (@bkps,$dir);
  $dir = AttrVal ($name, "dumpDirLocal", $dbrep_dump_path_def);     # 'dumpDirRemote' (Backup-Verz. auf dem MySQL-Server) muß gemountet sein und in 'dumpDirLocal' eingetragen sein
  $dir = $dir."/" unless($dir =~ m/\/$/);

  opendir(DIR,$dir);

  if ($dbmodel =~ /MYSQL/) {
      $dbname = $hash->{DATABASE};
      $sd     = $dbname."_.*?(csv|sql)";
  }
  elsif ($dbmodel =~ /SQLITE/) {
      $dbname = $hash->{DATABASE};
      $dbname = (split /[\/]/, $dbname)[-1];
      $dbname = (split /\./, $dbname)[0];
      $sd = $dbname."_.*?.sqlitebkp";
  }

  while (my $file = readdir(DIR)) {
      next unless (-f "$dir/$file");
      next unless ($file =~ /^$sd/);
      push @bkps,$file;
  }
  closedir(DIR);
  my $cj = @bkps ? join(",",reverse(sort @bkps)) : " ";

  my (undef, $hl) = DbRep_listSQLcmdCache ($name);                     # Drop-Down Liste bisherige Befehle in "sqlCmd" erstellen
  
  if (AttrVal($name, "sqlCmdHistoryLength", 0)) {
      $hl .= "___purge_sqlhistory___";
      $hl .= ",___list_sqlhistory___";
      $hl .= ",___save_sqlhistory___";
      $hl .= ",___restore_sqlhistory___";
  }

  my $collation = join ',', qw ( utf8mb4_bin
                                 utf8mb4_general_ci
                                 utf8_bin
                                 utf8_general_ci
                                 latin1_bin
                                 latin1_general_ci
                                 latin1_general_cs
                               );

  my $specials = "50mostFreqLogsLast2days";
  $specials   .= ",allDevCount";
  $specials   .= ",allDevReadCount";
  $specials   .= ",50DevReadCount";
  $specials   .= ",recentReadingsOfDevice";
  $specials   .= $dbmodel eq "MYSQL" ? ",readingsDifferenceByTimeDelta" : "";

  my $indl     = "list_all";
  $indl       .= ",recreate_Search_Idx";
  $indl       .= ",drop_Search_Idx";
  $indl       .= ",recreate_Report_Idx";
  $indl       .= ",drop_Report_Idx";

  my $setlist = "Unknown argument $opt, choose one of ".
                "eraseReadings:noArg ".
                "deviceRename ".
                "index:".$indl." ".
                ($hash->{ROLE} ne "Agent" ? "delDoublets:adviceDelete,delete "         : "").
                ($hash->{ROLE} ne "Agent" ? "delEntries "                              : "").
                ($hash->{ROLE} ne "Agent" ? "changeValue "                             : "").
                ($hash->{ROLE} ne "Agent" ? "readingRename "                           : "").
                ($hash->{ROLE} ne "Agent" ? "exportToFile "                            : "").
                ($hash->{ROLE} ne "Agent" ? "importFromFile "                          : "").
                ($hash->{ROLE} ne "Agent" ? "maxValue:display,writeToDB,deleteOther "  : "").
                ($hash->{ROLE} ne "Agent" ? "minValue:display,writeToDB,deleteOther "  : "").
                ($hash->{ROLE} ne "Agent" ? "multiCmd:textField-long "                 : "").
                ($hash->{ROLE} ne "Agent" ? "fetchrows:history,current "               : "").
                ($hash->{ROLE} ne "Agent" ? "diffValue:display,writeToDB "             : "").
                ($hash->{ROLE} ne "Agent" ? "insert "                                  : "").
                ($hash->{ROLE} ne "Agent" ? "reduceLog "                               : "").
                ($hash->{ROLE} ne "Agent" ? "sqlCmd:textField-long "                   : "").
                ($hash->{ROLE} ne "Agent" ? "sqlSpecial:".$specials." "                : "").
                ($hash->{ROLE} ne "Agent" ? "syncStandby "                             : "").
                ($hash->{ROLE} ne "Agent" ? "tableCurrentFillup:noArg "                : "").
                ($hash->{ROLE} ne "Agent" ? "tableCurrentPurge:noArg "                 : "").
                ($hash->{ROLE} ne "Agent" ? "countEntries:history,current "            : "").
                ($hash->{ROLE} ne "Agent" ? "sumValue:display,writeToDB,writeToDBSingle,writeToDBInTime "                          : "").
                ($hash->{ROLE} ne "Agent" ? "averageValue:display,writeToDB,writeToDBSingle,writeToDBSingleStart,writeToDBInTime " : "").
                ($hash->{ROLE} ne "Agent" ? "delSeqDoublets:adviceRemain,adviceDelete,delete "                     : "").
                ($hash->{ROLE} ne "Agent" && $hl                             ? "sqlCmdHistory:".$hl." "            : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/             ? "adminCredentials "                 : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/             ? "dumpMySQL:clientSide,serverSide "  : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/             ? "migrateCollation:".$collation." "  : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/            ? "dumpSQLite:noArg "                 : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/            ? "repairSQLite "                     : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/             ? "optimizeTables:showInfo,execute "  : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE|POSTGRESQL/ ? "vacuum:noArg "                     : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/             ? "restoreMySQL:".$cj." "             : "").
                ($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/            ? "restoreSQLite:".$cj." "            : "")
                ;

  return if(IsDisabled($name));

  if ($opt eq 'eraseReadings') {
       DbRep_setLastCmd (@a);
       
       no strict 'refs';
       $dbrep_hmainf{$opt}{fn} ($hash);                                   # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
       use strict;
       
       return;
  }

  if ($opt eq "dumpMySQL" && $hash->{ROLE} ne "Agent") {
       DbRep_setLastCmd (@a);

       if ($prop eq "serverSide") {
           Log3 ($name, 3, "DbRep $name - ################################################################");
           Log3 ($name, 3, "DbRep $name - ###             New database serverSide dump                 ###");
           Log3 ($name, 3, "DbRep $name - ################################################################");
       }
       else {
           Log3 ($name, 3, "DbRep $name - ################################################################");
           Log3 ($name, 3, "DbRep $name - ###             New database clientSide dump                 ###");
           Log3 ($name, 3, "DbRep $name - ################################################################");
       }

       DbRep_beforeproc ($hash, "dump");
       DbRep_Main       ($hash, $opt, $prop);

       return;
  }

  if ($opt eq "dumpSQLite" && $hash->{ROLE} ne "Agent") {
       DbRep_setLastCmd (@a);

       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###                    New SQLite dump                       ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");

       DbRep_beforeproc ($hash, "dump");
       DbRep_Main       ($hash, $opt, $prop);

       return;
  }

  if ($opt eq "repairSQLite" && $hash->{ROLE} ne "Agent") {
       $prop = $prop ? $prop : 36000;

       unless ($prop =~ /^(\d+)$/) {
           return " The Value of $opt is not valid. Use only figures 0-9 without decimal places !";
       }

       DbRep_setLastCmd ($name, $opt, $prop);

       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###                New SQLite repair attempt                 ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - start repair attempt of database ".$hash->{DATABASE});

       my $dbl = $dbloghash->{NAME};                              # closetime Datenbank
       CommandSet(undef,"$dbl reopen $prop");

       DbRep_beforeproc ($hash, "repair");
       DbRep_Main       ($hash, $opt);

       return;
  }

  if ($opt =~ /restoreMySQL|restoreSQLite/ && $hash->{ROLE} ne "Agent") {
       if(!$prop) {
           return qq{The command "$opt" needs an argument.};
       }

       DbRep_setLastCmd (@a);

       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###             New database Restore/Recovery                ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");

       DbRep_beforeproc ($hash, "restore");
       DbRep_Main       ($hash, $opt, $prop);

       return;
  }

  if ($opt =~ /optimizeTables|vacuum/ && $hash->{ROLE} ne "Agent") {
       DbRep_setLastCmd (@a);

       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###          New optimize table / vacuum execution           ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");

       DbRep_beforeproc ($hash, "optimize");
       DbRep_Main       ($hash, $opt, $prop);

       return;
  }

  if ($opt =~ m/delSeqDoublets|delDoublets/ && $hash->{ROLE} ne "Agent") {
      if ($opt eq "delSeqDoublets") {
          $prop //= "adviceRemain";
      }
      elsif ($opt eq "delDoublets") {
          $prop //= "adviceDelete";
      }

      DbRep_setLastCmd ($name, $opt, $prop);

      if ($prop =~ /delete/ && !AttrVal($hash->{NAME}, "allowDeletion", 0)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }

      DbRep_Main ($hash, $opt, $prop);

      return;
  }

  if ($opt =~ m/reduceLog/ && $hash->{ROLE} ne "Agent") {
      delete $hash->{HELPER}{REDUCELOG};
      
      if ($hash->{HELPER}{$dbrep_hmainf{reduceLog}{pk}} && $hash->{HELPER}{$dbrep_hmainf{reduceLog}{pk}}{pid} !~ m/DEAD/) {
          return "reduceLog already in progress. Please wait for the current process to finish.";
      }
      else {
          delete $hash->{HELPER}{$dbrep_hmainf{reduceLog}{pk}};
          DbRep_setLastCmd (@a);

          $hash->{HELPER}{REDUCELOG} = \@a;

          Log3 ($name, 3, "DbRep $name - ################################################################");
          Log3 ($name, 3, "DbRep $name - ###                    new reduceLog run                     ###");
          Log3 ($name, 3, "DbRep $name - ################################################################");

          DbRep_Main ($hash, $opt, $prop);

          return;
      }
  }

  if ($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) {
      $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"cancelDump:noArg ":"");
  }

  if ($hash->{HELPER}{RUNNING_REPAIR}) {
      $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"cancelRepair:noArg ":"");
  }

  if ($hash->{HELPER}{RUNNING_RESTORE}) {
      $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"cancelRestore:noArg ":"");
  }

  if ($opt eq "cancelDump" && $hash->{ROLE} ne "Agent") {
      DbRep_setLastCmd (@a);
      BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT});

      Log3 ($name, 3, "DbRep $name -> running Dump has been canceled");

      ReadingsSingleUpdateValue ($hash, "state", "Dump canceled", 1);
      return;
  }

  if ($opt eq "cancelRepair" && $hash->{ROLE} ne "Agent") {
      DbRep_setLastCmd (@a);
      BlockingKill($hash->{HELPER}{RUNNING_REPAIR});

      Log3 ($name, 3, "DbRep $name -> running Repair has been canceled");

      ReadingsSingleUpdateValue ($hash, "state", "Repair canceled", 1);
      return;
  }

  if ($opt eq "cancelRestore" && $hash->{ROLE} ne "Agent") {
      DbRep_setLastCmd (@a);
      BlockingKill($hash->{HELPER}{RUNNING_RESTORE});

      Log3 ($name, 3, "DbRep $name -> running Restore has been canceled");

      ReadingsSingleUpdateValue ($hash, "state", "Restore canceled", 1);
      return;
  }

  if ($opt =~ m/tableCurrentFillup/ && $hash->{ROLE} ne "Agent") {
      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash, $opt);
      return;
  }

  if ($opt eq "migrateCollation" && $hash->{ROLE} ne "Agent") {
      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash, $opt, $prop);
      return;
  }

  if ($opt eq 'index') {
       DbRep_setLastCmd (@a);
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###                    New Index operation                   ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");

       DbRep_beforeproc ($hash, "index");
       DbRep_Main       ($hash, $opt, $prop);

       return;
  }

  if ($opt eq 'adminCredentials' && $hash->{ROLE} ne "Agent") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
      my $success = DbRep_setcredentials($hash, "adminCredentials", $prop, $prop1);

      if($success) {
          return "Username and password for database root access saved successfully";
      }
      else {
          return "Error while saving username / password - see logfile for details";
      }
  }

  if ($opt eq 'countEntries' && $hash->{ROLE} ne "Agent") {
      my $table = $prop // "history";

      DbRep_setLastCmd ($name, $opt, $table);
      DbRep_Main       ($hash, $opt, $table);

      return;
  }
  
  if ($opt eq 'fetchrows' && $hash->{ROLE} ne "Agent") {
      my $table = $prop // "history";

      DbRep_setLastCmd ($name, $opt, $table);
      DbRep_Main       ($hash, $opt, $table);

      return;
  }

  #######################################################################################################
  ##        keine Aktionen außer die über diesem Eintrag solange Reopen xxxx im DbLog-Device läuft
  #######################################################################################################
  if ($dbloghash->{HELPER}{REOPEN_RUNS} && $opt !~ /\?/) {
      my $ro = $dbloghash->{HELPER}{REOPEN_RUNS_UNTIL};

      Log3 ($name, 3, "DbRep $name - connection $dblogdevice to db $dbname is closed until $ro - $opt postponed");

      ReadingsSingleUpdateValue ($hash, "state", "connection $dblogdevice to $dbname is closed until $ro - $opt postponed", 1);
      return;
  }

  if ($opt =~ m/(max|min|sum|average|diff)Value/ && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading to analyze is not set !";
      }

      if ($prop && $prop =~ /deleteOther/ && !AttrVal($hash->{NAME}, "allowDeletion", 0)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }

      if ($prop && $prop =~ /writeToDB/) {
          if (!AttrVal($hash->{NAME}, "device", "") || AttrVal($hash->{NAME}, "device", "") =~ /[%*:=,]/ || AttrVal($hash->{NAME}, "reading", "") =~ /[,\s]/) {
              return "<html>If you want write results back to database, attributes \"device\" and \"reading\" must be set.<br>
                      In that case \"device\" mustn't be a <a href='https://fhem.de/commandref.html#devspec\'>devspec</a> and mustn't contain SQL-Wildcard (%).<br>
                      The \"reading\" to evaluate has to be a single reading and no list.</html>";
          }
      }

      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash,$opt,$prop);
  }
  elsif ($opt =~ m/delEntries|tableCurrentPurge/ && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "allowDeletion", undef)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }

      delete $hash->{HELPER}{DELENTRIES};
      DbRep_setLastCmd (@a);

      shift @a;
      shift @a;
      $hash->{HELPER}{DELENTRIES} = \@a if(@a);

      DbRep_Main ($hash,$opt);
  }
  elsif ($opt eq "deviceRename") {
      shift @a;
      shift @a;
      $prop                 = join " ", @a;                                     # Device Name kann Leerzeichen enthalten
      my ($olddev, $newdev) = split ",", $prop;

      if (!$olddev || !$newdev) {
          return qq{Both entries "old device name" and "new device name" are needed. Use "set $name deviceRename olddevname,newdevname"};
      }

      $hash->{HELPER}{OLDDEV}  = $olddev;
      $hash->{HELPER}{NEWDEV}  = $newdev;

      DbRep_setLastCmd ($name, $opt, "$olddev,$newdev");
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq "readingRename") {
      shift @a;
      shift @a;
      $prop                   = join " ", @a;                                   # Readingname kann Leerzeichen enthalten
      my ($oldread, $newread) = split ",", $prop;

      if (!$oldread || !$newread) {
          return qq{Both entries "old reading name" and "new reading name" are needed. Use "set $name readingRename oldreadingname,newreadingname"};
      }

      $hash->{HELPER}{OLDREAD} = $oldread;
      $hash->{HELPER}{NEWREAD} = $newread;

      DbRep_setLastCmd ($name, $opt, "$oldread,$newread");
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq "insert" && $hash->{ROLE} ne "Agent") {
      shift @a;
      shift @a;
      $prop = join " ", @a;

      if (!$prop) {
          return qq{Data to insert to table 'history' are needed like this pattern: 'Date,Time,Value,[Unit],[<Device>],[<Reading>]'. Parameters included in "[...]" are optional. Spaces are not allowed !};
      }

      my ($i_date, $i_time, $i_value, $i_unit, $i_device, $i_reading) = split ",", $prop;
      $i_unit    //= "";
      $i_device  //= AttrVal($name, "device",  "");                                            # Device aus Attr lesen wenn nicht im insert angegeben
      $i_reading //= AttrVal($name, "reading", "");                                            # Reading aus Attr lesen wenn nicht im insert angegeben

      if (!$i_date || !$i_time || !defined $i_value) {
          return qq{At least data for "Date", "Time" and "Value" is needed to insert. Inputformat is "YYYY-MM-DD,HH:MM:SS,<Value>,<Unit>"};
      }

      if ($i_date !~ /^(\d{4})-(\d{2})-(\d{2})$/x || $i_time !~ /^(\d{2}):(\d{2}):(\d{2})$/x) {
          return "Input for date is not valid. Use format YYYY-MM-DD,HH:MM:SS";
      }

      if (!$i_device || !$i_reading) {
          return qq{One or both of "device", "reading" are not set. It's mandatory to set both in the insert command or with the device / reading attributes};
      }

      # Attribute device & reading dürfen kein SQL-Wildcard % enthalten
      if($i_device =~ m/%/ || $i_reading =~ m/%/ ) {
          return qq{One or both of "device", "reading" containing SQL wildcard "%". Wildcards are not allowed in manual function insert !}
      }

      my $i_timestamp = $i_date." ".$i_time;
      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($i_timestamp =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

      eval { my $ts = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
      if ($@) {
          my @l = split (/at/, $@);
          return " Timestamp is out of range - $l[0]";
      }

      DbRep_setLastCmd ($name, $opt, $prop);
      DbRep_Main       ($hash, $opt, "$i_timestamp,$i_device,$i_reading,$i_value,$i_unit");
  }
  elsif ($opt eq "exportToFile" && $hash->{ROLE} ne "Agent") {
      my ($ar, $hr) = parseParams (join ' ', @a);
      my $f         = $ar->[2] // AttrVal($name, "expimpfile", "");

      if (!$f) {
          return qq{"$opt" needs a file as argument or the attribute "expimpfile" (path and filename) to be set !};
      }

      my $e = q{};
      if ($hr->{MAXLINES}) {
          $e = "MAXLINES=".$hr->{MAXLINES};
          return qq{The "MAXLINES" parameter must be a integer value !} if($e !~ /^MAXLINES=\d+$/);
      }

      $prop = $e ? $f." ".$e : $f;

      DbRep_setLastCmd ($name, $opt, $prop);
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq "importFromFile" && $hash->{ROLE} ne "Agent") {
      my ($ar, $hr) = parseParams (join ' ', @a);
      my $f         = $ar->[2] // AttrVal($name, "expimpfile", "");

      if (!$f) {
          return qq{"$opt" needs a file as an argument or the attribute "expimpfile" (path and filename) to be set !};
      }

      DbRep_setLastCmd ($name, $opt, $f);
      DbRep_Main       ($hash, $opt, $f);
  }
  elsif ($opt =~ /sqlCmd|sqlSpecial|sqlCmdHistory/) {
      return qq{"set $opt" needs at least an argument} if ( @a < 3 );

      delete $data{DbRep}{$name}{sqlcache}{temp};

      my $sqlcmd;

      if($opt eq "sqlSpecial") {
          my ($tq,$gcl);

          if($prop eq "50mostFreqLogsLast2days") {
              $sqlcmd = "select Device, reading, count(0) AS `countA` from history where TIMESTAMP > (NOW() - INTERVAL 2 DAY) group by DEVICE, READING order by countA desc, DEVICE limit 50;" if($dbmodel =~ /MYSQL/);
              $sqlcmd = "select Device, reading, count(0) AS `countA` from history where TIMESTAMP > datetime('now' ,'-2 days') group by DEVICE, READING order by countA desc, DEVICE limit 50;"       if($dbmodel =~ /SQLITE/);
              $sqlcmd = "select Device, reading, count(0) AS countA from history where TIMESTAMP > (NOW() - INTERVAL '2' DAY) group by DEVICE, READING order by countA desc, DEVICE limit 50;" if($dbmodel =~ /POSTGRESQL/);
          }
          elsif ($prop eq "allDevReadCount") {
              $sqlcmd = "select device, reading, count(*) as count from history group by DEVICE, READING order by count desc;";
          }
          elsif ($prop eq "50DevReadCount") {
              $sqlcmd = "select DEVICE AS device, READING AS reading, count(0) AS number from history group by DEVICE, READING order by number DESC limit 50;";
          }
          elsif ($prop eq "allDevCount") {
              $sqlcmd = "select device, count(*) from history group by DEVICE;";
          }
          elsif ($prop eq "recentReadingsOfDevice") {
              if($dbmodel =~ /MYSQL/)      {$tq = "NOW() - INTERVAL 1 DAY"; $gcl = "READING"};
              if($dbmodel =~ /SQLITE/)     {$tq = "datetime('now','-1 day')"; $gcl = "READING"};
              if($dbmodel =~ /POSTGRESQL/) {$tq = "CURRENT_TIMESTAMP - INTERVAL '1 day'"; $gcl = "READING,DEVICE"};

              $sqlcmd = "SELECT t1.TIMESTAMP,t1.DEVICE,t1.READING,t1.VALUE
                         FROM history t1
                         INNER JOIN
                         (select max(TIMESTAMP) AS TIMESTAMP,DEVICE,READING
                            from history where §device§ AND TIMESTAMP > ".$tq." group by ".$gcl.") x
                         ON x.TIMESTAMP = t1.TIMESTAMP AND
                            x.DEVICE    = t1.DEVICE    AND
                            x.READING   = t1.READING;";
          }
          elsif ($prop eq "readingsDifferenceByTimeDelta") {
              $sqlcmd = 'SET @diff=0;
                         SET @delta=NULL;
                         SELECT t1.TIMESTAMP,t1.READING,t1.VALUE,t1.DIFF,t1.TIME_DELTA
                         FROM (SELECT TIMESTAMP,READING,VALUE,
                                cast((VALUE-@diff) AS DECIMAL(12,4))   AS DIFF,
                                @diff:=VALUE                           AS curr_V,
                                TIMESTAMPDIFF(MINUTE,@delta,TIMESTAMP) AS TIME_DELTA,
                                @delta:=TIMESTAMP                      AS curr_T
                                  FROM  history
                              WHERE §device§  AND
                                    §reading§ AND
                                    TIMESTAMP >= §timestamp_begin§ AND
                                    TIMESTAMP <= §timestamp_end§
                                    ORDER BY TIMESTAMP
                              ) t1;';
          }
      }

      if($opt eq "sqlCmd") {
          my @cmd = @a;
          shift @cmd;
          shift @cmd;

          $sqlcmd = join ' ', @cmd;

          if ($sqlcmd =~ /^ckey:/ix) {
              my $key = (split ":", $sqlcmd)[1];

              if (exists $data{DbRep}{$name}{sqlcache}{cmd}{$key}) {
                  $sqlcmd = $data{DbRep}{$name}{sqlcache}{cmd}{$key};
              }
              else {
                  return qq{SQL statement with key "$key" doesn't exists in history};
              }
          }

          $sqlcmd .= ';' if ($sqlcmd !~ m/\;$/x);
      }

      if($opt eq "sqlCmdHistory") {
          $sqlcmd = $prop;
          $sqlcmd =~ s/§/_ESC_ECS_/g;
          $sqlcmd =~ tr/ A-Za-z0-9!"#%&'()*+,-.\/:;<=>?@[\\]^_`{|}~äöüÄÖÜß€/ /cs;
          $sqlcmd =~ s/_ESC_ECS_/§/g;
          $sqlcmd =~ s/<c>/,/g;                                                        # noch aus Kompatibilitätsgründen enthalten
          $sqlcmd =~ s/(\x20)*\xbc/,/g;                                                # Forum: https://forum.fhem.de/index.php/topic,103908.0.html

          if($sqlcmd eq "___purge_sqlhistory___") {
              DbRep_deleteSQLcmdCache ($name);
              return "SQL command historylist of $name deleted.";
          }

          if($sqlcmd eq "___list_sqlhistory___") {
              my ($cache) = DbRep_listSQLcmdCache ($name);
              return $cache;
          }

          if($sqlcmd eq "___save_sqlhistory___") {
              my $err = DbRep_writeSQLcmdCache ($hash);                                # SQL Cache File schreiben
              $err  //= "SQL history entries of $name successfully saved";
              return $err;
          }

          if($sqlcmd eq "___restore_sqlhistory___") {
              my $count = DbRep_initSQLcmdCache ($name);
              return $count ? "SQL history entries of $name restored: $count" : undef;
          }
      }

      if ($sqlcmd =~ m/^\s*delete/is && !AttrVal($name, 'allowDeletion', undef)) {
          return "Attribute 'allowDeletion = 1' is needed for command '$sqlcmd'. Use it with care !";
      }

      $sqlcmd = _DbRep_sqlFormOnline ($hash, $sqlcmd);                                # SQL Statement online formatieren

      $sqlcmd                             = DbRep_trim ($sqlcmd);
      $data{DbRep}{$name}{sqlcache}{temp} = $sqlcmd;                                  # SQL incl. Formatierung zwischenspeichern

      my @cmd = split /\s+/, $sqlcmd;
      $sqlcmd = join ' ', @cmd;

      DbRep_setLastCmd ($name, $opt, $sqlcmd);
      DbRep_Main       ($hash, $opt, $sqlcmd);
  }
  elsif ($opt =~ /changeValue/) {
      my ($ac, $hc) = parseParams(join ' ', @a);

      my $oldval = $hc->{old};
      my $newval = $hc->{new};

      if (!$oldval || !$newval) {
          return qq{Both entries old="old string" new="new string" are needed.};
      }

      my $complex = 0;

      if($newval =~ m/^\s*\{"(.*)"\}\s*$/s) {
          $newval  = $1;
          $complex = 1;
      }

      $hash->{HELPER}{COMPLEX} = $complex;
      $hash->{HELPER}{OLDVAL}  = $oldval;
      $hash->{HELPER}{NEWVAL}  = $newval;

      DbRep_setLastCmd ($name, $opt, "old=$oldval new=$newval");
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt =~ m/syncStandby/ && $hash->{ROLE} ne "Agent") {
      unless($prop) {
          return qq{A DbLog-device (standby) is needed to sync. Use "set $name syncStandby <DbLog-standby name>"};
      }

      if(!exists($defs{$prop}) || $defs{$prop}->{TYPE} ne "DbLog") {
          return qq{The device "$prop" doesn't exist or is not a DbLog-device.};
      }

      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq 'multiCmd' && $hash->{ROLE} ne "Agent") {
      my @cmd = @a;
      shift @cmd;
      shift @cmd;

      my $ok  = 0;
      my $arg = join " ", @cmd;
      my $err = perlSyntaxCheck ($arg);
      return $err if($err);

      if ($arg =~ m/^\{.*\}$/xs && $arg =~ m/=>/xs) {                                # ist als Hash geschrieben
          my $av = eval $arg;

          if (ref $av eq "HASH") {
              $arg = $av;
              $ok  = 1;
          }
      }

      return "The syntax of 'multiCmd' is wrong. See command reference." if(!$ok);

      delete $data{DbRep}{$name}{multicmd};                                          # evtl. alten multiCmd löschen
      $data{DbRep}{$name}{multicmd} = $arg;

      DbRep_setLastCmd   ($name, $opt);
      DbRep_nextMultiCmd ($name);                                                    # Multikommandokette starten
  }
  else {
      return "$setlist";
  }

return;
}

###################################################################################
#                SQL Statement online formatieren
###################################################################################
sub _DbRep_sqlFormOnline {
  my $hash   = shift;
  my $sqlcmd = shift;

  my $name   = $hash->{NAME};
  my $fs     = AttrVal ($name, 'sqlFormatService', 'none');

  return $sqlcmd if($fs eq 'none');

  if ($fs eq 'https://sqlformat.org') {
      $fs .= '/api/v1/format';
  }

  my @cmds   = split ';', $sqlcmd;

  my $newcmd;

  for my $part (@cmds) {
      $part           = urlEncode ($part);
      my ($err, $dat) = HttpUtils_BlockingGet ({ url         => $fs,
                                                 timeout     => 5,
                                                 data        => "reindent=1&sql=$part",
                                                 method      => 'POST',
                                                 sslargs     => { SSL_verify_mode => 0 },
                                                 httpversion => '1.1',
                                                 loglevel    => 4
                                               }
                                              );

      if ($err) {
          Log3 ($name, 3, "DbRep $name - ERROR format SQL online: ".$err);
          return $sqlcmd;
      }
      else {
          my ($success, $decoded) = evalDecodeJSON ($hash, urlDecode ($dat));

          my $res = $decoded->{result};
          next if(!$res);

          if ($success) {
              $newcmd .= Encode::encode_utf8 ($res).';';

          }
          else {
              Log3 ($name, 3, "DbRep $name - ERROR decode JSON from SQL online formatter");
              return $sqlcmd;
          }
      }
  }

  Log3 ($name, 4, "DbRep $name - SQL online formatted: ".$newcmd);

return $newcmd;
}

###################################################################################
#                                  Get
###################################################################################
sub DbRep_Get {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name        = $a[0];
  my $opt         = $a[1];
  my $prop        = $a[2];
  my $dbh         = $hash->{DBH};
  my $dblogdevice = $hash->{HELPER}{DBLOGDEVICE};
  my $dbloghash   = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel     = $dbloghash->{MODEL};
  my $dbname      = $hash->{DATABASE};
  my $to          = AttrVal ($name, 'timeout', $dbrep_deftonbl);

  my $getlist = "Unknown argument $opt, choose one of ".
                "svrinfo:noArg ".
                "blockinginfo:noArg ".
                "minTimestamp:noArg ".
                "initData:noArg ".
                "sqlCmdBlocking:textField-long ".
                (($dbmodel =~ /MYSQL/) ? "storedCredentials:noArg " : "").
                (($dbmodel eq "MYSQL") ? "dbstatus:noArg "          : "").
                (($dbmodel eq "MYSQL") ? "tableinfo:noArg "         : "").
                (($dbmodel eq "MYSQL") ? "procinfo:noArg "          : "").
                (($dbmodel eq "MYSQL") ? "dbvars:noArg "            : "").
                "versionNotes "
                ;

  return if(IsDisabled($name));

  if ($dbloghash->{HELPER}{REOPEN_RUNS} && $opt !~ /\?|procinfo|blockinginfo/) {
      my $ro = $dbloghash->{HELPER}{REOPEN_RUNS_UNTIL};

      Log3 ($name, 3, "DbRep $name - connection $dblogdevice to db $dbname is closed until $ro - $opt postponed");

      ReadingsSingleUpdateValue ($hash, "state", "connection $dblogdevice to $dbname is closed until $ro - $opt postponed", 1);

      return;
  }

  if ($opt =~ /dbvars|dbstatus|tableinfo|procinfo/) {
      return "Dump is running - try again later !"                                if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
      return "The operation \"$opt\" isn't available with database type $dbmodel" if($dbmodel ne 'MYSQL');

      DbRep_delread    ($hash);                                                          # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq "svrinfo") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});

      DbRep_delread    ($hash);                                                          # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      DbRep_setLastCmd (@a);
      DbRep_Main       ($hash, $opt, $prop);
  }
  elsif ($opt eq "blockinginfo") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});

      DbRep_delread    ($hash);                                                          # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      DbRep_setLastCmd          (@a);
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);
      DbRep_getblockinginfo     ($hash);
  }
  elsif ($opt eq "minTimestamp" || $opt eq "initData") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});

      $hash->{HELPER}{IDRETRIES} = 3;                                                    # Anzahl wie oft versucht wird initiale Daten zu holen

      DbRep_delread             ($hash);
      DbRep_setLastCmd          (@a);
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);

      $prop //= '';
      DbRep_firstconnect("$name|$opt|$prop");
  }
  elsif ($opt =~ /sqlCmdBlocking/) {
      return qq{get "$opt" needs at least an argument} if ( @a < 3 );

      my @cmd = @a;
      shift @cmd;
      shift @cmd;

      my $sqlcmd  = join ' ', @cmd;
      $sqlcmd     =~ tr/ A-Za-z0-9!"#$§%&'()*+,-.\/:;<=>?@[\\]^_`{|}~äöüÄÖÜß€/ /cs;
      $sqlcmd    .= ';' if ($sqlcmd !~ m/\;$/x);

      $sqlcmd                             = _DbRep_sqlFormOnline ($hash, $sqlcmd);           # SQL Statement online formatieren
      $sqlcmd                             = DbRep_trim ($sqlcmd);
      $data{DbRep}{$name}{sqlcache}{temp} = $sqlcmd;                                         # SQL incl. Formatierung zwischenspeichern

      @cmd    = split /\s+/, $sqlcmd;
      $sqlcmd = join ' ', @cmd;

      DbRep_setLastCmd ($name, $opt, $sqlcmd);

      if ($sqlcmd =~ m/^\s*delete/is && !AttrVal($name, "allowDeletion", undef)) {
          return "Attribute 'allowDeletion = 1' is needed for command '$sqlcmd'. Use it with care !";
      }

      DbRep_delread    ($hash);                                                          # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);

      return DbRep_sqlCmdBlocking($name,$sqlcmd);
  }
  elsif ($opt eq "storedCredentials") {                                            # Credentials abrufen
        my $atxt;
        my $username                            = $defs{$defs{$name}->{HELPER}{DBLOGDEVICE}}->{dbuser};
        my $dblogname                           = $defs{$defs{$name}->{HELPER}{DBLOGDEVICE}}->{NAME};
        my $password                            = $attr{"sec$dblogname"}{secret};
        my ($success,$admusername,$admpassword) = DbRep_getcredentials($hash,"adminCredentials");

        if($success) {
            $atxt = "Username: $admusername, Password: $admpassword\n";
        }
        else {
            $atxt = "Credentials of $name couldn't be read. Make sure you've set it with \"set $name adminCredentials username password\" (only valid for DbRep device type \"Client\")";
        }

        return "Stored Credentials for database default access:\n".
               "===============================================\n".
               "Username: $username, Password: $password\n".
               "\n".
               "\n".
               "Stored Credentials for database admin access:\n".
               "=============================================\n".
               $atxt.
               "\n"
               ;

    }
    elsif ($opt =~ /versionNotes/) {
      my $header  = "<b>Module release information</b><br>";
      my $header1 = "<b>Helpful hints</b><br>";
      my %hs;

      # Ausgabetabelle erstellen
      my ($ret,$val0,$val1);
      my $i = 0;

      $ret  = "<html>";

      # Hints
      if (!$prop || $prop =~ /hints/ || $prop =~ /[\d]+/) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";

          if($prop && $prop =~ /[\d]+/) {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = ( $prop => $DbRep_vHintsExt_de{$prop} );
              }
              else {
                  %hs = ( $prop => $DbRep_vHintsExt_en{$prop} );
              }
          }
          else {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = %DbRep_vHintsExt_de;
              }
              else {
                  %hs = %DbRep_vHintsExt_en;
              }
          }

          $i = 0;

          for my $key (sortTopicNum("desc",keys %hs)) {
              $val0 = $hs{$key};
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
              $ret .= "</tr>";
              $i++;

              if ($i & 1) {                                                                                # $i ist ungerade
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

      if (!$prop || $prop =~ /rel/) {                                                                     # Notes
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";
          $i = 0;

          for my $key (sortTopicNum("desc",keys %DbRep_vNotesExtern)) {
              ($val0,$val1) = split(/\s/,$DbRep_vNotesExtern{$key},2);
              $ret         .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
              $ret         .= "</tr>";
              $i++;

              if ($i & 1) {                                                                               # $i ist ungerade
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
  else {
      return "$getlist";
  }

return;
}

###################################################################################
#                                       Attr
###################################################################################
sub DbRep_Attr {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash      = $defs{$name};
  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel   = $dbloghash->{MODEL};
  my $do;

    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    # nicht erlaubte / nicht setzbare Attribute wenn role = Agent
    my @agentnoattr = qw(aggregation
                         allowDeletion
                         autoForward
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
                         useAdminCredentials
                         );

    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }

        $do     = 0 if($cmd eq "del");
        my $val = ($do == 1 ?  "disabled" : "initialized");

        ReadingsSingleUpdateValue ($hash, "state", $val, 1);

        if ($do == 1) {
            my $dbh = $hash->{DBH};
            $dbh->disconnect() if($dbh);
        }
    }

    if ($cmd eq "set" && $hash->{ROLE} eq "Agent") {
        foreach (@agentnoattr) {
           return ("Attribute $aName is not usable due to role of $name is \"$hash->{ROLE}\"  ") if ($_ eq $aName);
        }
    }

    if ($aName eq 'readingPreventFromDel' && $cmd eq 'set') {
        if ($aVal =~ / /) {
            return "Usage of $aName is wrong. Use a comma separated list of readings which are should prevent from deletion when a new selection starts.";
        }
    }

    if ($aName eq "fetchValueFn") {
        if($cmd eq "set") {
            my $VALUE = "Hello";
            if( $aVal =~ m/^\s*(\{.*\})\s*$/s ) {                            # Funktion aus Attr validieren
                $aVal = $1;
            }
            else {
                $aVal = "";
            }
            return "Your function does not match the form \"{<function>}\"" if(!$aVal);
            eval $aVal;
            return "Bad function: $@" if($@);
        }
    }

    if ($aName eq "sqlCmdHistoryLength") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if ($do == 0) {
            DbRep_deleteSQLcmdCache ($name);
        }
    }

    if ($aName eq "userExitFn") {
        if($cmd eq "set") {
            if(!$aVal) {
                return "Usage of $aName is wrong. The function has to be specified as \"<UserExitFn> [reading:value]\" ";
            }
            if ($aVal =~ m/^\s*(\{.*\})\s*$/xs) {                             # unnamed Funktion direkt in userExitFn mit {...}
                $aVal = $1;
                my ($NAME,$READING,$VALUE) = ('','','');
                eval $aVal;
                return $@ if ($@);
            }
        }
    }

    if ($aName =~ /executeAfterProc|executeBeforeProc/xs) {
        if($cmd eq "set") {
            if ($aVal =~ m/^\s*(\{.*\}|{.*|.*})\s*$/xs && $aVal !~ /{".*"}/xs) {
                $aVal = $1;

                my $fdv                   = __DbRep_fhemDefVars ();
                my ($today, $hms, $we)    = ($fdv->{today}, $fdv->{hms},   $fdv->{we});
                my ($sec, $min, $hour)    = ($fdv->{sec},   $fdv->{min},   $fdv->{hour});
                my ($mday, $month, $year) = ($fdv->{mday},  $fdv->{month}, $fdv->{year});
                my ($wday, $yday, $isdst) = ($fdv->{wday},  $fdv->{yday},  $fdv->{isdst});

                eval $aVal;
                return $@ if ($@);
            }
        }
    }

    if ($aName eq "role") {
        if($cmd eq "set") {
            if ($aVal eq "Agent") {
                foreach(devspec2array("TYPE=DbRep")) {                       # check ob bereits ein Agent für die angeschlossene Datenbank existiert -> DbRep-Device kann dann keine Agent-Rolle einnehmen
                    my $devname = $_;
                    next if($devname eq $name);
                    my $devrole = $defs{$_}{ROLE};
                    my $devdb = $defs{$_}{DATABASE};
                    if ($devrole eq "Agent" && $devdb eq $hash->{DATABASE}) { return "There is already an Agent device: $devname defined for database $hash->{DATABASE} !"; }
                }

                foreach (@agentnoattr) {                                    # nicht erlaubte Attribute löschen falls gesetzt
                    delete($attr{$name}{$_});
                }

                $attr{$name}{icon} = "security";
            }
            $do = $aVal;
        }
        else {
            $do = "Client";
        }

        $hash->{ROLE}  = $do;
        $hash->{MODEL} = $hash->{ROLE};
        delete($attr{$name}{icon}) if($do eq "Client");
    }

    if($aName eq "device") {
        my $awdev = $aVal;
        DbRep_modAssociatedWith ($hash,$cmd,$awdev);
    }

    if ($cmd eq "set") {
        if ($aName =~ /valueFilter/) {
            eval { "Hallo" =~ m/$aVal/ };
            return "Bad regexp: $@" if($@);
        }

        if ($aName eq "autoForward") {
            my $em = "Usage of $aName is wrong. The function has to be specified as ".
                     "\"{ <destination-device> => \"<source-reading (Regex)> => [=> destination-reading]\" }\". ".
                     "The specification can be made in several lines separated by comma.";
            if($aVal !~ m/^\{.*(=>)+?.*\}$/s) {return $em;}
            my $av = eval $aVal;

            if($@) {
                Log3($name, 2, "$name - Error while evaluate: ".$@);
                return $@;
            }

            if(ref($av) ne "HASH") {
                return $em;
            }
        }

        if ($aName =~ /seqDoubletsVariance/) {
            my $edge = "";
            if($aVal =~ /EDGE=/) {
                ($aVal,$edge) = split("EDGE=", $aVal);
                unless ($edge =~ /^positive$|^negative$/i) { return qq{The parameter EDGE can only be "positive" or "negative" !}; }
            }

            my ($varpos,$varneg) = split(" ", $aVal);
            $varpos              = DbRep_trim($varpos);
            $varneg              = $varpos if(!$varneg);
            $varneg              = DbRep_trim($varneg);

            unless (looks_like_number($varpos) && looks_like_number($varneg)) {
                return " The Value of $aName is not valid. Only figures are allowed (except \"EDGE\") !";
            }
        }

        if ($aName eq "timeYearPeriod") {                                                         # z.Bsp: 06-01 02-28
            unless ($aVal =~ /^(\d{2})-(\d{2})\s(\d{2})-(\d{2})$/x ) {
                return "The Value of \"$aName\" isn't valid. Set the account period as \"MM-DD MM-DD\".";
            }

            my ($mm1, $dd1, $mm2, $dd2) = ($aVal =~ /^(\d{2})-(\d{2}) (\d{2})-(\d{2})$/);
            my (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime (time);         # Istzeit Ableitung
            my ($ybp, $yep);

            $year += 1900;
            $mon++;

            my $bdval = $mm1 * 30 + int $dd1;
            my $adval = $mon * 30 + int $mday;

            if ($adval >= $bdval) {
                $ybp = $year;
                $yep = $year++;
            }
            else {
                $ybp = $year--;
                $yep = $year;
            }

            eval { my $t1 = timelocal(00, 00, 00, $dd1, $mm1-1, $ybp-1900);
                   my $t2 = timelocal(00, 00, 00, $dd2, $mm2-1, $yep-1900);
                 }
                 or do {
                     return " The Value of $aName is out of range";
                 };

            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end})   if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeDiffToNow})   if ($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeOlderThan})   if ($attr{$name}{timeOlderThan});
            return;
        }

        if ($aName eq "timestamp_begin" || $aName eq "timestamp_end") {
            my @dtas = qw(current_year_begin
                          current_year_end
                          previous_year_begin
                          previous_year_end
                          current_month_begin
                          current_month_end
                          previous_month_begin
                          previous_month_end
                          current_week_begin
                          current_week_end
                          previous_week_begin
                          previous_week_end
                          current_day_begin
                          current_day_end
                          previous_day_begin
                          previous_day_end
                          next_day_begin
                          next_day_end
                          current_hour_begin
                          current_hour_end
                          previous_hour_begin
                          previous_hour_end
                         );

            if ($aVal ~~ @dtas) {
                delete($attr{$name}{timeDiffToNow});
                delete($attr{$name}{timeOlderThan});
                delete($attr{$name}{timeYearPeriod});
                return;
            }

            $aVal = DbRep_formatpicker($aVal);
            if ($aVal !~ /^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})$/x)
                {return "The Value of $aName is not valid. Use format YYYY-MM-DD HH:MM:SS or one of:\n".
                        "current_[year|month|day|hour]_begin, current_[year|month|day|hour]_end,\n".
                        "previous_[year|month|day|hour]_begin, previous_[year|month|day|hour]_end,\n".
                        "next_day_begin, next_day_end";}

            my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($aVal =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x);

            eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };

            if ($@) {
                my @l = split (/at/, $@);
                return " The Value of $aName is out of range - $l[0]";
            }

            delete($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeOlderThan});
            delete($attr{$name}{timeYearPeriod});
        }

        if ($aName =~ /ftpTimeout|timeout/) {
            unless ($aVal =~ /^[0-9]+$/) {
                return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";
            }
        }

        if ($aName =~ /diffAccept/) {
            my ($sign, $daval) = DbRep_ExplodeDiffAcc ($aVal);

            if (!$daval) {
                return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";
            }
        }

        if ($aName eq "readingNameMap") {
            unless ($aVal =~ m/^[A-Za-z\d_\.-]+$/) {
                return " Unsupported character in $aName found. Use only A-Z a-z _ . -";
            }
        }

        if ($aName eq "timeDiffToNow") {
            unless ($aVal =~ /^[0-9]+$/ || $aVal =~ /^\s*[ydhms]:([\d]+)\s*/ && $aVal !~ /.*,.*/ ) {
                return "The Value of \"$aName\" isn't valid. Set simple seconds like \"86400\" or use form like \"y:1 d:10 h:6 m:12 s:20\". Refer to commandref !";
            }
            delete($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end});
            delete($attr{$name}{timeYearPeriod});
        }

        if ($aName eq "timeOlderThan") {
            unless ($aVal =~ /^[0-9]+$/ || $aVal =~ /^\s*[ydhms]:([\d]+)\s*/ && $aVal !~ /.*,.*/ ) {
                 return "The Value of \"$aName\" isn't valid. Set simple seconds like \"86400\" or use form like \"y:1 d:10 h:6 m:12 s:20\". Refer to commandref !";
            }
            delete($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end});
            delete($attr{$name}{timeYearPeriod});
        }

        if ($aName eq "dumpMemlimit" || $aName eq "dumpSpeed") {
            unless ($aVal =~ /^[0-9]+$/) {
                return "The Value of $aName is not valid. Use only figures 0-9 without decimal places.";
            }
            my $dml = AttrVal($name, "dumpMemlimit", 100000);
            my $ds  = AttrVal($name, "dumpSpeed",     10000);

            if($aName eq "dumpMemlimit") {
                unless($aVal >= (10 * $ds)) {
                    return "The Value of $aName has to be at least '10 x dumpSpeed' ! ";
                }
            }
            if($aName eq "dumpSpeed") {
                unless($aVal <= ($dml / 10)) {
                    return "The Value of $aName mustn't be greater than 'dumpMemlimit / 10' ! ";
                }
            }
        }

        if ($aName eq "ftpUse") {
            delete($attr{$name}{ftpUseSSL});
        }

        if ($aName eq "ftpUseSSL") {
            delete($attr{$name}{ftpUse});
        }

        if ($aName eq "useAdminCredentials" && $aVal) {
            my ($success,$admusername,$admpassword) = DbRep_getcredentials($hash,"adminCredentials");
            unless ($success) {
                return "The credentials of a database admin user couldn't be read. ".
                       "Make shure you have set them with command \"set $name adminCredentials <user> <password>\" before.";
            }
        }
    }

return;
}

###################################################################################
#                                 Eventverarbeitung
###################################################################################
sub DbRep_Notify {
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

 for my $event (@{$events}) {
     $event  = "" if(!defined($event));
     my @evl = split("[ \t][ \t]*", $event);

     if($event =~ /DELETED/) {
         my $awdev = AttrVal($own_hash->{NAME}, "device", "");
         DbRep_modAssociatedWith ($own_hash,"set",$awdev);
     }

     if ($own_hash->{ROLE} eq "Agent") {                               # wenn Rolle "Agent" Verbeitung von RENAMED Events
         next if ($event !~ /RENAMED/);

         my $strucChanged;                                             # altes in neues device in der DEF des angeschlossenen DbLog-device ändern (neues device loggen)
         my $dblog_name = $own_hash->{HELPER}{DBLOGDEVICE};            # Name des an den DbRep-Agenten angeschlossenen DbLog-Dev
         my $dblog_hash = $defs{$dblog_name};

         if ( $dblog_hash->{DEF} =~ m/( |\(|\|)$evl[1]( |\)|\||:)/ ) {
             $dblog_hash->{DEF}    =~ s/$evl[1]/$evl[2]/;
             $dblog_hash->{REGEXP} =~ s/$evl[1]/$evl[2]/;

             $strucChanged = 1;                                                         # Definitionsänderung wurde vorgenommen

             Log3 ($myName, 3, "DbRep Agent $myName - $dblog_name substituted in DEF, old: \"$evl[1]\", new: \"$evl[2]\" ");
         }

         # DEVICE innerhalb angeschlossener Datenbank umbenennen
         Log3 ($myName, 4, "DbRep Agent $myName - Evt RENAMED rec - old device: $evl[1], new device: $evl[2] -> start deviceRename in DB: $own_hash->{DATABASE} ");
         $own_hash->{HELPER}{OLDDEV}  = $evl[1];
         $own_hash->{HELPER}{NEWDEV}  = $evl[2];
         $own_hash->{HELPER}{RENMODE} = "devren";

         DbRep_Main($own_hash, "deviceRename");

         for my $repname (devspec2array("TYPE=DbRep")) {                                # die Attribute "device" in allen DbRep-Devices mit der Datenbank = DB des Agenten von alten Device in neues Device ändern
             next if($repname eq $myName);

             my $repattrdevice = $attr{$repname}{device};
             next if(!$repattrdevice);
             my $repdb         = $defs{$repname}{DATABASE};

             if ($repattrdevice eq $evl[1] && $repdb eq $own_hash->{DATABASE}) {
                 $attr{$repname}{device} = $evl[2];

                 $strucChanged = 1;                                                     # Definitionsänderung wurde vorgenommen

                 Log3 ($myName, 3, "DbRep Agent $myName - $repname attr device changed, old: \"$evl[1]\", new: \"$evl[2]\" ");
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
sub DbRep_Undef {
 my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);

 my $dbh = $hash->{DBH};
 $dbh->disconnect() if(defined($dbh));

 BlockingKill($hash->{HELPER}{RUNNING_PID}) if (exists($hash->{HELPER}{RUNNING_PID}));
 BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) if (exists($hash->{HELPER}{RUNNING_BACKUP_CLIENT}));
 BlockingKill($hash->{HELPER}{RUNNING_RESTORE}) if (exists($hash->{HELPER}{RUNNING_RESTORE}));
 BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
 BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
 BlockingKill($hash->{HELPER}{RUNNING_REPAIR}) if (exists($hash->{HELPER}{RUNNING_REPAIR}));

 DbRep_delread($hash,1);

return;
}

###################################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion
# X_Undef aufgerufen um offene Verbindungen zu schließen,
# anschließend wird die Funktion X_Delete aufgerufen.
# Funktion: Aufräumen von dauerhaften Daten, welche durch das
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind.
# Es geht hier also eher darum, alle Spuren sowohl im laufenden
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben.
###################################################################################
sub DbRep_Delete {
    my $hash = shift;
    my $arg  = shift;

    my $name = $hash->{NAME};

    # gespeicherte Credentials löschen
    my $index = $hash->{TYPE}."_".$name."_adminCredentials";
    setKeyValue($index, undef);

    # gespeichertes SQL Cache löschen
    DbRep_deleteSQLhistFromFile ($name);

return;
}

###################################################################################
# DbRep_Shutdown
###################################################################################
sub DbRep_Shutdown {
  my $hash = shift;

  my $dbh = $hash->{DBH};
  $dbh->disconnect() if(defined($dbh));

  DbRep_delread          ($hash,1);
  RemoveInternalTimer    ($hash);
  DbRep_writeSQLcmdCache ($hash);                                              # SQL Cache File schreiben

return;
}

###################################################################################
#        First Init DB Connect
#        Verbindung zur DB aufbauen und Datenbankeigenschaften ermitteln
###################################################################################
sub DbRep_firstconnect {
  my $string                  = shift;
  my ($name,$opt,$prop,$fret) = split("\\|", $string);
  my $hash                    = $defs{$name};
  my $to                      = AttrVal ($name, 'timeout', $dbrep_deftonbl);

  RemoveInternalTimer ($hash, "DbRep_firstconnect");
  return if(IsDisabled($name));

  if ($init_done == 1) {
      my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
      my $dbconn    = $dbloghash->{dbconn};
      my $dbuser    = $dbloghash->{dbuser};
      my $fadef     = $hash->{MODEL} eq "Client" ? 1 : 0;                      # fastStart default immer 1 für Clients (0 für Agenten)

      if (AttrVal($name, "fastStart", $fadef) && $prop eq "onBoot" ) {
          DbRep_setLastCmd ($name, "initial database connect stopped due to attribute 'fastStart'");

          return;
      }

      # DB Struktur aus DbLog Instanz übernehmen
      $hash->{HELPER}{DBREPCOL}{COLSET}  = $dbloghash->{HELPER}{COLSET};
      $hash->{HELPER}{DBREPCOL}{DEVICE}  = $dbloghash->{HELPER}{DEVICECOL};
      $hash->{HELPER}{DBREPCOL}{TYPE}    = $dbloghash->{HELPER}{TYPECOL};
      $hash->{HELPER}{DBREPCOL}{EVENT}   = $dbloghash->{HELPER}{EVENTCOL};
      $hash->{HELPER}{DBREPCOL}{READING} = $dbloghash->{HELPER}{READINGCOL};
      $hash->{HELPER}{DBREPCOL}{VALUE}   = $dbloghash->{HELPER}{VALUECOL};
      $hash->{HELPER}{DBREPCOL}{UNIT}    = $dbloghash->{HELPER}{UNITCOL};

      # DB Strukturelemente abrufen
      Log3 ($name, 3, "DbRep $name - Connectiontest to database $dbconn with user $dbuser") if($hash->{LASTCMD} ne "minTimestamp");

      ReadingsSingleUpdateValue ($hash, "state", "running read database properties", 1);

      my $params = {
          hash => $hash,
          name => $name,
          opt  => $opt,
          prop => $prop,
          fret => $fret,
      };

      $hash->{HELPER}{RUNNING_PID} = BlockingCall("DbRep_getInitData", $params, "DbRep_getInitDataDone", $to, "DbRep_getInitDataAborted", $hash);

      if($hash->{HELPER}{RUNNING_PID}) {
          $hash->{HELPER}{RUNNING_PID}{loglevel} = 5;                             # Forum #77057
          Log3 ($name, 5, qq{DbRep $name - start BlockingCall with PID "$hash->{HELPER}{RUNNING_PID}{pid}"});
      }
  }
  else {
      InternalTimer(time+1, "DbRep_firstconnect", "$name|$opt|$prop|$fret", 0);
  }

return;
}

####################################################################################################
#                             Datenbankeigenschaften ermitteln
####################################################################################################
sub DbRep_getInitData {
  my $paref    = shift;
  my $hash     = $paref->{hash};
  my $name     = $paref->{name};
  my $opt      = $paref->{opt};
  my $prop     = $paref->{prop};
  my $fret     = $paref->{fret} // '';

  my $database = $hash->{DATABASE};

  my $bst = [gettimeofday];                                     # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my $st = [gettimeofday];                                      # SQL-Startzeit

  # ältesten Datensatz der DB ermitteln
  ######################################
  $paref->{dbh} = $dbh;
  my $mints     = _DbRep_getInitData_mints ($paref);

  # Encoding der Datenbank und Verbindung ermitteln
  ##################################################
  my $enc  = qq{};
  my $encc = qq{};
  my (@se,@sec);

  if($dbmodel =~ /MYSQL/) {
      eval { @se = $dbh->selectrow_array("SELECT default_character_set_name FROM information_schema.SCHEMATA WHERE schema_name = '$database'") };
      $enc = $se[0] // $enc;
      eval { @sec = $dbh->selectrow_array("SHOW VARIABLES LIKE 'character_set_connection'") };
      $encc = $sec[1] // $encc;
  }
  elsif($dbmodel =~ /SQLITE/) {
      eval { @se = $dbh->selectrow_array("PRAGMA encoding;") };
      $enc = $se[0] // $enc;
  }
  elsif($dbmodel =~ /POSTGRESQL/) {
      eval { @se = $dbh->selectrow_array("SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = '$database'") };
      $enc = $se[0] // $enc;
      eval { @sec = $dbh->selectrow_array("SHOW CLIENT_ENCODING") };
      $encc = $sec[0] // $encc;
  }

  Log3 ($name, 4, "DbRep $name - Encoding of database determined: $enc");

  # Report_Idx Status ermitteln
  ##############################
  my $idxstate = '';
  my $idx      = "Report_Idx";

  my ($ava,$sqlava);

  if($dbmodel =~ /MYSQL/) {
      $sqlava = "SHOW INDEX FROM history where Key_name='$idx';";
  }
  elsif($dbmodel =~ /SQLITE/) {
      $sqlava = "SELECT name FROM sqlite_master WHERE type='index' AND name='$idx';";
  }
  elsif($dbmodel =~ /POSTGRESQL/) {
      $sqlava = "SELECT indexname FROM pg_indexes WHERE tablename='history' and indexname ='$idx';";
  }

  eval { $ava = $dbh->selectrow_array($sqlava) };
  if($@) {
      $idxstate = "state of Index $idx can't be determined !";
      Log3($name, 2, "DbRep $name - WARNING - $idxstate");
  }
  else {
      if($hash->{LASTCMD} ne "minTimestamp") {
          if($ava) {
              $idxstate = qq{Index $idx exists};
              Log3($name, 3, "DbRep $name - $idxstate. Check ok");
          }
          else {
              $idxstate = qq{Index $idx doesn't exist. Please create the index by "set $name index recreate_Report_Idx" command !};
              Log3($name, 3, "DbRep $name - WARNING - $idxstate");
          }
      }
  }

  # Userrechte ermitteln
  #######################
  $paref->{dbmodel}  = $dbmodel;
  $paref->{database} = $database;

  my $grants         = _DbRep_getInitData_grants ($paref);

  $dbh->disconnect;

  my $rt = tv_interval($st);                                  # SQL-Laufzeit ermitteln

  $enc      = encode_base64($enc,      "");
  $encc     = encode_base64($encc,     "");
  $mints    = encode_base64($mints,    "");
  $idxstate = encode_base64($idxstate, "");
  $grants   = encode_base64($grants,   "");

  my $brt = tv_interval($bst);                                # Background-Laufzeit ermitteln

  $rt   = $rt.",".$brt;

  $opt  = DbRep_trim ($opt) if($opt);

  if($prop) {
      $prop = DbRep_trim    ($prop);
      $prop = encode_base64 ($prop, "");
  }

  $err  = q{};

return "$name|$err|$mints|$rt|$opt|$prop|$fret|$idxstate|$grants|$enc|$encc";
}

####################################################################################################
#                          ältesten Datensatz der DB ermitteln
####################################################################################################
sub _DbRep_getInitData_mints {
  my $paref = shift;
  my $name  = $paref->{name};
  my $dbh   = $paref->{dbh};

  my $mintsdef  = "1970-01-01 01:00:00";
  my $mints     = qq{undefined - $mintsdef is used instead};
  eval { my $fr = $dbh->selectrow_array("SELECT min(TIMESTAMP) FROM history;");
         $mints = $fr if($fr);
       };

  Log3 ($name, 4, "DbRep $name - Oldest timestamp determined: $mints");

  $mints = $mints =~ /undefined/x ? $mintsdef : $mints;

return $mints;
}

####################################################################################################
#                          effektive Userrechte ermitteln
####################################################################################################
sub _DbRep_getInitData_grants {
  my $paref    = shift;
  my $name     = $paref->{name};
  my $dbmodel  = $paref->{dbmodel};
  my $dbh      = $paref->{dbh};
  my $database = $paref->{database};

  my $grants = q{};

  return $grants if($dbmodel eq 'SQLITE');

  my ($sth,@uniq);

  if($dbmodel eq 'MYSQL') {

      eval {$sth = $dbh->prepare("SHOW GRANTS FOR CURRENT_USER();");
            $sth->execute();
            1;
           }
           or do { Log3($name, 2, "DbRep $name - WARNING - user rights couldn't be determined: ".$@);
                   return $grants;
                 };

      my $row = q{};

      while (my @line = $sth->fetchrow_array()) {
          for my $l (@line) {
              next if($l !~ /(\s+ON \*\.\*\s+|\s+ON `$database`)/ );
              $row .= "," if($row);
              $row .= (split(" ON ",(split("GRANT ", $l, 2))[1], 2))[0];
          }
      }

      $sth->finish;

      my %seen = ();
      my @g    = split(/,(\s?)/, $row);

      for my $e (@g) {
          next if(!$e || $e =~ /^\s+$/);
          $seen{$e}++;
      }

      @uniq   = keys %seen;
      $grants = join ",", @uniq;

      Log3 ($name, 4, "DbRep $name - Grants determined: $grants");
  }

return $grants;
}

####################################################################################################
#                           Auswertungsroutine DbRep_getInitData
####################################################################################################
sub DbRep_getInitDataDone {
  my $string    = shift;
  my @a         = split "\\|", $string;
  my $name      = $a[0];
  my $err       = $a[1]  ? decode_base64($a[1]) : '';
  my $mints     = decode_base64($a[2]);
  my $bt        = $a[3];
  my $opt       = $a[4];
  my $prop      = $a[5]  ? decode_base64($a[5])  : '';
  my $fret      = $a[6]  ? \&{$a[6]} : '';
  my $idxstate  = decode_base64($a[7]);
  my $grants    = $a[8]  ? decode_base64($a[8])  : '';
  my $enc       = $a[9]  ? decode_base64($a[9])  : '';
  my $encc      = $a[10] ? decode_base64($a[10]) : '';

  my $hash      = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - getInitData finished PID "$hash->{HELPER}{RUNNING_PID}{pid}"});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      readingsBeginUpdate     ($hash);
      ReadingsBulkUpdateValue ($hash, "errortext",           $err);
      ReadingsBulkUpdateValue ($hash, "state",     "disconnected");
      readingsEndUpdate       ($hash, 1);

      Log3 ($name, 2, "DbRep $name - DB connect failed. Make sure credentials of database $hash->{DATABASE} are valid and database is reachable.");
  }
  else {
      my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
      my $dbconn    = $dbloghash->{dbconn};
      my ($rt,$brt) = split ",", $bt;

      Log3 ($name, 3, "DbRep $name - Initial data information retrieved - total time used: ".sprintf("%.4f",$brt)." seconds");

      my $state = $hash->{LASTCMD} =~ /minTimestamp|initData/x ? "done" : "connected";

      $state    = qq{invalid timestamp "$mints" found in database - please delete it} if($mints =~ /^0000-00-00.*$/);

      readingsBeginUpdate ($hash);

      if($hash->{LASTCMD} eq "minTimestamp") {
          ReadingsBulkUpdateValue ($hash, "timestamp_oldest_dataset", $mints);
      }
      else {
          ReadingsBulkUpdateValue ($hash, "dbEncoding",                    $enc);
          ReadingsBulkUpdateValue ($hash, "connectionEncoding",           $encc) if($encc);
          ReadingsBulkUpdateValue ($hash, "indexState",               $idxstate);
          ReadingsBulkUpdateValue ($hash, "timestamp_oldest_dataset",    $mints);
          ReadingsBulkUpdateValue ($hash, "userRights",                 $grants) if($grants);
      }

      ReadingsBulkUpdateTimeState ($hash,$brt,$rt,$state);
      readingsEndUpdate           ($hash, 1);

      Log3 ($name, 3, "DbRep $name - Connectiontest to db $dbconn successful") if($hash->{LASTCMD} !~ /minTimestamp|initData/x);

      $hash->{HELPER}{MINTS}  = $mints;
      $hash->{HELPER}{GRANTS} = $grants if($grants);
      $hash->{UTF8}           = $enc =~ /utf-?8/xi ? 1 : 0;
  }

return if(!$fret);
return &$fret($hash,$opt,$prop);
}

####################################################################################################
#                                 Abbruchroutine DbRep_getInitData
####################################################################################################
sub DbRep_getInitDataAborted {
  my $hash  = shift;
  my $cause = shift // "Timeout: process terminated";
  my $name  = $hash->{NAME};

  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");

  delete($hash->{HELPER}{RUNNING_PID});

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "errortext", $cause);
  ReadingsBulkUpdateValue ($hash, "state", "disconnected");
  readingsEndUpdate       ($hash, 1);

return;
}

################################################################################################################
#                                              Hauptroutine
################################################################################################################
sub DbRep_Main {
 my $hash      = shift;
 my $opt       = shift;
 my $prop      = shift // q{};
 my $name      = $hash->{NAME};
 my $to        = AttrVal ($name, 'timeout', $dbrep_deftonbl);
 my $reading   = AttrVal ($name, 'reading',             '%');
 my $device    = AttrVal ($name, 'device',              '%');
 my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
 my $dbmodel   = $dbloghash->{MODEL};

 my $params;
 
 my $rdltag = delete $hash->{HELPER}{REDUCELOG};
 my $deetag = delete $hash->{HELPER}{DELENTRIES};

 # Entkommentieren für Testroutine im Vordergrund
 # DbRep_testexit($hash);

 if (($hash->{HELPER}{RUNNING_BACKUP_CLIENT}   ||
      $hash->{HELPER}{RUNNING_BCKPREST_SERVER} ||
      $hash->{HELPER}{RUNNING_RESTORE}         ||
      $hash->{HELPER}{RUNNING_REPAIR}          ||
      $hash->{HELPER}{RUNNING_REDUCELOG}       ||
      $hash->{HELPER}{RUNNING_OPTIMIZE})       &&
      $opt !~ /dumpMySQL|restoreMySQL|dumpSQLite|restoreSQLite|optimizeTables|vacuum|repairSQLite/ ) {
     return;
 }

 DbRep_delread($hash);                                      # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen

 if ($opt =~ /dumpMySQL|dumpSQLite/) {
     BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT})   if (exists($hash->{HELPER}{RUNNING_BACKUP_CLIENT}));
     BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE})        if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));

     $params = {
         hash    => $hash,
         name    => $name,
         table   => "history"
     };

     if ($dbmodel =~ /MYSQL/) {
         if ($prop eq "serverSide") {
             $hash->{HELPER}{RUNNING_BCKPREST_SERVER}           = BlockingCall("DbRep_mysql_DumpServerSide", $params, "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
             $hash->{HELPER}{RUNNING_BCKPREST_SERVER}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_BCKPREST_SERVER});
             ReadingsSingleUpdateValue ($hash, 'state', 'serverSide Dump is running - be patient and see Logfile!', 1);
         }
         else {
             $hash->{HELPER}{RUNNING_BACKUP_CLIENT}           = BlockingCall("DbRep_mysql_DumpClientSide", $params, "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
             $hash->{HELPER}{RUNNING_BACKUP_CLIENT}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_BACKUP_CLIENT});
             ReadingsSingleUpdateValue ($hash, 'state', 'clientSide Dump is running - be patient and see Logfile!', 1);
         }
     }

     if ($dbmodel =~ /SQLITE/) {
         $hash->{HELPER}{RUNNING_BACKUP_CLIENT}           = BlockingCall("DbRep_sqlite_Dump", $params, "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
         $hash->{HELPER}{RUNNING_BACKUP_CLIENT}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_BACKUP_CLIENT});
         ReadingsSingleUpdateValue ($hash, 'state', 'SQLite Dump is running - be patient and see Logfile!', 1);
     }

     return;
 }

 if ($opt =~ /restoreMySQL/) {
     BlockingKill($hash->{HELPER}{RUNNING_RESTORE})  if (exists($hash->{HELPER}{RUNNING_RESTORE}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));

     $params = {
         hash => $hash,
         name => $name,
         prop => $prop
     };

     if ($prop =~ /csv/) {
         $hash->{HELPER}{RUNNING_RESTORE} = BlockingCall("DbRep_mysql_RestoreServerSide", $params, "DbRep_restoreDone", $to, "DbRep_restoreAborted", $hash);
     }
     elsif ($prop =~ /sql/) {
         $hash->{HELPER}{RUNNING_RESTORE} = BlockingCall("DbRep_mysql_RestoreClientSide", $params, "DbRep_restoreDone", $to, "DbRep_restoreAborted", $hash);
     }
     else {
         ReadingsSingleUpdateValue ($hash, 'state', qq{restore database error - unknown fileextension "$prop"}, 1);
     }

     $hash->{HELPER}{RUNNING_RESTORE}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_RESTORE});

     ReadingsSingleUpdateValue ($hash, 'state', 'restore database is running - be patient and see Logfile!', 1);

     return;
 }

 if ($opt =~ /restoreSQLite/) {
     BlockingKill($hash->{HELPER}{RUNNING_RESTORE})  if (exists($hash->{HELPER}{RUNNING_RESTORE}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));

     $params = {
         hash => $hash,
         name => $name,
         prop => $prop
     };

     $hash->{HELPER}{RUNNING_RESTORE}           = BlockingCall("DbRep_sqliteRestore", $params, "DbRep_restoreDone", $to, "DbRep_restoreAborted", $hash);
     $hash->{HELPER}{RUNNING_RESTORE}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_RESTORE});

     ReadingsSingleUpdateValue ($hash, 'state', 'database restore is running - be patient and see Logfile!', 1);

     return;
 }

 if ($opt =~ /optimizeTables|vacuum/) {
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     BlockingKill($hash->{HELPER}{RUNNING_RESTORE})  if (exists($hash->{HELPER}{RUNNING_RESTORE}));

     $params = {
         hash  => $hash,
         name  => $name,
         prop  => $prop
     };

     $hash->{HELPER}{RUNNING_OPTIMIZE}           = BlockingCall("DbRep_optimizeTables", $params, "DbRep_OptimizeDone", $to, "DbRep_OptimizeAborted", $hash);
     $hash->{HELPER}{RUNNING_OPTIMIZE}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_OPTIMIZE});

     ReadingsSingleUpdateValue ($hash, 'state', 'optimize tables is running - be patient and see Logfile!', 1);

     return;
 }

 if ($opt =~ /repairSQLite/) {
     BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) if (exists($hash->{HELPER}{RUNNING_BACKUP_CLIENT}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE})      if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     BlockingKill($hash->{HELPER}{RUNNING_REPAIR})        if (exists($hash->{HELPER}{RUNNING_REPAIR}));

     $params = {
         hash  => $hash,
         name  => $name
     };

     $hash->{HELPER}{RUNNING_REPAIR}           = BlockingCall("DbRep_sqliteRepair", $params, "DbRep_RepairDone", $to, "DbRep_RepairAborted", $hash);
     $hash->{HELPER}{RUNNING_REPAIR}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_REPAIR});

     ReadingsSingleUpdateValue ($hash, 'state', 'repair database is running - be patient and see Logfile!', 1);

     return;
 }

 if ($opt =~ /index/) {
     if (exists($hash->{HELPER}{RUNNING_INDEX})) {
         Log3 ($name, 3, "DbRep $name - WARNING - running process $hash->{HELPER}{RUNNING_INDEX}{pid} will be killed now to start a new index operation");
         BlockingKill($hash->{HELPER}{RUNNING_INDEX});
     }

     Log3 ($name, 3, "DbRep $name - Command: $opt $prop");

     $params = {
         hash  => $hash,
         name  => $name,
         prop  => $prop
     };

     $hash->{HELPER}{RUNNING_INDEX}           = BlockingCall("DbRep_Index", $params, "DbRep_IndexDone", $to, "DbRep_IndexAborted", $hash);
     $hash->{HELPER}{RUNNING_INDEX}{loglevel} = 5 if(exists $hash->{HELPER}{RUNNING_INDEX});  # Forum #77057

     ReadingsSingleUpdateValue ($hash, 'state', 'index operation in database is running - be patient and see Logfile!', 1);

     return;
 }

 ## eventuell bereits laufenden BlockingCall beenden
 #####################################################
 if (exists($hash->{HELPER}{$dbrep_hmainf{$opt}{pk}}) && $hash->{ROLE} ne "Agent") {
     
     Log3 ($name, 3, "DbRep $name - WARNING - running process $hash->{HELPER}{$dbrep_hmainf{$opt}{pk}}{pid} will be killed now to start a new operation");
     
     BlockingKill($hash->{HELPER}{$dbrep_hmainf{$opt}{pk}});
 }

 # initiale Datenermittlung wie minimal Timestamp, Datenbankstrukturen, ...
 ############################################################################
 if (!$hash->{HELPER}{MINTS} or !$hash->{HELPER}{DBREPCOL}{COLSET}) {
     my $dbname                  = $hash->{DATABASE};
     $hash->{HELPER}{IDRETRIES}  = 3       if($hash->{HELPER}{IDRETRIES} < 0);
     $hash->{HELPER}{REDUCELOG}  = $rdltag if($rdltag);
     $hash->{HELPER}{DELENTRIES} = $deetag if($deetag);

     Log3 ($name, 3, "DbRep $name - get initial structure information of database \"$dbname\", remaining attempts: ".$hash->{HELPER}{IDRETRIES});

     $prop //= '';
     DbRep_firstconnect("$name|$opt|$prop|DbRep_Main") if($hash->{HELPER}{IDRETRIES} > 0);
     $hash->{HELPER}{IDRETRIES}--;

 return;
 }


 ##  Funktionsaufrufe
 ######################

 ReadingsSingleUpdateValue ($hash, 'state', 'running', 1);

 Log3 ($name, 4, "DbRep $name - -------- New selection --------- ");
 Log3 ($name, 4, "DbRep $name - Command: $opt $prop");

 my ($epoch_seconds_begin,$epoch_seconds_end,$runtime_string_first,$runtime_string_next);
 
 $hash->{HELPER}{REDUCELOG}  = $rdltag if($rdltag);
 $hash->{HELPER}{DELENTRIES} = $deetag if($deetag);

 if (defined $dbrep_hmainf{$opt} && defined &{$dbrep_hmainf{$opt}{fn}}) {
     $params = {
         hash    => $hash,
         name    => $name,
         opt     => $opt,
         prop    => $prop,
         table   => $dbrep_hmainf{$opt}{table} // $prop,
         device  => $device,
         reading => $reading
     };

     if ($dbrep_hmainf{$opt}{timeset}) {                                                              # zentrales Timestamp-Array und Zeitgrenzen bereitstellen
         my ($IsTimeSet, $IsAggrSet, $aggregation) = DbRep_checktimeaggr ($hash);
         my $ts                                    = "no_aggregation";                               # Dummy für eine Select-Schleife wenn != $IsTimeSet || $IsAggrSet

         if ($IsTimeSet || $IsAggrSet) {
             ($epoch_seconds_begin, $epoch_seconds_end, $runtime_string_first, $runtime_string_next, $ts) = DbRep_createTimeArray($hash, $aggregation, $opt);
         }
         else {
             Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: not set") if($opt !~ /tableCurrentPurge/);
             Log3 ($name, 4, "DbRep $name - Timestamp end human readable: not set")   if($opt !~ /tableCurrentPurge/);
         }

         Log3 ($name, 4, "DbRep $name - Aggregation: $aggregation") if($opt !~ /tableCurrentPurge|tableCurrentFillup|fetchrows|insert|reduceLog|delEntries|^sql/x);

         $params->{ts}  = $ts;
         $params->{rsf} = $runtime_string_first;
         $params->{rsn} = $runtime_string_next;
     }

     if (exists $dbrep_hmainf{$opt}{renmode}) {
         $params->{renmode} = $dbrep_hmainf{$opt}{renmode};
     }

     if ($opt eq "delEntries" || $opt =~ /reduceLog/xi) {                                                                              # Forum:#113202
         my ($valid, $cause) = DbRep_checkValidTimeSequence ($hash, $runtime_string_first, $runtime_string_next);
         
         if (!$valid) {
             Log3 ($name, 2, "DbRep $name - ERROR - $cause");
      
             delete $hash->{HELPER}{REDUCELOG};
             delete $hash->{HELPER}{DELENTRIES};
     
             return;
         }

         if ($opt =~ /reduceLog/xi) {
            ReadingsSingleUpdateValue ($hash, 'state', 'reduceLog database is running - be patient and see Logfile!', 1);
         }
     }

     if ($dbrep_hmainf{$opt}{dobp}) {                                         # Prozedur vor Command ausführen
         DbRep_beforeproc ($hash, $opt);
     }

     $hash->{HELPER}{$dbrep_hmainf{$opt}{pk}} = BlockingCall ($dbrep_hmainf{$opt}{fn},
                                                              $params,
                                                              $dbrep_hmainf{$opt}{fndone},
                                                              $to,
                                                              $dbrep_hmainf{$opt}{fnabort},
                                                              $hash
                                                             );

     delete $hash->{HELPER}{REDUCELOG};
     delete $hash->{HELPER}{DELENTRIES};

     if (exists $hash->{HELPER}{$dbrep_hmainf{$opt}{pk}}) {
         $hash->{HELPER}{$dbrep_hmainf{$opt}{pk}}{loglevel} = 5;                                             # Forum https://forum.fhem.de/index.php/topic,77057.msg689918.html#msg689918
         Log3 ($name, 5, qq{DbRep $name - BlockingCall with PID "$hash->{HELPER}{$dbrep_hmainf{$opt}{pk}}{pid}" started});
     }
 }

return;
}

################################################################################################################
#                              Create zentrales Timsstamp-Array
################################################################################################################
sub DbRep_createTimeArray {
 my $hash        = shift;
 my $aggregation = shift;
 my $opt         = shift;
 my $name        = $hash->{NAME};

 # year   als Jahre seit 1900
 # $mon   als 0..11
 # $time = timelocal( $sec, $min, $hour, $mday, $mon, $year );
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);       # Istzeit Ableitung
 my ($tsbegin,$tsend,$dim,$tsub,$tadd);
 my ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear);

 # absolute Auswertungszeiträume statische und dynamische (Beginn / Ende) berechnen
 ###################################################################################
 if($hash->{HELPER}{MINTS} && $hash->{HELPER}{MINTS} =~ m/0000-00-00/) {
     Log3 ($name, 1, "DbRep $name - ERROR - wrong timestamp \"$hash->{HELPER}{MINTS}\" found in database. Please delete it !");
     delete $hash->{HELPER}{MINTS};
 }

 my $mints = $hash->{HELPER}{MINTS} // "1970-01-01 01:00:00";  # Timestamp des 1. Datensatzes verwenden falls ermittelt
 $tsbegin  = AttrVal ($name, "timestamp_begin", $mints);
 $tsbegin  = DbRep_formatpicker($tsbegin);
 $tsend    = AttrVal ($name, "timestamp_end", strftime "%Y-%m-%d %H:%M:%S", localtime(time));
 $tsend    = DbRep_formatpicker($tsend);

 if (my $tap = AttrVal ($name, 'timeYearPeriod', undef)) {
     my ($ybp, $yep);
     my (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime (time);         # Istzeit Ableitung

     $tap    =~ qr/^(\d{2})-(\d{2}) (\d{2})-(\d{2})$/p;
     my $mbp = $1;
     my $dbp = $2;
     my $mep = $3;
     my $dep = $4;

     $year += 1900;
     $mon++;

     my $bdval = $mbp * 30 + int $dbp;
     my $adval = $mon * 30 + int $mday;

     if ($adval >= $bdval) {
         $ybp = $year;
         $yep = $year + 1;
     }
     else {
         $ybp = $year - 1;
         $yep = $year;
     }

     $tsbegin = "$ybp-$mbp-$dbp 00:00:00";
     $tsend   = "$yep-$mep-$dep 23:59:59";
 }

 if (AttrVal($name,"timestamp_begin","") eq "current_year_begin" ||
          AttrVal($name,"timestamp_end","") eq "current_year_begin") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,0,$year)) if(AttrVal($name,"timestamp_begin","") eq "current_year_begin");
     $tsend   = strftime "%Y-%m-%d %T" ,localtime(timelocal(0,0,0,1,0,$year)) if(AttrVal($name,"timestamp_end","")   eq "current_year_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_year_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_year_end") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,31,11,$year)) if(AttrVal($name,"timestamp_begin","") eq "current_year_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,31,11,$year)) if(AttrVal($name,"timestamp_end","")   eq "current_year_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_year_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_year_begin") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,0,$year-1)) if(AttrVal($name, "timestamp_begin", "") eq "previous_year_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,0,$year-1)) if(AttrVal($name, "timestamp_end", "")   eq "previous_year_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_year_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_year_end") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,31,11,$year-1)) if(AttrVal($name, "timestamp_begin", "") eq "previous_year_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,31,11,$year-1)) if(AttrVal($name, "timestamp_end", "")   eq "previous_year_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_month_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_month_begin") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_month_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_month_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_month_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_month_end") {
     $dim     = $mon-1 ? 30+(($mon+1)*3%7<4) : 28+!($year%4||$year%400*!($year%100));
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$dim,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_month_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$dim,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_month_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_month_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_month_begin") {
     $ryear   = ($mon-1<0)?$year-1:$year;
     $rmon    = ($mon-1<0)?11:$mon-1;
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_month_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,1,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_month_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_month_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_month_end") {
     $ryear   = ($mon-1<0)?$year-1:$year;
     $rmon    = ($mon-1<0)?11:$mon-1;
     $dim     = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$dim,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_month_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$dim,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_month_end");
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
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "current_week_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "current_week_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_week_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_week_end") {
     $tadd = 518400 if($wday == 1);       # wenn Start am "Mo" dann Korrektur +6 Tage
     $tadd = 432000 if($wday == 2);       # wenn Start am "Di" dann Korrektur +5 Tage
     $tadd = 345600 if($wday == 3);       # wenn Start am "Mi" dann Korrektur +4 Tage
     $tadd = 259200 if($wday == 4);       # wenn Start am "Do" dann Korrektur +3 Tage
     $tadd = 172800 if($wday == 5);       # wenn Start am "Fr" dann Korrektur +2 Tage
     $tadd = 86400  if($wday == 6);       # wenn Start am "Sa" dann Korrektur +1 Tage
     $tadd = 0 if($wday == 0);            # wenn Start am "So" keine Korrektur

     ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time+$tadd);
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "current_week_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "current_week_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_week_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_week_begin") {
     $tsub = 604800  if($wday == 1);      # wenn Start am "Mo" dann Korrektur -7 Tage
     $tsub = 691200  if($wday == 2);      # wenn Start am "Di" dann Korrektur -8 Tage
     $tsub = 777600  if($wday == 3);      # wenn Start am "Mi" dann Korrektur -9 Tage
     $tsub = 864000  if($wday == 4);      # wenn Start am "Do" dann Korrektur -10 Tage
     $tsub = 950400  if($wday == 5);      # wenn Start am "Fr" dann Korrektur -11 Tage
     $tsub = 1036800 if($wday == 6);      # wenn Start am "Sa" dann Korrektur -12 Tage
     $tsub = 1123200 if($wday == 0);      # wenn Start am "So" dann Korrektur -13 Tage

     ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time-$tsub);
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_week_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_week_begin");
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
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_week_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_week_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_day_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_day_begin") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_day_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_day_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_day_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_day_end") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_day_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_day_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "next_day_begin" ||
          AttrVal($name, "timestamp_end", "") eq "next_day_begin") {
     ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time+86400);                    # Istzeit + 1 Tag
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "next_day_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "next_day_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "next_day_end" ||
          AttrVal($name, "timestamp_end", "") eq "next_day_end") {
     ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time+86400);                    # Istzeit + 1 Tag
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "next_day_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "next_day_end");
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
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_day_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_day_begin");
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
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_day_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_day_end");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_hour_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_hour_begin") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_hour_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_hour_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "current_hour_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_hour_end") {
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_hour_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "")   eq "current_hour_end");
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
     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_hour_begin");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(0,0,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_hour_begin");
 }

 if (AttrVal($name, "timestamp_begin", "") eq "previous_hour_end" || AttrVal($name, "timestamp_end", "") eq "previous_hour_end") {
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

     $tsbegin = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_hour_end");
     $tsend   = strftime "%Y-%m-%d %T", localtime(timelocal(59,59,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "")   eq "previous_hour_end");
 }

 my ($yyyy1, $mm1, $dd1, $hh1, $min1, $sec1) = $tsbegin =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x;      # extrahieren der Einzelwerte von Datum/Zeit Beginn
 my ($yyyy2, $mm2, $dd2, $hh2, $min2, $sec2) = $tsend   =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x;      # extrahieren der Einzelwerte von Datum/Zeit Ende

 my ($timeolderthan,$timedifftonow,$fdopt) = DbRep_normRelTime($hash);                                   # relative Zeit normieren

 ### relative Auswertungszeit Beginn berücksichtigen, Umwandeln in Epochesekunden Beginn ###
 my $epoch_seconds_begin;
 $epoch_seconds_begin = fhemTimeLocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900) if($tsbegin);
 if($timedifftonow) {
     $epoch_seconds_begin = time() - $timedifftonow;
     Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp begin: $timedifftonow sec");
 }
 elsif ($timeolderthan) {
     $mints               =~ /^(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)$/;
     $epoch_seconds_begin = fhemTimeLocal ($6, $5, $4, $3, $2-1, $1-1900);
 }

 if($fdopt) {                                                                                            # FullDay Option ist gesetzt
     my $tbs              = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin);
     $tbs                 =~ /^(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)$/;
     $epoch_seconds_begin = fhemTimeLocal(00, 00, 00, $3, $2-1, $1-1900);
 }
 my $tsbegin_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin);

 if($opt !~ /tableCurrentPurge/) {
     Log3 ($name, 5, "DbRep $name - Timestamp begin epocheseconds: $epoch_seconds_begin");
     Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: $tsbegin_string");
 }
 ###########################################################################################

 ### relative Auswertungszeit Ende berücksichtigen, Umwandeln in Epochesekunden Endezeit ###
 my $epoch_seconds_end = fhemTimeLocal($sec2, $min2, $hh2, $dd2, $mm2-1, $yyyy2-1900);

 if($timeolderthan) {
     $epoch_seconds_end = time() - $timeolderthan;
 }
 Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp end: $timeolderthan sec") if(AttrVal($name, "timeOlderThan", undef));

 if($fdopt) {                                                                                           # FullDay Option ist gesetzt
     my $tes            = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
     $tes               =~ /^(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)$/;
     $epoch_seconds_end = fhemTimeLocal(59, 59, 23, $3, $2-1, $1-1900);
 }
 my $tsend_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);

 if($opt !~ /tableCurrentPurge/) {
     Log3 ($name, 5, "DbRep $name - Timestamp end epocheseconds: $epoch_seconds_end");
     Log3 ($name, 4, "DbRep $name - Timestamp end human readable: $tsend_string");
 }
 ###########################################################################################

 #  Erstellung Wertehash für Aggregationen

 my $runtime = $epoch_seconds_begin;                                    # Schleifenlaufzeit auf Beginn der Zeitselektion setzen
 my $runtime_string;                                                    # Datum/Zeit im SQL-Format für Readingname Teilstring
 my $runtime_string_first;                                              # Datum/Zeit Auswertungsbeginn im SQL-Format für SQL-Statement
 my $runtime_string_next;                                               # Datum/Zeit + Periode (Granularität) für Auswertungsende im SQL-Format
 my $reading_runtime_string;                                            # zusammengesetzter Readingname+Aggregation für Update
 my $wdadd;

 my $tsstr   = strftime "%H:%M:%S", localtime($runtime);                # für Berechnung Tagesverschieber / Stundenverschieber
 my $testr   = strftime "%H:%M:%S", localtime($epoch_seconds_end);      # für Berechnung Tagesverschieber / Stundenverschieber
 my $dsstr   = strftime "%Y-%m-%d", localtime($runtime);                # für Berechnung Tagesverschieber / Stundenverschieber
 my $destr   = strftime "%Y-%m-%d", localtime($epoch_seconds_end);      # für Berechnung Tagesverschieber / Stundenverschieber
 my $msstr   = strftime "%m",       localtime($runtime);                # Startmonat für Berechnung Monatsverschieber
 my $mestr   = strftime "%m",       localtime($epoch_seconds_end);      # Endemonat für Berechnung Monatsverschieber
 my $ysstr   = strftime "%Y",       localtime($runtime);                # Startjahr für Berechnung Monatsverschieber
 my $yestr   = strftime "%Y",       localtime($epoch_seconds_end);      # Endejahr für Berechnung Monatsverschieber

 my $wd    = strftime "%a", localtime($runtime);                        # Wochentag des aktuellen Startdatum/Zeit
 $wdadd    = 604800 if($wd eq "Mo");                                    # wenn Start am "Mo" dann nächste Grenze +7 Tage
 $wdadd    = 518400 if($wd eq "Di");                                    # wenn Start am "Di" dann nächste Grenze +6 Tage
 $wdadd    = 432000 if($wd eq "Mi");                                    # wenn Start am "Mi" dann nächste Grenze +5 Tage
 $wdadd    = 345600 if($wd eq "Do");                                    # wenn Start am "Do" dann nächste Grenze +4 Tage
 $wdadd    = 259200 if($wd eq "Fr");                                    # wenn Start am "Fr" dann nächste Grenze +3 Tage
 $wdadd    = 172800 if($wd eq "Sa");                                    # wenn Start am "Sa" dann nächste Grenze +2 Tage
 $wdadd    = 86400  if($wd eq "So");                                    # wenn Start am "So" dann nächste Grenze +1 Tage

  Log3 ($name, 5, "DbRep $name - weekday start for selection: $wd  ->  wdadd: $wdadd") if($wdadd);

  my $aggsec;
  if ($aggregation eq "minute") {
      $aggsec = 60;
  }
  elsif ($aggregation eq "hour") {
      $aggsec = 3600;
  }
  elsif ($aggregation eq "day") {
      $aggsec = 86400;
  }
  elsif ($aggregation eq "week") {
      $aggsec = 604800;
  }
  elsif ($aggregation eq "month") {
      $aggsec = 2678400;                      # Initialwert
  }
  elsif ($aggregation eq "year") {
      $aggsec = 31536000;                     # Initialwert
  }
  elsif ($aggregation eq "no") {
      $aggsec = 1;
  }
  else {
     return;
  }

  $hash->{HELPER}{CV}{tsstr}             = $tsstr;
  $hash->{HELPER}{CV}{testr}             = $testr;
  $hash->{HELPER}{CV}{dsstr}             = $dsstr;
  $hash->{HELPER}{CV}{destr}             = $destr;
  $hash->{HELPER}{CV}{msstr}             = $msstr;
  $hash->{HELPER}{CV}{mestr}             = $mestr;
  $hash->{HELPER}{CV}{ysstr}             = $ysstr;
  $hash->{HELPER}{CV}{yestr}             = $yestr;
  $hash->{HELPER}{CV}{aggsec}            = $aggsec;
  $hash->{HELPER}{CV}{aggregation}       = $aggregation;
  $hash->{HELPER}{CV}{epoch_seconds_end} = $epoch_seconds_end;
  $hash->{HELPER}{CV}{wdadd}             = $wdadd;

  my $ts;              # für Erstellung Timestamp-Array zur nonblocking SQL-Abarbeitung
  my $i = 1;           # Schleifenzähler -> nur Indikator für ersten Durchlauf -> anderer $runtime_string_first
  my $ll;              # loopindikator, wenn 1 = loopausstieg

  # Aufbau Timestampstring mit Zeitgrenzen entsprechend Aggregation
  ###################################################################
  while (!$ll) {
      # collect aggregation strings
      ($runtime,$runtime_string,$runtime_string_first,$runtime_string_next,$ll) = _DbRep_collaggstr( { hash => $hash,
                                                                                                       rtm  => $runtime,
                                                                                                       i    => $i,
                                                                                                       rsn  => $runtime_string_next
                                                                                                     }
                                                                                                   );
      $ts .= $runtime_string."#".$runtime_string_first."#".$runtime_string_next."|";
      $i++;
  }

return ($epoch_seconds_begin,$epoch_seconds_end,$runtime_string_first,$runtime_string_next,$ts);
}

####################################################################################################
#
#  Zusammenstellung Aggregationszeiträume
#  $runtime = Beginnzeit in Epochesekunden
#
####################################################################################################
sub _DbRep_collaggstr {
 my $paref               = shift;
 my $hash                = $paref->{hash};
 my $runtime             = $paref->{rtm};
 my $i                   = $paref->{i};
 my $runtime_string_next = $paref->{rsn};

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

 no warnings 'uninitialized';

 # keine Aggregation (all between timestamps)
 #############################################
 if ($aggregation eq "no") {
     $runtime_string       = "no_aggregation";                                         # für Readingname
     $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
     $ll                   = 1;
 }

 # Jahresaggregation
 #####################
 if ($aggregation eq "year") {
     $runtime_orig = $runtime;

     # Hilfsrechnungen
     my $rm = strftime "%m", localtime($runtime);                                      # Monat des aktuell laufenden Startdatums d. SQL-Select
     my $cy = strftime "%Y", localtime($runtime);                                      # Jahr des aktuell laufenden Startdatums d. SQL-Select
     my $yf = 365;
     $yf    = 366 if(DbRep_IsLeapYear($name,$cy));                                     # ist aktuelles Jahr ein Schaltjahr ?

     Log3 ($name, 5, "DbRep $name - current year:  $cy, endyear: $yestr");

     $aggsec  = $yf * 86400;
     $runtime = $runtime + 3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)

     $runtime_string = strftime "%Y", localtime($runtime);                             # für Readingname

     if ($i == 1) {                                                                    # nur im ersten Durchlauf
         $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime_orig);
     }

     if ($ysstr == $yestr || $cy ==  $yestr) {
         $runtime_string_first = strftime "%Y-01-01", localtime($runtime) if($i>1);
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         $ll                   = 1;
     }
     else {
         if ($runtime > $epoch_seconds_end) {
             $runtime_string_first = strftime "%Y-01-01", localtime($runtime);
             $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             $ll = 1;
         }
         else {
             $runtime_string_first = strftime "%Y-01-01", localtime($runtime) if($i>1);
             $runtime_string_next  = strftime "%Y-01-01", localtime($runtime + ($yf * 86400));
         }
     }

     $runtime = $runtime_orig + $aggsec;                                                # neue Beginnzeit in Epoche-Sekunden
 }

 # Monatsaggregation
 #####################
 if ($aggregation eq "month") {
     $runtime_orig = $runtime;

     # Hilfsrechnungen
     my $rm   = strftime "%m", localtime($runtime);                                    # Monat des aktuell laufenden Startdatums d. SQL-Select
     my $ry   = strftime "%Y", localtime($runtime);                                    # Jahr des aktuell laufenden Startdatums d. SQL-Select
     my $dim  = $rm-2 ? 30+($rm*3%7<4) : 28+!($ry%4||$ry%400*!($ry%100));              # Anzahl Tage des aktuell laufenden Monats

     Log3 ($name, 5, "DbRep $name - act year:  $ry, act month: $rm, days in month: $dim");

     $aggsec  = $dim     * 86400;
     $runtime = $runtime + 3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)

     $runtime_string = strftime "%Y-%m", localtime($runtime);                          # für Readingname

     if ($i == 1) {                                                                    # nur im ersten Durchlauf
         $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime_orig);
     }

     if ($ysstr == $yestr && $msstr == $mestr || $ry == $yestr && $rm == $mestr) {
         $runtime_string_first = strftime "%Y-%m-01",          localtime($runtime) if($i>1);
         $runtime_string_first = strftime "%Y-%m-01",          localtime($runtime);
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         $ll                   = 1;
     }
     else {
         if ($runtime > $epoch_seconds_end) {
             #$runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>11);  # ausgebaut 24.02.2018
             $runtime_string_first = strftime "%Y-%m-01",          localtime($runtime);
             $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             $ll                   = 1;
         }
         else {
             $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);
             $runtime_string_next  = strftime "%Y-%m-01", localtime($runtime + ($dim * 86400));
         }
     }

     #$runtime = $runtime_orig + $aggsec;      # ausgebaut 04.11.2022
     $runtime = $runtime + $aggsec;                                             # neue Beginnzeit in Epoche-Sekunden
 }

 # Wochenaggregation
 #####################
 if ($aggregation eq "week") {
     $runtime      = $runtime + 3600 if($i!=1 && DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
     $runtime_orig = $runtime;

     my $w           = strftime "%V", localtime($runtime);                      # Wochennummer des aktuellen Startdatum/Zeit
     $runtime_string = "week_".$w;                                              # für Readingname
     my $ms          = strftime "%m", localtime($runtime);                      # Startmonat (01-12)
     my $me          = strftime "%m", localtime($epoch_seconds_end);            # Endemonat (01-12)

     if ($i == 1) {                                                             # nur im ersten Schleifendurchlauf
         $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);

         # Korrektur $runtime_orig für Berechnung neue Beginnzeit für nächsten Durchlauf
         my ($yyyy1, $mm1, $dd1) = ($runtime_string_first =~ /(\d+)-(\d+)-(\d+)/);
         $runtime      = timelocal("00", "00", "00", $dd1, $mm1-1, $yyyy1-1900);
         $runtime      = $runtime + 3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);           # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
         $runtime      = $runtime + $wdadd;
         $runtime_orig = $runtime - $aggsec;

         # die Woche Beginn ist gleich der Woche vom Ende Auswertung
         if ((strftime "%V", localtime($epoch_seconds_end)) eq ($w) && ($ms+$me != 13)) {
             $runtime_string_next = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             $ll                  = 1;
         }
         else {
             $runtime_string_next = strftime "%Y-%m-%d", localtime($runtime);
         }
     }
     else {
         # weitere Durchläufe
         if(($runtime + $aggsec) > $epoch_seconds_end) {
             $runtime_string_first = strftime "%Y-%m-%d",          localtime($runtime_orig);
             $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             $ll                   = 1;
         }
         else {
             $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime_orig) ;
             $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime + $aggsec);
         }
     }

     $runtime = $runtime_orig + $aggsec;                                                             # neue Beginnzeit in Epoche-Sekunden
 }

 # Tagesaggregation
 ####################
 if ($aggregation eq "day") {
     $runtime_string       = strftime "%Y-%m-%d",          localtime($runtime);                      # für Readingname
     $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
     $runtime_string_first = strftime "%Y-%m-%d",          localtime($runtime) if($i>1);
     $runtime              = $runtime + 3600               if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)

     if ((($tsstr gt $testr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
         $runtime_string_first = strftime "%Y-%m-%d",          localtime($runtime);
         $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr);
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         $ll                   = 1;
     }
     else {
         $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime+$aggsec);
     }

     Log3 ($name, 5, "DbRep $name - runtime_string: $runtime_string, runtime_string_first: $runtime_string_first, runtime_string_next: $runtime_string_next");

     $runtime = $runtime + $aggsec;                                                                 # neue Beginnzeit in Epoche-Sekunden
 }

 # Stundenaggregation
 ######################
 if ($aggregation eq "hour") {
     $runtime_string       = strftime "%Y-%m-%d_%H",       localtime($runtime);                     # für Readingname
     $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
     $runtime              = $runtime + 3600               if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
     $runtime_string_first = strftime "%Y-%m-%d %H",       localtime($runtime) if($i>1);

     my @a     = split ":", $tsstr;
     my $hs    = $a[0];
     my $msstr = $a[1].":".$a[2];
     @a        = split ":", $testr;
     my $he    = $a[0];
     my $mestr = $a[1].":".$a[2];

     if ((($msstr gt $mestr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
         $runtime_string_first = strftime "%Y-%m-%d %H",       localtime($runtime);
         $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr && $hs eq $he);
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         $ll = 1;
     }
     else {
         $runtime_string_next  = strftime "%Y-%m-%d %H", localtime($runtime+$aggsec);
     }

     $runtime = $runtime + $aggsec;                                                               # neue Beginnzeit in Epoche-Sekunden
 }

 # Minutenaggregation
 ######################
 if ($aggregation eq "minute") {
     $runtime_string       = strftime "%Y-%m-%d_%H_%M",    localtime($runtime);                   # für Readingname
     $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
     $runtime              = $runtime + 60                 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
     $runtime_string_first = strftime "%Y-%m-%d %H:%M",    localtime($runtime) if($i>1);

     my @a     = split ":", $tsstr;
     my $ms    = $a[1];
     my $ssstr = $a[2];
     @a        = split ":", $testr;
     my $me    = $a[1];
     my $sestr = $a[2];

     if ((($ssstr gt $sestr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
         $runtime_string_first = strftime "%Y-%m-%d %H:%M",    localtime($runtime);
         # $runtime_string_first = strftime "%Y-%m-%d %H:%M", localtime($runtime) if( $dsstr eq $destr && $ms eq $me);
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         $ll = 1;
     }
     else {
         $runtime_string_next  = strftime "%Y-%m-%d %H:%M", localtime($runtime + $aggsec);
     }

     $runtime = $runtime + $aggsec;                                                              # neue Beginnzeit in Epoche-Sekunden
 }

return ($runtime,$runtime_string,$runtime_string_first,$runtime_string_next,$ll);
}

####################################################################################################
# nichtblockierende DB-Abfrage averageValue
####################################################################################################
sub DbRep_averval {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $prop    = $paref->{prop};
  my $ts      = $paref->{ts};

  my $bst     = [gettimeofday];                                                    # Background-Startzeit
  my $acf     = AttrVal ($name, 'averageCalcForm', 'avgArithmeticMean');           # Festlegung Berechnungsschema f. Mittelwert
  my $qlf     = "avg";

  my ($gts, $gtsstr) = (0, q{});                                                   # Variablen für Grünlandtemperatursumme GTS

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                         # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  my @ts                     = split "\\|", $ts;                                   # Timestampstring to Array

  $paref->{qlf}              = $qlf;
  $paref->{tsaref}           = \@ts;
  $paref->{dbmodel}          = $dbmodel;
  $paref->{IsTimeSet}        = $IsTimeSet;
  $paref->{IsAggrSet}        = $IsAggrSet;
  $paref->{dbh}              = $dbh;

  Log3 ($name, 4, "DbRep $name - averageValue calculation sceme: ".$acf);
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  my $st = [gettimeofday];                                                                           # SQL-Startzeit

  ($err, my $arrstr, my $wrstr, $qlf, $gtsstr, my $gtsreached) = &{$dbrep_havgfn{$acf}{fn}} ($paref);
  return "$name|$err" if ($err);

  $dbh->disconnect;

  my $rt = tv_interval($st);                                                                         # SQL-Laufzeit ermitteln

  my ($wrt,$irowdone);

  if($prop =~ /writeToDB/) {                                                                         # Ergebnisse in Datenbank schreiben
      ($err,$wrt,$irowdone) = DbRep_OutputWriteToDB ($name,$device,$reading,$wrstr,$qlf);
      return "$name|$err" if($err);

      $rt = $rt+$wrt;
  }

  no warnings 'uninitialized';

  $arrstr = encode_base64($arrstr, "");                                                              # Daten müssen als Einzeiler zurückgegeben werden
  $device = encode_base64($device, "");
  $gtsstr = encode_base64($gtsstr, "");

  my $brt = tv_interval($bst);                                                                       # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

return "$name|$err|$arrstr|$device|$reading|$rt|$irowdone|$gtsstr|$gtsreached";
}

####################################################################################################
#      averageValue Typ avgArithmeticMean
#      arithmetischer Mittelwert (Standard)
####################################################################################################
sub _DbRep_avgArithmeticMean {
  my $paref     = shift;

  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $table     = $paref->{table};
  my $device    = $paref->{device};
  my $reading   = $paref->{reading};
  my $qlf       = $paref->{qlf};
  my $tsaref    = $paref->{tsaref};
  my $dbmodel   = $paref->{dbmodel};
  my $dbh       = $paref->{dbh};
  my $IsTimeSet = $paref->{IsTimeSet};
  my $IsAggrSet = $paref->{IsAggrSet};

  my ($err, $sth, $sql, $arrstr, $wrstr);
  my (@rsf, @rsn);

  my $aval    = (DbRep_checktimeaggr($hash))[2];
  $qlf        = 'avgam';
  my $addon   = q{};
  my $selspec = 'AVG(VALUE)';

  if ($dbmodel eq "POSTGRESQL") {
     $selspec = 'AVG(VALUE::numeric)';
  }

  for my $row (@{$tsaref}) {
      my @ar                    = split "#", $row;
      my $runtime_string        = $ar[0];
      my $runtime_string_first  = $ar[1];
      my $runtime_string_next   = $ar[2];

      my $avg = '-';

      if ($IsTimeSet || $IsAggrSet) {
          $sql = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,$runtime_string_first,$runtime_string_next,$addon);
      }
      else {
          $sql = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,undef,undef,$addon);
      }

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
      return $err if ($err);

      my @line = $sth->fetchrow_array();
      $avg     = $line[0] if($line[0]);

      Log3 ($name, 5, "DbRep $name - SQL result: $avg ");

      if($aval eq "hour") {
          @rsf     = split /[ :]/, $runtime_string_first;
          @rsn     = split /[ :]/, $runtime_string_next;
          $arrstr .= $runtime_string."#".$avg."#".$rsf[0]."_".$rsf[1]."|";
      }
      elsif ($aval eq "minute") {
          @rsf     = split /[ :]/, $runtime_string_first;
          @rsn     = split /[ :]/, $runtime_string_next;
          $arrstr .= $runtime_string."#".$avg."#".$rsf[0]."_".$rsf[1]."-".$rsf[2]."|";
      }
      else {
          @rsf     = split " ", $runtime_string_first;
          @rsn     = split " ", $runtime_string_next;
          $arrstr .= $runtime_string."#".$avg."#".$rsf[0]."|";
      }

      next if($avg eq '-');                                                                      # Schreiben von '-' als Durchschnitt verhindern

      my @wsf  = split " ", $runtime_string_first;
      my @wsn  = split " ", $runtime_string_next;
      my $wsft = $wsf[1] ? '_'.$wsf[1] : q{};
      my $wsnt = $wsn[1] ? '_'.$wsn[1] : q{};

      $wrstr .= $runtime_string."#".$avg."#".$wsf[0].$wsft."#".$wsn[0].$wsnt."|";                # Kombi zum Rückschreiben in die DB
  }

  $sth->finish;

return ($err, $arrstr, $wrstr, $qlf);
}

####################################################################################################
#      averageValue Typ avgDailyMeanGWS
# Berechnung des Tagesmittelwertes (Temperatur) nach der Vorschrift des deutschen Wetterdienstes
#
# Berechnung der Tagesmittel aus 24 Stundenwerten, Bezugszeit für einen Tag i.d.R. 23:51 UTC des
# Vortages bis 23:50 UTC, d.h. 00:51 bis 23:50 MEZ
# Wenn mehr als 3 Stundenwerte fehlen -> Berechnung aus den 4 Hauptterminen (00, 06, 12, 18 UTC),
# d.h. 01, 07, 13, 19 MEZ
# https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html
#
####################################################################################################
sub _DbRep_avgDailyMeanGWS {
  my $paref     = shift;

  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $table     = $paref->{table};
  my $device    = $paref->{device};
  my $reading   = $paref->{reading};
  my $qlf       = $paref->{qlf};
  my $tsaref    = $paref->{tsaref};
  my $dbh       = $paref->{dbh};

  my ($err, $sth, $arrstr, $wrstr, $gtsreached);
  my (@rsf, @rsn);

  my ($gts,$gtsstr) = (0, q{});                                                    # Variablen für Grünlandtemperatursumme GTS

  my $aval    = (DbRep_checktimeaggr($hash))[2];
  my $acf     = AttrVal ($name, 'averageCalcForm', 'avgArithmeticMean');           # Festlegung Berechnungsschema f. Mittelwert
  my $addon   = "ORDER BY TIMESTAMP DESC LIMIT 1";
  my $selspec = "VALUE";
  $qlf        = "avgdmgws";

  for my $row (@{$tsaref}) {
      my @ar                    = split "#", $row;
      my $runtime_string        = $ar[0];
      my $runtime_string_first  = $ar[1];
      my $runtime_string_next   = $ar[2];

      my $sum = 0;
      my $anz = 0;                                                                 # Anzahl der Messwerte am Tag
      my ($t01,$t07,$t13,$t19);                                                    # Temperaturen der Haupttermine
      my ($bdate,undef) = split " ", $runtime_string_first;

      for my $i (0..23) {
          my $bsel = $bdate." ".sprintf("%02d",$i).":00:00";
          my $esel = ($i < 23) ? $bdate." ".sprintf("%02d",$i).":59:59" : $runtime_string_next;

          my $sql = DbRep_createSelectSql ($hash,$table,$selspec,$device,$reading,$bsel,$esel,$addon);

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
          return $err if ($err);

          my $val = $sth->fetchrow_array();

          Log3 ($name, 5, "DbRep $name - SQL result: $val") if($val);

          $val = DbRep_numval ($val);                                              # nichtnumerische Zeichen eliminieren

          if(defined $val && looks_like_number($val)) {
              $sum += $val;
              $t01 = $val if($val && $i == 00);                                    # Wert f. Stunde 01 ist zw. letzter Wert vor 01
              $t07 = $val if($val && $i == 06);
              $t13 = $val if($val && $i == 12);
              $t19 = $val if($val && $i == 18);
              $anz++;
          }
      }

      if($anz >= 21) {
          $sum = $sum/24;
      }
      elsif ($anz >= 4 && $t01 && $t07 && $t13 && $t19) {
          $sum = ($t01+$t07+$t13+$t19)/4;
      }
      else {
          $sum = qq{<html>insufficient values - execute <b>get $name versionNotes 2</b> for further information</html>};
      }

      if($aval eq "hour") {
          @rsf     = split /[ :]/, $runtime_string_first;
          @rsn     = split /[ :]/, $runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."|";
      }
      elsif ($aval eq "minute") {
          @rsf     = split /[ :]/, $runtime_string_first;
          @rsn     = split /[ :]/, $runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."-".$rsf[2]."|";
      }
      else {
          @rsf     = split " ", $runtime_string_first;
          @rsn     = split " ", $runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."|";
      }

      my @wsf = split " ", $runtime_string_first;
      my @wsn = split " ", $runtime_string_next;
      my $wsft = $wsf[1] ? '_'.$wsf[1] : q{};
      my $wsnt = $wsn[1] ? '_'.$wsn[1] : q{};

      $wrstr .= $runtime_string."#".$sum."#".$wsf[0].$wsft."#".$wsn[0].$wsnt."|";                # Kombi zum Rückschreiben in die DB

      ### Grünlandtemperatursumme lt. https://de.wikipedia.org/wiki/Gr%C3%BCnlandtemperatursumme ###
      my ($y,$m,$d) = split "-", $runtime_string;

      if ($acf eq 'avgDailyMeanGWSwithGTS' && looks_like_number($sum)) {
          $m    = DbRep_removeLeadingZero ($m);
          $d    = DbRep_removeLeadingZero ($d);
          $gts  = 0 if($m == 1 && $d == 1);

          my $f = $sum <= 0 ? 0    :
                  $m   >= 3 ? 1.00 :                                          # Faktorenberechnung lt. https://de.wikipedia.org/wiki/Gr%C3%BCnlandtemperatursumme
                  $m   == 2 ? 0.75 :
                  0.5;

          $gts += $sum*$f;

          if($gts >= 200) {
              $gtsreached = $gtsreached // $runtime_string;
          }

          $gtsstr .= $runtime_string."#".$gts."#".$rsf[0]."|";
      }
  }

  $sth->finish;

return ($err, $arrstr, $wrstr, $qlf, $gtsstr, $gtsreached);
}

####################################################################################################
#      averageValue Typ avgTimeWeightMean
#      zeitgewichteter Mittelwert
#
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
####################################################################################################
sub _DbRep_avgTimeWeightMean {
  my $paref     = shift;

  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $table     = $paref->{table};
  my $device    = $paref->{device};
  my $reading   = $paref->{reading};
  my $qlf       = $paref->{qlf};
  my $tsaref    = $paref->{tsaref};
  my $dbh       = $paref->{dbh};
  my $IsTimeSet = $paref->{IsTimeSet};
  my $IsAggrSet = $paref->{IsAggrSet};

  my ($err, $sth, $sql, $arrstr, $wrstr, $bin_end, $val1);
  my (@rsf, @rsn);

  my $aval    = (DbRep_checktimeaggr($hash))[2];
  $qlf        = 'avgtwm';
  my $selspec = 'TIMESTAMP,VALUE';
  my $addon   = 'ORDER BY TIMESTAMP ASC';
  my $addonl  = 'ORDER BY TIMESTAMP DESC LIMIT 1';

  for my $row (@{$tsaref}) {
      my @ar                    = split "#", $row;
      my $runtime_string        = $ar[0];
      my $runtime_string_first  = $ar[1];
      my $runtime_string_next   = $ar[2];

      my ($tf,$tl,$tn,$to,$dt,$val);

      if ($bin_end) {                                                     # das $bin_end des letzten Bin ist der effektive Zeitpunkt des letzten Datenwertes
          $tf = $bin_end;                                                 # der vorherigen Periode, die in die aktuelle Periode übernommen wird
      }
      else {                                                              # dies ist der erste Mittelungsplatz, und mit einem "Peek-back-in-time" wird versucht, den Wert unmittelbar vor der Startzeit zu ermitteln
          my ($year,$month,$day,$hour,$min,$sec) = $runtime_string_first =~ m/(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/xs;
          my $time                               = timelocal ($sec,$min,$hour,$day,$month-1,$year);

          if ($aval eq 'hour' || $aval eq 'minute') {
              $time -= 3600;                                              # um 1 Stunde zurückblicken
          }
          elsif ($aval eq 'day') {
              $time -= 24 * 3600;                                         # um 1 Tag zurückblicken
          }
          elsif ($aval eq 'week') {
              $time -= 7 * 24 * 3600;                                     # um 1 Woche zurückblicken
          }
          else {
              $time -= 30 * 24 * 3600;                                    # um 1 Monat zurückblicken
          };

          my $newtime_string = strftime ("%Y-%m-%d %H:%M:%S", localtime ($time));
          $sql               = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $newtime_string, $runtime_string_first, $addonl);

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
          return $err if ($err);

          my @twm_array = map { $_->[0]."_ESC_".$_->[1] } @{$sth->fetchall_arrayref()};

          for my $twmrow (@twm_array) {
              ($tn,$val1) = split "_ESC_", $twmrow;
              $val1       = DbRep_numval ($val1);                                   # nichtnumerische Zeichen eliminieren
              $bin_end    = $runtime_string_first;                                  # der letzte Wert vor dem vollständigen Zeitrahmen wird auf den Beginn des Zeitrahmens "gefälscht"
              $tf         = $runtime_string_first;
          };
      }

      my $tsum = 0;
      my $sum  = 0;

      if ($IsTimeSet || $IsAggrSet) {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
      }
      else {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, $addon);
      }

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
      return $err if ($err);

      my @twm_array = map { $_->[0]."_ESC_".$_->[1] } @{$sth->fetchall_arrayref()};

      if ($bin_end && $val1) {                                                      # der letzte Datenwert aus dem vorherigen Bin wird dem aktuellen Bin vorangestellt,
          unshift @twm_array, $bin_end.'_ESC_'.$val1;                               # wobei das vorherige $bin_end als Zeitstempel verwendet wird
      }

      # für jeden Bin wird die Endzeit aufgezeichnet, um sie für den nächsten Bin zu verwenden
      my ($yyyyf, $mmf, $ddf, $hhf, $minf, $secf) = $runtime_string_next =~ /(\d+)-*(\d+)*-*(\d+)*\s*(\d+)*:*(\d+)*:*(\d+)*/xs;
      $bin_end  = $runtime_string_next;
      $bin_end .='-01' if (!$mmf);
      $bin_end .='-01' if (!$ddf);
      $bin_end .=' 00' if (!$hhf);
      $bin_end .=':00' if (!$minf);
      $bin_end .=':00' if (!$secf);

      for my $twmrow (@twm_array) {
          ($tn,$val) = split "_ESC_", $twmrow;
          $val       = DbRep_numval ($val);                                                 # nichtnumerische Zeichen eliminieren

          my ($yyyyt1, $mmt1, $ddt1, $hht1, $mint1, $sect1) = $tn =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/xs;
          $tn                                               = timelocal ($sect1, $mint1, $hht1, $ddt1, $mmt1-1, $yyyyt1-1900);

          if(!$to) {
            $val1 = $val;
            $to   = $tn;
            next;
          }

          $dt    = $tn - $to;
          $tsum += $dt;                                                                     # Bildung der Zeitsumme für die spätere Division

          $sum  += $val1 * $dt if ($val1);                                                  # die Division durch die Gesamtzeit wird am Ende, außerhalb der Schleife durchgeführt
          $val1  = $val;
          $to    = $tn;

          Log3 ($name, 5, "DbRep $name - data element: $twmrow");
          Log3 ($name, 5, "DbRep $name - time sum: $tsum, delta time: $dt, value: $val1, twm: ".($tsum ? $val1*($dt/$tsum) : 0));
      }

      $dt    = timelocal($secf, $minf, $hhf, $ddf, $mmf-1, $yyyyf-1900);                    # die Zeitspanne des letzten Datenwertes in diesem Bin wird für diesen Bin berücksichtigt
      $dt   -= $to if ($to);                                                                # $dt ist das Zeitgewicht des letzten Wertes in diesem Bin
      $tsum += $dt;
      $sum  += $val1 * $dt if ($val1);
      $sum  /= $tsum if ($tsum > 0);
      $sum   = "insufficient values" if ($sum == 0);

      if($aval eq "hour") {
          @rsf     = split /[ :]/,$runtime_string_first;
          @rsn     = split /[ :]/,$runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."|";
      }
      elsif ($aval eq "minute") {
          @rsf     = split /[ :]/,$runtime_string_first;
          @rsn     = split /[ :]/,$runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."-".$rsf[2]."|";
      }
      else {
          @rsf     = split " ",$runtime_string_first;
          @rsn     = split " ",$runtime_string_next;
          $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."|";
      }

      $runtime_string_first =~ s/\s/_/xs;
      $runtime_string_next  =~ s/\s/_/xs;

      $wrstr .= $runtime_string."#".$sum."#".$runtime_string_first."#".$runtime_string_next."|";    # Kombi zum Rückschreiben in die DB
  }

  $sth->finish;

return ($err, $arrstr, $wrstr, $qlf);
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage averageValue
####################################################################################################
sub DbRep_avervalDone {
  my $string     = shift;
  my @a          = split "\\|", $string;
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $arrstr     = $a[2] ? decode_base64($a[2]) : '';
  my $device     = $a[3] ? decode_base64($a[3]) : '';
  my $reading    = $a[4];
  my $bt         = $a[5];
  my $irowdone   = $a[6];
  my $gtsstr     = $a[7] ? decode_base64($a[7]) : '';
  my $gtsreached = $a[8];

  my $hash       = $defs{$name};
  my $ndp        = AttrVal ($name, "numDecimalPlaces", $dbrep_defdecplaces);

  my $reading_runtime_string;

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                                # Befehl nach Procedure ausführen incl. state
      DbRep_nextMultiCmd        ($name);                                                  # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  no warnings 'uninitialized';

  my $acf = AttrVal($name, "averageCalcForm", "avgArithmeticMean");

  if($acf eq "avgArithmeticMean") {
      $acf = "AM"
  }
  elsif ($acf =~ /avgDailyMeanGWS/) {
      $acf = "DMGWS";
  }
  elsif ($acf eq "avgTimeWeightMean") {
      $acf = "TWM";
  }

  readingsBeginUpdate($hash);                                                 # Readings für Grünlandtemperatursumme

  my @agts = split("\\|", $gtsstr);

  for my $gts (@agts) {
      my @ay                = split "#", $gts;
      my $rt_string         = $ay[0];
      my $val               = $ay[1];
      my $rtf               = $ay[2]."__";

      my ($dev,$rdg)        = ("","");
      $dev                  = $device."__"  if ($device);
      $rdg                  = $reading."__" if ($reading);
      my $reading_rt_string = $rtf.$dev.$rdg."GrasslandTemperatureSum";

      ReadingsBulkUpdateValue ($hash, $reading_rt_string, sprintf("%.1f", $val));
  }

  ReadingsBulkUpdateValue ($hash, "reachedGTSthreshold", $gtsreached) if($gtsreached);

  my @arr = split "\\|", $arrstr;

  for my $row (@arr) {
      my @a                = split "#", $row;
      my $runtime_string   = $a[0];
      my $c                = $a[1];
      my $rsf              = $a[2]."__";

      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$runtime_string;
      }
      else {
          my ($ds,$rds)           = ("","");
          $ds                     = $device."__"  if ($device);
          $rds                    = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."AVG".$acf."__".$runtime_string;
      }

      if($acf eq "DMGWS") {
          ReadingsBulkUpdateValue ($hash, $reading_runtime_string, looks_like_number $c ? sprintf "%.1f",$c : $c);
      }
      else {
          ReadingsBulkUpdateValue ($hash, $reading_runtime_string, looks_like_number $c ? sprintf "%.${ndp}f", $c : "-");
      }
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage count
####################################################################################################
sub DbRep_count {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $ts      = $paref->{ts};

  my $ced     = AttrVal($name, "countEntriesDetail", 0);
  my $vf      = AttrVal($name, "valueFilter",       "");

  my ($sql,$sth);

  my $bst = [gettimeofday];                                             # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  no warnings 'uninitialized';

  # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  my ($IsTimeSet,$IsAggrSet,$aggregation) = DbRep_checktimeaggr($hash);
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  # Timestampstring to Array
  my @ts = split("\\|", $ts);
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  my $st = [gettimeofday];                                             # SQL-Startzeit

  my ($arrstr,@rsf,$ttail);
  my $addon   = '';
  my $selspec = "COUNT(*)";

  if($ced) {
      $addon   = "group by READING";
      $selspec = "READING, COUNT(*)";
  }

  for my $row (@ts) {                                                  # DB-Abfrage zeilenweise für jeden Timearray-Eintrag
      my @a                    = split("#", $row);
      my $runtime_string       = $a[0];
      my $runtime_string_first = $a[1];
      my $runtime_string_next  = $a[2];
      my $tc = 0;

      if($aggregation eq "hour") {
          @rsf   = split(/[" "\|":"]/,$runtime_string_first);
          $ttail = $rsf[0]."_".$rsf[1]."|";
      }
      else {
          @rsf   = split(" ",$runtime_string_first);
          $ttail = $rsf[0]."|";
      }

      if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
      }
      else {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, $addon);
      }

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
      return "$name|$err" if ($err);

      if($ced) {                                                                         # detaillierter Readings-Count
          while (my @line = $sth->fetchrow_array()) {
              Log3 ($name, 5, "DbRep $name - SQL result: @line");
              $tc += $line[1] if($line[1]);                                              # total count für Reading
              $arrstr .= $runtime_string."#".$line[0]."#".$line[1]."#".$ttail;
          }

          $arrstr .= $runtime_string."#"."ALLREADINGS"."#".$tc."#".$ttail;               # total count (über alle selected Readings) für Zeitabschnitt einfügen
      }
      else {
          my @line = $sth->fetchrow_array();
          Log3 ($name, 5, "DbRep $name - SQL result: $line[0]") if($line[0]);
          $arrstr .= $runtime_string."#"."ALLREADINGS"."#".$line[0]."#".$ttail;
      }
  }

  $sth->finish;
  $dbh->disconnect;

  my $rt = tv_interval($st);                                # SQL-Laufzeit ermitteln

  $arrstr = encode_base64($arrstr,"");
  $device = encode_base64($device,"");

  my $brt = tv_interval($bst);                              # Background-Laufzeit ermitteln

  $rt = $rt.",".$brt;

return "$name|$err|$arrstr|$device|$rt|$table";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage count
####################################################################################################
sub DbRep_countDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $arrstr     = $a[2] ? decode_base64($a[2]) : '';
  my $device     = $a[3] ? decode_base64($a[3]) : '';
  my $bt         = $a[4];
  my $table      = $a[5];

  my $hash       = $defs{$name};

  my $reading_runtime_string;

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                                # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                                  # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;

  Log3 ($name, 5, "DbRep $name - SQL result decoded: $arrstr") if($arrstr);

  no warnings 'uninitialized';

  readingsBeginUpdate ($hash);

  my @arr = split("\\|", $arrstr);
  for my $row (@arr) {
      my @a              = split("#", $row);
      my $runtime_string = $a[0];
      my $reading        = $a[1];
      $reading           =~ s/[^A-Za-z\/\d_\.-]/\//g;
      my $c              = $a[2];
      my $rsf            = $a[3]."__";

      if (AttrVal($name, 'readingNameMap', '')) {
          $reading_runtime_string = $rsf.AttrVal($name, 'readingNameMap', '')."__".$runtime_string;
      }
      else {
          my ($ds,$rds) = ("","");
          $ds           = $device."__"  if ($device);
          $rds          = $reading."__" if ($reading);

          if (AttrVal($name, 'countEntriesDetail', 0)) {
              $reading_runtime_string = $rsf.$rds."COUNT_".$table."__".$runtime_string;
          }
          else {
              $reading_runtime_string = $rsf."COUNT_".$table."__".$runtime_string;
          }
      }

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $c ? $c : "-");
  }

  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                           # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                             # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage maxValue
####################################################################################################
sub DbRep_maxval {
 my $paref   = shift;
 my $hash    = $paref->{hash};
 my $name    = $paref->{name};
 my $table   = $paref->{table};
 my $device  = $paref->{device};
 my $reading = $paref->{reading};
 my $prop    = $paref->{prop};
 my $ts      = $paref->{ts};

 my ($sql,$sth);

 my $bst = [gettimeofday];                                                             # Background-Startzeit

 my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
 return "$name|$err" if ($err);

 no warnings 'uninitialized';

 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                              # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

 my @ts = split("\\|", $ts);                                                           # Timestampstring to Array
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

 my $st = [gettimeofday];                                                              # SQL-Startzeit

 my @row_array;
 for my $row (@ts) {                                                                   # DB-Abfrage zeilenweise für jeden Array-Eintrag
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];

     $runtime_string = encode_base64($runtime_string,"");

     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash, $table, "VALUE,TIMESTAMP", $device, $reading, $runtime_string_first, $runtime_string_next, "ORDER BY TIMESTAMP");
     }
     else {
         $sql = DbRep_createSelectSql($hash, $table, "VALUE,TIMESTAMP", $device, $reading, undef, undef, "ORDER BY TIMESTAMP");
     }

     ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
     return "$name|$err" if ($err);

     my @array = map { $runtime_string." ".$_->[0]." ".$_->[1]."!_ESC_!".$runtime_string_first."|".$runtime_string_next } @{ $sth->fetchall_arrayref() };

     if(!@array) {
         my $aval = AttrVal($name, "aggregation", "");
         my @rsf;

         if ($aval eq "hour") {
             @rsf   = split(/[ :]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
         elsif ($aval eq "minute") {
             @rsf   = split(/[ :]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."-".$rsf[2]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
         else {
             @rsf   = split(" ",$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
     }

     push(@row_array, @array);
 }

 $sth->finish;
 $dbh->disconnect;

 my $rt = tv_interval($st);                                                      # SQL-Laufzeit ermitteln

 Log3 ($name, 5, "DbRep $name -> raw data of row_array result:\n @row_array");

 #---------- Berechnung Ergebnishash maxValue ------------------------
 my $i  = 1;
 my %rh = ();

 my ($lastruntimestring,$row_max_time,$max_value);

 for my $row (@row_array) {
     my ($r,$t)         = split("!_ESC_!", $row);                                # $t enthält $runtime_string_first."|".$runtime_string_next
     my @a              = split("[ \t][ \t]*", $r);
     my $runtime_string = decode_base64($a[0]);
     $lastruntimestring = $runtime_string if ($i == 1);
     my $value          = $a[1];

     $a[-1]             =~ s/:/-/g if($a[-1]);                                   # substituieren unsupported characters -> siehe fhem.pl
     my $timestamp      = $a[-1] && $a[-2] ? $a[-2]."_".$a[-1] : $a[-1];

     $timestamp         =~ s/\s+$//g;                                            # Leerzeichen am Ende $timestamp entfernen

     if (!looks_like_number($value)) {
         Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in maxValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
         $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
         return "$name|$err";
     }

     Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");

     if ($runtime_string eq $lastruntimestring) {
         if (!defined($max_value) || $value >= $max_value) {
             $max_value           = $value;
             $row_max_time        = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$max_value."|".$row_max_time."|".$t;
         }
     }
     else {                                                                    # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen
         $lastruntimestring = $runtime_string;
         undef $max_value;

         if (!defined($max_value) || $value >= $max_value) {
             $max_value           = $value;
             $row_max_time        = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$max_value."|".$row_max_time."|".$t;
         }
     }

     $i++;
 }
 #---------------------------------------------------------------------------------------------

 Log3 ($name, 5, "DbRep $name - result of maxValue calculation before encoding:");

 for my $key (sort(keys(%rh))) {
     Log3 ($name, 5, "runtimestring Key: $key, value: ".$rh{$key});
 }

 my $rows = join('§', %rh);                                                                # Ergebnishash als Einzeiler zurückgeben bzw. Übergabe Schreibroutine

 my ($wrt,$irowdone);

 if($prop =~ /writeToDB/) {                                                                # Ergebnisse in Datenbank schreiben
     ($err,$wrt,$irowdone) = DbRep_OutputWriteToDB($name,$device,$reading,$rows,"max");
     return "$name|$err" if($err);

     $rt = $rt+$wrt;
 }

 if($prop =~ /deleteOther/) {                                                              # andere Werte als "MAX" aus Datenbank löschen
     ($err,$wrt,$irowdone) = DbRep_deleteOtherFromDB($name,$device,$reading,$rows);
     return "$name|$err" if ($err);

     $rt = $rt+$wrt;
 }

 my $rowlist = encode_base64($rows,"");
 $device     = encode_base64($device,"");

 my $brt = tv_interval($bst);                                                              # Background-Laufzeit ermitteln
 $rt     = $rt.",".$brt;

return "$name|$err|$rowlist|$device|$reading|$rt|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage maxValue
####################################################################################################
sub DbRep_maxvalDone {
  my $string    = shift;
  my @a         = split("\\|",$string);
  my $name      = $a[0];
  my $err       = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist   = $a[2] ? decode_base64($a[2]) : '';
  my $device    = $a[3] ? decode_base64($a[3]) : '';
  my $reading   = $a[4];
  my $bt        = $a[5];
  my $irowdone  = $a[6];

  my $ndp       = AttrVal($name, "numDecimalPlaces", $dbrep_defdecplaces);
  my $hash      = $defs{$name};

  my ($reading_runtime_string);

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state",  "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                                 # Befehl nach Procedure ausführen incl. state
      DbRep_nextMultiCmd        ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my ($rt,$brt) = split ",", $bt;
  my %rh        = split "§", $rowlist;

  Log3 ($name, 5, "DbRep $name - result of maxValue calculation after decoding:");

  for my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key});
  }

  readingsBeginUpdate($hash);

  no warnings 'uninitialized';

  for my $key (sort(keys(%rh))) {
      my @k   = split("\\|",$rh{$key});
      my $rsf = "";
      $rsf    = $k[2]."__" if($k[2]);

      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      }
      else {
          my ($ds,$rds) = ("","");
          $ds           = $device."__"  if ($device);
          $rds          = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."MAX__".$k[0];
      }
      my $rv = $k[1];

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, defined $rv ? sprintf "%.${ndp}f",$rv : "-");
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB|deleteOther/);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage minValue
####################################################################################################
sub DbRep_minval {
 my $paref   = shift;
 my $hash    = $paref->{hash};
 my $name    = $paref->{name};
 my $table   = $paref->{table};
 my $device  = $paref->{device};
 my $reading = $paref->{reading};
 my $prop    = $paref->{prop};
 my $ts      = $paref->{ts};

 my ($sql,$sth);

 my $bst = [gettimeofday];                                                            # Background-Startzeit

 my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
 return "$name|$err" if ($err);

 no warnings 'uninitialized';

 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                            # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

 my @ts = split("\\|", $ts);                                                         # Timestampstring to Array
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

 my $st = [gettimeofday];                                                            # SQL-Startzeit

 my @row_array;
 for my $row (@ts) {                                                                 # DB-Abfrage zeilenweise für jeden Array-Eintrag
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];

     $runtime_string = encode_base64($runtime_string,"");

     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash, $table, "VALUE,TIMESTAMP", $device, $reading, $runtime_string_first, $runtime_string_next, "ORDER BY TIMESTAMP");
     }
     else {
         $sql = DbRep_createSelectSql($hash, $table, "VALUE,TIMESTAMP", $device, $reading, undef, undef, "ORDER BY TIMESTAMP");
     }

     ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
     return "$name|$err" if ($err);

     my @array = map { $runtime_string." ".$_->[0]." ".$_->[1]."!_ESC_!".$runtime_string_first."|".$runtime_string_next } @{ $sth->fetchall_arrayref() };

     if(!@array) {
         my $aval = AttrVal($name, "aggregation", "");
         my @rsf;

         if($aval eq "hour") {
             @rsf   = split(/[ :]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
         elsif($aval eq "minute") {
             @rsf   = split(/[ :]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."-".$rsf[2]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
         else {
             @rsf   = split(" ",$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."!_ESC_!".$runtime_string_first."|".$runtime_string_next);
         }
     }

     push(@row_array, @array);
 }

 $sth->finish;
 $dbh->disconnect;

 my $rt = tv_interval($st);                                                        # SQL-Laufzeit ermitteln

 Log3 ($name, 5, "DbRep $name -> raw data of row_array result:\n @row_array");

 #---------- Berechnung Ergebnishash minValue ------------------------
 my $i  = 1;
 my %rh = ();

 my ($row_min_time,$min_value,$value,$lastruntimestring);

 for my $row (@row_array) {
     my ($r,$t)         = split("!_ESC_!", $row);                                  # $t enthält $runtime_string_first."|".$runtime_string_next
     my @a              = split("[ \t][ \t]*", $r);
     my $runtime_string = decode_base64($a[0]);
     $lastruntimestring = $runtime_string if ($i == 1);
     $value             = $a[1];
     $min_value         = $a[1] if ($i == 1);
     $a[-1]             =~ s/:/-/g if($a[-1]);                                     # substituieren unsupported characters -> siehe fhem.pl
     my $timestamp      = $a[-1] && $a[-2] ? $a[-2]."_".$a[-1] : $a[-1];

     $timestamp         =~ s/\s+$//g;                                              # Leerzeichen am Ende $timestamp entfernen

     if (!looks_like_number($value)) {
         Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in minValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
         $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
         return "$name|$err";
     }

     Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");

     $rh{$runtime_string} = $runtime_string."|".$min_value."|".$timestamp."|".$t if ($i == 1);     # minValue des ersten SQL-Statements in hash einfügen

     if ($runtime_string eq $lastruntimestring) {
         if (!defined($min_value) || $value < $min_value) {
             $min_value           = $value;
             $row_min_time        = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$min_value."|".$row_min_time."|".$t;
         }
     }
     else {                                                                                        # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen
         $lastruntimestring   = $runtime_string;
         $min_value           = $value;
         $row_min_time        = $timestamp;
         $rh{$runtime_string} = $runtime_string."|".$min_value."|".$row_min_time."|".$t;
     }

     $i++;
 }
 #---------------------------------------------------------------------------------------------

 Log3 ($name, 5, "DbRep $name - result of minValue calculation before encoding:");
 for my $key (sort(keys(%rh))) {
     Log3 ($name, 5, "runtimestring Key: $key, value: ".$rh{$key});
 }

 my $rows = join('§', %rh);                                                                       # Ergebnishash als Einzeiler zurückgeben bzw. an Schreibroutine übergeben

 my ($wrt,$irowdone);

 if($prop =~ /writeToDB/) {                                                                       # Ergebnisse in Datenbank schreiben
     ($err,$wrt,$irowdone) = DbRep_OutputWriteToDB($name,$device,$reading,$rows,"min");
     return "$name|$err" if($err);

     $rt = $rt+$wrt;
 }

 if($prop =~ /deleteOther/) {                                                                    # andere Werte als "MIN" aus Datenbank löschen
     ($err,$wrt,$irowdone) = DbRep_deleteOtherFromDB($name,$device,$reading,$rows);
     return "$name|$err" if ($err);

     $rt = $rt + $wrt;
 }

 my $rowlist = encode_base64($rows,"");
 $device     = encode_base64($device,"");

 my $brt = tv_interval($bst);                                                                   # Background-Laufzeit ermitteln
 $rt     = $rt.",".$brt;

return "$name|$err|$rowlist|$device|$reading|$rt|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage minValue
####################################################################################################
sub DbRep_minvalDone {
  my $string    = shift;
  my @a         = split("\\|",$string);
  my $name      = $a[0];
  my $err       = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist   = $a[2] ? decode_base64($a[2]) : '';
  my $device    = $a[3] ? decode_base64($a[3]) : '';
  my $reading   = $a[4];
  my $bt        = $a[5];
  my $irowdone  = $a[6];

  my $hash      = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                                  # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                                    # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  my %rh        = split "§", $rowlist;
  my $ndp       = AttrVal($name, "numDecimalPlaces", $dbrep_defdecplaces);
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  Log3 ($name, 5, "DbRep $name - result of minValue calculation after decoding:");
  for my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key});
  }

  no warnings 'uninitialized';

  my $reading_runtime_string;

  readingsBeginUpdate($hash);

  for my $key (sort(keys(%rh))) {
      my @k   = split("\\|",$rh{$key});
      my $rsf = "";
      $rsf    = $k[2]."__" if($k[2]);

      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      }
      else {
          my ($ds,$rds)           = ("","");
          $ds                     = $device."__"  if ($device);
          $rds                    = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."MIN__".$k[0];
      }
      my $rv = $k[1];

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, defined($rv) ? sprintf("%.${ndp}f",$rv) : "-");
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB|deleteOther/);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage diffValue
####################################################################################################
sub DbRep_diffval {
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $prop    = $paref->{prop};
  my $ts      = $paref->{ts};

  my ($sql,$sth,$selspec);

  my $bst = [gettimeofday];                                                              # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  no warnings 'uninitialized';

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                               # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  my @ts = split("\\|", $ts);                                                            # Timestampstring to Array
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  if($dbmodel eq "OLDMYSQLVER") {                                                        # Forum: https://forum.fhem.de/index.php/topic,130697.0.html
      $selspec = "TIMESTAMP,VALUE, if(VALUE-\@V < 0 OR \@RB = 1 , \@diff:= 0, \@diff:= VALUE-\@V ) as DIFF, \@V:= VALUE as VALUEBEFORE, \@RB:= '0' as RBIT ";
  }
  else {
      $selspec = "TIMESTAMP,VALUE";
  }

  my @row_array;
  my @array;

  my $difflimit     = AttrVal ($name, 'diffAccept', 20);                                # legt fest, bis zu welchem Wert Differenzen akzeptiert werden (Ausreißer eliminieren)
  my ($sign, $dlim) = DbRep_ExplodeDiffAcc ($difflimit);                                # $sign -> Vorzeichen (+-)

  my $st = [gettimeofday];                                                              # SQL-Startzeit

  for my $row (@ts) {                                                                   # DB-Abfrage zeilenweise für jeden Array-Eintrag
      my @a                     = split "#", $row;
      my $runtime_string        = $a[0];
      my $runtime_string_first  = $a[1];
      my $runtime_string_next   = $a[2];
      $runtime_string           = encode_base64($runtime_string,"");

      if($dbmodel eq "OLDMYSQLVER") {                                                   # Forum: https://forum.fhem.de/index.php/topic,130697.0.html
          ($err, undef) = DbRep_dbhDo ($name, $dbh, "set \@V:= 0, \@diff:= 0, \@diffTotal:= 0, \@RB:= 1;");      # @\RB = Resetbit wenn neues Selektionsintervall beginnt
          return "$name|$err" if ($err);
      }

      if ($IsTimeSet || $IsAggrSet) {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device , $reading, $runtime_string_first, $runtime_string_next, 'ORDER BY TIMESTAMP');
      }
      else {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, 'ORDER BY TIMESTAMP');
      }

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
      return "$name|$err" if ($err);

      if($dbmodel eq "OLDMYSQLVER") {                                                  # Forum: https://forum.fhem.de/index.php/topic,130697.0.html
          @array = map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]." ".$_ -> [2]."\n" } @{ $sth->fetchall_arrayref() };
      }
      else {
          @array = map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]."\n" } @{ $sth->fetchall_arrayref() };

          if (@array) {
              my @sp;
              my $dse = 0;
              my $vold;
              my @db_array;

              for my $row (@array) {
                  @sp                = split /\s+/x, $row, 4;
                  my $runtime_string = $sp[0];
                  my $timestamp      = $sp[2] ? $sp[1]." ".$sp[2] : $sp[1];
                  my $vnew           = $sp[3];
                  $vnew              =~ tr/\n//d;

                  if (!DbRep_IsNumeric ($vnew)) {                                   # Test auf $value = "numeric"
                      Log3 ($name, 3, "DbRep $name - WARNING - dataset has no numeric value >$vnew< and is ignored\ntimestamp >$timestamp<, device >$device<, reading >$reading<");
                      next;
                  }

                  if (!defined $vold) {
                      $vold = $vnew;
                  }

                  if ($sign =~ /\+-/xs) {                                           # sowohl positive als auch negative Abweichung auswerten
                      $dse = $vnew - $vold;
                  }
                  else {
                      $dse = ($vnew - $vold) > 0 ? ($vnew - $vold) : 0;             # nur positive Abweichung auswerten
                  }

                  @sp   = $runtime_string." ".$timestamp." ".$vnew." ".$dse."\n";
                  $vold = $vnew;

                  push @db_array, @sp;
              }

              @array = @db_array;
          }
      }

      if(!@array) {
          my $aval = AttrVal($name, "aggregation", "");

          if($aval eq "month") {
              my @rsf = split /[ -]/, $runtime_string_first;
              @array  = ($runtime_string." ".$rsf[0]."_".$rsf[1]."\n");
          }
          elsif($aval eq "hour") {
              my @rsf = split /[ :]/, $runtime_string_first;
              @array  = ($runtime_string." ".$rsf[0]."_".$rsf[1]."\n");
          }
          elsif($aval eq "minute") {
              my @rsf = split /[ :]/, $runtime_string_first;
              @array  = ($runtime_string." ".$rsf[0]."_".$rsf[1]."-".$rsf[2]."\n");
          }
          else {
              my $rsfe = encode_base64((split " ", $runtime_string_first)[0],"");
              my @rsf  = split " ", $runtime_string_first;
              @array   = ($rsfe." ".$rsf[0]."\n");
          }
      }

      push @row_array, @array;
  }

  my $rt = tv_interval($st);                                                         # SQL-Laufzeit ermitteln

  $sth->finish;
  $dbh->disconnect;

  # Berechnung diffValue aus Selektionshash
  my %rh  = ();                   # Ergebnishash, wird alle Ergebniszeilen enthalten
  my %ch  = ();                   # counthash, enthält die Anzahl der verarbeiteten Datasets pro runtime_string
  my $i   = 1;
  my $max = ($#row_array)+1;      # Anzahl aller Listenelemente
  my $lastruntimestring;
  my $lval;                       # immer der letzte Wert von $value
  my $rslval;                     # runtimestring von lval
  my $uediff;                     # Übertragsdifferenz (Differenz zwischen letzten Wert einer Aggregationsperiode und dem ersten Wert der Folgeperiode)
  my $diff_current;               # Differenzwert des aktuellen Datasets
  my $diff_before;                # Differenzwert vorheriger Datensatz
  my $rejectstr;                  # String der ignorierten Differenzsätze
  my $diff_total;                 # Summenwert aller berücksichtigten Teildifferenzen

  Log3 ($name, 5, "DbRep $name - data of row_array result assigned to fields:\n");

  for my $row (@row_array) {
      my @a              = split /\s+/x, $row, 6;
      my $runtime_string = decode_base64($a[0]);
      $lastruntimestring = $runtime_string if ($i == 1);

      if(!$a[2]) {
          $rh{$runtime_string} = $runtime_string."|-|".$runtime_string;
          next;
      }

      my $timestamp      = $a[1]."_".$a[2];
      my $value          = $a[3] ? $a[3] : 0;
      my $diff           = $a[4] ? $a[4] : 0;

      $timestamp         =~ s/\s+$//g;                                                # Leerzeichen am Ende $timestamp entfernen

      if (!DbRep_IsNumeric ($value)) {                                                # Test auf $value = "numeric"
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in diffValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
          $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
          return "$name|$err";
      }

      Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value, DIFF: $diff");

      $diff_current = $timestamp." ".$diff;                                           # String ignorierter Zeilen erzeugen

      if(abs $diff > $dlim) {
          $rejectstr .= $diff_before." -> ".$diff_current."\n";
      }

      $diff_before = $diff_current;

      if ($runtime_string eq $lastruntimestring) {                                    # Ergebnishash erzeugen
          if ($i == 1) {
              if(abs $diff <= $dlim) {
                  $diff_total = $diff;
              }

              $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
              $ch{$runtime_string} = 1 if(defined $a[3]);
              $lval                = $value;
              $rslval              = $runtime_string;
          }

          if ($diff) {
              if(abs $diff <= $dlim) {
                  $diff_total = $diff_total + $diff;
              }

              $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
          }

          $lval                = $value;
          $rslval              = $runtime_string;
          $ch{$runtime_string}++ if(defined $a[3] && $i > 1);
      }
      else {                                                                          # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen und Übertragsdifferenz bilden
          $lastruntimestring = $runtime_string;
          $i                 = 1;
          $uediff            = $value - $lval;
          $diff              = $uediff;
          $lval              = $value if($value);                                     # Übertrag über Perioden mit value = 0 hinweg !

          Log3 ($name, 5, "DbRep $name - balance difference of $uediff between $rslval and $runtime_string");

          $rslval = $runtime_string;

          if(abs $diff <= $dlim) {
              $diff_total = $diff;
          }

          $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
          $ch{$runtime_string} = 1 if(defined $a[3]);
          $uediff              = 0;
      }

      $i++;
  }

  Log3 ($name, 5, "DbRep $name - print result of diffValue calculation before encoding ...");

  for my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "runtimestring Key: $key, value: ".$rh{$key});
  }

  my $ncp = DbRep_calcount($hash,\%ch);

  my ($ncps,$ncpslist);

  if(%$ncp) {
      Log3 ($name, 3, "DbRep $name - time/aggregation periods containing only one dataset -> no diffValue calc was possible in period:");

      for my $key (sort(keys%{$ncp})) {
          Log3 ($name, 3, $key) ;
      }

      $ncps     = join '§', %$ncp;
      $ncpslist = encode_base64($ncps,"");
  }

  # Ergebnishash als Einzeiler zurückgeben
  # ignorierte Zeilen (abs $diff > $dlim)
  my $rowsrej;
  $rowsrej = encode_base64 ($rejectstr, "") if($rejectstr);

  my $rows = join '§', %rh;                                                           # Ergebnishash

  my ($wrt,$irowdone);                                                                # Ergebnisse in Datenbank schreiben

  if($prop =~ /writeToDB/) {
      ($err,$wrt,$irowdone) = DbRep_OutputWriteToDB ($name,$device,$reading,$rows,"diff");
      return "$name|$err" if($err);

      $rt = $rt + $wrt;
  }

  my $rowlist = encode_base64($rows,  "");
  $device     = encode_base64($device,"");
  my $brt     = tv_interval($bst);                                                   # Background-Laufzeit ermitteln

  $rt = $rt.",".$brt;

return "$name|$err|$rowlist|$device|$reading|$rt|$rowsrej|$ncpslist|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage diffValue
####################################################################################################
sub DbRep_diffvalDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist    = $a[2] ? decode_base64($a[2]) : '';
  my $device     = $a[3] ? decode_base64($a[3]) : '';
  my $reading    = $a[4];
  my $bt         = $a[5];
  my $rowsrej    = $a[6] ? decode_base64($a[6]) : '';                                  # String von Datensätzen die nicht berücksichtigt wurden (diff Schwellenwert Überschreitung)
  my $ncpslist   = $a[7] ? decode_base64($a[7]) : '';                                  # Hash von Perioden die nicht kalkuliert werden konnten "no calc in period"
  my $irowdone   = $a[8];

  my $hash          = $defs{$name};
  my $ndp           = AttrVal ($name, "numDecimalPlaces", $dbrep_defdecplaces);
  my $difflimit     = AttrVal ($name, 'diffAccept', 20);                               # legt fest, bis zu welchem Wert Differenzen akzeptiert werden (Ausreißer eliminieren)
  my ($sign, $dlim) = DbRep_ExplodeDiffAcc ($difflimit);

  my $reading_runtime_string;

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                            # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                              # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  no warnings 'uninitialized';

  $rowsrej =~ s/_/ /g;
  Log3 ($name, 3, "DbRep $name -> data ignored while calc diffValue due to threshold overrun (diffAccept = $difflimit): \n$rowsrej")
           if($rowsrej);
  $rowsrej =~ s/\n/ \|\| /g;

  my %ncp  = split("§", $ncpslist);
  my $ncpstr;

  if(%ncp) {
      for my $ncpkey (sort(keys(%ncp))) {
          $ncpstr .= $ncpkey." || ";
      }
  }

  my %rh = split("§", $rowlist);

  readingsBeginUpdate($hash);

  for my $key (sort(keys(%rh))) {
      my $valid = 0;                                                                   # Datensatz hat kein Ergebnis als default
      my @k     = split("\\|",$rh{$key});
      $valid    = 1 if($k[2] =~ /(\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2}):(\d{2})/x);   # Datensatz hat einen Wert wenn kompletter Timestamp ist enthalten
      my $rts   = $k[2]."__";
      $rts      =~ s/:/-/g;                                                 # substituieren unsupported characters -> siehe fhem.pl

      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rts.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      }
      else {
          my ($ds,$rds)           = ("","");
          $ds                     = $device."__"  if ($device);
          $rds                    = $reading."__" if ($reading);
          $reading_runtime_string = $rts.$ds.$rds."DIFF__".$k[0];
      }
      my $rv = $k[1];

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, (!$valid ? "-" : defined $rv ? sprintf "%.${ndp}f", $rv : "-"));
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone)                   if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateValue ($hash, "diff_overrun_limit_".$dlim, $rowsrej)             if($rowsrej);
  ReadingsBulkUpdateValue ($hash, "less_data_in_period", $ncpstr)                    if($ncpstr);
  ReadingsBulkUpdateValue ($hash, "state", qq{WARNING - see readings 'less_data_in_period' or 'diff_overrun_limit_XX'})
                                                                                     if($ncpstr||$rowsrej);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                             nichtblockierende DB-Abfrage sumValue
####################################################################################################
sub DbRep_sumval {
 my $paref   = shift;
 my $hash    = $paref->{hash};
 my $name    = $paref->{name};
 my $table   = $paref->{table};
 my $device  = $paref->{device};
 my $reading = $paref->{reading};
 my $prop    = $paref->{prop};
 my $ts      = $paref->{ts};

 my ($sql,$sth,$selspec);

 my $bst = [gettimeofday];                                                           # Background-Startzeit

 my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
 return "$name|$err" if ($err);

 no warnings 'uninitialized';                                                        # only for this block because of warnings if details of readings are not set

 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                            # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

 my @ts = split("\\|", $ts);                                                         # Timestampstring to Array
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

 if ($dbmodel eq "POSTGRESQL") {                                                     #vorbereiten der DB-Abfrage, DB-Modell-abhaengig
     $selspec = "SUM(VALUE::numeric)";
 }
 elsif ($dbmodel eq "MYSQL") {
     $selspec = "SUM(VALUE)";
 }
 elsif ($dbmodel eq "SQLITE") {
     $selspec = "SUM(VALUE)";
 }
 else {
     $selspec = "SUM(VALUE)";
 }

 my $st = [gettimeofday];                                                            # SQL-Startzeit

 my ($arrstr,$wrstr,@rsf,@rsn,@wsf,@wsn);
 for my $row (@ts) {                                                                 # DB-Abfrage zeilenweise für jeden Array-Eintrag
     my @a                    = split("#", $row);
     my $runtime_string       = $a[0];
     my $runtime_string_first = $a[1];
     my $runtime_string_next  = $a[2];

     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, '');
     }
     else {
         $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, '');
     }

     ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
     return "$name|$err" if ($err);

     my @line = $sth->fetchrow_array();                                              # DB-Abfrage -> Ergebnis in @arr aufnehmen

     Log3 ($name, 5, "DbRep $name - SQL result: $line[0]") if($line[0]);

     if(AttrVal($name, "aggregation", "") eq "hour") {
         @rsf     = split(/[ :]/,$runtime_string_first);
         @rsn     = split(/[ :]/,$runtime_string_next);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."_".$rsf[1]."|";
     }
     else {
         @rsf     = split(" ",$runtime_string_first);
         @rsn     = split(" ",$runtime_string_next);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."|";
     }

     @wsf    = split(" ",$runtime_string_first);
     @wsn    = split(" ",$runtime_string_next);
     $wrstr .= $runtime_string."#".$line[0]."#".$wsf[0]."_".$wsf[1]."#".$wsn[0]."_".$wsn[1]."|";    # Kombi zum Rückschreiben in die DB
 }

 $sth->finish;
 $dbh->disconnect;

 my $rt = tv_interval($st);                                                          # SQL-Laufzeit ermitteln

 my ($wrt,$irowdone);                                                                # Ergebnisse in Datenbank schreiben

 if($prop =~ /writeToDB/) {
     ($err,$wrt,$irowdone) = DbRep_OutputWriteToDB($name,$device,$reading,$wrstr,"sum");
     return "$name|$err" if($err);

     $rt = $rt+$wrt;
 }

 $arrstr = encode_base64($arrstr,"");                                                # Daten müssen als Einzeiler zurückgegeben werden
 $device = encode_base64($device,"");

 my $brt = tv_interval($bst);                                                        # Background-Laufzeit ermitteln
 $rt     = $rt.",".$brt;

return "$name|$err|$arrstr|$device|$reading|$rt|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage sumValue
####################################################################################################
sub DbRep_sumvalDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $arrstr     = $a[2] ? decode_base64($a[2]) : '';
  my $device     = $a[3] ? decode_base64($a[3]) : '';
  my $reading    = $a[4];
  my $bt         = $a[5];
  my $irowdone   = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state",  "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                           # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  my $ndp       = AttrVal($name, "numDecimalPlaces", $dbrep_defdecplaces);
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  my $reading_runtime_string;

  no warnings 'uninitialized';                                                   # only for this block because of warnings if details of readings are not set

  readingsBeginUpdate ($hash);

  my @arr = split("\\|", $arrstr);
  
  for my $row (@arr) {
      my @a              = split("#", $row);
      my $runtime_string = $a[0];
      my $c              = $a[1] // "";
      my $rsf            = $a[2]."__";

      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$runtime_string;
      }
      else {
          my ($ds,$rds)           = ("","");
          $ds                     = $device. "__" if ($device);
          $rds                    = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."SUM__".$runtime_string;
      }

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $c ne "" ? sprintf "%.${ndp}f", $c : "-");
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierendes DB delete
####################################################################################################
sub DbRep_del {
  my $paref                = shift;
  my $hash                 = $paref->{hash};
  my $name                 = $paref->{name};
  my $table                = $paref->{table};
  my $device               = $paref->{device};
  my $reading              = $paref->{reading};
  my $runtime_string_first = $paref->{rsf};
  my $runtime_string_next  = $paref->{rsn};

  my ($sql,$sth,$rows);

  my $bst = [gettimeofday];                                                            # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                              # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  BlockingInformParent("DbRep_delHashValFromBlocking", [$name, "HELPER","DELENTRIES"], 1);

  if ($IsTimeSet || $IsAggrSet) {
      $sql = DbRep_createDeleteSql($hash,$table,$device,$reading,$runtime_string_first,$runtime_string_next,'');
  }
  else {
      $sql = DbRep_createDeleteSql($hash,$table,$device,$reading,undef,undef,'');
  }

  my $st = [gettimeofday];                                                             # SQL-Startzeit

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  $rows = $sth->rows;
  $dbh->commit() if(!$dbh->{AutoCommit});

  $sth->finish;
  $dbh->disconnect;

  my $rt = tv_interval($st);                                                          # SQL-Laufzeit ermitteln

  Log3 ($name, 5, "DbRep $name - Number of deleted rows: $rows");

  my $brt = tv_interval($bst);                                                        # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

return "$name|$err|$rows|$rt|$table|$device|$reading";
}

####################################################################################################
# Auswertungsroutine DB delete
####################################################################################################
sub DbRep_del_Done {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rows       = $a[2];
  my $bt         = $a[3];
  my $table      = $a[4];
  my $device     = $a[5];
  my $reading    = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                           # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  no warnings 'uninitialized';

  my ($reading_runtime_string, $ds, $rds);

  if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
      $reading_runtime_string = AttrVal($hash->{NAME}, "readingNameMap", "")."--DELETED_ROWS";
  }
  else {
      $ds   = $device. "--" if ($device  && $table ne "current");
      $rds  = $reading."--" if ($reading && $table ne "current");
      $reading_runtime_string = $ds.$rds."DELETED_ROWS_".uc($table);
  }

  readingsBeginUpdate ($hash);

  ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $rows);

  $rows = $table eq "current" ? $rows : $ds.$rds.$rows;
  Log3 ($name, 3, "DbRep $name - Entries of $hash->{DATABASE}.$table deleted: $rows");

  ReadingsBulkUpdateTime ($hash, $brt, $rt);
  readingsEndUpdate      ($hash, 1);

  DbRep_afterproc        ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd     ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierendes DB insert
####################################################################################################
sub DbRep_insert {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $table = $paref->{table};
  my $prop  = $paref->{prop};

  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  my $bst = [gettimeofday];                                                        # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  # check ob PK verwendet wird, @usepkx ? Anzahl der Felder im PK : 0 wenn kein PK,
  # $pkx ? Namen der Felder : none wenn kein PK
  my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);

  my ($i_timestamp,$i_device,$i_reading,$i_value,$i_unit) = split ",", $prop;
  my $i_type                                              = "manual";
  my $i_event                                             = "manual";

  if ($dbmodel ne 'SQLITE') {                                                      # V8.48.4 - Daten auf maximale Länge (entsprechend der Feldlänge in DbLog) beschneiden wenn nicht SQLite
      $i_device  = substr($i_device,  0, $hash->{HELPER}{DBREPCOL}{DEVICE});
      $i_reading = substr($i_reading, 0, $hash->{HELPER}{DBREPCOL}{READING});
      $i_value   = substr($i_value,   0, $hash->{HELPER}{DBREPCOL}{VALUE});
      $i_unit    = substr($i_unit,    0, $hash->{HELPER}{DBREPCOL}{UNIT});
  }

  Log3 ($name, 5, "DbRep $name -> data to insert Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");

  my $st = [gettimeofday];                                                         # SQL-Startzeit

  my ($sth,$sql,$irow);

  # insert into $table mit/ohne primary key
  if ($usepkh && $dbmodel eq 'MYSQL') {
      $sql = "INSERT IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbmodel eq 'SQLITE') {
      $sql = "INSERT OR IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbmodel eq 'POSTGRESQL') {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING";
  }
  else {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }

  ($err, $sth) = DbRep_prepareOnly ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  $err = DbRep_beginDatabaseTransaction ($name, $dbh);
  return "$name|$err" if ($err);

  eval{ $sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - Insert new dataset into database failed".($usepkh ? " (possible PK violation) " : ": ")."$@");
              $dbh->rollback();
              $dbh->disconnect();
              return "$name|$err";
            };

  $err = DbRep_commitOnly ($name, $dbh);
  return "$name|$err" if ($err);

  $dbh->disconnect();

  $err  = q{};
  $irow = $sth->rows;

  Log3 ($name, 4, "DbRep $name - Inserted into $hash->{DATABASE}.$table: $i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit");

  my $rt  = tv_interval($st);                                         # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                        # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

  my $insert = encode_base64 ("$i_timestamp,$i_device,$i_type,$i_event,$i_reading,$i_value,$i_unit", "");

return "$name|$err|$irow|$rt|$insert";
}

####################################################################################################
# Auswertungsroutine DB insert
####################################################################################################
sub DbRep_insertDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64 ($a[1]) : '';
  my $irow       = $a[2];
  my $bt         = $a[3];
  my $insert     = $a[4] ? decode_base64 ($a[4]) : '';

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "insert");                               # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  my ($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit) = split ",", $insert;

  no warnings 'uninitialized';

  readingsBeginUpdate ($hash);

  ReadingsBulkUpdateValue ($hash, "number_lines_inserted", $irow);
  ReadingsBulkUpdateValue ($hash, "data_inserted", $i_timestamp.", ".$i_device.", ".$i_type.", ".$i_event.", ".$i_reading.", ".$i_value.", ".$i_unit);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, "insert");                                 # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                           # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#   Current-Tabelle mit Device,Reading Kombinationen aus history auffüllen
####################################################################################################
sub DbRep_currentfillup {
  my $paref                = shift;
  my $hash                 = $paref->{hash};
  my $name                 = $paref->{name};
  my $table                = $paref->{table};
  my $device               = $paref->{device};
  my $reading              = $paref->{reading};
  my $runtime_string_first = $paref->{rsf};
  my $runtime_string_next  = $paref->{rsn};

  my $dbloghash            = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  my ($sth,$sql,$irow,$selspec,$addon,@dwc,@rwc);

  my $bst = [gettimeofday];                                                          # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);          # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                           # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  my $st = [gettimeofday];                                                           # SQL-Startzeit

  if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
      $selspec = "INSERT IGNORE INTO $table (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where";
      $addon   = "group by timestamp,device,reading";
  }
  elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {
      $selspec = "INSERT OR IGNORE INTO $table (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where";
      $addon   = "group by timestamp,device,reading";
  }
  elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
      $selspec = "INSERT INTO $table (DEVICE,TIMESTAMP,READING) SELECT device, (array_agg(timestamp ORDER BY reading ASC))[1], reading FROM history where";
      $addon   = "group by device,reading ON CONFLICT ($pkc) DO NOTHING";
  }
  else {
      if($dbloghash->{MODEL} ne 'POSTGRESQL') {                                     # MySQL und SQLite
          $selspec = "INSERT INTO $table (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where";
          $addon   = "group by device,reading";
      }
      else {                                                                        # PostgreSQL
          $selspec = "INSERT INTO $table (DEVICE,TIMESTAMP,READING) SELECT device, (array_agg(timestamp ORDER BY reading ASC))[1], reading FROM history where";
          $addon   = "group by device,reading";
      }
  }

  # SQL-Statement zusammenstellen
  my $valfilter = AttrVal($name, "valueFilter", undef);                            # Wertefilter

  my $specs = {
      hash      => $hash,
      selspec   => $selspec,
      device    => $device,
      reading   => $reading,
      dbmodel   => $dbmodel,
      valfilter => $valfilter,
      addon     => $addon
  };

  if ($IsTimeSet || $IsAggrSet) {
      $specs->{rsf} = $runtime_string_first;
      $specs->{rsn} = $runtime_string_next;
  }

  $sql = DbRep_createCommonSql($specs);

  $err = DbRep_beginDatabaseTransaction ($name, $dbh);
  return "$name|$err" if ($err);

  ($err, $sth, $irow) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  $err = DbRep_commitOnly ($name, $dbh);
  return "$name|$err" if ($err);

  $dbh->disconnect();

  $irow = $irow eq "0E0" ? 0 : $irow;

  my $rt  = tv_interval($st);                                                # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                               # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

return "$name|$err|$irow|$rt|$device|$reading";
}

####################################################################################################
#                      Auswertungsroutine Current-Tabelle auffüllen
####################################################################################################
sub DbRep_currentfillupDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $irow       = $a[2];
  my $bt         = $a[3];
  my $device     = $a[4];
  my $reading    = $a[5];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                         # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                           # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  undef $device  if ($device =~ m(^%$));
  undef $reading if ($reading =~ m(^%$));

  no warnings 'uninitialized';

  my $rowstr;
  $rowstr = $irow if(!$device && !$reading);
  $rowstr = $irow." - limited by device: ".$device if($device && !$reading);
  $rowstr = $irow." - limited by reading: ".$reading if(!$device && $reading);
  $rowstr = $irow." - limited by device: ".$device." and reading: ".$reading if($device && $reading);

  readingsBeginUpdate      ($hash);
  ReadingsBulkUpdateValue  ($hash, "number_lines_inserted", $rowstr);
  ReadingsBulkUpdateTime   ($hash, $brt, $rt);
  readingsEndUpdate        ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Table '$hash->{DATABASE}'.'current' filled up with rows: $rowstr");

  DbRep_afterproc          ($hash, $hash->{LASTCMD});                     # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd       ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    nichtblockierendes DB deviceRename / readingRename
####################################################################################################
sub DbRep_changeDevRead {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $renmode = $paref->{renmode};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};

  my $db      = $hash->{DATABASE};

  my ($sql,$dev,$sth,$old,$new);

  my $bst = [gettimeofday];                                # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my $st = [gettimeofday];                                # SQL-Startzeit

  $err = DbRep_beginDatabaseTransaction ($name, $dbh);
  return "$name|$err" if ($err);

  if ($renmode eq "devren") {
      $old  = delete $hash->{HELPER}{OLDDEV};
      $new  = delete $hash->{HELPER}{NEWDEV};

      Log3 ($name, 5, qq{DbRep $name -> Rename old device name "$old" to new device name "$new" in database $db});

      $old =~ s/'/''/g;                                       # escape ' with ''
      $new =~ s/'/''/g;                                       # escape ' with ''
      $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,DEVICE='$new' WHERE DEVICE='$old'; ";
  }
  elsif ($renmode eq "readren") {
      $old        = delete $hash->{HELPER}{OLDREAD};
      ($dev,$old) = split ":", $old,2 if($old =~ /:/);        # Wert besteht aus [device]:old_readingname, device ist optional
      $new        = delete $hash->{HELPER}{NEWREAD};

      Log3 ($name, 5, qq{DbRep $name -> Rename old reading name }.($dev ? "$dev:$old" : "$old").qq{ to new reading name "$new" in database $db});

      $old =~ s/'/''/g;                               # escape ' with ''
      $new =~ s/'/''/g;                               # escape ' with ''

      if($dev) {
          $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,READING='$new' WHERE DEVICE='$dev' AND READING='$old'; ";
      }
      else {
          $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,READING='$new' WHERE READING='$old'; ";
      }
  }

  $old =~ s/''/'/g;                                   # escape back
  $new =~ s/''/'/g;                                   # escape back

  my $urow;
  ($err, $sth) = DbRep_prepareOnly ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  eval{ $sth->execute();
      }
      or do { $err = encode_base64($@,"");
              my $m = ($renmode eq "devren") ? "device" : "reading";

              Log3 ($name, 2, qq{DbRep $name - Failed to rename old $m name "$old" to new $m name "$new": $@});

              $dbh->rollback() if(!$dbh->{AutoCommit});
              $dbh->disconnect();
              return "$name|$err";
            };

  $err = DbRep_commitOnly ($name, $dbh);
  return "$name|$err" if ($err);

  $dbh->disconnect();

  $urow = $sth->rows;

  my $rt  = tv_interval($st);                         # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                        # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $old    = $dev ? "$dev:$old" : $old;
  $err    = q{};

return "$name|$err|$urow|$rt|$old|$new|$renmode";
}

####################################################################################################
#                        nichtblockierendes DB changeValue (Field VALUE)
####################################################################################################
sub DbRep_changeVal {
  my $paref                = shift;
  my $hash                 = $paref->{hash};
  my $name                 = $paref->{name};
  my $table                = $paref->{table};
  my $renmode              = $paref->{renmode};
  my $device               = $paref->{device};
  my $reading              = $paref->{reading};
  my $runtime_string_first = $paref->{rsf};
  my $runtime_string_next  = $paref->{rsn};
  my $ts                   = $paref->{ts};

  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $db        = $hash->{DATABASE};
  my $complex   = $hash->{HELPER}{COMPLEX};                              # einfache oder komplexe Werteersetzung

  my ($sql,$urow,$sth);

  my $bst = [gettimeofday];                                              # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  my $st = [gettimeofday];                                             # SQL-Startzeit

  $err = DbRep_beginDatabaseTransaction ($name, $dbh);
  return "$name|$err" if ($err);

  my $old = delete $hash->{HELPER}{OLDVAL};
  my $new = delete $hash->{HELPER}{NEWVAL};

 if (!$complex) {
     Log3 ($name, 5, qq{DbRep $name -> Change old value "$old" to new value "$new" in database $db});

     $old =~ s/'/''/g;                                            # escape ' with ''
     $new =~ s/'/''/g;                                            # escape ' with ''

     my $addon   = $old =~ /%/ ? "WHERE VALUE LIKE '$old'" : "WHERE VALUE='$old'";
     my $selspec = "UPDATE $table SET TIMESTAMP=TIMESTAMP,VALUE='$new' $addon AND ";

     my $valfilter = AttrVal($name, "valueFilter", undef);                            # Wertefilter

     my $specs = {
         hash      => $hash,
         selspec   => $selspec,
         device    => $device,
         reading   => $reading,
         dbmodel   => $dbmodel,
         valfilter => $valfilter,
         addon     => ''
     };

     if ($IsTimeSet) {
         $specs->{rsf} = $runtime_string_first;
         $specs->{rsn} = $runtime_string_next;
     }

     $sql = DbRep_createCommonSql($specs);

     ($err, $sth) = DbRep_prepareOnly ($name, $dbh, $sql);
     return "$name|$err" if ($err);

     $old =~ s/''/'/g;                                           # escape back
     $new =~ s/''/'/g;                                           # escape back

      eval{ $sth->execute();
          }
          or do { $err = encode_base64($@, "");
                  Log3 ($name, 2, qq{DbRep $name - Failed to change old value "$old" to new value "$new": $@});
                  $dbh->rollback() if(!$dbh->{AutoCommit});
                  $dbh->disconnect();
                  return "$name|$err";
                };

     $urow = $sth->rows;
 }
 else {
     $old =~ s/'/''/g;                                                           # escape ' with ''

     my @tsa = split("\\|", $ts);                                                # Timestampstring to Array

     Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@tsa");

     $urow       = 0;
     my $selspec = "DEVICE,READING,TIMESTAMP,VALUE,UNIT";
     my $addon   = $old =~ /%/ ? "AND VALUE LIKE '$old'" : "AND VALUE='$old'";

     for my $row (@tsa) {                                                        # DB-Abfrage zeilenweise für jeden Array-Eintrag
         my @ra                    = split("#", $row);
         my $runtime_string        = $ra[0];
         my $runtime_string_first  = $ra[1];
         my $runtime_string_next   = $ra[2];

         if ($IsTimeSet || $IsAggrSet) {
             $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
         }
         else {
             $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, $addon);
         }

         ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
         return "$name|$err" if ($err);

         no warnings 'uninitialized';
         #                     DEVICE   _ESC_  READING  _ESC_     DATE _ESC_ TIME        _ESC_  VALUE    _ESC_   UNIT
         my @row_array = map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3]."_ESC_".$_->[4]."\n" } @{$sth->fetchall_arrayref()};
         use warnings;

         Log3 ($name, 4, "DbRep $name - Now change values of selected array ... ");

         for my $upd (@row_array) {                                  # für jeden selektierten (zu ändernden) Datensatz Userfunktion anwenden und updaten
             my ($device,$reading,$date,$time,$value,$unit) = ($upd =~ /^(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)$/);

             my $oval  = $value;                                     # Selektkriterium für Update alter Valuewert
             my $VALUE = $value;
             my $UNIT  = $unit;

             eval $new;
             if ($@) {
                 $err = encode_base64($@,"");
                 Log3 ($name, 2, "DbRep $name - $@");
                 $dbh->disconnect;
                 return "$name|$err";
             }

             $value = $VALUE if(defined $VALUE);
             $unit  = $UNIT  if(defined $UNIT);

             # Daten auf maximale Länge beschneiden (DbLog-Funktion !)
             (undef,undef,undef,undef,$value,$unit) = DbLog_cutCol($dbloghash,"1","1","1","1",$value,$unit);

             $value =~ s/'/''/g;                                  # escape ' with ''
             $unit  =~ s/'/''/g;                                  # escape ' with ''

             $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,VALUE='$value',UNIT='$unit' WHERE TIMESTAMP = '$date $time' AND DEVICE = '$device' AND READING = '$reading' AND VALUE='$oval'";

             ($err, $sth) = DbRep_prepareOnly ($name, $dbh, $sql);
             return "$name|$err" if ($err);

             $value =~ s/''/'/g;                                  # escape back
             $unit  =~ s/''/'/g;                                  # escape back

             eval{ $sth->execute();
                 }
                 or do { $err = encode_base64($@,"");
                         Log3 ($name, 2, qq{DbRep $name - Failed to change old value "$old" to new value "$new": $@});
                         $dbh->rollback() if(!$dbh->{AutoCommit});
                         $dbh->disconnect();
                         return "$name|$err";
                       };

             $urow++;
         }
     }
 }

 $err = DbRep_commitOnly ($name, $dbh);
 return "$name|$err" if ($err);

 $dbh->disconnect();

 my $rt  = tv_interval($st);                                     # SQL-Laufzeit ermitteln
 my $brt = tv_interval($bst);                                    # Background-Laufzeit ermitteln
 $rt     = $rt.",".$brt;

return "$name|$err|$urow|$rt|$old|$new|$renmode";
}

####################################################################################################
#                   Auswertungsroutine DB deviceRename/readingRename/changeValue
####################################################################################################
sub DbRep_changeDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $urow       = $a[2];
  my $bt         = $a[3];
  my $old        = $a[4];
  my $new        = $a[5];
  my $renmode    = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $renmode);                             # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                       # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt)  = split(",", $bt);

  no warnings 'uninitialized';

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "number_lines_updated", $urow);

  if($renmode eq "devren") {
      ReadingsBulkUpdateValue ($hash, "device_renamed", "old: ".$old." to new: ".$new) if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "device_not_renamed", "WARNING - old: ".$old." not found")
          if($urow == 0);
  }

  if($renmode eq "readren") {
      ReadingsBulkUpdateValue ($hash, "reading_renamed", "old: ".$old." to new: ".$new)  if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "reading_not_renamed", "WARNING - old: ".$old." not found")
          if ($urow == 0);
  }

  if($renmode eq "changeval") {
      ReadingsBulkUpdateValue ($hash, "value_changed", "old: ".$old." to new: ".$new)  if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "value_not_changed", "WARNING - old: ".$old." not found")
          if ($urow == 0);
  }

  ReadingsBulkUpdateTime ($hash, $brt, $rt);
  readingsEndUpdate      ($hash, 1);

  if ($urow != 0) {
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - DEVICE renamed in \"$hash->{DATABASE}\" - old: \"$old\", new: \"$new\", number: $urow ")  if($renmode eq "devren");
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - READING renamed in \"$hash->{DATABASE}\" - old: \"$old\", new: \"$new\", number: $urow ") if($renmode eq "readren");
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - VALUE changed in \"$hash->{DATABASE}\" - old: \"$old\", new: \"$new\", number: $urow ")   if($renmode eq "changeval");
  }
  else {
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - WARNING - old device \"$old\" was not found in database \"$hash->{DATABASE}\" ")  if($renmode eq "devren");
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - WARNING - old reading \"$old\" was not found in database \"$hash->{DATABASE}\" ") if($renmode eq "readren");
      Log3 ($name, 3, "DbRep ".($hash->{ROLE} eq "Agent" ? "Agent " : "")."$name - WARNING - old value \"$old\" not found in database \"$hash->{DATABASE}\" ")       if($renmode eq "changeval");
  }

  DbRep_afterproc        ($hash, $renmode);                             # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd     ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage fetchrows
####################################################################################################
sub DbRep_fetchrows {
  my $paref                = shift;
  my $hash                 = $paref->{hash};
  my $name                 = $paref->{name};
  my $table                = $paref->{table};
  my $device               = $paref->{device};
  my $reading              = $paref->{reading};
  my $runtime_string_first = $paref->{rsf};
  my $runtime_string_next  = $paref->{rsn};

  my $utf8                 = $hash->{UTF8} // 0;
  my $limit                = AttrVal($name, "limit", 1000);
  my $fetchroute           = AttrVal($name, "fetchRoute", "descent");
  $fetchroute              = $fetchroute eq "descent" ? "DESC" : "ASC";

  my ($sth,$sql,$rowlist,$nrows);

  my $bst = [gettimeofday];                                                           # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                            # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  if ($IsTimeSet) {                                                                   # SQL zusammenstellen für DB-Abfrage
      $sql = DbRep_createSelectSql($hash, $table, "DEVICE,READING,TIMESTAMP,VALUE,UNIT", $device, $reading, $runtime_string_first, $runtime_string_next, "ORDER BY TIMESTAMP $fetchroute LIMIT ".($limit+1));
  }
  else {
      $sql = DbRep_createSelectSql($hash, $table, "DEVICE,READING,TIMESTAMP,VALUE,UNIT", $device, $reading, undef, undef, "ORDER BY TIMESTAMP $fetchroute LIMIT ".($limit+1));
  }

  my $st = [gettimeofday];                                                           # SQL-Startzeit

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  no warnings 'uninitialized';

  my @row_array = map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3]."_ESC_".$_->[4]."\n" } @{$sth->fetchall_arrayref()};

  use warnings;

  $nrows = $#row_array+1;                                                            # Anzahl der Ergebniselemente
  pop @row_array if($nrows > $limit);                                                # das zuviel selektierte Element wegpoppen wenn Limit überschritten

  s/\|/_E#S#C_/g for @row_array;                                                     # escape Pipe "|"

  if ($utf8 && $dbmodel ne "SQLITE") {
      $rowlist = Encode::encode_utf8(join('|', @row_array));
  }
  else {
      $rowlist = join('|', @row_array);
  }

  Log3 ($name, 5, "DbRep $name -> row result list:\n$rowlist");

  my $rt = tv_interval($st);                                                         # SQL-Laufzeit ermitteln

  $dbh->disconnect;

  $rowlist = encode_base64($rowlist,"");                                             # Daten müssen als Einzeiler zurückgegeben werden
  my $brt  = tv_interval($bst);                                                      # Background-Laufzeit ermitteln
  $rt      = $rt.",".$brt;
  $err     = q{};

return "$name|$err|$rowlist|$rt|$nrows";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage fetchrows
####################################################################################################
sub DbRep_fetchrowsDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist    = $a[2] ? decode_base64($a[2]) : '';
  my $bt         = $a[3];
  my $nrows      = $a[4];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                     # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                       # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt)  = split ",", $bt;
  my $reading    = AttrVal($name, "reading",        '');
  my $limit      = AttrVal($name, "limit",        1000);
  my $fvfn       = AttrVal($name, "fetchValueFn",   '');

  my $color      = "<html><span style=\"color: #".AttrVal($name, "fetchMarkDuplicates", "000000").";\">";  # Highlighting doppelter DB-Einträge
  $color         =~ s/#// if($color =~ /red|blue|brown|green|orange/);
  my $ecolor     = "</span></html>";                                                                       # Ende Highlighting

  my @row;
  my $reading_runtime_string;

  my @row_array = split("\\|", $rowlist);
  s/_E#S#C_/\|/g for @row_array;                               # escaped Pipe return to "|"

  Log3 ($name, 5, "DbRep $name - row_array decoded:\n @row_array");

  readingsBeginUpdate($hash);
  my ($orow,$nrow,$oval,$nval);
  my $dz  = 1;                                                 # Index des Vorkommens im Selektionsarray
  my $zs  = "";                                                # Zusatz wenn device + Reading + Timestamp von folgenden DS gleich ist UND Value unterschiedlich
  my $zsz = 1;                                                 # Zusatzzähler

  for my $row (@row_array) {
      chomp $row;
      my @a   = split("_ESC_", $row, 6);
      my $dev = $a[0];
      my $rea = $a[1];
      $a[3]   =~ s/:/-/g;                                      # substituieren unsupported characters ":" -> siehe fhem.pl
      my $ts  = $a[2]."_".$a[3];
      my $val = $a[4];
      my $unt = $a[5];
      $val    = $unt ? $val." ".$unt : $val;

      $nrow = $ts.$dev.$rea;
      $nval = $val;

      if($orow) {
          if($orow.$oval eq $nrow.$val) {
              $dz++;
              $zs = "";
              $zsz = 1;
          }
          else {                                                # wenn device + Reading + Timestamp gleich ist UND Value unterschiedlich -> dann Zusatz an Reading hängen
              if(($orow eq $nrow) && ($oval ne $val)) {
                  $zs = "_".$zsz;
                  $zsz++;
              }
              else {
                  $zs = "";
                  $zsz = 1;
              }

              $dz = 1;
          }
      }

      $orow = $nrow;
      $oval = $val;

      if ($reading && AttrVal($hash->{NAME}, "readingNameMap", "")) {
          if($dz > 1 && AttrVal($name, "fetchMarkDuplicates", undef)) {
              $reading_runtime_string = $ts."__".$color.$dz."__".AttrVal($hash->{NAME}, "readingNameMap", "").$zs.$ecolor;
          }
          else {
              $reading_runtime_string = $ts."__".$dz."__".AttrVal($hash->{NAME}, "readingNameMap", "").$zs;
          }
      }
      else {
          if($dz > 1 && AttrVal($name, "fetchMarkDuplicates", undef)) {
              $reading_runtime_string = $ts."__".$color.$dz."__".$dev."__".$rea.$zs.$ecolor;
          }
          else {
              $reading_runtime_string = $ts."__".$dz."__".$dev."__".$rea.$zs;
          }
      }

      if($fvfn) {
          my $VALUE = $val;

          if( $fvfn =~ m/^\s*(\{.*\})\s*$/s ) {
              $fvfn = $1;
          }
          else {
              $fvfn = "";
          }

          if ($fvfn) {
              eval $fvfn;
              $val = $VALUE if(!$@);
          }
      }

      ReadingsBulkUpdateValue($hash, $reading_runtime_string, $val);
  }
  my $sfx = AttrVal("global", "language", "EN");
  $sfx    = $sfx eq "EN" ? "" : "_$sfx";

  ReadingsBulkUpdateValue ($hash, "number_fetched_rows", ($nrows>$limit) ? $nrows-1 : $nrows);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  ReadingsBulkUpdateValue ($hash, "state",
      "<html>done - Warning: present rows exceed specified limit, adjust attribute <a href='https://fhem.de/commandref${sfx}.html#DbRep-attr-limit' target='_blank'>limit</a></html>") if($nrows-$limit>0);
  readingsEndUpdate($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                     # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                                 Doubletten finden und löschen
####################################################################################################
sub DbRep_deldoublets {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $prop    = $paref->{prop};
  my $ts      = $paref->{ts};

  my $utf8    = $hash->{UTF8} // 0;
  my $limit   = AttrVal($name, "limit", 1000);

  my ($sth,$sql,$rowlist,$selspec,$st,$addon,$dsql);

  my $bst = [gettimeofday];                                                         # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my @ts = split("\\|", $ts);                                                       # Timestampstring to Array
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  # mehrfache Datensätze finden
  $selspec = "TIMESTAMP,DEVICE,READING,VALUE,count(*)";
  # $addon   = "GROUP BY TIMESTAMP, DEVICE, READING, VALUE ASC HAVING count(*) > 1";                        # 18.10.2019 / V 8.28.2
  $addon   = "GROUP BY TIMESTAMP, DEVICE, READING, VALUE HAVING count(*) > 1 ORDER BY TIMESTAMP ASC";       # Forum: https://forum.fhem.de/index.php/topic,53584.msg914489.html#msg914489
                                                                                                            # und Forum: https://forum.fhem.de/index.php/topic,104593.msg985007.html#msg985007
  $sql = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,"?","?",$addon);                      # SQL zusammenstellen für DB-Abfrage

  eval { $sth = $dbh->prepare_cached($sql);
       }
       or do { $err = encode_base64($@,"");
               Log3 ($name, 2, "DbRep $name - $@");
               $dbh->disconnect;
               return "$name|$err";
             };

  # DB-Abfrage zeilenweise für jeden Timearray-Eintrag
  my @todel;
  my $ntodel  = 0;
  my $ndel    = 0;
  my $rt      = 0;

  no warnings 'uninitialized';

  for my $row (@ts) {
      my @a                     = split("#", $row);
      my $runtime_string        = $a[0];
      my $runtime_string_first  = $a[1];
      my $runtime_string_next   = $a[2];
      $runtime_string           = encode_base64($runtime_string,"");

      $st = [gettimeofday];                                                              # SQL-Startzeit

      # SQL zusammenstellen für Logausgabe
      my $sql1 = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
      Log3 ($name, 4, "DbRep $name - SQL execute: $sql1");

      eval { $sth->execute($runtime_string_first, $runtime_string_next);
           }
           or do { $err = encode_base64($@,"");
                   Log3 ($name, 2, "DbRep $name - $@");
                   $dbh->disconnect;
                   return "$name|$err";
                 };

      $rt = $rt+tv_interval($st);                                                       # SQL-Laufzeit ermitteln

      # Beginn Löschlogik, Zusammenstellen der zu löschenden DS (warping)
      # Array @warp -> die zu löschenden Datensätze
      my (@warp);
      my $i = 0;

      for my $nr (map { $_->[1]."_ESC_".$_->[2]."_ESC_".($_->[0] =~ s/ /_ESC_/r)."_ESC_".$_->[3]."_|_".($_->[4]-1) } @{$sth->fetchall_arrayref()}) {
          # Reihenfolge geändert in: DEVICE,READING,DATE,TIME,VALUE,count(*)
          if($prop =~ /adviceDelete/x) {
              push(@warp,$i."_".$nr) if($#todel+1 < $limit);                   # die zu löschenden Datensätze (nur zur Anzeige)
          }
          else {
              push(@warp,$i."_".$nr);                                          # Array der zu löschenden Datensätze
          }

          my $c   = (split("|",$nr))[-1];

          Log3 ($name, 4, "DbRep $name - WARP: $nr, ntodel: $ntodel, c: $c");

          $ntodel = $ntodel + $c;

          if ($prop =~ /delete/x) {                                       # delete Datensätze
              my ($dev,$read,$date,$time,$val,$limit) = split(/_ESC_|_\|_/, $nr);
              my $dt = $date." ".$time;
              chomp($val);
              $dev  =~ s/'/''/g;                                        # escape ' with ''
              $read =~ s/'/''/g;                                        # escape ' with ''
              $val  =~ s/'/''/g;                                        # escape ' with ''
              $val  =~ s/\\/\\\\/g if($dbmodel eq "MYSQL");             # escape \ with \\ für MySQL
              $st = [gettimeofday];

              if($dbmodel =~ /MYSQL/x) {
                  $dsql = "delete FROM $table WHERE TIMESTAMP = '$dt' AND DEVICE = '$dev' AND READING = '$read' AND VALUE = '$val' limit $limit;";
              }
              elsif ($dbmodel eq "SQLITE") {                            # Forum: https://forum.fhem.de/index.php/topic,122791.0.html
                  $dsql = "delete FROM $table where rowid in (select rowid from $table WHERE TIMESTAMP = '$dt' AND DEVICE = '$dev' AND READING = '$read' AND VALUE = '$val' LIMIT $limit);";
              }
              elsif ($dbmodel eq "POSTGRESQL") {
                  $dsql = "DELETE FROM $table WHERE ctid = any (array(SELECT ctid FROM $table WHERE TIMESTAMP = '$dt' AND DEVICE = '$dev' AND READING = '$read' AND VALUE = '$val' ORDER BY timestamp LIMIT $limit));";
              }

              Log3 ($name, 4, "DbRep $name - SQL execute: $dsql");

              my $sthd = $dbh->prepare($dsql);

              eval { $sthd->execute();
                   }
                   or do { $err = encode_base64($@,"");
                           Log3 ($name, 2, "DbRep $name - $@");
                           $dbh->disconnect;
                           return "$name|$err";
                         };

              $ndel = $ndel+$sthd->rows;
              $dbh->commit() if(!$dbh->{AutoCommit});

              $rt = $rt+tv_interval($st);
          }

          $i++;
      }

      if(@warp && $prop =~ /adviceDelete/x) {
          push(@todel,@warp);
      }
  }

  Log3 ($name, 3, "DbRep $name - number records identified to delete by \"$hash->{LASTCMD}\": $ntodel") if($ntodel && $prop =~ /advice/);
  Log3 ($name, 3, "DbRep $name - rows deleted by \"$hash->{LASTCMD}\": $ndel") if($ndel);

  my $retn     = $prop =~ /adviceDelete/x ? $ntodel : $ndel;
  my @retarray = $prop =~ /adviceDelete/x ? @todel : " ";

  s/\|/_E#S#C_/g for @retarray;                                                # escape Pipe "|"
  if ($utf8 && @retarray) {
      $rowlist = Encode::encode_utf8(join('|', @retarray));
  }
  elsif (@retarray) {
      $rowlist = join('|', @retarray);
  }
  else {
      $rowlist = 0;
  }

  use warnings;
  Log3 ($name, 5, "DbRep $name -> row result list:\n$rowlist");

  $dbh->disconnect;

  $rowlist = encode_base64($rowlist,"");
  my $brt  = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  $rt      = $rt.",".$brt;
  $err     = q{};

return "$name|$err|$rowlist|$rt|$retn|$prop";
}

####################################################################################################
#                              sequentielle Doubletten löschen
####################################################################################################
sub DbRep_delseqdoubl {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $prop    = $paref->{prop};
  my $ts      = $paref->{ts};

  my $utf8    = $hash->{UTF8} // 0;
  my $limit   = AttrVal($name, "limit", 1000);
  my $var     = AttrVal($name, "seqDoubletsVariance", undef);                     # allgemeine Varianz

  my ($sth,$sql,$rowlist,$nrows,$selspec,$st,$varo,$varu);

  my $bst = [gettimeofday];                                                       # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my $edge = "balanced";                                                          # positive und negative Flankenvarianz spezifizieren
  if($var && $var =~ /EDGE=/) {
      ($var,$edge) = split "EDGE=", $var;
  }

  my ($varpos,$varneg);
  if (defined $var) {
      ($varpos,$varneg) = split " ", $var;
      $varpos           = DbRep_trim($varpos);
      $varneg           = $varpos if(!$varneg);
      $varneg           = DbRep_trim($varneg);
  }

  Log3 ($name, 4, "DbRep $name - delSeqDoublets params -> positive variance: ".(defined $varpos ? $varpos : "")
        .", negative variance: ".(defined $varneg ? $varneg : "").", EDGE: $edge");

  my @ts = split "\\|", $ts;                                                     # Timestampstring to Array
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  $selspec = "DEVICE,READING,TIMESTAMP,VALUE";

  # SQL zusammenstellen für DB-Abfrage
  $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, "?", "?", "ORDER BY DEVICE,READING,TIMESTAMP ASC");
  $sth = $dbh->prepare_cached($sql);

  # DB-Abfrage zeilenweise für jeden Timearray-Eintrag
  my @remain;
  my @todel;
  my $nremain = 0;
  my $ntodel  = 0;
  my $ndel    = 0;
  my $rt      = 0;

  no warnings 'uninitialized';

  for my $row (@ts) {
      my @a                     = split "#", $row;
      my $runtime_string        = $a[0];
      my $runtime_string_first  = $a[1];
      my $runtime_string_next   = $a[2];
      $runtime_string           = encode_base64($runtime_string,"");

      $st = [gettimeofday];                                                            # SQL-Startzeit

      # SQL zusammenstellen für Logausgabe
      my $sql1 = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,$runtime_string_first,$runtime_string_next,'');
      Log3 ($name, 4, "DbRep $name - SQL execute: $sql1");

      eval{$sth->execute($runtime_string_first, $runtime_string_next);};
      if ($@) {
          $err = encode_base64($@,"");
          Log3 ($name, 2, "DbRep $name - $@");
          $dbh->disconnect;
          return "$name|$err";
      }

      $rt = $rt+tv_interval($st);                                                     # SQL-Laufzeit ermitteln

      # Beginn Löschlogik, Zusammenstellen der löschenden DS (warping)
      # Array @sel -> die VERBLEIBENDEN Datensätze, @warp -> die zu löschenden Datensätze
      my (@sel,@warp);
      my ($or,$oor,$odev,$oread,$oval,$ooval,$ndev,$nread,$nval);
      my $i = 0;

      for my $nr (map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3] } @{$sth->fetchall_arrayref()}) {
          ($ndev,$nread,undef,undef,$nval) = split "_ESC_", $nr;                      # Werte des aktuellen Elements
          $or                              = pop @sel;                                # das letzte Element der Liste
          ($odev,$oread,undef,undef,$oval) = split "_ESC_", $or;                      # Value des letzten Elements

          if (looks_like_number($oval) && defined $varpos && defined $varneg) {       # unterschiedliche Varianz +/- für numerische Werte
              $varo = $oval + $varpos;
              $varu = $oval - $varneg;
          }
          elsif (looks_like_number($oval) && defined $varpos && !defined $varneg) {   # identische Varianz +/- für numerische Werte
              $varo = $oval + $varpos;
              $varu = $oval - $varpos;
          }
          else {
              undef $varo;
              undef $varu;
          }

          $oor   = pop @sel;                                         # das vorletzte Element der Liste
          $ooval = (split '_ESC_', $oor)[-1];                        # Value des vorletzten Elements

          if ($ndev.$nread ne $odev.$oread) {
              $i = 0;                                                # neues Device/Reading in einer Periode -> ooor soll erhalten bleiben
              push (@sel,$oor) if($oor);
              push (@sel,$or) if($or);
              push (@sel,$nr);
          }
          elsif ($i>=2 && ($ooval eq $oval && $oval eq $nval) ||
                ($i>=2 && $varo   && $varu && ($ooval <= $varo) &&
                ($varu <= $ooval) && ($nval <= $varo) && ($varu <= $nval)) ) {

              if ($edge =~ /negative/i && ($ooval > $oval)) {
                  push (@sel,$oor);                                  # negative Flanke -> der fallende DS und desssen Vorgänger
                  push (@sel,$or);                                   # werden behalten obwohl im Löschkorridor
                  push (@sel,$nr);
              }
              elsif ($edge =~ /positive/i && ($ooval < $oval)) {
                  push (@sel,$oor);                                  # positive Flanke -> der steigende DS und desssen Vorgänger
                  push (@sel,$or);                                   # werden behalten obwohl im Löschkorridor
                  push (@sel,$nr);
              }
              else {
                  push (@sel,$oor);                                  # Array der zu behaltenden Datensätze
                  push (@sel,$nr);                                   # Array der zu behaltenden Datensätze
                  push (@warp,$or);                                  # Array der zu löschenden Datensätze
              }

              if ($prop =~ /delete/ && $or) {                         # delete Datensätze
                  my ($dev,$read,$date,$time,$val) = split "_ESC_", $or;
                  my $dt                           = $date." ".$time;
                  chomp($val);
                  $dev  =~ s/'/''/g;                                 # escape ' with ''
                  $read =~ s/'/''/g;                                 # escape ' with ''
                  $val  =~ s/'/''/g;                                 # escape ' with ''
                  $st   = [gettimeofday];
                  my $dsql = "delete FROM $table where TIMESTAMP = '$dt' AND DEVICE = '$dev' AND READING = '$read' AND VALUE = '$val';";
                  my $sthd = $dbh->prepare($dsql);

                  Log3 ($name, 4, "DbRep $name - SQL execute: $dsql");

                  eval {$sthd->execute();};
                  if ($@) {
                      $err = encode_base64($@,"");
                      Log3 ($name, 2, "DbRep $name - $@");
                      $dbh->disconnect;
                      return "$name|$err";
                  }

                  $ndel = $ndel+$sthd->rows;
                  $dbh->commit() if(!$dbh->{AutoCommit});

                  $rt = $rt+tv_interval($st);
              }
          }
          else {
              push (@sel,$oor) if($oor);
              push (@sel,$or)  if($or);
              push (@sel,$nr);
          }

          $i++;
      }

      if(@sel && $prop =~ /adviceRemain/) {                      # die verbleibenden Datensätze nach Ausführung (nur zur Anzeige)
          push(@remain,@sel) if($#remain+1 < $limit);
      }

      if(@warp && $prop =~ /adviceDelete/) {                     # die zu löschenden Datensätze (nur zur Anzeige)
          push(@todel,@warp) if($#todel+1 < $limit);
      }

      $nremain = $nremain + $#sel+1  if(@sel);
      $ntodel  = $ntodel  + $#warp+1 if(@warp);
      my $sum  = $nremain + $ntodel;

      Log3 ($name, 3, "DbRep $name - rows analyzed by \"$hash->{LASTCMD}\": $sum") if($sum && $prop =~ /advice/);
  }

  Log3 ($name, 3, "DbRep $name - rows deleted by \"$hash->{LASTCMD}\": $ndel") if($ndel);

  my $retn = $prop =~ /adviceRemain/ ? $nremain :
             $prop =~ /adviceDelete/ ? $ntodel  :
             $ndel;

  my @retarray = $prop =~ /adviceRemain/ ? @remain :
                 $prop =~ /adviceDelete/ ? @todel  :
                 " ";

  s/\|/_E#S#C_/g for @retarray;                                             # escape Pipe "|"

  if ($utf8 && @retarray) {
      $rowlist = Encode::encode_utf8(join('|', @retarray));
  }
  elsif(@retarray) {
      $rowlist = join('|', @retarray);
  }
  else {
      $rowlist = 0;
  }

  use warnings;
  Log3 ($name, 5, "DbRep $name - row result list:\n$rowlist");

  $dbh->disconnect;

  $rowlist = encode_base64($rowlist,"");                                    # Daten müssen als Einzeiler zurückgegeben werden

  my $brt = tv_interval($bst);                                              # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = q{};

return "$name|$err|$rowlist|$rt|$retn|$prop";
}

####################################################################################################
#                      Auswertungsroutine delSeqDoublets / delDoublets
####################################################################################################
sub DbRep_deldoubl_Done {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist    = $a[2] ? decode_base64($a[2]) : '';
  my $bt         = $a[3];
  my $nrows      = $a[4];
  my $prop       = $a[5];

  my $reading    = AttrVal($name, "reading",  '');
  my $limit      = AttrVal($name, "limit",  1000);

  my $hash       = $defs{$name};

  my @row;
  my $l = 1;
  my $reading_runtime_string;

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                     # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                       # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  no warnings 'uninitialized';

  readingsBeginUpdate($hash);

  if ($prop !~ /delete/ && $rowlist) {
      my @row_array = split("\\|", $rowlist);
      s/_E#S#C_/\|/g for @row_array;                                    # escaped Pipe return to "|"

      Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");

      for my $row (@row_array) {
          last if($l >= $limit);
          my @a   = split("_ESC_", $row, 5);
          my $dev = $a[0];
          my $rea = $a[1];
          $a[3]   =~ s/:/-/g;                                           # substituieren unsupported characters ":" -> siehe fhem.pl
          my $ts  = $a[2]."_".$a[3];
          my $val = $a[4];

          if ($reading && AttrVal($hash->{NAME}, "readingNameMap", "")) {
              $reading_runtime_string = $ts."__".AttrVal($hash->{NAME}, "readingNameMap", "") ;
          }
          else {
              $reading_runtime_string = $ts."__".$dev."__".$rea;
          }

          ReadingsBulkUpdateValue($hash, $reading_runtime_string, $val);
          $l++;
      }
  }

  use warnings;

  my $sfx = AttrVal("global", "language", "EN");
  $sfx    = $sfx eq "EN" ? "" : "_$sfx";

  my $rnam = $prop =~ /adviceRemain/ ? "number_rows_to_remain" :
             $prop =~ /adviceDelete/ ? "number_rows_to_delete" :
             "number_rows_deleted";

  ReadingsBulkUpdateValue ($hash, "$rnam", "$nrows");
  ReadingsBulkUpdateValue ($hash, 'state',
                           "<html>done - Warning: not all items are shown, adjust attribute <a href='https://fhem.de/commandref${sfx}.html#limit' target='_blank'>limit</a> if you want see more</html>") if($l >= $limit);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                     # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Funktion expfile
####################################################################################################
sub DbRep_expfile {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $table   = $paref->{table};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $rsf     = $paref->{rsf};
  my $file    = $paref->{prop};
  my $ts      = $paref->{ts};

  my ($sth,$sql);

  my $bst = [gettimeofday];                                            # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  if (!$rsf) {                                                        # ältesten Datensatz der DB ermitteln
      Log3 ($name, 4, "DbRep $name - no time limits defined - determine the oldest record ...");

      $paref->{dbh} = $dbh;
      $rsf          = _DbRep_getInitData_mints ($paref);
  }

  my $ml;
  my $part = ".";

  if($file =~ /MAXLINES=/) {
       my ($ar, $hr) = parseParams($file);
       $file         = $ar->[0];
       $ml           = $hr->{MAXLINES};
       $part         = "_part1.";
  }

  $rsf        =~ s/[:\s]/_/g;
  my ($f,$e)  = $file =~ /(.*)\.(.*)/;
  $e        //= "";
  $f          =~ s/%TSB/$rsf/g;
  my @t       = localtime;
  $f          = ResolveDateWildcards($f, @t);
  my $outfile = $f.$part.$e;

  Log3 ($name, 4, "DbRep $name - Export data to file: $outfile ".($ml ? "splitted to parts of $ml lines" : "")  );

  if (open(FH, ">", $outfile)) {
      binmode (FH);
  }
  else {
      $err = encode_base64("could not open ".$outfile.": ".$!,"");
      return "$name|$err";
  }

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                            # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  my @ts = split("\\|", $ts);
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  my $st = [gettimeofday];                                                            # SQL-Startzeit

  my $arrstr;
  my ($nrows,$frows) = (0,0);
  my $p              = 2;
  my $addon          = "ORDER BY TIMESTAMP";

  no warnings 'uninitialized';

  for my $row (@ts) {                                                                 # DB-Abfrage zeilenweise für jeden Array-Eintrag
      my @a                    = split("#", $row);
      my $runtime_string       = $a[0];
      my $runtime_string_first = $a[1];
      my $runtime_string_next  = $a[2];

      if ($IsTimeSet || $IsAggrSet) {
          $sql = DbRep_createSelectSql($hash, $table, "TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT", $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
      }
      else {
          $sql = DbRep_createSelectSql($hash, $table, "TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT", $device, $reading, undef, undef, $addon);
      }

      Log3 ($name, 4, "DbRep $name - SQL execute: $sql");

      eval{ $sth = $dbh->prepare($sql);
            $sth->execute();
            1;
          }
          or do { $err = encode_base64($@,"");
                  Log3 ($name, 2, "DbRep $name - $@");
                  $dbh->disconnect;
                  return "$name|$err";
          };

      while (my $row = $sth->fetchrow_arrayref) {
          print FH DbRep_charfilter(join(',', map { s{"}{""}g; "\"$_\"";} @$row)), "\n";
          Log3 ($name, 5, "DbRep $name -> write row:  @$row");

          $nrows++;                                                                # Anzahl der Datensätze
          $frows++;

          if($ml && $frows >= $ml) {
              Log3 ($name, 3, "DbRep $name - Number of exported datasets from $hash->{DATABASE} to file $outfile: ".$frows);
              close(FH);
              $outfile = $f."_part$p.".$e;

              if (open(FH, ">", $outfile)) {
                  binmode (FH);
              }
              else {
                  $err = encode_base64("could not open ".$outfile.": ".$!,"");
                  return "$name|$err";
              }

              $p++;
              $frows = 0;
          }
      }
  }

  close(FH);

  Log3 ($name, 3, "DbRep $name - Number of exported datasets from $hash->{DATABASE} to file $outfile: ".$frows);

  my $rt = tv_interval($st);                                                       # SQL-Laufzeit ermitteln

  $sth->finish;
  $dbh->disconnect;

  my $brt = tv_interval($bst);                                                     # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

return "$name|$err|$nrows|$rt|$device|$reading|$outfile";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Funktion expfile
####################################################################################################
sub DbRep_expfile_Done {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $nrows      = $a[2];
  my $bt         = $a[3];
  my $device     = $a[4];
  my $reading    = $a[5];
  my $outfile    = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "export");                             # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                       # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;
  $device       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading      =~ s/[^A-Za-z\/\d_\.-]/\//g;

  no warnings 'uninitialized';

  my ($ds,$rds)     = ("","");
  $ds               = $device." -- "  if ($device);
  $rds              = $reading." -- " if ($reading);
  my $export_string = $ds.$rds." -- ROWS EXPORTED TO FILE(S) -- ";

  readingsBeginUpdate      ($hash);
  ReadingsBulkUpdateValue  ($hash, $export_string, $nrows);
  ReadingsBulkUpdateTime   ($hash, $brt, $rt);
  readingsEndUpdate        ($hash, 1);

  DbRep_afterproc          ($hash, "export");                             # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd       ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Funktion impfile
####################################################################################################
sub DbRep_impfile {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $table  = $paref->{table};
  my $rsf    = $paref->{rsf};
  my $infile = $paref->{prop};

  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  my $bst = [gettimeofday];                                                          # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  if (!$rsf) {                                                                       # ältesten Datensatz der DB ermitteln
      Log3 ($name, 4, "DbRep $name - no time limits defined - determine the oldest record ...");

      $paref->{dbh} = $dbh;
      $rsf          = _DbRep_getInitData_mints ($paref);
  }

  my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);           # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK

  $rsf    =~ s/[:\s]/_/g;
  $infile =~ s/%TSB/$rsf/g;
  my @t   = localtime;
  $infile = ResolveDateWildcards($infile, @t);

  if (open(FH, "<", "$infile")) {
      binmode (FH);
  }
  else {
      $err = encode_base64("could not open ".$infile.": ".$!,"");
      return "$name|$err";
  }

  no warnings 'uninitialized';

  my $st = [gettimeofday];                                                           # SQL-Startzeit

  my $al;
  # Datei zeilenweise einlesen und verarbeiten !
  # Beispiel Inline:
  # "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""

  # insert history mit/ohne primary key
  my $sql;
  if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
      $sql = "INSERT IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
      $sql = "INSERT OR IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING";
  }
  else {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }

  my $sth;
  eval { $sth = $dbh->prepare_cached($sql);
       }
       or do { $err = encode_base64($@,"");
               Log3 ($name, 2, "DbRep $name - $@");
               $dbh->disconnect();
               return "$name|$err";
             };

  $err = DbRep_beginDatabaseTransaction ($name, $dbh, "begin import as one transaction");
  return "$name|$err" if ($err);

  my $irowdone  = 0;
  my $irowcount = 0;
  my $warn      = 0;

  while (<FH>) {
      $al = $_;
      chomp $al;
      my @alarr = split("\",\"", $al);

      for (@alarr) {
          tr/"//d;
      }

      my $i_timestamp = DbRep_trim($alarr[0]);
      my $i_device    = DbRep_trim($alarr[1]);
      my $i_type      = DbRep_trim($alarr[2]);
      my $i_event     = DbRep_trim($alarr[3]);
      my $i_reading   = DbRep_trim($alarr[4]);
      my $i_value     = DbRep_trim($alarr[5]);
      my $i_unit      = DbRep_trim($alarr[6] ? $alarr[6]: "");

      $irowcount++;
      next if(!$i_timestamp);                                                             #leerer Datensatz

      my ($i_date, $i_time) = split(" ",$i_timestamp);                                    # check ob TIMESTAMP Format ok ?

      if ($i_date !~ /(\d{4})-(\d{2})-(\d{2})/ || $i_time !~ /(\d{2}):(\d{2}):(\d{2})/) {
          $err = encode_base64("Format of date/time is not valid in row $irowcount of $infile. Must be format \"YYYY-MM-DD HH:MM:SS\" !","");
          Log3 ($name, 2, "DbRep $name -> ERROR - Import from file $infile was not done. Invalid date/time field format in row $irowcount.");
          close(FH);
          $dbh->rollback;
          return "$name|$err";
      }

      # Daten auf maximale Länge (entsprechend der Feldlänge in DbLog DB create-scripts) beschneiden wenn nicht SQLite
      if ($dbmodel ne 'SQLITE') {
          $i_device   = substr($i_device,0, $hash->{HELPER}{DBREPCOL}{DEVICE});
          $i_event    = substr($i_event,0, $hash->{HELPER}{DBREPCOL}{EVENT});
          $i_reading  = substr($i_reading,0, $hash->{HELPER}{DBREPCOL}{READING});
          $i_value    = substr($i_value,0, $hash->{HELPER}{DBREPCOL}{VALUE});
          $i_unit     = substr($i_unit,0, $hash->{HELPER}{DBREPCOL}{UNIT}) if($i_unit);
      }

      Log3 ($name, 5, "DbRep $name -> data to insert Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");

      if($i_timestamp && $i_device && $i_reading) {
          eval { $sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);
               }
               or do { $err = encode_base64($@,"");
                       Log3 ($name, 2, "DbRep $name - Failed to insert new dataset into database: $@");
                       close(FH);

                       $dbh->rollback;
                       $dbh->disconnect;

                       return "$name|$err";
                     };

          $irowdone++;
      }
      else {
          my $c = !$i_timestamp ? "field \"timestamp\" is empty" :
                  !$i_device    ? "field \"device\" is empty"    :
                  "field \"reading\" is empty";
          $err  = encode_base64("format error in in row $irowcount of $infile - cause: $c","");

          Log3 ($name, 2, "DbRep $name -> ERROR - Import of datasets NOT done. Formaterror in row $irowcount of $infile - cause: $c");

          close(FH);

          $dbh->rollback;
          $dbh->disconnect;

          return "$name|$err";
      }
  }

  $err = DbRep_commitOnly ($name, $dbh, "import committed");
  return "$name|$err" if ($err);

  $dbh->disconnect;

  close(FH);

  my $rt  = tv_interval($st);                                  # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                 # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;

return "$name|$err|$irowdone|$rt|$infile";
}

####################################################################################################
#             Auswertungsroutine der nichtblockierenden DB-Funktion impfile
####################################################################################################
sub DbRep_impfile_Done {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $irowdone   = $a[2];
  my $bt         = $a[3];
  my $infile     = $a[4];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "import");                                # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                          # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  no warnings 'uninitialized';

  my $import_string = " -- ROWS IMPORTED FROM FILE -- ";

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, $import_string, $irowdone);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Number of imported datasets to $hash->{DATABASE} from file $infile: $irowdone");

  DbRep_afterproc         ($hash, "import");                             # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                       # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage sqlCmd - generischer SQL-Befehl - name | opt | sqlcommand
####################################################################################################
# set logdbrep sqlCmd select count(*) from history
# set logdbrep sqlCmd select DEVICE,count(*) from history group by DEVICE HAVING count(*) > 10000
sub DbRep_sqlCmd {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $opt     = $paref->{opt};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $rsf     = $paref->{rsf};
  my $rsn     = $paref->{rsn};
  my $cmd     = $paref->{prop};

  my $srs = AttrVal($name, "sqlResultFieldSep", "|");

  my $bst = [gettimeofday];                                                          # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name);
  return "$name|$err" if ($err);

  no warnings 'uninitialized';

  $cmd =~ s/\;\;/ESC_ESC_ESC/gx;                                                     # ersetzen von escapeten ";" (;;)

  $cmd   .= ";" if ($cmd !~ m/\;$/x);
  my $sql = $cmd;

  my @pms;

  $err = _DbRep_setSessAttrVars ($name, $dbh);
  return "$name|$err" if ($err);

  $err = _DbRep_setSessVars ($name, $dbh, \$sql);
  return "$name|$err" if ($err);

  $err = _DbRep_setSessPragma ($name, $dbh, \$sql);
  return "$name|$err" if ($err);

  $err = _DbRep_execSessPrepare ($name, $dbh, \$sql);
  return "$name|$err" if ($err);

  # Ersetzung von Schlüsselwörtern für Timing, Gerät, Lesen (unter Verwendung der Attributsyntax)
  ($err, $sql) = _DbRep_sqlReplaceKeywords ( { hash    => $hash,
                                               sql     => $sql,
                                               device  => $device,
                                               reading => $reading,
                                               dbmodel => $dbmodel,
                                               rsf     => $rsf,
                                               rsn     => $rsn
                                             }
                                           );
  return "$name|$err" if ($err);

  $sql =~ s/ESC_ESC_ESC/;/gx;                                                      # wiederherstellen von escapeten ";" -> umwandeln von ";;" in ";"

  my $st = [gettimeofday];                                                         # SQL-Startzeit

  my ($sth,$r);

  ($err, $sth, $r) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
  return "$name|$err" if ($err);

  my (@rows,$row,@head);
  my $nrows = 0;

  if($sql =~ m/^\s*(call|explain|select|pragma|show|describe)/is) {
      @head = map { uc($sth->{NAME}[$_]) } keys @{$sth->{NAME}};                   # https://metacpan.org/pod/DBI#NAME1
      if (@head) {
          $row = join("$srs", @head);
          push(@rows, $row);
      }

      while (my @line = $sth->fetchrow_array()) {
          Log3 ($name, 4, "DbRep $name - SQL result: @line");
          $row = join("$srs", @line);

          $row =~ s/§/|°escaped°|/g;                                              # join Delimiter "§" escapen

          push(@rows, $row);
          $nrows++;                                                               # Anzahl der Datensätze
      }
  }
  else {
      $nrows = $sth->rows;

      $err = DbRep_commitOnly ($name, $dbh);
      return "$name|$err" if ($err);

      push(@rows, $r);
      my $com = (split(" ",$sql, 2))[0];

      Log3 ($name, 3, "DbRep $name - Number of entries processed in db $hash->{DATABASE}: $nrows by $com");
  }

  $sth->finish;

  my $rt = tv_interval($st);                                                       # SQL-Laufzeit ermitteln

  $dbh->disconnect;

  my $rowstring = join("§", @rows);                                                # Daten müssen als Einzeiler zurückgegeben werden
  $rowstring    = encode_base64($rowstring,"");

  $cmd =~ s/ESC_ESC_ESC/;;/gx;                                                     # wiederherstellen der escapeten ";" -> ";;"

  my $brt = tv_interval($bst);                                                     # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = q{};

return "$name|$err|$rowstring|$opt|$cmd|$nrows|$rt";
}

####################################################################################################
#     blockierende DB-Abfrage
#     liefert Ergebnis sofort zurück, setzt keine Readings
####################################################################################################
sub DbRep_sqlCmdBlocking {
  my $name   = shift;
  my $cmd    = shift;

  my $hash   = $defs{$name};
  my $srs    = AttrVal ($name, 'sqlResultFieldSep',  '|');
  my $to     = AttrVal ($name, 'timeout', $dbrep_deftobl);

  my ($ret);

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name);
  if ($err) {
      _DbRep_sqlBlckgErrorState ($hash, $err);
      return $err;
  }

  $cmd =~ s/\;\;/ESC_ESC_ESC/gx;                                                     # ersetzen von escapeten ";" (;;)

  $cmd   .= ";" if ($cmd !~ m/\;$/x);
  my $sql = $cmd;

  Log3 ($name, 4, "DbRep $name - -------- New selection --------- ");
  Log3 ($name, 4, "DbRep $name - sqlCmdBlocking Command:\n$sql");

  my @pms;

  $err = _DbRep_setSessAttrVars ($name, $dbh);
  if ($err) {
      _DbRep_sqlBlckgErrorState ($hash, $err);
      return $err;
  }

  $err = _DbRep_setSessVars ($name, $dbh, \$sql);
  if ($err) {
      _DbRep_sqlBlckgErrorState ($hash, $err);
      return $err;
  }

  $err = _DbRep_setSessPragma ($name, $dbh, \$sql);
  if ($err) {
      _DbRep_sqlBlckgErrorState ($hash, $err);
      return $err;
  }

  $err = _DbRep_execSessPrepare ($name, $dbh, \$sql);
  if ($err) {
      _DbRep_sqlBlckgErrorState ($hash, $err);
      return $err;
  }

  my $st = [gettimeofday];                                                        # SQL-Startzeit

  my $totxt = qq{Timeout occured (limit: $to seconds). You may be able to adjust the "Timeout" attribute.};

  my ($sth,$r,$failed);

  eval {                                                                          # outer eval fängt Alarm auf, der gerade vor diesem Alarm feuern könnte(0)
      POSIX::sigaction(SIGALRM, POSIX::SigAction->new(sub {die "Timeout\n"}));    # \n ist nötig !

      alarm($to);
      eval {
          $sth = $dbh->prepare($sql);
          $r   = $sth->execute();
      };
      alarm(0);                                                                   # Alarm aufheben (wenn der Code schnell lief)

      if ($@) {
          if($@ eq "Timeout\n") {                                                 # timeout
              $failed = $totxt;
          }
          else {                                                                  # ein anderer Fehler
              $failed = $@;
          }
      }
      1;

  }
  or $failed = $@;

  alarm(0);                                                                      # Schutz vor Race Condition

  if ($failed) {
      $err = $failed eq "Timeout\n" ? $totxt : $failed;

      Log3 ($name, 2, "DbRep $name - $err");

      my $encerr = encode_base64($err, "");

      $sth->finish if($sth);
      $dbh->disconnect;

      _DbRep_sqlBlckgErrorState ($hash, $encerr);

      return $err;
  }

  my $nrows = 0;
  if($sql =~ m/^\s*(call|explain|select|pragma|show|describe)/is) {
      while (my @line = $sth->fetchrow_array()) {
          Log3 ($name, 4, "DbRep $name - SQL result: @line");
          $ret .= "\n" if($nrows);                                              # Forum: #103295
          $ret .= join("$srs", @line);
          $nrows++;                                                             # Anzahl der Datensätze
      }
  }
  else {
      $nrows = $sth->rows;

      $err = DbRep_commitOnly ($name, $dbh);
      if ($err) {
          _DbRep_sqlBlckgErrorState ($hash, $err);
          return $err;
      }

      $ret = $nrows;
  }

  $sth->finish;
  $dbh->disconnect;

  my $rt  = tv_interval($st);                                                   # SQL-Laufzeit ermitteln
  my $com = (split " ", $sql, 2)[0];

  Log3 ($name, 4, "DbRep $name - Number of entries processed in db $hash->{DATABASE}: $nrows");

  readingsBeginUpdate         ($hash);

  if (defined $data{DbRep}{$name}{sqlcache}{temp}) {                # SQL incl. Formatierung aus Zwischenspeicherzwischenspeichern
      my $tmpsql = delete $data{DbRep}{$name}{sqlcache}{temp};
      ReadingsBulkUpdateValue ($hash, 'sqlCmd', $tmpsql);
  }

  ReadingsBulkUpdateTimeState ($hash, undef, $rt, 'done');
  readingsEndUpdate           ($hash, 1);

return $ret;
}

################################################################
#   Set Session Variablen "SET" oder PRAGMA aus
#   Attribut "sqlCmdVars"
################################################################
sub _DbRep_setSessAttrVars {
  my $name = shift;
  my $dbh  = shift;

  my $vars = AttrVal($name, "sqlCmdVars", "");                                       # Set Session Variablen "SET" oder PRAGMA aus Attribut "sqlCmdVars"

  if ($vars) {
      my @pms = split ';', $vars;

      for my $pm (@pms) {
          if($pm !~ /PRAGMA|SET/i) {
              next;
          }

          $pm = ltrim($pm).';';
          $pm =~ s/ESC_ESC_ESC/;/gx;                                                 # wiederherstellen von escapeten ";" -> umwandeln von ";;" in ";"

          (my $err, undef) = DbRep_dbhDo ($name, $dbh, $pm, "Set VARIABLE or PRAGMA: $pm");
          return $err if ($err);
      }
  }

return;
}

################################################################
# Abarbeitung von Session Variablen vor einem SQL-Statement
# z.B. SET  @open:=NULL, @closed:=NULL; Select ...
################################################################
sub _DbRep_setSessVars {
  my $name   = shift;
  my $dbh    = shift;
  my $sqlref = shift;

  if(${$sqlref} =~ /^\s*SET.*;/i) {
      my @pms    = split ';', ${$sqlref};
      ${$sqlref} = q{};

      for my $pm (@pms) {
          if($pm !~ /SET/i) {
              ${$sqlref} .= $pm.';';
              next;
          }

          $pm = ltrim($pm).';';
          $pm =~ s/ESC_ESC_ESC/;/gx;                                                # wiederherstellen von escapeten ";" -> umwandeln von ";;" in ";"

          (my $err, undef) = DbRep_dbhDo ($name, $dbh, $pm, "Set SQL session variable: $pm");
          return $err if ($err);
      }
  }

return;
}

################################################################
# Abarbeitung aller Pragmas vor einem SQLite Statement,
# SQL wird extrahiert wenn Pragmas im SQL vorangestellt sind
################################################################
sub _DbRep_setSessPragma {
  my $name   = shift;
  my $dbh    = shift;
  my $sqlref = shift;

  if(${$sqlref} =~ /^\s*PRAGMA.*;/i) {
      my @pms    = split ';', ${$sqlref};
      ${$sqlref} = q{};

      for my $pm (@pms) {
          if($pm !~ /PRAGMA.*=/i) {                                                 # PRAGMA ohne "=" werden als SQL-Statement mit Abfrageergebnis behandelt
              ${$sqlref} .= $pm.';';
              next;
          }

          $pm = ltrim($pm).';';
          $pm =~ s/ESC_ESC_ESC/;/gx;                                                # wiederherstellen von escapeten ";" -> umwandeln von ";;" in ";"

          (my $err, undef) = DbRep_dbhDo ($name, $dbh, $pm, "Exec PRAGMA Statement: $pm");
          return $err if ($err);
      }
  }

return;
}

####################################################################
# Abarbeitung von PREPARE statement als Befehl als Bestandteil
# des SQL
# Forum: #114293  / https://forum.fhem.de/index.php?topic=114293.0
# z.B. PREPARE statement FROM @CMD
####################################################################
sub _DbRep_execSessPrepare {
  my $name   = shift;
  my $dbh    = shift;
  my $sqlref = shift;

  if(${$sqlref} =~ /^\s*PREPARE.*;/i) {
      my @pms    = split ';', ${$sqlref};
      ${$sqlref} = q{};

      for my $pm (@pms) {
          if($pm !~ /PREPARE/i) {
              ${$sqlref} .= $pm.';';
              next;
          }

          $pm = ltrim($pm).';';
          $pm =~ s/ESC_ESC_ESC/;/gx;                                                # wiederherstellen von escapeten ";" -> umwandeln von ";;" in ";"

          (my $err, undef) = DbRep_dbhDo ($name, $dbh, $pm, "Exec PREPARE statement: $pm");
          return $err if ($err);
      }
  }

return;
}

####################################################################
#  Error -> Readings errortext und state
####################################################################
sub _DbRep_sqlBlckgErrorState {
  my $hash = shift;
  my $err  = shift;

  my $name = $hash->{NAME};
  $err     = decode_base64 ($err);

  Log3 ($name, 2, "DbRep $name - ERROR - $err");

  readingsBeginUpdate     ($hash);

  if (defined $data{DbRep}{$name}{sqlcache}{temp}) {                # SQL incl. Formatierung aus Zwischenspeicherzwischenspeichern
      my $tmpsql = delete $data{DbRep}{$name}{sqlcache}{temp};
      ReadingsBulkUpdateValue ($hash, 'sqlCmd', $tmpsql);
  }

  ReadingsBulkUpdateValue ($hash, 'errortext',    $err);
  ReadingsBulkUpdateValue ($hash, 'state',     'error');
  readingsEndUpdate       ($hash, 1);

return;
}

####################################################################################################
#        Ersetzung von Schlüsselwörtern für Time*, Devices und Readings
#        in SQL-Statements (unter Verwendung der Attributsyntax)
####################################################################################################
sub _DbRep_sqlReplaceKeywords {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $sql     = $paref->{sql};
  my $device  = $paref->{device};
  my $reading = $paref->{reading};
  my $dbmodel = $paref->{dbmodel};
  my $rsf     = $paref->{rsf};
  my $rsn     = $paref->{rsn};

  my $err  = q{};
  my $name = $hash->{NAME};
  my $sfx  = AttrVal("global", "language", "EN");
  $sfx     = $sfx eq 'EN' ? '' : "_$sfx";

  $sql =~ s/§timestamp_begin§/'$rsf'/g;
  $sql =~ s/§timestamp_end§/'$rsn'/g;

  my $rdspec;

  my @keywords = qw(device reading);

  for my $kw (@keywords) {
      next if ($sql !~ /§${kw}§/xs);

      my $vna = $kw eq "device"  ? $device  :
                $kw eq "reading" ? $reading :
                '';

      if ($vna eq "%") {
          $err = qq{You must specify ${kw}(s) in attribute "${kw}" if you use the placeholder "§${kw}§" in your statement};

          Log3 ($name, 2, "DbRep $name - ERROR - $err");

          $err = qq{<html> $err </html>};
          $err =~ s/"${kw}"/<a href='https:\/\/fhem.de\/commandref${sfx}.html#${kw}' target='_blank'>${kw}<\/a>/xs;
          $err = encode_base64($err,"");
          return $err;
      }

      $rdspec = DbRep_createCommonSql( {hash => $hash, ${kw} => $vna, dbmodel => $dbmodel} );
      $rdspec = (split /AND\s(?:1|true)/xis, $rdspec)[0];
      $sql    =~ s/§${kw}§/$rdspec/xg;
  }

return ($err, $sql);
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage sqlCmd
####################################################################################################
sub DbRep_sqlCmdDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rowstring  = $a[2] ? decode_base64($a[2]) : '';
  my $opt        = $a[3];
  my $cmd        = $a[4];
  my $nrows      = $a[5];
  my $bt         = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  my $tmpsql = $data{DbRep}{$name}{sqlcache}{temp};                                    # SQL incl. Formatierung aus Zwischenspeicher holen

  if ($err) {
    readingsBeginUpdate     ($hash);
    ReadingsBulkUpdateValue ($hash, 'sqlCmd',    $tmpsql);
    ReadingsBulkUpdateValue ($hash, "errortext", $err   );
    ReadingsBulkUpdateValue ($hash, "state",     "error");
    readingsEndUpdate       ($hash, 1);

    DbRep_afterproc         ($hash, $hash->{LASTCMD});                                 # Befehl nach Procedure ausführen
    DbRep_nextMultiCmd      ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

    return;
  }

  DbRep_addSQLcmdCache ($name);                                                        # Drop-Down Liste bisherige sqlCmd-Befehle füllen und in Key-File sichern

  my ($rt,$brt)  = split ",", $bt;
  my $srf        = AttrVal($name, "sqlResultFormat", "separated");
  my $srs        = AttrVal($name, "sqlResultFieldSep", "|");

  Log3 ($name, 5, "DbRep $name - SQL result decoded: $rowstring") if($rowstring);

  no warnings 'uninitialized';

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, 'sqlCmd', $tmpsql);
  ReadingsBulkUpdateValue ($hash, 'sqlResultNumRows', $nrows);

  if ($srf eq "sline") {
      $rowstring =~ s/§/]|[/g;
      $rowstring =~ s/\|°escaped°\|/§/g;
      ReadingsBulkUpdateValue ($hash, "SqlResult", $rowstring);
  }
  elsif ($srf eq "table") {
      my $res = "<html><table border=2 bordercolor='darkgreen' cellspacing=0>";
      my @rows = split( /§/, $rowstring );
      my $row;

      for $row ( @rows ) {
          $row =~ s/\|°escaped°\|/§/g;
          $row =~ s/$srs/\|/g if($srs !~ /\|/);
          $row =~ s/\|/<\/td><td style='padding-right:5px;padding-left:5px;text-align: right;'>/g;
          $res .= "<tr><td style='padding-right:5px;padding-left:5px;text-align: right;'>".$row."</td></tr>";
      }
      $row .= $res."</table></html>";

      ReadingsBulkUpdateValue ($hash,"SqlResult", $row);
  }
  elsif ($srf eq "mline") {
      my $res = "<html>";
      my @rows = split( /§/, $rowstring );
      my $row;

      for $row ( @rows ) {
          $row =~ s/\|°escaped°\|/§/g;
          $res .= $row."<br>";
      }
      $row .= $res."</html>";

      ReadingsBulkUpdateValue ($hash, "SqlResult", $row );
  }
  elsif ($srf eq "separated") {
      my @rows = split( /§/, $rowstring );
      my $bigint = @rows;
      my $numd = ceil(log10($bigint));
      my $formatstr = sprintf('%%%d.%dd', $numd, $numd);
      my $i = 0;

      for my $row ( @rows ) {
          $i++;
          $row =~ s/\|°escaped°\|/§/g;
          my $fi = sprintf($formatstr, $i);
          ReadingsBulkUpdateValue ($hash, "SqlResultRow_".$fi, $row);
      }
  }
  elsif ($srf eq "json") {
      my %result = ();
      my @rows = split( /§/, $rowstring );
      my $bigint = @rows;
      my $numd = ceil(log10($bigint));
      my $formatstr = sprintf('%%%d.%dd', $numd, $numd);
      my $i = 0;

      for my $row ( @rows ) {
          $i++;
          $row =~ s/\|°escaped°\|/§/g;
          my $fi = sprintf($formatstr, $i);
          $result{$fi} = $row;
      }
      my $json = toJSON(\%result);                                         # need at least fhem.pl 14348 2017-05-22 20:25:06Z
      ReadingsBulkUpdateValue ($hash, "SqlResult", $json);
  }

  ReadingsBulkUpdateTime ($hash, $brt, $rt);
  readingsEndUpdate      ($hash, 1);

  DbRep_afterproc        ($hash, $hash->{LASTCMD});                        # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd     ($name);                                          # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nichtblockierende DB-Abfrage get db Metadaten
####################################################################################################
sub DbRep_dbmeta {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};

  my $db    = $hash->{DATABASE};
  my $utf8  = $hash->{UTF8} // 0;

  my ($sth,$sql);

  my $bst = [gettimeofday];                                                     # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  no warnings 'uninitialized';

  my $param;                                                                    # Liste der anzuzeigenden Parameter erzeugen, sonst alle ("%"), abhängig von $opt
  $param = AttrVal($name, "showVariables", "%")    if($opt eq "dbvars");
  $param = AttrVal($name, "showSvrInfo", "[A-Z_]") if($opt eq "svrinfo");
  $param = AttrVal($name, "showStatus", "%")       if($opt eq "dbstatus");
  $param = "1" if($opt =~ /tableinfo|procinfo/);                                # Dummy-Eintrag für einen Schleifendurchlauf

  my @parlist = split ",", $param;

  my $st = [gettimeofday];                                                      # SQL-Startzeit

  my @row_array;

 # due to incompatible changes made in MyQL 5.7.5, see http://johnemb.blogspot.de/2014/09/adding-or-removing-individual-sql-modes.html
 if($dbmodel eq "MYSQL") {
      ($err, undef) = DbRep_dbhDo ($name, $dbh, "SET sql_mode=(SELECT REPLACE(\@\@sql_mode,'ONLY_FULL_GROUP_BY',''));");
      return "$name|$err" if ($err);
 }

 if ($opt ne "svrinfo") {
    for my $ple (@parlist) {
         if ($opt eq "dbvars") {
             $sql = "show variables like '$ple';";
         }
         elsif ($opt eq "dbstatus") {
             $sql = "show global status like '$ple';";
         }
         elsif ($opt eq "tableinfo") {
             $sql = "show Table Status from $db;";
         }
         elsif ($opt eq "procinfo") {
             $sql = "show full processlist;";
         }

         ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
         return "$name|$err" if ($err);

         if ($opt eq "tableinfo") {
             $param = AttrVal($name, "showTableInfo", "[A-Z_]");
             $param =~ s/,/\|/g;
             $param =~ tr/%//d;

             while (my $line = $sth->fetchrow_hashref()) {

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
         }
         elsif ($opt eq "procinfo") {
               my $row;
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

                   $row  = join("|", @line);
                   $row  =~ tr/ A-Za-z0-9!"#$§%&'()*+,-.\/:;<=>?@[\]^_`{|}~//cd;
                   $row  =~ s/\|/<\/td><td style='padding-right:5px;padding-left:5px'>/g;
                   $res .= "<tr><td style='padding-right:5px;padding-left:5px'>".$row."</td></tr>";
               }

               my $tab .= $res."</table></html>";

               push(@row_array, "ProcessList ".$tab);
         }
         else {
             while (my @line = $sth->fetchrow_array()) {

                 Log3 ($name, 4, "DbRep $name - SQL result: @line");

                 my $row = join("§", @line);
                 $row    =~ s/ /_/g;
                 @line   = split("§", $row);

                 push(@row_array, $line[0]." ".$line[1]);
             }
         }

         $sth->finish;
     }
 }
 else {
     $param =~ s/,/\|/g;
     $param =~ tr/%//d;

     if($dbmodel eq 'SQLITE') {
         my $sf;
         eval{ $sf = $dbh->sqlite_db_filename();
               1;
             }
             or do { $err = encode_base64($@,"");
                     Log3 ($name, 2, "DbRep $name - $@");
                     $dbh->disconnect;
                     return "$name|$err";
                   };

         my $key = "SQLITE_DB_FILENAME";
         push(@row_array, $key." ".$sf) if($key =~ m/($param)/i);

         my @fi = split(' ',qx(du -m $hash->{DATABASE})) if ($^O =~ m/linux/i || $^O =~ m/unix/i);
         $key   = "SQLITE_FILE_SIZE_MB";

         push(@row_array, $key." ".$fi[0]) if($key =~ m/($param)/i);
     }

     my $info;
     while( my ($key,$value) = each(%GetInfoType) ) {
         eval{ $info = $dbh->get_info($GetInfoType{"$key"});
               1;
             }
             or do { $err = encode_base64($@,"");
                     Log3 ($name, 2, "DbRep $name - $@");
                     $dbh->disconnect;
                     return "$name|$err";
                    };

         if($utf8) {
             $info = Encode::encode_utf8($info) if($info);
         }

         push(@row_array, $key." ".$info) if($key =~ m/($param)/i);
     }
 }

 $dbh->disconnect;

 my $rt = tv_interval($st);                                              # SQL-Laufzeit ermitteln

 my $rowlist = join('§', @row_array);

 Log3 ($name, 5, "DbRep $name -> row_array: \n@row_array");

 $rowlist = encode_base64($rowlist,"");                                  # Daten müssen als Einzeiler zurückgegeben werden
 my $brt  = tv_interval($bst);                                           # Background-Laufzeit ermitteln
 $rt      = $rt.",".$brt;
 $err     = q{};

return "$name|$err|$rowlist|$rt|$opt";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage get db Metadaten
####################################################################################################
sub DbRep_dbmeta_Done {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $rowlist    = $a[2] ? decode_base64($a[2]) : '';
  my $bt         = $a[3];
  my $opt        = $a[4];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);
      return;
  }

  my ($rt,$brt) = split ",", $bt;

  no warnings 'uninitialized';

  readingsBeginUpdate($hash);

  my @row_array = split("§", $rowlist);

  Log3 ($name, 5, "DbRep $name - SQL result decoded: \n@row_array") if(@row_array);

  my $pre = "";
  $pre    = "VAR_"  if($opt eq "dbvars");
  $pre    = "STAT_" if($opt eq "dbstatus");
  $pre    = "INFO_" if($opt eq "tableinfo");

  for my $row (@row_array) {
      my @va = split " ", $row, 2;
      my $k = $va[0];
      my $v = $va[1];
      ReadingsBulkUpdateValue ($hash, $pre.$k, $v);
  }

  ReadingsBulkUpdateTimeState ($hash, $brt, $rt, "done");
  readingsEndUpdate           ($hash, 1);

return;
}

####################################################################################################
#                           Index operations - (re)create, drop, ...
#     list_all
#     recreate_Search_Idx
#     drop_Search_Idx
#     recreate_Report_Idx
#     drop_Report_Idx
#
####################################################################################################
sub DbRep_Index {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $cmdidx     = $paref->{prop};

  my $dbloghash  = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $database   = $hash->{DATABASE};
  my $dbuser     = $dbloghash->{dbuser};

  my ($sqldel,$sqlcre,$sqlava,$sqlallidx,$ret) = ("","","","","");
  my $p = 0;

  my ($sth,$rows,@six);

  my $bst = [gettimeofday];                                         # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, $p);
  return "$name|$err" if ($err);

  # Userrechte ermitteln
  #######################
  $paref->{dbmodel}  = $dbmodel;
  $paref->{dbh}      = $dbh;
  $paref->{database} = $database;
  my $grants         = _DbRep_getInitData_grants ($paref);

  if($cmdidx ne "list_all" && $dbmodel =~ /MYSQL/) {                # Rechte Check MYSQL
      if($grants && $grants ne "ALL PRIVILEGES") {                  # Rechte INDEX und ALTER benötigt
          my $i = index($grants, "INDEX");
          my $a = index($grants, "ALTER");

          if($i == -1 || $a == -1) {
              $p = 1;
          }
      }
      elsif (!$grants) {
          $p = 1;
      }
  }

  if($p) {
      Log3 ($name, 2, qq{DbRep $name - user "$dbuser" doesn't have rights "INDEX" and "ALTER" as needed - try use adminCredentials automatically !});

      $dbh->disconnect();

      ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, $p);
      return "$name|$err" if ($err);
  }

  my ($cmd,$idx) = split "_", $cmdidx, 2;

  my $st = [gettimeofday];                                             # SQL-Startzeit

  if($dbmodel =~ /MYSQL/) {
      $sqlallidx = "SELECT TABLE_NAME,INDEX_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = '$database';";
      $sqlava    = "SHOW INDEX FROM history where Key_name='$idx';";

      if($cmd =~ /recreate/) {
          $sqldel = "ALTER TABLE `history` DROP INDEX `$idx`;";
          $sqlcre = "ALTER TABLE `history` ADD INDEX `Search_Idx` (DEVICE, READING, TIMESTAMP) USING BTREE;" if($idx eq "Search_Idx");
          $sqlcre = "ALTER TABLE `history` ADD INDEX `Report_Idx` (TIMESTAMP, READING) USING BTREE;"         if($idx eq "Report_Idx");
      }

      if($cmd =~ /drop/) {
          $sqldel = "ALTER TABLE `history` DROP INDEX `$idx`;";
      }
  }
  elsif($dbmodel =~ /SQLITE/) {
      $sqlallidx = "SELECT tbl_name,name,sql FROM sqlite_master WHERE type='index' ORDER BY tbl_name,name DESC;";
      $sqlava    = "SELECT tbl_name,name FROM sqlite_master WHERE type='index' AND name='$idx';";

      if($cmd =~ /recreate/) {
          $sqldel = "DROP INDEX '$idx';";
          $sqlcre = "CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP);" if($idx eq "Search_Idx");
          $sqlcre = "CREATE INDEX Report_Idx ON `history` (TIMESTAMP,READING);"          if($idx eq "Report_Idx");
      }

      if($cmd =~ /drop/) {
          $sqldel = "DROP INDEX '$idx';";
      }
  }
  elsif($dbmodel =~ /POSTGRESQL/) {
      $sqlallidx = "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE tablename NOT LIKE 'pg%' ORDER BY tablename,indexname DESC;";
      $sqlava    = "SELECT * FROM pg_indexes WHERE tablename='history' and indexname ='$idx';";

      if($cmd =~ /recreate/) {
          $sqldel = "DROP INDEX \"$idx\";";
          $sqlcre = "CREATE INDEX \"Search_Idx\" ON history USING btree (device, reading, \"timestamp\");" if($idx eq "Search_Idx");
          $sqlcre = "CREATE INDEX \"Report_Idx\" ON history USING btree (\"timestamp\", reading);" if($idx eq "Report_Idx");
      }

      if($cmd =~ /drop/) {
          $sqldel = "DROP INDEX \"$idx\";";
      }
  }
  else {
      $err = "database model unknown";
      Log3 ($name, 2, "DbRep $name - DbRep_Index - $err");
      $err = encode_base64($err,"");
      $dbh->disconnect();
      return "$name|$err";
  }

  # alle Indizes auflisten
  Log3($name, 4, "DbRep $name - List all indexes: $sqlallidx");

  my ($sql_table,$sql_idx,$sql_column);
  eval {$sth = $dbh->prepare($sqlallidx);
        $sth->execute();
        $sth->bind_columns(\$sql_table, \$sql_idx, \$sql_column);
       };

  $ret = "";

  my ($lt,$li) = ("",""); my $i = 0;
  while($sth->fetch()) {
      if($lt ne $sql_table || $li ne $sql_idx) {
          $ret .= "\n" if($i>0);
          if($dbmodel =~ /SQLITE/ or $dbmodel =~ /POSTGRESQL/) {
              $sql_column =~ /.*\((.*)\).*/;
              $sql_column = uc($1);
              $sql_column =~ s/"//g;
          }
          $ret .= "Table: $sql_table, Idx: $sql_idx, Col: $sql_column";
      }
      else {
          $ret .= ", $sql_column";
      }

      $lt = $sql_table;
      $li = $sql_idx;
      $i++;
  }

  Log3($name, 3, "DbRep $name - Index found in database:\n$ret");

  $ret = "Index found in database:\n========================\n".$ret;

  if($cmd !~ /list/) {
      Log3($name, 4, "DbRep $name - SQL execute: $sqlava $sqldel $sqlcre");

      if($sqldel) {
          eval {@six = $dbh->selectrow_array($sqlava);};
          if (@six) {
              Log3 ($name, 3, "DbRep $name - dropping index $idx ... ");

              eval {$rows = $dbh->do($sqldel);};
              if ($@) {
                  if($cmd !~ /recreate/) {
                      $err = encode_base64($@,"");
                      Log3 ($name, 2, "DbRep $name - DbRep_Index - $@");
                      $dbh->disconnect();
                      return "$name|$err";
                  }
              }
              else {
                  $ret = "Index $idx dropped";
                  Log3 ($name, 3, "DbRep $name - $ret");
              }
          }
          else {
              $ret = "Index $idx doesn't exist, no need to drop it";
              Log3 ($name, 3, "DbRep $name - $ret");
          }
      }

      if($sqlcre) {
          Log3 ($name, 3, "DbRep $name - creating index $idx ... ");

          eval {$rows = $dbh->do($sqlcre);};
          if ($@) {
              $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - DbRep_Index - $@");
              $dbh->disconnect();
              return "$name|$err";
          }
          else {
              $ret = "Index $idx created";
              Log3 ($name, 3, "DbRep $name - $ret");
          }
      }

      $rows = $rows eq "0E0" ? 0 : $rows if(defined $rows);                        # always return true if no error
  }

  my $rt = tv_interval($st);                                                       # SQL-Laufzeit ermitteln

  $dbh->disconnect();

  $ret    = encode_base64($ret,"");
  my $brt = tv_interval($bst);                                                     # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = q{};

return "$name|$err|$ret|$rt";
}

####################################################################################################
#                     Auswertungsroutine Index Operation
####################################################################################################
sub DbRep_IndexDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $ret        = $a[2] ? decode_base64($a[2]) : '';
  my $bt         = $a[3];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_INDEX}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_INDEX});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "index");                                 # Befehl nach Procedure ausführen incl. state
      DbRep_nextMultiCmd        ($name);                                          # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "index_state", $ret);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, "index");                                       # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                                # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Index operation
####################################################################################################
sub DbRep_IndexAborted {
  my $hash   = shift;
  my $cause  = shift // "Timeout: process terminated";

  my $name   = $hash->{NAME};
  my $dbh    = $hash->{DBH};

  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_INDEX}{fn} pid:$hash->{HELPER}{RUNNING_INDEX}{pid} $cause");

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "index");                                # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);
  my $state  = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));

  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database index operation aborted due to \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_INDEX});

  DbRep_nextMultiCmd ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                             optimize Tables alle Datenbanken
####################################################################################################
sub DbRep_optimizeTables {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $prop   = $paref->{prop} // '';                     # default execute wenn nichts angegeben (wg. Kompatibilität)

  my $dbname = $hash->{DATABASE};
  my $value  = 0;

  my ($sth,$query,$db_MB_start,$db_MB_end);
  my (%db_tables,@tablenames);

  my $bst = [gettimeofday];                                                                   # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my $st = [gettimeofday];                                                                    # SQL-Startzeit

  if ($dbmodel =~ /MYSQL/) {
      $query = "SHOW TABLE STATUS FROM `$dbname`";                                            # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query, "Searching for tables inside database $dbname....");
      return "$name|$err" if ($err);

      while ( $value = $sth->fetchrow_hashref()) {
          Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");

          for my $tk (sort(keys(%$value))) {
              Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
          }

          Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");

          if (defined $value->{Type}) {                                                      # check for old MySQL3-Syntax Type=xxx
              $value->{Engine} = $value->{Type};                                             # port old index type to index engine, so we can use the index Engine in the rest of the script
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
          return "$name|$err";
      }

      $hash->{HELPER}{DBTABLES}      = \%db_tables;                                                         # Tabellen optimieren

      my $opars = {
          hash   => $hash,
          dbh    => $dbh,
          omode  => $prop,
          tables => \@tablenames
      };

      ($err, $db_MB_start, $db_MB_end) = _DbRep_mysqlOptimizeTables ($opars);
      return "$name|$err" if ($err);
  }

  if ($dbmodel =~ /SQLITE/) {
      $db_MB_start = (split(' ',qx(du -m $hash->{DATABASE})))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);  # Anfangsgröße ermitteln

      Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB_start");

      $query = "PRAGMA auto_vacuum = FULL;";

      $err = _DbRep_setSessPragma ($name, $dbh, \$query);
      return "$name|$err" if ($err);

      $query = "VACUUM";

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query, "VACUUM database $dbname....");
      return "$name|$err" if ($err);

      $db_MB_end = (split(' ',qx(du -m $hash->{DATABASE})))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);    # Endgröße ermitteln

      Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB_end");
  }

  if ($dbmodel =~ /POSTGRESQL/) {
      $query = "SELECT pg_size_pretty(pg_database_size('$dbname'))";                                   # Anfangsgröße ermitteln

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);
      return "$name|$err" if ($err);

      $value       = $sth->fetchrow();
      $value       =~ tr/MB//d;
      $db_MB_start = sprintf("%.2f",$value);

      Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB_start");

      $query = "vacuum history";

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query, "VACUUM database $dbname....");
      return "$name|$err" if ($err);

      $query = "SELECT pg_size_pretty(pg_database_size('$dbname'))";                      # Endgröße ermitteln

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);
      return "$name|$err" if ($err);

      $value     = $sth->fetchrow();
      $value     =~ tr/MB//d;
      $db_MB_end = sprintf("%.2f",$value);

      Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB_end");
  }

  $sth->finish;
  $dbh->disconnect;

  $db_MB_start = encode_base64($db_MB_start,"");
  $db_MB_end   = encode_base64($db_MB_end,  "");

  my $rt  = tv_interval($st);                                               # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                              # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = qq{};

  Log3 ($name, 3, "DbRep $name - Optimize tables of $dbname finished - total time (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$db_MB_start|$db_MB_end";
}

####################################################################################################
#             Tabellenoptimierung MySQL
####################################################################################################
sub _DbRep_mysqlOptimizeTables {
  my $opars  = shift;
  my $hash   = $opars->{hash};
  my $dbh    = $opars->{dbh};
  my $omode  = $opars->{omode};
  my $tables = $opars->{tables};

  my $name      = $hash->{NAME};
  my $dbname    = $hash->{DATABASE};
  my $db_tables = $hash->{HELPER}{DBTABLES};
  my $result    = 0;
  my $opttbl    = 0;
  my $err       = qq{};

  my ($sth,$db_MB_start,$db_MB_end);

  ($err, $db_MB_start) = _DbRep_mysqlOpdAndFreeSpace ($hash, $dbh);
  return $err if ($err);

  Log3 ($name, 3, "DbRep $name - Estimate of $dbname before optimize (MB): $db_MB_start");

  if($omode eq "showInfo") {                                                                     # nur Info, keine Ausführung
      return ('',$db_MB_start,'');
  }

  Log3 ($name, 3, "DbRep $name - Optimizing tables");

  for my $tablename (@{$tables}) {                                                                # optimize table if engine supports optimization
      my $engine = '';
      $engine    = uc($db_tables->{$tablename}{Engine}) if($db_tables->{$tablename}{Engine});

      if ($engine =~ /(MYISAM|BDB|INNODB|ARIA)/xi) {
          Log3($name, 3, "DbRep $name - Optimizing table `$tablename` ($engine). It may take a while ...");

          ($err, $sth, $result) = DbRep_prepareExecuteQuery ($name, $dbh, "OPTIMIZE TABLE `$tablename`");
          return $err if ($err);

          if ($result) {
              Log3($name, 3, "DbRep $name - Table ".($opttbl+1)." `$tablename` optimized successfully.");
              $opttbl++;
          }
          else {
              Log3($name, 2, "DbRep $name - Error while optimizing table $tablename. Continue with next table or backup.");
          }
      }
  }

  Log3($name, 3, "DbRep $name - $opttbl tables have been optimized.") if($opttbl > 0);

  ($err, $db_MB_end) = _DbRep_mysqlOpdAndFreeSpace ($hash, $dbh);
  return $err if ($err);

  Log3 ($name, 3, "DbRep $name - Estimate of $dbname after optimize (MB): $db_MB_end");

return ($err,$db_MB_start,$db_MB_end);
}

####################################################################################################
#             MySQL Datenbank belegten und freien Speicher ermitteln
####################################################################################################
sub _DbRep_mysqlOpdAndFreeSpace  {
  my $hash   = shift;
  my $dbh    = shift;

  my $name   = $hash->{NAME};
  my $dbname = $hash->{DATABASE};

  my $query = qq{SELECT table_name, };                                                                         # SQL zur Größenermittlung
  $query   .= qq{round (data_length / 1024 / 1024, 2) "data size in MB", };
  $query   .= qq{round (index_length / 1024 / 1024, 2) "index size in MB", };
  $query   .= qq{round (data_free / 1024 / 1024, 2) "free space in MB" };
  $query   .= qq{FROM information_schema.TABLES where table_schema = '$dbname'; };

  my ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);                               # Anfangsgröße ermitteln
  return $err if ($err);

  my ($dl,$il,$fs) = (0,0,0);
  my $tn           = '';

  while (my @line = $sth->fetchrow_array()) {
      $tn  = $line[0] // '';
      $dl += $line[1] // 0;
      $il += $line[2] // 0;
      $fs += $line[3] // 0;

      # Log3 ($name, 5, "DbRep $name - Size details: table name -> $line[0], data size -> $line[1] MB, index size -> $line[2] MB, Space free -> $line[3] MB");
  }

  $query  = qq{SELECT round ((COUNT(*) * 300 * 1024)/1048576 + 150, 2) "overhead in MB" };
  $query .= qq{FROM information_schema.TABLES where table_schema = '$dbname'; };

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);                               # Overhead ermitteln
  return $err if ($err);

  my $ovh = $sth->fetchrow_array();

  my $db_MB_size = "Data size: $dl, Index size: $il, Space free: $fs, Overhead: $ovh";

return ($err, $db_MB_size);
}

####################################################################################################
#             Auswertungsroutine optimize tables
####################################################################################################
sub DbRep_OptimizeDone {
  my $string       = shift;
  my @a            = split("\\|",$string);
  my $name         = $a[0];
  my $err          = $a[1] ? decode_base64($a[1]) : '';
  my $bt           = $a[2];
  my $db_MB_start  = $a[3] ? decode_base64($a[3]) : '';
  my $db_MB_end    = $a[4] ? decode_base64($a[4]) : '';

  my $hash         = $defs{$name};

  delete($hash->{HELPER}{RUNNING_OPTIMIZE});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "optimize");                   # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                               # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split(",", $bt);

  no warnings 'uninitialized';

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "SizeDbBegin_MB", $db_MB_start);
  ReadingsBulkUpdateValue ($hash, "SizeDbEnd_MB",   $db_MB_end  );
  ReadingsBulkUpdateTime  ($hash, $brt, undef);
  readingsEndUpdate       ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Optimize tables finished successfully. ");

  DbRep_afterproc         ($hash, "optimize");                         # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                     # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
# nicht blockierende Dump-Routine für MySQL (clientSide)
####################################################################################################
sub DbRep_mysql_DumpClientSide {
  my $paref                      = shift;
  my $hash                       = $paref->{hash};
  my $name                       = $paref->{name};

  my $dump_path                  = AttrVal ($name, "dumpDirLocal",             $dbrep_dump_path_def);
  my $optimize_tables_beforedump = AttrVal ($name, "optimizeTablesBeforeDump",                    0);
  my $memory_limit               = AttrVal ($name, "dumpMemlimit",                           100000);
  my $my_comment                 = AttrVal ($name, "dumpComment",                                "");
  my $dumpspeed                  = AttrVal ($name, "dumpSpeed",                               10000);
  my $ebd                        = AttrVal ($name, "executeBeforeProc",                       undef);
  my $ead                        = AttrVal ($name, "executeAfterProc",                        undef);

  my $mysql_commentstring        = "-- ";
  my $repver                     = $hash->{HELPER}{VERSION};
  my $dbname                     = $hash->{DATABASE};
  $dump_path                     = $dump_path."/" unless($dump_path =~ m/\/$/);

  my ($sth,$tablename,$rct,$insert,$backupfile,$drc,$drh,$filesize,$totalrecords);
  my (@ar,@tablenames,@tables,@ctab);
  my (%db_tables, %db_tables_views);

  my $bst = [gettimeofday];                                                        # Background-Startzeit

  Log3 ($name, 3, "DbRep $name - Starting dump of database '$dbname'");

  #####################  Beginn Dump  ########################
  ############################################################

  undef %db_tables;

  # Startzeit ermitteln
  my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);

  $Jahr           += 1900;
  $Monat          += 1;
  $Jahrestag      += 1;
  my $CTIME_String = strftime "%Y-%m-%d %T", localtime(time);
  my $time_stamp   = $Jahr."_".sprintf("%02d",$Monat)."_".sprintf("%02d",$Monatstag)."_".sprintf("%02d",$Stunden)."_".sprintf("%02d",$Minuten);
  my $starttime    = sprintf("%02d",$Monatstag).".".sprintf("%02d",$Monat).".".$Jahr."  ".sprintf("%02d",$Stunden).":".sprintf("%02d",$Minuten);

  my $fieldlist = "";

  my ($err, $dbh, $dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if($err);

  $dbh->{mysql_enable_utf8} = 0;                                                                             # Dump Performance !!! Forum: https://forum.fhem.de/index.php/topic,53584.msg1204535.html#msg1204535

  my $st = [gettimeofday];                                                                                   # SQL-Startzeit

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, "SELECT VERSION()");                                # Mysql-Version ermitteln
  return "$name|$err" if($err);

  my @mysql_version = $sth->fetchrow;
  my @v             = split(/\./,$mysql_version[0]);
  my $collation     = '';
  my $dbcharset     = '';

  if ($v[0] >= 5 || ($v[0] >= 4 && $v[1] >= 1) ) {                                                           # mysql Version >= 4.1
      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SHOW VARIABLES LIKE 'collation_database'));
      return "$name|$err" if($err);

      @ar = $sth->fetchrow;

      if ($ar[1]) {
          $collation = $ar[1];
          $dbcharset = (split '_', $collation, 2)[0];

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SET NAMES "$dbcharset" COLLATE "$collation"));
          return "$name|$err" if($err);
      }
  }
  else {                                                                                                     # mysql Version < 4.1 -> no SET NAMES available
      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, "SHOW VARIABLES LIKE 'dbcharset'");             # get standard encoding of MySQl-Server
      return "$name|$err" if($err);

      @ar = $sth->fetchrow;

      if ($ar[1]) {
          $dbcharset = $ar[1];
      }
  }

  Log3 ($name, 3, "DbRep $name - Characterset of collection set to $dbcharset. ");

  my $t         = 0;
  my $r         = 0;
  my $value     = 0;
  my $engine    = '';
  my $dbpraefix = '';
  my $query     = "SHOW TABLE STATUS FROM `$dbname`";                                                   # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)

  if ($dbpraefix ne "") {
      $query .= " LIKE '$dbpraefix%'";

      Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname with prefix $dbpraefix....");
  }
  else {
      Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname....");
  }

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);
  return "$name|$err" if($err);

  while ( $value = $sth->fetchrow_hashref()) {
      $value->{skip_data} = 0;                                                                          # default -> backup data of table

      Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");

      for my $tk (sort(keys(%$value))) {
          Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
      }

      Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");

      # decide if we need to skip the data while dumping (VIEWs and MEMORY)
      # check for old MySQL3-Syntax Type=xxx

      if (defined $value->{Type}) {                                                                    # port old index type to index engine, so we can use the index Engine in the rest of the script
          $value->{Engine} = $value->{Type};
          $engine          = uc($value->{Type});

          if ($engine eq "MEMORY") {
              $value->{skip_data} = 1;
          }
      }

      if (defined $value->{Engine}) {                                                                  # check for > MySQL3 Engine = xxx
          $engine = uc($value->{Engine});

          if ($engine eq "MEMORY") {
              $value->{skip_data} = 1;
          }
      }

      if (defined $value->{Comment} && uc(substr($value->{Comment},0,4)) eq 'VIEW') {                  # check for Views - if it is a view the comment starts with "VIEW"
          $value->{skip_data}   = 1;
          $value->{Engine}      = 'VIEW';
          $value->{Update_time} = '';
          $db_tables_views{$value->{Name}} = $value;
      }
      else {
          $db_tables{$value->{Name}} = $value;
      }

      $value->{Rows}         += 0;                                                                     # cast indexes to int, cause they are used for builing the statusline
      $value->{Data_length}  += 0;
      $value->{Index_length} += 0;
  }

  $sth->finish;

  @tablenames = sort(keys(%db_tables));

  @tablenames = (@tablenames,sort(keys(%db_tables_views)));                                            # add VIEW at the end as they need all tables to be created before
  %db_tables  = (%db_tables,%db_tables_views);
  $tablename  = '';

  if (@tablenames < 1) {
      $err = "There are no tables inside database $dbname ! It doesn't make sense to backup an empty database. Skipping this one.";
      Log3 ($name, 2, "DbRep $name - $err");
      $err = encode_base64($@,"");
      $dbh->disconnect;
      return "$name|$err";
  }

  if ($optimize_tables_beforedump) {                                                                   # Tabellen optimieren vor dem Dump
      $hash->{HELPER}{DBTABLES} = \%db_tables;

      my $opars = {
          hash   => $hash,
          dbh    => $dbh,
          omode  => "execute",
          tables => \@tablenames
      };

      ($err) = _DbRep_mysqlOptimizeTables ($opars);
      return $err if($err);
  }

  my $part = '';                                                                                       # Tabelleneigenschaften für SQL-File ermitteln

  for $tablename (@tablenames) {
      my $dump_table = 1;

      if ($dbpraefix ne "") {
          if (substr ($tablename, 0, length($dbpraefix)) ne $dbpraefix) {                              # exclude table from backup because it doesn't fit to praefix
              $dump_table = 0;
          }
      }

      if ($dump_table == 1) {

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SELECT count(*) FROM `$tablename`));
          return "$name|$err" if($err);

          $db_tables{$tablename}{Rows} = $sth->fetchrow;                                               # how many rows
          $sth->finish;

          $r += $db_tables{$tablename}{Rows};
          push @tables, $db_tables{$tablename}{Name};                                                  # add tablename to backuped tables
          $t++;

          if (!defined $db_tables{$tablename}{Update_time}) {
              $db_tables{$tablename}{Update_time} = 0;
          }

          $part .= $mysql_commentstring;
          $part .= "TABLE: $db_tables{$tablename}{Name} | ";
          $part .= "Rows: $db_tables{$tablename}{Rows} | ";
          $part .= "Length: ".($db_tables{$tablename}{Data_length} + $db_tables{$tablename}{Index_length})." | ";
          $part .= "Engine: $db_tables{$tablename}{Engine}";
          $part .= "\n";

          if ($db_tables{$tablename}{Name} eq "current") {
              $drc = $db_tables{$tablename}{Rows};
          }

          if ($db_tables{$tablename}{Name} eq "history") {
              $drh = $db_tables{$tablename}{Rows};
          }
      }
  }

  $part .= $mysql_commentstring."EOF TABLE-INFO";

  Log3 ($name, 3, "DbRep $name - Found ".(@tables)." tables with $r records.");

  ## Headerzeilen aufbauen
  ##########################
  my $sql_text = $mysql_commentstring."DB Name: $dbname";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."DB Character set: $dbcharset";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."MySQL Version: $mysql_version[0]";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."Dump created on $CTIME_String by DbRep-Version $repver";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."Comment: $my_comment";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."TABLE-INFO";
  $sql_text   .= "\n";
  $sql_text   .= $mysql_commentstring."TABLES: $t, Rows: $r";
  $sql_text   .= "\n";
  $sql_text   .= $part;
  $sql_text   .= "\n\n";

  ## neues SQL Ausgabefile mit Header anlegen
  #############################################
  my $sql_file = '';

  ($err, $sql_file, $backupfile) = DbRep_NewDumpFilename ( { sql_text   => $sql_text,
                                                             dump_path  => $dump_path,
                                                             dbname     => $dbname,
                                                             time_stamp => $time_stamp
                                                           }
                                                         );

  if ($err) {
      Log3 ($name, 2, "DbRep $name - $err");
      $err = encode_base64 ($err, "");
      return "$name|$err";
  }
  else {
      Log3 ($name, 3, "DbRep $name - New dump file $sql_file was created");
  }

  my $first_insert = 0;

  ## DB Einstellungen
  #####################

  $sql_text  = "/*!40101 SET NAMES '".$dbcharset."' */;";
  $sql_text .= "\n";
  $sql_text .= "SET FOREIGN_KEY_CHECKS=0;";
  $sql_text .= "\n\n";

  DbRep_WriteToDumpFile ($sql_text, $sql_file);

  ## DB Create Statement einfügen
  #################################
  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SHOW CREATE DATABASE IF NOT EXISTS $dbname));
  return "$name|$err" if($err);

  my $db_create = $sth->fetchrow;
  $sth->finish;

  $sql_text  = $mysql_commentstring;
  $sql_text .= "\n";
  $sql_text .= $mysql_commentstring;
  $sql_text .= "Create database";
  $sql_text .= "\n";
  $sql_text .= $mysql_commentstring;
  $sql_text .= "\n";

  $sql_text .= $db_create.';';
  $sql_text .= "\n";
  $sql_text .= "USE `$dbname`;";
  $sql_text .= "\n\n";

  DbRep_WriteToDumpFile ($sql_text, $sql_file);

  ## jede einzelne Tabelle dumpen
  #################################
  $totalrecords = 0;
  $sql_text     = "";

  for $tablename (@tables) {                                                                                    # first get CREATE TABLE Statement
      if ($dbpraefix eq "" || ($dbpraefix ne "" && substr($tablename, 0, length($dbpraefix)) eq $dbpraefix)) {
          Log3 ($name, 3, "DbRep $name - Dumping table $tablename (Type ".$db_tables{$tablename}{Engine}."):");

          $part  = $mysql_commentstring;
          $part .= "\n";
          $part .= $mysql_commentstring;
          $part .= "Table structure of table `$tablename`";
          $part .= "\n";
          $part .= $mysql_commentstring;
          $part .= "\n";

          if ($db_tables{$tablename}{Engine} ne 'VIEW' ) {
              $part .= "DROP TABLE IF EXISTS `$tablename`;";
          }
          else {
              $part .= "DROP VIEW IF EXISTS `$tablename`;";
          }

          $sql_text .= $part;
          $sql_text .= "\n";

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SHOW CREATE TABLE `$tablename`));
          return "$name|$err" if($err);

          @ctab = $sth->fetchrow;
          $sth->finish;

          $part  = $ctab[1].";";
          $part .= "\n";

          if (length($part) < 10) {
              $err = "Fatal error! Couldn't read CREATE-Statement for table `$tablename`! This backup might be incomplete! Check your database for errors. MySQL-Error: ".$DBI::errstr;

              Log3 ($name, 2, "DbRep $name - $err");

              return "$name|$err";
          }
          else {
              $sql_text .= $part;
          }

          Log3 ($name, 5, "DbRep $name - Create-SQL found:\n$part");

          if ($db_tables{$tablename}{skip_data} == 0) {
              $sql_text .= "\n";
              $sql_text .= "$mysql_commentstring\n";
              $sql_text .= "$mysql_commentstring";
              $sql_text .= "Dumping data of table `$tablename`\n";
              $sql_text .= "$mysql_commentstring\n";

              $sql_text .= "/*!40000 ALTER TABLE `$tablename` DISABLE KEYS */;";

              DbRep_WriteToDumpFile ($sql_text, $sql_file);

              $sql_text = "";

              ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(SHOW FIELDS FROM `$tablename`));
              return "$name|$err" if($err);

              $fieldlist = "(";

              while (@ar = $sth->fetchrow) {                                                       # build fieldlist
                  $fieldlist .= "`".$ar[0]."`,";
              }

              $sth->finish;

              Log3 ($name, 5, "DbRep $name - Fieldlist found: $fieldlist");

              $fieldlist = substr ($fieldlist, 0, length($fieldlist)-1).")";                       # remove trailing ',' and add ')'

              $rct = $db_tables{$tablename}{Rows};                                                 # how many rows

              Log3 ($name, 5, "DbRep $name - Number entries of table $tablename: $rct");

              for (my $ttt = 0; $ttt < $rct; $ttt += $dumpspeed) {                                 # create insert Statements
                  $insert       = "INSERT INTO `$tablename` $fieldlist VALUES (";                  # default beginning for INSERT-String
                  $first_insert = 0;

                  my $sql_daten = "SELECT * FROM `$tablename` LIMIT ".$ttt.",".$dumpspeed.";";     # get rows (parts)

                  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql_daten);
                  return "$name|$err" if($err);

                  while ( @ar = $sth->fetchrow) {                                                  # Start the insert
                      if ($first_insert == 0) {
                          $part = "\n$insert";
                      }
                      else {
                          $part = "\n(";
                      }

                      for my $cont (@ar) {                                                         # quote all values
                          $part .= $dbh->quote($cont).",";
                      }

                      $part      = substr ($part, 0, length($part)-1).");";                        # remove trailing ',' and add end-sql
                      $sql_text .= $part;

                      if ($memory_limit > 0 && length($sql_text) > $memory_limit) {
                          ($err, $filesize) = DbRep_WriteToDumpFile ($sql_text, $sql_file);
                          # Log3 ($name, 5, "DbRep $name - Memory limit '$memory_limit' exceeded. Wrote to '$sql_file'. Filesize: '"._DbRep_byteOutput($filesize)."'");
                          $sql_text = "";
                      }
                  }

                  $sth->finish;
              }

              $sql_text .= "\n/*!40000 ALTER TABLE `$tablename` ENABLE KEYS */;\n";
          }

          ($err, $filesize) = DbRep_WriteToDumpFile ($sql_text, $sql_file);                       # write sql commands to file

          $sql_text = "";

          if ($db_tables{$tablename}{skip_data} == 0) {
              Log3 ($name, 3, "DbRep $name - $rct records inserted (size of backupfile: "._DbRep_byteOutput ($filesize).")") if($filesize);
              $totalrecords += $rct;
          }
          else {
              Log3 ($name, 3, "DbRep $name - Dumping structure of $tablename (Type ".$db_tables{$tablename}{Engine}." ) (size of backupfile: "._DbRep_byteOutput($filesize).")");
          }
      }
  }

  # end

  DbRep_WriteToDumpFile("\nSET FOREIGN_KEY_CHECKS=1;\n", $sql_file);
  ($err, $filesize) = DbRep_WriteToDumpFile ($mysql_commentstring."EOB\n", $sql_file);

  $sth->finish();
  $dbh->disconnect();

  my $rt = tv_interval($st);                                                                       # SQL-Laufzeit ermitteln

  my $compress = AttrVal ($name, "dumpCompress", 0);                                               # Dumpfile komprimieren wenn dumpCompress=1

  if ($compress) {
      ($err, $backupfile, $filesize) = DbRep_dumpCompress ($hash, $backupfile);
  }

  my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp ($hash,$backupfile);                                 # Dumpfile per FTP senden und versionieren
  my $ftp = $ftperr ? encode_base64($ftperr,"") :
            $ftpmsg ? encode_base64($ftpmsg,"") :
            0;

  my $ffd   = join ", ", @ftpfd;
  $ffd      = $ffd ? encode_base64($ffd,"") : 0;

  my @fd    = DbRep_deldumpfiles ($hash,$backupfile);                                              # alte Dumpfiles löschen
  my $bfd   = join ", ", @fd;
  $bfd      = $bfd ? encode_base64($bfd,"") : 0;

  my $brt   = tv_interval($bst);                                                                   # Background-Laufzeit ermitteln
  $rt       = $rt.",".$brt;

  my $fsize = _DbRep_byteOutput($filesize);
  $fsize    = encode_base64    ($fsize,"");
  $err      = q{};

  Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$dump_path$backupfile|$drc|$drh|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#                  nicht blockierende Dump-Routine für MySQL (serverSide)
####################################################################################################
sub DbRep_mysql_DumpServerSide {
 my $paref                      = shift;
 my $hash                       = $paref->{hash};
 my $name                       = $paref->{name};
 my $table                      = $paref->{table};

 my $dbname                     = $hash->{DATABASE};
 my $optimize_tables_beforedump = AttrVal($name, "optimizeTablesBeforeDump", 0);
 my $dump_path_rem              = AttrVal($name, "dumpDirRemote", $dbrep_dump_remotepath_def);
 $dump_path_rem                 = $dump_path_rem."/" unless($dump_path_rem =~ m/\/$/);

 my $dump_path_loc              = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
 $dump_path_loc                 = $dump_path_loc."/" unless($dump_path_loc =~ m/\/$/);

 my $ebd                        = AttrVal($name, "executeBeforeProc", undef);
 my $ead                        = AttrVal($name, "executeAfterProc", undef);

 my ($sth,$drh);
 my (%db_tables,@tablenames);

 my $bst = [gettimeofday];                                              # Background-Startzeit

 my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
 return "$name|$err" if ($err);

 my $value  = 0;
 my $query  ="SHOW TABLE STATUS FROM `$dbname`";                        # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)

 Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname....");

 ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $query);
 return "$name|$err" if ($err);

 while ( $value = $sth->fetchrow_hashref()) {
     Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");

     for my $tk (sort(keys(%$value))) {
         Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
     }

     Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");

     if (defined $value->{Type}) {                                                     # check for old MySQL3-Syntax Type=xxx
         $value->{Engine} = $value->{Type};                                            # port old index type to index engine, so we can use the index Engine in the rest of the script
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
     return "$name|$err";
 }

 if($optimize_tables_beforedump) {                                                       # Tabellen optimieren vor dem Dump
     $hash->{HELPER}{DBTABLES} = \%db_tables;

     my $opars = {
         hash   => $hash,
         dbh    => $dbh,
         omode  => "execute",
         tables => \@tablenames
     };

     ($err) = _DbRep_mysqlOptimizeTables($opars);
     return "$name|$err" if ($err);
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

 my $st  = [gettimeofday];                                                                     # SQL-Startzeit

 my $sql = "SELECT * FROM $table INTO OUTFILE '$dump_path_rem$bfile' FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n'; ";

 ($err, $sth, $drh) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
 return "$name|$err" if ($err);

 $sth->finish;
 $dbh->disconnect;

 my $rt       = tv_interval($st);                                                       # SQL-Laufzeit ermitteln

 my $fsBytes  = _DbRep_fsizeInBytes ($dump_path_loc.$bfile);                            # Größe Dumpfile ermitteln
 my $fsize    = _DbRep_byteOutput   ($fsBytes);

 Log3 ($name, 3, "DbRep $name - Size of backupfile: ".$fsize);

 my $compress = AttrVal($name, "dumpCompress", 0);                                      # Dumpfile komprimieren wenn dumpCompress=1

 if($compress) {                                                                        # $err nicht auswerten -> wenn compress fehlerhaft wird unkomprimiertes dumpfile verwendet
     ($err, $bfile, $fsBytes) = DbRep_dumpCompress ($hash, $bfile);
     $fsize                   = _DbRep_byteOutput  ($fsBytes);
 }

 Log3 ($name, 3, "DbRep $name - Number of exported datasets: $drh");

 my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp($hash,$bfile);                             # Dumpfile per FTP senden und versionieren
 my $ftp = $ftperr ? encode_base64($ftperr,"") :
           $ftpmsg ? encode_base64($ftpmsg,"") :
           0;

 my $ffd   = join(", ", @ftpfd);
 $ffd      = $ffd ? encode_base64($ffd,"") : 0;

 my @fd    = DbRep_deldumpfiles($hash,$bfile);                                            # alte Dumpfiles löschen
 my $bfd   = join(", ", @fd );
 $bfd      = $bfd ? encode_base64($bfd,"") : 0;

 my $brt   = tv_interval($bst);                                                           # Background-Laufzeit ermitteln

 $fsize    = encode_base64    ($fsize,"");

 $rt  = $rt.",".$brt;
 $err = q{};

 Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$dump_path_rem$bfile|n.a.|$drh|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#                                      Dump-Routine SQLite
####################################################################################################
sub DbRep_sqlite_Dump {
 my $paref                      = shift;
 my $hash                       = $paref->{hash};
 my $name                       = $paref->{name};

 my $dbname                     = $hash->{DATABASE};
 my $dump_path                  = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
 $dump_path                     = $dump_path."/" unless($dump_path =~ m/\/$/);
 my $optimize_tables_beforedump = AttrVal($name, "optimizeTablesBeforeDump", 0);
 my $ebd                        = AttrVal($name, "executeBeforeProc", undef);
 my $ead                        = AttrVal($name, "executeAfterProc", undef);

 my ($db_MB,$r,$query,$sth,$fsBytes);

 my $bst = [gettimeofday];                                                                   # Background-Startzeit

 my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
 return "$name|$err" if ($err);

 if($optimize_tables_beforedump) {                                                           # Vacuum vor Dump  # Anfangsgröße ermitteln
     $fsBytes  = _DbRep_fsizeInBytes ($dbname);
     $db_MB    = _DbRep_byteOutput   ($fsBytes);

     Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB");

     $query  ="VACUUM";

     Log3 ($name, 3, "DbRep $name - VACUUM database $dbname....");

     ($err, $sth, $r) = DbRep_prepareExecuteQuery ($name, $dbh, $query);
     return "$name|$err" if ($err);

     $fsBytes  = _DbRep_fsizeInBytes ($dbname);
     $db_MB    = _DbRep_byteOutput   ($fsBytes);

     Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB");
 }

 $dbname = (split /[\/]/, $dbname)[-1];

 Log3 ($name, 3, "DbRep $name - Starting dump of database '$dbname'");

 # Startzeit ermitteln
 my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);

 $Jahr         += 1900;
 $Monat        += 1;
 $Jahrestag    += 1;
 my $time_stamp = $Jahr."_".sprintf("%02d",$Monat)."_".sprintf("%02d",$Monatstag)."_".sprintf("%02d",$Stunden)."_".sprintf("%02d",$Minuten);

 $dbname   = (split /\./, $dbname)[0];
 my $bfile = $dbname."_".$time_stamp.".sqlitebkp";

 Log3 ($name, 5, "DbRep $name - Use Outfile: $dump_path$bfile");

 my $st = [gettimeofday];                                                              # SQL-Startzeit

 eval { $dbh->sqlite_backup_to_file($dump_path.$bfile); };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|$err";
 }

 $dbh->disconnect;

 my $rt    = tv_interval($st);                                                         # SQL-Laufzeit ermitteln

 $fsBytes  = _DbRep_fsizeInBytes ($dump_path.$bfile);                                  # Größe Dumpfile ermitteln
 my $fsize = _DbRep_byteOutput   ($fsBytes);

 Log3 ($name, 3, "DbRep $name - Size of backupfile: ".$fsize);

 my $compress = AttrVal($name, "dumpCompress", 0);                                     # Dumpfile komprimieren
 if($compress) {                                                                       # $err nicht auswerten -> wenn compress fehlerhaft wird unkomprimiertes dumpfile verwendet
     ($err, $bfile, $fsBytes) = DbRep_dumpCompress ($hash, $bfile);
     $fsize                   = _DbRep_byteOutput  ($fsBytes);
 }

 my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp($hash,$bfile);                            # Dumpfile per FTP senden und versionieren
 my $ftp = $ftperr ? encode_base64($ftperr,"") :
           $ftpmsg ? encode_base64($ftpmsg,"") :
           0;

 my $ffd   = join ", ", @ftpfd;
 $ffd      = $ffd ? encode_base64($ffd,"") : 0;

 my @fd    = DbRep_deldumpfiles($hash,$bfile);                                           # alte Dumpfiles löschen
 my $bfd   = join ", ", @fd;
 $bfd      = $bfd ? encode_base64($bfd,"") : 0;

 my $brt   = tv_interval($bst);                                                          # Background-Laufzeit ermitteln

 $fsize    = encode_base64($fsize,"");
 $rt       = $rt.",".$brt;
 $err      = q{};

 Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$dump_path$bfile|n.a.|n.a.|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#             Auswertungsroutine der nicht blockierenden DB-Funktion Dump
####################################################################################################
sub DbRep_DumpDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $bt         = $a[2];
  my $bfile      = $a[3];
  my $drc        = $a[4];
  my $drh        = $a[5];
  my $fs         = $a[6] ? decode_base64($a[6]) : '';
  my $ftp        = $a[7] ? decode_base64($a[7]) : '';
  my $bfd        = $a[8] ? decode_base64($a[8]) : '';
  my $ffd        = $a[9] ? decode_base64($a[9]) : '';

  my $hash       = $defs{$name};

  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "dump");                             # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                     # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  no warnings 'uninitialized';

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "DumpFileCreated",    $bfile);
  ReadingsBulkUpdateValue ($hash, "DumpFileCreatedSize",   $fs);
  ReadingsBulkUpdateValue ($hash, "DumpFilesDeleted",     $bfd);
  ReadingsBulkUpdateValue ($hash, "DumpRowsCurrent",      $drc);
  ReadingsBulkUpdateValue ($hash, "DumpRowsHistory",      $drh);
  ReadingsBulkUpdateValue ($hash, "FTP_Message",          $ftp) if($ftp);
  ReadingsBulkUpdateValue ($hash, "FTP_DumpFilesDeleted", $ffd) if($ffd);
  ReadingsBulkUpdateValue ($hash, "background_processing_time", sprintf("%.4f",$brt));
  readingsEndUpdate       ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database dump finished successfully. ");

  DbRep_afterproc         ($hash, "dump");                                  # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                          # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                                      Dump-Routine SQLite
####################################################################################################
sub DbRep_sqliteRepair {
  my $paref       = shift;
  my $hash        = $paref->{hash};
  my $name        = $paref->{name};

  my $dbloghash   = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $db          = $hash->{DATABASE};
  my $dbname      = (split /[\/]/, $db)[-1];
  my $dbpath      = (split /$dbname/, $db)[0];
  my $dblogname   = $dbloghash->{NAME};
  my $sqlfile     = $dbpath."dump_all.sql";

  my $err;

  my $bst = [gettimeofday];                                                    # Background-Startzeit

  my $c    = "echo \".mode insert\n.output $sqlfile\n.dump\n.exit\" | sqlite3 $db; ";
  my $clog = $c;
  $clog    =~ s/\n/ /g;

  Log3 ($name, 4, "DbRep $name - Systemcall: $clog");

  my $ret = system qq($c);
  if($ret) {
      $err = "Error in step \"dump corrupt database\" - see logfile";
      $err = encode_base64($err,"");
      return "$name|$err";
  }

  $c    = "mv $db $db.corrupt";
  $clog = $c;
  $clog =~ s/\n/ /g;

  Log3 ($name, 4, "DbRep $name - Systemcall: $clog");

  $ret = system qq($c);
  if($ret) {
      $err = "Error in step \"move atabase to corrupt-db\" - see logfile";
      $err = encode_base64($err,"");
      return "$name|$err";
  }

  $c    = "echo \".read $sqlfile\n.exit\" | sqlite3 $db;";
  $clog = $c;
  $clog =~ s/\n/ /g;

  Log3 ($name, 4, "DbRep $name - Systemcall: $clog");

  $ret = system qq($c);
  if($ret) {
      $err = "Error in step \"read dump to new database\" - see logfile";
      $err = encode_base64($err,"");
      return "$name|$err";
  }

  $c    = "rm $sqlfile";
  $clog = $c;
  $clog =~ s/\n/ /g;

  Log3 ($name, 4, "DbRep $name - Systemcall: $clog");

  $ret = system qq($c);
  if($ret) {
      $err = "Error in step \"delete $sqlfile\" - see logfile";
      $err = encode_base64($err,"");
      return "$name|$err";
  }

  my $brt = tv_interval($bst);                                          # Background-Laufzeit ermitteln
  $err    = q{};

return "$name|$err|$brt";
}

####################################################################################################
#             Auswertungsroutine der nicht blockierenden DB-Funktion Dump
####################################################################################################
sub DbRep_RepairDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $brt        = $a[2];

  my $hash       = $defs{$name};
  my $dbloghash  = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  delete($hash->{HELPER}{RUNNING_REPAIR});

  CommandSet(undef,"$dbloghash->{NAME} reopen");                               # Datenbankverbindung in DbLog wieder öffenen

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "repair");                             # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                       # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  no warnings 'uninitialized';

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "background_processing_time", sprintf("%.4f",$brt));
  readingsEndUpdate       ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database repair $hash->{DATABASE} finished - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

  DbRep_afterproc         ($hash, "repair");                                   # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                             # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                                     Restore SQLite
####################################################################################################
sub DbRep_sqliteRestore {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $bfile  = $paref->{prop};

  my $dump_path = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
  $dump_path    = $dump_path."/" unless($dump_path =~ m/\/$/);

  my $bst = [gettimeofday];                                             # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  my $dbname;
  eval{ $dbname = $dbh->sqlite_db_filename();
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - $@");
              $dbh->disconnect;
              return "$name|$err";
            };

  $dbname = (split /[\/]/, $dbname)[-1];

  if($bfile =~ m/.*.gzip$/) {                                         # Dumpfile dekomprimieren wenn gzip
      ($err,$bfile) = DbRep_dumpUnCompress($hash,$bfile);
      if ($err) {
          $err = encode_base64($err,"");
          $dbh->disconnect;
          return "$name|$err";
      }
  }

  Log3 ($name, 3, "DbRep $name - Starting restore of database '$dbname'");

  my $st = [gettimeofday];                                            # SQL-Startzeit

  eval{ $dbh->sqlite_backup_from_file($dump_path.$bfile);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - $@");
              $dbh->disconnect;
              return "$name|$err";
            };

  $dbh->disconnect;

  my $rt  = tv_interval($st);                                         # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                        # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = q{};

  Log3 ($name, 3, "DbRep $name - Restore of $dump_path$bfile into '$dbname' finished - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$dump_path$bfile|n.a.";
}

####################################################################################################
#                  Restore MySQL (serverSide)
####################################################################################################
sub DbRep_mysql_RestoreServerSide {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $bfile  = $paref->{prop};

  my $dbname        = $hash->{DATABASE};
  my $dump_path_rem = AttrVal($name, "dumpDirRemote", $dbrep_dump_remotepath_def);
  $dump_path_rem    = $dump_path_rem."/" unless($dump_path_rem =~ m/\/$/);
  my $table         = "history";

  my ($sth,$drh);

  my $bst = [gettimeofday];                                       # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  if($bfile =~ m/.*.gzip$/) {                                    # Dumpfile dekomprimieren wenn gzip
      ($err,$bfile) = DbRep_dumpUnCompress($hash,$bfile);
      if ($err) {
          $err = encode_base64($err,"");
          $dbh->disconnect;
          return "$name|$err";
      }
  }

  Log3 ($name, 3, "DbRep $name - Starting restore of database '$dbname', table '$table'.");

  my $st  = [gettimeofday];                                       # SQL-Startzeit

  my $sql = "LOAD DATA CONCURRENT INFILE '$dump_path_rem$bfile' IGNORE INTO TABLE $table FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n'; ";

  eval{ $sth = $dbh->prepare($sql);
        $drh = $sth->execute();
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - $@");
              $dbh->disconnect;
              return "$name|$err";
            };

  $sth->finish;
  $dbh->disconnect;

  my $rt  = tv_interval($st);                                   # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                  # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = q{};

  Log3 ($name, 3, "DbRep $name - Restore of $dump_path_rem$bfile into '$dbname', '$table' finished - total time used (hh:mm:ss): ".DbRep_sec2hms($brt));

return "$name|$err|$rt|$dump_path_rem$bfile|n.a.";
}

####################################################################################################
#                  Restore MySQL (ClientSide)
####################################################################################################
sub DbRep_mysql_RestoreClientSide {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $bfile  = $paref->{prop};

  my $dbname    = $hash->{DATABASE};
  my $i_max     = AttrVal($name, "dumpMemlimit", 100000);                      # max. Anzahl der Blockinserts
  my $dump_path = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
  $dump_path    = $dump_path."/" if($dump_path !~ /.*\/$/);

  my ($v1,$v2,$e);

  my $bst = [gettimeofday];                                                    # Background-Startzeit

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect ($name, 0);
  return "$name|$err" if($err);

  $dbh->{mysql_enable_utf8} = 0;                                               # identisch zu DbRep_mysql_DumpClientSide setzen !

  my @row_ary;
  my $sql         = "show variables like 'max_allowed_packet'";                # maximal mögliche Packetgröße ermitteln (in Bits) -> Umrechnen in max. Zeichen
  eval {@row_ary  = $dbh->selectrow_array($sql);};
  my $max_packets = $row_ary[1];                                               # Bits
  $i_max          = ($max_packets/8)-500;                                      # Characters mit Sicherheitszuschlag

  if ($bfile =~ m/.*.gzip$/) {                                                 # Dumpfile dekomprimieren wenn gzip
      ($err,$bfile) = DbRep_dumpUnCompress($hash,$bfile);

      if ($err) {
          $err = encode_base64($err,"");
          $dbh->disconnect;
          return "$name|$err";
      }
  }

 if (!open(FH, "<$dump_path$bfile")) {
     $err = encode_base64("could not open ".$dump_path.$bfile.": ".$!,"");
     return "$name|$err";
 }

 Log3 ($name, 3, "DbRep $name - Restore of database '$dbname' started. Sourcefile: $dump_path$bfile");
 Log3 ($name, 3, "DbRep $name - Max packet lenght of insert statement: $i_max");

 my $st = [gettimeofday];                                       # SQL-Startzeit

 my $nc         = 0;                                            # Insert Zähler current
 my $nh         = 0;                                            # Insert Zähler history
 my $n          = 0;                                            # Insert Zähler
 my $i          = 0;                                            # Array Zähler
 my $tmp        = '';
 my $line       = '';
 my $base_query = '';
 my $query      = '';

 while (<FH>) {
     $tmp = $_;
     chomp $tmp;

     if (!$tmp || substr($tmp, 0, 2) eq "--") {
         next;
     }

     $line .= $tmp;

     if (substr($line,-1) eq ";") {
         if ($line !~ /^INSERT INTO.*$/) {
             Log3 ($name, 4, "DbRep $name - do query: $line");

             eval { $dbh->do($line);
                  }
                  or do {
                      $e   = $@;
                      $err = encode_base64($e,"");
                      close(FH);
                      $dbh->disconnect;

                      Log3 ($name, 1, "DbRep $name - last query: $line");
                      Log3 ($name, 1, "DbRep $name - $e");

                      return "$name|$err";
                  };

             $line = '';
             next;
         }

         if (!$base_query) {
             $line =~ /INSERT INTO (.*) VALUES \((.*)\);/;
             $v1   = $1;
             $v2   = $2;
             $base_query = qq{INSERT INTO $v1 VALUES };
             $query = $base_query;
             $nc++ if($base_query =~ /INSERT INTO `current`.*/);
             $nh++ if($base_query =~ /INSERT INTO `history`.*/);
             $query .= "," if($i);
             $query .= "(".$v2.")";
             $i++;
         }
         else {
             $line  =~ /INSERT INTO (.*) VALUES \((.*)\);/;
             $v1    = $1;
             $v2    = $2;
             my $ln = qq{INSERT INTO $v1 VALUES };

             if ($base_query eq $ln) {
                 $nc++ if($base_query =~ /INSERT INTO `current`.*/);
                 $nh++ if($base_query =~ /INSERT INTO `history`.*/);
                 $query .= "," if($i);
                 $query .= "(".$v2.")";
                 $i++;
             }
             else {
                 $query = $query.";";

                 eval { $dbh->do($query);
                      }
                      or do {
                          $e = $@;
                          $err = encode_base64($e,"");
                          close(FH);
                          $dbh->disconnect;

                          Log3 ($name, 1, "DbRep $name - last query: $query");
                          Log3 ($name, 1, "DbRep $name - $e");

                          return "$name|$err";
                      };

                 $i          = 0;
                 $line       =~ /INSERT INTO (.*) VALUES \((.*)\);/;
                 $v1         = $1;
                 $v2         = $2;
                 $base_query = qq{INSERT INTO $v1 VALUES };
                 $query      = $base_query;
                 $query     .= "(".$v2.")";
                 $nc++ if($base_query =~ /INSERT INTO `current`.*/);
                 $nh++ if($base_query =~ /INSERT INTO `history`.*/);
                 $i++;
             }
         }

         if (length($query) >= $i_max) {
             $query = $query.";";

             eval { $dbh->do($query);
                  }
                  or do {
                      $e   = $@;
                      $err = encode_base64($e,"");
                      close(FH);
                      $dbh->disconnect;

                      Log3 ($name, 1, "DbRep $name - last query: $query");
                      Log3 ($name, 1, "DbRep $name - $e");

                      return "$name|$err";
                  };

             $i          = 0;
             $query      = '';
             $base_query = '';
         }

         $line = '';
     }
 }

 eval { $dbh->do($query) if($i);
      }
      or do {
          $e = $@;
          $err = encode_base64($e,"");
          close(FH);
          $dbh->disconnect;

          Log3 ($name, 1, "DbRep $name - last query: $query");
          Log3 ($name, 1, "DbRep $name - $e");

          return "$name|$err";
      };

 $dbh->disconnect;
 close(FH);

 my $rt  = tv_interval($st);                                  # SQL-Laufzeit ermitteln
 my $brt = tv_interval($bst);                                 # Background-Laufzeit ermitteln
 $rt     = $rt.",".$brt;
 $err    = q{};

 Log3 ($name, 3, "DbRep $name - Restore of '$dbname' finished - inserted history: $nh, inserted curent: $nc, time used: ".sprintf("%.0f",$brt)." seconds.");

return "$name|$err|$rt|$dump_path$bfile|$nh|$nc";
}

####################################################################################################
#                                  Auswertungsroutine Restore
####################################################################################################
sub DbRep_restoreDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $bt         = $a[2];
  my $bfile      = $a[3];
  my $drh        = $a[4];
  my $drc        = $a[5];

  my $hash       = $defs{$name};

  delete($hash->{HELPER}{RUNNING_RESTORE});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "restore", $bfile);                                 # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd      ($name);                                                      # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "RestoreRowsHistory", $drh) if($drh);
  ReadingsBulkUpdateValue ($hash, "RestoreRowsCurrent", $drc) if($drc);
  ReadingsBulkUpdateTime  ($hash, $brt, undef);
  readingsEndUpdate       ($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database restore finished successfully. ");

  DbRep_afterproc         ($hash, "restore", $bfile);                                      # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                                         # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#      Übertragung Datensätze in weitere DB
####################################################################################################
sub DbRep_syncStandby {
  my $paref                = shift;
  my $hash                 = $paref->{hash};
  my $name                 = $paref->{name};
  my $stbyname             = $paref->{prop};
  my $table                = $paref->{table};
  my $device               = $paref->{device};
  my $reading              = $paref->{reading};
  my $runtime_string_first = $paref->{rsf};
  my $runtime_string_next  = $paref->{rsn};
  my $ts                   = $paref->{ts};

  my $utf8                 = $hash->{UTF8} // 0;

  my ($dbhstby,$sql);

  # Standby-DB
  my $stbyhash   = $defs{$stbyname};
  my $stbyconn   = $stbyhash->{dbconn};
  my $stbyuser   = $stbyhash->{dbuser};
  my $stbypasswd = $attr{"sec$stbyname"}{secret};
  my $stbyutf8   = defined($stbyhash->{UTF8}) ? $stbyhash->{UTF8} : 0;

  my $bst = [gettimeofday];                                                  # Background-Startzeit

  # Verbindung zur Quell-DB
  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
  return "$name|$err" if ($err);

  # Verbindung zur Standby-DB
  eval {$dbhstby = DBI->connect("dbi:$stbyconn", $stbyuser, $stbypasswd, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $stbyutf8 });};
  if ($@) {
      $err = encode_base64($@,"");
      Log3 ($name, 2, "DbRep $name - $@");
      return "$name|$err";
  }

  my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash);                           # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)
  Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

  my $st = [gettimeofday];                                                           # SQL-Startzeit

  my ($sth,$old,$new);

  $err = DbRep_beginDatabaseTransaction ($name, $dbhstby);
  return "$name|$err" if ($err);

  my @ts = split("\\|", $ts);                                                        # Timestampstring to Array
  Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

  my $irows    = 0;                                                                  # DB-Abfrage zeilenweise für jeden Array-Eintrag
  my $selspec  = "TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT";
  my $addon    = '';

  for my $row (@ts) {
      my @a                     = split("#", $row);
      my $runtime_string        = $a[0];
      my $runtime_string_first  = $a[1];
      my $runtime_string_next   = $a[2];

      if ($IsTimeSet || $IsAggrSet) {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);
      }
      else {
          $sql = DbRep_createSelectSql($hash, $table, $selspec, $device, $reading, undef, undef, $addon);
      }

      Log3 ($name, 4, "DbRep $name - SQL execute: $sql");

      ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
      return "$name|$err" if ($err);

      no warnings 'uninitialized';

      #                          DATE _ESC_ TIME      _ESC_  DEVICE   _ESC_  TYPE    _ESC_   EVENT    _ESC_  READING  _ESC_   VALUE   _ESC_   UNIT
      my @row_array = map { ($_->[0] =~ s/ /_ESC_/r)."_ESC_".$_->[1]."_ESC_".$_->[2]."_ESC_".$_->[3]."_ESC_".$_->[4]."_ESC_".$_->[5]."_ESC_".$_->[6] } @{$sth->fetchall_arrayref()};
      use warnings;

      my $irowdone = 0;
      ($err, $irowdone) = DbRep_WriteToDB($name, $dbhstby, $stbyhash, 0, @row_array) if(@row_array);
      if ($err) {
          Log3 ($name, 2, "DbRep $name - $err");
          $err = encode_base64($err,"");
          $dbh->disconnect;
          $dbhstby->disconnect();
          return "$name|$err";
      }

      $irows += $irowdone;
  }

  $err = DbRep_commitOnly ($name, $dbhstby);
  return "$name|$err" if ($err);

  $dbh->disconnect();
  $dbhstby->disconnect();

  my $rt  = tv_interval($st);                                       # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                      # Background-Laufzeit ermitteln
  $rt     = $rt.",".$brt;
  $err    = 0;

return "$name|$err|$irows|$rt";
}

####################################################################################################
#         Auswertungsroutine Übertragung Datensätze in weitere DB
####################################################################################################
sub DbRep_syncStandbyDone {
  my $string     = shift;
  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';

  my $irows      = $a[2];
  my $bt         = $a[3];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "syncStandby");                             # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                            # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt)  = split ",", $bt;

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "number_lines_inserted_Standby", $irows);
  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, "syncStandby");                                   # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                                  # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#           reduceLog - Historische Werte ausduennen non-blocking > Forum #41089
#
#           $nts - reduce Logs neuer als: Attribut "timeDiffToNow" oder "timestamp_begin"
#           $ots - reduce Logs älter als: Attribut "timeOlderThan" oder "timestamp_end"
####################################################################################################
sub DbRep_reduceLog {
    my $paref      = shift;
    my $hash       = $paref->{hash};
    my $name       = $paref->{name};
    my $table      = $paref->{table};
    my $d          = $paref->{device};
    my $r          = $paref->{reading};
    my $nts        = $paref->{rsf};
    my $ots        = $paref->{rsn} // "";

    my @a   = @{$hash->{HELPER}{REDUCELOG}};
    my $err = q{};

    if (!$ots) {
        $err = qq{reduceLog needs at least one of attributes "timeOlderThan", "timeDiffToNow", "timestamp_begin" or "timestamp_end" to be set};
        Log3 ($name, 2, "DbRep $name - ERROR - $err");
        $err = encode_base64($err,"");
        return "$name|$err";
    }

    BlockingInformParent("DbRep_delHashValFromBlocking", [$name, "HELPER","REDUCELOG"], 1);

    shift @a;                                            # Devicenamen aus @a entfernen

    my @b;
    for my $w (@a) {                                     # ausfiltern von optionalen Zeitangaben, z.B. 700:750
        next if($w =~ /\b(\d+(:\d+)?)\b/);
        push @b, $w;
    }

    @a = @b;

    my ($pa,$ph) = parseParams(join ' ', @a);

    my $mode = (@$pa[1]        && @$pa[1] =~ /average/i)   ? 'average'     :
               ($ph->{average} && $ph->{average} eq "day") ? 'average=day' :
               (@$pa[1]        && @$pa[1] =~ /max/i)       ? 'max'         :
               ($ph->{max}     && $ph->{max} eq "day")     ? 'max=day'     :
               (@$pa[1]        && @$pa[1] =~ /min/i)       ? 'min'         :
               ($ph->{min}     && $ph->{min} eq "day")     ? 'min=day'     :
               (@$pa[1]        && @$pa[1] =~ /sum/i)       ? 'sum'         :
               ($ph->{sum}     && $ph->{sum} eq "day")     ? 'sum=day'     :
               q{};

    my $mstr = $mode =~ /average/i ? 'average' :
               $mode =~ /max/i     ? 'max'     :
               $mode =~ /min/i     ? 'min'     :
               $mode =~ /sum/i     ? 'sum'     :
               q{};

    my $excludes = $ph->{EXCLUDE} // q{};
    my $includes = $ph->{INCLUDE} // q{};

    my @excludeRegex;
    if ($excludes) {
        @excludeRegex = split ',', $excludes;
    }

    my ($dbh, $dbmodel);
    ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
    return "$name|$err" if ($err);

    my ($idevs,$idevswc,$idanz,$ireading,$iranz,$irdswc,$edevs,$edevswc,$edanz,$ereading,$eranz,$erdswc) = DbRep_specsForSql($hash,$d,$r);

    my ($IsTimeSet,$IsAggrSet,$aggregation) = DbRep_checktimeaggr($hash);              # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef)

    Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

    my $selspec = "SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $table where ";
    my $addon   = "ORDER BY TIMESTAMP ASC";

    my $valfilter = AttrVal($name, "valueFilter", undef);                               # Wertefilter

    my $specs = {
        hash      => $hash,
        selspec   => $selspec,
        device    => $d,
        reading   => $r,
        dbmodel   => $dbmodel,
        valfilter => $valfilter,
        addon     => $addon
    };

    my $sql;

    if($includes) {                                                                      # Option EX/INCLUDE wurde angegeben
        $sql = "SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $table WHERE "
               .($includes =~ /^(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
               ."TIMESTAMP <= '$ots'"
               .($nts ? " AND TIMESTAMP >= '$nts' " : " ")
               ."ORDER BY TIMESTAMP ASC";
    }
    elsif ($IsTimeSet || $IsAggrSet) {
        $specs->{rsf} = $nts;
        $specs->{rsn} = $ots;
        $sql          = DbRep_createCommonSql ($specs);
    }
    else {
        $sql = DbRep_createCommonSql ($specs);
    }

    Log3 ($name, 3, "DbRep $name - reduce data older than: $ots, newer than: $nts");

    Log3 ($name, 3, "DbRep $name - reduceLog requested with options: "
          .($mode ? "\n".$mode : '')
          .($includes  ? "\nINCLUDE -> $includes " :
           ((($idanz || $idevswc || $iranz || $irdswc) ? "\nINCLUDE -> " : '')
          . (($idanz || $idevswc)                      ? "Devs: ".($idevs ? $idevs : '').($idevswc ? $idevswc : '').' ' : '').(($iranz || $irdswc) ? "Readings: ".($ireading ? $ireading : '').($irdswc ? $irdswc : '') : '')
           ))
          .($excludes ? "\nEXCLUDE -> $excludes " :
           ((($edanz || $edevswc || $eranz || $erdswc) ? "\nEXCLUDE -> " : '')
          . (($edanz || $edevswc)                      ? "Devs: ".($edevs ? $edevs : '').($edevswc ? $edevswc : '').' ' : '').(($eranz || $erdswc) ? "Readings: ".($ereading ? $ereading : '').($erdswc ? $erdswc : '') : '')
           ))
         );

    ($err, my $sth_del)     = DbRep_prepareOnly ($name, $dbh, "DELETE FROM $table WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
    return "$name|$err" if ($err);

    ($err, my $sth_delNull) = DbRep_prepareOnly ($name, $dbh, "DELETE FROM $table WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND VALUE IS NULL");
    return "$name|$err" if ($err);

    ($err, my $sth_upd)     = DbRep_prepareOnly ($name, $dbh, "UPDATE $table SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
    return "$name|$err" if ($err);

    ($err, my $sth_delD)    = DbRep_prepareOnly ($name, $dbh, "DELETE FROM $table WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
    return "$name|$err" if ($err);

    ($err, my $sth_updD)    = DbRep_prepareOnly ($name, $dbh, "UPDATE $table SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
    return "$name|$err" if ($err);

    ($err, my $sth_get)     = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
    return "$name|$err" if ($err);


    ## Start
    ############################################

    # Ergebnis von $sth_get->fetchrow_arrayref:
    # $row->[0] = Datum (YYYY-MM-DD hh:mm:ss)
    # $row->[1] = Device
    # $row->[2] = leer
    # $row->[3] = Reading
    # $row->[4] = Value

    my $ndp = AttrVal($name, "numDecimalPlaces", $dbrep_defdecplaces);

    my ($day, $hour, $processingDay, $params);
    my (%hourlyKnown,@dayRows,@updateHour,@updateDay);
    my ($startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$rowCount,$excludeCount) = (time(),99,0,0,0,0,0);

    do {
        my $row      = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];        # || execute last-day dummy
        my $ts       = $row->[0];
        my $device   = $row->[1];
        my $reading  = $row->[3];
        my $value    = $row->[4];
        ($day,$hour) = $ts =~ /-(\d{2})\s(\d{2}):/;

        $rowCount++ if($day != 00);

        ## verarbeiten der unten vorbereiteten Arrays und Hashes
        #########################################################

        if ($day != $currentDay) {
            if ($currentDay) {                                                             # nicht am ersten ausgeführten Tag
                if (scalar @dayRows) {                                                     # alle Tageseinträge löschen

                    $params = {
                        name            => $name,
                        dbh             => $dbh,
                        sth_del         => $sth_del,
                        sth_delNull     => $sth_delNull,
                        table           => $table,
                        dayRowsref      => \@dayRows,
                        deletedCountref => \$deletedCount,
                        processingDay   => $processingDay,
                        ndp             => $ndp
                    };

                    $err = _DbRep_rl_deleteDayRows ($params);
                    return "$name|$err" if ($err);

                    undef @dayRows;
                }

                if ($mode =~ /average|max|min|sum/i) {

                    $params = {
                        name            => $name,
                        dbh             => $dbh,
                        sth_upd         => $sth_upd,
                        mode            => $mode,
                        mstr            => $mstr,
                        table           => $table,
                        hourlyKnownref  => \%hourlyKnown,
                        updateHourref   => \@updateHour,
                        updateDayref    => \@updateDay,
                        updateCountref  => \$updateCount,
                        processingDay   => $processingDay,
                        ndp             => $ndp
                    };

                    $err = _DbRep_rl_updateHour ($params);
                    return "$name|$err" if ($err);

                    undef @updateHour;
                }

                if ($mode =~ /=day/i && scalar @updateDay) {

                    $params = {
                        name            => $name,
                        dbh             => $dbh,
                        sth_delD        => $sth_delD,
                        sth_updD        => $sth_updD,
                        mode            => $mode,
                        mstr            => $mstr,
                        table           => $table,
                        updateDayref    => \@updateDay,
                        deletedCountref => \$deletedCount,
                        updateCountref  => \$updateCount,
                        processingDay   => $processingDay,
                        ndp             => $ndp
                    };

                    $err = _DbRep_rl_updateDay ($params);
                    return "$name|$err" if ($err);

                }

                undef %hourlyKnown;
                undef @updateHour;
                undef @updateDay;
                $currentHour = 99;
            }

            $currentDay = $day;
        }

        ## Füllen Arrays und Hashes
        ############################

        if ($hour != $currentHour) {                                              # forget records from last hour, but remember these for average
            if ($mode =~ /average|max|min|sum/i && keys(%hourlyKnown)) {
                push(@updateHour, {%hourlyKnown});
            }

            undef %hourlyKnown;
            $currentHour = $hour;
        }

        if (defined $hourlyKnown{$device.$reading}) {                             # das erste reading pro device und Stunde wird nicht in @dayRows (zum Löschen) gespeichert, die anderen können gelöscht werden
            push(@dayRows, [@$row]);

            if ($mode =~ /average|max|min|sum/i         &&
                defined($value)                         &&
                DbRep_IsNumeric ($value)                &&
                $hourlyKnown{$device.$reading}->[0]) {

                if ($hourlyKnown{$device.$reading}->[0]) {
                    push(@{$hourlyKnown{$device.$reading}->[4]}, $value);
                }
            }
        }
        else {
            my $exclude = 0;

            for my $exreg (@excludeRegex) {
                $exclude = 1 if("$device:$reading" =~ /^$exreg$/);
            }

            if ($exclude) {
                $excludeCount++ if($day != 00);
            }
            else {
                $hourlyKnown{$device.$reading} = DbRep_IsNumeric ($value)                  ?
                                                 [$ts,$device,$row->[2],$reading,[$value]] :
                                                 [0];
            }
        }

        $processingDay = (split ' ', $ts)[0];                                     # $ts = Datum (YYYY-MM-DD hh:mm:ss)

    } while ($day != 00);                                                         # die do...while-Anweisung überprüft die Bedingung am Ende jeder Iteration.

    #########################################   Ende

    my $brt = time() - $startTime;

    my $result = "Rows processed: $rowCount, deleted: $deletedCount"
                 .($mode =~ /average|max|min|sum/i ? ", updated: $updateCount"   : '')
                 .($excludeCount                   ? ", excluded: $excludeCount" : '');

    Log3 ($name, 3, "DbRep $name - reduceLog finished. $result");

    $dbh->disconnect();

    my $ret = encode_base64("reduceLog finished. $result", "");

return "$name|$err|$ret|$brt";
}

####################################################################################################
#           reduceLog alle im @dayRows Array enthaltene DB Einträge löschen
####################################################################################################
sub _DbRep_rl_deleteDayRows {
  my $paref           = shift;
  my $name            = $paref->{name};
  my $dbh             = $paref->{dbh};
  my $sth_del         = $paref->{sth_del};
  my $sth_delNull     = $paref->{sth_delNull};
  my $table           = $paref->{table};
  my $dayRowsref      = $paref->{dayRowsref};
  my $deletedCountref = $paref->{deletedCountref};
  my $processingDay   = $paref->{processingDay};

  my $err     = q{};
  my $c       = 0;
  my @dayRows = @{$dayRowsref};

  #Log3 ($name, 3, "DbRep $name - content dayRows Array:\n".Dumper @dayRows);

  for my $delRow (@dayRows) {
      $c++;
  }

  if($c) {
      ${$deletedCountref} += $c;

      Log3 ($name, 3, "DbRep $name - reduceLog deleting $c records of day: $processingDay");

      $err = DbRep_beginDatabaseTransaction ($name, $dbh);
      return $err if ($err);

      eval {
          my $i  = 0;
          my $k  = 1;
          my $th = _DbRep_rl_logThreshold ($#dayRows);

          for my $delRow (@dayRows) {
              my $device  = $delRow->[1];
              my $reading = $delRow->[3];
              my $time    = $delRow->[0];
              my $value   = $delRow->[4] // 'NULL';

              if ($value eq 'NULL') {
                  Log3 ($name, 5, "DbRep $name - DELETE FROM $table WHERE (DEVICE=$device) AND (READING=$reading) AND (TIMESTAMP=$time) AND VALUE IS $value");

                  $sth_delNull->execute($device, $reading, $time);
              }
              else {
                  Log3 ($name, 5, "DbRep $name - DELETE FROM $table WHERE (DEVICE=$device) AND (READING=$reading) AND (TIMESTAMP=$time) AND (VALUE=$value)");

                  $sth_del->execute($device, $reading, $time, $value);
              }

              $i++;

              my $params = {
                  name          => $name,
                  logtxt        => "deletion",
                  iref          => \$i,
                  kref          => \$k,
                  th            => $th,
                  processingDay => $processingDay
              };

              _DbRep_rl_logProgress ($params);
          }
          1;
      }
      or do {
          $err = encode_base64($@, "");

          Log3 ($name, 2, "DbRep $name - ERROR - reduceLog failed for day $processingDay: $@");

          DbRep_rollbackOnly ($name, $dbh);
          return $err;
      };

      $err = DbRep_commitOnly ($name, $dbh);
      return $err if ($err);
  }

return $err;
}

####################################################################################################
#           reduceLog
#           Stundenupdates vornehmen und @updateDay füllen bei
#           $mode = *=day
####################################################################################################
sub _DbRep_rl_updateHour {
  my $paref           = shift;
  my $name            = $paref->{name};
  my $dbh             = $paref->{dbh};
  my $sth_upd         = $paref->{sth_upd};
  my $mode            = $paref->{mode};
  my $mstr            = $paref->{mstr};
  my $table           = $paref->{table};
  my $hourlyKnownref  = $paref->{hourlyKnownref};
  my $updateHourref   = $paref->{updateHourref};
  my $updateDayref    = $paref->{updateDayref};
  my $updateCountref  = $paref->{updateCountref};
  my $processingDay   = $paref->{processingDay};
  my $ndp             = $paref->{ndp};

  my $err = q{};
  my $c   = 0;

  #Log3 ($name, 3, "DbRep $name - content hourlyKnown Hash:\n".Dumper %$hourlyKnownref);

  push(@$updateHourref, {%$hourlyKnownref});

  for my $hourHash (@$updateHourref) {                                                             # Only count for logging...
      for my $hourKey (keys %$hourHash) {
          $c++ if ($hourHash->{$hourKey}->[0] && scalar @{$hourHash->{$hourKey}->[4]} > 1);
      }
  }

  ${$updateCountref} += $c;

  if($c) {
      Log3 ($name, 3, "DbRep $name - reduceLog (hourly-$mstr) updating $c records of day: $processingDay");

      $err = DbRep_beginDatabaseTransaction ($name, $dbh);
      return $err if ($err);
  }

  my ($params, $value);
  my $i   = 0;
  my $k   = 1;
  my $th  = _DbRep_rl_logThreshold ($c);

  my $event = $mstr eq 'average' ? 'rl_av_h'  :
              $mstr eq 'max'     ? 'rl_max_h' :
              $mstr eq 'min'     ? 'rl_min_h' :
              $mstr eq 'sum'     ? 'rl_sum_h' :
              'rl_h';

  my $updminutes = $mstr eq 'average' ? '30:00' :
                   $mstr eq 'max'     ? '59:59' :
                   $mstr eq 'min'     ? '00:01' :
                   $mstr eq 'sum'     ? '00:00' :
                   '00:00';

  #Log3 ($name, 3, "DbRep $name - content updateHour Array:\n".Dumper @$updateHourref);

  $paref->{updminutes} = $updminutes;
  $paref->{event}      = $event;
  $paref->{th}         = $th;
  $paref->{iref}       = \$i;
  $paref->{kref}       = \$k;

  for my $hourHash (@$updateHourref) {

      for my $hourKey (keys %$hourHash) {

          next if (!$hourHash->{$hourKey}->[0]);
          my ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;

          $paref->{updDate}    = $updDate;
          $paref->{updHour}    = $updHour;
          $paref->{timestamp}  = $hourHash->{$hourKey}->[0];
          $paref->{device}     = $hourHash->{$hourKey}->[1];
          $paref->{reading}    = $hourHash->{$hourKey}->[3];
          $paref->{oldvalue}   = $hourHash->{$hourKey}->[4]->[0];

          if (scalar @{$hourHash->{$hourKey}->[4]} > 1) {                                 # wahr wenn reading hat mehrere Datensätze diese Stunde

              $i++;

              $paref->{hourHashKeyRef} = $hourHash->{$hourKey}->[4];

              if ($mstr eq 'average') {                                                   # Berechnung Average
                  $value = __DbRep_rl_calcAverageHourly ($paref);
              }
              elsif ($mstr eq 'max') {                                                    # Berechnung Max
                  $value = __DbRep_rl_calcMaxHourly ($paref);
              }
              elsif ($mstr eq 'min') {                                                    # Berechnung Min
                  $value = __DbRep_rl_calcMinHourly ($paref);
              }
              elsif ($mstr eq 'sum') {                                                    # Berechnung Summary
                  $value = __DbRep_rl_calcSumHourly ($paref);
              }

              $paref->{logtxt}   = "(hourly-$mstr) updating";
              $paref->{newvalue} = $value;

              $err = __DbRep_rl_updateHourDatabase ($paref);

              if ($err) {
                  Log3 ($name, 2, "DbRep $name - ERROR - reduceLog $mstr failed for day $processingDay: $err");
                  $err = encode_base64($err, "");

                  DbRep_rollbackOnly ($name, $dbh);
                  return $err;
              }
          }
          else {
              __DbRep_rl_onlyFillDayArray ($paref);
          }
      }
  }

  if($c) {
      $err = DbRep_commitOnly ($name, $dbh);
      return $err if ($err);
  }

return $err;
}

####################################################################################################
#           reduceLog stündlichen average Wert berechnen
####################################################################################################
sub __DbRep_rl_calcAverageHourly {
  my $paref          = shift;
  my $name           = $paref->{name};
  my $hourHashKeyRef = $paref->{hourHashKeyRef};
  my $ndp            = $paref->{ndp};

  my $sum = 0;

  for my $val (@{$hourHashKeyRef}) {
      $sum += $val;
  }

  my $value = sprintf "%.${ndp}f", $sum / scalar @{$hourHashKeyRef};

return $value;
}

####################################################################################################
#           reduceLog stündlichen Max Wert berechnen
####################################################################################################
sub __DbRep_rl_calcMaxHourly {
  my $paref          = shift;
  my $name           = $paref->{name};
  my $hourHashKeyRef = $paref->{hourHashKeyRef};
  my $ndp            = $paref->{ndp};

  my $max;

  for my $val (@{$hourHashKeyRef}) {
      if (!defined $max) {
          $max = $val;
      }
      else {
          $max = $val if ($val > $max);
      }
  }

  my $value = sprintf "%.${ndp}f", $max;

return $value;
}

####################################################################################################
#           reduceLog stündlichen Min Wert berechnen
####################################################################################################
sub __DbRep_rl_calcMinHourly {
  my $paref          = shift;
  my $name           = $paref->{name};
  my $hourHashKeyRef = $paref->{hourHashKeyRef};
  my $ndp            = $paref->{ndp};

  my $min;

  for my $val (@{$hourHashKeyRef}) {
      if (!defined $min) {
          $min = $val;
      }
      else {
          $min = $val if ($val < $min);
      }
  }

  my $value = sprintf "%.${ndp}f", $min;

return $value;
}

####################################################################################################
#           reduceLog stündlichen summary Wert berechnen
####################################################################################################
sub __DbRep_rl_calcSumHourly {
  my $paref          = shift;
  my $name           = $paref->{name};
  my $hourHashKeyRef = $paref->{hourHashKeyRef};
  my $ndp            = $paref->{ndp};

  my $sum = 0;

  for my $val (@{$hourHashKeyRef}) {
      $sum += $val;
  }

  my $value = sprintf "%.${ndp}f", $sum;

return $value;
}

################################################################
#   reduceLog Stundenupdate Datenbank und
#   füllen Tages Update Array
################################################################
sub __DbRep_rl_updateHourDatabase {
  my $paref        = shift;
  my $name         = $paref->{name};
  my $mode         = $paref->{mode};
  my $table        = $paref->{table};
  my $sth_upd      = $paref->{sth_upd};
  my $updateDayref = $paref->{updateDayref};
  my $updDate      = $paref->{updDate};
  my $updHour      = $paref->{updHour};
  my $updminutes   = $paref->{updminutes};
  my $event        = $paref->{event};
  my $newvalue     = $paref->{newvalue};
  my $device       = $paref->{device};
  my $reading      = $paref->{reading};
  my $timestamp    = $paref->{timestamp};
  my $oldvalue     = $paref->{oldvalue};

  Log3 ($name, 4, "DbRep $name - UPDATE $table SET TIMESTAMP=$updDate $updHour:$updminutes, EVENT=$event, VALUE=$newvalue WHERE DEVICE=$device AND READING=$reading AND TIMESTAMP=$timestamp AND VALUE=$oldvalue");

  eval { $sth_upd->execute("$updDate $updHour:$updminutes", $event, $newvalue, $device, $reading, $timestamp, $oldvalue);
       }
       or do { return $@;
             };

  _DbRep_rl_logProgress ($paref);

  if ($mode =~ /=day/i) {
      push(@$updateDayref, ["$updDate $updHour:$updminutes", $event, $newvalue, $device, $reading, $updDate]);
  }

return;
}

################################################################
#   reduceLog Tages Array füllen
################################################################
sub __DbRep_rl_onlyFillDayArray {
  my $paref        = shift;
  my $mode         = $paref->{mode};
  my $updateDayref = $paref->{updateDayref};
  my $timestamp    = $paref->{timestamp};
  my $event        = $paref->{event};
  my $oldvalue     = $paref->{oldvalue};
  my $device       = $paref->{device};
  my $reading      = $paref->{reading};
  my $updDate      = $paref->{updDate};

  if ($mode =~ /=day/i) {
      push(@$updateDayref, [$timestamp, $event, $oldvalue, $device, $reading, $updDate]);
  }

return;
}

####################################################################################################
#           reduceLog Tagesupdates vornehmen
####################################################################################################
sub _DbRep_rl_updateDay {
  my $paref           = shift;
  my $name            = $paref->{name};
  my $dbh             = $paref->{dbh};
  my $sth_delD        = $paref->{sth_delD};
  my $sth_updD        = $paref->{sth_updD};
  my $mode            = $paref->{mode};
  my $mstr            = $paref->{mstr};
  my $table           = $paref->{table};
  my $updateDayref    = $paref->{updateDayref};
  my $deletedCountref = $paref->{deletedCountref};
  my $updateCountref  = $paref->{updateCountref};
  my $processingDay   = $paref->{processingDay};
  my $ndp             = $paref->{ndp};

  my $err = q{};

  #Log3 ($name, 3, "DbRep $name - content updateDay Array:\n".Dumper @$updateDayref);

  my %updateHash;

  for my $row (@$updateDayref) {
      $updateHash{$row->[3].$row->[4]}->{date} = $row->[5];
      push @{$updateHash{$row->[3].$row->[4]}->{tedr}}, [$row->[0], $row->[1], $row->[3], $row->[4]];           # tedr -> time, event, device, reading

      if ($mstr eq 'average') {                                                                                 # Day Average
          $updateHash{$row->[3].$row->[4]}->{sum} += $row->[2];                                                 # Summe aller Werte
      }
      elsif ($mstr eq 'max') {                                                                                  # Day Max
          if (!defined $updateHash{$row->[3].$row->[4]}->{max}) {
              $updateHash{$row->[3].$row->[4]}->{max} = $row->[2];
          }
          else {
              $updateHash{$row->[3].$row->[4]}->{max} = $row->[2] if ($row->[2] > $updateHash{$row->[3].$row->[4]}->{max});
          }
      }
      elsif ($mstr eq 'min') {                                                                                  # Day Min
          if (!defined $updateHash{$row->[3].$row->[4]}->{min}) {
              $updateHash{$row->[3].$row->[4]}->{min} = $row->[2];
          }
          else {
              $updateHash{$row->[3].$row->[4]}->{min} = $row->[2] if ($row->[2] < $updateHash{$row->[3].$row->[4]}->{min});
          }
      }
      elsif ($mstr eq 'sum') {                                                                                  # Day Summary
          $updateHash{$row->[3].$row->[4]}->{sum} += $row->[2];                                                 # Summe aller Werte
      }
  }

  my $c = 0;

  for my $key (keys %updateHash) {
      if(scalar @{$updateHash{$key}->{tedr}} == 1) {
          delete $updateHash{$key};
      }
      else {
          $c += (scalar @{$updateHash{$key}->{tedr}} - 1);
      }
  }

  ${$deletedCountref} += $c;
  ${$updateCountref}  += keys %updateHash;

  my ($params, $value);
  my ($id,$iu) = (0,0);
  my ($kd,$ku) = (1,1);
  my $thd      = _DbRep_rl_logThreshold ($c);
  my $thu      = _DbRep_rl_logThreshold (scalar keys %updateHash);

  my $event = $mstr eq 'average' ? 'rl_av_d'  :
              $mstr eq 'max'     ? 'rl_max_d' :
              $mstr eq 'min'     ? 'rl_min_d' :
              $mstr eq 'sum'     ? 'rl_sum_d' :
              'rl_d';

  my $time  = $mstr eq 'average' ? '12:00:00' :
              $mstr eq 'max'     ? '23:59:59' :
              $mstr eq 'min'     ? '00:00:01' :
              $mstr eq 'sum'     ? '12:00:00' :
              '00:00:00';

  $paref->{time}  = $time;
  $paref->{event} = $event;

  if(keys %updateHash) {
      Log3 ($name, 3, "DbRep $name - reduceLog (daily-$mstr) updating ".(keys %updateHash).", deleting $c records of day: $processingDay");

      $err = DbRep_beginDatabaseTransaction ($name, $dbh);
      return $err if ($err);
  }

  for my $uhk (keys %updateHash) {

      if ($mstr eq 'average') {                                                                          # Day Average
          $value = sprintf "%.${ndp}f", $updateHash{$uhk}->{sum} / scalar @{$updateHash{$uhk}->{tedr}};
      }
      elsif ($mstr eq 'max') {                                                                           # Day Max
          $value = sprintf "%.${ndp}f", $updateHash{$uhk}->{max};
      }
      elsif ($mstr eq 'min') {                                                                           # Day Min
          $value = sprintf "%.${ndp}f", $updateHash{$uhk}->{min};
      }
      elsif ($mstr eq 'sum') {                                                                           # Day Summary
          $value = sprintf "%.${ndp}f", $updateHash{$uhk}->{sum};
      }

      my $lastUpdH = pop @{$updateHash{$uhk}->{tedr}};

      for my $tedr (@{$updateHash{$uhk}->{tedr}}) {
          $id++;

          $paref->{logtxt}    = "(daily-$mstr) deleting";
          $paref->{iref}      = \$id;
          $paref->{kref}      = \$kd;
          $paref->{th}        = $thd;
          $paref->{timestamp} = $tedr->[0];
          $paref->{device}    = $tedr->[2];
          $paref->{reading}   = $tedr->[3];

          $err = __DbRep_rl_deleteDayDatabase ($paref);

          if ($err) {
              Log3 ($name, 3, "DbRep $name - ERROR - reduceLog $mstr=day failed for day $processingDay: $err");
              $err = encode_base64($err, "");

              DbRep_rollbackOnly ($name, $dbh);
              return $err;
          }
      }

      $iu++;

      $paref->{logtxt}    = "(daily-$mstr) updating";
      $paref->{iref}      = \$iu;
      $paref->{kref}      = \$ku;
      $paref->{th}        = $thu;
      $paref->{date}      = $updateHash{$uhk}->{date};
      $paref->{timestamp} = $lastUpdH->[0];
      $paref->{device}    = $lastUpdH->[2];
      $paref->{reading}   = $lastUpdH->[3];
      $paref->{value}     = $value;

      $err = __DbRep_rl_updateDayDatabase ($paref);

      if ($err) {
          Log3 ($name, 3, "DbRep $name - ERROR - reduceLog $mstr=day failed for day $processingDay: $err");
          $err = encode_base64($err, "");

          DbRep_rollbackOnly ($name, $dbh);
          return $err;
      }
  }

  if(keys %updateHash) {
      $err = DbRep_commitOnly ($name, $dbh);
      return $err if ($err);
  }

return $err;
}

################################################################
#   reduceLog Tageswerte löschen
################################################################
sub __DbRep_rl_deleteDayDatabase {
  my $paref        = shift;
  my $name         = $paref->{name};
  my $table        = $paref->{table};
  my $sth_delD     = $paref->{sth_delD};
  my $device       = $paref->{device};
  my $reading      = $paref->{reading};
  my $timestamp    = $paref->{timestamp};

  Log3 ($name, 4, "DbRep $name - DELETE FROM $table WHERE DEVICE='$device' AND READING='$reading' AND TIMESTAMP='$timestamp'");

  eval { $sth_delD->execute($device, $reading, $timestamp);
       }
       or do { return $@;
             };

  _DbRep_rl_logProgress ($paref);

return;
}

################################################################
#   reduceLog Tageswerte updaten
################################################################
sub __DbRep_rl_updateDayDatabase {
  my $paref        = shift;
  my $name         = $paref->{name};
  my $table        = $paref->{table};
  my $sth_updD     = $paref->{sth_updD};
  my $event        = $paref->{event};
  my $device       = $paref->{device};
  my $reading      = $paref->{reading};
  my $value        = $paref->{value};
  my $date         = $paref->{date};
  my $time         = $paref->{time};
  my $timestamp    = $paref->{timestamp};

  Log3 ($name, 4, "DbRep $name - UPDATE $table SET TIMESTAMP=$date $time, EVENT=$event, VALUE=$value WHERE (DEVICE=$device) AND (READING=$reading) AND (TIMESTAMP=$timestamp)");

  eval { $sth_updD->execute("$date $time", $event, $value, $device, $reading, $timestamp);
       }
       or do { return $@;
             };

  _DbRep_rl_logProgress ($paref);

return;
}

####################################################################################################
#           reduceLog Grenzen für Logausgabe abhängig von der Zeilenanzahl
####################################################################################################
sub _DbRep_rl_logThreshold {
  my $rn = shift;

  my $th = ($rn <= 2000)  ? 100  :
           ($rn <= 30000) ? 1000 :
           10000;

return $th;
}

################################################################
#   reduceLog Logausgabe Fortschritt
################################################################
sub _DbRep_rl_logProgress {
  my $paref           = shift;
  my $name            = $paref->{name};
  my $logtxt          = $paref->{logtxt};
  my $iref            = $paref->{iref};
  my $kref            = $paref->{kref};
  my $th              = $paref->{th};
  my $processingDay   = $paref->{processingDay};

  if(${$iref} == $th) {
      my $prog = ${$kref} * ${$iref};

      Log3 ($name, 3, "DbRep $name - reduceLog $logtxt progress of day: $processingDay is: $prog");

      ${$iref} = 0;
      ${$kref}++;
  }

return;
}

####################################################################################################
#                   reduceLog non-blocking Rückkehrfunktion
####################################################################################################
sub DbRep_reduceLogDone {
  my $string    = shift;
  my @a         = split("\\|",$string);
  my $name      = $a[0];
  my $err       = $a[1] ? decode_base64($a[1]) : '';
  my $ret       = $a[2] ? decode_base64($a[2]) : '';
  my $brt       = $a[3];

  my $hash      = $defs{$name};
  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  delete $hash->{HELPER}{RUNNING_REDUCELOG};

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, "reduceLog");                       # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                    # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  readingsBeginUpdate     ($hash);
  ReadingsBulkUpdateValue ($hash, "background_processing_time", sprintf("%.2f", $brt));
  ReadingsBulkUpdateValue ($hash, "reduceLogState", $ret);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, "reduceLog");                             # Befehl nach Procedure ausführen
  DbRep_nextMultiCmd      ($name);                                          # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#          Migration DB / Tabellen Charset und Collation
####################################################################################################
sub DbRep_migCollation {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $opt       = $paref->{opt};
  my $collation = $paref->{prop};

  my $db    = $hash->{DATABASE};
  my $utf8  = $hash->{UTF8} // 0;

  my @se    = ();
  my ($sth, $table);

  my $bst = [gettimeofday];                                                     # Background-Startzeit

  my $charset = (split '_', $collation, 2)[0];

  my ($err,$dbh,$dbmodel) = DbRep_dbConnect($name);
  return "$name|$err" if ($err);

  my $st = [gettimeofday];                                                      # SQL-Startzeit

  # DB Migration
  ###############
  Log3 ($name, 3, "DbRep $name - migrate database >$db< collation to >$collation<, please be patient ...");

  ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(ALTER DATABASE $db CHARACTER SET = $charset COLLATE = $collation));
  return "$name|$err" if ($err);

  ($err, @se) = DbRep_prepareExec2Array ($name, $dbh, qq(SHOW VARIABLES LIKE 'collation_database'));
  return "$name|$err" if ($err);

  my $dcs = @se ? $se[1] : 'no result';

  Log3 ($name, 4, "DbRep $name - new Collation of database >$db< is >$dcs<");

  # Tabelle history Migration
  #############################
  ($err, my $hcs) = _DbRep_migCollTable ( {name      => $name,
                                           dbh       => $dbh,
                                           table     => 'history',
                                           db        => $db,
                                           charset   => $charset,
                                           collation => $collation
                                          }
                                        );
  return "$name|$err" if ($err);

  # Tabelle current Migration
  #############################
  ($err, my $ccs) = _DbRep_migCollTable ( {name      => $name,
                                           dbh       => $dbh,
                                           table     => 'current',
                                           db        => $db,
                                           charset   => $charset,
                                           collation => $collation
                                          }
                                        );
  return "$name|$err" if ($err);

  Log3 ($name, 3, "DbRep $name - migration done");

  $dbh->disconnect;

  my $rt   = tv_interval($st);                                            # SQL-Laufzeit ermitteln
  my $brt  = tv_interval($bst);                                           # Background-Laufzeit ermitteln
  $rt      = $rt.",".$brt;
  $err     = q{};

return "$name|$err|$dcs|$ccs|$hcs|$rt|$opt";
}

####################################################################################################
#          Migration Tabellen Charset und Collation
####################################################################################################
sub _DbRep_migCollTable {
  my $paref     = shift;

  my $name      = $paref->{name};
  my $dbh       = $paref->{dbh};
  my $table     = $paref->{table};
  my $db        = $paref->{db};
  my $charset   = $paref->{charset};
  my $collation = $paref->{collation};

  Log3 ($name, 3, "DbRep $name - migrate table >$table< collation to >$collation< ... be patient ...");

  my ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, qq(ALTER TABLE $table CONVERT TO CHARACTER SET $charset COLLATE $collation));
  return $err if ($err);

  ($err, my @se) = DbRep_prepareExec2Array ($name, $dbh, qq(SELECT TABLE_COLLATION FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = "$table" and TABLE_SCHEMA = "$db"));
  return $err if ($err);

  my $col = @se ? $se[0] : 'no result';

  Log3 ($name, 4, "DbRep $name - new Collation of table >$table< is >$col<");

return ($err, $col);
}

####################################################################################################
# Auswertungsroutine Migration DB / Tabellen Charset und Collation
####################################################################################################
sub DbRep_migCollation_Done {
  my $string     = shift;

  my @a          = split("\\|",$string);
  my $name       = $a[0];
  my $err        = $a[1] ? decode_base64($a[1]) : '';
  my $dcs        = $a[2];
  my $ccs        = $a[3];
  my $hcs        = $a[4];
  my $bt         = $a[5];
  my $opt        = $a[6];

  my $hash       = $defs{$name};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});

  delete($hash->{HELPER}{RUNNING_PID});

  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err,    1);
      ReadingsSingleUpdateValue ($hash, "state",     "error", 1);

      DbRep_afterproc           ($hash, $hash->{LASTCMD});                                 # Befehl nach Procedure ausführen
      DbRep_nextMultiCmd        ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

      return;
  }

  my ($rt,$brt) = split ",", $bt;

  readingsBeginUpdate     ($hash);

  ReadingsBulkUpdateValue ($hash, 'collation_database',      $dcs);
  ReadingsBulkUpdateValue ($hash, 'collation_table_current', $ccs);
  ReadingsBulkUpdateValue ($hash, 'collation_table_history', $hcs);

  ReadingsBulkUpdateTime  ($hash, $brt, $rt);
  readingsEndUpdate       ($hash, 1);

  DbRep_afterproc         ($hash, $hash->{LASTCMD});                                      # Befehl nach Procedure ausführen incl. state
  DbRep_nextMultiCmd      ($name);                                                        # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub DbRep_ParseAborted {
  my $hash   = shift;
  my $cause  = shift // "Timeout: process terminated";

  my $name   = $hash->{NAME};
  my $dbh    = $hash->{DBH};

  Log3 ($name, 5, qq{DbRep $name - BlockingCall PID "$hash->{HELPER}{RUNNING_PID}{pid}" finished});
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");

  delete($hash->{HELPER}{RUNNING_PID});

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "command");                                # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state  = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database command aborted: \"$cause\" ");

  DbRep_nextMultiCmd ($name);                                                     # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                                Abbruchroutine Timeout reduceLog
####################################################################################################
sub DbRep_reduceLogAborted {
  my $hash  = shift;
  my $cause = shift // "Timeout: process terminated";

  my $name  = $hash->{NAME};
  my $dbh   = $hash->{DBH};

  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_REDUCELOG}{fn} pid:$hash->{HELPER}{RUNNING_REDUCELOG}{pid} $cause") if($hash->{HELPER}{RUNNING_REDUCELOG});

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "reduceLog");                             # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state = $cause.$erread;
  $dbh->disconnect() if(defined($dbh));

  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database reduceLog aborted: \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_REDUCELOG});

  DbRep_nextMultiCmd ($name);                                                    # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Timeout Restore
####################################################################################################
sub DbRep_restoreAborted {
  my $hash  = shift;
  my $cause = shift // "Timeout: process terminated";

  my $name  = $hash->{NAME};
  my $dbh   = $hash->{DBH};

  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_RESTORE}{fn} pid:$hash->{HELPER}{RUNNING_RESTORE}{pid} $cause") if($hash->{HELPER}{RUNNING_RESTORE});

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "restore");                              # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database restore aborted: \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_RESTORE});

  DbRep_nextMultiCmd ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Dump
####################################################################################################
sub DbRep_DumpAborted {
  my $hash  = shift;
  my $cause = shift // "Timeout: process terminated";

  my $name  = $hash->{NAME};
  my $dbh   = $hash->{DBH};

  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BACKUP_CLIENT}{fn} pid:$hash->{HELPER}{RUNNING_BACKUP_CLIENT}{pid} $cause") if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BCKPREST_SERVER}{fn} pid:$hash->{HELPER}{RUNNING_BCKPREST_SERVER}{pid} $cause") if($hash->{HELPER}{RUNNING_BCKPREST_SERVER});

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "dump");                                 # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database dump aborted: \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});

  DbRep_nextMultiCmd ($name);                                                   # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub DbRep_OptimizeAborted {
  my $hash  = shift;
  my $cause = shift // "Timeout: process terminated";

  my $name  = $hash->{NAME};
  my $dbh   = $hash->{DBH};

  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_OPTIMIZE}}{fn} pid:$hash->{HELPER}{RUNNING_OPTIMIZE}{pid} $cause");

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "optimize");                            # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);

  Log3 ($name, 2, "DbRep $name - Database optimize aborted: \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_OPTIMIZE});

  DbRep_nextMultiCmd ($name);                                                  # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#                    Abbruchroutine Repair SQlite
####################################################################################################
sub DbRep_RepairAborted {
  my $hash      = shift;
  my $cause     = shift // "Timeout: process terminated";

  my $name      = $hash->{NAME};
  my $dbh       = $hash->{DBH};
  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};

  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_REPAIR}{fn} pid:$hash->{HELPER}{RUNNING_REPAIR}{pid} $cause");

  # Datenbankverbindung in DbLog wieder öffenen
  my $dbl = $dbloghash->{NAME};
  CommandSet(undef,"$dbl reopen");

  ReadingsSingleUpdateValue ($hash, 'state', 'Abort', 0);

  my $erread = DbRep_afterproc ($hash, "repair");                             # Befehl nach Procedure ausführen
  $erread    = ", ".(split("but", $erread))[1] if($erread);

  my $state = $cause.$erread;

  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash,"state",$state, 1);

  Log3 ($name, 2, "DbRep $name - Database repair aborted: \"$cause\" ");

  delete($hash->{HELPER}{RUNNING_REPAIR});

  DbRep_nextMultiCmd ($name);                                                 # nächstes multiCmd ausführen falls gesetzt

return;
}

####################################################################################################
#               SQL-Statement zusammenstellen Common
####################################################################################################
sub DbRep_createCommonSql {
  my $specs     = shift;
  my $hash      = $specs->{hash};
  my $selspec   = $specs->{selspec} // q{};
  my $device    = $specs->{device};
  my $reading   = $specs->{reading};
  my $dbmodel   = $specs->{dbmodel};
  my $rsf       = $specs->{rsf};
  my $rsn       = $specs->{rsn};
  my $valfilter = $specs->{valfilter};
  my $addon     = $specs->{addon} // q{};

  my ($sql,$vf,@dwc,@rwc);

  my ($idevs,$idevswc,$idanz,$ireading,$iranz,$irdswc,$edevs,$edevswc,$edanz,$ereading,$eranz,$erdswc) = DbRep_specsForSql($hash,$device,$reading);

  my $tnfull = 0;

  if($rsn && $rsn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
      $tnfull = 1;
  }

  if(defined $valfilter) {
      if ($dbmodel eq "POSTGRESQL") {
          $vf = "VALUE ~ '$valfilter' AND ";
      }
      else {
          $vf = "VALUE REGEXP '$valfilter' AND ";
      }
  }

  $sql = $selspec." " if($selspec);

  # included devices
  ###################
  $sql .= "( "                                 if(($idanz || $idevswc) && $idevs !~ m(^%$));
  if($idevswc && $idevs !~ m(^%$)) {
      @dwc    = split ",", $idevswc;
      my $i   = 1;
      my $len = scalar(@dwc);

      for (@dwc) {
          if($i<$len) {
              $sql .= "DEVICE LIKE '$_' OR ";
          }
          else {
              $sql .= "DEVICE LIKE '$_' ";
          }
          $i++;
      }

      if($idanz) {
          $sql .= "OR ";
      }
  }

  $sql .= "DEVICE = '$idevs' "                 if($idanz == 1 && $idevs && $idevs !~ m(^%$));
  $sql .= "DEVICE IN ($idevs) "                if($idanz > 1);
  $sql .= ") AND "                             if(($idanz || $idevswc) && $idevs !~ m(^%$));

  # excluded devices
  ###################
  if($edevswc) {
      @dwc = split ",", $edevswc;

      for (@dwc) {
          $sql .= "DEVICE NOT LIKE '$_' AND ";
      }
  }

  $sql .= "DEVICE != '$edevs' "                if($edanz == 1 && $edanz && $edevs !~ m(^%$));
  $sql .= "DEVICE NOT IN ($edevs) "            if($edanz > 1);
  $sql .= "AND "                               if($edanz && $edevs !~ m(^%$));

  # included readings
  ####################
  $sql .= "( "                                 if(($iranz || $irdswc) && $ireading !~ m(^%$));
  if($irdswc && $ireading !~ m(^%$)) {
      @rwc    = split ",", $irdswc;
      my $i   = 1;
      my $len = scalar(@rwc);

      for (@rwc) {
          if($i < $len) {
              $sql .= "READING LIKE '$_' OR ";
          }
          else {
              $sql .= "READING LIKE '$_' ";
          }
          $i++;
      }

      if($iranz) {
          $sql .= "OR ";
      }
  }

  $sql .= "READING = '$ireading' "             if($iranz == 1 && $ireading && $ireading !~ m(\%));
  $sql .= "READING IN ($ireading) "            if($iranz > 1);
  $sql .= ") AND "                             if(($iranz || $irdswc) && $ireading !~ m(^%$));

  # excluded readings
  ####################
  if($erdswc) {
      @dwc = split ",", $erdswc;

      for (@dwc) {
          $sql .= "READING NOT LIKE '$_' AND ";
      }
  }

  $sql .= "READING != '$ereading' "            if($eranz && $eranz == 1 && $ereading !~ m(\%));
  $sql .= "READING NOT IN ($ereading) "        if($eranz > 1);
  $sql .= "AND "                               if($eranz && $ereading !~ m(^%$));

  # add valueFilter
  ##################
  $sql .= $vf if(defined $vf);

  # Timestamp Filter
  ###################
  if (($rsf && $rsn)) {
      # $sql .= "TIMESTAMP >= '$rsf' AND TIMESTAMP ".($tnfull ? "<=" : "<")." '$rsn' ";
      # $sql .= "TIMESTAMP >= ".($rsf eq '?' ? $rsf : qq{'}.$rsf.qq{'})." AND TIMESTAMP ".($tnfull ? "<=" : "<")." ".($rsn eq '?' ? $rsn : qq{'}.$rsn.qq{'})." ";
      $sql .= _DbRep_timeSelspec ($rsf, $rsn, $tnfull);
  }
  else {
      if ($dbmodel eq "POSTGRESQL") {
          $sql .= "true ";
      }
      else {
          $sql .= "1 ";
      }
  }

  $sql .= "$addon;";

return $sql;
}

####################################################################################################
#               SQL-Statement zusammenstellen für DB-Abfrage Select
####################################################################################################
sub DbRep_createSelectSql {
  my ($hash,$table,$selspec,$device,$reading,$rsf,$rsn,$addon) = @_;
  my $name      = $hash->{NAME};
  my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel   = $dbloghash->{MODEL};
  my $valfilter = AttrVal($name, "valueFilter", undef);                         # Wertefilter

  my ($sql,$vf,@dwc,@rwc);

  my ($idevs,$idevswc,$idanz,$ireading,$iranz,$irdswc,$edevs,$edevswc,$edanz,$ereading,$eranz,$erdswc) = DbRep_specsForSql ($hash, $device, $reading);

  my $tnfull = 0;

  if($rsn && $rsn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
      $tnfull = 1;
  }

  if(defined $valfilter) {
      if ($dbmodel eq 'POSTGRESQL') {
          $vf = "VALUE ~ '$valfilter' AND ";
      }
      else {
          $vf = "VALUE REGEXP '$valfilter' AND ";
      }
  }

  if ($dbmodel eq 'POSTGRESQL') {                                              # eingefügt mit V 8.52.10
      if ($rsn  =~ /\d{4}-\d{2}-\d{2}\s\d{2}$/xs) {
          $rsn .= ':00:00';
      }

      if ($rsf  =~ /\d{4}-\d{2}-\d{2}\s\d{2}$/xs) {
          $rsf .= ':00:00';
      }
  }

  $sql = "SELECT $selspec FROM $table where ";

  # included devices
  ###################
  $sql .= "( "                                 if(($idanz || $idevswc) && $idevs !~ m(^%$));
  if($idevswc && $idevs !~ m(^%$)) {
      @dwc    = split ",", $idevswc;
      my $i   = 1;
      my $len = scalar(@dwc);

      for (@dwc) {
          if($i<$len) {
              $sql .= "DEVICE LIKE '$_' OR ";
          } else {
              $sql .= "DEVICE LIKE '$_' ";
          }
          $i++;
      }

      if($idanz) {
          $sql .= "OR ";
      }
  }

  $sql .= "DEVICE = '$idevs' "                 if($idanz == 1 && $idevs && $idevs !~ m(^%$));
  $sql .= "DEVICE IN ($idevs) "                if($idanz > 1);
  $sql .= ") AND "                             if(($idanz || $idevswc) && $idevs !~ m(^%$));

  # excluded devices
  ###################
  if($edevswc) {
      @dwc = split ",", $edevswc;

      for (@dwc) {
          $sql .= "DEVICE NOT LIKE '$_' AND ";
      }
  }

  $sql .= "DEVICE != '$edevs' "                if($edanz == 1 && $edanz && $edevs !~ m(^%$));
  $sql .= "DEVICE NOT IN ($edevs) "            if($edanz > 1);
  $sql .= "AND "                               if($edanz && $edevs !~ m(^%$));

  # included readings
  ####################
  $sql .= "( "                                 if(($iranz || $irdswc) && $ireading !~ m(^%$));
  if($irdswc && $ireading !~ m(^%$)) {
      @rwc    = split ",", $irdswc;
      my $i   = 1;
      my $len = scalar(@rwc);

      for (@rwc) {
          if ($i<$len) {
              $sql .= "READING LIKE '$_' OR ";
          }
          else {
              $sql .= "READING LIKE '$_' ";
          }

          $i++;
      }

      if ($iranz) {
          $sql .= "OR ";
      }
  }

  $sql .= "READING = '$ireading' "             if($iranz == 1 && $ireading && $ireading !~ m(\%));
  $sql .= "READING IN ($ireading) "            if($iranz > 1);
  $sql .= ") AND "                             if(($iranz || $irdswc) && $ireading !~ m(^%$));

  # excluded readings
  ####################
  if($erdswc) {
      @dwc = split ",", $erdswc;

      for (@dwc) {
          $sql .= "READING NOT LIKE '$_' AND ";
      }
  }

  $sql .= "READING != '$ereading' "            if($eranz && $eranz == 1 && $ereading !~ m(\%));
  $sql .= "READING NOT IN ($ereading) "        if($eranz > 1);
  $sql .= "AND "                               if($eranz && $ereading !~ m(^%$));

  # add valueFilter
  ##################
  $sql .= $vf if(defined $vf);

  # Timestamp Filter
  ###################
  if (($rsf && $rsn)) {
      # $sql .= "TIMESTAMP >= ".($rsf eq '?' ? $rsf : qq{'}.$rsf.qq{'})." AND TIMESTAMP ".($tnfull ? "<=" : "<")." ".($rsn eq '?' ? $rsn : qq{'}.$rsn.qq{'})." ";
      $sql .= _DbRep_timeSelspec ($rsf, $rsn, $tnfull);
  }
  else {
      if ($dbmodel eq "POSTGRESQL") {
          $sql .= "true ";
      }
      else {
          $sql .= "1 ";
      }
  }

  $sql .= "$addon;";

return $sql;
}

####################################################################################################
#  SQL-Statement zusammenstellen für Löschvorgänge
####################################################################################################
sub DbRep_createDeleteSql {
 my ($hash,$table,$device,$reading,$rsf,$rsn,$addon) = @_;
 my $name      = $hash->{NAME};
 my $dbloghash = $defs{$hash->{HELPER}{DBLOGDEVICE}};
 my $dbmodel   = $dbloghash->{MODEL};
 my $valfilter = AttrVal($name, "valueFilter", undef);        # Wertefilter
 my $tnfull    = 0;

 my ($sql,$vf,@dwc,@rwc);

 if($table eq "current") {
     $sql = "delete FROM $table; ";
     return $sql;
 }

 my ($idevs,$idevswc,$idanz,$ireading,$iranz,$irdswc,$edevs,$edevswc,$edanz,$ereading,$eranz,$erdswc) = DbRep_specsForSql($hash,$device,$reading);

 if($rsn && $rsn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
     $tnfull = 1;
 }

 if(defined $valfilter) {
     if ($dbmodel eq "POSTGRESQL") {
         $vf = "VALUE ~ '$valfilter' AND ";
     }
     else {
         $vf = "VALUE REGEXP '$valfilter' AND ";
     }
 }

  if ($dbmodel eq 'POSTGRESQL') {                                              # eingefügt mit V 8.52.10
      if ($rsn  =~ /\d{4}-\d{2}-\d{2}\s\d{2}$/xs) {
          $rsn .= ':00:00';
      }

      if ($rsf  =~ /\d{4}-\d{2}-\d{2}\s\d{2}$/xs) {
          $rsf .= ':00:00';
      }
  }

 $sql = "delete FROM $table where ";

 # included devices
 ###################
 $sql .= "( "                                 if(($idanz || $idevswc) && $idevs !~ m(^%$));
 if($idevswc && $idevs !~ m(^%$)) {
     @dwc    = split ",", $idevswc;
     my $i   = 1;
     my $len = scalar(@dwc);

     for (@dwc) {
         if($i<$len) {
             $sql .= "DEVICE LIKE '$_' OR ";
         }
         else {
             $sql .= "DEVICE LIKE '$_' ";
         }
         $i++;
     }

     if($idanz) {
         $sql .= "OR ";
     }
 }
 $sql .= "DEVICE = '$idevs' "                 if($idanz == 1 && $idevs && $idevs !~ m(^%$));
 $sql .= "DEVICE IN ($idevs) "                if($idanz > 1);
 $sql .= ") AND "                             if(($idanz || $idevswc) && $idevs !~ m(^%$));

 # excluded devices
 ###################
 if($edevswc) {
     @dwc = split ",", $edevswc;

     for (@dwc) {
         $sql .= "DEVICE NOT LIKE '$_' AND ";
     }
 }
 $sql .= "DEVICE != '$edevs' "                if($edanz == 1 && $edanz && $edevs !~ m(^%$));
 $sql .= "DEVICE NOT IN ($edevs) "            if($edanz > 1);
 $sql .= "AND "                               if($edanz && $edevs !~ m(^%$));

 # included readings
 ####################
 $sql .= "( "                                 if(($iranz || $irdswc) && $ireading !~ m(^%$));
 if($irdswc && $ireading !~ m(^%$)) {
     @rwc    = split(",",$irdswc);
     my $i   = 1;
     my $len = scalar(@rwc);

     for (@rwc) {
         if ($i<$len) {
             $sql .= "READING LIKE '$_' OR ";
         }
         else {
             $sql .= "READING LIKE '$_' ";
         }

         $i++;
     }

     if($iranz) {
         $sql .= "OR ";
     }
 }
 $sql .= "READING = '$ireading' "             if($iranz == 1 && $ireading && $ireading !~ m(\%));
 $sql .= "READING IN ($ireading) "            if($iranz > 1);
 $sql .= ") AND "                             if(($iranz || $irdswc) && $ireading !~ m(^%$));

 # excluded readings
 ####################
 if($erdswc) {
     @dwc = split(",",$erdswc);

     for (@dwc) {
         $sql .= "READING NOT LIKE '$_' AND ";
     }
 }
 $sql .= "READING != '$ereading' "            if($eranz && $eranz == 1 && $ereading !~ m(\%));
 $sql .= "READING NOT IN ($ereading) "        if($eranz > 1);
 $sql .= "AND "                               if($eranz && $ereading !~ m(^%$));

 # add valueFilter
 ##################
 $sql .= $vf if(defined $vf);

 # Timestamp Filter
 ###################
 if ($rsf && $rsn) {
     #$sql .= "TIMESTAMP >= '$rsf' AND TIMESTAMP ".($tnfull ? "<=" : "<")." '$rsn' $addon;";
     #$sql .= "TIMESTAMP >= ".($rsf eq '?' ? $rsf : qq{'}.$rsf.qq{'})." AND TIMESTAMP ".($tnfull ? "<=" : "<")." ".($rsn eq '?' ? $rsn : qq{'}.$rsn.qq{'})." $addon;";
     $sql .= _DbRep_timeSelspec ($rsf, $rsn, $tnfull);
     $sql .= "$addon;";
 }
 else {
     if ($dbmodel eq "POSTGRESQL") {
         $sql .= "true;";
     }
     else {
          $sql .= "1;";
     }
 }

return $sql;
}

###################################################################################
#      erzeugt die Zeitabgrenzung für SQL-Statements
#      ? im Statement ist bei Verwendung von Platzhaltern relevant
###################################################################################
sub _DbRep_timeSelspec {
  my $rsf    = shift;
  my $rsn    = shift;
  my $tnfull = shift;

  my $tlspec = "TIMESTAMP >= ".($rsf eq '?' ? $rsf : qq{'}.$rsf.qq{'})." AND TIMESTAMP ".($tnfull ? "<=" : "<")." ".($rsn eq '?' ? $rsn : qq{'}.$rsn.qq{'})." ";

return $tlspec;
}

####################################################################################################
#               Ableiten von Device, Reading-Spezifikationen
####################################################################################################
sub DbRep_specsForSql {
 my $hash    = shift;
 my $device  = shift // q{};
 my $reading = shift // q{};

 my $name    = $hash->{NAME};

 my (@idvspcs,@edvspcs,@idvs,@edvs,@idvswc,@edvswc,@residevs,@residevswc);
 my ($nl,$nlwc) = ("","");

 ##### inkludierte / excludierte Devices und deren Anzahl ermitteln #####
 my ($idevice,$edevice)               = ('','');
 my ($idevs,$idevswc,$edevs,$edevswc) = ('','','','');
 my ($idanz,$edanz)                   = (0,0);

 if($device =~ /EXCLUDE=/i) {
     ($idevice,$edevice) = split(/EXCLUDE=/i,$device);
     $idevice            = $idevice ? DbRep_trim($idevice) : "%";
 }
 else {
     $idevice = $device;
 }

 # Devices exkludiert
 if($edevice) {
     @edvs             = split ",", $edevice;
     ($edevs,$edevswc) = DbRep_resolveDevspecs($name,$edevice,\@edvs);
 }

 $edanz = split ",", $edevs;                                         # Anzahl der exkludierten Elemente (Lauf1)

 # Devices inkludiert
 @idvs             = split ",", $idevice;
 ($idevs,$idevswc) = DbRep_resolveDevspecs($name,$idevice,\@idvs);
 $idanz            = split ",", $idevs;                              # Anzahl der inkludierten Elemente (Lauf1)

 Log3 ($name, 5, "DbRep $name - Devices for operation - \n"
                ."included ($idanz): $idevs \n"
                ."included with wildcard: $idevswc \n"
                ."excluded ($edanz): $edevs \n"
                ."excluded with wildcard: $edevswc");

 # exkludierte Devices aus inkludierten entfernen (aufgelöste)
 @idvs = split ",", $idevs;
 @edvs = split ",", $edevs;

 for my $in (@idvs) {
     my $inc = 1;

     for my $v (@edvs) {
         next if($in ne $v);
         $inc = 0;
         $nl .= "|" if($nl);
         $nl .= $v;                                                  # Liste der entfernten devices füllen
     }

     push(@residevs, $in) if($inc);
 }

 $edevs = join (",", map {($_ !~ /$nl/) ? $_ : ();} @edvs) if($nl);

 # exkludierte Devices aus inkludierten entfernen (wildcard konnte nicht aufgelöst werden)
 @idvswc = split ",", $idevswc;
 @edvswc = split ",", $edevswc;

 for my $inwc (@idvswc) {
     my $inc = 1;

     for my $w (@edvswc) {
         next if($inwc ne $w);
         $inc   = 0;
         $nlwc .= "|" if($nlwc);
         $nlwc .= $w;                                                # Liste der entfernten devices füllen
     }

     push @residevswc, $inwc if($inc);
 }
 $edevswc = join (",", map {($_ !~ /$nlwc/) ? $_ : ();} @edvswc) if($nlwc);

 # Ergebnis zusammenfassen
 $idevs   = join ",", @residevs;
 $idevs   =~ s/'/''/g;                                               # escape ' with ''
 $idevswc = join ",", @residevswc;
 $idevswc =~ s/'/''/g;                                               # escape ' with ''

 $idanz = split ",", $idevs;                                         # Anzahl der inkludierten Elemente (Lauf2)

 if($idanz > 1) {
     $idevs =~ s/,/','/g;
     $idevs = "'".$idevs."'";
 }

 $edanz = split ",", $edevs;                                         # Anzahl der exkludierten Elemente (Lauf2)

 if($edanz > 1) {
     $edevs =~ s/,/','/g;
     $edevs = "'".$edevs."'";
 }

 ##### inkludierte / excludierte Readings und deren Anzahl ermitteln #####
 my ($ireading,$ereading)           = ('','');
 my ($iranz,$eranz)                 = (0,0);
 my ($erdswc,$erdgs,$irdswc,$irdgs) = ('','','','');
 my (@erds,@irds);

 $reading =~ s/'/''/g;                                               # escape ' with ''

 if($reading =~ /EXCLUDE=/i) {
     ($ireading,$ereading) = split(/EXCLUDE=/i,$reading);
     $ireading = $ireading ? DbRep_trim ($ireading) : "%";
 }
 else {
     $ireading = $reading;
 }

 if($ereading) {
     @erds = split ",", $ereading;

     for my $e (@erds) {
         if($e =~ /%/ && $e !~ /^%$/) {                              # Readings mit Wildcard (%) erfassen
             $erdswc .= "," if($erdswc);
             $erdswc .= $e;
         }
         else {
             $erdgs .= "," if($erdgs);
             $erdgs .= $e;
         }
     }
 }

 @irds  = split ",", $ireading;                                      # Readings inkludiert

 for my $i (@irds) {
     if($i =~ /%/ && $i !~ /^%$/) {                                  # Readings mit Wildcard (%) erfassen
         $irdswc .= "," if($irdswc);
         $irdswc .= $i;
     }
     else {
         $irdgs .= "," if($irdgs);
         $irdgs .= $i;
     }
 }

 $iranz = split ",", $irdgs;

 if($iranz > 1) {
     $irdgs =~ s/,/','/g;
     $irdgs = "'".$irdgs."'";
 }

 if($ereading) {                                                     # Readings exkludiert
     $eranz = split ",", $erdgs;
     if($eranz > 1) {
         $erdgs =~ s/,/','/g;
         $erdgs = "'".$erdgs."'";
     }
 }

 Log3 $name, 5, "DbRep $name - Readings for operation - \n"
                ."included ($iranz): $irdgs \n"
                ."included with wildcard: $irdswc \n"
                ."excluded ($eranz): $erdgs \n"
                ."excluded with wildcard: $erdswc";

return ($idevs,$idevswc,$idanz,$irdgs,$iranz,$irdswc,$edevs,$edevswc,$edanz,$erdgs,$eranz,$erdswc);
}

####################################################################################################
#               devspecs für SQL auflösen
####################################################################################################
sub DbRep_resolveDevspecs {
  my $name   = shift;
  my $dlist  = shift;                                                # Komma getrennte Deviceliste
  my $devref = shift;                                                # Referenz der Deviceliste

  my ($devs,$devswc) = ('','');

  for my $d (@$devref) {
      $d          =~ s/%/\.*/g if($d !~ /^%$/);                      # SQL Wildcard % auflösen
      my @devspcs = devspec2array($d);
      @devspcs    = qw(^^) if(!@devspcs);                            # ein nie existierendes Device (^^) setzen wenn Liste leer
      @devspcs    = map {s/\.\*/%/g; $_; } @devspcs;

      if((map {$_ =~ /%/;} @devspcs) && $dlist !~ /^%$/) {           # Devices mit Wildcard (%) erfassen, die nicht aufgelöst werden konnten
          $devswc .= "," if($devswc);
          $devswc .= join(",",@devspcs);
      }
      else {
          $devs .= "," if($devs);
          $devs .= join(",",@devspcs);
      }
  }

return ($devs,$devswc);
}

######################################################################################
#            Erstelle Insert SQL-Schema für Tabelle mit/ohne primary key
######################################################################################
sub DbRep_createInsertSQLscheme {
  my $table   = shift;
  my $dbmodel = shift;
  my $usepkh  = shift;

  my $sql;

  if ($usepkh && $dbmodel eq 'MYSQL') {
      $sql = "INSERT IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbmodel eq 'SQLITE') {
      $sql = "INSERT OR IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }
  elsif ($usepkh && $dbmodel eq 'POSTGRESQL') {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING";
  }
  else {
      $sql = "INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
  }

return $sql;
}

######################################################################################
#            Erstelle Update SQL-Schema für Tabelle
######################################################################################
sub DbRep_createUpdateSQLscheme {
  my $table = shift;

  my $sql = "UPDATE $table SET TIMESTAMP=?, DEVICE=?, READING=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE TIMESTAMP=? AND DEVICE=? AND READING=?";

return $sql;
}

######################################################################################
#    Connect zur Datenbank herstellen
#
#    $uac:  undef - Verwendung adminCredentials abhängig von Attr useAdminCredentials
#              0  - adminCredentials werden nicht verwendet
#              1  - adminCredentials werden immer verwendet
######################################################################################
sub DbRep_dbConnect {
  my $name       = shift;
  my $uac        = shift // AttrVal($name, "useAdminCredentials", 0);

  my $hash       = $defs{$name};
  my $dbloghash  = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};
  my $dblogname  = $dbloghash->{NAME};
  my $dbmodel    = $dbloghash->{MODEL};
  my $dbpassword = $attr{"sec$dblogname"}{secret};
  my $utf8       = $hash->{UTF8} // 0;

  my $dbh;
  my $err = q{};

  if($uac) {
      my ($success,$admusername,$admpassword) = DbRep_getcredentials ($hash, "adminCredentials");

      if ($success) {
          $dbuser     = $admusername;
          $dbpassword = $admpassword;
      }
      else {
          $err = "Can't use admin credentials for database access, see logfile !";
          Log3 ($name, 2, "DbRep $name - ERROR - admin credentials are needed for database operation, but are not set or can't read it");
          return encode_base64($err,"");
      }
  }

  Log3 ($name, 4, "DbRep $name - Database connect - user: ".($dbuser ? $dbuser : 'no').", UTF-8 option set: ".($utf8 ? 'yes' : 'no'));

  eval { $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0,
                                                                    RaiseError          => 1,
                                                                    AutoCommit          => 1,
                                                                    AutoInactiveDestroy => 1
                                                                  }
                            ); 1;
       }
       or do { $err = encode_base64($@,"");
               Log3 ($name, 2, "DbRep $name - ERROR: $@");
               return $err;
             };

  if ($utf8) {
      if ($dbmodel eq "MYSQL") {
          $dbh->{mysql_enable_utf8} = 1;

          ($err, my @se) = DbRep_prepareExec2Array ($name, $dbh, "SHOW VARIABLES LIKE 'collation_database'");
          return $err if ($err);

          my $dbcharset = @se ? $se[1] : 'noresult';

          Log3 ($name, 4, "DbRep $name - Database Character set is >$dbcharset<");

          if ($dbcharset !~ /noresult|ucs2|utf16|utf32/ixs) {                                                                 # Impermissible Client Character Sets -> https://dev.mysql.com/doc/refman/8.0/en/charset-connection.html
              my $collation = $dbcharset;
              $dbcharset    = (split '_', $collation, 2)[0];

              ($err, undef) = DbRep_dbhDo ($name, $dbh, qq(set names "$dbcharset" collate "$collation"));
              return $err if ($err);
          }
      }

      if ($dbmodel eq "SQLITE") {
        $dbh->do('PRAGMA encoding="UTF-8"');
      }
  }

return ($err, $dbh, $dbmodel);
}

####################################################################################################
#          nur SQL prepare
#          return $sth bei Erfolg
####################################################################################################
sub DbRep_prepareOnly {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "SQL prepare: $sql";

  my $err  = q{};

  my $sth;

  Log3 ($name, 4, "DbRep $name - $info");

  eval{ $sth = $dbh->prepare($sql);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return ($err, $sth);
}

####################################################################################################
#          nur SQL prepare Cached
#          return $sth bei Erfolg
####################################################################################################
sub DbRep_prepareCachedOnly {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "SQL prepare cached: $sql";

  my $err  = q{};

  my $sth;

  Log3 ($name, 4, "DbRep $name - $info");

  eval{ $sth = $dbh->prepare_cached($sql);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return ($err, $sth);
}

####################################################################################################
#          SQL Query evaluieren und Return Error-String oder $sth-String
#          bei Erfolg
####################################################################################################
sub DbRep_prepareExecuteQuery {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "SQL execute: $sql";

  my $err  = q{};

  my ($sth,$res);

  Log3 ($name, 4, "DbRep $name - $info");

  eval{ $sth = $dbh->prepare($sql);
        $res = $sth->execute();
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $sth->finish if($sth);
              $dbh->disconnect;
            };

return ($err, $sth, $res);
}

####################################################################################################
#          SQL Query evaluieren und Return Error-String oder Ergebnis Array
#          bei Erfolg
####################################################################################################
sub DbRep_prepareExec2Array {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "SQL execute: $sql";

  my $err  = q{};
  my @sr   = ();

  my ($sth,$res);

  Log3 ($name, 4, "DbRep $name - $info");

  eval{ $sth = $dbh->prepare($sql);
        $res = $sth->execute();
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $sth->finish if($sth);
              $dbh->disconnect;
            };

  @sr = $sth->fetchrow_array;

return ($err, @sr);
}

####################################################################################################
#  einfaches Sdbh->do, return ERROR-String wenn Fehler bzw. die Anzahl der betroffenen Zeilen
####################################################################################################
sub DbRep_dbhDo {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "simple do statement: $sql";

  my $err  = q{};
  my $rv   = q{};

  Log3 ($name, 4, "DbRep $name - $info");

  eval{ $rv = $dbh->do($sql);
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return ($err, $rv);
}

####################################################################################################
#    führt ein sth execute prepared Insert aus
#    return ERROR oder die Anzahl der betroffenen Zeilen
####################################################################################################
sub DbRep_execInsertPrepared {
  my $paref = shift;

  my $name      = $paref->{name};
  my $sth       = $paref->{sth};
  my $timestamp = $paref->{timestamp};
  my $device    = $paref->{device};
  my $type      = $paref->{type};
  my $event     = $paref->{event};
  my $reading   = $paref->{reading};
  my $value     = $paref->{value};
  my $unit      = $paref->{unit};
  my $err       = q{};
  my $rv        = q{};

  eval{ $rv = $sth->execute($timestamp, $device, $type, $event, $reading, $value, $unit);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
            };

  $rv = 0 if($rv eq "0E0");

return ($err, $rv);
}

####################################################################################################
#    führt ein sth execute prepared Update aus
#    return ERROR oder die Anzahl der betroffenen Zeilen
####################################################################################################
sub DbRep_execUpdatePrepared {
  my $paref = shift;

  my $name      = $paref->{name};
  my $sth       = $paref->{sth};
  my $timestamp = $paref->{timestamp};
  my $device    = $paref->{device};
  my $type      = $paref->{type};
  my $event     = $paref->{event};
  my $reading   = $paref->{reading};
  my $value     = $paref->{value};
  my $unit      = $paref->{unit};
  my $err       = q{};
  my $rv        = q{};

  eval{ $rv = $sth->execute($timestamp, $device, $reading, $type, $event, $value, $unit, $timestamp, $device, $reading);
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
            };

  $rv = 0 if($rv eq "0E0");

return ($err, $rv);
}

####################################################################################################
#       nur Datenbank "begin transaction"
#       $dbh->{AutoCommit} = 0;  # enable transactions, if possible
#           oder
#       $dbh->begin_work();
####################################################################################################
sub DbRep_beginDatabaseTransaction {
  my $name = shift;
  my $dbh  = shift;
  my $info = shift // "begin transaction";

  my $err  = q{};

  eval{ if($dbh->{AutoCommit}) {
            $dbh->begin_work();
            Log3 ($name, 4, "DbRep $name - $info");
        }
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return $err;
}

####################################################################################################
#          nur Datenbank "commit"
####################################################################################################
sub DbRep_commitOnly {
  my $name = shift;
  my $dbh  = shift;
  my $info = shift // "transaction committed";

  my $err  = q{};

  eval{ if(!$dbh->{AutoCommit}) {
            $dbh->commit();
            Log3 ($name, 4, "DbRep $name - $info");
        }
        else {
            Log3 ($name, 4, "DbRep $name - data autocommitted");
        }
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return $err;
}

####################################################################################################
#          nur Datenbank "rollback"
####################################################################################################
sub DbRep_rollbackOnly {
  my $name = shift;
  my $dbh  = shift;
  my $info = shift // "transaction rollback";

  my $err  = q{};

  eval{ if(!$dbh->{AutoCommit}) {
            $dbh->rollback();
            Log3 ($name, 4, "DbRep $name - $info");
        }
        else {
            Log3 ($name, 4, "DbRep $name - data auto rollback");
        }
        1;
      }
      or do { $err = encode_base64($@,"");
              Log3 ($name, 2, "DbRep $name - ERROR - $@");
              $dbh->disconnect;
            };

return $err;
}

####################################################################################################
#             Whitespace am Anfang / Ende eines Strings entfernen
####################################################################################################
sub DbRep_trim {
  my $str = shift;

  return if(!$str);
  $str =~ s/^\s+|\s+$//g;

return $str;
}

####################################################################################################
#                  Sekunden in Format hh:mm:ss umwandeln
####################################################################################################
sub DbRep_sec2hms {
 my $s = shift;
 my $hms;

 my $hh = sprintf("%02d", int($s/3600));
 my $mm = sprintf("%02d", int(($s-($hh*3600))/60));
 my $ss = sprintf("%02d", $s-($mm*60)-($hh*3600));

return ("$hh:$mm:$ss");
}

####################################################################################################
#    Check ob Zeitgrenzen bzw. Aggregation gesetzt sind, evtl. übersteuern (je nach Funktion)
#    Return "1" wenn Bedingung erfüllt, sonst "0"
####################################################################################################
sub DbRep_checktimeaggr {
  my $hash        = shift // return;
  my $name        = $hash->{NAME};
  my $IsTimeSet   = 0;
  my $IsAggrSet   = 0;
  my $aggregation = AttrVal($name,"aggregation","no");

  my @a;
  @a = @{$hash->{HELPER}{REDUCELOG}}  if($hash->{HELPER}{REDUCELOG});
  @a = @{$hash->{HELPER}{DELENTRIES}} if($hash->{HELPER}{DELENTRIES});

  my $timeoption = 0;

  for my $elem (@a) {                                                     # evtl. Relativzeiten bei "reduceLog" oder "deleteEntries" berücksichtigen
      $timeoption = 1 if($elem =~ /\b\d+(:\d+)?\b/);
  }

  if (AttrVal ($name,"timestamp_begin", undef) ||
      AttrVal ($name,"timestamp_end",   undef) ||
      AttrVal ($name,"timeDiffToNow",   undef) ||
      AttrVal ($name,"timeOlderThan",   undef) ||
      AttrVal ($name,"timeYearPeriod",  undef) || $timeoption ) {
      $IsTimeSet = 1;
  }

  if ($aggregation ne "no") {
      $IsAggrSet = 1;
  }

  if($hash->{LASTCMD} =~ /delSeqDoublets|delDoublets/) {
      $aggregation = ($aggregation eq "no") ? "day" : $aggregation;       # wenn Aggregation "no", für delSeqDoublets immer "day" setzen
      $IsAggrSet   = 1;
  }

  if($hash->{LASTCMD} =~ /averageValue/ && AttrVal($name, "averageCalcForm", "avgArithmeticMean") =~ /avgDailyMeanGWS/x) {
      $aggregation = "day";                                               # für Tagesmittelwertberechnung des deutschen Wetterdienstes immer "day"
      $IsAggrSet   = 1;
  }

  if($hash->{LASTCMD} =~ /^sql|delEntries|fetchrows|deviceRename|readingRename|tableCurrentFillup|reduceLog|\breadingsDifferenceByTimeDelta\b/) {
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
      }
      else {
          $IsAggrSet   = 0;
          $aggregation = "no";
      }
  }

  if($hash->{LASTCMD} =~ /syncStandby/ ) {
      if($aggregation !~ /minute|hour|day|week/) {
          $aggregation = "day";
          $IsAggrSet   = 1;
      }
  }

return ($IsTimeSet,$IsAggrSet,$aggregation);
}

####################################################################################################
#    ReadingsSingleUpdate für Reading, Value, Event
####################################################################################################
sub ReadingsSingleUpdateValue {
 my $hash    = shift;
 my $reading = shift;
 my $val     = shift;
 my $ev      = shift;
 my $name    = $hash->{NAME};

 readingsSingleUpdate($hash, $reading, $val, $ev);

 readingsBeginUpdate ($hash);
 DbRep_userexit      ($name, $reading, $val);
 readingsEndUpdate   ($hash, 1);

 DbRep_autoForward   ($name, $reading, $val);

return;
}

####################################################################################################
#    ReadingsSingleUpdate für Time-Readings
####################################################################################################
sub ReadingsSingleUpdateTime {
 my $hash = shift;
 my $bpt  = shift;
 my $spt  = shift;
 my $evt  = shift;

 my $name = $hash->{NAME};

 if (AttrVal($name, "showproctime", 0)) {
     if (defined $bpt) {
         $bpt = sprintf "%.4f", $bpt;

         readingsSingleUpdate ($hash, "background_processing_time", $bpt, $evt);

         readingsBeginUpdate  ($hash);
         DbRep_userexit       ($name, "background_processing_time", $bpt);
         readingsEndUpdate    ($hash, 1);
     }

     if (defined $spt) {
        $spt = sprintf "%.4f", $spt;

        readingsSingleUpdate ($hash, "sql_processing_time", $spt, $evt);

        readingsBeginUpdate  ($hash);
        DbRep_userexit       ($name, "sql_processing_time", $spt);
        readingsEndUpdate    ($hash, 1);
     }
 }

return;
}

####################################################################################################
#    Readingsbulkupdate für Reading, Value
#    readingsBeginUpdate und readingsEndUpdate muss vor/nach Funktionsaufruf gesetzt werden
####################################################################################################
sub ReadingsBulkUpdateValue {
 my $hash    = shift;
 my $reading = shift;
 my $val     = shift;
 my $name    = $hash->{NAME};

 readingsBulkUpdate($hash, $reading, $val);
 DbRep_userexit    ($name, $reading, $val);
 DbRep_autoForward ($name, $reading, $val);

return;
}

####################################################################################################
#    Readingsbulkupdate für processing_time, state
#    readingsBeginUpdate und readingsEndUpdate muss vor/nach Funktionsaufruf gesetzt werden
####################################################################################################
sub ReadingsBulkUpdateTimeState {
 my $hash = shift;
 my $brt  = shift;
 my $rt   = shift;
 my $sval = shift;

 my $name = $hash->{NAME};

 if(AttrVal($name, 'showproctime', 0)) {
     if (defined $brt) {
         $brt = sprintf "%.4f", $brt;
         readingsBulkUpdate ($hash, "background_processing_time", $brt);
         DbRep_userexit     ($name, "background_processing_time", $brt);
     }

     if (defined $rt) {
         $rt = sprintf "%.4f", $rt;
         readingsBulkUpdate ($hash, "sql_processing_time", $rt);
         DbRep_userexit     ($name, "sql_processing_time", $rt);
     }
 }

 readingsBulkUpdate ($hash, "state", $sval);
 DbRep_userexit     ($name, "state", $sval);
 DbRep_autoForward  ($name, "state", $sval);

return;
}

####################################################################################################
#    Readingsbulkupdate für processing_time,
#    readingsBeginUpdate und readingsEndUpdate muss vor/nach Funktionsaufruf gesetzt werden
####################################################################################################
sub ReadingsBulkUpdateTime {
 my $hash = shift;
 my $bpt  = shift;
 my $spt  = shift;

 my $name = $hash->{NAME};

 if(AttrVal($name, 'showproctime', 0)) {
     if (defined $bpt) {
         $bpt = sprintf "%.4f", $bpt;
         readingsBulkUpdate ($hash, "background_processing_time", $bpt);
         DbRep_userexit     ($name, "background_processing_time", $bpt);
     }

     if (defined $spt) {
         $spt = sprintf "%.4f", $spt;
         readingsBulkUpdate ($hash, "sql_processing_time", $spt);
         DbRep_userexit     ($name, "sql_processing_time", $spt);
     }
 }

return;
}

####################################################################################################
#               Übertragen von Readings und Ergebniswerten in ein anderes Device
#
#   autoForward Attribut:
#
#   {
#     "<source-reading>" => "<dest.device>" [=> <dest.-reading>]",
#     "<source-reading>" => "<dest.device>" [=> <dest.-reading>]",
#     ....
#   }
####################################################################################################
sub DbRep_autoForward {
  my $name    = shift;
  my $reading = shift;
  my $value   = shift;
  
  my $hash = $defs{$name};
  my $av   = AttrVal ($name, 'autoForward', '');
  
  return if(!$av);

  $av =~ m/^\{(.*)\}/s;
  $av = $1;
  $av =~ s/["\n]//g;

  my @a = split ",", $av;
  $av   = "{ ";
  
  my $i = 0;
  for my $elm (@a) {
      $av .= qq("$i" => "$elm",);
      $i++;
  }

  $av .= " }";

  my ($sr,$af);
  
  $af = eval $av;
  
  if($@ || ref($af) ne "HASH") {
      Log3($name, 2, "$name - Values specified in attribute \"autoForward\" are not defined as HASH ... exiting !") if(ref($af) ne "HASH");
      Log3($name, 2, "$name - Error while evaluate: ".$@) if($@);
      return;
  }

  for my $key (keys %{$af}) {
      my ($srr, $ddev, $dr) = split("=>", $af->{$key});
      $ddev                 = DbRep_trim ($ddev) if($ddev);
      next if(!$ddev);
      
      $srr  = DbRep_trim ($srr) if($srr);
      $dr   = DbRep_trim ($dr)  if($dr);

      if(!$defs{$ddev}) {                                                          # Vorhandensein Destination Device prüfen
          Log3($name, 2, "$name - WARNING - Forward reading \"$reading\" not possible, device \"$ddev\" doesn't exist");
          next;
      }

      if(!$srr || $reading !~ /^$srr$/) {
          # Log3 ($name, 4, "$name - Reading \"$reading\" doesn't match autoForward-Regex: ".($srr?$srr:"")." - no forward to \"$ddev\" ");
          next;
      }

      eval { $sr = $srr };
      $dr = $dr ? $dr : ($sr !~ /\.\*/xs) ? $sr : $reading;                        # Destination Reading = Source Reading wenn Destination Reading nicht angegeben
      $dr = makeReadingName ($dr);                                                 # Destination Readingname validieren / entfernt aus dem übergebenen Readingname alle ungültigen Zeichen und ersetzt diese durch einen Unterstrich "_"
      
      Log3($name, 4, "$name - Forward reading \"$reading\" to \"$ddev:$dr\" ");

      CommandSetReading(undef, "$ddev $dr $value");
  }

return;
}

####################################################################################################
#  Anzeige von laufenden Blocking Prozessen
####################################################################################################
sub DbRep_getblockinginfo {
  my $hash = shift;
  my $name = $hash->{NAME};

  my @rows;
  our %BC_hash;
  my $len = 99;

  for my $h (values %BC_hash) {
      next if($h->{terminated} || !$h->{pid});
      my @allk = keys%{$h};

      for my $k (@allk) {
          Log3 ($name, 5, "DbRep $name -> $k : ".$h->{$k});
      }

      my $fn   = ref($h->{fn})  ? ref($h->{fn})  : $h->{fn};
      my $arg  = ref($h->{arg}) ? ref($h->{arg}) : $h->{arg};
      my $arg1 = substr($arg,0,$len);
      $arg1    = $arg1."..." if(length($arg) > $len+1);
      my $to   = $h->{timeout} ? $h->{timeout} : "N/A";
      my $conn = $h->{telnet}  ? $h->{telnet}  : "N/A";

      push @rows, "$h->{pid}|ESCAPED|$fn|ESCAPED|$arg1|ESCAPED|$to|ESCAPED|$conn";
  }

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

  for my $row (@rows) {
      $row =~ s/\|ESCAPED\|/<\/td><td style='padding-right:5px;padding-left:5px'>/g;
      $res .= "<tr><td style='padding-right:5px;padding-left:5px'>".$row."</td></tr>";
  }
  my $tab = $res."</table></html>";

  ReadingsBulkUpdateValue ($hash,"BlockingInfo",$tab);
  ReadingsBulkUpdateValue ($hash,"Blocking_Count",$#rows+1);

  ReadingsBulkUpdateTimeState($hash,undef,undef,"done");
  readingsEndUpdate          ($hash, 1);

return;
}

####################################################################################################
#    relative Zeitangaben als Sekunden normieren
#
# liefert die Attribute timeOlderThan, timeDiffToNow als Sekunden normiert zurück
####################################################################################################
sub DbRep_normRelTime {
 my $hash  = shift;
 my $name  = $hash->{NAME};
 my $tdtn  = AttrVal($name, "timeDiffToNow", undef);
 my $toth  = AttrVal($name, "timeOlderThan", undef);
 my $fdopt = 0;                                                       # FullDay Option

 my ($y,$d,$h,$m,$s,$aval,@a);

 # evtl. Relativzeiten bei "reduceLog" oder "deleteEntries" berücksichtigen
 @a = @{$hash->{HELPER}{REDUCELOG}}  if($hash->{HELPER}{REDUCELOG});
 @a = @{$hash->{HELPER}{DELENTRIES}} if($hash->{HELPER}{DELENTRIES});

 for my $ey (@a) {
     if($ey =~ /\b(\d+(:\d+)?)\b/) {
         my ($od,$nd) = split ":", $1;                                # $od - Tage älter als , $nd - Tage neuer als,
         $toth        = "d:$od FullDay" if($od);                      # FullDay Option damit der ganze Tag berücksichtigt wird
         $tdtn        = "d:$nd FullDay" if($nd);
     }
 }

 if($tdtn && $tdtn =~ /^\s*[ydhms]:(([\d]+.[\d]+)|[\d]+)\s*/) {
     $aval = $tdtn;
     if($tdtn =~ /.*y:(([\d]+.[\d]+)|[\d]+).*/) {
         $y =  $tdtn;
         $y =~ s/.*y:(([\d]+.[\d]+)|[\d]+).*/$1/e;
     }
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
     Log3($name, 4, "DbRep $name - timeDiffToNow - year: $y, day: $d, hour: $h, min: $m, sec: $s");
     use warnings;
     $y = $y?($y*365*86400):0;
     $d = $d?($d*86400):0;
     $h = $h?($h*3600):0;
     $m = $m?($m*60):0;
     $s = $s?$s:0;

     $tdtn  = $y + $d + $h + $m + $s + 1;                             # one security second for correct create TimeArray
     $tdtn  = DbRep_corrRelTime($name,$tdtn,1);
     $fdopt = ($aval =~ /FullDay/x && $tdtn >= 86400) ? 1 : 0;        # ist FullDay Option gesetzt UND Zeitdiff >= 1 Tag ?
 }

 if($toth && $toth =~ /^\s*[ydhms]:(([\d]+.[\d]+)|[\d]+)\s*/) {
     $aval = $toth;
     if($toth =~ /.*y:(([\d]+.[\d]+)|[\d]+).*/) {
         $y =  $toth;
         $y =~ s/.*y:(([\d]+.[\d]+)|[\d]+).*/$1/e;
     }
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
     Log3($name, 4, "DbRep $name - timeOlderThan - year: $y, day: $d, hour: $h, min: $m, sec: $s");
     use warnings;

     $y = $y ? ($y*365*86400) : 0;
     $d = $d ? ($d*86400)     : 0;
     $h = $h ? ($h*3600)      : 0;
     $m = $m ? ($m*60)        : 0;
     $s = $s ? $s             : 0;

     $toth  = $y + $d + $h + $m + $s + 1;                             # one security second for correct create TimeArray
     $toth  = DbRep_corrRelTime($name,$toth,0);
     $fdopt = ($aval =~ /FullDay/x && $toth >= 86400) ? 1 : 0;        # ist FullDay Option gesetzt UND Zeitdiff >= 1 Tag ?
 }

 $fdopt = 1 if($hash->{LASTCMD} =~ /reduceLog.*=day/x);               # reduceLog -> FullDay Option damit der ganze Tag berücksichtigt wird

 Log3($name, 4, "DbRep $name - FullDay option: $fdopt");

return ($toth,$tdtn,$fdopt);
}

####################################################################################################
#   Korrektur Schaltjahr und Sommer/Winterzeit bei relativen Zeitangaben
####################################################################################################
sub DbRep_corrRelTime {
 my ($name,$tim,$tdtn) = @_;
 my $hash = $defs{$name};

 # year   als Jahre seit 1900
 # $mon   als 0..11
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
 my ($dsec,$dmin,$dhour,$dmday,$dmon,$dyear,$dwday,$dyday,$disdst,$fyear,$cyear);
 (undef,undef,undef,undef,undef,$cyear,undef,undef,$isdst)          = localtime(time);       # aktuelles Jahr, Sommer/Winterzeit

 if($tdtn) {                                                                                 # timeDiffToNow
     ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,undef)           = localtime(time);       # Istzeit
     ($dsec,$dmin,$dhour,$dmday,$dmon,$dyear,$dwday,$dyday,$disdst) = localtime(time-$tim);  # Istzeit abzgl. Differenzzeit = Selektionsbeginnzeit
 }
 else {                                                                                      # timeOlderThan
     ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$disdst)         = localtime(time-$tim);  # Berechnung Selektionsendezeit
     my $mints = $hash->{HELPER}{MINTS}?$hash->{HELPER}{MINTS}:"1970-01-01 01:00:00";        # Selektionsstartzeit
     my ($yyyy1, $mm1, $dd1, $hh1, $min1, $sec1) = ($mints =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
     my $tsend = timelocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900);
     ($dsec,$dmin,$dhour,$dmday,$dmon,$dyear,$dwday,$dyday,undef)   = localtime($tsend);     # Timestamp Selektionsstartzeit
 }

 $year  += 1900;                                                     # aktuelles Jahr
 $dyear += 1900;                                                     # Startjahr der Selektion
 $cyear += 1900;                                                     # aktuelles Jahr

 if($tdtn) {                                                         # timeDiffToNow
     $fyear = $dyear;                                                # Berechnungsjahr -> hier Selektionsbeginn
 }
 else {                                                              # timeOlderThan
     $fyear = $year;                                                 # Berechnungsjahr -> hier Selektionsende
 }

 my $k   = $cyear - $fyear;                                          # Anzahl Jahre
 my $mg  = ((int($mon)+1)+(($k-1)*12)+(11-int($dmon)+1));            # Gesamtzahl der Monate des Bewertungszeitraumes
 my $cly = 0;                                                        # Anzahl Schaltjahre innerhalb Beginn und Ende Auswertungszeitraum
 my $fly = 0;                                                        # erstes Schaltjahr nach Start
 my $lly = 0;                                                        # letzes Schaltjahr nach Start

 while ($fyear+$k >= $fyear) {
     my $ily = DbRep_IsLeapYear($name,$fyear+$k);
     $cly++ if($ily);
     $fly = $fyear+$k if($ily && !$fly);
     $lly = $fyear+$k if($ily);
     $k--;
 }

 if( $mon > 1 && ($lly > $fyear || ($lly = $fyear && $dmon < 1)) ) {
     $tim += $cly*86400;
 }
 else {
     $tim += ($cly-1)*86400 if($cly);
 }

 # Sommer/Winterzeitkorrektur
 (undef,undef,undef,undef,undef,undef,undef,undef,$disdst) = localtime(time-$tim);
 $tim += ($disdst-$isdst)*3600 if($disdst != $isdst);

 Log3($name, 4, "DbRep $name - startMonth: $dmon endMonth: $mon lastleapyear: $lly baseYear: $fyear diffdaylight:$disdst isdaylight:$isdst");

return $tim;
}

####################################################################################################
#  liefert zurück ob übergebenes Jahr ein Schaltjahr ist ($ily = 1)
#
#  Es gilt:
#  - Wenn ein Jahr durch 4 teilbar ist, ist es ein Schaltjahr, aber
#  - wenn es durch 100 teilbar ist, ist es kein schaltjahr, außer
#  - es ist durch 400 teilbar, dann ist es ein schaltjahr
#
####################################################################################################
sub DbRep_IsLeapYear {
  my ($name,$year) = @_;
  my $ily = 0;

  if ($year % 4 == 0 && $year % 100 != 0 || $year % 400 == 0) {    # $year modulo 4 -> muß 0 sein
      $ily = 1;
  }

  Log3($name, 4, "DbRep $name - Year $year is leap year") if($ily);

return $ily;
}

###############################################################################
#              Zeichencodierung für Fileexport filtern
###############################################################################
sub DbRep_charfilter {
  my ($txt) = @_;

  # nur erwünschte Zeichen, Filtern von Steuerzeichen
  $txt =~ s/\xb0/1degree1/g;
  $txt =~ s/\xC2//g;
  $txt =~ tr/ A-Za-z0-9!"#$§%&'()*+,-.\/:;<=>?@[\\]^_`{|}~äöüÄÖÜß€//cd;
  $txt =~ s/1degree1/°/g;

return ($txt);
}

###################################################################################
#                    Befehl vor Procedure ausführen
###################################################################################
sub DbRep_beforeproc {
  my $hash = shift;
  my $cmd  = shift // q{process};

  my $name = $hash->{NAME};
  my $fn   = AttrVal($name, 'executeBeforeProc', '');

  if($fn) {
      Log3 ($name, 3, "DbRep $name - execute command before $cmd: '$fn' ");

      my $err = _DbRep_procCode ($hash, $fn);

      if ($err) {
          Log3 ($name, 2, "DbRep $name - command message before $cmd: \"$err\" ");
          my $erread = "Warning - message from command before $cmd appeared";

          ReadingsSingleUpdateValue ($hash, "before_".$cmd."_message", $err, 1);
          ReadingsSingleUpdateValue ($hash, "state", $erread, 1);
      }
  }

return;
}

###################################################################################
#                    Befehl nach Procedure ausführen
###################################################################################
sub DbRep_afterproc {
  my $hash  = shift;
  my $cmd   = shift // q{process};
  my $bfile = shift // q{};

  my ($err,$erread);

  my $name   = $hash->{NAME};
  $cmd       = (split " ", $cmd)[0];
  my $sval   = ReadingsVal ($name, 'state', '');
  my $fn     = AttrVal     ($name, 'executeAfterProc', '');

  if($fn) {
      Log3 ($name, 3, "DbRep $name - execute command after $cmd: '$fn' ");

      $err = _DbRep_procCode ($hash, $fn);

      if ($err) {
          Log3 ($name, 2, qq{DbRep $name - command message after $cmd: >$err<});

          $erread = $sval eq 'error' ? $sval : qq(WARNING - $cmd finished, but message after command appeared);

          ReadingsSingleUpdateValue ($hash, 'after_'.$cmd.'_message', $err, 1);
          ReadingsSingleUpdateValue ($hash, 'state', $erread, 1);

          return $erread;
      }
  }

  return '' if($sval && $sval !~ /running/xs);

  my $rtxt  = $cmd eq "dump"      ? "Database backup finished"                :
              $cmd eq "repair"    ? "Repair finished $hash->{DATABASE}"       :
              $cmd eq "restore"   ? "Restore of $bfile finished"              :
              $cmd eq "reduceLog" ? "reduceLog of $hash->{DATABASE} finished" :
              $cmd eq "optimize"  ? "optimize tables finished"                :
              "done";

  ReadingsSingleUpdateValue ($hash, 'state', $rtxt, 1);

return '';
}

###################################################################################
#     Befehl oder Code prozessieren
###################################################################################
sub _DbRep_procCode {
  my $hash = shift;
  my $fn   = shift;

  my $err  = q{};
  my $name = $hash->{NAME};

  $fn =~ s/\s*#.*//g;                                          # Kommentare entfernen
  $fn =  join ' ', split /\s+/sx, $fn;                         # Funktion serialisieren

  if ($fn =~ m/^\s*(\{.*\})\s*$/xs) {                          # unnamed Funktion direkt mit {...}
      $fn = $1;

      my $fdv                   = __DbRep_fhemDefVars ();
      my ($today, $hms, $we)    = ($fdv->{today}, $fdv->{hms},   $fdv->{we});
      my ($sec, $min, $hour)    = ($fdv->{sec},   $fdv->{min},   $fdv->{hour});
      my ($mday, $month, $year) = ($fdv->{mday},  $fdv->{month}, $fdv->{year});
      my ($wday, $yday, $isdst) = ($fdv->{wday},  $fdv->{yday},  $fdv->{isdst});

      eval $fn;
      $err = $@ if($@);
  }
  else {
      $err = AnalyzeCommandChain (undef, $fn);
  }

return $err;
}

###################################################################################
#  FHEM Standardvariablen bereitstellen identisch fhem.pl sub AnalyzePerlCommand
#  AnalyzePerlCommand kann nicht verwendet werden ohne die bisherige Syntax
#  (Übergabe von $name, $hash) zu brechen.
###################################################################################
sub __DbRep_fhemDefVars {
  my ($sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst) = localtime (gettimeofday());
  $month++;
  $year    += 1900;
  my $today = sprintf '%04d-%02d-%02d', $year, $month, $mday;
  my $hms   = sprintf '%02d:%02d:%02d', $hour, $min,   $sec;
  my $we    = IsWe (undef, $wday);

  my $retvals = {
      sec   => $sec,
      min   => $min,
      hour  => $hour,
      mday  => $mday,

      month => $month,
      year  => $year,
      wday  => $wday,
      yday  => $yday,
      isdst => $isdst,

      today => $today,
      hms   => $hms,
      we    => $we
  };

return $retvals;
}

##############################################################################################
#   timestamp_begin, timestamp_end bei Einsatz datetime-Picker entsprechend
#   den Anforderungen formatieren
##############################################################################################
sub DbRep_formatpicker {
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
####################################################################################################
sub DbRep_userexit {
  my $name    = shift;
  my $reading = shift // "";
  my $value   = shift // "";

  my $uefn = AttrVal($name, "userExitFn", "");
  return if(!$uefn);

  $uefn    =~ s/\s*#.*//g;                                          # Kommentare entfernen

  my $r;

  my $hash = $defs{$name};
  $value   =~ s/\\/\\\\/g;                                          # escapen of chars for evaluation
  $value   =~ s/'/\\'/g;

  $uefn    =  join ' ', split(/\s+/sx, $uefn);                      # Funktion aus Attr userExitFn serialisieren

  if ($uefn =~ m/^\s*(\{.*\})\s*$/xs) {                             # unnamed Funktion direkt in userExitFn mit {...}
      $uefn       = $1;
      my $NAME    = $name;
      my $READING = $reading;
      my $VALUE   = $value;

      eval $uefn;
      if ($@) {
          Log3 ($name, 1, "DbRep $name - ERROR in specific userExitFn: ".$@);
      }
  }
  else {                                                            # Aufruf mit Funktionsname
      my ($fun,$rex) = split / /, $uefn, 2;
      $rex         //= '.*:.*';

      if ("$reading:$value" =~ m/^$rex$/) {

          my $cmd = $fun."('$name','$reading','$value')";
          $cmd    = "{".$cmd."}";
          $r      = AnalyzeCommandChain(undef, $cmd);
      }
  }

return;
}

####################################################################################################
#                 delete Readings before new operation
# Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
####################################################################################################
sub DbRep_delread {
  my $hash         = shift;
  my $shutdown     = shift;
  
  my $name         = $hash->{NAME};
  my @allrds       = keys%{$defs{$name}{READINGS}};
  my $featurelevel = AttrVal ('global', 'featurelevel', 99.99);

  if($shutdown) {
      my $do = 0;

      for my $key(@allrds) {                                                       # Highlighted Readings löschen und save statefile wegen Inkompatibilitär beim Restart
          if($key =~ /<html><span/) {
              $do = 1;
              readingsDelete($hash,$key);
          }

          if($do == 0 && $featurelevel > 5.9 && !goodReadingName($key)) {          # Reading löschen wenn Featuelevel > 5.9 und zu lang nach der neuen Festlegung
              $do = 1;
              readingsDelete($hash,$key);
          }
      }

      WriteStatefile() if($do == 1);
      return;
  }

  my @rdpfdel = split ",", AttrVal ($name, 'readingPreventFromDel', '');

  if(@rdpfdel) {
      for my $key(@allrds) {
          my $dodel = 1;

          for my $rdpfdel(@rdpfdel) {
              if($key =~ /^$rdpfdel$/xs || $key =~ /\bstate\b|\bassociatedWith\b/) {
                  $dodel = 0;
              }
          }

          if($dodel) {                                                            # delete($defs{$name}{READINGS}{$key});
              readingsDelete($hash,$key);
          }
      }
  }
  else {
      for my $key(@allrds) {                                                      # delete($defs{$name}{READINGS}{$key}) if($key ne "state");
          next if($key =~ /\bstate\b|\bassociatedWith\b/);
          readingsDelete($hash,$key);
      }
  }

return;
}

####################################################################################################
#                          erstellen neues SQL-File für Dumproutine
####################################################################################################
sub DbRep_NewDumpFilename {
  my $paref         = shift;
  my $sql_text      = $paref->{sql_text};
  my $dump_path     = $paref->{dump_path};
  my $dbname        = $paref->{dbname};
  my $time_stamp    = $paref->{time_stamp};

  my $part       = "";
  my $sql_file   = $dump_path.$dbname."_".$time_stamp.$part.".sql";
  my $backupfile = $dbname."_".$time_stamp.$part.".sql";

  my ($err, $filesize) = DbRep_WriteToDumpFile ($sql_text, $sql_file);
  return $err if($err);

  chmod (0664, $sql_file);

return ($err, $sql_file, $backupfile);
}

####################################################################################################
#                          Schreiben DB-Dumps in SQL-File
####################################################################################################
sub DbRep_WriteToDumpFile {
  my $inh      = shift;
  my $sql_file = shift;

  my $filesize;

  my $err = '';

  if(length($inh) > 0) {
      my $fh;
      unless (open $fh,">>$sql_file") {
          $err = "Can't open file '$sql_file' for write access";
          return ($err);
      }

      binmode($fh);

      print $fh $inh;
      close $fh;

      my $fref = stat($sql_file);

      if ($fref =~ /ARRAY/) {
          $filesize = (@{stat($sql_file)})[7];
      }
      else {
          $filesize = (stat($sql_file))[7];
      }
  }

return ($err, $filesize);
}

######################################################################################
#                            Username / Paßwort speichern
#   $cre = "adminCredentials"  -> Credentials für Datenbank root-Zugriff
######################################################################################
sub DbRep_setcredentials {
    my ($hash, $cre, @credentials) = @_;
    my $name                       = $hash->{NAME};
    my ($success, $credstr, $index, $retcode,$username,$passwd);
    my (@key,$len,$i);

    $credstr = encode_base64(join(':', @credentials));

    # Beginn Scramble-Routine
    @key     = qw(1 3 4 5 6 3 2 1 9);
    $len     = scalar @key;
    $i       = 0;
    $credstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $credstr;
    # End Scramble-Routine

    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$cre;
    $retcode = setKeyValue($index, $credstr);

    if ($retcode) {
        Log3($name, 2, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    }
    else {
        ($success, $username, $passwd) = DbRep_getcredentials($hash,$cre);
    }

return ($success);
}

######################################################################################
#          das erste bzw. nächste Kommando des übergebenen multiCmd ausführen
######################################################################################
sub DbRep_nextMultiCmd {
  my $name = shift;

  return if(!defined $data{DbRep}{$name}{multicmd} || !scalar keys %{$data{DbRep}{$name}{multicmd}});

  my @mattr = qw(aggregation
                 autoForward
                 averageCalcForm
                 timestamp_begin
                 timestamp_end
                 timeDiffToNow
                 timeOlderThan
                 timeYearPeriod
                 device
                 reading
                 readingNameMap
                 optimizeTablesBeforeDump
                );

  for my $da (@mattr) {
      CommandDeleteAttr (undef, "-silent $name $da") if(defined AttrVal($name, $da, undef));
  }
  
  pop (@mattr);                                                          # optimizeTablesBeforeDump aus Liste entfernen -> Attr darf nicht gesetzt werden!
  
  my $ok   = 0;
  my $verb = 4;
  my $cmd  = '';
  my $la   = '';

  for my $k (sort{$a<=>$b} keys %{$data{DbRep}{$name}{multicmd}}) {
      my $mcmd = delete $data{DbRep}{$name}{multicmd}{$k};

      for my $sa (@mattr) {
          next if(!defined $mcmd->{$sa});
          
          CommandAttr (undef, "-silent $name $sa $mcmd->{$sa}");
      }

      $cmd = (split " ", $mcmd->{cmd})[0];
      
      if (defined $dbrep_hmainf{$cmd}) {
          $cmd = $mcmd->{cmd};
          $la  = 'start';
          $ok  = 1;
      }
      else {
          $verb = 1;
          $la   = "don't contain a valid command -> skip '$cmd'";
      }
      
      Log3 ($name, $verb, "DbRep $name - multiCmd index >$k< $la");

      last;                                                             # immer nur den ersten verbliebenen Eintrag abarbeiten
  }
  
  if ($ok) {
      CommandSet (undef, "$name $cmd");
  }
  else {
      DbRep_nextMultiCmd ($name);                                       # nächsten Eintrag abarbeiten falls Kommando ungültig
  }
  
return;
}

######################################################################################
#                             Username / Paßwort abrufen
#   $cre = "adminCredentials"  -> Credentials für Datenbank root-Zugriff
######################################################################################
sub DbRep_getcredentials {
    my ($hash, $cre) = @_;
    my $name         = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);

    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$cre;
    ($retcode, $credstr) = getKeyValue($index);

    if ($retcode) {
        Log3($name, 2, "DbRep $name - Unable to read password from file: $retcode");
        $success = 0;
    }

    if($credstr) {
        # Beginn Descramble-Routine
        @key     = qw(1 3 4 5 6 3 2 1 9);
        $len     = scalar @key;
        $i       = 0;
        $credstr = join "",
        map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $credstr;
        # Ende Descramble-Routine

        ($username, $passwd) = split(":",decode_base64($credstr));

        Log3($name, 4, "DbRep $name - $cre successfully read from file");
    }
    else {
        Log3($name, 2, "DbRep $name - ERROR - $cre not set. Use \"set $name adminCredentials\" first.");
    }

    $success = (defined($passwd)) ? 1 : 0;

return ($success, $username, $passwd);
}

####################################################################################################
#                           anlegen Keyvalue-File für DbRep wenn nicht vorhanden
####################################################################################################
sub DbRep_createCmdFile {
  my $hash  = shift;

  my $param = {FileName => $dbrep_fName};
  my @new;
  push (@new, "# This file is auto generated from 93_DbRep.pm",
              "# Please do not modify, move or delete it.",
              "");

return FileWrite ($param, @new);
}

####################################################################################################
#                      Schreibroutine in DbRep Keyvalue-File
####################################################################################################
sub DbRep_setCmdFile {
  my ($key,$value,$hash) = @_;

  my $param       = {FileName => $dbrep_fName};
  my ($err, @old) = FileRead ($param);

  DbRep_createCmdFile ($hash) if($err);

  my @new;
  my $fnd;

  for my $l (@old) {
      if($l =~ m/^$key:/) {
          $fnd = 1;
          push @new, "$key:$value" if(defined($value));
      }
      else {
          push @new, $l;
      }
  }

  push @new, "$key:$value" if(!$fnd && defined($value));

  $err = FileWrite ($param, @new);

return $err;
}

####################################################################################################
#                       Leseroutine aus DbRep Keyvalue-File
####################################################################################################
sub DbRep_getCmdFile {
  my $key = shift;

  my $param     = {FileName => $dbrep_fName};
  my ($err, @l) = FileRead ($param);
  return ($err, '') if($err);

  for my $line (@l) {
      return ('', $line) if($line =~ m/^$key:(.*)/);
  }

return;
}

####################################################################################################
#          SQL Cache für sqlCmd History aus RAM löschen
####################################################################################################
sub DbRep_deleteSQLcmdCache {
  my $name = shift;

  delete $data{DbRep}{$name}{sqlcache};
  $data{DbRep}{$name}{sqlcache}{index} = 0;                              # SQL-CommandHistory CacheIndex

return;
}

####################################################################################################
#          SQL Cache für sqlCmd History aus File löschen
####################################################################################################
sub DbRep_deleteSQLhistFromFile {
  my $name = shift;

  my $key         = $name."_sqlCmdList";
  my ($err, @old) = FileRead($dbrep_fName);
  my @new;

  if(!$err) {
      for my $l (@old) {
          if($l =~ m/^$key:/) {
              next;
          }
          else {
              push @new, $l;
          }
      }

      FileWrite($dbrep_fName, @new);
  }

return;
}

####################################################################################################
#          SQL Cache für sqlCmd History initialisieren
####################################################################################################
sub DbRep_initSQLcmdCache {
  my $name = shift;

  my $hash = $defs{$name};

  RemoveInternalTimer ($name, "DbRep_initSQLcmdCache");
  if (!$init_done) {
      InternalTimer(time+1, "DbRep_initSQLcmdCache", $name, 0);
      return;
  }

  DbRep_deleteSQLcmdCache ($name);

  my ($err,$hl) = DbRep_getCmdFile($name."_sqlCmdList");
  my $count     = 0;

  if($hl) {
      $hl = (split ":", $hl, 2)[1];

      my @cmds  = split ",", $hl;

      for my $elem (@cmds) {
          $elem = _DbRep_deconvertSQL ($elem);
          _DbRep_insertSQLtoCache     ($name, $elem);
          $count++;
      }

      Log3 ($name, 4, qq{DbRep $name - SQL history restored from Cache file - count: $count}) if($count);
  }

return $count;
}

####################################################################################################
#          sqlCmd zur SQL Cache History hinzufügen
# Drop-Down Liste bisherige sqlCmd-Befehle füllen und in Key-File sichern
####################################################################################################
sub DbRep_addSQLcmdCache {
  my $name = shift;

  my $hash = $defs{$name};

  my $tmpsql = delete $data{DbRep}{$name}{sqlcache}{temp};                         # SQL incl. Formatierung aus Zwischenspeicher
  return if(!$tmpsql);

  my $doIns = 1;
  while (my ($key, $value) = each %{$data{DbRep}{$name}{sqlcache}{cmd}}) {
      if ($tmpsql eq $value) {
          $doIns = 0;
          last;
      }
  }

  if($doIns) {
      _DbRep_insertSQLtoCache ($name, $tmpsql);
  }

return;
}

####################################################################################################
#          SQL Cache listen
#    $write:  0 - listen für Anzeige bzw. Drop-Down Liste
#             1 - erzeuge Liste zum Schreiben in Cache File
####################################################################################################
sub DbRep_listSQLcmdCache {
  my $name  = shift;
  my $write = shift // 0;

  my $cache;
  my $cstr = q{};

  for my $key (sort{$b<=>$a} keys %{$data{DbRep}{$name}{sqlcache}{cmd}}) {
      $cache .= $key." => ".$data{DbRep}{$name}{sqlcache}{cmd}{$key}."\n";

      if ($write) {
          $cstr .= $key."|=>|"._DbRep_convertSQL ($data{DbRep}{$name}{sqlcache}{cmd}{$key}, 1).",";
      }
      else {
          $cstr .= _DbRep_convertSQL ($data{DbRep}{$name}{sqlcache}{cmd}{$key}).",";
      }
  }

return ($cache,$cstr);
}

####################################################################################################
#          SQL Cache History einen Eintrag einfügen
####################################################################################################
sub _DbRep_insertSQLtoCache {
  my $name = shift;
  my $cmd  = shift;

  if ($cmd =~ /\|=\>\|/xs) {
      my ($k,$v)                             = split /\|=\>\|/, $cmd, 2;
      $data{DbRep}{$name}{sqlcache}{cmd}{$k} = $v;
      $data{DbRep}{$name}{sqlcache}{index}   = $k if($k > $data{DbRep}{$name}{sqlcache}{index});
  }
  else {
      $data{DbRep}{$name}{sqlcache}{index}++;
      my $index = $data{DbRep}{$name}{sqlcache}{index};
      $data{DbRep}{$name}{sqlcache}{cmd}{$index} = $cmd;
  }

  return if(!$init_done);                                                          # nicht beim initialen Laden ausführen

  my $hlc = AttrVal($name, "sqlCmdHistoryLength", 0);                              # Anzahl der Einträge in Drop-Down Liste

  my $ck = scalar keys %{$data{DbRep}{$name}{sqlcache}{cmd}};                      # Anzahl Paare im SQL Cache

  if ($ck > $hlc) {
      my $ey = 0;
      for my $key (sort{$b<=>$a} keys %{$data{DbRep}{$name}{sqlcache}{cmd}}) {
          $ey++;
          delete $data{DbRep}{$name}{sqlcache}{cmd}{$key} if($ey > $hlc);
      }
  }

return;
}

####################################################################################################
#             SQL Cache History speichern
####################################################################################################
sub DbRep_writeSQLcmdCache {
  my $hash = shift;

  my $name = $hash->{NAME};

  my (undef, $cstr) = DbRep_listSQLcmdCache ($name, 1);
  my $err           = DbRep_setCmdFile($name."_sqlCmdList", $cstr, $hash);

return $err;
}

####################################################################################################
#          SQL Statement konvertieren
#    $write - setzen für Schreiben Cache File
####################################################################################################
sub _DbRep_convertSQL {
  my $cmd   = shift;
  my $write = shift // 0;

  if($write) {
      $cmd =~ s/\n/&#42;/g;
      $cmd =~ s/\s/&nbsp;/g;
  }

  $cmd =~ s/\s+/&nbsp;/g;
  $cmd =~ s/,/&#65292;/g;                                               # Forum: https://forum.fhem.de/index.php/topic,103908.0.html
  $cmd =~ s/&#65292;&nbsp;/&#65292;/g;

return $cmd;
}

####################################################################################################
#          SQL Statement de-konvertieren
####################################################################################################
sub _DbRep_deconvertSQL {
  my $cmd  = shift;

  $cmd =~ s/&#42;/\n/g;
  $cmd =~ s/&nbsp;/ /g;
  $cmd =~ s/&#65292;/,/g;                                                   # Forum: https://forum.fhem.de/index.php/topic,103908.0.html

return $cmd;
}

####################################################################################################
#             Dump-Files im dumpDirLocal löschen bis auf die letzten "n"
####################################################################################################
sub DbRep_deldumpfiles {
  my ($hash,$bfile) = @_;
  my $name          = $hash->{NAME};
  my $dbloghash     = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dump_path_loc = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
  $dump_path_loc    = $dump_path_loc."/" unless($dump_path_loc =~ m/\/$/);
  my $dfk           = AttrVal($name, "dumpFilesKeep", 3);
  my $pfix          = (split '\.', $bfile)[1];
  my $dbname        = (split '_', $bfile)[0];
  my $file          = $dbname."_.*".$pfix.".*";    # Files mit/ohne Endung "gzip" berücksichtigen
  my @fd;

  if(!opendir(DH, $dump_path_loc)) {
      push(@fd, "No files deleted - Can't open path '$dump_path_loc'");
      return @fd;
  }
  my @files = sort grep {/^$file$/} readdir(DH);

  my $fref = stat("$dump_path_loc/$bfile");

  if($fref) {
      if ($fref =~ /ARRAY/) {
          @files = sort { (@{stat("$dump_path_loc/$a")})[9] cmp (@{stat("$dump_path_loc/$b")})[9] } @files
                if(AttrVal("global", "archivesort", "alphanum") eq "timestamp");
      } else {
          @files = sort { (stat("$dump_path_loc/$a"))[9] cmp (stat("$dump_path_loc/$b"))[9] } @files
                if(AttrVal("global", "archivesort", "alphanum") eq "timestamp");
      }
  }

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
#         Rückgabe        $GzipError: zip-Fehler
#                         <Ergebnisfile>
#                         $fsBytes:   Filegröße in Bytes
####################################################################################################
sub DbRep_dumpCompress {
  my $hash          = shift;
  my $bfile         = shift;
  my $name          = $hash->{NAME};
  my $dump_path_loc = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
  $dump_path_loc    =~ s/(\/$|\\$)//;
  my $input         = $dump_path_loc."/".$bfile;
  my $output        = $dump_path_loc."/".$bfile.".gzip";

  my $fsBytes = '';

  Log3($name, 3, "DbRep $name - compress file $input");

  my $stat = gzip $input => $output ,BinModeIn => 1;
  if($GzipError) {
      Log3($name, 2, "DbRep $name - gzip of $input failed: $GzipError");
      $fsBytes = _DbRep_fsizeInBytes ($input);
      return ($GzipError, $input, $fsBytes);
  }

  Log3($name, 3, "DbRep $name - file compressed to output file: $output");

  $fsBytes  = _DbRep_fsizeInBytes ($output);
  my $fsize = _DbRep_byteOutput   ($fsBytes);

  Log3 ($name, 3, "DbRep $name - Size of compressed file: ".$fsize);

  unlink("$input");

  Log3($name, 3, "DbRep $name - input file deleted: $input");

return ('', $bfile.".gzip", $fsBytes);
}

####################################################################################################
#                                  Dumpfile dekomprimieren
####################################################################################################
sub DbRep_dumpUnCompress {
  my ($hash,$bfile) = @_;
  my $name          = $hash->{NAME};
  my $dump_path_loc = AttrVal($name, "dumpDirLocal", $dbrep_dump_path_def);
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

  my $fsBytes = _DbRep_fsizeInBytes ($output);
  my $fsize   = _DbRep_byteOutput   ($fsBytes);

  Log3 ($name, 3, "DbRep $name - Size of uncompressed file: ".$fsize);

return (undef,$outfile);
}

####################################################################################################
#                      Größe File in Bytes ermitteln
####################################################################################################
sub _DbRep_fsizeInBytes {
  my $file = shift // return;

  my $fs;
  my $fref = stat($file);

  return '' if(!$fref);

  if ($fref =~ /ARRAY/) {
      $fs = (@{stat($file)})[7];
  }
  else {
      $fs = (stat($file))[7];
  }

  $fs //= '';

return ($fs);
}

####################################################################################################
#             Filesize (Byte) umwandeln in KB bzw. MB
####################################################################################################
sub _DbRep_byteOutput {
  my $bytes = shift;

  return ''     if(!defined($bytes));
  return $bytes if(!looks_like_number($bytes));

  my $suffix = q{};

  if ($bytes >= 1048576) {
      $suffix = "MB";
      $bytes  = $bytes/1048576;
  }
  elsif ($bytes >= 1024) {
      $suffix = "KB";
      $bytes  = $bytes/1024;
  }
  else {
      $suffix = "Bytes";
  }

  my $ret = sprintf "%.2f", $bytes;
  $ret   .=' '.$suffix;

return $ret;
}

####################################################################################################
#             erzeugtes Dump-File aus dumpDirLocal zum FTP-Server übertragen
####################################################################################################
sub DbRep_sendftp {
  my ($hash,$bfile) = @_;
  my $name          = $hash->{NAME};
  my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dbrep_dump_path_def);
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
sub DbRep_dsttest {
 my $hash      = shift;
 my $runtime   = shift;
 my $aggsec    = shift;
 my $name      = $hash->{NAME};
 my $dstchange = 0;

 # der Wechsel der daylight saving time wird dadurch getestet, dass geprüft wird
 # ob im Vergleich der aktuellen zur nächsten Selektionsperiode von "$aggsec (day, week, month)"
 # ein Wechsel der daylight saving time vorliegt

 my $dst      = (localtime($runtime))[8];                      # ermitteln daylight saving aktuelle runtime
 my $ostr     = localtime ($runtime);
 my $nstr     = localtime ($runtime + $aggsec);                # textual time representation
 my $dst_new  = (localtime($runtime + $aggsec))[8];            # ermitteln daylight saving nächste runtime

 if ($dst != $dst_new) {
     $dstchange = 1;
 }

 Log3 ($name, 5, qq{DbRep $name - Daylight savings changed: $dstchange (from "$ostr" to "$nstr")});

return $dstchange;
}

####################################################################################################
#                          Counthash Untersuchung
#  Logausgabe der Anzahl verarbeiteter Datensätze pro Zeitraum / Aggregation
#  Rückgabe eines ncp-hash (no calc in period) mit den Perioden für die keine Differenz berechnet
#  werden konnte weil nur ein Datensatz in der Periode zur Verfügung stand
####################################################################################################
sub DbRep_calcount {
 my ($hash,$ch) = @_;
 my $name = $hash->{NAME};
 my %ncp  = ();

 Log3 ($name, 4, "DbRep $name - count of values used for calc:");
 for my $key (sort(keys%{$ch})) {
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
sub DbRep_OutputWriteToDB {
  my $name       = shift;
  my $device     = shift;
  my $reading    = shift;
  my $wrstr      = shift;
  my $optxt      = shift;                                # Operation Kürzel

  my $hash       = $defs{$name};
  my $dbloghash  = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dblogname  = $dbloghash->{NAME};
  my $DbLogType  = AttrVal ($dblogname, 'DbLogType',  'History');
  my $supk       = AttrVal ($dblogname, 'noSupportPK',        0);

  $device        =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $type       = 'calculated';
  my $event      = 'calculated';
  my $unit       = qq{};
  my $wrt        = 0;
  my $irowdone   = 0;
  my $ndp        = AttrVal ($name, 'numDecimalPlaces', $dbrep_defdecplaces);

  my ($dbh,$err,$value,$date,$time,$hour,$minute,$ndate,$ntime,$rsf,$rsn,@wr_arr);
  my ($timestamp,$year,$mon,$mday,$t1,$corr);

  if(!$dbloghash->{HELPER}{COLSET}) {
      $err = qq(No result of "$hash->{LASTCMD}" to database written. Cause: column width in "$hash->{DEF}" isn't set);

      Log3 ($name, 2, "DbRep $name - ERROR - $err");

      $err = encode_base64($err,"");

      return ($err,$wrt,$irowdone);
  }

  no warnings 'uninitialized';

  my $aggr = (DbRep_checktimeaggr ($hash))[2];
  $reading = $optxt."_".$aggr."_".AttrVal ($name, 'readingNameMap', $reading);

  $type = uc($defs{$device}{TYPE}) if($defs{$device});            # $type vom Device übernehmen

  if($optxt =~ /avg|sum/) {
      my @arr = split "\\|", $wrstr;
      my $ele = $#arr;                                            # Nr des letzten Elements
      my $i   = 0;

      for my $row (@arr) {
          my @a              = split "#", $row;
          my $runtime_string = $a[0];                             # Aggregations-Alias (nicht benötigt)
          $value             = defined($a[1]) ? (looks_like_number($a[1]) ? sprintf("%.${ndp}f",$a[1]) : undef) : undef;                     # in Version 8.40.0 geändert
          $rsf               = $a[2];                             # Runtime String first - Datum / Zeit für DB-Speicherung
          ($date,$time)      = split "_", $rsf;
          $time              =~ s/-/:/g if($time);
          $rsn               = $a[3];                             # Runtime String next - Datum / Zeit für DB-Speicherung
          ($ndate,$ntime)    = split "_", $rsn;
          $ntime             =~ s/-/:/g if($ntime);

          if($aggr =~ /no|day|week|month|year/) {
              $time  = "00:00:01" if($time  !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);                          # https://forum.fhem.de/index.php/topic,105787.msg1013920.html#msg1013920
              $ntime = "23:59:59" if($ntime !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);

              ($year,$mon,$mday) = split "-", $ndate;
              $corr              = $i != $ele ? 86400 : 0;
              $t1                = fhemTimeLocal(59, 59, 23, $mday, $mon-1, $year-1900)-$corr;
              ($ndate,undef)     = split " ", FmtDateTime($t1);
          }
          elsif ($aggr =~ /minute|hour/) {
              ($hour,$minute) = split ":", $time;

              if($aggr eq "minute") {
                  $time  = "$hour:$minute:01" if($time  !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);                          # https://forum.fhem.de/index.php/topic,105787.msg1013920.html#msg1013920
                  $ntime = "$hour:$minute:59" if($ntime !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);
              }

              if($aggr eq "hour") {
                  $time  = "$hour:00:01" if($time  !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);                         # https://forum.fhem.de/index.php/topic,105787.msg1013920.html#msg1013920
                  $ntime = "$hour:59:59" if($ntime !~ /^(\d{2}):(\d{2}):(\d{2})$/ || $hash->{LASTCMD} =~ /\bwriteToDB(Single(Start)?)*?\b/);
              }
          }

          if (defined $value) {
              ($device,$type,$event,$reading,$value,$unit) = DbLog_cutCol($dbloghash,$device,$type,$event,$reading,$value,$unit);

              if($i == 0) {
                  push @wr_arr, "$date $time|$device|$type|$event|$reading|$value|$unit"    if($hash->{LASTCMD} !~ /\bwriteToDBSingle\b/);
                  push @wr_arr, "$ndate $ntime|$device|$type|$event|$reading|$value|$unit"  if($hash->{LASTCMD} !~ /\bwriteToDBSingleStart\b/);
              }
              else {
                  if ($aggr =~ /no|day|week|month|year/) {
                      ($year,$mon,$mday) = split "-", $date;
                      $t1                = fhemTimeLocal(01, 00, 00, $mday, $mon-1, $year-1900);
                      ($date,$time)      = split " ", FmtDateTime($t1);
                  }
                  elsif ($aggr =~ /hour/) {
                      ($year,$mon,$mday) = split "-", $date;
                      $t1                = fhemTimeLocal(01, 00, $hour, $mday, $mon-1, $year-1900);
                      ($date,$time)      = split " ", FmtDateTime($t1);
                  }

                  push @wr_arr, "$date $time|$device|$type|$event|$reading|$value|$unit"    if($hash->{LASTCMD} !~ /\bwriteToDBSingle\b/);
                  push @wr_arr, "$ndate $ntime|$device|$type|$event|$reading|$value|$unit"  if($hash->{LASTCMD} !~ /\bwriteToDBSingleStart\b/);
              }
          }
          $i++;
      }
  }

  if($optxt =~ /min|max|diff/) {
      my %rh = split "§", $wrstr;

      for my $key (sort(keys(%rh))) {
          my @k  = split "\\|", $rh{$key};
          $value = defined($k[1]) && $k[1] ne '-' ? sprintf("%.${ndp}f",$k[1]) : undef;
          $rsf   = $k[2];                                                        # Datum / Zeit für DB-Speicherung

          ($date,$time) = split "_", $rsf;
          $time         =~ s/-/:/g if($time);

          if($time !~ /^(\d{2}):(\d{2}):(\d{2})$/) {
              if($aggr =~ /no|day|week|month/) {
                  $time = "23:59:58";
              }
              elsif ($aggr =~ /hour/) {
                  $time = "$time:59:58";
              }
              elsif ($aggr =~ /minute/) {
                  $time = "$time:58";
              }
          }
          if ($value) {
              ($device,$type,$event,$reading,$value,$unit) = DbLog_cutCol($dbloghash,$device,$type,$event,$reading,$value,$unit);
              push @wr_arr, "$date $time|$device|$type|$event|$reading|$value|$unit";
          }
      }
  }

  return ($err,$wrt,$irowdone) if(!@wr_arr);

  #Log3 ($name, 2, "DbRep $name - data for write: \n". Dumper @wr_arr);
  #return;

  # Schreibzyklus
  ##################
  ($err, $dbh, my $dbmodel) = DbRep_dbConnect ($name, 0);
  return ($err,$wrt,$irowdone) if ($err);

  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
  my ($usepkh,$usepkc,$pkh,$pkc);

  if (!$supk) {
      ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
  }
  else {
      Log3 ($name, 5, "DbRep $name -> Primary Key usage suppressed by attribute noSupportPK in DbLog >$dblogname<");
  }

  my $sql            = DbRep_createInsertSQLscheme ('history', $dbmodel, $usepkh);
  ($err, my $sth_ih) = DbRep_prepareOnly           ($name, $dbh, $sql);
  return ($err,$wrt,$irowdone) if ($err);

  $sql               = DbRep_createUpdateSQLscheme ('history');
  ($err, my $sth_uh) = DbRep_prepareOnly           ($name, $dbh, $sql);
  return ($err,$wrt,$irowdone) if ($err);

  $sql               = DbRep_createInsertSQLscheme ('current', $dbmodel, $usepkc);
  ($err, my $sth_ic) = DbRep_prepareOnly           ($name, $dbh, $sql);
  return ($err,$wrt,$irowdone) if ($err);

  $sql               = DbRep_createUpdateSQLscheme ('current');
  ($err, my $sth_uc) = DbRep_prepareOnly           ($name, $dbh, $sql);
  return ($err,$wrt,$irowdone) if ($err);

  $err = DbRep_beginDatabaseTransaction ($name, $dbh);
  return ($err,$wrt,$irowdone) if ($err);

  my $wst = [gettimeofday];                                                   # SQL-Startzeit

  my $ihs = 0;
  my $uhs = 0;

  for my $row (@wr_arr) {
      my @a = split "\\|", $row;

      $timestamp = $a[0];
      $device    = $a[1];
      $type      = $a[2];
      $event     = $a[3];
      $reading   = $a[4];
      $value     = $a[5];
      $unit      = $a[6];

      if (lc($DbLogType) =~ m(history) ) {
          ($err, my $rv_uh) = DbRep_execUpdatePrepared ( { name      => $name,
                                                           sth       => $sth_uh,
                                                           timestamp => $timestamp,
                                                           device    => $device,
                                                           type      => $type,
                                                           event     => $event,
                                                           reading   => $reading,
                                                           value     => $value,
                                                           unit      => $unit
                                                         }
                                                       );
          if ($err) {
              $dbh->disconnect;
              return ($err,$wrt,$irowdone);
          }

          $uhs += $rv_uh if($rv_uh);

          Log3 ($name, 4, "DbRep $name - UPDATE history: $row, RESULT: $rv_uh");

          if ($rv_uh == 0) {
              ($err, my $rv_ih) = DbRep_execInsertPrepared ( { name      => $name,
                                                               sth       => $sth_ih,
                                                               timestamp => $timestamp,
                                                               device    => $device,
                                                               type      => $type,
                                                               event     => $event,
                                                               reading   => $reading,
                                                               value     => $value,
                                                               unit      => $unit
                                                             }
                                                           );
              if ($err) {
                  $dbh->disconnect;
                  return ($err,$wrt,$irowdone);
              }

              $ihs += $rv_ih if($rv_ih);

              Log3 ($name, 4, "DbRep $name - INSERT history: $row, RESULT: $rv_ih");
          }
      }

      if (lc($DbLogType) =~ m(current) ) {
          ($err, my $rv_uc) = DbRep_execUpdatePrepared ( { name      => $name,
                                                           sth       => $sth_uc,
                                                           timestamp => $timestamp,
                                                           device    => $device,
                                                           type      => $type,
                                                           event     => $event,
                                                           reading   => $reading,
                                                           value     => $value,
                                                           unit      => $unit
                                                         }
                                                       );
          if ($err) {
              $dbh->disconnect;
              return ($err,$wrt,$irowdone);
          }

          if ($rv_uc == 0) {
              ($err, undef) = DbRep_execInsertPrepared ( { name      => $name,
                                                           sth       => $sth_ic,
                                                           timestamp => $timestamp,
                                                           device    => $device,
                                                           type      => $type,
                                                           event     => $event,
                                                           reading   => $reading,
                                                           value     => $value,
                                                           unit      => $unit
                                                         }
                                                       );
          }
      }
  }

  $err = DbRep_commitOnly ($name, $dbh);
  return ($err,$wrt,$irowdone) if ($err);

  $dbh->disconnect;

  Log3 ($name, 3, "DbRep $name - number of lines updated in >$dblogname<: $uhs");
  Log3 ($name, 3, "DbRep $name - number of lines inserted into >$dblogname<: $ihs");

  $irowdone = $ihs + $uhs;

  $wrt = tv_interval($wst);                                                       # SQL-Laufzeit ermitteln

return ($err,$wrt,$irowdone);
}

#######################################################################################################
# Werte außer dem Extremwert (MAX/$max_value, MIN/$mix_value) aus Datenbank im Zeitraum x für
# Device / Reading löschen
#
# Struktur $rh{$key} ->
# $runtime_string."|".$max_value."|".$row_max_time."|".$runtime_string_first."|".$runtime_string_next
#
#######################################################################################################
sub DbRep_deleteOtherFromDB {
  my ($name,$device,$reading,$rows) = @_;
  my $hash       = $defs{$name};
  my $dbloghash  = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};
  my $dblogname  = $dbloghash->{NAME};
  my $dbmodel    = $dbloghash->{MODEL};
  my $dbpassword = $attr{"sec$dblogname"}{secret};
  my $wrt        = 0;
  my $irowdone   = 0;
  my $table      = "history";
  my $err        = qq{};

  my ($dbh,$sth,$timestamp,$value,$addon,$row_extreme_time,$runtime_string_first,$runtime_string_next);
  my @row_array;

  my %rh = split "§", $rows;

  for my $key (sort(keys(%rh))) {
      # Inhalt $rh{$key} -> $runtime_string."|".$max_value."|".$row_max_time."|".$runtime_string_first."|".$runtime_string_next
      my @k                 = split "\\|", $rh{$key};
      $value                = $k[1] // undef;
      $row_extreme_time     = $k[2];
      $runtime_string_first = $k[3];
      $runtime_string_next  = $k[4];

      if ($value) {                                                    # den Extremwert von Device/Reading und die Zeitgrenzen in Array speichern -> alle anderen sollen gelöscht werden
          push(@row_array, "$device|$reading|$value|$row_extreme_time|$runtime_string_first|$runtime_string_next");
      }
  }

  if (@row_array) {                                                    # Löschzyklus
      ($err,$dbh,$dbmodel) = DbRep_dbConnect($name, 0);
      return $err if ($err);

      $err = DbRep_beginDatabaseTransaction ($name, $dbh);
      return $err if ($err);

      # SQL-Startzeit
      my $wst = [gettimeofday];

      my $dlines = 0;

      for my $row (@row_array) {
          my @a                 = split "\\|", $row;
          $device               = $a[0];
          $reading              = $a[1];
          $value                = $a[2];
          $row_extreme_time     = $a[3];
          $runtime_string_first = $a[4];
          $runtime_string_next  = $a[5];

          my($date, $time) = split "_", $row_extreme_time;
          $time            =~ s/-/:/gxs;
          $addon           = qq{AND (TIMESTAMP,VALUE) != ('$date $time','$value')};
          my $sql          = DbRep_createDeleteSql($hash, $table, $device, $reading, $runtime_string_first, $runtime_string_next, $addon);

          ($err, $sth) = DbRep_prepareExecuteQuery ($name, $dbh, $sql);
          return $err if ($err);

          $dlines += $sth->rows;
      }

      $err = DbRep_commitOnly ($name, $dbh);
      return $err if ($err);

      $dbh->disconnect;

      Log3 $hash->{NAME}, 3, "DbRep $name - number of lines deleted in \"$dblogname\": $dlines";

      $irowdone = $dlines;

      # SQL-Laufzeit ermitteln
      $wrt = tv_interval($wst);
  }

return ($err,$wrt,$irowdone);
}

####################################################################################################
#                              Werte eines Array in DB schreiben
# Übergabe-Array: $date_ESC_$time_ESC_$device_ESC_$type_ESC_$event_ESC_$reading_ESC_$value_ESC_$unit
# $histupd = 1 wenn history update, $histupd = 0 nur history insert
#
####################################################################################################
sub DbRep_WriteToDB {
  my ($name,$dbh,$dbloghash,$histupd,@row_array) = @_;
  my $hash      = $defs{$name};
  my $dblogname = $dbloghash->{NAME};
  my $DbLogType = AttrVal($dblogname, "DbLogType",  "History");
  my $supk      = AttrVal($dblogname, "noSupportPK",        0);
  my $wrt       = 0;
  my $irowdone  = 0;

  my ($sth_ih,$sth_uh,$sth_ic,$sth_uc,$err,$sql);

  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
  my ($usepkh,$usepkc,$pkh,$pkc);
  if (!$supk) {
      ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
  }
  else {
      Log3 $hash->{NAME}, 5, "DbRep $name -> Primary Key usage suppressed by attribute noSupportPK in DbLog \"$dblogname\"";
  }

  if ($DbLogType =~ /history/xi) {                                               # insert history mit/ohne primary key
      if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
          $sql = "INSERT IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
          $sql = "INSERT OR IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          $sql = "INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING";
      }
      else {
          $sql = "INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }

      Log3 ($name, 4, "DbRep $name - prepare insert history SQL: \n$sql");

      eval {
          $sth_ih = $dbh->prepare_cached($sql);
      }
      or do { $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              return ($err,$irowdone,$wrt);
            };

      # update history mit/ohne primary key
      if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
          $sql = "REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
          $sql = "INSERT OR REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          $sql = "INSERT INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                  DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                  VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT";
      }
      else {
          $sql = "UPDATE history SET TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (TIMESTAMP=?) AND (DEVICE=?) AND (READING=?)";
      }

      Log3 ($name, 4, "DbRep $name - prepare update history SQL: \n$sql");
      $sth_uh = $dbh->prepare($sql);
  }

  if ($DbLogType =~ /current/xi ) {                                     # insert current mit/ohne primary key
      if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
          $sql = "INSERT IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {
          $sql = "INSERT OR IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          $sql = "INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING";
      }
      else {                                                                                 # old behavior
          $sql = "INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }

      Log3 ($name, 4, "DbRep $name - prepare insert current SQL: \n$sql");

      eval {
          $sth_ic = $dbh->prepare_cached($sql);
      }
      or do { $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              return ($err,$irowdone,$wrt);
            };

      # update current mit/ohne primary key
      if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
          $sql = "REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {
          $sql = "INSERT OR REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)";
      }
      elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          $sql = "INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                  DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                  VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT";
      }
      else {
          $sql = "UPDATE current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)";
      }

      Log3 ($name, 4, "DbRep $name - prepare update current SQL: \n$sql");
      $sth_uc = $dbh->prepare($sql);
  }

  Log3 $hash->{NAME}, 5, "DbRep $name - data prepared to db write:";

  my $wst = [gettimeofday];                                                                                      # SQL-Startzeit

  my ($ihs,$uhs) = (0,0);

  for my $row (@row_array) {
      my ($date,$time,$device,$type,$event,$reading,$value,$unit) = ($row =~ /^(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)$/);
      Log3 $hash->{NAME}, 5, "DbRep $name - $row";
      my $timestamp = $date." ".$time;

      eval {                                                                                                     # update oder insert history
          if ($DbLogType =~ /history/xi ) {
              my $rv_uh = 0;
              if($histupd) {
                  $rv_uh = $sth_uh->execute($type,$event,$value,$unit,$timestamp,$device,$reading);
              }

              if ($rv_uh == 0) {
                  $ihs += $sth_ih->execute($timestamp,$device,$type,$event,$reading,$value,$unit);               # V8.30.7
                  # $ihs++;                                                                                      # V8.30.7
              }
              else {
                  $uhs += $rv_uh;                                                                                # V8.30.7
              }
          }

          # update oder insert current
          if ($DbLogType =~ /current/xi ) {
              my $rv_uc = $sth_uc->execute($timestamp,$type,$event,$value,$unit,$device,$reading);

              if ($rv_uc == 0) {
                  $sth_ic->execute($timestamp,$device,$type,$event,$reading,$value,$unit);
              }
          }
          1;
      }
      or do { $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              $dbh->rollback;
              return ($err,$irowdone,$wrt);
            };
  }

  Log3 ($name, 3, "DbRep $name - number of lines updated in \"$dblogname\": $uhs")    if($uhs);
  Log3 ($name, 3, "DbRep $name - number of lines inserted into \"$dblogname\": $ihs") if($ihs);

  $irowdone = $ihs + $uhs;
  $wrt      = tv_interval($wst);                                                                                 # SQL-Laufzeit ermitteln

return ($err,$irowdone,$wrt);
}

################################################################
# check ob primary key genutzt wird
################################################################
sub DbRep_checkUsePK {
  my ($hash,$dbloghash,$dbh) = @_;
  my $name   = $hash->{NAME};
  my $dbconn = $dbloghash->{dbconn};
  my $upkh   = 0;
  my $upkc   = 0;
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

  Log3 ($name, 5, "DbRep $name -> Primary Key used in $db.history: $upkh ($pkh)");
  Log3 ($name, 5, "DbRep $name -> Primary Key used in $db.current: $upkc ($pkc)");

return ($upkh,$upkc,$pkh,$pkc);
}

################################################################
# prüft die logische Gültigkeit der Zeitgrenzen
# $runtime_string_first und $runtime_string_next
################################################################
sub DbRep_checkValidTimeSequence {
  my $hash                 = shift;
  my $runtime_string_first = shift;
  my $runtime_string_next  = shift;

  my $valid = 1;
  my $cause = '';

  return $valid if(!$runtime_string_first || !$runtime_string_next);

  my $mint = $hash->{HELPER}{MINTS} // '1970-01-01 01:00:00';              # Time des 1. Datensatzes in der DB

  my ($yyyy1, $mm1, $dd1, $hh1, $min1, $sec1) = $runtime_string_first =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x;
  my ($yyyy2, $mm2, $dd2, $hh2, $min2, $sec2) = $runtime_string_next  =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x;
  my ($yyyy3, $mm3, $dd3, $hh3, $min3, $sec3) = $mint                 =~ /(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/x;

  my $nthants = fhemTimeLocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900);
  my $othants = fhemTimeLocal($sec2, $min2, $hh2, $dd2, $mm2-1, $yyyy2-1900);
  my $mints   = fhemTimeLocal($sec3, $min3, $hh3, $dd3, $mm3-1, $yyyy3-1900);

  if ($mints > $othants) {
      ReadingsSingleUpdateValue ($hash, 'state', 'The Timestamp of the oldest dataset is newer than the specified time range', 1);
      $valid = 0;
      $cause = "The Timestamp of the oldest dataset ($mints) is newer than specified end time ($othants)";
  }
  elsif ($nthants > $othants) {
      ReadingsSingleUpdateValue ($hash, 'state', "ERROR - Wrong time limits. The 'nn' (days newer than) option must be greater than the 'no' (older than) one!", 1);
      $valid = 0;
      $cause = "Wrong time limits. The time stamps for start and end are logically wrong for each other.";
  }

return ($valid, $cause);
}

################################################################
# extrahiert aus dem übergebenen Wert nur die Zahl
################################################################
sub DbRep_numval {
  my $val = shift;

  return undef if(!defined($val));

  $val = ($val =~ /(-?\d+(\.\d+)?)/ ? $1 : "");

return $val;
}

################################################################
#          Zerlegung des Attributwertes "diffAccept"
################################################################
sub DbRep_ExplodeDiffAcc {
  my $val   = shift // q{empty};

  my $sign  = q{};
  my $daval = q{};

  if ($val =~/^(\+?-?)([0-9]+)$/xs) {
      $sign  = $1;
      $daval = $2;
  }

return ($sign, $daval);
}

################################################################
#  Prüfung auf numerischen Wert (vorzeichenbehaftet)
################################################################
sub DbRep_IsNumeric {
  my $val = shift // q{empty};

  my $ret = 0;

  if($val =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/xs) {
      $ret = 1;
  }

return $ret;
}

################################################################
#  entfernt führende Mullen einer Zahl
################################################################
sub DbRep_removeLeadingZero {
  my $val = shift;

  return if(!defined($val));

  $val =~ s/^0//;

return $val;
}

################################################################
# setzt Internal LASTCMD
################################################################
sub DbRep_setLastCmd {
  my (@vars) = @_;

  my $name         = shift @vars;
  my $hash         = $defs{$name};
  $hash->{LASTCMD} = join " ", @vars;

return;
}

################################################################
#        Werte aus BlockingCall heraus setzen
#   Erwartete Liste:
#   @setl = $name,$setread,$helper
################################################################
sub DbRep_setFromBlocking {
  my $name    = shift;
  my $setread = shift // "NULL";
  my $helper  = shift // "NULL";

  my $hash    = $defs{$name};

  if($setread ne "NULL") {
      my @cparts = split ":", $setread, 2;
      ReadingsSingleUpdateValue ($hash, $cparts[0], $cparts[1], 1);
  }

  if($helper ne "NULL") {
      my ($hnam,$k1,$k2,$k3) = split ":", $helper, 4;

      if(defined $k3) {
          $hash->{HELPER}{"$hnam"}{"$k1"}{"$k2"} = $k3;
      }
      elsif (defined $k2) {
          $hash->{HELPER}{"$hnam"}{"$k1"} = $k2;
      }
      else {
          $hash->{HELPER}{"$hnam"} = $k1;
      }
  }

return 1;
}

################################################################
#  löscht einen Wert vom $hash  des Hauptprozesses aus
#  einem BlockingCall heraus
################################################################
sub DbRep_delHashValFromBlocking {
  my ($name,$v1,$v2) = @_;
  my $hash        = $defs{$name};

  if($v2) {
      delete $hash->{$v1}{$v2};
  }
  elsif ($v1) {
      delete $hash->{$v1};
  }

return 1;
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub DbRep_sortVersion {
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./]} @versions;

  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./} @versions;

  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }

return @sorted;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub DbRep_setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %DbRep_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;

  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
      if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 93_DbRep.pm 28267 2023-12-08 21:52:20Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
      } else {
          $modules{$type}{META}{x_version} = $v;
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 93_DbRep.pm 28267 2023-12-08 21:52:20Z DS_Starter $ im Kopf komplett! vorhanden )
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

####################################################################################################
# blockierende DB-Abfrage
# liefert den Wert eines Device:Readings des nächstmöglichen Logeintrags zum
# angegebenen Zeitpunkt
#
# Aufruf als Funktion: DbReadingsVal("<dbrep-device>","<device:reading>","<timestamp>,"<default>")
# Aufruf als FHEM-Cmd: DbReadingsVal <dbrep-device> <device:reading> <date_time> <default>
####################################################################################################
sub CommandDbReadingsVal {
  my ($cl, $param) = @_;

  my ($name, $devread, $ts, $default) = split m{\s+}x, $param;
  $ts =~ s/_/ /;

  my $ret = DbReadingsVal($name, $devread, $ts, $default);

return $ret;
}

sub DbReadingsVal($$$$) {
  my $name    = shift // return qq{A DbRep-device must be specified};
  my $devread = shift // return qq{"device:reading" must be specified};
  my $ts      = shift // return qq{The Command needs a timestamp defined in format "YYYY-MM-DD_hh:mm:ss"};
  my $default = shift // return qq{The Command needs a default value defined};

  my ($err,$ret,$sql);

  if(!defined($defs{$name})) {
      return qq{DbRep-device "$name" doesn't exist.};
  }
  if(!$defs{$name}{TYPE} eq "DbRep") {
      return qq{"$name" is not a DbRep-device but of type "}.$defs{$name}{TYPE}.qq{"};
  }

  my $hash    = $defs{$name};
  my $dbmodel = $defs{$hash->{HELPER}{DBLOGDEVICE}}{MODEL};

  $ts =~ s/_/ /;
  if($ts !~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/x) {
      return qq{timestamp has not the valid format. Use "YYYY-MM-DD_hh:mm:ss" as timestamp.};
  }

  my ($dev,$reading) = split(":",$devread);
  if(!$dev || !$reading) {
      return qq{"device:reading" must be specified};
  }

  if($dbmodel eq "MYSQL") {
      $sql = "select value from (
                ( select *, TIMESTAMPDIFF(SECOND, '$ts', timestamp) as diff from history
                  where device='$dev' and reading='$reading' and timestamp >= '$ts' order by timestamp asc limit 1
                )
                union
                ( select *, TIMESTAMPDIFF(SECOND, timestamp, '$ts') as diff from history
                  where device='$dev' and reading='$reading' and timestamp < '$ts' order by timestamp desc limit 1
                )
              ) x order by diff limit 1;";

  } elsif ($dbmodel eq "SQLITE") {
      $sql = "select value from (
                select value, (julianday(timestamp) - julianday('$ts')) * 86400.0 as diff from history
                where device='$dev' and reading='$reading' and timestamp >= '$ts'
                union
                select value, (julianday('$ts') - julianday(timestamp)) * 86400.0 as diff from history
                where device='$dev' and reading='$reading' and timestamp < '$ts'
              )
              x order by diff limit 1;";

  } elsif ($dbmodel eq "POSTGRESQL") {
      $sql = "select value from (
                select value, EXTRACT(EPOCH FROM (timestamp - '$ts')) as diff from history
                where device='$dev' and reading='$reading' and timestamp >= '$ts'
                union
                select value, EXTRACT(EPOCH FROM ('$ts' - timestamp)) as diff from history
                where device='$dev' and reading='$reading' and timestamp < '$ts'
              )
              x order by diff limit 1;";

  } else {
      return qq{DbReadingsVal is not implemented for $dbmodel};
  }

  $hash->{LASTCMD} = "sqlCmdBlocking $sql";
  $ret             = DbRep_sqlCmdBlocking($name,$sql);
  $ret             = $ret ? $ret : $default;

return $ret;
}

####################################################################################################
# Browser Refresh nach DB-Abfrage
####################################################################################################
sub browser_refresh {
  my ($hash) = @_;
  RemoveInternalTimer($hash, "browser_refresh");
  {FW_directNotify("#FHEMWEB:WEB", "location.reload('true')", "")};
  #  map { FW_directNotify("#FHEMWEB:$_", "location.reload(true)", "") } devspec2array("WEB.*");
return;
}

###################################################################################
#                     Associated Devices setzen
###################################################################################
sub DbRep_modAssociatedWith {
  my $hash  = shift;
  my $cmd   = shift;
  my $awdev = shift;

  my $name  = $hash->{NAME};

  my (@naw,@edvs,@edvspcs,$edevswc);
  my ($edevs,$idevice,$edevice) = ('','','');

  if($cmd eq "del") {
      readingsDelete($hash,".associatedWith");
      return;
  }

  ($idevice,$edevice) = split(/EXCLUDE=/i,$awdev);

  if($edevice) {
      @edvs = split(",",$edevice);
      for my $e (@edvs) {
          $e       =~ s/%/\.*/g if($e !~ /^%$/);                      # SQL Wildcard % auflösen
          @edvspcs = devspec2array($e);
          @edvspcs = map { my $e = $_; $e =~ s/\.\*/%/xg; } @edvspcs;

          if((map {$_ =~ /%/;} @edvspcs) && $edevice !~ /^%$/) {      # Devices mit Wildcard (%) aussortieren, die nicht aufgelöst werden konnten
              $edevswc .= "|" if($edevswc);
              $edevswc .= join(" ",@edvspcs);
          }
          else {
              $edevs .= "|" if($edevs);
              $edevs .= join("|",@edvspcs);
          }
      }
  }

  if($idevice) {
      my @nadev = split("[, ]", $idevice);

      for my $d (@nadev) {
          $d    =~ s/%/\.*/g if($d !~ /^%$/);                         # SQL Wildcard % in Regex
          my @a = devspec2array($d);

          for (@a) {
              next if(!$defs{$_});
              push(@naw, $_) if($_ !~ /$edevs/);
          }
      }
  }

  if(@naw) {
      ReadingsSingleUpdateValue ($hash, ".associatedWith", join(" ",@naw), 0);
  }
  else {
      readingsDelete($hash, ".associatedWith");
  }

return;
}

####################################################################################################
#                 Test-Sub zu Testzwecken
####################################################################################################
sub DbRep_testexit {
my $hash = shift;
my $name = $hash->{NAME};


return;
}


1;

=pod
=item helper
=item summary    Reporting and management of DbLog database content.
=item summary_DE Reporting und Management von DbLog-Datenbank Inhalten.
=begin html

<a id="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  The purpose of this module is browsing and managing the content of DbLog-databases. The searchresults can be evaluated concerning to various aggregations and the appropriate
  Readings will be filled. The data selection will been done by declaration of device, reading and the time settings of selection-begin and selection-end.  <br><br>

  Almost all database operations are implemented nonblocking. If there are exceptions it will be suggested to.
  Optional the execution time of SQL-statements in background can also be determined and provided as reading.
  (refer to <a href="#DbRep-attr">attributes</a>). <br>
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
     <li> change of reading values in the database (changeValue) </li>
     <li> automatic rename of device names in datasets and other DbRep-definitions after FHEM "rename" command (see <a href="#DbRep-autorename">DbRep-Agent</a>) </li>
     <li> Execution of arbitrary user specific SQL-commands (non-blocking) </li>
     <li> Execution of arbitrary user specific SQL-commands (blocking) for usage in user own code (sqlCmdBlocking) </li>
     <li> creation of backups of the database in running state non-blocking (MySQL, SQLite) </li>
     <li> transfer dumpfiles to a FTP server after backup incl. version control</li>
     <li> restore of SQLite- and MySQL-Dumps non-blocking </li>
     <li> optimize the connected database (optimizeTables, vacuum) </li>
     <li> report of existing database processes (MySQL) </li>
     <li> purge content of current-table </li>
     <li> fill up the current-table with a (tunable) extract of the history-table</li>
     <li> delete consecutive datasets with different timestamp but same values (clearing up consecutive doublets) </li>
     <li> Repair of a corrupted SQLite database ("database disk image is malformed") </li>
     <li> transmission of datasets from source database into another (Standby) database (syncStandby) </li>
     <li> reduce the amount of datasets in database (reduceLog) </li>
     <li> delete of duplicate records (delDoublets) </li>
     <li> drop and (re)create of indexes which are needed for DbLog and DbRep (index) </li>
     </ul></ul>
     <br>

  To activate the function <b>Autorename</b> the attribute "role" has to be assigned to a defined DbRep-device. The standard role after DbRep definition is "Client".
  Please read more in section <a href="#DbRep-autorename">DbRep-Agent</a> about autorename function. <br><br>

  DbRep provides a <b>UserExit</b> function. With this interface the user can execute own program code dependent from free
  definable Reading/Value-combinations (Regex). The interface works without respectively independent from event
  generation.
  Further informations you can find as described at <a href="#DbRep-attr-userExitFn">userExitFn</a> attribute.
  <br><br>

  Once a DbRep-Device is defined, the Perl function <b>DbReadingsVal</b> provided as well as and the FHEM command <b>dbReadingsVal</b>.
  With this function you can, similar to the well known ReadingsVal, get a reading value from database. <br>
  The function is executed blocking with a standard timeout of 10 seconds to prevent a permanent blocking of FHEM.
  The timeout is adjustable with the attribute <a href="#DbRep-attr-timeout">timeout</a>. <br><br>

  <ul>
  The command syntax for the Perl function is: <br><br>

  <code>
    DbReadingsVal("&lt;name&gt;","&lt;device:reading&gt;","&lt;timestamp&gt;","&lt;default&gt;")
  </code>
  <br><br>

  <b>Example: </b><br>
  <pre>
  $ret = DbReadingsVal("Rep.LogDB1","MyWetter:temperature","2018-01-13_08:00:00","");
  attr &lt;name&gt; userReadings oldtemp {DbReadingsVal("Rep.LogDB1","MyWetter:temperature","2018-04-13_08:00:00","")}
  attr &lt;name&gt; userReadings todayPowerIn
    {
       my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
       $month++;
       $year+=1900;
       my $today = sprintf('%04d-%02d-%02d', $year,$month,$mday);
       DbReadingsVal("Rep.LogDB1","SMA_Energymeter:Bezug_Wirkleistung_Zaehler",$today."_00:00:00",0)
    }
  </pre>

  The command syntax for the FHEM command is: <br><br>

  <code>
    dbReadingsVal &lt;name&gt; &lt;device:reading&gt; &lt;timestamp&gt; &lt;default&gt;
  </code>
  <br><br>

  <b>Example: </b><br>
  <code>
    dbReadingsVal Rep.LogDB1 MyWetter:temperature 2018-01-13_08:00:00 0
  </code>
  <br><br>

  <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> <b>&lt;name&gt;</b>           </td><td>: name of the DbRep-Device to request  </td></tr>
     <tr><td> <b>&lt;device:reading&gt;</b> </td><td>: device:reading whose value is to deliver </td></tr>
     <tr><td> <b>&lt;timestamp&gt;</b>      </td><td>: timestamp of reading whose value is to deliver (*) in format "YYYY-MM-DD_hh:mm:ss" </td></tr>
     <tr><td> <b>&lt;default&gt;</b>        </td><td>: default value if no reading value can be retrieved </td></tr>
  </table>
  </ul>
  <br>

  (*) If no value can be retrieved at the &lt;timestamp&gt; exactly requested, the chronological most convenient reading
      value is delivered back.
  <br><br>

  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting and Management of database content (DbLog)</a>.<br><br>

  <br>
</ul>

  <b>Preparations </b> <br><br>
<ul>
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

</ul>
<br>

<a id="DbRep-define"></a>
<b>Definition</b>

<br>
<ul>
  <code>
    define &lt;name&gt; DbRep &lt;name of DbLog-instance&gt;
  </code>

  <br><br>
  (&lt;name of DbLog-instance&gt; - name of the database instance which is wanted to analyze needs to be inserted)
  <br><br>

  Due to a good operation performance, the database should contain the index "Report_Idx". Please create it after the DbRep
  device definition by the following set command if it isn't already existing on the database: <br><br>
  <ul>
   <code>
    set &lt;name&gt; index recreate_Report_Idx
   </code>
  </ul>

</ul>

<br><br>

<a id="DbRep-set"></a>
<b>Set </b>
<ul>

 Currently following set-commands are included. They are used to trigger the evaluations and define the evaluation option option itself.
 The criteria of searching database content and determine aggregation is carried out by setting several <a href="#DbRep-attr">attributes</a>.
 <br><br>

 <b>Note: </b> <br>
 If you are in detail view it could be necessary to refresh the browser to see the result of operation as soon in DeviceOverview section "state = done" will be shown.
 <br><br>

 <ul><ul>
     <a id="DbRep-set-adminCredentials"></a>
     <li><b> adminCredentials &lt;User&gt; &lt;Passwort&gt; </b> <br><br>

     Save a user / password for the privileged respectively administrative database access.
     The user is required for database operations which has to be executed by a privileged user.
     Please see also attribute <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>.
     </li>
     <br>

    <a id="DbRep-set-averageValue"></a>
    <li><b> averageValue [display | writeToDB | writeToDBSingle | writeToDBSingleStart | writeToDBInTime]</b> <br><br>

     Calculates an average value of the database field "VALUE" in the time limits
     of the possible time.*-attributes. <br><br>

     The reading to be evaluated must be specified in the attribute <a href="#DbRep-attr-reading">reading</a>
     must be specified.
     With the attribute <a href="#DbRep-attr-averageCalcForm">averageCalcForm</a> the calculation variant
     is used for Averaging defined. <br><br>

     If none or the option <b>display</b> is specified, the results are only displayed. With
     the options <b>writeToDB</b>, <b>writeToDBSingle</b>, <b>writeToDBSingleStart</b> or <b>writeToDBInTime</b> the
     calculation results are written with a new reading name into the database.
     <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> <b>writeToDB</b>              </td><td>: writes one value each with the time stamps XX:XX:01 and XX:XX:59 within the respective evaluation period </td></tr>
          <tr><td> <b>writeToDBSingle</b>        </td><td>: writes only one value with the time stamp XX:XX:59 at the end of an evaluation period                    </td></tr>
          <tr><td> <b>writeToDBSingleStart</b>   </td><td>: writes only one value with the time stamp XX:XX:01 at the begin of an evaluation period                  </td></tr>
          <tr><td> <b>writeToDBInTime</b>        </td><td>: writes a value at the beginning and end of the time limits of an evaluation period                       </td></tr>
       </table>
       </ul>
       <br>

     The new reading name is formed from a prefix and the original reading name,
     where the original reading name can be replaced by the attribute "readingNameMap".
     The prefix consists of the educational function and the aggregation. <br>
     The timestamp of the new readings in the database is determined by the set aggregation period
     if no clear time of the result can be determined.
     The field "EVENT" is filled with "calculated". <br><br>

     <ul>
     <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
     avgam_day_totalpac <br>
     # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>
     </ul>
     <br>

     Summarized the relevant attributes to control this function are: <br><br>

     <ul>
     <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>averageCalcForm</b>                        </td><td>: choose the calculation variant for average determination </td></tr>
        <tr><td> <b>device</b>                                 </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
        <tr><td> <b>executeBeforeProc</b>                      </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
        <tr><td> <b>executeAfterProc</b>                       </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
        <tr><td> <b>reading</b>                                </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
        <tr><td> <b>time.*</b>                                 </td><td>: a number of attributes to limit selection by time </td></tr>
        <tr><td> <b>valueFilter</b>                            </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
        </table>
     </ul>
     <br>
     <br>
     </li>

    <a id="DbRep-set-cancelDump"></a>
    <li><b> cancelDump </b> <br><br>

    Stops a running database dump.
    </li>
    <br>

    <a id="DbRep-set-changeValue"></a>
    <li><b> changeValue old="&lt;old String&gt;" new="&lt;new String&gt;" </b> <br><br>

    Changes the stored value of a reading. <br>
    If the selection is limited to certain device/reading combinations by the attributes
    <a href="#DbRep-attr-device">device</a> or <a href="#DbRep-attr-reading">reading</a>, they are taken into account
    in the same way as set time limits (time.* attributes).  <br>
    If these constraints are missing, the entire database is searched and the specified value is
    is changed. <br><br>

    The "string" can be: <br>
      <table>
         <colgroup> <col width=20%> <col width=80%> </colgroup>
         <tr><td><b>&lt;old String&gt; :</b>   </td><td><li>a simple string with/without spaces, e.g. "OL 12" </li>                                        </td></tr>
         <tr><td>                              </td><td><li>a string with use of SQL wildcard, e.g. "%OL%"    </li>                                        </td></tr>
         <tr><td> </td><td> </td></tr>
         <tr><td> </td><td> </td></tr>
         <tr><td><b>&lt;new String&gt; :</b>   </td><td><li>a simple string with/without spaces, e.g. "12 kWh" </li>                                       </td></tr>
         <tr><td>                              </td><td><li>Perl code enclosed in {"..."} including quotes, e.g. {"($VALUE,$UNIT) = split(" ",$VALUE)"}    </td></tr>
         <tr><td>                              </td><td>The variables $VALUE and $UNIT are passed to the Perl expression. They can be changed              </td></tr>
         <tr><td>                              </td><td>within the Perl code. The returned value of $VALUE and $UNIT is stored                             </td></tr>
         <tr><td>                              </td><td>in the VALUE or UNIT field of the record. </li>                                                    </td></tr>
      </table>
    <br>

    <b>Examples: </b> <br>
    set &lt;name&gt; changeValue old="OL" new="12 OL"  <br>
    # the old field value "OL" is changed to "12 OL".  <br><br>

    set &lt;name&gt; changeValue old="%OL%" new="12 OL"  <br>
    # contains the field VALUE the substring "OL", it is changed to "12 OL". <br><br>

    set &lt;name&gt; changeValue old="12 kWh" new={"($VALUE,$UNIT) = split(" ",$VALUE)"}  <br>
    # the old field value "12 kWh" is splitted to VALUE=12 and UNIT=kWh and saved into the database fields <br><br>

    set &lt;name&gt; changeValue old="24%" new={"$VALUE = (split(" ",$VALUE))[0]"}  <br>
    # if the old field value begins with "24", it is splitted and VALUE=24 is saved (e.g. "24 kWh")
    <br><br>

    Summarized the relevant attributes to control function changeValue are: <br><br>

    <ul>
      <table>
      <colgroup> <col width=5%> <col width=95%> </colgroup>
         <tr><td> <b>device</b>              </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
         <tr><td> <b>reading</b>             </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
         <tr><td> <b>time.*</b>              </td><td>: a number of attributes to limit selection by time </td></tr>
         <tr><td> <b>executeBeforeProc</b>   </td><td>: execute a FHEM command (or Perl-routine) before start of changeValue </td></tr>
         <tr><td> <b>executeAfterProc</b>    </td><td>: execute a FHEM command (or Perl-routine) after changeValue is finished </td></tr>
         <tr><td> <b>valueFilter</b>         </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
         </table>
    </ul>
    <br>
    <br>
    </li>

    <a id="DbRep-set-countEntries"></a>
    <li><b> countEntries [history|current] </b> <br><br>

    Provides the number of table entries (default: history) between time period set by
    time.* -<a href="#DbRep-attr">attributes</a> if set.
    If time.* attributes not set, all entries of the table will be count.
    The <a href="#DbRep-attr-device">device</a> and <a href="#DbRep-attr-reading">reading</a> can be used to limit the
    evaluation.  <br>
    By default the summary of all counted datasets, labeled by "ALLREADINGS", will be created. If the attribute
    <a href="#DbRep-attr-countEntriesDetail">countEntriesDetail</a> is set, the number of every reading is reported
    additionally. <br><br>

    The relevant attributes for this function are: <br><br>

    <ul>
    <table>
      <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>aggregation</b>              </td><td>: aggregatiion/grouping of time intervals </td></tr>
      <tr><td> <b>countEntriesDetail</b>       </td><td>: detailed report the count of datasets (per reading) </td></tr>
      <tr><td> <b>device</b>                   </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
      <tr><td> <b>reading</b>                  </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
      <tr><td> <b>executeBeforeProc</b>        </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
      <tr><td> <b>executeAfterProc</b>         </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
      <tr><td> <b>time.*</b>                   </td><td>: a number of attributes to limit selection by time </td></tr>
      <tr><td> <b>valueFilter</b>              </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
      </table>
    </ul>
    </li>
    <br>
    <br>

    <li><b> delDoublets [adviceDelete | delete]</b>   -  show respectively delete duplicate/multiple datasets.
                                 Therefore the fields TIMESTAMP, DEVICE, READING and VALUE of records are compared. <br>
                                 The <a href="#DbRep-attr">attributes</a> to define the scope of aggregation, time period, device and reading are
                                 considered. If attribute aggregation is not set or set to "no", it will change to the default aggregation
                                 period "day".
                                 <br><br>

                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>adviceDelete</b>  </td><td>: simulates the datasets to delete in database (nothing will be deleted !) </td></tr>
                                      <tr><td> <b>delete</b>        </td><td>: deletes the doublets </td></tr>
                                   </table>
                                   </ul>
                                   <br>

                                 Due to security reasons the attribute <a href="#DbRep-attr-allowDeletion">allowDeletion</a> needs
                                 to be set for execute the "delete" option. <br>
                                 The amount of datasets to show by commands "delDoublets adviceDelete" is initially limited
                                 and can be adjusted by <a href="#DbRep-attr-limit">limit</a> attribute.
                                 The adjustment of "limit" has no impact to the "delDoublets delete" function, but affects
                                 <b>ONLY</b> the display of the data.  <br>
                                 Before and after this "delDoublets" it is possible to execute a FHEM command or Perl script
                                 (please see attributes <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
                                 <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>).
                                 <br><br>

                                 <ul>
                                 <b>Example:</b> <br><br>
                                 Output of records to delete included their amount by "delDoublets adviceDelete": <br><br>

                                 2018-11-07_14-11-38__Dum.Energy__T 260.9_|_2 <br>
                                 2018-11-07_14-12-37__Dum.Energy__T 260.9_|_2 <br>
                                 2018-11-07_14-15-38__Dum.Energy__T 264.0_|_2 <br>
                                 2018-11-07_14-16-37__Dum.Energy__T 264.0_|_2 <br>
                                 <br>
                                 In the created readings after "_|_" the amount of the appropriate records to delete
                                 is shown. The records are deleted by command "delDoublets delete".
                                 </ul>
                                 <br>

                                 Zusammengefasst sind die zur Steuerung dieser Funktion relevanten Attribute: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>allowDeletion</b>                          </td><td>: needs to be set to execute the delete option </td></tr>
                                    <tr><td> <b>aggregation</b>                            </td><td>: choose the aggregation period </td></tr>
                                    <tr><td> <b>limit</b>                                  </td><td>: limits ONLY the count of datasets to display </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: execute a FHEM command (or Perl-routine) before start of the function </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: execute a FHEM command (or Perl-routine) after the function is finished </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: a number of attributes to limit selection by time </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
                                    </table>
                                 </ul>
                                 <br>
                                 <br>

                                 </li>

    <a id="DbRep-set-delEntries"></a>
    <li><b> delEntries [&lt;no&gt;[:&lt;nn&gt;]] </b> <br><br>

    Deletes all database entries or only the database entries specified by attributes
    <a href="#DbRep-attr-device">device</a> and/or <a href="#DbRep-attr-reading">reading</a>. <br><br>

    The time limits are considered according to the available time.*-attributes: <br><br>

    <ul>
      "timestamp_begin" is set <b>-&gt;</b> deletes db entries <b>from</b> this timestamp until current date/time <br>
      "timestamp_end" is set  <b>-&gt;</b>  deletes db entries <b>until</b> this timestamp <br>
      both Timestamps are set <b>-&gt;</b>  deletes db entries <b>between</b> these timestamps <br>
      "timeOlderThan" is set  <b>-&gt;</b>  delete entries <b>older</b> than current time minus "timeOlderThan" <br>
      "timeDiffToNow" is set  <b>-&gt;</b>  delete db entries <b>from</b> current time minus "timeDiffToNow" until now <br>
    </ul>

    <br>
    Due to security reasons the attribute <a href="#DbRep-attr-allowDeletion">allowDeletion</a> needs to be set to unlock the
    delete-function. <br>
    Time limits (days) can be specified as an option. In this case, any time.*-attributes set are
    overmodulated.
    Records older than <b>&lt;no&gt;</b> days and (optionally) newer than
    <b>&lt;nn&gt;</b> days are considered.
    <br><br>

    The relevant attributes to control function changeValue delEntries are: <br><br>

    <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>allowDeletion</b>     </td><td>: unlock the delete function </td></tr>
          <tr><td> <b>device</b>            </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
          <tr><td> <b>reading</b>           </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
          <tr><td> <b>time.*</b>            </td><td>: a number of attributes to limit selection by time </td></tr>
          <tr><td> <b>executeBeforeProc</b> </td><td>: execute a FHEM command (or Perl-routine) before start of delEntries </td></tr>
          <tr><td> <b>executeAfterProc</b>  </td><td>: execute a FHEM command (or Perl-routine) after delEntries is finished </td></tr>
          </table>
    </ul>
    <br>
    <br>
    </li>
    <br>

    <li><b> delSeqDoublets [adviceRemain | adviceDelete | delete]</b> -  show respectively delete identical sequentially datasets.
                                 Therefore Device,Reading and Value of the sequentially datasets are compared.
                                 Not deleted are the first und the last dataset of a aggregation period (e.g. hour,day,week and so on) as
                                 well as the datasets before or after a value change (database field VALUE). <br>
                                 The <a href="#DbRep-attr">attributes</a> to define the scope of aggregation, time period, device and reading are
                                 considered. If attribute aggregation is not set or set to "no", it will change to the default aggregation
                                 period "day". For datasets containing numerical values it is possible to determine a variance with attribute
                                 <a href="#DbRep-attr-seqDoubletsVariance">seqDoubletsVariance</a>.
                                 Up to this value consecutive numerical datasets are handled as identical and should be
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

                                 Due to security reasons the attribute <a href="#DbRep-attr-allowDeletion">allowDeletion</a> needs to be set for
                                 execute the "delete" option. <br>
                                 The amount of datasets to show by commands "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" is
                                 initially limited (default: 1000) and can be adjusted by attribute <a href="#DbRep-attr-limit">limit</a>.
                                 The adjustment of "limit" has no impact to the "delSeqDoublets delete" function, but affects <b>ONLY</b> the
                                 display of the data.  <br>
                                 Before and after this "delSeqDoublets" it is possible to execute a FHEM command or Perl-script
                                 (please see <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a> and
                                 <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>).
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
                                 <br>

                                 Summarized the relevant attributes to control this function are: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>allowDeletion</b>                          </td><td>: needs to be set to execute the delete option </td></tr>
                                    <tr><td> <b>aggregation</b>                            </td><td>: choose the aggregation period </td></tr>
                                    <tr><td> <b>limit</b>                                  </td><td>: limits ONLY the count of datasets to display </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: execute a FHEM command (or Perl-routine) before start of the function </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: execute a FHEM command (or Perl-routine) after the function is finished </td></tr>
                                    <tr><td> <b>seqDoubletsVariance</b>                    </td><td>: Up to this value consecutive numerical datasets are handled as identical and should be deleted </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: a number of attributes to limit selection by time </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
                                 </table>
                                 </ul>

                                 </li>
                                 <br>
                                 <br>

    <a id="DbRep-set-deviceRename"></a>
    <li><b> deviceRename &lt;old_name&gt;,&lt;new_name&gt;</b> <br><br>

    Renames the device name of a device inside the connected database (Internal DATABASE).
    The devicename will allways be changed in the <b>entire</b> database. Possibly set time limits or restrictions by
    <a href="#DbRep-attr-device">device</a> and/or <a href="#DbRep-attr-reading">reading</a> will not be considered.  <br><br>

    <ul>
     <b>Example: </b> <br>
     set &lt;name&gt; deviceRename ST_5000,ST5100  <br>
     # The amount of renamed device names (datasets) will be displayed in reading "device_renamed". <br>
     # If the device name to be renamed was not found in the database, a WARNUNG will appear in reading "device_not_renamed". <br>
     # Appropriate entries will be written to Logfile if verbose >= 3 is set.
    </ul>
    <br><br>

    <b>Note:</b> <br>
    Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
    is operating in asynchronous mode to avoid FHEMWEB from blocking. <br>
    <br>

    The relevant attributes to control this function are: <br><br>

    <ul>
     <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>executeBeforeProc</b>        </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
        <tr><td> <b>executeAfterProc</b>         </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
        </table>
    </ul>
    <br>
    <br>
    </li>

    <li><b> diffValue [display | writeToDB]</b>
                                 - calculates the difference of database column "VALUE" in the given time period. (see also the several time*-attributes). <br>
                                 The reading to evaluate must be defined in attribute <a href="#DbRep-attr-reading">reading</a>. <br>
                                 This function is mostly reasonable if values are increasing permanently and don't write value differences into the database.
                                 The difference will always be generated between all consecutive datasets (VALUE-Field) and add them together, in doing add carry value of the
                                 previous aggregation period to the next aggregation period in case the previous period contains a value. <br>
                                 A possible counter overrun (restart with value "0") will be considered (compare attribute <a href="#DbRep-attr-diffAccept">diffAccept</a>). <br><br>

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
                                 The new readingname is built of a prefix and the original reading name,
                                 in which the original reading name can be partly replaced by the value of attribute <a href="#DbRep-attr-readingNameMap">readingNameMap</a>.
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period,
                                 unless no unique point of time of the result can be determined.
                                 The field "EVENT" will be filled with "calculated".<br><br>

                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 diff_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>
                                 </ul>
                                 <br>

                                 Summarized the relevant attributes to control this function are: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>aggregation</b>                            </td><td>: choose the aggregation period </td></tr>
                                    <tr><td> <b>diffAccept</b>                             </td><td>: the accepted maximum difference between sequential records </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
                                    <tr><td> <b>readingNameMap</b>                         </td><td>: rename the resulted reading name </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: a number of attributes to limit selection by time </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
                                 </table>
                                 </ul>
                                 <br>
                                 <br>

                                 </li><br>


  <li><b> dumpMySQL [clientSide | serverSide]</b> <br><br>

     Creates a dump of the connected MySQL database.  <br>
     Depending from selected option the dump will be created on Client- or on Server-Side. <br>
     The variants differs each other concerning the executing system, the creating location, the usage of
     attributes, the function result and the needed hardware ressources. <br>
     The option "clientSide" e.g. needs more powerful FHEM-Server hardware, but saves all available
     tables inclusive possibly created views. <br>
     With attribute "dumpCompress" a compression of dump file after creation can be switched on.
     <br><br>

     <ul>
     <b><u>Option clientSide</u></b> <br>
     The dump will be created by client (FHEM-Server) and will be saved in FHEM log-directory ((typical /opt/fhem/log/)) by
     default.
     The target directory can be set by attribute <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> and has to be
     writable by the FHEM process. <br>
     Before executing the dump a table optimization can be processed optionally (see attribute
     "optimizeTablesBeforeDump") as well as a FHEM-command (attribute "executeBeforeProc").
     After the dump a FHEM-command can be executed as well (see attribute "executeAfterProc"). <br><br>

     <b>Note: <br>
     To avoid FHEM from blocking, you have to operate DbLog in asynchronous mode if the table
     optimization want to be used ! </b> <br><br>

     By the attributes <a href="#DbRep-attr-dumpMemlimit">dumpMemlimit</a> and
     <a href="#DbRep-attr-dumpSpeed">dumpSpeed</a> the run-time behavior of the function can be
     controlled to optimize the performance and demand of ressources. <br><br>

     The attributes relevant for function "dumpMySQL clientSide" are: <br><br>
       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>dumpComment </b>              </td><td>: User comment in head of dump file  </td></tr>
          <tr><td> <b>dumpCompress </b>             </td><td>: compress of dump files after creation </td></tr>
          <tr><td> <b>dumpDirLocal </b>             </td><td>: the local destination directory for dump file creation </td></tr>
          <tr><td> <b>dumpMemlimit </b>             </td><td>: limits memory usage </td></tr>
          <tr><td> <b>dumpSpeed </b>                </td><td>: limits CPU utilization </td></tr>
          <tr><td> <b>dumpFilesKeep </b>            </td><td>: number of dump files to keep </td></tr>
          <tr><td> <b>executeBeforeProc </b>        </td><td>: execution of FHEM command (or Perl-routine) before dump </td></tr>
          <tr><td> <b>executeAfterProc </b>         </td><td>: execution of FHEM command (or Perl-routine) after dump </td></tr>
          <tr><td> <b>optimizeTablesBeforeDump </b> </td><td>: table optimization before dump </td></tr>
       </table>
       </ul>
       <br>

     After a successfull finished dump the old dumpfiles are deleted and only the number of files
     defined by attribute "dumpFilesKeep" (default: 3) remain in the target directory
     "dumpDirLocal". If "dumpFilesKeep = 0" is set, all
     dumpfiles (also the current created file), are deleted. This setting can be helpful, if FTP transmission is used
     and the created dumps are only keep remain in the FTP destination directory. <br><br>

     The <b>naming convention of dump files</b> is:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.sql[.gzip] <br><br>

     To rebuild the database from a dump file the command: <br><br>

       <ul>
       set &lt;name&gt; restoreMySQL &lt;filename&gt; <br><br>
       </ul>

     can be used. <br><br>

     The created dumpfile (uncompressed) can imported on the MySQL-Server by: <br><br>

       <ul>
       mysql -u &lt;user&gt; -p &lt;dbname&gt; < &lt;filename&gt;.sql <br><br>
       </ul>

     as well to restore the database from dump file. <br><br><br>


     <b><u>Option serverSide</u></b> <br>
     The dump will be created on the MySQL-Server and will be saved in its Home-directory
     by default. <br>
     The whole history-table (not the current-table) will be exported <b>CSV-formatted</b> without
     any restrictions. <br>

     Before executing the dump a table optimization can be processed optionally (see attribute
     "optimizeTablesBeforeDump") as well as a FHEM-command (attribute "executeBeforeProc"). <br><br>

     <b>Note: <br>
     To avoid FHEM from blocking, you have to operate DbLog in asynchronous mode if the table
     optimization is used ! </b> <br><br>

     After the dump a FHEM-command can be executed as well (see attribute "executeAfterProc"). <br><br>

     The attributes relevant for function "dumpMySQL serverSide" are: <br><br>
       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>dumpDirRemote </b>            </td><td>: destination directory of dump file on remote server  </td></tr>
          <tr><td> <b>dumpCompress </b>             </td><td>: compress of dump files after creation </td></tr>
          <tr><td> <b>dumpDirLocal </b>             </td><td>: the local mounted directory dumpDirRemote </td></tr>
          <tr><td> <b>dumpFilesKeep </b>            </td><td>: number of dump files to keep </td></tr>
          <tr><td> <b>executeBeforeProc </b>        </td><td>: execution of FHEM command (or Perl-routine) before dump </td></tr>
          <tr><td> <b>executeAfterProc </b>         </td><td>: execution of FHEM command (or Perl-routine) after dump </td></tr>
          <tr><td> <b>optimizeTablesBeforeDump </b> </td><td>: table optimization before dump </td></tr>
       </table>
       </ul>
       <br>

     The target directory can be set by <a href="#DbRep-attr-dumpDirRemote">dumpDirRemote</a> attribute.
     It must be located on the MySQL-Host and has to be writable by the MySQL-server process. <br>
     The used database user must have the <b>FILE</b> privilege (see <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#3._Backup_durchf.C3.BChren_2">Wiki</a>). <br><br>

     <b>Note:</b> <br>
     If the internal version management of DbRep should be used and the size of the created dumpfile be
     reported, you have to mount the remote  MySQL-Server directory "dumpDirRemote" on the client
     and publish it to the DbRep-device by fill out the <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> attribute. <br>
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
     If those possibility is be used, the attribute <a href="#DbRep-attr-ftpUse">ftpUse</a> or
     <a href="#DbRep-attr-ftpUseSSL">ftpUseSSL</a> has to be set. The latter if encoding for FTP is to be used.
     The module also carries the version control of dump files in FTP-destination by attribute
     "ftpDumpFilesKeep". <br>
     Further attributes are: <br><br>

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
     </li>
     <br>

    <li><b> dumpSQLite </b>   -  creates a dump of the connected SQLite database.  <br>
                                 This function uses the SQLite Online Backup API and allow to create a consistent backup of the
                                 database during the normal operation.
                                 The dump will be saved in FHEM log-directory by default.
                                 The target directory can be defined by the <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> attribute and
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
                                      <tr><td> dumpCompress             </td><td>: compress of dump files after creation                   </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: Target directory of the dumpfiles                       </td></tr>
                                      <tr><td> dumpFilesKeep            </td><td>: number of dump files to keep                            </td></tr>
                                      <tr><td> executeBeforeProc        </td><td>: execution of FHEM command (or Perl-routine) before dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: execution of FHEM command (or Perl-routine) after dump  </td></tr>
                                      <tr><td> optimizeTablesBeforeDump </td><td>: table optimization before dump                          </td></tr>
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

    <a id="DbRep-set-eraseReadings"></a>
    <li><b> eraseReadings </b> <br><br>

    Deletes all created readings in the device, except reading "state" and readings, which are
    contained in exception list defined by attribute <a href="#DbRep-attr-readingPreventFromDel">readingPreventFromDel</a>.
    </li>
    <br>

    <li><b> exportToFile [&lt;/path/file&gt;] [MAXLINES=&lt;lines&gt;]</b>
                                 -  exports DB-entries to a file in CSV-format of time period specified by time attributes. <br><br>

                                 The filename can be defined by the <a href="#DbRep-attr-expimpfile">expimpfile</a> attribute. <br>
                                 Optionally a file can be specified as a command option (/path/file) and overloads a possibly
                                 defined attribute "expimpfile".
                                 The maximum number of datasets which are exported into one file can be specified
                                 with the optional parameter "MAXLINES". In this case several files with extensions
                                 "_part1", "_part2", "_part3" and so on are created (pls. remember it when you import the files !). <br>
                                 Limitation of selections can be done by attributes <a href="#DbRep-attr-device">device</a> and/or
                                 <a href="#DbRep-attr-reading">reading</a>.
                                 The filename may contain wildcards as described
                                 in attribute section of "expimpfile".
                                 <br>
                                 By setting attribute "aggregation" the export of datasets will be splitted into time slices
                                 corresponding to the specified aggregation.
                                 If, for example, "aggregation = month" is set, the data are selected in monthly packets and written
                                 into the exportfile. Thereby the usage of main memory is optimized if very large amount of data
                                 is exported and avoid the "died prematurely" error. <br><br>

                                 The attributes relevant for this function are: <br><br>
                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>aggregation</b>                          </td><td>: determination of selection time slices </td></tr>
                                      <tr><td> <b>device</b>                               </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
                                      <tr><td> <b>reading</b>                              </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>                                      <tr><td> <b>time.*</b>            </td><td>: a number of attributes to limit selection by time </td></tr>
                                      <tr><td> <b>executeBeforeProc</b>                    </td><td>: execution of FHEM command (or Perl-routine) before export </td></tr>
                                      <tr><td> <b>executeAfterProc</b>                     </td><td>: execution of FHEM command (or Perl-routine) after export </td></tr>
                                      <tr><td> <b>expimpfile</b>                           </td><td>: the name of exportfile </td></tr>
                                      <tr><td> <b>time.*</b>                               </td><td>: a number of attributes to limit selection by time </td></tr>
                                      <tr><td> <b>valueFilter</b>                          </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
                                      </table>
                                   </ul>

                                 </li> <br>

    <li><b> fetchrows [history|current] </b>
                              -  provides <b>all</b> table entries (default: history)
                                 of time period set by time.*-<a href="#DbRep-attr">attributes</a> respectively selection conditions
                                 by attributes "device" and "reading".
                                 An aggregation set will <b>not</b> be considered.  <br>
                                 The direction of data selection can be determined by the <a href="#DbRep-attr-fetchRoute">fetchRoute</a> attribute.
                                 <br><br>

                                 Every reading of result is composed of the dataset timestring , an index, the device name
                                 and the reading name.
                                 The function has the capability to reconize multiple occuring datasets (doublets).
                                 Such doublets are marked by an index > 1. Optional a Unique-Index is appended if
                                 datasets with identical timestamp, device and reading but different value are existing. <br>
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
                                 2017-10-22_03-04-43__1__SMA_Energymeter__Bezug_WirkP_Kosten_Diff__[1] <br>
                                 # &lt;date&gt;_&lt;time&gt;__&lt;index&gt;__&lt;device&gt;__&lt;reading&gt;__[Unique-Index]
                                 </ul>
                                 <br>

                                 For a better overview the relevant attributes are listed here in a table: <br><br>

                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>device</b>               </td><td>: include or exclude &lt;device&gt; from selection </td></tr>
                                      <tr><td> <b>fetchRoute</b>           </td><td>: direction of selection read in database </td></tr>
                                      <tr><td> <b>fetchMarkDuplicates</b>  </td><td>: Highlighting of found doublets </td></tr>
                                      <tr><td> <b>fetchValueFn</b>         </td><td>: the displayed value of the VALUE database field can be changed by a function before the reading is created </td></tr>
                                      <tr><td> <b>limit</b>                </td><td>: limits the number of datasets to select and display </td></tr>
                                      <tr><td> <b>reading</b>              </td><td>: include or exclude &lt;reading&gt; from selection </td></tr>
                                      <tr><td> <b>executeBeforeProc</b>    </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
                                      <tr><td> <b>executeAfterProc</b>     </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
                                      <tr><td> <b>time.*</b>               </td><td>: A number of attributes to limit selection by time </td></tr>
                                      <tr><td> <b>valueFilter</b>          </td><td>: an additional REGEXP to control the record selection. The REGEXP is applied to the database field 'VALUE'. </td></tr>
                                   </table>
                                   </ul>
                                   <br>
                                   <br>

                                 <b>Note:</b> <br>
                                 Although the module is designed non-blocking, a huge number of selection result (huge number of rows)
                                 can overwhelm the browser session respectively FHEMWEB.
                                 Due to the sample space can be limited by <a href="#DbRep-attr-limit">limit</a> attribute.
                                 Of course ths attribute can be increased if your system capabilities allow a higher workload. <br><br>
                                 </li> <br>

    <li><b> index &lt;Option&gt; </b>
                               - Reports the existing indexes in the database or creates the index which is needed.
                               If the index is already created, it will be renewed (dropped and new created) <br><br>

                               The possible options are:    <br><br>

                               <ul>
                                 <table>
                                   <colgroup> <col width=25%> <col width=75%> </colgroup>
                                   <tr><td> <b>list_all</b>                 </td><td>: reports the existing indexes </td></tr>
                                   <tr><td> <b>recreate_Search_Idx</b>      </td><td>: create or renew (if existing) the index Search_Idx in table history (index for DbLog) </td></tr>
                                   <tr><td> <b>drop_Search_Idx</b>          </td><td>: delete the index Search_Idx in table history </td></tr>
                                   <tr><td> <b>recreate_Report_Idx</b>      </td><td>: create or renew (if existing) the index Report_Idx in table history (index for DbRep) </td></tr>
                                   <tr><td> <b>drop_Report_Idx</b>          </td><td>: delete the index Report_Idx in table history </td></tr>
                                 </table>
                               </ul>
                               <br>

                               For a better overview the relevant attributes for this operation are listed here: <br><br>

                               <ul>
                                 <table>
                                   <colgroup> <col width=42%> <col width=58%> </colgroup>
                                   <tr><td> <b>useAdminCredentials</b>        </td><td>: use privileged user for the operation </td></tr>
                                 </table>
                               </ul>
                               <br>
                               <br>

                               <b>Note:</b> <br>
                               The MySQL database user used requires the ALTER, CREATE and INDEX privilege. <br>
                               These rights can be set with: <br><br>
                               <ul>
                                 set &lt;Name&gt; sqlCmd GRANT INDEX, ALTER, CREATE ON `&lt;db&gt;`.* TO '&lt;user&gt;'@'%';
                               </ul>
                               <br>
                               The <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a> attribute must usually be set to be able to
                               change the rights of the used user.

                               </li>
                               <br>

    <a id="DbRep-set-insert"></a>
    <li><b> insert &lt;Date&gt;,&lt;Time&gt;,&lt;Value&gt;,[&lt;Unit&gt;],[&lt;Device&gt;],[&lt;Reading&gt;] </b>
                                 -  Manual insertion of a data record into the table "history". Input values for date, time and value are obligatory.
                                 The values for the DB fields TYPE and EVENT are filled with "manual". <br>
                                 If <b>Device</b>, <b>Reading</b> are not set, these values are taken from the corresponding
                                 attributes <a href="#DbRep-attr-device">device</a>, <a href="#DbRep-attr-reading">reading</a>.
                                 <br><br>

                                 <b>Note: </b><br>
                                 Unused fields within the insert command must be enclosed within the string in ","
                                 within the string.
                                 <br>
                                 <br>

                                 <ul>
                                 <b>Examples: </b> <br>
                                 set &lt;name&gt; insert 2016-08-01,23:00:09,12.03,kW                         <br>
                                 set &lt;name&gt; insert 2021-02-02,10:50:00,value with space                 <br>
                                 set &lt;name&gt; insert 2022-05-16,10:55:00,1800,,SMA_Wechselrichter,etotal  <br>
                                 set &lt;name&gt; insert 2022-05-16,10:55:00,1800,,,etotal                    <br>
                                 </ul>
                                 <br>

                                 The relevant attributes to control this function are: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>executeBeforeProc</b>        </td><td>: execution of FHEM command (or Perl-routine) before operation </td></tr>
                                    <tr><td> <b>executeAfterProc</b>         </td><td>: execution of FHEM command (or Perl-routine) after operation </td></tr>
                                    </table>
                                 </ul>
                                 <br>
                                 <br>

                                 </li>

    <li><b> importFromFile [&lt;file&gt;] </b>
                                 - imports data in CSV format from file into database. <br>
                                 The filename can be defined by attribute <a href="#DbRep-attr-expimpfile">expimpfile</a>. <br>
                                 Optionally a file can be specified as a command option (/path/file) and overloads a possibly
                                 defined attribute "expimpfile". The filename may contain wildcards as described
                                 in attribute section of "expimpfile". <br><br>

                                 <ul>
                                 <b>dataset format: </b> <br>
                                 "TIMESTAMP","DEVICE","TYPE","EVENT","READING","VALUE","UNIT"  <br><br>
                                 # The fields "TIMESTAMP","DEVICE","TYPE","EVENT","READING" and "VALUE" have to be set. The field "UNIT" is optional.
                                 The file content will be imported transactional. That means all of the content will be imported or, in case of error, nothing of it.
                                 If an extensive file will be used, DON'T set verbose = 5 because of a lot of datas would be written to the logfile in this case.
                                 It could lead to blocking or overload FHEM ! <br><br>

                                 <b>Example for a source dataset: </b> <br>
                                 "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>

                                 The attributes relevant for this function are: <br><br>
                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>executeBeforeProc</b>  </td><td>: execution of FHEM command (or Perl-routine) before import </td></tr>
                                      <tr><td> <b>executeAfterProc</b>   </td><td>: execution of FHEM command (or Perl-routine) after import </td></tr>
                                      <tr><td> <b>expimpfile</b>         </td><td>: the name of exportfile </td></tr>
                                   </table>
                                   </ul>

                                 </li> <br>
                                 </ul>
                                 <br>

    <li><b> maxValue [display | writeToDB | deleteOther]</b> <br>br>

    Calculates the maximum value of database column "VALUE" between period given by attributes
    <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>, "timestamp_end" / "timeDiffToNow / timeOlderThan" and so on.
    The reading to evaluate must be defined using attribute <a href="#DbRep-attr-reading">reading</a>.
    The evaluation contains the timestamp of the <b>last</b> appearing of the identified maximum value
    within the given period.  <br><br>

    If no option or the option <b>display</b> is specified, the results are only displayed. Using
    option <b>writeToDB</b> the calculated results are stored in the database with a new reading
    name. <br>

    The new readingname is built of a prefix and the original reading name,
    in which the original reading name can be replaced by the value of attribute <a href="#DbRep-attr-readingNameMap">readingNameMap</a>.
    The prefix is made up of the creation function and the aggregation. <br>
    The timestamp of the new stored readings is deviated from aggregation period,
    unless no unique point of time of the result can be determined.
    The field "EVENT" will be filled with "calculated". <br><br>

    With option <b>deleteOther</b> all datasets except the dataset with the maximum value are deleted. <br><br>

    <ul>
      <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
      max_day_totalpac <br>
      # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>
    </ul>
    <br>

    Summarized the relevant attributes to control this function are: <br>

    <ul>
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-attributes
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-migrateCollation"></a>
    <li><b> migrateCollation &lt;Collation&gt; </b> <br><br>

    Migrates the used character set/collation of the database and the tables current and history to the
    specified format.
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <li><b> minValue [display | writeToDB | deleteOther]</b> <br><br>

    Calculates the minimum value of database column "VALUE" between period given by attributes
    <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>, "timestamp_end" / "timeDiffToNow / timeOlderThan" and so on.
    The reading to evaluate must be defined using attribute <a href="#DbRep-attr-reading">reading</a>.
    The evaluation contains the timestamp of the <b>first</b> appearing of the identified minimum
    value within the given period.  <br><br>

    If no option or the option <b>display</b> is specified, the results are only displayed. Using
    option <b>writeToDB</b> the calculated results are stored in the database with a new reading
    name. <br>

    The new readingname is built of a prefix and the original reading name,
    in which the original reading name can be replaced by the value of attribute <a href="#DbRep-attr-readingNameMap">readingNameMap</a>.
    The prefix is made up of the creation function and the aggregation. <br>
    The timestamp of the new stored readings is deviated from aggregation period,
    unless no unique point of time of the result can be determined.
    The field "EVENT" will be filled with "calculated". <br><br>

    With option <b>deleteOther</b> all datasets except the dataset with the maximum value are deleted. <br><br>

    <ul>
      <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
      min_day_totalpac <br>
      # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>
    </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-multiCmd"></a>
    <li><b> multiCmd {&lt;Befehl-Hash&gt;}</b>  <br><br>

    Executes several set commands sequentially in a definable order. <br>
    The commands and certain modifiable attributes that are relevant for the commands are transferred in a
    hash.  <br>
    The commands to be executed (key <b>cmd</b>) and the attributes to be set for them are defined via keys in the
    transferred hash. The order in which the commands are processed is determined via the command index in the
    hash.
    <br><br>

    Attribute keys that can be defined in the hash are: <br>

    <ul>
      <a href="#DbRep-attr-autoForward">autoForward</a>,
      <a href="#DbRep-attr-averageCalcForm">averageCalcForm</a>,
      <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>,
      <a href="#DbRep-attr-timestamp_end">timestamp_end</a>,
      <a href="#DbRep-attr-timeDiffToNow">timeDiffToNow</a>,
      <a href="#DbRep-attr-timeOlderThan">timeOlderThan</a>,
      <a href="#DbRep-attr-timeYearPeriod">timeYearPeriod</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-reading">readingNameMap</a>,
    </ul>
    <br>

    <b>Example of the definition of a command hash: </b> <br>

    <ul>
      <pre>
        {
          1  => { timestamp_begin => '2023-12-17 00:00:00', 
                  timestamp_end   => '2023-12-17 01:00:00', 
                  device          => 'SMA_Energymeter', 
                  reading         => 'Einspeisung_Wirkleistung_Zaehler', 
                  cmd             => 'countEntries history'
                },
          2  => { timestamp_begin => '2023-12-15 11:00:00', 
                  timestamp_end   => 'previous_day_end', 
                  device          => 'SMA_Energymeter', 
                  reading         => 'Einspeisung_Wirkleistung_Zaehler', 
                  cmd             => 'countEntries' 
                },
          3  => { timeDiffToNow   => 'd:2',
                  readingNameMap  => 'COUNT',
                  autoForward     => '{ ".*COUNT.*" => "Dum.Rep.All" }',
                  device          => 'SMA_%,MySTP.*',
                  reading         => 'etotal,etoday,Ein% EXCLUDE=%Wirkleistung', 
                  cmd             => 'countEntries history' 
                },
          4  => { timeDiffToNow   => 'd:2',
                  readingNameMap  => 'SUM',
                  autoForward     => '{ ".*SUM.*" => "Dum.Rep.All" }',
                  device          => 'SMA_%,MySTP.*',
                  reading         => 'etotal,etoday,Ein% EXCLUDE=%Wirkleistung', 
                  cmd             => 'sumValue' 
                },
          5  => { cmd             => 'sqlCmd select count(*) from current'
                },
        }
      </pre>
    </ul>
    </li>
    <br>

    <a id="DbRep-set-optimizeTables"></a>
    <li><b> optimizeTables [showInfo | execute]</b> <br><br>

    Optimize tables in the connected database (MySQL). <br><br>

    <ul>
    <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>showInfo</b>  </td><td>: shows information about the used / free space within the database   </td></tr>
        <tr><td> <b>execute</b>   </td><td>: performs optimization of all tables in the database                 </td></tr>
     </table>
    </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    </li>

    <a id="DbRep-set-readingRename"></a>
    <li><b> readingRename &lt;[device:]oldreadingname&gt;,&lt;newreadingname&gt; </b> <br><br>

    Renames the reading name of a device inside the connected database (see Internal DATABASE).
    The readingname will allways be changed in the <b>entire</b> database.
    Possibly set time limits or restrictions by attributes
    <a href="#DbRep-attr-device">device</a> and/or <a href="#DbRep-attr-reading">reading</a> will not be considered.  <br>
    As an option a device can be specified. In this case only the old readings of this device
    will be renamed. <br><br>

    <ul>
      <b>Examples: </b> <br>
      set &lt;name&gt; readingRename TotalConsumtion,L1_TotalConsumtion  <br>
      set &lt;name&gt; readingRename Dum.Energy:TotalConsumtion,L1_TotalConsumtion  <br>
    </ul>
    <br>

    The amount of renamed reading names (datasets) will be displayed in reading "reading_renamed". <br>
    If the reading name to be renamed was not found in the database, a WARNING will appear in reading "reading_not_renamed". <br>
    Appropriate entries will be written to Logfile if verbose >= 3 is set.
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <br>
    </li>

    <li><b> reduceLog [&lt;no&gt;[:&lt;nn&gt;]] [mode] [EXCLUDE=device1:reading1,device2:reading2,...] [INCLUDE=device:reading] </b> <br><br>

    Reduces historical data sets. <br><br>

    <b>Operation without specifying command line operators</b> <br><br>

    The data is cleaned within the time limits defined by the <b>time.*</b>-attributes.
    At least one of the <b>time.*</b> attributes must be set (see table below).
    The respective missing time accrual is determined by the module in this case. <br>
    The working mode is determined by the optional specification of <b>mode</b>:
    <br><br>

    <ul>
    <table>
    <colgroup> <col width=23%> <col width=77%> </colgroup>
       <tr><td> <b>without specification of mode</b> </td><td>:&nbsp;the data is reduced to the first entry per hour per device & reading                                        </td></tr>
       <tr><td> <b>average</b>                       </td><td>:&nbsp;numerical values are reduced to an average value per hour per device & reading, otherwise as without mode   </td></tr>
       <tr><td> <b>average=day</b>                   </td><td>:&nbsp;numeric values are reduced to one mean value per day per device & reading, otherwise as without mode        </td></tr>
       <tr><td>                                      </td><td>&nbsp;&nbsp;The FullDay option (full days are always selected) is used implicitly.                                 </td></tr>
       <tr><td> <b>max</b>                           </td><td>:&nbsp;numeric values are reduced to the maximum value per hour per device & reading, otherwise as without mode    </td></tr>
       <tr><td> <b>max=day</b>                       </td><td>:&nbsp;numeric values are reduced to the maximum value per day per device & reading, otherwise as without mode     </td></tr>
       <tr><td>                                      </td><td>&nbsp;&nbsp;The FullDay option (full days are always selected) is used implicitly.                                 </td></tr>
       <tr><td> <b>min</b>                           </td><td>:&nbsp;numeric values are reduced to the minimum value per hour per device & reading, otherwise as without mode    </td></tr>
       <tr><td> <b>min=day</b>                       </td><td>:&nbsp;numeric values are reduced to the minimum value per day per device & reading, otherwise as without mode     </td></tr>
       <tr><td>                                      </td><td>&nbsp;&nbsp;The FullDay option (full days are always selected) is used implicitly.                                 </td></tr>
       <tr><td> <b>sum</b>                           </td><td>:&nbsp;numeric values are reduced to the sum per hour per Device & Reading, otherwise as without mode              </td></tr>
       <tr><td> <b>sum=day</b>                       </td><td>:&nbsp;numeric values are reduced to the sum per day per Device & Reading, otherwise as without mode               </td></tr>
       <tr><td>                                      </td><td>&nbsp;&nbsp;The FullDay option (full days are always selected) is used implicitly.                                 </td></tr>
    </table>
    </ul>
    <br>


    With the attributes <b>device</b> and <b>reading</b> the data records to be considered can be included
    or be excluded. Both restrictions reduce the selected data and reduce the
    resource requirements.
    The read "reduceLogState" contains the execution result of the last reduceLog command.  <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-numDecimalPlaces">numDecimalPlaces</a>,
      <a href="#DbRep-attr-timeOlderThan">timeOlderThan</a>,
      <a href="#DbRep-attr-timeDiffToNow">timeDiffToNow</a>,
      <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>,
      <a href="#DbRep-attr-timestamp_end">timestamp_end</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

     <b>Examples: </b><br><br>
     <ul>
     attr &lt;name&gt; timeOlderThan d:200  <br>
     set &lt;name&gt; reduceLog <br>
     # Records older than 200 days are written to the first entry per hour per Device & Reading.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:200  <br>
     set &lt;name&gt; reduceLog average=day <br>
     # Records newer than 200 days are limited to one entry per day per Device & Reading.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:30  <br>
     attr &lt;name&gt; device TYPE=SONOSPLAYER EXCLUDE=Sonos_Kueche  <br>
     attr &lt;name&gt; reading room% EXCLUDE=roomNameAlias  <br>
     set &lt;name&gt; reduceLog <br>
     # Records newer than 30 days that are devices of type SONOSPLAYER
     (except Device "Sonos_Kitchen") and the readings start with "room" (except "roomNameAlias")
     are reduced to the first entry per hour per Device & Reading.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:10 <br>
     attr &lt;name&gt; timeOlderThan d:5  <br>
     attr &lt;name&gt; device Luftdaten_remote  <br>
     set &lt;name&gt; reduceLog average <br>
     # Records older than 5 and newer than 10 days and containing DEVICE "Luftdaten_remote
     are adjusted. Numerical values of an hour are reduced to an average value <br>
     <br>
     </ul>
     <br>

     <b>Operation with specification of command line operators</b> <br><br>

     Es werden Datensätze berücksichtigt die älter sind als <b>&lt;no&gt;</b> Tage und (optional) neuer sind als
     <b>&lt;nn&gt;</b> Tage.
     Records are considered that are older than <b>&lt;no&gt;</b> days and (optionally) newer than
     <b>&lt;nn&gt;</b> days.
     The working mode is determined by the optional specification of <b>mode</b> as described above.
     <br><br>

     The additions "EXCLUDE" or "INCLUDE" can be added to exclude or include device/reading combinations in reduceLog
     and override the "device" and "reading" attributes, which are ignored in this case. <br>
     The specification in "EXCLUDE" is evaluated as a <b>regex</b>. Inside "INCLUDE", <b>SQL wildcards</b>
     can be used. (for more information on SQL wildcards, see with <b>get &lt;name&gt; versionNotes 6</b>)
     <br><br>

     <b>Examples: </b><br><br>
     <ul>
     set &lt;name&gt; reduceLog 174:180 average EXCLUDE=SMA_Energymeter:Bezug_Wirkleistung INCLUDE=SMA_Energymeter:% <br>
     # Records older than 174 and newer than 180 days are reduced to average per hour. <br>
     # All readings from the device "SMA_Energymeter" except "Bezug_Wirkleistung" are taken reduced.  <br>
     </ul>
     <br>

    <b>Note:</b> <br>
    Although the function itself is designed non-blocking, the assigned DbLog device should be operated in
    asynchronous mode to avoid blocking FHEMWEB (table lock). <br>
    Furthermore it is strongly recommended to create the standard INDEX 'Search_Idx' in the table
    'history' ! <br>
    The processing of this command may take an extremely long time (without INDEX). <br><br>

    </li>
    <br>

    <a id="DbRep-set-repairSQLite"></a>
    <li><b> repairSQLite [sec] </b> <br><br>

    Repairs a corrupted SQLite database. <br><br>

    A corruption is usally existent when the error message "database disk image is malformed"
    appears in reading "state" of the connected DbLog-device.
    If the command was started, the connected DbLog-device will firstly disconnected from the
    database for 10 hours (36000 seconds) automatically (breakup time). After the repair is
    finished, the DbLog-device will be connected to the (repaired) database immediately. <br>
    As an argument the command can be completed by a differing breakup time (in seconds). <br>
    The corrupted database is saved as &lt;database&gt;.corrupt in same directory.
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Example: </b><br>
    <ul>
      set &lt;name&gt; repairSQLite  <br>
      # the database is trying to repair, breakup time is 10 hours <br>
      set &lt;name&gt; repairSQLite 600 <br>
      # the database is trying to repair, breakup time is 10 minutes
      <br><br>
    </ul>

    <b>Note:</b> <br>
    It can't be guaranteed, that the repair attempt proceed successfully and no data loss will result.
    Depending from corruption severity data loss may occur or the repair will fail even though
    no error appears during the repair process. Please make sure a valid backup took place !
    <br><br>

    </li>
    <br>

    <a id="DbRep-set-restoreMySQL"></a>
    <li><b> restoreMySQL &lt;File&gt; </b>  - restore a database from serverSide- or clientSide-Dump. <br><br>

    The function provides a drop-down-list of files which can be used for restore. <br><br>

    <b>Usage of serverSide-Dumps </b> <br>
    The content of history-table will be restored from a serverSide-Dump.
    Therefore the remote directory "dumpDirRemote" of the MySQL-Server has to be mounted on the
    Client and make it usable to the DbRep device by setting attribute <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a>
    to the appropriate value. <br>
    All files with extension "csv[.gzip]" and if the filename is beginning with the name of the connected database
    (see Internal DATABASE) are listed.
    <br><br>

    <b>Usage of clientSide-Dumps </b> <br>
    The used database user needs the <b>FILE</b> privilege (see <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#4._Restore_2">Wiki</a>). <br>
    All tables and views (if present) are restored.
    The directory which contains the dump files has to be set by attribute <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a>
    to make it usable by the DbRep device. <br>
    All files with extension "sql[.gzip]" and if the filename is beginning with the name of the connected database
    (see Internal DATABASE) are listed. <br>
    The restore speed depends of the server variable "<b>max_allowed_packet</b>". You can change
    this variable in file my.cnf to adapt the speed. Please consider the need of sufficient ressources
    (especially RAM).
    <br><br>

    The database user needs rights for database management, e.g.: <br>
    CREATE, ALTER, INDEX, DROP, SHOW VIEW, CREATE VIEW
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-restoreSQLite"></a>
    <li><b> restoreSQLite &lt;File&gt;.sqlitebkp[.gzip] </b>  <br><br>

    Restores a backup of SQLite database. <br>
    The function provides a drop-down-list of files which can be used for restore.
    The data stored in the current database are deleted respectively overwritten.
    All files with extension "sqlitebkp[.gzip]" and if the filename is beginning with the name of the connected database
    will are listed.
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <li><b> sqlCmd </b> <br><br>

    Executes any user-specific command.  <br>
    If this command contains a delete operation, for safety reasons the attribute
    <a href="#DbRep-attr-allowDeletion">allowDeletion</a> has to be set. <br>

    sqlCmd also accepts the setting of SQL session variables such as.
    "SET @open:=NULL, @closed:=NULL;" or the use of SQLite PRAGMA prior to the
    execution of the SQL statement.
    If the session variable or PRAGMA has to be set every time before executing a SQL statement, the
    attribute <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a> can be set. <br><br>

    If the attributes <a href="#DbRep-attr-device">device</a>, <a href="#DbRep-attr-reading">reading</a>,
    <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a> respectively
    <a href="#DbRep-attr-timestamp_end">timestamp_end</a>
    set in the module are to be taken into account in the statement,
    the placeholders <b>§device§</b>, <b>§reading§</b>, <b>§timestamp_begin§</b> respectively
    <b>§timestamp_end§</b> can be used for this purpose. <br>
    It should be noted that the placeholders §device§ and §reading§ complex are resolved and
    should be applied accordingly as in the example below.
    <br><br>

    If you want update a dataset, you have to add "TIMESTAMP=TIMESTAMP" to the update-statement to avoid changing the
    original timestamp. <br><br>

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
    <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where §device§ AND TIMESTAMP >= §timestamp_begin§ group by DEVICE  </li>
    <li>set &lt;name&gt; sqlCmd select DEVICE, READING, count(*) from history where §device§ AND §reading§ AND TIMESTAMP >= §timestamp_begin§ group by DEVICE, READING  </li>
    <br>

    Here you can see examples of a more complex statement (MySQL) with setting SQL session
    variables and the SQLite PRAGMA usage: <br><br>

    <li>set &lt;name&gt; sqlCmd SET @open:=NULL, @closed:=NULL;
           SELECT
               TIMESTAMP, VALUE,DEVICE,
               @open AS open,
               @open := IF(VALUE = 'open', TIMESTAMP, NULL) AS curr_open,
               @closed  := IF(VALUE = 'closed',  TIMESTAMP, NULL) AS closed
           FROM history WHERE
              DATE(TIMESTAMP) = CURDATE() AND
              DEVICE = "HT_Fensterkontakt" AND
              READING = "state" AND
              (VALUE = "open" OR VALUE = "closed")
              ORDER BY  TIMESTAMP; </li>
    <li>set &lt;name&gt; sqlCmd PRAGMA temp_store=MEMORY; PRAGMA synchronous=FULL; PRAGMA journal_mode=WAL; PRAGMA cache_size=4000; select count(*) from history; </li>
    <li>set &lt;name&gt; sqlCmd PRAGMA temp_store=FILE; PRAGMA temp_store_directory = '/opt/fhem/'; VACUUM; </li>
    </ul>
    <br>

    The formatting of result can be choosen by attribute <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
    as well as the used field separator can be determined by attribute
    <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>. <br><br>

    The module provides a command history once a sqlCmd command was executed successfully.
    To use this option, activate the attribute <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>
    with list lenght you want. <br>
    If the command history is enabled, an indexed list of stored SQL statements is available
    with <b>___list_sqlhistory___</b> within the sqlCmdHistory command. <br><br>

    An SQL statement can be executed by specifying its index in this form:
    <br><br>
      <ul>
        set &lt;name&gt; sqlCmd ckey:&lt;Index&gt;   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(e.g. ckey:4)
      </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>,
      <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Note:</b> <br>
    Even though the module works non-blocking regarding to database operations, a huge
    sample space (number of rows/readings) could block the browser session respectively
    FHEMWEB. <br>
    If you are unsure about the result of the statement, you should preventively add a limit to
    the statement. <br><br>
    </li>
    <br>

    <a id="DbRep-set-sqlCmdHistory"></a>
    <li><b> sqlCmdHistory </b> <br><br>

    If activated with the attribute <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>,
    a stored SQL statement can be selected from a list and executed. <br>
    The SQL cache is automatically saved when FHEM is closed and restored when the system is started. <br>
    The following entries execute special functions: <br>
    <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>___purge_sqlhistory___</b>   </td><td>: deletes the history cache                                                         </td></tr>
       <tr><td> <b>___list_sqlhistory___ </b>   </td><td>: shows the SQL statements currently in the cache, including their cache key (ckey) </td></tr>
       <tr><td> <b>___save_sqlhistory___</b>    </td><td>: backs up the history cache manually                                               </td></tr>
       <tr><td> <b>___restore_sqlhistory___</b> </td><td>: restores the last backup of the history cache                                     </td></tr>
    </table>
    </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>,
      <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-sqlSpecial"></a>
    <li><b> sqlSpecial </b> <br><br>

    This function provides a drop-down list with a selection of prepared reportings. <br>
    The statements result is depicted in reading "SqlResult".
    The result can be formatted by attribute <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>
    a well as the used field separator by attribute <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>.
    <br><br>

    <ul>
    <table>
    <colgroup> <col width=33%> <col width=67%> </colgroup>
       <tr><td> <b>50mostFreqLogsLast2days </b>       </td><td> reports the 50 most occuring log entries of the last 2 days                         </td></tr>
       <tr><td> <b>allDevCount </b>                   </td><td> all devices occuring in database and their quantity                                 </td></tr>
       <tr><td> <b>allDevReadCount </b>               </td><td> all device/reading combinations occuring in database and their quantity             </td></tr>
       <tr><td> <b>50DevReadCount </b>                </td><td> the 50 most frequently included device/reading combinations in the database         </td></tr>
       <tr><td> <b>recentReadingsOfDevice </b>        </td><td> determines the newest records of a device available in the database. The            </td></tr>
       <tr><td>                                       </td><td> device must be defined in attribute <a href="#DbRep-attr-device">device</a>         </td></tr>
       <tr><td> <b>readingsDifferenceByTimeDelta </b> </td><td> determines the value difference of successive data records of a reading. The        </td></tr>
       <tr><td>                                       </td><td> device and reading must be defined in the attribute <a href="#DbRep-attr-device">device</a> or <a href="#DbRep-attr-reading">reading</a>.  </td></tr>
       <tr><td>                                       </td><td> The time limits of the evaluation are defined by the time.*-attributes.                                                                    </td></tr>
    </table>
    </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    <br>

    </li>
    <br>


    <li><b> sumValue [display | writeToDB | writeToDBSingle | writeToDBInTime] </b> <br><br>

    Calculates the total values of the database field "VALUE" in the time limits
    of the possible time.*-attributes. <br><br>

    The reading to be evaluated must be specified in the attribute <a href="#DbRep-attr-reading">reading</a>.
    This function is useful if continuous value differences of a reading are written
    into the database.  <br><br>

    If none or the option <b>display</b> is specified, the results are only displayed. With
    the options <b>writeToDB</b>, <b>writeToDBSingle</b> or <b>writeToDBInTime</b> the calculation results are written
    with a new reading name into the database. <br><br>

    <ul>
      <table>
      <colgroup> <col width=10%> <col width=90%> </colgroup>
         <tr><td> <b>writeToDB</b>         </td><td>: writes one value each with the time stamps XX:XX:01 and XX:XX:59 within the respective aggregation period </td></tr>
         <tr><td> <b>writeToDBSingle</b>   </td><td>: writes only one value with the time stamp XX:XX:59 at the end of an aggregation period </td></tr>
         <tr><td> <b>writeToDBInTime</b>   </td><td>: writes a value at the beginning and end of the time limits of an aggregation period </td></tr>
      </table>
    </ul>
    <br>

    The new reading name is formed from a prefix and the original reading name,
    where the original reading name can be replaced by the attribute "readingNameMap".
    The prefix consists of the educational function and the aggregation. <br>
    The timestamp of the new reading in the database is determined by the set aggregation period
    if no clear time of the result can be determined.
    The field "EVENT" is filled with "calculated".  <br><br>

    <ul>
      <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
      sum_day_totalpac <br>
      # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>
    </ul>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-attributes
    </ul>
    <br>
    <br>

    </li>
    <br>

    <li><b> syncStandby &lt;DbLog-Device Standby&gt; </b> <br><br>

    Datasets of the connected database (source) are transmitted into another database
    (Standby-database). <br>
    Here the "&lt;DbLog-Device Standby&gt;" is the DbLog-Device what is connected to the
    Standby-database. <br><br>
    All the datasets which are determined by <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a> attribute
    or respectively the attributes "device", "reading" are transmitted. <br>
    The datasets are transmitted in time slices accordingly to the adjusted aggregation.
    If the attribute "aggregation" has value "no" or "month", the datasets are transmitted
    automatically in daily time slices into standby-database.
    Source- and Standby-database can be of different types.
    <br><br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-attributes
    </ul>
    <br>
    <br>

    </li>
    <br>

    <a id="DbRep-set-tableCurrentFillup"></a>
    <li><b> tableCurrentFillup </b> <br><br>

    The current-table will be filled u with an extract of the history-table. <br>
    The <a href="#DbRep-attr">attributes</a> for limiting time and device, reading are considered. <br>
    Thereby the content of the extract can be affected. <br>
    In the associated DbLog-device the attribute "DbLogType" should be set to "SampleFill/History".
    <br>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-attributes
    </ul>
    <br>
    <br>

    </li>

    <a id="DbRep-set-tableCurrentPurge"></a>
    <li><b> tableCurrentPurge </b> <br><br>

    Deletes the content of current-table. <br>
    There are no limits, e.g. by attributes timestamp_begin, timestamp_end, device or reading
    considered.
    <br>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    <br>

    </li>

    <a id="DbRep-set-vacuum"></a>
    <li><b> vacuum </b> <br><br>

    Optimizes the tables in the connected database (SQLite, PostgreSQL). <br>
    Especially for SQLite databases it is strongly recommended to temporarily close the connection of the relevant DbLog
    device to the database (see DbLog reopen command).
    <br>
    <br>

    Relevant attributes are: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Note:</b> <br>
    When the vacuum command is executed, the PRAGMA <b>auto_vacuum = FULL</b> is automatically applied to SQLite databases. <br>
    The vacuum command requires additional temporary memory. If there is not enough space in the default TMPDIR directory,
    SQLite can be assigned a sufficiently large directory by setting the environment variable <b>SQLITE_TMPDIR</b>. <br>
    (see also: <a href="https://www.sqlite.org/tempfiles.html">www.sqlite.org/tempfiles</a>)
    </li>
    <br>
    <br>

    <br>
    </ul>
    </ul>

</ul>

<a id="DbRep-get"></a>
<b>Get </b>
<ul>

 The get-commands of DbRep provide to retrieve some metadata of the used database instance.
 Those are for example adjusted server parameter, server variables, datadasestatus- and table informations. THe available get-functions depending of
 the used database type. So for SQLite curently only "get svrinfo" is usable. The functions nativ are delivering a lot of outpit values.
 They can be limited by function specific <a href="#DbRep-attr">attributes</a>.
 The filter has to be setup by a comma separated list.
 SQL-Wildcard (%) can be used to setup the list arguments.
 <br><br>

 <b>Note: </b> <br>
 After executing a get-funktion in detail view please make a browser refresh to see the results !
 <br><br>

 <ul><ul>
    <a id="DbRep-get-blockinginfo"></a>
    <li><b> blockinginfo </b> - list the current system wide running background processes (BlockingCalls) together with their informations.
                                If character string is too long (e.g. arguments) it is reported shortened.
                                </li>
                                <br><br>

    <a id="DbRep-get-dbstatus"></a>
    <li><b> dbstatus </b> -  lists global information about MySQL server status (e.g. informations related to cache, threads, bufferpools, etc. ).
                             Initially all available informations are reported. Using the attribute <a href="#DbRep-attr-showStatus">showStatus</a> the quantity of
                             results can be limited to show only the desired values. Further detailed informations of items meaning are
                             explained <a href="http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html">here</a>.  <br><br>

                                 <ul>
                                   <b>Example</b>  <br>
                                   attr &lt;name&gt; showStatus %uptime%,%qcache%    <br>
                                   get &lt;name&gt; dbstatus  <br>
                                   # Only readings containing "uptime" and "qcache" in name will be created
                                 </ul>
                                 </li>
                                 <br><br>

    <a id="DbRep-get-dbvars"></a>
    <li><b> dbvars </b> -  lists global informations about MySQL system variables. Included are e.g. readings related to InnoDB-Home, datafile path,
                           memory- or cache-parameter and so on. The Output reports initially all available informations. Using the
                           attribute <a href="#DbRep-attr-showVariables">showVariables</a> the quantity of results can be limited to show only the desired values.
                           Further detailed informations of items meaning are explained
                           <a href="http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html">here</a>. <br><br>

                                 <ul>
                                   <b>Example</b>  <br>
                                   attr &lt;name&gt; showVariables %version%,%query_cache%    <br>
                                   get &lt;name&gt; dbvars  <br>
                                   # Only readings containing "version" and "query_cache" in name will be created
                                 </ul>
                                 </li>
                                 <br><br>

    <a id="DbRep-get-initData"></a>
    <li><b> initData </b> - Determines some database properties relevant for the module function.
                            The command is executed implicitly at the first database connection.
                            </li>
                            <br><br>

    <a id="DbRep-get-minTimestamp"></a>
    <li><b> minTimestamp </b> - Identifies the oldest timestamp in the database (will be executed implicitely at FHEM start).
                                The timestamp is used as begin of data selection if no time attribut is set to determine the
                                start date.
                                </li>
                                <br><br>

    <a id="DbRep-get-procinfo"></a>
    <li><b> procinfo </b> - Reports the existing database processes in a summary table (only MySQL). <br>
                            Typically only the own processes of the connection user (set in DbLog configuration file) will be
                            reported. If all precesses have to be reported, the global "PROCESS" right has to be granted to the
                            user. <br>
                            As of MariaDB 5.3 for particular SQL-Statements a progress reporting will be provided
                            (table row "PROGRESS"). So you can track, for instance, the degree of processing during an index
                            creation. <br>
                            Further informations can be found
                            <a href="https://mariadb.com/kb/en/mariadb/show-processlist/">here</a>. <br>
                            </li>
                            <br><br>

    <a id="DbRep-get-sqlCmdBlocking"></a>
    <li><b> sqlCmdBlocking &lt;SQL-statement&gt;</b> <br><br>
    Executes the specified SQL statement <b>blocking</b> with a default timeout of 10 seconds.
    The timeout can be set with the attribute <a href="#DbRep-attr-timeout">timeout</a>.
    <br><br>

    <ul>
      <b>Examples:</b>  <br>
      { fhem("get &lt;name&gt; sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device") } <br>
      { CommandGet(undef,"Rep.LogDB1 sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device") } <br>
      get &lt;name&gt; sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device  <br>
    </ul>
    </li>
    <br>

    Because of its mode of operation this function is particular convenient for user own perl scripts.  <br>
    The input accepts multi line commands and delivers multi line results as well.
    This command also accept the setting of SQL session variables like "SET @open:=NULL,
    @closed:=NULL;" or PRAGMA for SQLite. <br>
    If several fields are selected and passed back, the fieds are separated by the separator defined
    by attribute <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a> (default "|"). Several result lines
    are separated by newline ("\n"). <br>
    This function only set/update status readings, the userExitFn function isn't called.
    <br><br>

    If you create a little routine in 99_myUtils, for example:
    <br>

    <pre>
sub dbval {
  my $name = shift;
  my $cmd) = shift;
  my $ret = CommandGet(undef,"$name sqlCmdBlocking $cmd");
  return $ret;
}
    </pre>

    it can be accessed with e.g. those calls:
    <br><br>

    <ul>
       <b>Examples:</b>  <br>
       { dbval("&lt;name&gt;","select count(*) from history") } <br>
       $ret = dbval("&lt;name&gt;","select count(*) from history"); <br>
    </ul>

    <br><br>

    <a id="DbRep-get-storedCredentials"></a>
    <li><b> storedCredentials </b> - Reports the users / passwords stored for database access by the device. <br>
                                   (only valid if database type is MYSQL)
                                   </li>
                                   <br><br>

    <a id="DbRep-get-svrinfo"></a>
    <li><b> svrinfo </b> -  Common database server informations, e.g. DBMS-version, server address and port and so on. The quantity of elements to get depends
                            on the database type. Using the attribute <a href="#DbRep-attr-showSvrInfo">showSvrInfo</a> the quantity of results can be limited to show only
                            the desired values. Further detailed informations of items meaning are explained
                            <a href="https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx">here</a>. <br><br>

                                 <ul>
                                   <b>Example</b>  <br>
                                   attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>
                                   get &lt;name&gt; svrinfo  <br>
                                   # Only readings containing "SQL_CATALOG_TERM" and "NAME" in name will be created
                                 </ul>
                                 </li>
                                 <br><br>

    <a id="DbRep-get-tableinfo"></a>
    <li><b> tableinfo </b> -  Access detailed informations about tables in MySQL database which is connected by the DbRep-device.
                              All available tables in the connected database will be selected by default.
                              Using the attribute <a href="#DbRep-attr-showTableInfo">showTableInfo</a> the results can be limited to tables you want to show.
                              Further detailed informations of items meaning are explained
                              <a href="http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html">here</a>.  <br><br>

                                 <ul>
                                   <b>Example</b>  <br>
                                   attr &lt;name&gt; showTableInfo current,history   <br>
                                   get &lt;name&gt; tableinfo  <br>
                                   # Only informations related to tables "current" and "history" are going to be created
                                 </ul>
                                 </li>
                                 <br><br>

    <a id="DbRep-get-versionNotes"></a>
    <li><b> versionNotes [hints | rel | &lt;key&gt;] </b> -
                              Shows realease informations and/or hints about the module.

                              <br><br>

                              <ul>
                               <table>
                               <colgroup> <col width=5%> <col width=95%> </colgroup>
                                   <tr><td> rel          </td><td>: shows only release information                   </td></tr>
                                   <tr><td> hints        </td><td>: shows only hints                                 </td></tr>
                                   <tr><td> &lt;key&gt;  </td><td>: the note with the specified number is displayed  </td></tr>
                               </table>
                              </ul>

                              </li>

                              <br>

                              It contains only main release informations for module users. <br>
                              If no options are specified, both release informations and hints will be shown. "rel" shows
                              only release informations and "hints" shows only hints. By the &lt;key&gt;-specification only
                              the hint with the specified number is shown.
                              <br>

  </ul></ul>

</ul>


<a id="DbRep-attr"></a>
<b>Attributes</b>

<br>
<ul>
  Using the module specific attributes you are able to define the scope of evaluation and the aggregation. <br>
  The listed attrbutes are not completely relevant for every function of the module. The help of set/get-commands
  contain explicitly which attributes are relevant for the specific command. <br><br>

  <b>Note for SQL-Wildcard Usage:</b> <br>
  Within the attribute values of "device" and "reading" you may use SQL-Wildcard "%", Character "_" is not supported as a wildcard.
  The character "%" stands for any characters.  <br>
  This rule is valid to all functions <b>except</b> "insert", "importFromFile" and "deviceRename". <br>
  The function "insert" doesn't allow setting the mentioned attributes containing the wildcard "%". <br>
  In readings the wildcard character "%" will be replaced by "/" to meet the rules of allowed characters in readings.
  <br><br>

  <ul><ul>
  <a id="DbRep-attr-aggregation"></a>
  <li><b>aggregation </b> <br><br>
  
  Creation of the function results in time slices within the selection period. 
  <br><br>
  
  <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> no      </td><td>- No aggregation (default)                                  </td></tr>
        <tr><td> minute  </td><td>- the function results are summarized per minute            </td></tr>
        <tr><td> hour    </td><td>- the function results are summarized per hour              </td></tr>
        <tr><td> day     </td><td>- the function results are summarized per calendar day      </td></tr>
        <tr><td> week    </td><td>- the function results are summarized per calendar week     </td></tr>
        <tr><td> month   </td><td>- the function results are summarized per calendar month    </td></tr>
        <tr><td> year    </td><td>- the functional results are summarized per calendar year   </td></tr>
    </table>
  </ul>
  </li> 
  <br>
  
  <a id="DbRep-attr-allowDeletion"></a>
  <li><b>allowDeletion </b> <br><br>
  
  Enables the delete function of the module.
  </li> 
  <br>

  <a id="DbRep-attr-autoForward"></a>
  <li><b>autoForward </b> <br><br>
  If activated, the result threads of a function are transferred to one or more devices. <br>
  The definition takes the form: <br>

  <pre>
  {
   "&lt;source-reading&gt;" => "&lt;dest.device&gt; [=> &lt;dest.-reading&gt;]",
   "&lt;source-reading&gt;" => "&lt;dest.device&gt; [=> &lt;dest.-reading&gt;]",
   ...
  }
  </pre>

  Wildcards (.*) are permitted in the specification <b>&lt;source-reading&gt;</b>. <br><br>

  <b>Example:</b>
  <pre>
  {
    ".*"        => "Dum.Rep.All",
    ".*AVGAM.*" => "Dum.Rep     => average",
    ".*SUM.*"   => "Dum.Rep.Sum => summary",
  }
  # All readings are transferred to device "Dum.Rep.All", reading name remains in the target
  # readings with "AVGAM" in the name are transferred to the "Dum.Rep" device in the reading "average"
  # readings with "SUM" in the name are transferred to the device "Dum.Rep.Sum" in the reading "summary"
  </pre>
  </li> 
  <br>

  <a id="DbRep-attr-averageCalcForm"></a>
  <li><b>averageCalcForm </b> <br><br>

  Defines the calculation variant for determining the average value with "averageValue". <br><br>

  Currently the following variants are implemented: <br><br>

  <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td><b>avgArithmeticMean:</b>       </td><td>The arithmetic average is calculated. (default)                                         </td></tr>
       <tr><td>                                </td><td>                                                                                        </td></tr>
       <tr><td><b>avgDailyMeanGWS:</b>         </td><td>Calculates the daily medium temperature according the                                   </td></tr>
       <tr><td>                                </td><td>specifications of german weather service. (see also "get &lt;name&gt; versionNotes 2")  </td></tr>
       <tr><td>                                </td><td>This variant uses aggregation "day" automatically.                                      </td></tr>
       <tr><td>                                </td><td>                                                                                        </td></tr>
       <tr><td> <b>avgDailyMeanGWSwithGTS:</b> </td><td>Same as "avgDailyMeanGWS" and additionally calculates the grassland temperature sum.    </td></tr>
       <tr><td>                                </td><td>If the value 200 is reached, the reading "reachedGTSthreshold" is created with the      </td></tr>
       <tr><td>                                </td><td>date of the first time this threshold value is reached.                                 </td></tr>                                        <tr><td>                                </td><td><b>Note:</b> the attribute timestamp_begin must be set to the beginning of a year !    </td></tr>
       <tr><td>                                </td><td><b>Note:</b> The attribute timestamp_begin must be set to the beginning of a year!      </td></tr>
       <tr><td>                                </td><td>(see also "get &lt;name&gt; versionNotes 5")                                            </td></tr>
       <tr><td>                                </td><td>                                                                                        </td></tr>
       <tr><td><b>avgTimeWeightMean:</b>       </td><td>Calculates the time-weighted average.                                                   </td></tr>
       <tr><td>                                </td><td><b>Note:</b> There must be at least two data points per aggregation period.             </td></tr>
    </table>
 </ul>
 </li>
 <br>

  <a id="DbRep-attr-countEntriesDetail"></a>
  <li><b>countEntriesDetail </b> <br><br>
  
  If set, the function countEntries creates a detailed report of counted datasets of
  every reading. By default only the summary of counted datasets is reported.
  </li> 
  <br>

  <a id="DbRep-attr-device"></a>
  <li><b>device </b>          - Selection of particular or several devices. <br>
                                You can specify a list of devices separated by "," or use device specifications (devspec). <br>
                                In that case the device names are derived from the device specification and the existing
                                devices in FHEM before carry out the SQL selection. <br>
                                If the the device, list or device specification is prepended by "EXCLUDE=",
                                the devices are excluded from database selection. <br>
                                The database selection is executed as a logical AND operation of "device" and the attribute
                                 <a href="#DbRep-attr-reading">reading</a>.
                                <br><br>

                                <ul>
                                <b>Examples:</b> <br>
                                <code>attr &lt;name&gt; device TYPE=DbRep </code> <br>
                                <code>attr &lt;name&gt; device MySTP_5000 </code> <br>
                                <code>attr &lt;name&gt; device SMA.*,MySTP.* </code> <br>
                                <code>attr &lt;name&gt; device SMA_Energymeter,MySTP_5000 </code> <br>
                                <code>attr &lt;name&gt; device %5000 </code> <br>
                                <code>attr &lt;name&gt; device TYPE=SSCam EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device TYPE=SSCam,TYPE=ESPEasy EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device EXCLUDE=TYPE=SSCam </code> <br>
                                </ul>
                                <br>

                                If you need more information about device specifications, execute
                                "get &lt;name&gt; versionNotes 3".
                                <br><br>
                                </li>

  <a id="DbRep-attr-diffAccept"></a>
  <li><b>diffAccept </b>      - valid for function diffValue. diffAccept determines the threshold,  up to that a calaculated
                                difference between two straight sequently datasets should be commenly accepted
                                (default = 20). <br>
                                Hence faulty DB entries with a disproportional high difference value will be eliminated and
                                don't tamper the result.
                                If a threshold overrun happens, the reading "diff_overrun_limit_&lt;diffLimit&gt;" will be
                                generated (&lt;diffLimit&gt; will be substituted with the present prest attribute value). <br>
                                The reading contains a list of relevant pair of values. Using verbose=3 this list will also
                                be reported in the FHEM logfile.
                                <br><br>

                                <ul>
                                Example report in logfile if threshold of diffAccept=10 overruns: <br><br>

                                DbRep Rep.STP5000.etotal -> data ignored while calc diffValue due to threshold overrun (diffAccept = 10): <br>
                                2016-04-09 08:50:50 0.0340 -> 2016-04-09 12:42:01 13.3440 <br><br>

                                # The first dataset with a value of 0.0340 is untypical low compared to the next value of 13.3440 and results a untypical
                                  high difference value. <br>
                                # Now you have to decide if the (second) dataset should be deleted, ignored of the attribute diffAccept should be adjusted.
                                </ul><br>
                                </li>

  <a id="DbRep-attr-dumpComment"></a>
  <li><b>dumpComment </b> <br>
  User-specific comment which is entered in the header of the file generated by "dumpMyQL clientSide".
  </li>
  <br>

  <a id="DbRep-attr-dumpCompress"></a>
  <li><b>dumpCompress </b> <br>
  If set, the file created by "dumpMySQL" or "dumpSQLite" is then compressed and the uncompressed source file is deleted.
  </li>
  <br>

  <a id="DbRep-attr-dumpDirLocal"></a>
  <li><b>dumpDirLocal </b>  <br><br>
  <ul>
    Destination directory for creating dumps with "dumpMySQL clientSide" or "dumpSQLite".  <br>

    Setting this attribute activates the internal version management.
    In this directory backup files are searched and deleted if the found number exceeds the attribute value
    "dumpFilesKeep".
    The attribute is also used to make a locally mounted directory "dumpDirRemote" (for dumpMySQL serverSide)
    known to DbRep. <br>

    (default: "{global}{modpath}/log/")
    <br><br>

    <b>Example: </b> <br>
    attr &lt;Name&gt; dumpDirLocal /sds1/backup/dumps_FHEM/

  <br>
  <br>
  </ul>
  </li>

  <a id="DbRep-attr-dumpDirRemote"></a>
  <li><b>dumpDirRemote </b>   - Target directory of database dumps by command "dumpMySQL serverSide"
                                (default: the Home-directory of MySQL-Server on the MySQL-Host). </li> <br>

  <a id="DbRep-attr-dumpMemlimit"></a>
  <li><b>dumpMemlimit </b>    - tolerable memory consumption for the SQL-script during generation period (default: 100000 characters).
                                Please adjust this parameter if you may notice memory bottlenecks and performance problems based
                                on it on your specific hardware. </li> <br>

  <a id="DbRep-attr-dumpSpeed"></a>
  <li><b>dumpSpeed </b>       - Number of Lines which will be selected in source database with one select by dump-command
                                "dumpMySQL ClientSide" (default: 10000).
                                This parameter impacts the run-time and consumption of resources directly.  </li> <br>

  <a id="DbRep-attr-dumpFilesKeep"></a>
  <li><b>dumpFilesKeep </b>   <br><br>
  <ul>
    The integrated version management leaves the specified number of backup files in the backup directory. <br>
    Version management must be enabled by setting the "dumpDirLocal" attribute. <br>
    If there are more (older) backup files, they will be deleted after a new backup has been successfully created.
    The global attribute "archivesort" is taken into account. <br>
    (default: 3)

  <br>
  <br>
  </ul>
  </li>

  <a id="DbRep-attr-executeAfterProc"></a>
  <li><b>executeAfterProc </b> <br><br>

  You can specify a FHEM command or Perl code that should be executed <b>after the command is processed</b>. <br>
  Perl code is to be enclosed in {...}. The variables $hash (hash of the DbRep device) and $name
  (name of the DbRep device) are available. <br><br>

  <ul>
    <b>Example:</b> <br><br>
    attr &lt;name&gt; executeAfterProc set og_gz_westfenster off; <br>
    attr &lt;name&gt; executeAfterProc {adump ($name)} <br><br>

    # "adump" is a function defined in 99_myUtils. <br>

<pre>
sub adump {
    my ($name) = @_;
    my $hash   = $defs{$name};
    # the own function, e.g.
    Log3($name, 3, "DbRep $name -> Dump is finished");

    return;
}
</pre>
  </ul>
  </li>

  <a id="DbRep-attr-executeBeforeProc"></a>
  <li><b>executeBeforeProc </b> <br><br>

  A FHEM command or Perl code can be specified which is to be executed <b>before the command is processed</b>. <br>
  Perl code is to be enclosed in {...}. The variables $hash (hash of the DbRep device) and $name
  (name of the DbRep device) are available. <br><br>

  <ul>
    <b>Example:</b> <br><br>
    attr &lt;name&gt; executeBeforeProc set og_gz_westfenster on; <br>
    attr &lt;name&gt; executeBeforeProc {bdump ($name)}           <br><br>

    # "bdump" is a function defined in 99_myUtils. <br>

<pre>
sub bdump {
    my ($name) = @_;
    my $hash   = $defs{$name};
    # the own function, e.g.
    Log3($name, 3, "DbRep $name -> Dump starts");

    return;
}
</pre>
   </ul>
   </li>


  <a id="DbRep-attr-expimpfile"></a>
  <li><b>expimpfile &lt;/path/file&gt; [MAXLINES=&lt;lines&gt;] </b>
                                - Path/filename for data export/import. <br><br>

                                The maximum number of datasets which are exported into one file can be specified
                                with the optional parameter "MAXLINES". In this case several files with extensions
                                "_part1", "_part2", "_part3" and so on are created. <br>
                                The filename may contain wildcards which are replaced by corresponding values
                                (see subsequent table).
                                Furthermore filename can contain %-wildcards of the POSIX strftime function of the underlying OS (see your
                                strftime manual).
                                <br><br>

                                <ul>
                                  <table>
                                  <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> %L    </td><td>: is replaced by the value of global logdir attribute </td></tr>
                                      <tr><td> %TSB  </td><td>: is replaced by the (calculated) value of the start timestamp of the data selection </td></tr>
                                      <tr><td>       </td><td>  </td></tr>
                                      <tr><td>       </td><td> <b>Common used POSIX-wildcards are:</b> </td></tr>
                                      <tr><td> %d    </td><td>: day of month (01..31) </td></tr>
                                      <tr><td> %m    </td><td>: month (01..12) </td></tr>
                                      <tr><td> %Y    </td><td>: year (1970...) </td></tr>
                                      <tr><td> %w    </td><td>: day of week (0..6);  0 represents Sunday </td></tr>
                                      <tr><td> %j    </td><td>: day of year (001..366) </td></tr>
                                      <tr><td> %U    </td><td>: week number of year with Sunday as first day of week (00..53) </td></tr>
                                      <tr><td> %W    </td><td>: week number of year with Monday as first day of week (00..53) </td></tr>
                                  </table>
                                </ul>
                                <br>

                                <ul>
                                <b>Examples:</b> <br>
                                <code>attr &lt;name&gt; expimpfile /sds1/backup/exptest_%TSB.csv     </code> <br>
                                <code>attr &lt;name&gt; expimpfile /sds1/backup/exptest_%Y-%m-%d.csv </code> <br>
                                </ul>
                                <br>

                                About POSIX wildcard usage please see also explanations in
                                <a href="https://fhem.de/commandref.html#FileLog">Filelog</a>. <br>
                                <br><br>
                                </li>

  <a id="DbRep-attr-fastStart"></a>
  <li><b>fastStart </b>       - Usually every DbRep device is making a short connect to its database when FHEM is started to
                                retrieve some important informations and the reading "state" switches to "connected" on success.
                                If this attrbute is set, the initial database connection is executed not till then the
                                DbRep device is processing its first command. <br>
                                While the reading "state" is remaining in state "initialized" after FHEM-start. <br>
                                (default: 1 for TYPE Client)
                                </li> <br>

  <a id="DbRep-attr-fetchMarkDuplicates"></a>
  <li><b>fetchMarkDuplicates </b>
                              - Highlighting of multiple occuring datasets in result of "fetchrows" command </li> <br>

  <a id="DbRep-attr-fetchRoute"></a>
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

  <a id="DbRep-attr-fetchValueFn"></a>
  <li><b>fetchValueFn </b>      - When fetching the database content, you are able to manipulate the value fetched from the
                                VALUE database field before create the appropriate reading. You have to insert a Perl
                                function which is enclosed in {} .<br>
                                The value of the database field VALUE is provided in variable $VALUE. <br><br>

                                <ul>
                                <b>Example:</b> <br>
                                attr &lt;name&gt; fetchValueFn { $VALUE =~ s/^.*Used:\s(.*)\sMB,.*/$1." MB"/e } <br>

                                # From a long line a specific pattern is extracted and will be displayed als VALUE instead
                                the whole line
                                </ul>
                                </li> <br><br>

  <a id="DbRep-attr-ftpUse"></a>
  <li><b>ftpUse </b>          - FTP Transfer after dump will be switched on (without SSL encoding). The created
                                database backup file will be transfered non-blocking to the FTP-Server (Attribut "ftpServer").
                                </li> <br>

  <a id="DbRep-attr-ftpUseSSL"></a>
  <li><b>ftpUseSSL </b>       - FTP Transfer with SSL encoding after dump. The created database backup file will be transfered
                                non-blocking to the FTP-Server (Attribut "ftpServer"). </li> <br>

 <a id="DbRep-attr-ftpUser"></a>
  <li><b>ftpUser </b>         - User for FTP-server login, default: "anonymous". </li> <br>

  <a id="DbRep-attr-ftpDebug"></a>
  <li><b>ftpDebug </b>        - debugging of FTP communication for diagnostics. </li> <br>

  <a id="DbRep-attr-ftpDir"></a>
  <li><b>ftpDir </b>          - directory on FTP-server in which the file will be send into (default: "/"). </li> <br>

  <a id="DbRep-attr-ftpDumpFilesKeep"></a>
  <li><b>ftpDumpFilesKeep </b> - leave the number of dump files in FTP-destination &lt;ftpDir&gt; (default: 3). Are there more
                                 (older) dump files present, these files are deleted after a new dump was transfered successfully. </li> <br>

  <a id="DbRep-attr-ftpPassive"></a>
  <li><b>ftpPassive </b>      - set if passive FTP is to be used </li> <br>

  <a id="DbRep-attr-ftpPort"></a>
  <li><b>ftpPort </b>         - FTP-Port, default: 21 </li> <br>

  <a id="DbRep-attr-ftpPwd"></a>
  <li><b>ftpPwd </b>          - password of FTP-User, is not set by default </li> <br>

  <a id="DbRep-attr-ftpServer"></a>
  <li><b>ftpServer </b>       - name or IP-address of FTP-server. <b>absolutely essential !</b> </li> <br>

  <a id="DbRep-attr-ftpTimeout"></a>
  <li><b>ftpTimeout </b>      - timeout of FTP-connection in seconds (default: 30). </li> <br>

  <a id="DbRep-attr-limit"></a>
  <li><b>limit </b>           - limits the number of selected datasets by the "fetchrows", or the shown datasets of "delSeqDoublets adviceDelete",
                                "delSeqDoublets adviceRemain" commands (default: 1000).
                                This limitation should prevent the browser session from overload and
                                avoids FHEMWEB from blocking. Please change the attribut according your requirements or change the
                                selection criteria (decrease evaluation period). </li> <br>

  <a id="DbRep-attr-numDecimalPlaces"></a>
  <li><b>numDecimalPlaces </b>  - Sets the number of decimal places for readings with numeric results. <br>
                                  Excludes results from user-specific queries (sqlCmd). <br>
                                  (default: 4)
                                  </li> <br>

  <a id="DbRep-attr-optimizeTablesBeforeDump"></a>
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

  <a id="DbRep-attr-reading"></a>
  <li><b>reading </b>         - Selection of particular or several readings.
                                More than one reading can be specified by a comma separated list. <br>
                                SQL wildcard (%) can be used. <br>
                                If the reading or the reading list is prepended by "EXCLUDE=", those readings are not
                                included. <br>
                                The database selection is executed as a logical AND operation of "reading" and the attribute
                                <a href="#DbRep-attr-device">device</a>.
                                <br><br>

                                <ul>
                                <b>Examples:</b> <br>
                                <code>attr &lt;name&gt; reading etotal</code> <br>
                                <code>attr &lt;name&gt; reading et%</code> <br>
                                <code>attr &lt;name&gt; reading etotal,etoday</code> <br>
                                <code>attr &lt;name&gt; reading eto%,Einspeisung EXCLUDE=etoday  </code> <br>
                                <code>attr &lt;name&gt; reading etotal,etoday,Ein% EXCLUDE=%Wirkleistung  </code> <br>
                                </ul>
                                <br><br>
                                </li>

  <a id="DbRep-attr-readingNameMap"></a>
  <li><b>readingNameMap </b> <br><br>
  
  The part between the first and last double underscore ('__') of the created reading name is replaced with the 
  specified string.   
  </li> 
  <br>

  <a id="DbRep-attr-role"></a>
  <li><b>role </b> <br><br>
  
  The role of the DbRep-device. Standard role is "Client". <br>
  The role "Agent" is described in section <a href="#DbRep-attr-autorename">DbRep-Agent</a>.
  </li> 
  <br>

  <a id="DbRep-attr-readingPreventFromDel"></a>
  <li><b>readingPreventFromDel </b> <br><br>
  
  Comma separated list of readings which are should prevent from deletion when a new operation starts. <br>
  The readings can be specified as a regular expression. <br>
  (default: state)
  <br><br>
  
  <ul>
    <b>Example:</b> <br>
    attr &lt;name&gt; readingPreventFromDel .*Count.*,.*Summary1.*,.*Summary2.*
  </ul>
  </li> 
  <br>

  <a id="DbRep-attr-seqDoubletsVariance"></a>
  <li><b>seqDoubletsVariance  &lt;positive variance [negative variance] [EDGE=negative|positive]&gt; </b> <br><br>

  Accepted variance for the command "set &lt;name&gt; delSeqDoublets". <br>
  The value of this attribute describes the variance up to consecutive numeric values (VALUE) of
  datasets are handled as identical. If only one numeric value is declared, it is used as
  postive as well as negative variance and both form the "deletion corridor".
  Optional a second numeric value for a negative variance, separated by blank,can be
  declared.
  Always absolute, i.e. positive numeric values, have to be declared. <br>
  If the supplement "EDGE=negative" is declared, values at a negative edge (e.g. when
  value is changed from  4.0 -&gt; 1.0) are not deleted although they are in the "deletion corridor".
  Equivalent is valid with "EDGE=positive" for the positive edge (e.g. the change
  from 1.2 -&gt; 2.8).
  <br><br>

  <ul>
  <b>Examples:</b> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 0.0014  </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 1.45    </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 3.0 2.0 </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 1.5 EDGE=negative </code> <br>
  </ul>
  <br>
  <br>
  </li>

  <a id="DbRep-attr-showproctime"></a>
  <li><b>showproctime </b>    - if set, the reading "sql_processing_time" shows the required execution time (in seconds)
                                for the sql-requests. This is not calculated for a single sql-statement, but the summary
                                of all sql-statements necessara for within an executed DbRep-function in background. </li> <br>

  <a id="DbRep-attr-showStatus"></a>
  <li><b>showStatus </b>      - limits the sample space of command "get &lt;name&gt; dbstatus". SQL-Wildcard (%) can be used.
                                <br><br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showStatus %uptime%,%qcache%  <br>
                                # Only readings with containing "uptime" and "qcache" in name will be shown <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showVariables"></a>
  <li><b>showVariables </b>   - limits the sample space of command "get &lt;name&gt; dbvars". SQL-Wildcard (%) can be used.
                                <br><br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showVariables %version%,%query_cache% <br>
                                # Only readings with containing "version" and "query_cache" in name will be shown <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showSvrInfo"></a>
  <li><b>showSvrInfo </b>     - limits the sample space of command "get &lt;name&gt; svrinfo". SQL-Wildcard (%) can be used.
                                <br><br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                                # Only readings with containing "SQL_CATALOG_TERM" and "NAME" in name will be shown <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showTableInfo"></a>
  <li><b>showTableInfo </b> <br><br>

  Limits the result set of the command "get &lt;name&gt; tableinfo". SQL wildcard (%) can be used.
  <br><br>

  <ul>
    <b>Example: </b> <br>
    attr &lt;name&gt; showTableInfo current,history  <br>
    # Only information from the "current" and "history" tables is displayed. <br>
  </ul>
  <br>
  </li>

  <a id="DbRep-attr-sqlCmdHistoryLength"></a>
  <li><b>sqlCmdHistoryLength </b> <br><br>

    Activates the command history of "sqlCmd" with a value > 0 and defines the number of
    SQL statements to be stored. <br>
    (default: 0)

  </li>
  <br>

  <a id="DbRep-attr-sqlCmdVars"></a>
  <li><b>sqlCmdVars </b> <br><br>

    Sets the specified SQL session variable(s) or PRAGMA before each SQL statement executed with sqlCmd.
    SQL statement.  <br><br>

    <ul>
      <b>Example:</b> <br>
      attr &lt;name&gt; sqlCmdVars SET @open:=NULL, @closed:=NULL; <br>
      attr &lt;name&gt; sqlCmdVars PRAGMA temp_store=MEMORY;PRAGMA synchronous=FULL;PRAGMA journal_mode=WAL; <br>
    </ul>
  <br>
  </li>
  <br>

  <a id="DbRep-attr-sqlFormatService"></a>
  <li><b>sqlFormatService </b> <br><br>

    Automated formatting of SQL statements can be activated via an online service. <br>
    This option is especially useful for complex SQL statements of the setters sqlCmd, sqlCmdHistory, and sqlSpecial
    to improve structuring and readability. <br>
    An internet connection is required and the global attribute <b>dnsServer</b> should be set. <br>
    (default: none)

  </li>
  <br>

  <a id="DbRep-attr-sqlResultFieldSep"></a>
  <li><b>sqlResultFieldSep </b> <br><br>

    Sets the used field separator in the result of the command "set ... sqlCmd". <br>
    (default: "|")

  </li>
  <br>

  <a id="DbRep-attr-sqlResultFormat"></a>
  <li><b>sqlResultFormat </b> - determines the formatting of the "set &lt;name&gt; sqlCmd" command result.
                                Possible options are:
                                <br><br>

                                <ul>
                                <b>separated </b> - every line of the result will be generated sequentially in a single
                                                    reading. (default) <br><br>
                                <b>mline </b>     - the result will be generated as multiline in
                                                    Reading SqlResult.
                                                    <br><br>
                                <b>sline </b>     - the result will be generated as singleline in
                                                    Reading SqlResult.
                                                    Datasets are separated by "]|[". <br><br>
                                <b>table </b>     - the result will be generated as an table in
                                                    Reading SqlResult. <br><br>
                                <b>json </b>      - creates the Reading SqlResult as a JSON
                                                    coded hash.
                                                    Every hash-element consists of the serial number of the dataset (key)
                                                    and its value.
                                <br><br>


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
        </li>

  <a id="DbRep-attr-timeYearPeriod"></a>
  <li><b>timeYearPeriod &lt;Month&gt;-&lt;Day&gt; &lt;Month&gt;-&lt;Day&gt;</b> <br>
  An annual period is determined for the database selection.
  The annual period is calculated dynamically at execution time.
  It is not possible to provide information during the year. <br>
  This attribute is primarily intended to create evaluations synchronized with a billing period, e.g. that of an energy or
  gas supplier.
  <br><br>

  <ul>
    <b>Example:</b> <br><br>
    attr &lt;name&gt; timeYearPeriod 06-25 06-24 <br><br>

    Evaluates the database in the time limits June 25 AAAA to June 24 BBBB. <br>
    The year AAAA or BBBB is calculated depending on the current date. <br>
    If the current date is >= June 25 and <= December 31, then AAAA = current year and BBBB = current year+1 <br>
    If the current date is >= January 01 and <= June 24, then AAAA = current year-1 and BBBB = current year
  </ul>
  <br><br>
  </li>

  <a id="DbRep-attr-timestamp_begin"></a>
  <li><b>timestamp_begin </b> - begin of data selection  <br>

  The format of timestamp is as used with DbLog "YYYY-MM-DD HH:MM:SS". For the attributes "timestamp_begin", "timestamp_end"
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
                              <b>next_day_begin</b>         : matches "&lt;next day&gt; 00:00:00"                   <br>
                              <b>next_day_end</b>           : matches "&lt;next day&gt; 23:59:59"                   <br>
                              <b>current_hour_begin</b>     : matches "&lt;current hour&gt;:00:00"                  <br>
                              <b>current_hour_end</b>       : matches "&lt;current hour&gt;:59:59"                  <br>
                              <b>previous_hour_begin</b>    : matches "&lt;previous hour&gt;:00:00"                 <br>
                              <b>previous_hour_end</b>      : matches "&lt;previous hour&gt;:59:59"                 <br>
                              </ul>
                              <br><br>
                              </li>

  <a id="DbRep-attr-timestamp_end"></a>
  <li><b>timestamp_end </b>   - end of data selection. If not set the current date/time combination will be used.  <br>

  The format of timestamp is as used with DbLog "YYYY-MM-DD HH:MM:SS". For the attributes "timestamp_begin", "timestamp_end"
  you can also use one of the following entries. The timestamp-attribute will be dynamically set to:
                              <br><br>

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
                              <b>next_day_begin</b>         : matches "&lt;next day&gt; 00:00:00"                   <br>
                              <b>next_day_end</b>           : matches "&lt;next day&gt; 23:59:59"                   <br>
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
  </li>

  <a id="DbRep-attr-timeDiffToNow"></a>
  <li><b>timeDiffToNow </b>   - the <b>begin time </b> of data selection will be set to the timestamp <b>"&lt;current time&gt; -
                                &lt;timeDiffToNow&gt;"</b> dynamically. The time period will be calculated dynamically at
                                execution time. Optional can with the additional entry "FullDay" the selection start time
                                and the selection end time be expanded to the begin / end of the involved days
                                (take only effect if adjusted time difference is >= 1 day).
                                <br><br>

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
                                <code>attr &lt;name&gt; timeDiffToNow y:1 h:2.5</code> <br>
                                # the start time is set to "current time - 1 year and 2,5 hours" <br>
                                <code>attr &lt;name&gt; timeDiffToNow y:1.5</code> <br>
                                # the start time is set to "current time - 1.5 years" <br>
                                <code>attr &lt;name&gt; timeDiffToNow d:8 FullDay </code> <br>
                                # the start time is set to "current time - 8 days", the selection time period is expanded to the begin / end of the involved days <br>
                                </ul>
                                <br>

                                If both attributes "timeDiffToNow" and "timeOlderThan" are set, the selection
                                period will be calculated between of these timestamps dynamically.
                                <br><br>
                                </li>

  <a id="DbRep-attr-timeOlderThan"></a>
  <li><b>timeOlderThan </b>   - the <b>end time</b> of data selection will be set to the timestamp <b>"&lt;aktuelle Zeit&gt; -
                                &lt;timeOlderThan&gt;"</b> dynamically. Always the datasets up to timestamp
                                "&lt;current time&gt; - &lt;timeOlderThan&gt;" will be considered. The time period will be calculated dynamically at
                                execution time. Optional can with the additional entry "FullDay" the selection start time
                                and the selection end time be expanded to the begin / end of the involved days
                                (take only effect if adjusted time difference is >= 1 day).
                                <br><br>

                                <ul>
                                <b>Examples for input format:</b> <br>
                                <code>attr &lt;name&gt; timeOlderThan 86400</code> <br>
                                # the selection end time is set to "current time - 86400 seconds" <br>
                                <code>attr &lt;name&gt; timeOlderThan d:2 h:3 m:2 s:10</code> <br>
                                # the selection end time is set to "current time - 2 days 3 hours 2 minutes 10 seconds" <br>
                                <code>attr &lt;name&gt; timeOlderThan m:600</code> <br>
                                # the selection end time is set to "current time - 600 minutes" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan h:2.5</code> <br>
                                # the selection end time is set to "current time - 2,5 hours" <br>
                                <code>attr &lt;name&gt; timeOlderThan y:1 h:2.5</code> <br>
                                # the selection end time is set to "current time - 1 year and 2,5 hours" <br>
                                <code>attr &lt;name&gt; timeOlderThan y:1.5</code> <br>
                                # the selection end time is set to "current time - 1.5 years" <br>
                                <code>attr &lt;name&gt; timeOlderThan d:8 FullDay </code> <br>
                                # the end time is set to "current time - 8 days", the selection time period is expanded to the begin / end of the involved days <br>

                                </ul>
                                <br>

                                If both attributes "timeDiffToNow" and "timeOlderThan" are set, the selection
                                period will be calculated between of these timestamps dynamically.
                                <br><br>
                                </li>

  <a id="DbRep-attr-timeout"></a>
  <li><b>timeout </b>         - set the timeout-value for Blocking-Call Routines in background in seconds (default 86400)  </li> <br>

  <a id="DbRep-attr-useAdminCredentials"></a>
  <li><b>useAdminCredentials </b>
                                - If set, a before with "set &lt;aame&gt; adminCredentials" saved privileged user is used
                                  for particular database operations. <br>
                                  (only valid if database type is MYSQL and DbRep-type "Client")
                                  </li> <br>

  <a id="DbRep-attr-userExitFn"></a>
  <li><b>userExitFn </b> - provides an interface for executing custom user code. <br>
                           Basically, the interface works <b>without</b> event generation or does not require an event to function.
                           The interface can be used with the following variants. <br><br>

                           <ul>

                           <b>1. call a subroutine, e.g. in 99_myUtils.pm </b> <br><br>.

                           The subroutine to be called is created in 99_myUtils.pm according to the following pattern: <br>

<pre>
sub UserFunction {
  my $name    = shift;         # the name of the DbRep device.
  my $reading = shift;         # the name of the reading to create
  my $value   = shift;         # the value of the reading
  my $hash    = $defs{$name};
  ...
  # e.g. log passed data
  Log3 $name, 1, "UserExitFn $name called - transfer parameters are Reading: $reading, Value: $value " ;
  ...
return;
}
</pre>

                               In the attribute the subroutine and optionally a Reading:Value regex
                               must be specified as an argument. Without this specification all Reading:Value combinations are
                               evaluated as "true" and passed to the subroutine (equivalent to .*:.*).
                               <br><br>

                               <ul>
                               <b>Example:</b> <br>
                               attr <device> userExitFn UserFunction Meter:Energy.* <br>
                               # "UserFunction" is the subroutine in 99_myUtils.pm.
                               </ul>
                               <br>

                               The regex is checked after the creation of each reading.
                               If the check is true, the specified function is called. <br><br>

                               <b>2. Direct input of custom code</b> <br><br>.

                               The custom code is enclosed in curly braces.
                               The code is called after the creation of each reading.
                               In the code, the following variables are available for evaluation: <br><br>

                               <ul>
                               <li>$NAME - the name of the DbRep device</li>
                               <li>$READING - the name of the reading created</li>
                               <li>$VALUE - the value of the reading </li>
                               </ul>

                               <br>

                               <ul>
                               <b>Example:</b> <br>
<pre>
{
  if ($READING =~ /PrEnergySumHwc1_0_value__DIFF/) {
    my $mpk  = AttrVal($NAME, 'multiplier', '0');
    my $tarf = AttrVal($NAME, 'Tariff', '0');                                      # cost €/kWh
    my $m3   = sprintf "%.3f", $VALUE/10000 * $mpk;                                # consumed m3
    my $kwh  = sprintf "%.3f", $m3 * AttrVal($NAME, 'Calorific_kWh/m3', '0');      # conversion m3 -> kWh
    my $cost = sprintf "%.2f", $kwh * $tarf;

    my $hash = $defs{$NAME};

    readingsBulkUpdate ($hash, 'gas_consumption_m3', $m3);
    readingsBulkUpdate ($hash, 'gas_consumption_kwh', $kwh);
    readingsBulkUpdate ($hash, 'gas_costs_euro', $cost);
  }
}
</pre>
                               # The readings gas_consumption_m3, gas_consumption_kwh and gas_costs_euro are calculated
                               And generated in the DbRep device.
                               </ul>

                               </ul>
                               </li>
                               <br>
                               <br>

  <a id="DbRep-attr-valueFilter"></a>
  <li><b>valueFilter </b>     - Regular expression (REGEXP) to filter datasets within particular functions. The REGEXP is
                                applied to a particular field or to the whole selected dataset (inclusive Device, Reading and
                                so on).
                                Please consider the explanations within the set-commands. Further information is available
                                with command "get &lt;name&gt; versionNotes 4". </li> <br>

</ul>
</ul></ul>

<a id="DbRep-readings"></a>
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
                                               by attribute <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a> </li> <br>

  <li><b>sqlCmd </b>                         - contains the last executed sqlCmd-command </li> <br>

  </ul></ul>
  <br><br>

</ul>

<a id="DbRep-autorename"></a>
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
        attr Rep.Agent stateFormat { ReadingsVal($name, 'state', '') eq 'running' ? 'renaming' : ReadingsVal($name, 'state', ''). ' &raquo;; ProcTime: '.ReadingsVal($name, 'sql_processing_time', '').' sec'}  <br>
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

<a id="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  Zweck des Moduls ist es, den Inhalt von DbLog-Datenbanken nach bestimmten Kriterien zu durchsuchen, zu managen, das Ergebnis hinsichtlich verschiedener
  Aggregationen auszuwerten und als Readings darzustellen. Die Abgrenzung der zu berücksichtigenden Datenbankinhalte erfolgt durch die Angabe von Device, Reading und
  die Zeitgrenzen für Auswertungsbeginn bzw. Auswertungsende.  <br><br>

  Fast alle Datenbankoperationen werden nichtblockierend ausgeführt. Auf Ausnahmen wird hingewiesen.
  Die Ausführungszeit der (SQL)-Hintergrundoperationen kann optional ebenfalls als Reading bereitgestellt
  werden (siehe <a href="#DbRep-attr">Attribute</a>). <br>
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
     <li> Ändern von Reading-Werten (VALUES) in der Datenbank (changeValue) </li>
     <li> automatisches Umbenennen von Device-Namen in Datenbanksätzen und DbRep-Definitionen nach FHEM "rename"
          Befehl (siehe <a href="#DbRep-autorename">DbRep-Agent</a>) </li>
     <li> Ausführen von beliebigen Benutzer spezifischen SQL-Kommandos (non-blocking) </li>
     <li> Ausführen von beliebigen Benutzer spezifischen SQL-Kommandos (blocking) zur Verwendung in eigenem Code (sqlCmdBlocking) </li>
     <li> Backups der FHEM-Datenbank im laufenden Betrieb erstellen (MySQL, SQLite) </li>
     <li> senden des Dumpfiles zu einem FTP-Server nach dem Backup incl. Versionsverwaltung </li>
     <li> Restore von SQLite- und MySQL-Dumps </li>
     <li> Optimierung der angeschlossenen Datenbank (optimizeTables, vacuum) </li>
     <li> Ausgabe der existierenden Datenbankprozesse (MySQL) </li>
     <li> leeren der current-Tabelle </li>
     <li> Auffüllen der current-Tabelle mit einem (einstellbaren) Extrakt der history-Tabelle</li>
     <li> Bereinigung sequentiell aufeinander folgender Datensätze mit unterschiedlichen Zeitstempel aber gleichen Werten (sequentielle Dublettenbereinigung) </li>
     <li> Reparatur einer korrupten SQLite Datenbank ("database disk image is malformed") </li>
     <li> Übertragung von Datensätzen aus der Quelldatenbank in eine andere (Standby) Datenbank (syncStandby) </li>
     <li> Reduktion der Anzahl von Datensätzen in der Datenbank (reduceLog) </li>
     <li> Löschen von doppelten Datensätzen (delDoublets) </li>
     <li> Löschen und (Wieder)anlegen der für DbLog und DbRep benötigten Indizes (index) </li>
     </ul></ul>
     <br>

  Zur Aktivierung der Funktion <b>Autorename</b> wird dem definierten DbRep-Device mit dem Attribut "role" die Rolle "Agent" zugewiesen. Die Standardrolle nach Definition
  ist "Client". Mehr ist dazu im Abschnitt <a href="#DbRep-autorename">DbRep-Agent</a> beschrieben. <br><br>

  DbRep stellt dem Nutzer einen <b>UserExit</b> zur Verfügung. Über diese Schnittstelle kann der Nutzer in Abhängigkeit von
  frei definierbaren Reading/Value-Kombinationen (Regex) eigenen Code zur Ausführung bringen. Diese Schnittstelle arbeitet
  unabhängig von einer Eventgenerierung. Weitere Informationen dazu ist unter <a href="#DbRep-attr-userExitFn">userExitFn</a>
  beschrieben. <br><br>

  Sobald ein DbRep-Device definiert ist, wird sowohl die Perl Funktion <b>DbReadingsVal</b> als auch das FHEM Kommando
  <b>dbReadingsVal</b> zur Verfügung gestellt.
  Mit dieser Funktion läßt sich, ähnlich dem allgemeinen ReadingsVal, der Wert eines Readings aus der Datenbank abrufen. <br>
  Die Funktionsausführung erfolgt blockierend mit einem Standardtimeout von 10 Sekunden um eine dauerhafte Blockierung von FHEM zu verhindern.
  Der Timeout ist mit dem Attribut <a href="#DbRep-attr-timeout">timeout</a> anpassbar. <br><br>

  <ul>
  Die Befehlssyntax für die Perl Funktion ist: <br><br>

  <code>
    DbReadingsVal("&lt;name&gt;","&lt;device:reading&gt;","&lt;timestamp&gt;","&lt;default&gt;")
  </code>
  <br><br>

  <b>Beispiel: </b><br>
  <pre>
  $ret = DbReadingsVal("Rep.LogDB1","MyWetter:temperature","2018-01-13_08:00:00","");
  attr &lt;name&gt; userReadings oldtemp {DbReadingsVal("Rep.LogDB1","MyWetter:temperature","2018-04-13_08:00:00","")}
  attr &lt;name&gt; userReadings todayPowerIn
    {
       my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
       $month++;
       $year+=1900;
       my $today = sprintf('%04d-%02d-%02d', $year,$month,$mday);
       DbReadingsVal("Rep.LogDB1","SMA_Energymeter:Bezug_Wirkleistung_Zaehler",$today."_00:00:00",0)
    }
  </pre>

  Die Befehlssyntax als FHEM Kommando ist: <br><br>

  <code>
    dbReadingsVal &lt;name&gt; &lt;device:reading&gt; &lt;timestamp&gt; &lt;default&gt;
  </code>
  <br><br>

  <b>Beispiel: </b><br>
  <code>
    dbReadingsVal Rep.LogDB1 MyWetter:temperature 2018-01-13_08:00:00 0
  </code>
  <br><br>

  <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> <b>&lt;name&gt;</b>           </td><td>: Name des abzufragenden DbRep-Device   </td></tr>
     <tr><td> <b>&lt;device:reading&gt;</b> </td><td>: Device:Reading dessen Wert geliefert werden soll </td></tr>
     <tr><td> <b>&lt;timestamp&gt;</b>      </td><td>: Zeitpunkt des zu liefernden Readingwertes (*) im Format "YYYY-MM-DD_hh:mm:ss" </td></tr>
     <tr><td> <b>&lt;default&gt;</b>        </td><td>: Defaultwert falls kein Readingwert ermittelt werden konnte </td></tr>
  </table>
  </ul>
  <br>

  (*) Es wird der zeitlich zu &lt;timestamp&gt; passendste Readingwert zurück geliefert, falls kein Wert exakt zu dem
        angegebenen Zeitpunkt geloggt wurde.
  <br><br>

  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting und Management von Datenbankinhalten (DbLog)</a>. <br><br>

  FHEM-Wiki: <br>
  <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten">DbRep - Reporting und Management von DbLog-Datenbankinhalten</a>. <br><br>
  <br>
  </ul>

<b>Voraussetzungen </b> <br><br>
<ul>
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
</ul>
<br>

<a id="DbRep-define"></a>
<b>Definition</b>

<br>
<ul>
  <code>
    define &lt;name&gt; DbRep &lt;Name der DbLog-Instanz&gt;
  </code>

  <br><br>
  (&lt;Name der DbLog-Instanz&gt; - es wird der Name der auszuwertenden DbLog-Datenbankdefinition angegeben <b>nicht</b> der Datenbankname selbst)
  <br><br>

  Für eine gute Operation Performance sollte die Datenbank den Index "Report_Idx" enthalten. Der Index kann nach der
  DbRep Devicedefinition mit dem set-Kommando angelegt werden sofern er auf der Datenbank noch nicht existiert: <br><br>
  <ul>
   <code>
    set &lt;name&gt; index recreate_Report_Idx
   </code>
  </ul>
</ul>

<br><br>

<a id="DbRep-set"></a>
<b>Set </b>
<ul>

 Zur Zeit gibt es folgende Set-Kommandos. Über sie werden die Auswertungen angestoßen und definieren selbst die Auswertungsvariante.
 Nach welchen Kriterien die Datenbankinhalte durchsucht werden und die Aggregation erfolgt, wird durch <a href="#DbRep-attr">Attribute</a> gesteuert.
 <br><br>

 <b>Hinweis: </b> <br>

 In der Detailansicht kann ein Browserrefresh nötig sein um die Operationsergebnisse zu sehen sobald im DeviceOverview
 "state = done" angezeigt wird.
 <br><br>

 <ul><ul>
    <a id="DbRep-set-adminCredentials"></a>
    <li><b> adminCredentials &lt;User&gt; &lt;Passwort&gt; </b> <br><br>

    Speichert einen User / Passwort für den privilegierten bzw. administrativen
    Datenbankzugriff. Er wird bei Datenbankoperationen benötigt, die mit einem privilegierten User
    ausgeführt werden müssen. Siehe auch Attribut <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>.
    </li>
    <br>

    <a id="DbRep-set-averageValue"></a>
    <li><b> averageValue [display | writeToDB | writeToDBSingle | writeToDBSingleStart | writeToDBInTime]</b> <br><br>

     Berechnet einen Durchschnittswert des Datenbankfelds "VALUE" in den Zeitgrenzen
     der möglichen time.*-Attribute. <br><br>

     Es muss das auszuwertende Reading im Attribut <a href="#DbRep-attr-reading">reading</a>
     angegeben sein.
     Mit dem Attribut <a href="#DbRep-attr-averageCalcForm">averageCalcForm</a> wird die Berechnungsvariante zur
     Mittelwertermittlung definiert. <br>
     Ist keine oder die Option <b>display</b> angegeben, werden die Ergebnisse nur angezeigt. Mit
     den Optionen <b>writeToDB</b>, <b>writeToDBSingle</b>, <b>writeToDBSingleStart</b> bzw. <b>writeToDBInTime</b>
     werden die Berechnungsergebnisse mit einem neuen Readingnamen in der Datenbank gespeichert. <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> <b>writeToDB</b>             </td><td>: schreibt jeweils einen Wert mit den Zeitstempeln XX:XX:01 und XX:XX:59 innerhalb der jeweiligen Auswertungsperiode </td></tr>
          <tr><td> <b>writeToDBSingle</b>       </td><td>: schreibt nur einen Wert mit dem Zeitstempel XX:XX:59 am Ende einer Auswertungsperiode                              </td></tr>
          <tr><td> <b>writeToDBSingleStart</b>  </td><td>: schreibt nur einen Wert mit dem Zeitstempel XX:XX:01 am Beginn einer Auswertungsperiode                            </td></tr>
          <tr><td> <b>writeToDBInTime</b>       </td><td>: schreibt jeweils einen Wert am Anfang und am Ende der Zeitgrenzen einer Auswertungsperiode                         </td></tr>
       </table>
       </ul>
       <br>

     Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet,
     wobei der originale Readingname durch das Attribut "readingNameMap" ersetzt werden kann.
     Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
     Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode
     abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann.
     Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>

     <ul>
     <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
     avgam_day_totalpac <br>
     # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>
     </ul>
     <br>

     Zusammengefasst sind die zur Steuerung dieser Funktion relevanten Attribute: <br><br>

       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>aggregation</b>                            </td><td>: Auswahl einer Aggregationsperiode </td></tr>
          <tr><td> <b>averageCalcForm</b>                        </td><td>: Auswahl der Berechnungsvariante für den Durchschnitt</td></tr>
          <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
          <tr><td> <b>executeBeforeProc</b>                      </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start Operation </td></tr>
          <tr><td> <b>executeAfterProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende Operation </td></tr>
          <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
          <tr><td> <b>readingNameMap</b>                         </td><td>: die entstehenden Ergebnisreadings werden partiell umbenannt </td></tr>
          <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
          <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
          </table>
       </ul>
       <br>
       <br>

    </li>
    <br>

    <a id="DbRep-set-cancelDump"></a>
    <li><b> cancelDump </b> <br><br>

    Bricht einen laufenden Datenbankdump ab.
    </li>
    <br>

    <a id="DbRep-set-changeValue"></a>
    <li><b> changeValue old="&lt;alter String&gt;" new="&lt;neuer String&gt;" </b> <br><br>

    Ändert den gespeicherten Wert eines Readings. <br>
    Ist die Selektion auf bestimmte Device/Reading-Kombinationen durch die Attribute
    <a href="#DbRep-attr-device">device</a> bzw. <a href="#DbRep-attr-reading">reading</a> beschränkt, werden sie genauso
    berücksichtigt wie gesetzte Zeitgrenzen (time.* Attribute).  <br>
    Fehlen diese Beschränkungen, wird die gesamte Datenbank durchsucht und der angegebene Wert
    geändert. <br><br>

    "String" kann sein: <br>
      <table>
         <colgroup> <col width=20%> <col width=80%> </colgroup>
         <tr><td><b>&lt;alter String&gt; :</b> </td><td><li>ein einfacher String mit/ohne Leerzeichen, z.B. "OL 12" </li>                                  </td></tr>
         <tr><td>                              </td><td><li>ein String mit Verwendung von SQL-Wildcard, z.B. "%OL%" </li>                                  </td></tr>
         <tr><td> </td><td> </td></tr>
         <tr><td> </td><td> </td></tr>
         <tr><td><b>&lt;neuer String&gt; :</b> </td><td><li>ein einfacher String mit/ohne Leerzeichen, z.B. "12 kWh" </li>                                 </td></tr>
         <tr><td>                              </td><td><li>Perl Code eingeschlossen in {"..."} inkl. Quotes, z.B. {"($VALUE,$UNIT) = split(" ",$VALUE)"}  </td></tr>
         <tr><td>                              </td><td>Dem Perl-Ausdruck werden die Variablen $VALUE und $UNIT übergeben. Sie können innerhalb            </td></tr>
         <tr><td>                              </td><td>des Perl-Code geändert werden. Der zurückgebene Wert von $VALUE und $UNIT wird in dem Feld         </td></tr>
         <tr><td>                              </td><td>VALUE bzw. UNIT des Datensatzes gespeichert. </li>                                                 </td></tr>
      </table>
    <br>

    <b>Beispiele: </b> <br>
    set &lt;name&gt; changeValue old="OL" new="12 OL"   <br>
    # der alte Feldwert "OL" wird in "12 OL" geändert.  <br><br>

    set &lt;name&gt; changeValue old="%OL%" new="12 OL"  <br>
    # enthält das Feld VALUE den Teilstring "OL", wird es in "12 OL" geändert. <br><br>

    set &lt;name&gt; changeValue old="12 kWh" new={"($VALUE,$UNIT) = split(" ",$VALUE)"}  <br>
    # der alte Feldwert "12 kWh" wird in VALUE=12 und UNIT=kWh gesplittet und in den Datenbankfeldern gespeichert <br><br>

    set &lt;name&gt; changeValue old="24%" new={"$VALUE = (split(" ",$VALUE))[0]"}  <br>
    # beginnt der alte Feldwert mit "24", wird er gesplittet und VALUE=24 gespeichert (z.B. "24 kWh")
    <br><br>

    Zusammengefasst sind die zur Steuerung von changeValue relevanten Attribute: <br><br>

      <ul>
      <table>
      <colgroup> <col width=5%> <col width=95%> </colgroup>
         <tr><td> <b>device</b>                                  </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
         <tr><td> <b>reading</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
         <tr><td> <b>time.*</b>                                  </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
         <tr><td> <b>executeBeforeProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start changeValue </td></tr>
         <tr><td> <b>executeAfterProc</b>                        </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende changeValue </td></tr>
         <tr><td> <b>valueFilter</b>                             </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
      </table>
      </ul>
    <br>
    <br>
    </li>

    <a id="DbRep-set-countEntries"></a>
    <li><b> countEntries [history | current] </b> <br><br>

    Liefert die Anzahl der Tabelleneinträge (default: history) in den gegebenen
    Zeitgrenzen (siehe <a href="#DbRep-attr">time*-Attribute</a>).
    Sind die Timestamps nicht gesetzt, werden alle Einträge der Tabelle gezählt.
    Beschränkungen durch die Attribute <a href="#DbRep-attr-device">device</a> bzw. <a href="#DbRep-attr-reading">reading</a>
    gehen in die Selektion mit ein. <br>
    Standardmäßig wird die Summe aller Datensätze, gekennzeichnet mit "ALLREADINGS", erstellt.
    Ist das Attribut <a href="#DbRep-attr-countEntriesDetail">countEntriesDetail</a> gesetzt, wird die Anzahl jedes
    einzelnen Readings zusätzlich ausgegeben. <br><br>

    Die für diese Funktion relevanten Attribute sind: <br><br>

    <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>aggregation</b>            </td><td>: Zusammenfassung/Gruppierung von Zeitintervallen </td></tr>
          <tr><td> <b>countEntriesDetail</b>     </td><td>: detaillierte Ausgabe der Datensatzanzahl </td></tr>
          <tr><td> <b>device</b>                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
          <tr><td> <b>reading</b>                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
          <tr><td> <b>time.*</b>                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
          <tr><td> executeBeforeProc             </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Ausführung </td></tr>
          <tr><td> executeAfterProc              </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ausführung </td></tr>
          <tr><td> <b>readingNameMap</b>         </td><td>: die entstehenden Ergebnisreadings werden partiell umbenannt </td></tr>
          <tr><td> <b>valueFilter</b>            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
          </table>
    </ul>
    </li>
    <br>
    <br>

    <li><b> delDoublets [adviceDelete | delete]</b>   -  zeigt bzw. löscht doppelte / mehrfach vorkommende Datensätze.
                                 Dazu wird Timestamp, Device,Reading und Value ausgewertet. <br>
                                 Die <a href="#DbRep-attr">Attribute</a> zur Aggregation,Zeit-,Device- und Reading-Abgrenzung werden dabei
                                 berücksichtigt. Ist das Attribut "aggregation" nicht oder auf "no" gesetzt, wird im Standard die Aggregation
                                 "day" verwendet.
                                 <br><br>
                                 </li>

                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>adviceDelete</b>  </td><td>: ermittelt die zu löschenden Datensätze (es wird nichts gelöscht !) </td></tr>
                                      <tr><td> <b>delete</b>        </td><td>: löscht die Dubletten </td></tr>
                                   </table>
                                   </ul>
                                   <br>

                                 Aus Sicherheitsgründen muss das Attribut <a href="#DbRep-attr-allowDeletion">allowDeletion</a> für die "delete" Option
                                 gesetzt sein. <br>
                                 Die Anzahl der anzuzeigenden Datensätze des Kommandos "delDoublets adviceDelete" ist zunächst
                                 begrenzt (default 1000) und kann durch das Attribut <a href="#DbRep-attr-limit">limit</a> angepasst
                                 werden.
                                 Die Einstellung von "limit" hat keinen Einfluss auf die "delDoublets delete" Funktion, sondern
                                 beeinflusst <b>NUR</b> die Anzeige der Daten.   <br>
                                 Vor und nach der Ausführung von "delDoublets" kann ein FHEM-Kommando bzw. Perl-Routine ausgeführt
                                 werden. (siehe Attribute <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
                                 <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>)
                                 <br><br>

                                 <ul>
                                 <b>Beispiel:</b> <br><br>
                                 Ausgabe der zu löschenden Records inklusive der Anzahl mit "delDoublets adviceDelete": <br><br>

                                 2018-11-07_14-11-38__Dum.Energy__T 260.9_|_2 <br>
                                 2018-11-07_14-12-37__Dum.Energy__T 260.9_|_2 <br>
                                 2018-11-07_14-15-38__Dum.Energy__T 264.0_|_2 <br>
                                 2018-11-07_14-16-37__Dum.Energy__T 264.0_|_2 <br>
                                 <br>
                                 Im Werteteil der erzeugten Readings wird nach "_|_" die Anzahl der entsprechenden Datensätze
                                 ausgegeben, die mit "delDoublets delete" gelöscht werden.
                                 </ul>
                                 <br>

                                 Zusammengefasst sind die zur Steuerung dieser Funktion relevanten Attribute: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>allowDeletion</b>                          </td><td>: Freischaltung der Löschfunktion </td></tr>
                                    <tr><td> <b>aggregation</b>                            </td><td>: Auswahl einer Aggregationsperiode </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                    <tr><td> <b>limit</b>                                  </td><td>: begrenzt NUR die Anzahl der anzuzeigenden Datensätze  </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start des Befehls </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende des Befehls </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
                                    </table>
                                 </ul>
                                 <br>
                                 <br>

    <a id="DbRep-set-delEntries"></a>
    <li><b> delEntries [&lt;no&gt;[:&lt;nn&gt;]] </b> <br><br>

    Löscht alle oder die durch die <a href="#DbRep-attr">Attribute</a> device und/oder
    reading definierten Datenbankeinträge. Die Eingrenzung über Timestamps erfolgt
    folgendermaßen: <br><br>

    <ul>
      "timestamp_begin" gesetzt <b>-&gt;</b> gelöscht werden DB-Einträge <b>ab</b> diesem Zeitpunkt bis zum aktuellen Datum/Zeit <br>
      "timestamp_end" gesetzt <b>-&gt;</b>   gelöscht werden DB-Einträge <b>bis</b> bis zu diesem Zeitpunkt <br>
      beide Timestamps gesetzt <b>-&gt;</b>  gelöscht werden DB-Einträge <b>zwischen</b> diesen Zeitpunkten <br>
      "timeOlderThan" gesetzt  <b>-&gt;</b>  gelöscht werden DB-Einträge <b>älter</b> als aktuelle Zeit minus "timeOlderThan" <br>
      "timeDiffToNow" gesetzt  <b>-&gt;</b>  gelöscht werden DB-Einträge <b>ab</b> aktueller Zeit minus "timeDiffToNow" bis jetzt <br>
    </ul>
    <br>

    Aus Sicherheitsgründen muss das Attribut <a href="#DbRep-attr-allowDeletion">allowDeletion</a>
    gesetzt sein um die Löschfunktion freizuschalten. <br>
    Zeitgrenzen (Tage) können als Option angegeben werden. In diesem Fall werden eventuell gesetzte Zeitattribute
    übersteuert.
    Es werden Datensätze berücksichtigt die älter sind als <b>&lt;no&gt;</b> Tage und (optional) neuer sind als
    <b>&lt;nn&gt;</b> Tage.
    <br><br>

    Die zur Steuerung von delEntries relevanten Attribute: <br><br>

    <ul>
     <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>allowDeletion</b>                          </td><td>: Freischaltung der Löschfunktion </td></tr>
        <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
        <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
        <tr><td> <b>readingNameMap</b>                         </td><td>: die entstehenden Ergebnisreadings werden partiell umbenannt </td></tr>
        <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
        <tr><td> <b>executeBeforeProc</b>                      </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start delEntries </td></tr>
        <tr><td> <b>executeAfterProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende delEntries </td></tr>
        <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
     </table>
    </ul>
    <br>
    </li>
    <br>

    <li><b> delSeqDoublets [adviceRemain | adviceDelete | delete]</b>   -  zeigt bzw. löscht aufeinander folgende identische Datensätze.
                                 Dazu wird Device,Reading und Value ausgewertet. Nicht gelöscht werden der erste und der letzte Datensatz
                                 einer Aggregationsperiode (z.B. hour, day, week usw.) sowie die Datensätze vor oder nach einem Wertewechsel
                                 (Datenbankfeld VALUE). <br>
                                 Die <a href="#DbRep-attr">Attribute</a> zur Aggregation,Zeit-,Device- und Reading-Abgrenzung werden dabei
                                 berücksichtigt. Ist das Attribut "aggregation" nicht oder auf "no" gesetzt, wird als Standard die Aggregation
                                 "day" verwendet. Für Datensätze mit numerischen Werten kann mit dem Attribut <a href="#DbRep-attr-seqDoubletsVariance">seqDoubletsVariance</a>
                                 eine Abweichung eingestellt werden, bis zu der aufeinander folgende numerische Werte als
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

                                 Aus Sicherheitsgründen muss das Attribut <a href="#DbRep-attr-allowDeletion">allowDeletion</a> für die "delete" Option
                                 gesetzt sein. <br>
                                 Die Anzahl der anzuzeigenden Datensätze der Kommandos "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" ist
                                 zunächst begrenzt (default 1000) und kann durch das Attribut <a href="#DbRep-attr-limit">limit</a> angepasst werden.
                                 Die Einstellung von "limit" hat keinen Einfluss auf die "delSeqDoublets delete" Funktion, sondern beeinflusst <b>NUR</b> die
                                 Anzeige der Daten.  <br>
                                 Vor und nach der Ausführung von "delSeqDoublets" kann ein FHEM-Kommando bzw. Perl-Routine ausgeführt werden.
                                 (siehe Attribute <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
                                 <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>)
                                 <br><br>

                                 <ul>
                                 <b>Beispiel</b> - die nach Verwendung der delete-Option in der DB verbleibenden Datensätze sind <b>fett</b>
                                 gekennzeichnet:<br><br>
                                 <ul>
                                 <b>2017-11-25_00-00-05__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_00-02-26__eg.az.fridge_Pwr__power 0                 <br>
                                 2017-11-25_00-04-33__eg.az.fridge_Pwr__power 0                 <br>
                                 2017-11-25_01-06-10__eg.az.fridge_Pwr__power 0                 <br>
                                 <b>2017-11-25_01-08-21__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_01-08-59__eg.az.fridge_Pwr__power 60.32 </b>     <br>
                                 <b>2017-11-25_01-11-21__eg.az.fridge_Pwr__power 56.26 </b>     <br>
                                 <b>2017-11-25_01-27-54__eg.az.fridge_Pwr__power 6.19  </b>     <br>
                                 <b>2017-11-25_01-28-51__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_01-31-00__eg.az.fridge_Pwr__power 0                 <br>
                                 2017-11-25_01-33-59__eg.az.fridge_Pwr__power 0                 <br>
                                 <b>2017-11-25_02-39-29__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_02-41-18__eg.az.fridge_Pwr__power 105.28</b>     <br>
                                 <b>2017-11-25_02-41-26__eg.az.fridge_Pwr__power 61.52 </b>     <br>
                                 <b>2017-11-25_03-00-06__eg.az.fridge_Pwr__power 47.46 </b>     <br>
                                 <b>2017-11-25_03-00-33__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_03-02-07__eg.az.fridge_Pwr__power 0                 <br>
                                 2017-11-25_23-37-42__eg.az.fridge_Pwr__power 0                 <br>
                                 <b>2017-11-25_23-40-10__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1                 <br>
                                 <b>2017-11-25_23-45-27__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 <b>2017-11-25_23-47-07__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_23-55-27__eg.az.fridge_Pwr__power 0                 <br>
                                 <b>2017-11-25_23-48-15__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-50-21__eg.az.fridge_Pwr__power 59.1  </b>     <br>
                                 <b>2017-11-25_23-55-14__eg.az.fridge_Pwr__power 52.31 </b>     <br>
                                 <b>2017-11-25_23-58-09__eg.az.fridge_Pwr__power 51.73 </b>     <br>
                                 </ul>
                                 </ul>
                                 <br>

                                 Zusammengefasst sind die zur Steuerung dieser Funktion relevanten Attribute: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>allowDeletion</b>                          </td><td>: needs to be set to execute the delete option </td></tr>
                                    <tr><td> <b>aggregation</b>                            </td><td>: Auswahl einer Aggregationsperiode </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                    <tr><td> <b>limit</b>                                  </td><td>: begrenzt NUR die Anzahl der anzuzeigenden Datensätze  </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                    <tr><td> <b>readingNameMap</b>                         </td><td>: die entstehenden Ergebnisreadings werden partiell umbenannt </td></tr>
                                    <tr><td> <b>seqDoubletsVariance</b>                    </td><td>: bis zu diesem Wert werden aufeinander folgende numerische Datensätze als identisch angesehen und werden gelöscht </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start des Befehls </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende des Befehls </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
                                    </table>
                                 </ul>
                                 <br>
                                 <br>

                                 </li>

    <a id="DbRep-set-deviceRename"></a>
    <li><b> deviceRename &lt;old_name&gt;,&lt;new_name&gt;</b> <br><br>

    Benennt den Namen eines Device innerhalb der angeschlossenen Datenbank (Internal DATABASE) um.
    Der Gerätename wird immer in der <b>gesamten</b> Datenbank umgesetzt. Eventuell gesetzte
    Zeitgrenzen oder Beschränkungen durch die Attribute <a href="#DbRep-attr-device">device</a> bzw.
    <a href="#DbRep-attr-reading">reading</a> werden nicht berücksichtigt.  <br><br>

    <ul>
     <b>Beispiel: </b><br>
     set &lt;name&gt; deviceRename ST_5000,ST5100  <br>
     # Die Anzahl der umbenannten Device-Datensätze wird im Reading "device_renamed" ausgegeben. <br>
     # Wird der umzubenennende Gerätename in der Datenbank nicht gefunden, wird eine WARNUNG im Reading "device_not_renamed" ausgegeben. <br>
     # Entsprechende Einträge erfolgen auch im Logfile mit verbose=3
    </ul>
    <br><br>

    <b>Hinweis:</b> <br>
    Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
    im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br>
    <br>

    Zusammengefasst sind die zur Steuerung dieser Funktion relevanten Attribute: <br><br>

    <ul>
     <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>executeBeforeProc</b>    </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start des Befehls </td></tr>
        <tr><td> <b>executeAfterProc</b>     </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende des Befehls </td></tr>
        </table>
    </ul>
    <br>
    <br>
    </li>

    <li><b> diffValue [display | writeToDB] </b> <br><br>

     Berechnet den Differenzwert des Datenbankfelds "VALUE" in den angegebenen Zeitgrenzen
     (siehe verschiedenen time*-Attribute). <br><br>

     Es wird die Differenz aus den VALUE-Werten der im Aggregationszeitraum (z.B. day) vorhandenen Datensätze gebildet und
     aufsummiert.
     Ein Übertragswert aus der Vorperiode (<a href="#DbRep-attr-aggregation">aggregation</a>) zur darauf folgenden
     Aggregationsperiode wird berücksichtigt, sofern diese Periode einen Value-Wert enhtält.  <br><br>

     In der Standardeinstellung wertet die Funktion nur positive Differenzen aus wie sie z.B. bei einem stetig ansteigenden
     Zählerwert auftreten.
     Mit dem Attribut <a href="#DbRep-attr-diffAccept">diffAccept</a>) kann sowohl die akzeptierte Differenzschwelle als
     auch die Möglichkeit negative Differenzen auszuwerten eingestellt werden. <br><br>

     <ul>
       <b>Hinweis: </b><br>
       Im Auswertungs- bzw. Aggregationszeitraum (Tag, Woche, Monat, etc.) sollten dem Modul pro Periode mindestens ein
       Datensatz zu Beginn und ein Datensatz gegen Ende des Aggregationszeitraumes zur Verfügung stehen um eine möglichst
       genaue Auswertung der Differenzwerte vornehmen zu können. <br>

       Wird in einer auszuwertenden Zeit- bzw. Aggregationsperiode nur ein Datensatz gefunden, kann die Differenz in
       Verbindung mit dem Differenzübertrag der Vorperiode berechnet werden. in diesem Fall kann es zu einer logischen
       Ungenauigkeit in der Zuordnung der Differenz zu der Aggregationsperiode kommen. In diesem Fall wird eine Warnung
       im state ausgegeben und das Reading <b>less_data_in_period</b> mit einer Liste der betroffenen Perioden erzeugt.
     <br>
     <br>
     </ul>

     Ist keine oder die Option <b>display</b> angegeben, werden die Ergebnisse nur angezeigt. <br><br>

     Mit der Option <b>writeToDB</b> werden die Berechnungsergebnisse mit einem neuen Readingnamen
     in der Datenbank gespeichert. <br>
     Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet,
     wobei der originale Readingname durch das Attribut <a href="#DbRep-attr-readingNameMap">readingNameMap</a> ersetzt
     werden kann. <br>
     Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
     Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode
     abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann.
     Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>

     <ul>
     <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
     diff_day_totalpac <br>
     # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>
     </ul>
     <br>

     Die für die Funktion relevanten Attribute sind: <br><br>

     <ul>
      <table>
      <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>aggregation</b>                            </td><td>: Auswahl einer Aggregationsperiode </td></tr>
        <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
        <tr><td> <b>diffAccept</b>                             </td><td>: akzeptierte positive Werte-Differenz zwischen zwei unmittelbar aufeinander folgenden Datensätzen </td></tr>
        <tr><td> <b>executeBeforeProc</b>                      </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor Start Operation </td></tr>
        <tr><td> <b>executeAfterProc</b>                       </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach Ende Operation </td></tr>
        <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
        <tr><td> <b>readingNameMap</b>                         </td><td>: die entstehenden Ergebnisreadings werden partiell umbenannt </td></tr>
        <tr><td> <b>time*</b>                                  </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
        <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
      </table>
     </ul>
     <br>

     </li>
     <br>

    <li><b> dumpMySQL [clientSide | serverSide]</b> <br><br>

     Erstellt einen Dump der angeschlossenen MySQL-Datenbank.  <br>
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
     (typisch /opt/fhem/log/) gespeichert.
     Das Zielverzeichnis kann mit dem Attribut <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> verändert werden und muß auf
     dem Client durch FHEM beschreibbar sein. <br>
     Vor dem Dump kann eine Tabellenoptimierung (Attribut "optimizeTablesBeforeDump") oder ein FHEM-Kommando
     (Attribut "executeBeforeProc") optional zugeschaltet werden.
     Nach dem Dump kann ebenfalls ein FHEM-Kommando (siehe Attribut "executeAfterProc") ausgeführt werden. <br><br>

     <b>Achtung ! <br>
     Um ein Blockieren von FHEM zu vermeiden, muß DbLog im asynchronen Modus betrieben werden wenn die
     Tabellenoptimierung verwendet wird ! </b> <br><br>

     Über die Attribute <a href="#DbRep-attr-dumpMemlimit">dumpMemlimit</a> und <a href="#DbRep-attr-dumpSpeed">dumpSpeed</a>
     kann das Laufzeitverhalten der
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
          <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor dem Dump </td></tr>
          <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach dem Dump </td></tr>
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

     Um die Datenbank aus dem Dumpfile wiederherzustellen kann das Kommmando: <br><br>

       <ul>
       set &lt;name&gt; restoreMySQL &lt;filename&gt; <br><br>
       </ul>

     verwendet werden. <br><br>

     Das erzeugte Dumpfile (unkomprimiert) kann ebenfalls mit: <br><br>

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
          <tr><td> dumpDirRemote            </td><td>: das Erstellungsverzeichnis des Dumpfile auf dem entfernten Server </td></tr>
          <tr><td> dumpCompress             </td><td>: Komprimierung des Dumpfiles nach der Erstellung </td></tr>
          <tr><td> dumpDirLocal             </td><td>: Directory des lokal gemounteten dumpDirRemote-Verzeichnisses  </td></tr>
          <tr><td> dumpFilesKeep            </td><td>: Anzahl der aufzubwahrenden Dumpfiles </td></tr>
          <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor dem Dump </td></tr>
          <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach dem Dump </td></tr>
          <tr><td> optimizeTablesBeforeDump </td><td>: Tabelloptimierung vor dem Dump ausführen </td></tr>
       </table>
       </ul>
       <br>

     Das Zielverzeichnis kann mit dem Attribut <a href="#DbRep-attr-dumpDirRemote">dumpDirRemote</a> verändert werden.
     Es muß sich auf dem MySQL-Host gefinden und durch den MySQL-Serverprozess beschreibbar sein. <br>
     Der verwendete Datenbankuser benötigt das <b>FILE</b> Privileg (siehe <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#3._Backup_durchf.C3.BChren_2">Wiki</a>). <br><br>

     <b>Hinweis:</b> <br>
     Soll die interne Versionsverwaltung und die Dumpfilekompression des Moduls genutzt, sowie die Größe des erzeugten
     Dumpfiles ausgegeben werden, ist das Verzeichnis "dumpDirRemote" des MySQL-Servers auf dem Client zu mounten
     und im Attribut <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> dem DbRep-Device bekannt zu machen. <br>
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
     Wenn diese Möglichkeit genutzt werden soll, ist das Attribut <a href="#DbRep-attr-ftpUse">ftpUse</a> oder
     "ftpUseSSL" zu setzen. Letzteres gilt wenn eine verschlüsselte Übertragung genutzt werden soll. <br>
     Das Modul übernimmt ebenfalls die Versionierung der Dumpfiles im FTP-Zielverzeichnis mit Hilfe des Attributes
     "ftpDumpFilesKeep".
     Für die FTP-Übertragung relevante Attribute sind: <br><br>

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
     </li>
     <br>

    <li><b> dumpSQLite </b>   -  erstellt einen Dump der angeschlossenen SQLite-Datenbank.  <br>
                                 Diese Funktion nutzt die SQLite Online Backup API und ermöglicht es konsistente Backups der SQLite-DB
                                 in laufenden Betrieb zu erstellen.
                                 Der Dump wird per default im log-Verzeichnis des FHEM-Rechners gespeichert.
                                 Das Zielverzeichnis kann mit dem <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> Attribut verändert werden und muß
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
                                      <tr><td> dumpCompress             </td><td>: Komprimierung des Dumpfiles nach der Erstellung           </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: Zielverzeichnis der Dumpfiles                             </td></tr>
                                      <tr><td> dumpFilesKeep            </td><td>: Anzahl der aufzubwahrenden Dumpfiles                      </td></tr>
                                      <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder Perl-Routine) vor dem Dump  </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder Perl-Routine) nach dem Dump </td></tr>
                                      <tr><td> optimizeTablesBeforeDump </td><td>: Tabelloptimierung vor dem Dump ausführen                  </td></tr>
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

    <a id="DbRep-set-eraseReadings"></a>
    <li><b> eraseReadings </b> <br><br>

    Löscht alle angelegten Readings im Device, außer dem Reading "state" und Readings, die in der
    Ausnahmeliste definiert mit Attribut <a href="#DbRep-attr-readingPreventFromDel">readingPreventFromDel</a>
    enthalten sind.
    </li>
    <br>

    <li><b> exportToFile [&lt;/Pfad/File&gt;] [MAXLINES=&lt;lines&gt;] </b>
                                 -  exportiert DB-Einträge im CSV-Format in den gegebenen Zeitgrenzen. <br><br>

                                 Der Dateiname wird durch das <a href="#DbRep-attr-expimpfile">expimpfile</a> Attribut bestimmt.
                                 Alternativ kann "/Pfad/File" als Kommando-Option angegeben werden und übersteuert ein
                                 eventuell gesetztes Attribut "expimpfile". Optional kann über den Parameter "MAXLINES" die
                                 maximale Anzahl von Datensätzen angegeben werden, die in ein File exportiert werden.
                                 In diesem Fall werden mehrere Files mit den Extensions "_part1", "_part2", "_part3" usw.
                                 erstellt (beim Import berücksichtigen !). <br><br>
                                 Einschränkungen durch die Attribute <a href="#DbRep-attr-device">device</a> bzw.
                                 <a href="#DbRep-attr-reading">reading</a> gehen in die Selektion mit ein.
                                 Der Dateiname kann Wildcards enthalten (siehe Attribut "expimpfile").
                                 <br>
                                 Durch das Attribut "aggregation" wird der Export der Datensätze in Zeitscheiben der angegebenen Aggregation
                                 vorgenommen. Ist z.B. "aggregation = month" gesetzt, werden die Daten in monatlichen Paketen selektiert und in
                                 das Exportfile geschrieben. Dadurch wird die Hauptspeicherverwendung optimiert wenn sehr große Datenmengen
                                 exportiert werden sollen und vermeidet den "died prematurely" Abbruchfehler. <br><br>

                                 Die für diese Funktion relevanten Attribute sind: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>aggregation</b>                            </td><td>: Festlegung der Selektionspaketierung </td></tr>
                                    <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                    <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                    <tr><td> <b>executeBeforeProc</b>                      </td><td>: FHEM Kommando (oder Perl-Routine) vor dem Export ausführen </td></tr>
                                    <tr><td> <b>executeAfterProc</b>                       </td><td>: FHEM Kommando (oder Perl-Routine) nach dem Export ausführen </td></tr>
                                    <tr><td> <b>expimpfile</b>                             </td><td>: der Name des Exportfiles </td></tr>
                                    <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
                                    <tr><td> <b>valueFilter</b>                            </td><td>: ein zusätzliches REGEXP um die Datenselektion zu steuern. Der REGEXP wird auf das Datenbankfeld 'VALUE' angewendet. </td></tr>
                                 </table>
                                 </ul>

                                 </li><br>

    <li><b> fetchrows [history|current] </b>
                                 -  liefert <b>alle</b> Tabelleneinträge (default: history)
                                 in den gegebenen Zeitgrenzen bzw. Selektionsbedingungen durch die Attribute
                                 <a href="#DbRep-attr-device">device</a> und <a href="#DbRep-attr-reading">reading</a>.
                                 Eine evtl. gesetzte Aggregation wird dabei <b>nicht</b> berücksichtigt. <br>
                                 Die Leserichtung in der Datenbank kann durch das Attribut
                                 <a href="#DbRep-attr-fetchRoute">fetchRoute</a> bestimmt werden. <br><br>

                                 Jedes Ergebnisreading setzt sich aus dem Timestring des Datensatzes, einem Dubletten-Index,
                                 dem Device und dem Reading zusammen.
                                 Die Funktion fetchrows ist in der Lage, mehrfach vorkommende Datensätze (Dubletten) zu erkennen.
                                 Solche Dubletten sind mit einem Dubletten-Index > 1 gekennzeichnet. Optional wird noch ein
                                 Unique-Index angehängt, wenn Datensätze mit identischem Timestamp, Device und Reading aber
                                 unterschiedlichem Value vorhanden sind. <br>
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
                                 2017-10-22_03-04-43__1__SMA_Energymeter__Bezug_WirkP_Kosten_Diff__[1] <br>
                                 # &lt;Datum&gt;_&lt;Zeit&gt;__&lt;Dubletten-Index&gt;__&lt;Device&gt;__&lt;Reading&gt;__[Unique-Index]
                                 </ul>
                                 <br>

                                 Die zur Steuerung von fetchrows relevanten Attribute sind: <br><br>

                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>device</b>                                 </td><td>: einschließen oder ausschließen von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                      <tr><td> <b>fetchRoute</b>                             </td><td>: Leserichtung der Selektion innerhalb der Datenbank </td></tr>
                                      <tr><td> <b>fetchMarkDuplicates</b>                    </td><td>: Hervorhebung von gefundenen Dubletten </td></tr>
                                      <tr><td> <b>fetchValueFn</b>                           </td><td>: der angezeigte Wert des VALUE Datenbankfeldes kann mit einer Funktion vor der Readingerstellung geändert werden </td></tr>
                                      <tr><td> <b>limit</b>                                  </td><td>: begrenzt die Anzahl zu selektierenden bzw. anzuzeigenden Datensätze  </td></tr>
                                      <tr><td> <b>executeBeforeProc</b>                      </td><td>: FHEM Kommando (oder Perl-Routine) vor dem Befehl ausführen </td></tr>
                                      <tr><td> <b>executeAfterProc</b>                       </td><td>: FHEM Kommando (oder Perl-Routine) nach dem Befehl ausführen </td></tr>
                                      <tr><td> <b>reading</b>                                </td><td>: einschließen oder ausschließen von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                      <tr><td> <b>time.*</b>                                 </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
                                      <tr><td> <b>valueFilter</b>                            </td><td>: filtert die anzuzeigenden Datensätze mit einem regulären Ausdruck (Datenbank spezifischer REGEXP). Der REGEXP wird auf Werte des Datenbankfeldes 'VALUE' angewendet. </td></tr>
                                   </table>
                                   </ul>
                                   <br>
                                   <br>

                                 <b>Hinweis:</b> <br>
                                 Auch wenn das Modul bezüglich der Datenbankabfrage nichtblockierend arbeitet, kann eine
                                 zu große Ergebnismenge (Anzahl Zeilen bzw. Readings) die Browsersesssion bzw. FHEMWEB
                                 blockieren. Aus diesem Grund wird die Ergebnismenge mit dem Attribut
                                 <a href="#DbRep-attr-limit">limit</a> begrenzt. Bei Bedarf kann dieses Attribut
                                 geändert werden, falls eine Anpassung der Selektionsbedingungen nicht möglich oder
                                 gewünscht ist. <br><br>
                                 </li> <br>

    <li><b> index &lt;Option&gt; </b>
                               - Listet die in der Datenbank vorhandenen Indexe auf bzw. legt die benötigten Indexe
                               an. Ist ein Index bereits angelegt, wird er erneuert (gelöscht und erneut angelegt) <br><br>

                               Die möglichen Optionen sind: <br><br>

                               <ul>
                                 <table>
                                   <colgroup> <col width=25%> <col width=75%> </colgroup>
                                   <tr><td> <b>list_all</b>                 </td><td>: listet die vorhandenen Indexe auf </td></tr>
                                   <tr><td> <b>recreate_Search_Idx</b>      </td><td>: erstellt oder erneuert (falls vorhanden) den Index Search_Idx in Tabelle history (Index für DbLog) </td></tr>
                                   <tr><td> <b>drop_Search_Idx</b>          </td><td>: löscht den Index Search_Idx in Tabelle history </td></tr>
                                   <tr><td> <b>recreate_Report_Idx</b>      </td><td>: erstellt oder erneuert (falls vorhanden) den Index Report_Idx in Tabelle history (Index für DbRep) </td></tr>
                                   <tr><td> <b>drop_Report_Idx</b>          </td><td>: löscht den Index Report_Idx in Tabelle history </td></tr>
                                 </table>
                               </ul>
                               <br>

                               Die für diese Funktion relevanten Attribute sind: <br><br>

                               <ul>
                                 <table>
                                   <colgroup> <col width=39%> <col width=61%> </colgroup>
                                   <tr><td> <b>useAdminCredentials</b>        </td><td>: benutzt einen privilegierten User für die Operation </td></tr>
                                 </table>
                               </ul>
                               <br>

                               <b>Hinweis:</b> <br>
                               Der verwendete MySQL Datenbank-Nutzer benötigt das ALTER, CREATE und INDEX Privileg. <br>
                               Diese Rechte können gesetzt werden mit: <br><br>
                               <ul>
                                 set &lt;Name&gt; sqlCmd GRANT INDEX, ALTER, CREATE ON `&lt;db&gt;`.* TO '&lt;user&gt;'@'%';
                               </ul>
                               <br>
                               Das Attribut <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a> muß gewöhnlich gesetzt sein um
                               die Rechte des verwendeten Users ändern zu können.

                               </li>
                               <br>

    <a id="DbRep-set-insert"></a>
    <li><b> insert &lt;Datum&gt;,&lt;Zeit&gt;,&lt;Value&gt;,[&lt;Unit&gt;],[&lt;Device&gt;],[&lt;Reading&gt;] </b>
                                 -  Manuelles Einfügen eines Datensatzes in die Tabelle "history". Obligatorisch sind Eingabewerte für Datum, Zeit und Value.
                                 Die Werte für die DB-Felder TYPE bzw. EVENT werden mit "manual" gefüllt. <br>
                                 Werden <b>Device</b>, <b>Reading</b> nicht gesetzt, werden diese Werte aus den entsprechenden
                                 Attributen <a href="#DbRep-attr-device">device</a> bzw. <a href="#DbRep-attr-reading">reading</a> genommen.
                                 <br><br>

                                 <b>Hinweis: </b><br>
                                 Nicht belegte Felder innerhalb des insert Kommandos müssen innerhalb des Strings in ","
                                 eingeschlossen werden.
                                 <br>
                                 <br>

                                 <ul>
                                 <b>Beispiel: </b> <br>
                                 set &lt;name&gt; insert 2016-08-01,23:00:09,12.03,kW                         <br>
                                 set &lt;name&gt; insert 2021-02-02,10:50:00,value with space                 <br>
                                 set &lt;name&gt; insert 2022-05-16,10:55:00,1800,,SMA_Wechselrichter,etotal  <br>
                                 set &lt;name&gt; insert 2022-05-16,10:55:00,1800,,,etotal                    <br>
                                 </ul>
                                 <br>

                                 Die für diese Funktion relevanten Attribute sind: <br><br>

                                 <ul>
                                 <table>
                                 <colgroup> <col width=5%> <col width=95%> </colgroup>
                                    <tr><td> <b>executeBeforeProc</b>   </td><td>: FHEM Kommando (oder Perl-Routine) vor dem Befehl ausführen </td></tr>
                                    <tr><td> <b>executeAfterProc</b>    </td><td>: FHEM Kommando (oder Perl-Routine) nach dem Befehl ausführen </td></tr>
                                 </table>
                                 </ul>
                                 <br>
                                 <br>

                                 </li>

    <li><b> importFromFile [&lt;File&gt;] </b>
                                 - importiert Datensätze im CSV-Format aus einer Datei in die Datenbank. <br>
                                 Der Dateiname wird durch das Attribut <a href="#DbRep-attr-expimpfile">expimpfile</a> bestimmt. <br>
                                 Alternativ kann die Datei (/Pfad/Datei) als Kommando-Option angegeben werden und übersteuert ein
                                 eventuell gesetztes Attribut "expimpfile". Der Dateiname kann Wildcards enthalten (siehe
                                 Attribut "expimpfile"). <br><br>

                                 <ul>
                                 <b>Datensatzformat: </b> <br>
                                 "TIMESTAMP","DEVICE","TYPE","EVENT","READING","VALUE","UNIT"  <br><br>
                                 # Die Felder "TIMESTAMP","DEVICE","TYPE","EVENT","READING" und "VALUE" müssen gesetzt sein. Das Feld "UNIT" ist optional.
                                 Der Fileinhalt wird als Transaktion importiert, d.h. es wird der Inhalt des gesamten Files oder, im Fehlerfall, kein Datensatz des Files importiert.
                                 Wird eine umfangreiche Datei mit vielen Datensätzen importiert, sollte KEIN verbose=5 gesetzt werden. Es würden in diesem Fall sehr viele Sätze in
                                 das Logfile geschrieben werden was FHEM blockieren oder überlasten könnte. <br><br>

                                 <b>Beispiel: </b> <br>
                                 "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>

                                 Die für diese Funktion relevanten Attribute sind: <br><br>
                                   <ul>
                                   <table>
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>executeBeforeProc</b>  </td><td>: FHEM Kommando (oder Perl-Routine) vor dem Import ausführen </td></tr>
                                      <tr><td> <b>executeAfterProc</b>   </td><td>: FHEM Kommando (oder Perl-Routine) nach dem Import ausführen </td></tr>
                                      <tr><td> <b>expimpfile</b>         </td><td>: der Name des Importfiles </td></tr>
                                   </table>
                                   </ul>
                                 </li> <br>
                                 </ul>
                                 <br>

    <li><b> maxValue [display | writeToDB | deleteOther] </b> <br><br>

     Berechnet den Maximalwert des Datenbankfelds "VALUE" in den Zeitgrenzen
     (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan" etc.
     Es muss das auszuwertende Reading über das Attribut <a href="#DbRep-attr-reading">reading</a>
     angegeben sein.
     Die Auswertung enthält den Zeitstempel des ermittelten Maximumwertes innerhalb der
     Aggregation bzw. Zeitgrenzen.
     Im Reading wird der Zeitstempel des <b>letzten</b> Auftretens vom Maximalwert ausgegeben,
     falls dieser Wert im Intervall mehrfach erreicht wird. <br><br>

     Ist keine oder die Option <b>display</b> angegeben, werden die Ergebnisse nur angezeigt. Mit
     der Option <b>writeToDB</b> werden die Berechnungsergebnisse mit einem neuen Readingnamen
     in der Datenbank gespeichert. <br>
     Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet,
     wobei der originale Readingname durch das Attribut <a href="#DbRep-attr-readingNameMap">readingNameMap</a> ersetzt werden kann.
     Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
     Der Timestamp des neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode
     abgeleitet.
     Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>

     Wird die Option <b>deleteOther</b> verwendet, werden alle Datensätze außer dem Datensatz mit dem
     ermittelten Maximalwert aus der Datenbank innerhalb der definierten Grenzen gelöscht. <br><br>

     <ul>
       <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
       max_day_totalpac <br>
       # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>
     </ul>
     <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-migrateCollation"></a>
    <li><b> migrateCollation &lt;Collation&gt; </b> <br><br>

    Migriert den verwendeten Zeichensatz/Kollation der Datenbank und der Tabellen current und history in das
    angegebene Format.
    <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <li><b> minValue [display | writeToDB | deleteOther]</b> <br><br>

    Berechnet den Minimalwert des Datenbankfelds "VALUE" in den Zeitgrenzen
    (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan" etc.
    Es muss das auszuwertende Reading über das Attribut <a href="#DbRep-attr-reading">reading</a>
    angegeben sein.
    Die Auswertung enthält den Zeitstempel des ermittelten Minimumwertes innerhalb der
    Aggregation bzw. Zeitgrenzen.
    Im Reading wird der Zeitstempel des <b>ersten</b> Auftretens vom Minimalwert ausgegeben
    falls dieser Wert im Intervall mehrfach erreicht wird. <br><br>

    Ist keine oder die Option <b>display</b> angegeben, werden die Ergebnisse nur angezeigt. Mit
    der Option <b>writeToDB</b> werden die Berechnungsergebnisse mit einem neuen Readingnamen
    in der Datenbank gespeichert. <br>
    Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet,
    wobei der originale Readingname durch das Attribut <a href="#DbRep-attr-readingNameMap">readingNameMap</a> ersetzt werden kann.
    Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
    Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode
    abgeleitet.
    Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>

    Wird die Option <b>deleteOther</b> verwendet, werden alle Datensätze außer dem Datensatz mit dem
    ermittelten Maximalwert aus der Datenbank innerhalb der definierten Grenzen gelöscht. <br><br>

    <ul>
      <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
      min_day_totalpac <br>
      # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>
    </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-multiCmd"></a>
    <li><b> multiCmd {&lt;Befehl-Hash&gt;}</b>  <br><br>

    Führt mehrere Set-Befehle sequentiell in einer definierbaren Reihenfolge aus. <br>
    Die Befehle und bestimmte veränderbare Attribute, die für die Befehle relevant sind, werden in einem
    Hash übergeben. In einem Script, z.B. einem at-Device, kann auch eine Variable übergeben werden die einen definierten
    Hash enthält.  <br>
    Die auszuführenden Befehle (Schlüssel <b>cmd</b>) und die dafür zu setzenden Attribute werden über Schlüssel im
    übergebenen Hash definiert. Die Festlegung der Abarbeitungsreihenfolge der Befehle erfolgt über den Befehl-Index im
    Hash.
    <br><br>

    Im Hash definierbare Attributschlüssel sind: <br>

    <ul>
      <a href="#DbRep-attr-autoForward">autoForward</a>,
      <a href="#DbRep-attr-averageCalcForm">averageCalcForm</a>,
      <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>,
      <a href="#DbRep-attr-timestamp_end">timestamp_end</a>,
      <a href="#DbRep-attr-timeDiffToNow">timeDiffToNow</a>,
      <a href="#DbRep-attr-timeOlderThan">timeOlderThan</a>,
      <a href="#DbRep-attr-timeYearPeriod">timeYearPeriod</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-reading">readingNameMap</a>,
    </ul>
    <br>

    <b>Beispiel für die Definition eines Befehl-Hashes: </b> <br>

    <ul>
      <pre>
        {
          1  => { timestamp_begin => '2023-12-17 00:00:00', 
                  timestamp_end   => '2023-12-17 01:00:00', 
                  device          => 'SMA_Energymeter', 
                  reading         => 'Einspeisung_Wirkleistung_Zaehler', 
                  cmd             => 'countEntries history'
                },
          2  => { timestamp_begin => '2023-12-15 11:00:00', 
                  timestamp_end   => 'previous_day_end', 
                  device          => 'SMA_Energymeter', 
                  reading         => 'Einspeisung_Wirkleistung_Zaehler', 
                  cmd             => 'countEntries' 
                },
          3  => { timeDiffToNow   => 'd:2',
                  readingNameMap  => 'COUNT',
                  autoForward     => '{ ".*COUNT.*" => "Dum.Rep.All" }',
                  device          => 'SMA_%,MySTP.*',
                  reading         => 'etotal,etoday,Ein% EXCLUDE=%Wirkleistung', 
                  cmd             => 'countEntries history' 
                },
          4  => { timeDiffToNow   => 'd:2',
                  readingNameMap  => 'SUM',
                  autoForward     => '{ ".*SUM.*" => "Dum.Rep.All" }',
                  device          => 'SMA_%,MySTP.*',
                  reading         => 'etotal,etoday,Ein% EXCLUDE=%Wirkleistung', 
                  cmd             => 'sumValue' 
                },
          5  => { cmd             => 'sqlCmd select count(*) from current'
                },
        }
      </pre>
    </ul>
    </li>
    <br>

    <a id="DbRep-set-optimizeTables"></a>
    <li><b> optimizeTables [showInfo | execute]</b> <br><br>

    Optimiert die Tabellen in der angeschlossenen Datenbank (MySQL). <br><br>

    <ul>
    <table>
     <colgroup> <col width=5%> <col width=95%> </colgroup>
        <tr><td> <b>showInfo</b>  </td><td>: zeigt Informationen zum belegten / freien Speicherplatz innerhalb der Datenbank   </td></tr>
        <tr><td> <b>execute</b>   </td><td>: führt die Optimierung aller Tabellen in der Datenbank aus                         </td></tr>
     </table>
    </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    </li>
    <br>

    <a id="DbRep-set-readingRename"></a>
    <li><b> readingRename &lt;[Device:]alterReadingname&gt;,&lt;neuerReadingname&gt; </b>  <br><br>

    Benennt den Namen eines Readings innerhalb der angeschlossenen Datenbank (siehe Internal DATABASE) um.
    Der Readingname wird immer in der <b>gesamten</b> Datenbank umgesetzt. Eventuell
    gesetzte Zeitgrenzen oder Beschränkungen durch die Attribute
    <a href="#DbRep-attr-device">device</a> bzw. <a href="#DbRep-attr-reading">reading</a> werden nicht berücksichtigt.  <br>
    Optional kann eine Device angegeben werden. In diesem Fall werden <b>nur</b> die alten Readings
    dieses Devices in den neuen Readingnamen umgesetzt.
    <br><br>

    <ul>
      <b>Beispiele: </b><br>
      set &lt;name&gt; readingRename TotalConsumption,L1_TotalConsumption  <br>
      set &lt;name&gt; readingRename Dum.Energy:TotalConsumption,L1_TotalConsumption  <br>
    </ul>
    <br>

    Die Anzahl der umbenannten Device-Datensätze wird im Reading "reading_renamed" ausgegeben. <br>
    Wird der umzubenennende Readingname in der Datenbank nicht gefunden, wird eine WARNUNG im Reading
    "reading_not_renamed" ausgegeben. <br>
    Entsprechende Einträge erfolgen auch im Logfile mit verbose=3.
    <br><br>

    Für diese Funktion sind folgende Attribute relevant: <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <li><b> reduceLog [&lt;no&gt;[:&lt;nn&gt;]] [mode] [EXCLUDE=device1:reading1,device2:reading2,...] [INCLUDE=device:reading] </b> <br><br>

    Reduziert historische Datensätze. <br><br>

    <b>Arbeitsweise ohne Angabe von Befehlszeilenoperatoren </b> <br><br>

    Es werden die Daten innerhalb der durch die <b>time.*</b>-Attribute bestimmten Zeitgrenzen bereinigt.
    Es muss mindestens eines der <b>time.*</b>-Attribute gesetzt sein (siehe Tabelle unten).
    Die jeweils fehlende Zeitabgrenzung wird in diesem Fall durch das Modul ermittelt. <br>
    Der Arbeitsmodus wird durch die optionale Angabe von <b>mode</b> bestimmt:
    <br><br>

    <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td> <b>ohne Angabe von mode</b>    </td><td>:&nbsp;die Daten werden auf den ersten Eintrag pro Stunde je Device & Reading reduziert                            </td></tr>
       <tr><td> <b>average</b>                 </td><td>:&nbsp;numerische Werte werden auf einen Mittelwert pro Stunde je Device & Reading reduziert, sonst wie ohne mode  </td></tr>
       <tr><td> <b>average=day</b>             </td><td>:&nbsp;numerische Werte werden auf einen Mittelwert pro Tag je Device & Reading reduziert, sonst wie ohne mode     </td></tr>
       <tr><td>                                </td><td>&nbsp;&nbsp;Die FullDay-Option (es werden immer volle Tage selektiert) wird impliziert verwendet.                  </td></tr>
       <tr><td> <b>max</b>                     </td><td>:&nbsp;numerische Werte werden auf den Maximalwert pro Stunde je Device & Reading reduziert, sonst wie ohne mode   </td></tr>
       <tr><td> <b>max=day</b>                 </td><td>:&nbsp;numerische Werte werden auf den Maximalwert pro Tag je Device & Reading reduziert, sonst wie ohne mode      </td></tr>
       <tr><td>                                </td><td>&nbsp;&nbsp;Die FullDay-Option (es werden immer volle Tage selektiert) wird impliziert verwendet.                  </td></tr>
       <tr><td> <b>min</b>                     </td><td>:&nbsp;numerische Werte werden auf den Minimalwert pro Stunde je Device & Reading reduziert, sonst wie ohne mode   </td></tr>
       <tr><td> <b>min=day</b>                 </td><td>:&nbsp;numerische Werte werden auf den Minimalwert pro Tag je Device & Reading reduziert, sonst wie ohne mode      </td></tr>
       <tr><td>                                </td><td>&nbsp;&nbsp;Die FullDay-Option (es werden immer volle Tage selektiert) wird impliziert verwendet.                  </td></tr>
       <tr><td> <b>sum</b>                     </td><td>:&nbsp;numerische Werte werden auf die Summe pro Stunde je Device & Reading reduziert, sonst wie ohne mode         </td></tr>
       <tr><td> <b>sum=day</b>                 </td><td>:&nbsp;numerische Werte werden auf die Summe pro Tag je Device & Reading reduziert, sonst wie ohne mode            </td></tr>
       <tr><td>                                </td><td>&nbsp;&nbsp;Die FullDay-Option (es werden immer volle Tage selektiert) wird impliziert verwendet.                  </td></tr>
    </table>
    </ul>
    <br>

    Mit den Attributen <b>device</b> und <b>reading</b> können die zu berücksichtigenden Datensätze eingeschlossen
    bzw. ausgeschlossen werden. Beide Eingrenzungen reduzieren die selektierten Daten und verringern den
    Ressourcenbedarf.
    Das Reading "reduceLogState" enthält das Ausführungsergebnis des letzten reduceLog-Befehls.  <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-numDecimalPlaces">numDecimalPlaces</a>,
      <a href="#DbRep-attr-timeOlderThan">timeOlderThan</a>,
      <a href="#DbRep-attr-timeDiffToNow">timeDiffToNow</a>,
      <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a>,
      <a href="#DbRep-attr-timestamp_end">timestamp_end</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

     <b>Beispiele: </b><br><br>
     <ul>
     attr &lt;name&gt; timeOlderThan d:200  <br>
     set &lt;name&gt; reduceLog <br>
     # Datensätze die älter als 200 Tage sind, werden auf den ersten Eintrag pro Stunde je Device & Reading
     reduziert.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:200  <br>
     set &lt;name&gt; reduceLog average=day <br>
     # Datensätze die neuer als 200 Tage sind, werden auf einen Eintrag pro Tag je Device & Reading
     reduziert.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:30  <br>
     attr &lt;name&gt; device TYPE=SONOSPLAYER EXCLUDE=Sonos_Kueche  <br>
     attr &lt;name&gt; reading room% EXCLUDE=roomNameAlias  <br>
     set &lt;name&gt; reduceLog <br>
     # Datensätze die neuer als 30 Tage sind, die Devices vom Typ SONOSPLAYER sind
     (außer Device "Sonos_Kueche"), die Readings mit "room" beginnen (außer "roomNameAlias"),
     werden auf den ersten Eintrag pro Stunde je Device & Reading reduziert.  <br>
     <br>

     attr &lt;name&gt; timeDiffToNow d:10 <br>
     attr &lt;name&gt; timeOlderThan d:5  <br>
     attr &lt;name&gt; device Luftdaten_remote  <br>
     set &lt;name&gt; reduceLog average <br>
     # Datensätze die älter als 5 und neuer als 10 Tage sind und DEVICE "Luftdaten_remote" enthalten,
     werden bereinigt. Numerische Werte einer Stunde werden auf einen Mittelwert reduziert <br>
     <br>
     </ul>
     <br>

     <b>Arbeitsweise mit Angabe von Befehlszeilenoperatoren </b> <br><br>

     Es werden Datensätze berücksichtigt die älter sind als <b>&lt;no&gt;</b> Tage und (optional) neuer sind als
     <b>&lt;nn&gt;</b> Tage.
     Der Arbeitsmodus wird durch die optionale Angabe von <b>mode</b> wie oben beschrieben bestimmt.
     <br><br>

     Die Zusätze "EXCLUDE" bzw. "INCLUDE" können ergänzt werden um device/reading Kombinationen in reduceLog auszuschließen
     bzw. einzuschließen und überschreiben die Einstellung der Attribute "device" und "reading", die in diesem Fall
     nicht beachtet werden.  <br>
     Die Angabe in "EXCLUDE" wird als <b>Regex</b> ausgewertet. Innerhalb von "INCLUDE" können <b>SQL-Wildcards</b>
     verwendet werden (weitere Informationen zu SQL-Wildcards siehe mit <b>get &lt;name&gt; versionNotes 6</b>).
     <br><br>

     <b>Beispiele: </b><br><br>
     <ul>
     set &lt;name&gt; reduceLog 174:180 average EXCLUDE=SMA_Energymeter:Bezug_Wirkleistung INCLUDE=SMA_Energymeter:% <br>
     # Datensätze älter als 174 und neuer als 180 Tage werden auf den Durchschnitt pro Stunde reduziert. <br>
     # Es werden alle Readings vom Device "SMA_Energymeter" außer "Bezug_Wirkleistung" berücksichtigt.
     reduziert.  <br>
     </ul>
     <br>

     <b>Hinweis:</b> <br>
     Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
     im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden
     (Tabellen-Lock). <br>
     Weiterhin wird dringend empfohlen den standard INDEX 'Search_Idx' in der Tabelle 'history'
     anzulegen ! <br>
     Die Abarbeitung dieses Befehls dauert unter Umständen (ohne INDEX) extrem lange. <br><br>

     </li>
     <br>

    <a id="DbRep-set-repairSQLite"></a>
    <li><b> repairSQLite [sec]</b>  <br><br>

    Repariert eine korrupte SQLite-Datenbank. <br><br>

    Eine Korruption liegt im Allgemeinen vor, wenn die Fehlermitteilung "database disk image is malformed"
    im state des DbLog-Devices erscheint.
    Wird dieses Kommando gestartet, wird das angeschlossene DbLog-Device zunächst automatisch für 10 Stunden
    (36000 Sekunden) von der Datenbank getrennt (Trennungszeit). Nach Abschluss der Reparatur erfolgt
    wieder eine sofortige Neuverbindung zur reparierten Datenbank. <br>
    Dem Befehl kann eine abweichende Trennungszeit (in Sekunden) als Argument angegeben werden. <br>
    Die korrupte Datenbank wird als &lt;database&gt;.corrupt im gleichen Verzeichnis gespeichert.
    <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Beispiel: </b><br>
    <ul>
      set &lt;name&gt; repairSQLite  <br>
      # Die Datenbank wird repariert, Trennungszeit beträgt 10 Stunden <br>
      set &lt;name&gt; repairSQLite 600 <br>
      # Die Datenbank wird repariert, Trennungszeit beträgt 10 Minuten
      <br><br>
    </ul>

    <b>Hinweis:</b> <br>
    Es ist nicht garantiert, dass die Reparatur erfolgreich verläuft und keine Daten verloren gehen.
    Je nach Schwere der Korruption kann Datenverlust auftreten oder die Reparatur scheitern, auch wenn
    kein Fehler im Ablauf signalisiert wird. Ein Backup der Datenbank sollte unbedingt vorhanden
    sein!
    <br><br>

    </li>
    <br>

    <a id="DbRep-set-restoreMySQL"></a>
    <li><b> restoreMySQL &lt;File&gt; </b>  <br><br>

    Stellt die Datenbank aus einem serverSide- oder clientSide-Dump wieder her. <br>
    Die Funktion stellt über eine Drop-Down Liste eine Dateiauswahl für den Restore zur Verfügung. <br><br>

    <b>Verwendung eines serverSide-Dumps </b> <br>
    Der verwendete Datenbankuser benötigt das <b>FILE</b> Privileg (siehe <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten#4._Restore_2">Wiki</a>). <br>
    Es wird der Inhalt der history-Tabelle aus einem serverSide-Dump wiederhergestellt.
    Dazu ist das Verzeichnis "dumpDirRemote" des MySQL-Servers auf dem Client zu mounten
    und im Attribut <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> dem DbRep-Device bekannt zu machen. <br>
    Es werden alle Files mit der Endung "csv[.gzip]" und deren Name mit der
    verbundenen Datenbank beginnt (siehe Internal DATABASE), aufgelistet.
    <br><br>

    <b>Verwendung eines clientSide-Dumps </b> <br>
    Es werden alle Tabellen und eventuell vorhandenen Views wiederhergestellt.
    Das Verzeichnis, in dem sich die Dump-Files befinden, ist im Attribut <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a> dem
    DbRep-Device bekannt zu machen. <br>
    Es werden alle Files mit der Endung "sql[.gzip]" und deren Name mit der
    verbundenen Datenbank beginnt (siehe Internal DATABASE), aufgelistet. <br>
    Die Geschwindigkeit des Restores ist abhängig von der Servervariable "<b>max_allowed_packet</b>". Durch Veränderung
    dieser Variable im File my.cnf kann die Geschwindigkeit angepasst werden. Auf genügend verfügbare Ressourcen (insbesondere
    RAM) ist dabei zu achten. <br><br>

    Der Datenbankuser benötigt Rechte zum Tabellenmanagement, z.B.: <br>
    CREATE, ALTER, INDEX, DROP, SHOW VIEW, CREATE VIEW
    <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-dumpDirLocal">dumpDirLocal</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-restoreSQLite"></a>
    <li><b> restoreSQLite &lt;File&gt;.sqlitebkp[.gzip] </b> <br><br>

    Stellt das Backup einer SQLite-Datenbank wieder her. <br>
    Die Funktion stellt über eine Drop-Down Liste die für den Restore zur Verfügung stehenden Dateien
    zur Verfügung. Die aktuell in der Zieldatenbank enthaltenen Daten werden gelöscht bzw.
    überschrieben.
    Es werden alle Files mit der Endung "sqlitebkp[.gzip]" und deren Name mit dem Namen der
    verbundenen Datenbank beginnt, aufgelistet.
    <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <li><b> sqlCmd </b> <br><br>

    Führt ein beliebiges benutzerspezifisches Kommando aus. <br>
    Enthält dieses Kommando eine Delete-Operation, muss zur Sicherheit das Attribut
    <a href="#DbRep-attr-allowDeletion">allowDeletion</a> gesetzt sein. <br>
    sqlCmd akzeptiert ebenfalls das Setzen von SQL Session Variablen wie z.B.
    "SET @open:=NULL, @closed:=NULL;" oder die Verwendung von SQLite PRAGMA vor der
    Ausführung des SQL-Statements.
    Soll die Session Variable oder das PRAGMA vor jeder Ausführung eines SQL Statements
    gesetzt werden, kann dafür das Attribut <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a>
    verwendet werden. <br><br>

    Sollen die im Modul gesetzten Attribute <a href="#DbRep-attr-device">device</a>, <a href="#DbRep-attr-reading">reading</a>,
    <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a> bzw.
    <a href="#DbRep-attr-timestamp_end">timestamp_end</a> im Statement berücksichtigt werden, können die Platzhalter
    <b>§device§</b>, <b>§reading§</b>, <b>§timestamp_begin§</b> bzw.
    <b>§timestamp_end§</b> eingesetzt werden. <br>
    Dabei ist zu beachten, dass die Platzhalter §device§ und §reading§ komplex aufgelöst werden
    und dementsprechend wie im unten stehenden Beispiel anzuwenden sind.
    <br><br>

    Soll ein Datensatz upgedated werden, ist dem Statement "TIMESTAMP=TIMESTAMP" hinzuzufügen um eine Änderung des
    originalen Timestamps zu verhindern. <br><br>

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
    <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where §device§ AND TIMESTAMP >= §timestamp_begin§ group by DEVICE  </li>
    <li>set &lt;name&gt; sqlCmd select DEVICE, READING, count(*) from history where §device§ AND §reading§ AND TIMESTAMP >= §timestamp_begin§ group by DEVICE, READING  </li>
    <br>

    Nachfolgend Beispiele für ein komplexeres Statement (MySQL) unter Mitgabe von
    SQL Session Variablen und die SQLite PRAGMA-Verwendung: <br><br>

    <li>set &lt;name&gt; sqlCmd SET @open:=NULL, @closed:=NULL;
           SELECT
               TIMESTAMP, VALUE,DEVICE,
               @open AS open,
               @open := IF(VALUE = 'open', TIMESTAMP, NULL) AS curr_open,
               @closed  := IF(VALUE = 'closed',  TIMESTAMP, NULL) AS closed
           FROM history WHERE
              DATE(TIMESTAMP) = CURDATE() AND
              DEVICE = "HT_Fensterkontakt" AND
              READING = "state" AND
              (VALUE = "open" OR VALUE = "closed")
              ORDER BY  TIMESTAMP; </li>
    <li>set &lt;name&gt; sqlCmd PRAGMA temp_store=MEMORY; PRAGMA synchronous=FULL; PRAGMA journal_mode=WAL; PRAGMA cache_size=4000; select count(*) from history; </li>
    <li>set &lt;name&gt; sqlCmd PRAGMA temp_store=FILE; PRAGMA temp_store_directory = '/opt/fhem/'; VACUUM; </li>
    </ul>
    <br>

    Die Ergebnis-Formatierung kann durch das Attribut <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a> ausgewählt,
    sowie der verwendete Feldtrenner durch das Attribut <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>
    festgelegt werden. <br><br>

    Das Modul stellt optional eine Kommando-Historie zur Verfügung sobald ein SQL-Kommando erfolgreich
    ausgeführt wurde.
    Um diese Option zu nutzen, ist das Attribut <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a> mit der
    gewünschten Listenlänge zu aktivieren. <br>
    Ist die Kommando-Historie aktiviert, ist mit <b>___list_sqlhistory___</b> innerhalb des Kommandos
    sqlCmdHistory eine indizierte Liste der gespeicherten SQL-Statements verfügbar. <br><br>

    Ein SQL-Statement kann durch Angabe seines Index im ausgeführt werden mit:
    <br><br>
      <ul>
        set &lt;name&gt; sqlCmd ckey:&lt;Index&gt;    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(e.g. ckey:4)
      </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>,
      <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Hinweis:</b> <br>
    Auch wenn das Modul bezüglich der Datenbankabfrage nichtblockierend arbeitet, kann eine
    zu große Ergebnismenge (Anzahl Zeilen bzw. Readings) die Browsersesssion bzw. FHEMWEB
    blockieren. <br>
    Wenn man sich unsicher ist, sollte man vorsorglich dem Statement ein Limit
    hinzufügen.
    <br><br>

    </li>
    <br>

    <a id="DbRep-set-sqlCmdHistory"></a>
    <li><b> sqlCmdHistory </b> <br><br>

    Wenn mit dem Attribut <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a> aktiviert, kann
    ein gespeichertes SQL-Statement aus einer Liste ausgewählt und ausgeführt werden. <br>
    Der SQL Cache wird beim Beenden von FHEM automatisch gesichert und beim Start des Systems wiederhergestellt. <br>
    Mit den nachfolgenden Einträgen werden spezielle Funktionen ausgeführt: <br>
    <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>___purge_sqlhistory___</b>   </td><td>: löscht den History Cache                                                           </td></tr>
       <tr><td> <b>___list_sqlhistory___ </b>   </td><td>: zeigt die aktuell im Cache vorhandenen SQL-Statements incl. ihrem Cache Key (ckey) </td></tr>
       <tr><td> <b>___save_sqlhistory___</b>    </td><td>: sichert den History Cache manuell                                                  </td></tr>
       <tr><td> <b>___restore_sqlhistory___</b> </td><td>: stellt die letzte Sicherung des History Cache wieder her                           </td></tr>
    </table>
    </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlCmdHistoryLength">sqlCmdHistoryLength</a>,
      <a href="#DbRep-attr-sqlCmdVars">sqlCmdVars</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-useAdminCredentials">useAdminCredentials</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    </li>
    <br>

    <a id="DbRep-set-sqlSpecial"></a>
    <li><b> sqlSpecial </b> <br><br>

    Die Funktion bietet eine Drop-Downliste mit einer Auswahl vorbereiter Auswertungen
    an. <br>
    Das Ergebnis des Statements wird im Reading "SqlResult" dargestellt.
    Die Ergebnis-Formatierung kann durch das Attribut <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>
    ausgewählt, sowie der verwendete Feldtrenner durch das Attribut <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>
    festgelegt werden. <br><br>

    <ul>
    <table>
    <colgroup> <col width=27%> <col width=73%> </colgroup>
       <tr><td> <b>50mostFreqLogsLast2days </b>       </td><td> ermittelt die 50 am häufigsten vorkommenden Loggingeinträge der letzten 2 Tage                   </td></tr>
       <tr><td> <b>allDevCount </b>                   </td><td> alle in der Datenbank vorkommenden Devices und deren Anzahl                                      </td></tr>
       <tr><td> <b>allDevReadCount </b>               </td><td> alle in der Datenbank vorkommenden Device/Reading-Kombinationen und deren Anzahl                 </td></tr>
       <tr><td> <b>50DevReadCount </b>                </td><td> die 50 am häufigsten in der Datenbank enthaltenen Device/Reading-Kombinationen                   </td></tr>
       <tr><td> <b>recentReadingsOfDevice </b>        </td><td> ermittelt die neuesten in der Datenbank vorhandenen Datensätze eines Devices. Das auszuwertende  </td></tr>
       <tr><td>                                       </td><td> Device muß im Attribut <a href="#DbRep-attr-device">device</a> definiert sein.                                                            </td></tr>
       <tr><td> <b>readingsDifferenceByTimeDelta </b> </td><td> ermittelt die Wertedifferenz aufeinanderfolgender Datensätze eines Readings. Das auszuwertende                                            </td></tr>
       <tr><td>                                       </td><td> Device und Reading muß im Attribut <a href="#DbRep-attr-device">device</a> bzw. <a href="#DbRep-attr-reading">reading</a> definiert sein. </td></tr>
       <tr><td>                                       </td><td> Die Zeitgrenzen der Auswertung werden durch die time.*-Attribute festgelegt.                                                              </td></tr>
    </table>
    </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-allowDeletion">allowDeletion</a>,
      <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a>,
      <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a>,
      <a href="#DbRep-attr-sqlFormatService">sqlFormatService</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    <br>

    </li>
    <br>

    <li><b> sumValue [display | writeToDB | writeToDBSingle | writeToDBInTime]</b> <br><br>

    Berechnet die Summenwerte des Datenbankfelds "VALUE" in den Zeitgrenzen
    der möglichen time.*-Attribute. <br><br>

    Es muss das auszuwertende Reading im Attribut <a href="#DbRep-attr-reading">reading</a>
    angegeben sein. <br>
    Diese Funktion ist sinnvoll wenn fortlaufend Wertedifferenzen eines
    Readings in die Datenbank geschrieben werden.  <br><br>

    Ist keine oder die Option <b>display</b> angegeben, werden die Ergebnisse nur angezeigt. <br>
    Mit den Optionen <b>writeToDB</b>, <b>writeToDBSingle</b> bzw. <b>writeToDBInTime</b> werden die
    Berechnungsergebnisse mit einem neuen Readingnamen in der Datenbank gespeichert. <br><br>

      <ul>
      <table>
      <colgroup> <col width=10%> <col width=90%> </colgroup>
         <tr><td> <b>writeToDB</b>         </td><td>: schreibt jeweils einen Wert mit den Zeitstempeln XX:XX:01 und XX:XX:59 innerhalb der jeweiligen Auswertungsperiode </td></tr>
         <tr><td> <b>writeToDBSingle</b>   </td><td>: schreibt nur einen Wert mit dem Zeitstempel XX:XX:59 am Ende einer Auswertungsperiode</td></tr>
         <tr><td> <b>writeToDBInTime</b>   </td><td>: schreibt jeweils einen Wert am Anfang und am Ende der Zeitgrenzen einer Auswertungsperiode </td></tr>
      </table>
      </ul>
      <br>

    Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet, <br>
    wobei der originale Readingname durch das Attribut "readingNameMap" ersetzt werden kann. <br>
    Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
    Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode abgeleitet, <br>
    sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann.
    Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>

    <ul>
      <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
      sum_day_totalpac <br>
      # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>
    </ul>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>
    <br>

    </li>
    <br>

    <li><b> syncStandby &lt;DbLog-Device Standby&gt; </b> <br><br>

    Es werden die Datensätze aus der angeschlossenen Datenbank (Quelle) direkt in eine weitere
    Datenbank (Standby-Datenbank) übertragen.
    Dabei ist "&lt;DbLog-Device Standby&gt;" das DbLog-Device, welches mit der Standby-Datenbank
    verbunden ist. <br><br>
    Es werden alle Datensätze übertragen, die durch das <a href="#DbRep-attr-timestamp_begin">timestamp_begin</a> Attribut
    bzw. die Attribute "device", "reading" bestimmt sind. <br>
    Die Datensätze werden dabei in Zeitscheiben entsprechend der eingestellten Aggregation übertragen.
    Hat das Attribut "aggregation" den Wert "no" oder "month", werden die Datensätze automatisch
    in Tageszeitscheiben zur Standby-Datenbank übertragen.
    Quell- und Standby-Datenbank können unterschiedlichen Typs sein.
    <br><br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-aggregation">aggregation</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-readingNameMap">readingNameMap</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>
    <br>

    </li>
    <br>

    <a id="DbRep-set-tableCurrentFillup"></a>
    <li><b> tableCurrentFillup </b> <br><br>

    Die current-Tabelle wird mit einem Extrakt der history-Tabelle aufgefüllt. <br>
    Die Attribute zur Zeiteinschränkung bzw. device, reading werden ausgewertet. <br>
    Dadurch kann der Inhalt des Extrakts beeinflusst werden. <br>
    Im zugehörigen DbLog-Device sollte das Attribut "DbLogType=SampleFill/History" gesetzt sein.
    <br>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-device">device</a>,
      <a href="#DbRep-attr-reading">reading</a>,
      <a href="#DbRep-attr-valueFilter">valueFilter</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>,
      time.*-Attribute
    </ul>
    <br>
    <br>

    </li>

    <a id="DbRep-set-tableCurrentPurge"></a>
    <li><b> tableCurrentPurge </b> <br><br>

    Löscht den Inhalt der current-Tabelle. <br>
    Es werden keine Limitierungen, z.B. durch die Attribute timestamp_begin,
    timestamp_end, device oder reading ausgewertet.
    <br>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>
    <br>

    </li>

    <a id="DbRep-set-vacuum"></a>
    <li><b> vacuum </b> <br><br>

    Optimiert die Tabellen in der angeschlossenen Datenbank (SQLite, PostgreSQL). <br>
    Insbesondere für SQLite Datenbanken ist unbedingt empfehlenswert die Verbindung des relevanten DbLog-Devices zur
    Datenbank vorübergehend zu schließen (siehe DbLog reopen Kommando).
    <br>
    <br>

    Relevante Attribute sind: <br>

    <ul>
      <a href="#DbRep-attr-executeBeforeProc">executeBeforeProc</a>,
      <a href="#DbRep-attr-executeAfterProc">executeAfterProc</a>,
      <a href="#DbRep-attr-userExitFn">userExitFn</a>
    </ul>
    <br>

    <b>Hinweis:</b> <br>
    Bei der Ausführung des vacuum Kommandos wird bei SQLite Datenbanken automatisch das PRAGMA <b>auto_vacuum = FULL</b>
    angewendet. <br>
    Das vacuum Kommando erfordert zusätzlichen temporären Speicherplatz. Sollte der Platz im Standard TMPDIR Verzeichnis
    nicht ausreichen, kann SQLite durch setzen der Umgebungsvariable <b>SQLITE_TMPDIR</b> ein ausreichend großes Verzeichnis
    zugewiesen werden. <br>
    (siehe: <a href="https://www.sqlite.org/tempfiles.html">www.sqlite.org/tempfiles</a>)
    </li>
    <br>
    <br>

   <br>
   </ul>
   </ul>

</ul>

<a id="DbRep-get"></a>
<b>Get </b>
<ul>

 Die Get-Kommandos von DbRep dienen dazu eine Reihe von Metadaten der verwendeten Datenbankinstanz abzufragen.
 Dies sind zum Beispiel eingestellte Serverparameter, Servervariablen, Datenbankstatus- und Tabelleninformationen. Die verfügbaren get-Funktionen
 sind von dem verwendeten Datenbanktyp abhängig. So ist für SQLite z.Zt. nur "svrinfo" verfügbar. Die Funktionen liefern nativ sehr viele Ausgabewerte,
 die über über funktionsspezifische Attribute abgrenzbar sind. Der Filter ist als kommaseparierte Liste anzuwenden.
 Dabei kann SQL-Wildcard (%) verwendet werden.
 <br><br>

 <b>Hinweis: </b> <br>
 Nach der Ausführung einer get-Funktion in der Detailsicht einen Browserrefresh durchführen um die Ergebnisse zu sehen !
 <br><br>


 <ul><ul>
    <a id="DbRep-get-blockinginfo"></a>
    <li><b> blockinginfo </b> - Listet die aktuell systemweit laufenden Hintergrundprozesse (BlockingCalls) mit ihren Informationen auf.
                                Zu lange Zeichenketten (z.B. Argumente) werden gekürzt ausgeschrieben.
                                </li>
                                <br><br>

    <a id="DbRep-get-dbstatus"></a>
    <li><b> dbstatus </b> -  Listet globale Informationen zum MySQL Serverstatus (z.B. Informationen zum Cache, Threads, Bufferpools, etc. ).
                             Es werden zunächst alle verfügbaren Informationen berichtet. Mit dem Attribut <a href="#DbRep-attr-showStatus">showStatus</a> kann die
                             Ergebnismenge eingeschränkt werden, um nur gewünschte Ergebnisse abzurufen. Detailinformationen zur Bedeutung der einzelnen Readings
                             sind <a href="http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html">hier</a> verfügbar.  <br><br>

                             <ul>
                               <b>Beispiel</b>  <br>
                               attr &lt;name&gt; showStatus %uptime%,%qcache%    <br>
                               get &lt;name&gt; dbstatus  <br>
                               # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthaltenen
                             </ul>
                             </li>
                             <br><br>

    <a id="DbRep-get-dbvars"></a>
    <li><b> dbvars </b> -  Zeigt die globalen Werte der MySQL Systemvariablen. Enthalten sind zum Beispiel Angaben zum InnoDB-Home, dem Datafile-Pfad,
                           Memory- und Cache-Parameter, usw. Die Ausgabe listet zunächst alle verfügbaren Informationen auf. Mit dem Attribut
                           <a href="#DbRep-attr-showVariables">showVariables</a> kann die Ergebnismenge eingeschränkt werden um nur gewünschte Ergebnisse
                           abzurufen. Weitere Informationen zur Bedeutung der ausgegebenen Variablen sind
                           <a href="http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html">hier</a> verfügbar. <br><br>

                           <ul>
                             <b>Beispiel</b>  <br>
                             attr &lt;name&gt; showVariables %version%,%query_cache%    <br>
                             get &lt;name&gt; dbvars  <br>
                             # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten
                           </ul>
                           </li>
                           <br><br>

    <a id="DbRep-get-initData"></a>
    <li><b> initData </b> - Ermittelt einige für die Funktion des Moduls relevante Datenbankeigenschaften.
                            Der Befehl wird bei der ersten Datenbankverbindung implizit ausgeführt.
                            </li>
                            <br><br>

    <a id="DbRep-get-minTimestamp"></a>
    <li><b> minTimestamp </b> - Ermittelt den Zeitstempel des ältesten Datensatzes in der Datenbank (wird implizit beim Start von
                                FHEM ausgeführt).
                                Der Zeitstempel wird als Selektionsbeginn verwendet wenn kein Zeitattribut den Selektionsbeginn
                                festlegt.
                                </li>
                                <br><br>

    <a id="DbRep-get-procinfo"></a>
    <li><b> procinfo </b> - Listet die existierenden Datenbank-Prozesse in einer Tabelle auf (nur MySQL). <br>
                            Typischerweise werden nur die Prozesse des Verbindungsusers (angegeben in DbLog-Konfiguration)
                            ausgegeben. Sollen alle Prozesse angezeigt werden, ist dem User das globale Recht "PROCESS"
                            einzuräumen. <br>
                            Für bestimmte SQL-Statements wird seit MariaDB 5.3 ein Fortschrittsreporting (Spalte "PROGRESS")
                            ausgegeben. Zum Beispiel kann der Abarbeitungsgrad bei der Indexerstellung verfolgt werden. <br>
                            Weitere Informationen sind
                            <a href="https://mariadb.com/kb/en/mariadb/show-processlist/">hier</a> verfügbar. <br>
                            </li>
                            <br><br>

    <a id="DbRep-get-sqlCmdBlocking"></a>
    <li><b> sqlCmdBlocking &lt;SQL-Statement&gt;</b> <br><br>

    Führt das angegebene SQL-Statement <b>blockierend</b> mit einem Standardtimeout von 10 Sekunden aus.
    Der Timeout kann mit dem Attribut <a href="#DbRep-attr-timeout">timeout</a> eingestellt werden.
    <br><br>

    <ul>
      <b>Beispiele:</b>  <br>
      { fhem("get &lt;name&gt; sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device") } <br>
      { CommandGet(undef,"Rep.LogDB1 sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device") } <br>
      get &lt;name&gt; sqlCmdBlocking select device,count(*) from history where timestamp > '2018-04-01' group by device  <br>
    </ul>
    </li>
    <br>

    Diese Funktion ist durch ihre Arbeitsweise speziell für den Einsatz in benutzerspezifischen Scripten geeignet. <br>
    Die Eingabe akzeptiert Mehrzeiler und gibt ebenso mehrzeilige Ergebisse zurück.
    Dieses Kommando akzeptiert ebenfalls das Setzen von SQL Session Variablen wie z.B.
    "SET @open:=NULL, @closed:=NULL;" oder PRAGMA für SQLite. <br>
    Werden mehrere Felder selektiert und zurückgegeben, erfolgt die Feldtrennung mit dem Trenner
    des Attributs <a href="#DbRep-attr-sqlResultFieldSep">sqlResultFieldSep</a> (default "|"). Mehrere Ergebniszeilen
    werden mit Newline ("\n") separiert. <br>
    Diese Funktion setzt/aktualisiert nur Statusreadings, die Funktion im Attribut  "userExitFn"
    wird nicht aufgerufen.
    <br><br>

    Erstellt man eine kleine Routine in 99_myUtils, wie z.B.:
    <br>

    <pre>
sub dbval {
  my $name = shift;
  my $cmd  = shift;
  my $ret  = CommandGet(undef,"$name sqlCmdBlocking $cmd");
  return $ret;
}
    </pre>

    kann sqlCmdBlocking vereinfacht verwendet werden mit Aufrufen wie:
    <br><br>

     <ul>
       <b>Beispiele:</b>  <br>
       { dbval("&lt;name&gt;","select count(*) from history") } <br>
       oder <br>
       $ret = dbval("&lt;name&gt;","select count(*) from history"); <br>
     </ul>

     <br><br>

    <a id="DbRep-get-storedCredentials"></a>
    <li><b> storedCredentials </b> - Listet die im Device gespeicherten User / Passworte für den Datenbankzugriff auf. <br>
                                   (nur gültig bei Datenbanktyp MYSQL)
                                   </li>
                                   <br><br>

    <a id="DbRep-get-svrinfo"></a>
    <li><b> svrinfo </b> -  allgemeine Datenbankserver-Informationen wie z.B. die DBMS-Version, Serveradresse und Port usw. Die Menge der Listenelemente
                            ist vom Datenbanktyp abhängig. Mit dem Attribut <a href="#DbRep-attr-showSvrInfo">showSvrInfo</a> kann die Ergebnismenge eingeschränkt werden.
                            Weitere Erläuterungen zu den gelieferten Informationen sind
                            <a href="https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx">hier</a> zu finden. <br><br>

                            <ul>
                              <b>Beispiel</b>  <br>
                              attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>
                              get &lt;name&gt; svrinfo  <br>
                              # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten
                            </ul>
                            </li>
                            <br><br>

    <a id="DbRep-get-tableinfo"></a>
    <li><b> tableinfo </b> -  ruft Tabelleninformationen aus der mit dem DbRep-Device verbundenen Datenbank ab (MySQL).
                              Es werden per default alle in der verbundenen Datenbank angelegten Tabellen ausgewertet.
                              Mit dem Attribut <a href="#DbRep-attr-showTableInfo">showTableInfo</a> können die Ergebnisse eingeschränkt werden. Erläuterungen zu den erzeugten
                              Readings sind  <a href="http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html">hier</a> zu finden.  <br><br>

                              <ul>
                                <b>Beispiel</b>  <br>
                                attr &lt;name&gt; showTableInfo current,history   <br>
                                get &lt;name&gt; tableinfo  <br>
                                # Es werden nur Information der Tabellen "current" und "history" angezeigt
                              </ul>
                              </li>
                              <br><br>

    <a id="DbRep-get-versionNotes"></a>
    <li><b> versionNotes [hints | rel | &lt;key&gt;] </b> -
                             Zeigt Release Informationen und/oder Hinweise zum Modul an.
                             <br><br>

                             <ul>
                              <table>
                              <colgroup> <col width=5%> <col width=95%> </colgroup>
                                  <tr><td> rel          </td><td>: zeigt nur Release Informationen                           </td></tr>
                                  <tr><td> hints        </td><td>: zeigt nur Hinweise an                                     </td></tr>
                                  <tr><td> &lt;key&gt;  </td><td>: es wird der Hinweis mit der angegebenen Nummer angezeigt  </td></tr>
                              </table>
                             </ul>

                             </li>

                             <br>
                             Sind keine Optionen angegeben, werden sowohl Release Informationen als auch Hinweise angezeigt.
                             Es sind nur Release Informationen mit Bedeutung für den Modulnutzer enthalten. <br>


  <br>
  </ul></ul>

</ul>


<a id="DbRep-attr"></a>
<b>Attribute</b>

<br>
<ul>
  Über die modulspezifischen Attribute wird die Abgrenzung der Auswertung und die Aggregation der Werte gesteuert. <br>
  Die hier aufgeführten Attribute sind nicht für jede Funktion des Moduls bedeutsam. In der Hilfe zu den set/get-Kommandos
  wird explizit angegeben, welche Attribute für das jeweilige Kommando relevant sind. <br><br>

  <b>Hinweis zur SQL-Wildcard Verwendung:</b> <br>
  Innerhalb der Attribut-Werte für "device" und "reading" kann SQL-Wildcards "%" angegeben werden.
  Dabei wird "%" als Platzhalter für beliebig viele Zeichen verwendet.
  Das Zeichen "_" wird nicht als SQL-Wildcard supported.  <br>
  Dies gilt für alle Funktionen <b>ausser</b> "insert", "importFromFile" und "deviceRename". <br>
  Die Funktion "insert" erlaubt nicht, dass die genannten Attribute das Wildcard "%" enthalten. Character "_" wird als normales Zeichen gewertet.<br>
  In Ergebnis-Readings wird das Wildcardzeichen "%" durch "/" ersetzt um die Regeln für erlaubte Zeichen in Readings einzuhalten.
  <br><br>

  <ul><ul>
  <a id="DbRep-attr-aggregation"></a>
  <li><b>aggregation </b> <br><br>
  
  Erstellung der Funktionsergebnisse in Zeitscheiben innerhalb des Selektionszeitraumes. 
  <br><br>
  
  <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> no      </td><td>- keine Aggregation (default)                                       </td></tr>
        <tr><td> minute  </td><td>- die Funktionsergebnisse werden pro Minute zusammengefasst         </td></tr>
        <tr><td> hour    </td><td>- die Funktionsergebnisse werden pro Stunde zusammengefasst         </td></tr>
        <tr><td> day     </td><td>- die Funktionsergebnisse werden pro Kalendertag zusammengefasst    </td></tr>
        <tr><td> week    </td><td>- die Funktionsergebnisse werden pro Kalenderwoche zusammengefasst  </td></tr>
        <tr><td> month   </td><td>- die Funktionsergebnisse werden pro Kalendermonat zusammengefasst  </td></tr>
        <tr><td> year    </td><td>- die Funktionsergebnisse werden pro Kalenderjahr zusammengefasst   </td></tr>
    </table>
  </ul>
  </li> 
  <br>

  <a id="DbRep-attr-allowDeletion"></a>
  <li><b>allowDeletion </b> <br><br>
  
  Schaltet die Löschfunktion des Moduls frei.
  </li> 
  <br>

  <a id="DbRep-attr-autoForward"></a>
  <li><b>autoForward </b> <br><br>
  Wenn aktiviert, werden die Ergebnisreadings einer Funktion in ein oder mehrere Devices
  übertragen. <br>
  Die Definition erfolgt in der Form: <br>

  <pre>
   {
    "&lt;source-reading&gt;" => "&lt;dest.device&gt; [=> &lt;dest.-reading&gt;]",
    "&lt;source-reading&gt;" => "&lt;dest.device&gt; [=> &lt;dest.-reading&gt;]",
    ...
   }
  </pre>

  In der Angabe <b>&lt;source-reading&gt;</b> sind Wildcards (.*) erlaubt. <br><br>

  <b>Beispiel:</b>
  <pre>
   {
    ".*"        => "Dum.Rep.All",
    ".*AVGAM.*" => "Dum.Rep     => average",
    ".*SUM.*"   => "Dum.Rep.Sum => summary",
   }
   # alle Readings werden zum Device "Dum.Rep.All" übertragen, Readingname bleibt im Ziel erhalten
   # Readings mit "AVGAM" im Namen werden zum Device "Dum.Rep" in das Reading "average" übertragen
   # Readings mit "SUM" im Namen werden zum Device "Dum.Rep.Sum" in das Reading "summary" übertragen
  </pre>
  </li> 
  <br>

  <a id="DbRep-attr-averageCalcForm"></a>
  <li><b>averageCalcForm </b> <br><br>

  Legt die Berechnungsvariante für die Ermittlung des Durchschnittswertes mit "averageValue" fest.
  <br><br>

  Zur Zeit sind folgende Varianten implementiert: <br><br>

  <ul>
     <table>
     <colgroup> <col width=20%> <col width=80%> </colgroup>
        <tr><td> <b>avgArithmeticMean:</b>      </td><td>Es wird der arithmetische Mittelwert berechnet. (default)                                     </td></tr>
        <tr><td>                                </td><td>                                                                                              </td></tr>
        <tr><td> <b>avgDailyMeanGWS:</b>        </td><td>Berechnet die Tagesmitteltemperatur entsprechend den                                          </td></tr>
        <tr><td>                                </td><td>Vorschriften des deutschen Wetterdienstes. (siehe "get &lt;name&gt; versionNotes 2")          </td></tr>
        <tr><td>                                </td><td>Diese Variante verwendet automatisch die Aggregation "day".                                   </td></tr>
        <tr><td>                                </td><td>                                                                                              </td></tr>
        <tr><td> <b>avgDailyMeanGWSwithGTS:</b> </td><td>Wie "avgDailyMeanGWS" und berechnet zusätzlich die Grünlandtemperatursumme.                   </td></tr>
        <tr><td>                                </td><td>Ist der Wert 200 erreicht, wird das Reading "reachedGTSthreshold" mit dem Datum               </td></tr>
        <tr><td>                                </td><td>des erstmaligen Erreichens dieses Schwellenwertes erstellt.                                   </td></tr>
        <tr><td>                                </td><td><b>Hinweis:</b> Das Attribut timestamp_begin muss auf den Beginn eines Jahres gesetzt werden! </td></tr>
        <tr><td>                                </td><td>(siehe "get &lt;name&gt; versionNotes 5")                                                     </td></tr>
        <tr><td>                                </td><td>                                                                                              </td></tr>
        <tr><td> <b>avgTimeWeightMean:</b>      </td><td>Berechnet den zeitgewichteten Mittelwert.                                                     </td></tr>
        <tr><td>                                </td><td><b>Hinweis:</b> Es müssen mindestens zwei Datenpunkte pro aggregation Periode vorhanden sein. </td></tr>
     </table>
  </ul>
  </li>
  <br>

  <a id="DbRep-attr-countEntriesDetail"></a>
  <li><b>countEntriesDetail </b> <br><br>
  
  Wenn gesetzt, erstellt die Funktion "countEntries" eine detallierte Ausgabe der Datensatzzahl
  pro Reading und Zeitintervall.
  Standardmäßig wird nur die Summe aller selektierten Datensätze ausgegeben.
  </li> 
  <br>

 <a id="DbRep-attr-device"></a>
 <li><b>device </b>           - Abgrenzung der DB-Selektionen auf ein bestimmtes oder mehrere Devices. <br>
                                Es können Geräte-Spezifikationen (devspec) angegeben werden. <br>
                                In diesem Fall werden die Devicenamen vor der Selektion aus der Geräte-Spezifikationen und den aktuell in FHEM
                                vorhandenen Devices aufgelöst. <br>
                                Wird dem Device bzw. der Device-Liste oder Geräte-Spezifikation ein "EXCLUDE=" vorangestellt,
                                werden diese Devices von der Selektion ausgeschlossen. <br>
                                Die Datenbankselektion wird als logische UND-Verknüpfung aus "device" und dem Attribut
                                <a href="#DbRep-attr-reading">reading</a> ausgeführt.
                                <br><br>

                                <ul>
                                <b>Beispiele:</b> <br>
                                <code>attr &lt;name&gt; device TYPE=DbRep </code> <br>
                                <code>attr &lt;name&gt; device MySTP_5000 </code> <br>
                                <code>attr &lt;name&gt; device SMA.*,MySTP.* </code> <br>
                                <code>attr &lt;name&gt; device SMA_Energymeter,MySTP_5000 </code> <br>
                                <code>attr &lt;name&gt; device %5000 </code> <br>
                                <code>attr &lt;name&gt; device TYPE=SSCam EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device TYPE=SSCam,TYPE=ESPEasy EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device EXCLUDE=SDS1_SVS </code> <br>
                                <code>attr &lt;name&gt; device EXCLUDE=TYPE=SSCam </code> <br>
                                </ul>

                                <br>
                                Falls weitere Informationen zu Geräte-Spezifikationen benötigt werden, bitte
                                "get &lt;name&gt; versionNotes 3" ausführen.
                                <br><br>
                                </li>

  <a id="DbRep-attr-diffAccept"></a>
  <li><b>diffAccept [+-]&lt;Schwellenwert&gt; </b> <br><br>

  diffAccept legt für die Funktion diffValue fest, bis zu welchem &lt;Schwellenwert&gt; eine
  Werte-Differenz zwischen zwei unmittelbar aufeinander folgenden Datensätzen akzeptiert werden. <br>
  Wird dem Schwellenwert <b>+-</b> (optional) vorangestellt, werden sowohl positive als auch negative Differenzen
  ausgewertet.
  <br><br>

  (default: 20, nur positive Differenzen zwischen Vorgänger und Nachfolger)
  <br><br>

  <ul>
    <b>Beispiel: </b> <br>
    attr <Name> diffAccept +-10000
  </ul>
  <br>

  Bei Schwellenwertüberschreitungen wird das Reading <b>diff_overrun_limit_&lt;Schwellenwert&gt;</b>
  erstellt. <br>
  Es enthält eine Liste der relevanten Wertepaare. Mit verbose 3 werden diese Datensätze ebenfalls im Logfile protokolliert.
  <br><br>

  <ul>
    <b>Beispiel Ausgabe im Logfile beim Überschreiten von diffAccept=10:</b> <br><br>

    DbRep Rep.STP5000.etotal -> data ignored while calc diffValue due to threshold overrun (diffAccept = 10): <br>
    2016-04-09 08:50:50 0.0340 -> 2016-04-09 12:42:01 13.3440 <br><br>

    # Der Differenz zwischen dem ersten Datensatz mit einem Wert von 0.0340 zum nächsten Wert 13.3440 ist untypisch hoch
    und führt zu einem zu hohen Differenzwert. <br>
    # Es ist zu entscheiden ob der Datensatz gelöscht, ignoriert, oder das Attribut diffAccept angepasst werden sollte.
  </ul>

  <br>
  </li>

  <a id="DbRep-attr-dumpComment"></a>
  <li><b>dumpComment </b> <br>
  Benutzer spezifischer Kommentar, welcher im Kopf der durch "dumpMyQL clientSide" erzeugten Datei
  eingetragen wird.
  </li>
  <br>

  <a id="DbRep-attr-dumpCompress"></a>
  <li><b>dumpCompress </b> <br>
  Wenn gesetzt, wird die durch "dumpMySQL" bzw. "dumpSQLite" erzeugte Datei anschließend komprimiert und die
  unkomprimierte Quellendatei gelöscht.
  </li>
  <br>

  <a id="DbRep-attr-dumpDirLocal"></a>
  <li><b>dumpDirLocal </b>  <br><br>

  <ul>
    Zielverzeichnis für die Erstellung von Dumps mit "dumpMySQL clientSide" oder "dumpSQLite".  <br>

    Durch Setzen dieses Attributes wird die interne Versionsverwaltung aktiviert.
    In diesem Verzeichnis werden Backup Dateien gesucht und gelöscht wenn die gefundene Anzahl den Attributwert
    "dumpFilesKeep" überschreitet.
    Mit dem Attribut wird ebenfalls ein lokal gemountetes Verzeichnis "dumpDirRemote" (bei dumpMySQL serverSide)
    DbRep bekannt gemacht. <br>

    (default: {global}{modpath}/log/)
    <br><br>

    <b>Beispiel: </b> <br>
    attr &lt;Name&gt; dumpDirLocal /sds1/backup/dumps_FHEM/

  <br>
  <br>
  </ul>
  </li>

  <a id="DbRep-attr-dumpDirRemote"></a>
  <li><b>dumpDirRemote </b> <br><br>
  <ul>
    Zielverzeichnis für die Erstellung von Dumps mit "dumpMySQL serverSide". <br>
    (default: das Home-Dir des MySQL-Servers auf dem MySQL-Host)
  <br>
  <br>
  </ul>
  </li>

  <a id="DbRep-attr-dumpMemlimit"></a>
  <li><b>dumpMemlimit </b>    - erlaubter Speicherverbrauch für das Dump SQL-Script zur Generierungszeit (default: 100000 Zeichen).
                                Bitte den Parameter anpassen, falls es zu Speicherengpässen und damit verbundenen Performanceproblemen
                                kommen sollte. </li> <br>

  <a id="DbRep-attr-dumpSpeed"></a>
  <li><b>dumpSpeed </b>       - Anzahl der abgerufenen Zeilen aus der Quelldatenbank (default: 10000) pro Select durch "dumpMySQL ClientSide".
                                Dieser Parameter hat direkten Einfluß auf die Laufzeit und den Ressourcenverbrauch zur Laufzeit.  </li> <br>

  <a id="DbRep-attr-dumpFilesKeep"></a>
  <li><b>dumpFilesKeep </b>   <br><br>
  <ul>
    Die integrierte Versionsverwaltung belässt die angegebene Anzahl Backup Dateien im Backup Verzeichnis. <br>
    Die Versionsverwaltung muß durch Setzen des Attributs "dumpDirLocal" eingeschaltet sein. <br>
    Sind mehr (ältere) Backup Dateien vorhanden, werden diese gelöscht nachdem ein neues Backup erfolgreich erstellt wurde.
    Das globale Attribut "archivesort" wird berücksichtigt. <br>
    (default: 3)

  <br>
  <br>
  </ul>
  </li>

  <a id="DbRep-attr-executeAfterProc"></a>
  <li><b>executeAfterProc </b> <br><br>

  Es kann ein FHEM-Kommando oder Perl Code angegeben werden der <b>nach der Befehlsabarbeitung</b> ausgeführt
  werden soll. <br>
  Perl Code ist in {...} einzuschließen. Es stehen die Variablen $hash (Hash des DbRep Devices) und $name
  (Name des DbRep-Devices) zur Verfügung. <br><br>

  <ul>
    <b>Beispiel:</b> <br><br>
    attr &lt;name&gt; executeAfterProc set og_gz_westfenster off; <br>
    attr &lt;name&gt; executeAfterProc {adump ($name)} <br><br>

    # "adump" ist eine in 99_myUtils definierte Funktion. <br>

<pre>
sub adump {
    my ($name) = @_;
    my $hash   = $defs{$name};
    # die eigene Funktion, z.B.
    Log3($name, 3, "DbRep $name -> Dump ist beendet");

    return;
}
</pre>
  </ul>
  </li>

  <a id="DbRep-attr-executeBeforeProc"></a>
  <li><b>executeBeforeProc </b> <br><br>

  Es kann ein FHEM-Kommando oder Perl Code angegeben werden der <b>vor der Befehlsabarbeitung</b> ausgeführt
  werden soll. <br>
  Perl Code ist in {...} einzuschließen. Es stehen die Variablen $hash (Hash des DbRep Devices) und $name
  (Name des DbRep-Devices) zur Verfügung. <br><br>

  <ul>
    <b>Beispiel:</b> <br><br>
    attr &lt;name&gt; executeBeforeProc set og_gz_westfenster on; <br>
    attr &lt;name&gt; executeBeforeProc {bdump ($name)}           <br><br>

    # "bdump" ist eine in 99_myUtils definierte Funktion. <br>

<pre>
sub bdump {
    my ($name) = @_;
    my $hash   = $defs{$name};
    # die eigene Funktion, z.B.
    Log3($name, 3, "DbRep $name -> Dump startet");

    return;
}
</pre>
   </ul>
   </li>

  <a id="DbRep-attr-expimpfile"></a>
  <li><b>expimpfile &lt;/Pfad/Filename&gt; [MAXLINES=&lt;lines&gt;]</b>
                                - Pfad/Dateiname für Export/Import in/aus einem File.  <br><br>

                                Optional kann über den Parameter "MAXLINES" die maximale Anzahl von Datensätzen angegeben
                                werden, die in ein File exportiert werden. In diesem Fall werden mehrere Files mit den
                                Extensions "_part1", "_part2", "_part3" usw. erstellt. <br>
                                Der Dateiname kann Platzhalter enthalten die gemäß der nachfolgenden Tabelle ersetzt werden.
                                Weiterhin können %-wildcards der POSIX strftime-Funktion des darunterliegenden OS enthalten
                                sein (siehe auch strftime Beschreibung). <br>
                                <br>

                                <ul>
                                  <table>
                                  <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> %L    </td><td>: wird ersetzt durch den Wert des global logdir Attributs </td></tr>
                                      <tr><td> %TSB  </td><td>: wird ersetzt durch den (berechneten) Wert des Starttimestamps der Datenselektion </td></tr>
                                      <tr><td>       </td><td>  </td></tr>
                                      <tr><td>       </td><td> <b>Allgemein gebräuchliche POSIX-Wildcards sind:</b> </td></tr>
                                      <tr><td> %d    </td><td>: Tag des Monats (01..31) </td></tr>
                                      <tr><td> %m    </td><td>: Monat (01..12) </td></tr>
                                      <tr><td> %Y    </td><td>: Jahr (1970...) </td></tr>
                                      <tr><td> %w    </td><td>: Wochentag (0..6); beginnend mit Sonntag (0) </td></tr>
                                      <tr><td> %j    </td><td>: Tag des Jahres (001..366) </td></tr>
                                      <tr><td> %U    </td><td>: Wochennummer des Jahres, wobei Wochenbeginn = Sonntag (00..53) </td></tr>
                                      <tr><td> %W    </td><td>: Wochennummer des Jahres, wobei Wochenbeginn = Montag (00..53) </td></tr>
                                  </table>
                                </ul>
                                <br>

                                <ul>
                                <b>Beispiele:</b> <br>
                                <code>attr &lt;name&gt; expimpfile /sds1/backup/exptest_%TSB.csv     </code> <br>
                                <code>attr &lt;name&gt; expimpfile /sds1/backup/exptest_%Y-%m-%d.csv </code> <br>
                                </ul>
                                <br>

                                Zur POSIX Wildcardverwendung siehe auch die Erläuterungen zum Filelog Modul.
                                <br><br>
                                </li>

  <a id="DbRep-attr-fastStart"></a>
  <li><b>fastStart </b>       - Normalerweise verbindet sich jedes DbRep-Device beim FHEM-Start kurz mit seiner Datenbank um
                                benötigte Informationen abzurufen und das Reading "state" springt bei Erfolg auf "connected".
                                Ist dieses Attribut gesetzt, erfolgt die initiale Datenbankverbindung erst dann wenn das
                                DbRep-Device sein erstes Kommando ausführt. <br>
                                Das Reading "state" verbleibt nach FHEM-Start solange im Status "initialized". <br>
                                (default: 1 für TYPE Client)
                                </li> <br>

  <a id="DbRep-attr-fetchMarkDuplicates"></a>
  <li><b>fetchMarkDuplicates </b>
                              - Markierung von mehrfach vorkommenden Datensätzen im Ergebnis des "fetchrows" Kommandos </li> <br>

  <a id="DbRep-attr-fetchRoute"></a>
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

  <a id="DbRep-attr-fetchValueFn"></a>
  <li><b>fetchValueFn </b>      - Der angezeigte Wert des Datenbankfeldes VALUE kann vor der Erstellung des entsprechenden
                                Readings geändert werden. Das Attribut muss eine Perl Funktion eingeschlossen in {}
                                enthalten. <br>
                                Der Wert des Datenbankfeldes VALUE wird in der Variable $VALUE zur Verfügung gestellt. <br><br>

                                <ul>
                                <b>Beispiel:</b> <br>
                                attr &lt;name&gt; fetchValueFn { $VALUE =~ s/^.*Used:\s(.*)\sMB,.*/$1." MB"/e } <br>

                                # Von einer langen Ausgabe wird ein spezifisches Zeichenmuster extrahiert und als VALUE
                                anstatt der gesamten Zeile im Reading angezeigt.
                                </ul>
                                </li> <br><br>

  <a id="DbRep-attr-ftpUse"></a>
  <li><b>ftpUse </b>          - FTP Transfer nach einem Dump wird eingeschaltet (ohne SSL Verschlüsselung). Das erzeugte
                                Datenbank Backupfile wird non-blocking zum angegebenen FTP-Server (Attribut "ftpServer")
                                übertragen. </li> <br>

  <a id="DbRep-attr-ftpUseSSL"></a>
  <li><b>ftpUseSSL </b>       - FTP Transfer mit SSL Verschlüsselung nach einem Dump wird eingeschaltet. Das erzeugte
                                Datenbank Backupfile wird non-blocking zum angegebenen FTP-Server (Attribut "ftpServer")
                                übertragen. </li> <br>

  <a id="DbRep-attr-ftpUser"></a>
  <li><b>ftpUser </b>         - User zur Anmeldung am FTP-Server nach einem Dump, default: "anonymous". </li> <br>

  <a id="DbRep-attr-ftpDebug"></a>
  <li><b>ftpDebug </b>        - Debugging der FTP Kommunikation zur Fehlersuche. </li> <br>

  <a id="DbRep-attr-ftpDir"></a>
  <li><b>ftpDir </b>          - Verzeichnis des FTP-Servers in welches das File nach einem Dump übertragen werden soll
                                (default: "/"). </li> <br>

  <a id="DbRep-attr-ftpDumpFilesKeep"></a>
  <li><b>ftpDumpFilesKeep </b> - Es wird die angegebene Anzahl Dumpfiles im &lt;ftpDir&gt; belassen (default: 3). Sind mehr
                                 (ältere) Dumpfiles vorhanden, werden diese gelöscht nachdem ein neuer Dump erfolgreich
                                 übertragen wurde. </li> <br>

  <a id="DbRep-attr-ftpPassive"></a>
  <li><b>ftpPassive </b>      - setzen wenn passives FTP verwendet werden soll </li> <br>

  <a id="DbRep-attr-ftpPort"></a>
  <li><b>ftpPort </b>         - FTP-Port, default: 21 </li> <br>

  <a id="DbRep-attr-ftpPwd"></a>
  <li><b>ftpPwd </b>          - Passwort des FTP-Users, default nicht gesetzt </li> <br>

  <a id="DbRep-attr-ftpServer"></a>
  <li><b>ftpServer </b>       - Name oder IP-Adresse des FTP-Servers zur Übertragung von Files nach einem Dump. </li> <br>

  <a id="DbRep-attr-ftpTimeout"></a>
  <li><b>ftpTimeout </b>      - Timeout für eine FTP-Verbindung in Sekunden (default: 30). </li> <br>

  <a id="DbRep-attr-limit"></a>
  <li><b>limit </b>           - begrenzt die Anzahl der resultierenden Datensätze im select-Statement von "fetchrows", bzw. der anzuzeigenden Datensätze
                                der Kommandos "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" (default 1000).
                                Diese Limitierung soll eine Überlastung der Browsersession und ein
                                blockieren von FHEMWEB verhindern. Bei Bedarf entsprechend ändern bzw. die
                                Selektionskriterien (Zeitraum der Auswertung) anpassen. </li> <br>

  <a id="DbRep-attr-numDecimalPlaces"></a>
  <li><b>numDecimalPlaces </b>  - Legt die Anzahl der Nachkommastellen bei Readings mit numerischen Ergebnissen fest. <br>
                                  Ausgenommen sind Ergebnisse aus userspezifischen Abfragen (sqlCmd). <br>
                                  (default: 4)
                                  </li> <br>

  <a id="DbRep-attr-optimizeTablesBeforeDump"></a>
  <li><b>optimizeTablesBeforeDump </b>  - wenn "1", wird vor dem Datenbankdump eine Tabellenoptimierung ausgeführt (default: 0).
                                          Dadurch verlängert sich die Laufzeit des Dump. <br><br>
                                          <ul>
                                          <b>Hinweis </b> <br>
                                          Die Tabellenoptimierung führt zur Sperrung der Tabellen und damit zur Blockierung von
                                          FHEM falls DbLog nicht im asynchronen Modus (DbLog-Attribut "asyncMode") betrieben wird !
                                          <br>
                                          </ul>
                                          </li> <br>

  <a id="DbRep-attr-reading"></a>
  <li><b>reading </b>         - Abgrenzung der DB-Selektionen auf ein bestimmtes oder mehrere Readings sowie exkludieren von
                                Readings.
                                Mehrere Readings werden als Komma separierte Liste angegeben.
                                Es können SQL Wildcard (%) verwendet werden. <br>
                                Wird dem Reading bzw. der Reading-Liste ein "EXCLUDE=" vorangestellt, werden diese Readings
                                nicht inkludiert. <br>
                                Die Datenbankselektion wird als logische UND Verknüpfung aus "reading" und dem Attribut
                                <a href="#DbRep-attr-device">device</a> ausgeführt.
                                <br><br>

                                <ul>
                                <b>Beispiele:</b> <br>
                                <code>attr &lt;name&gt; reading etotal</code> <br>
                                <code>attr &lt;name&gt; reading et%</code> <br>
                                <code>attr &lt;name&gt; reading etotal,etoday</code> <br>
                                <code>attr &lt;name&gt; reading eto%,Einspeisung EXCLUDE=etoday  </code> <br>
                                <code>attr &lt;name&gt; reading etotal,etoday,Ein% EXCLUDE=%Wirkleistung  </code> <br>
                                </ul>
                                <br><br>
                                </li>

  <a id="DbRep-attr-readingNameMap"></a>
  <li><b>readingNameMap </b> <br><br>
  
  Der Teil zwischen dem ersten und letzten doppelten Unterstrich ('__') des erstellten Readingnamens wird mit dem 
  angegebenen String ersetzt.  
  </li> 
  <br>

  <a id="DbRep-attr-readingPreventFromDel"></a>
  <li><b>readingPreventFromDel </b> <br><br>
  
  Komma separierte Liste von Readings die vor einer neuen Operation nicht gelöscht werden sollen. <br>
  Die Readings können als regulärer Ausdruck angegeben werden. <br>
  (default: state)
  <br><br>
  
  <ul>
    <b>Beispiel:</b> <br>
    attr &lt;name&gt; readingPreventFromDel .*Count.*,.*Summary1.*,.*Summary2.*
  </ul>
  </li> 
  <br>

  <a id="DbRep-attr-role"></a>
  <li><b>role </b> <br><br>
  
  Die Rolle des DbRep-Device. Standard ist "Client". 
  Die Rolle "Agent" ist im Abschnitt <a href="#DbRep-autorename">DbRep-Agent</a> beschrieben. <br>
  </li> 
  <br>

  <a id="DbRep-attr-seqDoubletsVariance"></a>
  <li><b>seqDoubletsVariance  &lt;positive Abweichung [negative Abweichung] [EDGE=negative|positive]&gt; </b> <br><br>

  Akzeptierte Abweichung für das Kommando "set &lt;name&gt; delSeqDoublets". <br>
  Der Wert des Attributs beschreibt die Abweichung bis zu der aufeinanderfolgende numerische
  Werte (VALUE) von Datensätzen als gleich angesehen werden sollen.
  Ist in "seqDoubletsVariance" nur ein Zahlenwert angegeben, wird er sowohl als positive als
  auch negative Abweichung verwendet und bilden den "Löschkorridor".
  Optional kann ein zweiter Zahlenwert für eine negative Abweichung, getrennt durch
  Leerzeichen, angegeben werden.
  Es sind immer absolute, d.h. positive Zahlenwerte anzugeben. <br>
  Ist der Zusatz "EDGE=negative" angegeben, werden Werte an einer negativen Flanke
  (z.B. beim Wechel von 4.0 -&gt; 1.0) nicht gelöscht auch wenn sie sich im "Löschkorridor"
  befinden. Entsprechendes gilt bei "EDGE=positive" für die positive Flanke (z.B. beim Wechel
  von 1.2 -&gt; 2.8).
  <br><br>

  <ul>
    <b>Beispiele:</b> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 0.0014  </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 1.45    </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 3.0 2.0 </code> <br>
    <code>attr &lt;name&gt; seqDoubletsVariance 1.5 EDGE=negative </code> <br>
  </ul>
  <br>
  <br>
  </li>

  <a id="DbRep-attr-showproctime"></a>
  <li><b>showproctime </b>    - wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden)
                                für die SQL-Ausführung der durchgeführten Funktion. Dabei wird nicht ein einzelnes
                                SQl-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der jeweiligen
                                Funktion betrachtet.   </li> <br>

  <a id="DbRep-attr-showStatus"></a>
  <li><b>showStatus </b>      - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; dbstatus" ein. Es können
                                SQL-Wildcard (%) verwendet werden.
                                <br><br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showStatus %uptime%,%qcache%  <br>
                                # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthalten <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showVariables"></a>
  <li><b>showVariables </b>   - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; dbvars" ein. Es können
                                SQL-Wildcard (%) verwendet werden.
                                <br><br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showVariables %version%,%query_cache% <br>
                                # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showSvrInfo"></a>
  <li><b>showSvrInfo </b>     - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; svrinfo" ein. Es können
                                SQL-Wildcard (%) verwendet werden.
                                <br><br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                                # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten <br>
                                </ul><br>
                                </li>

  <a id="DbRep-attr-showTableInfo"></a>
  <li><b>showTableInfo </b> <br><br>

  Grenzt die Ergebnismenge des Befehls "get &lt;name&gt; tableinfo" ein. Es können SQL-Wildcard (%) verwendet werden.
  <br><br>

  <ul>
    <b>Bespiel: </b> <br>
    attr &lt;name&gt; showTableInfo current,history  <br>
    # Es werden nur Information der Tabellen "current" und "history" angezeigt <br>
  </ul>
  <br>
  </li>

  <a id="DbRep-attr-sqlCmdHistoryLength"></a>
  <li><b>sqlCmdHistoryLength </b> <br><br>

    Aktiviert mit einem Wert > 0 die Kommandohistorie von "sqlCmd" und legt die Anzahl der zu speichernden
    SQL Statements fest. <br>
    (default: 0)

  </li>
  <br>

  <a id="DbRep-attr-sqlCmdVars"></a>
  <li><b>sqlCmdVars </b> <br><br>

    Setzt die angegebene(n) SQL Session Variable(n) oder PRAGMA vor jedem mit sqlCmd ausgeführten
    SQL-Statement.  <br><br>

    <ul>
      <b>Beispiel:</b> <br>
      attr &lt;name&gt; sqlCmdVars SET @open:=NULL, @closed:=NULL; <br>
      attr &lt;name&gt; sqlCmdVars PRAGMA temp_store=MEMORY;PRAGMA synchronous=FULL;PRAGMA journal_mode=WAL; <br>
    </ul>
  <br>
  </li>
  <br>

  <a id="DbRep-attr-sqlFormatService"></a>
  <li><b>sqlFormatService </b> <br><br>

    Über einen Online-Dienst kann eine automatisierte Formatierung von SQL-Statements aktiviert werden. <br>
    Diese Möglichkeit ist insbesondere für komplexe SQL-Statements der Setter sqlCmd, sqlCmdHistory und sqlSpecial
    hilfreich um die Strukturierung und Lesbarkeit zu verbessern. <br>
    Eine Internetverbindung wird benötigt und es sollte das globale Attribut <b>dnsServer</b> gesetzt sein. <br>
    (default: none)

  </li>
  <br>

  <a id="DbRep-attr-sqlResultFieldSep"></a>
  <li><b>sqlResultFieldSep </b> <br><br>

    Legt den verwendeten Feldseparator im Ergebnis des Kommandos "set ... sqlCmd" fest. <br>
    (default: "|")

  </li>
  <br>

  <a id="DbRep-attr-sqlResultFormat"></a>
  <li><b>sqlResultFormat </b> - legt die Formatierung des Ergebnisses des Kommandos "set &lt;name&gt; sqlCmd" fest.
                                Mögliche Optionen sind: <br><br>

                                <ul>
                                <b>separated </b> - die Ergebniszeilen werden als einzelne Readings fortlaufend
                                                    generiert. (default)<br><br>
                                <b>mline </b>     - das Ergebnis wird als Mehrzeiler im Reading
                                                    SqlResult dargestellt. <br><br>
                                <b>sline </b>     - das Ergebnis wird als Singleline im Reading
                                                    SqlResult dargestellt. Satztrenner ist"]|[". <br><br>
                                <b>table </b>     - das Ergebnis wird als Tabelle im Reading
                                                    SqlResult dargestellt. <br><br>
                                <b>json </b>      - erzeugt das Reading SqlResult als
                                                    JSON-kodierten Hash.
                                                    Jedes Hash-Element (Ergebnissatz) setzt sich aus der laufenden Nummer
                                                    des Datensatzes (Key) und dessen Wert zusammen. <br><br>

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
        </li>

  <a id="DbRep-attr-timeYearPeriod"></a>
  <li><b>timeYearPeriod &lt;Monat&gt;-&lt;Tag&gt; &lt;Monat&gt;-&lt;Tag&gt;</b> <br>
  Es wird eine jährliche Periode für die Datenbankselektion bestimmt.
  Die Jahresperiode wird dynamisch zur Ausführungszeit berechnet.
  Eine unterjährige Angabe ist nicht möglich. <br>
  Dieses Attribut ist vor allem dazu gedacht Auswertungen synchron zu einer Abrechnungsperiode, z.B. der eines
  Energie- oder Gaslieferanten, anzufertigen.
  <br><br>

  <ul>
    <b>Beispiel:</b> <br><br>
    attr &lt;name&gt; timeYearPeriod 06-25 06-24 <br><br>

    Wertet die Datenbank in den Zeitgrenzen 25. Juni AAAA bis 24. Juni BBBB aus. <br>
    Das Jahr AAAA bzw. BBBB wird in Abhängigkeit des aktuellen Datums errechnet. <br>
    Ist das aktuelle Datum >= 25. Juni und <= 31. Dezember, dann ist AAAA = aktuelles Jahr und BBBB = aktuelles Jahr+1 <br>
    Ist das aktuelle Datum >= 01. Januar und <= 24. Juni, dann ist AAAA = aktuelles Jahr-1 und BBBB = aktuelles Jahr
  </ul>
  <br><br>
  </li>

  <a id="DbRep-attr-timestamp_begin"></a>
  <li><b>timestamp_begin </b> - der zeitliche Beginn für die Datenselektion  <br>

  Das Format von Timestamp ist "YYYY-MM-DD HH:MM:SS". Für die Attribute "timestamp_begin", "timestamp_end"
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
                              <b>next_day_begin</b>         : entspricht "&lt;nächster Tag&gt; 00:00:00"                  <br>
                              <b>next_day_end</b>           : entspricht "&lt;nächster Tag&gt; 23:59:59"                  <br>
                              <b>current_hour_begin</b>     : entspricht "&lt;aktuelle Stunde&gt;:00:00"                  <br>
                              <b>current_hour_end</b>       : entspricht "&lt;aktuelle Stunde&gt;:59:59"                  <br>
                              <b>previous_hour_begin</b>    : entspricht "&lt;vorherige Stunde&gt;:00:00"                 <br>
                              <b>previous_hour_end</b>      : entspricht "&lt;vorherige Stunde&gt;:59:59"                 <br>
                              </ul>
                              <br>
                              </li>

  <a id="DbRep-attr-timestamp_end"></a>
  <li><b>timestamp_end </b>   - das zeitliche Ende für die Datenselektion. Wenn nicht gesetzt wird immer die aktuelle
                                Datum/Zeit-Kombi für das Ende der Selektion eingesetzt.  <br>

  Das Format von Timestamp ist "YYYY-MM-DD HH:MM:SS". Für die Attribute "timestamp_begin", "timestamp_end"
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
                              <b>next_day_begin</b>         : entspricht "&lt;nächster Tag&gt; 00:00:00"                  <br>
                              <b>next_day_end</b>           : entspricht "&lt;nächster Tag&gt; 23:59:59"                  <br>
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
                                <br>

  <b>Hinweis </b> <br>

  Wird das Attribut "timeDiffToNow" gesetzt, werden die eventuell gesetzten anderen Zeit-Attribute
  ("timestamp_begin","timestamp_end","timeYearPeriod") gelöscht.
  Das Setzen von "timestamp_begin" bzw. "timestamp_end" bedingt die Löschung von anderen Zeit-Attribute falls sie vorher
  gesetzt waren.
  <br><br>
  </li>

  <a id="DbRep-attr-timeDiffToNow"></a>
  <li><b>timeDiffToNow </b>   - der <b>Selektionsbeginn</b> wird auf den Zeitpunkt <b>"&lt;aktuelle Zeit&gt; - &lt;timeDiffToNow&gt;"</b>
                                gesetzt. Die Timestampermittlung erfolgt dynamisch zum Ausführungszeitpunkt. Optional kann mit
                                der Zusatzangabe "FullDay" der Selektionsbeginn und das Selektionsende auf Beginn / Ende der
                                jeweiligen Selektionstage erweitert werden (wirkt nur wenn eingestellte Zeitdifferenz ist >= 1 Tag).
                                <br><br>

                                <ul>
                                <b>Eingabeformat Beispiele:</b> <br>
                                <code>attr &lt;name&gt; timeDiffToNow 86400 </code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 86400 Sekunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow d:2 h:3 m:2 s:10 </code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 2 Tage 3 Stunden 2 Minuten 10 Sekunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow m:600</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 600 Minuten" gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow h:2.5</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 2,5 Stunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow y:1 h:2.5</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 1 Jahr und 2,5 Stunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow y:1.5</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 1,5 Jahre gesetzt <br>
                                <code>attr &lt;name&gt; timeDiffToNow d:8 FullDay </code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 8 Tage gesetzt, der Selektionszeitraum wird auf Beginn / Ende der beteiligten Tage erweitert  <br>
                                </ul>
                                <br>

                                Sind die Attribute "timeDiffToNow" und "timeOlderThan" gleichzeitig gesetzt, wird der
                                Selektionszeitraum zwischen diesen Zeitpunkten dynamisch kalkuliert.
                                <br><br>
                                </li>

  <a id="DbRep-attr-timeOlderThan"></a>
  <li><b>timeOlderThan </b>   - das <b>Selektionsende</b> wird auf den Zeitpunkt <b>"&lt;aktuelle Zeit&gt; - &lt;timeOlderThan&gt;"</b>
                                gesetzt. Dadurch werden alle Datensätze bis zu dem Zeitpunkt "&lt;aktuelle
                                Zeit&gt; - &lt;timeOlderThan&gt;" berücksichtigt. Die Timestampermittlung erfolgt
                                dynamisch zum Ausführungszeitpunkt. Optional kann mit der Zusatzangabe
                                "FullDay" der Selektionsbeginn und das Selektionsende auf Beginn / Ende der jeweiligen
                                Selektionstage erweitert werden (wirkt nur wenn eingestellte Zeitdifferenz ist >= 1 Tag).
                                <br><br>

                                <ul>
                                <b>Eingabeformat Beispiele:</b> <br>
                                <code>attr &lt;name&gt; timeOlderThan 86400</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 86400 Sekunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan d:2 h:3 m:2 s:10</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 2 Tage 3 Stunden 2 Minuten 10 Sekunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan m:600</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 600 Minuten" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan h:2.5</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 2,5 Stunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan y:1 h:2.5</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 1 Jahr und 2,5 Stunden" gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan y:1.5</code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 1,5 Jahre gesetzt <br>
                                <code>attr &lt;name&gt; timeOlderThan d:8 FullDay </code> <br>
                                # das Selektionsende wird auf "aktuelle Zeit - 8 Tage gesetzt, der Selektionszeitraum wird auf Beginn / Ende der beteiligten Tage erweitert  <br>

                                </ul>
                                <br>

                                Sind die Attribute "timeDiffToNow" und "timeOlderThan" gleichzeitig gesetzt, wird der
                                Selektionszeitraum zwischen diesen Zeitpunkten dynamisch kalkuliert.
                                <br><br>
                                </li>

  <a id="DbRep-attr-timeout"></a>
  <li><b>timeout </b>         - das Attribut setzt den Timeout-Wert für die Blocking-Call Routinen in Sekunden
                                (Default: 86400) </li> <br>

  <a id="DbRep-attr-useAdminCredentials"></a>
  <li><b>useAdminCredentials </b>
                                - Wenn gesetzt, wird ein zuvor mit "set &lt;Name&gt; adminCredentials" gespeicherter
                                  privilegierter User für bestimmte Datenbankoperationen verwendet. <br>
                                  (nur gültig für Datenbanktyp MYSQL und DbRep-Typ "Client")
                                  </li> <br>

  <a id="DbRep-attr-userExitFn"></a>
  <li><b>userExitFn   </b>    - stellt eine Schnittstelle zur Ausführung eigenen Usercodes zur Verfügung. <br>
                                Grundsätzlich arbeitet die Schnittstelle <b>ohne</b> Eventgenerierung bzw. benötigt zur Funktion
                                keinen Event.
                                Die Schnittstelle kann mit folgenden Varianten verwendet werden. <br><br>

                                <ul>

                                <b>1. Aufruf einer Subroutine, z.B. in 99_myUtils.pm </b> <br><br>

                                Die aufzurufende Subroutine wird in 99_myUtils.pm nach folgendem Muster erstellt:  <br>

<pre>
sub UserFunction {
  my $name    = shift;             # der Name des DbRep-Devices
  my $reading = shift;             # der Namen des erstellen Readings
  my $value   = shift;             # der Wert des Readings
  my $hash    = $defs{$name};
  ...
  # z.B. übergebene Daten loggen
  Log3 $name, 1, "UserExitFn $name called - transfer parameter are Reading: $reading, Value: $value " ;
  ...
return;
}
</pre>

                               Im Attribut wird die Subroutine und optional ein Reading:Value Regex
                               als Argument angegeben. Ohne diese Angabe werden alle Wertekombinationen als "wahr"
                               gewertet und an die Subroutine übergeben (entspricht .*:.*).
                               <br><br>

                               <ul>
                               <b>Beispiel:</b> <br>
                               attr <device> userExitFn UserFunction Meter:Energy.* <br>
                               # "UserFunction" ist die Subroutine in 99_myUtils.pm.
                               </ul>
                               <br>

                               Die Regexprüfung nach der Erstellung jedes Readings.
                               Ist die Prüfung wahr, wird die angegebene Funktion aufgerufen. <br><br>

                               <b>2. direkte Eingabe von eigenem Code  </b> <br><br>

                               Der eigene Code wird in geschweifte Klammern eingeschlossen.
                               Der Aufruf des Codes erfolgt nach der Erstellung jedes Readings.
                               Im Code stehen folgende Variablen für eine Auswertung zur Verfügung: <br><br>

                               <ul>
                               <li>$NAME - der Name des DbRep-Devices </li>
                               <li>$READING  - der Namen des erstellen Readings </li>
                               <li>$VALUE - der Wert des Readings </li>
                               </ul>

                               <br>

                               <ul>
                               <b>Beispiel:</b> <br>
<pre>
{
  if ($READING =~ /PrEnergySumHwc1_0_value__DIFF/) {
    my $mpk  = AttrVal($NAME, 'Multiplikator', '0');
    my $tarf = AttrVal($NAME, 'Tarif', '0');                                   # Kosten €/kWh
    my $m3   = sprintf "%.3f", $VALUE/10000 * $mpk;                            # verbrauchte m3
    my $kwh  = sprintf "%.3f", $m3 * AttrVal($NAME, 'Brennwert_kWh/m3', '0');  # Umrechnung m3 -> kWh
    my $cost = sprintf "%.2f", $kwh * $tarf;

    my $hash = $defs{$NAME};

    readingsBulkUpdate ($hash, 'gas_consumption_m3',   $m3);
    readingsBulkUpdate ($hash, 'gas_consumption_kwh', $kwh);
    readingsBulkUpdate ($hash, 'gas_costs_euro',     $cost);
  }
}
</pre>
                               # Es werden die Readings gas_consumption_m3, gas_consumption_kwh und gas_costs_euro berechnet
                               und im DbRep-Device erzeugt.
                               </ul>

                               </ul>
                               </li>
                               <br>
                               <br>

  <a id="DbRep-attr-valueFilter"></a>
  <li><b>valueFilter </b>     - Regulärer Ausdruck (REGEXP) zur Filterung von Datensätzen innerhalb bestimmter Funktionen.
                                Der REGEXP wird auf ein bestimmtes Feld oder den gesamten selektierten Datensatz (inkl. Device,
                                Reading usw.) angewendet.
                                Bitte beachten sie die Erläuterungen zu den entsprechenden Set-Kommandos. Weitere Informationen
                                sind mit "get &lt;name&gt; versionNotes 4" verfügbar. </li> <br>


</ul></ul>
</ul>

<a id="DbRep-attr-readings"></a>
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
                                            des <a href="#DbRep-attr-sqlResultFormat">sqlResultFormat</a> Attributes </li> <br>

  <li><b>sqlCmd </b>                      - das letzte ausgeführte sqlCmd-Kommando </li> <br>
  </ul></ul>
  <br>

</ul>

<a id="DbRep-attr-autorename"></a>
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
        attr Rep.Agent stateFormat { ReadingsVal($name, 'state', '') eq 'running' ? 'renaming' : ReadingsVal($name, 'state', ''). ' &raquo;; ProcTime: '.ReadingsVal($name, 'sql_processing_time', '').' sec'}  <br>
        attr Rep.Agent timeout 86400      <br>
        </code>
        <br>
        </ul>

  <b>Hinweis:</b> <br>
  Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
  im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br><br>

</ul>

=end html_DE

=for :application/json;q=META.json 93_DbRep.pm
{
  "abstract": "Reporting and management of DbLog database content.",
  "x_lang": {
    "de": {
      "abstract": "Reporting und Management von DbLog Datenbankinhalten."
    }
  },
  "keywords": [
    "dblog",
    "database",
    "reporting",
    "logging",
    "analyze"
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
        "POSIX": 0,
        "Time::HiRes": 0,
        "Scalar::Util": 0,
        "DBI": 0,
        "DBI::Const::GetInfoType": 0,
        "Blocking": 0,
        "Color": 0,
        "Time::Local": 0,
        "Encode": 0
      },
      "recommends": {
        "Net::FTP": 0,
        "IO::Compress::Gzip": 0,
        "IO::Uncompress::Gunzip": 0,
        "FHEM::Meta": 0
      },
      "suggests": {
        "Net::FTPSSL": 0
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten",
      "title": "DbRep - Reporting und Management von DbLog-Datenbankinhalten"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/93_DbRep.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/93_DbRep.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cutt