##########################################################################################################
# $Id$
##########################################################################################################
#       93_DbRep.pm
#
#       (c) 2016 by Heiko Maaz
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
#  - some proposals to boost and improve SQL-Statements by JoeALLb
#
###########################################################################################################
#
# create additional indexes due to performance purposes:
#
# ALTER TABLE 'fhem'.'history' ADD INDEX `Reading_Time_Idx` (`READING`, `TIMESTAMP`) USING BTREE;
#
# Definition: define <name> DbRep <DbLog-Device>
#
# This module uses credentials of DbLog-devices
#
###########################################################################################################
#  Versions History:
#
# 4.7.7        08.12.2016       code review
# 4.7.6        07.12.2016       DbRep version as internal, check if perl module DBI is installed
# 4.7.5        05.12.2016       collaggstr day aggregation changed
# 4.7.4        28.11.2016       sub calcount changed due to Forum #msg529312
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
# 1.1          20.05.2016       change result-format of "count", move runtime-counter to sub collaggstr
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
use Time::Local;
# no if $] >= 5.017011, warnings => 'experimental';  

my $DbRepVersion = "4.7.7";

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
 $hash->{NotifyFn}     = "DbRep_Notify";
 $hash->{SetFn}        = "DbRep_Set";
 $hash->{GetFn}        = "DbRep_Get";
 $hash->{AttrFn}       = "DbRep_Attr";
 
 $hash->{AttrList} =   "disable:1,0 ".
                       "reading ".                       
                       "allowDeletion:1,0 ".
                       "readingNameMap ".
                       "readingPreventFromDel ".
                       "device ".
                       "expimpfile ".
                       "aggregation:hour,day,week,month,no ".
					   "diffAccept ".
                       "role:Client,Agent ".
                       "showproctime:1,0 ".
                       "showSvrInfo ".
                       "showVariables ".
                       "showStatus ".
                       "showTableInfo ".
                       "timestamp_begin ".
                       "timestamp_end ".
                       "timeDiffToNow ".
                       "timeOlderThan ".
                       "timeout ".
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
  
 return "Error: Perl module ".$DbRepMMDBI." is missing. 
        Install it on Debian with: sudo apt-get install libdbi-perl" if($DbRepMMDBI);
  
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
  
  RemoveInternalTimer($hash);
  InternalTimer(time+5, 'DbRep_firstconnect', $hash, 0);
  
  Log3 ($name, 4, "DbRep $name - initialized");
  readingsSingleUpdate($hash, 'state', 'initialized', 1);
   
return undef;
}

###################################################################################
# DbRep_Set
###################################################################################
sub DbRep_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $dbh     = $hash->{DBH};
  my $dblogdevice    = $hash->{HELPER}{DBLOGDEVICE};
  $hash->{dbloghash} = $defs{$dblogdevice};
  my $dbmodel = $hash->{dbloghash}{DBMODEL};
  
  my $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"sumValue:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"averageValue:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"delEntries:noArg ":"").
                "deviceRename ".
                (($hash->{ROLE} ne "Agent")?"exportToFile:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"importFromFile:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"maxValue:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"minValue:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"fetchrows:noArg ":"").  
                (($hash->{ROLE} ne "Agent")?"diffValue:noArg ":"").   
                (($hash->{ROLE} ne "Agent")?"insert ":"").
                (($hash->{ROLE} ne "Agent")?"countEntries:noArg ":"");
  
  return if(IsDisabled($name));
  
  if ($opt eq "countEntries" && $hash->{ROLE} ne "Agent") {
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "fetchrows" && $hash->{ROLE} ne "Agent") {
      sqlexec($hash,$opt);
      
  } elsif ($opt =~ m/(max|min|sum|average|diff)Value/ && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading to analyze is not set !";
      }
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "delEntries" && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "allowDeletion", undef)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }        
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "deviceRename") {
      my ($olddev, $newdev) = split(",",$prop);
      if (!$olddev || !$newdev) {return "Both entries \"old device name\", \"new device name\" are needed. Use \"set ... deviceRename olddevname,newdevname\" ";}
      $hash->{HELPER}{OLDDEV} = $olddev;
      $hash->{HELPER}{NEWDEV} = $newdev;
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "insert" && $hash->{ROLE} ne "Agent") { 
      if ($prop) {
          if (!AttrVal($hash->{NAME}, "device", "") || !AttrVal($hash->{NAME}, "reading", "") ) {
              return "One or both of attributes \"device\", \"reading\" is not set. It's mandatory to set both to complete dataset for manual insert !";
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
      
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "exportToFile" && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "expimpfile", "")) {
          return "The attribute \"expimpfile\" (path and filename) has to be set for export to file !";
      }
      sqlexec($hash,$opt);
      
  } elsif ($opt eq "importFromFile" && $hash->{ROLE} ne "Agent") {
      if (!AttrVal($hash->{NAME}, "expimpfile", "")) {
          return "The attribute \"expimpfile\" (path and filename) has to be set for import from file !";
      }
      sqlexec($hash,$opt);
      
  }  
  else  
  {
      return "$setlist";
  }  
$hash->{LASTCMD} = "$opt";
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
  my $dbmodel = $hash->{dbloghash}{DBMODEL};
  my $to = AttrVal($name, "timeout", "60");
  
  my $getlist = "Unknown argument $opt, choose one of ".
                "svrinfo:noArg ".
                (($dbmodel eq "MYSQL")?"dbstatus:noArg ":"").
                (($dbmodel eq "MYSQL")?"tableinfo:noArg ":"").
                (($dbmodel eq "MYSQL")?"dbvars:noArg ":"") 
                ;
  
  return if(IsDisabled($name));
  
  if ($opt eq "dbvars" || $opt eq "dbstatus" || $opt eq "tableinfo") {
      return "The operation \"$opt\" isn't available with database type $dbmodel" if ($dbmodel ne 'MYSQL');
      readingsSingleUpdate($hash, "state", "running", 1);
      delread($hash);  # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("dbmeta_DoParse", "$name|$opt", "dbmeta_ParseDone", $to, "ParseAborted", $hash);    
  } elsif ($opt eq "svrinfo") {
      delread($hash); 
      readingsSingleUpdate($hash, "state", "running", 1);
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("dbmeta_DoParse", "$name|$opt", "dbmeta_ParseDone", $to, "ParseAborted", $hash);      
  }
  else 
  {
      return "$getlist";
  } 
  
$hash->{LASTCMD} = "$opt";
return undef;
}

###################################################################################
# DbRep_Attr
###################################################################################
sub DbRep_Attr($$$$) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  $hash->{dbloghash} = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel = $hash->{dbloghash}{DBMODEL};
  my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    # nicht erlaubte / zu löschende Attribute wenn role = Agent
    my @agentnoattr = qw(aggregation
                         allowDeletion
                         reading
                         readingNameMap
                         readingPreventFromDel
                         device
						 diffAccept
                         expimpfile
                         timestamp_begin
                         timestamp_end
                         timeDiffToNow
                         timeOlderThan
                         );
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val   = ($do == 1 ?  "disabled" : "initialized");
  
        readingsSingleUpdate($hash, "state", $val, 1);
        
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
        if ($aName eq "timestamp_begin" || $aName eq "timestamp_end") {
          
            if ($aVal eq "current_year_begin" || $aVal eq "previous_year_begin" || $aVal eq "current_year_end" || $aVal eq "previous_year_end") {
                delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
                delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
                return undef;
            }
           
            unless ($aVal =~ /(19[0-9][0-9]|2[0-9][0-9][0-9])-(0[1-9]|1[1-2])-(0[1-9]|1[0-9]|2[0-9]|3[0-1]) (0[0-9])|1[1-9]|2[0-3]:([0-5][0-9]):([0-5][0-9])/) 
                {return " The Value for $aName is not valid. Use format YYYY-MM-DD HH:MM:SS or one of \"current_year_begin\",\"current_year_end\", \"previous_year_begin\", \"previous_year_end\" !";}
           
            my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($aVal =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
           
            eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
           
            if ($@) {
                my @l = split (/at/, $@);
                return " The Value of $aName is out of range - $l[0]";
            }
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
        }
        if ($aName eq "timeout" || $aName eq "diffAccept") {
            unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
        } 
        if ($aName eq "readingNameMap") {
            unless ($aVal =~ m/^[A-Za-z\d_\.-]+$/) { return " Unsupported character in $aName found. Use only A-Z a-z _ . -";}
        }
        if ($aName eq "timeDiffToNow") {
            unless ($aVal =~ /^[0-9]+$/) { return "The Value of $aName is not valid. Use only figures 0-9 without decimal places. It's the time (in seconds) before current time used as start of selection. Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
        } 
        if ($aName eq "timeOlderThan") {
            unless ($aVal =~ /^[0-9]+$/) { return "The Value of $aName is not valid. Use only figures 0-9 without decimal places. It's the time (in seconds) before current time used as end of selection. Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
        }
        if ($aName eq "reading" || $aName eq "device") {
            if ($dbmodel && $dbmodel ne 'SQLITE') {
                if ($dbmodel eq 'POSTGRESQL') {
                    return "Length of \"$aName\" is too big. Maximum lenth for database type $dbmodel is $dbrep_col{READING}" if(length($aVal) > $dbrep_col{READING});
                } elsif ($dbmodel eq 'MYSQL') {
                    return "Length of \"$aName\" is too big. Maximum lenth for database type $dbmodel is $dbrep_col{READING}" if(length($aVal) > $dbrep_col{READING});
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
     
     # wenn Rolle "Agent" Verbeitung von RENAMED Events
     if ($own_hash->{ROLE} eq "Agent") {
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
         $own_hash->{HELPER}{OLDDEV} = $evl[1];
         $own_hash->{HELPER}{NEWDEV} = $evl[2];
         sqlexec($own_hash,"deviceRename");
         
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
    
return undef;
}


###################################################################################
# First Init DB Connect 
###################################################################################
sub DbRep_firstconnect($) {
  my ($hash)= @_;
  my $name           = $hash->{NAME};
  my $dblogdevice    = $hash->{HELPER}{DBLOGDEVICE};
  $hash->{dbloghash} = $defs{$dblogdevice};
  my $dbconn         = $hash->{dbloghash}{dbconn};

if ($init_done == 1) {
  
  if ( !DbRep_Connect($hash) ) {
      Log3 ($name, 2, "DbRep $name - DB connect failed. Credentials of database $hash->{DATABASE} are valid and database reachable ?");
      readingsSingleUpdate($hash, "state", "disconnected", 1);
  } else {
      Log3 ($name, 4, "DbRep $name - Connectiontest to db $dbconn successful");
      my $dbh = $hash->{DBH}; 
      $dbh->disconnect();
  }
} else {
     RemoveInternalTimer($hash, "DbRep_firstconnect");
     InternalTimer(time+1, "DbRep_firstconnect", $hash, 0);
}

return;
}

###################################################################################
# DB Connect
###################################################################################
sub DbRep_Connect($) {
  my ($hash)= @_;
  my $name       = $hash->{NAME};
  my $dbloghash  = $hash->{dbloghash};

  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};
  my $dblogname  = $dbloghash->{NAME};
  my $dbpassword = $attr{"sec$dblogname"}{secret};
  
  my $dbh;
  
  eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1 });};

  if(!$dbh) {
    RemoveInternalTimer($hash);
    Log3 ($name, 3, "DbRep $name - Connectiontest to database $dbconn with user $dbuser");
    
    readingsSingleUpdate($hash, 'state', 'disconnected', 1);
    
    InternalTimer(time+5, 'DbRep_Connect', $hash, 0);
    
    Log3 ($name, 3, "DbRep $name - Waiting for database connection");
    
    return 0;
  }

  $hash->{DBH} = $dbh;

  readingsSingleUpdate($hash, "state", "connected", 1);
  Log3 ($name, 3, "DbRep $name - connected");
  
  return 1;
}

################################################################################################################
#  Hauptroutine "Set"
################################################################################################################

sub sqlexec($$) {
 my ($hash,$opt) = @_;
 my $name        = $hash->{NAME}; 
 my $to          = AttrVal($name, "timeout", "60");
 my $reading     = AttrVal($name, "reading", undef);
 my $aggregation = AttrVal($name, "aggregation", "no");   # wichtig !! aggregation niemals "undef"
 my $device      = AttrVal($name, "device", undef);
 my $aggsec;
 
 # Entkommentieren für Testroutine im Vordergrund
 # testexit($hash);
 
 if (exists($hash->{HELPER}{RUNNING_PID}) && $hash->{ROLE} ne "Agent") {
     Log3 ($name, 3, "DbRep $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
     BlockingKill($hash->{HELPER}{RUNNING_PID});
 }
 
 # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
 delread($hash);
 
 readingsSingleUpdate($hash, "state", "running", 1);
 
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # Ausgaben und Zeitmanipulationen
 Log3 ($name, 4, "DbRep $name - -------- New selection --------- "); 
 Log3 ($name, 4, "DbRep $name - Aggregation: $aggregation"); 
 Log3 ($name, 4, "DbRep $name - Command: $opt"); 
        
 # Auswertungszeit Beginn (String)
 # dynamische Berechnung von Startdatum/zeit aus current_year_begin / previous_year_begin 
 # timestamp in SQL format YYYY-MM-DD hh:mm:ss
 my $cy = strftime "%Y", localtime;      # aktuelles Jahr
 my $tsbegin;
 if (AttrVal($hash->{NAME}, "timestamp_begin", "") eq "current_year_begin") {
     $tsbegin = $cy."-01-01 00:00:00";
 } elsif (AttrVal($hash->{NAME}, "timestamp_begin", "") eq "previous_year_begin") {
     $tsbegin = ($cy-1)."-01-01 00:00:00";
 } else {
     $tsbegin = AttrVal($hash->{NAME}, "timestamp_begin", "1970-01-01 01:00:00");  
 }
 
 # Auswertungszeit Ende (String)
 # dynamische Berechnung von Endedatum/zeit aus current_year_begin / previous_year_begin 
 # timestamp in SQL format YYYY-MM-DD hh:mm:ss
 my $tsend;
 if (AttrVal($hash->{NAME}, "timestamp_end", "") eq "current_year_end") {
     $tsend = $cy."-12-31 23:59:59";
 } elsif (AttrVal($hash->{NAME}, "timestamp_end", "") eq "previous_year_end") {
     $tsend = ($cy-1)."-12-31 23:59:59";
 } else {
     $tsend = AttrVal($hash->{NAME}, "timestamp_end", strftime "%Y-%m-%d %H:%M:%S", localtime(time)); 
 }
        
 # extrahieren der Einzelwerte von Datum/Zeit Beginn
 my ($yyyy1, $mm1, $dd1, $hh1, $min1, $sec1) = ($tsbegin =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/); 
 # extrahieren der Einzelwerte von Datum/Zeit Ende 
 my ($yyyy2, $mm2, $dd2, $hh2, $min2, $sec2) = ($tsend =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
        
 # Umwandeln in Epochesekunden Beginn
 my $epoch_seconds_begin = timelocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900) if($tsbegin);
 
 if(AttrVal($hash->{NAME}, "timeDiffToNow", undef)) {
     $epoch_seconds_begin = time() - AttrVal($hash->{NAME}, "timeDiffToNow", undef);
     Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp begin: ".AttrVal($hash->{NAME}, "timeDiffToNow", undef)." sec"); 
 } elsif (AttrVal($hash->{NAME}, "timeOlderThan", undef)) {
     $epoch_seconds_begin = timelocal(00, 00, 01, 01, 01-1, 1970-1900);
 }
 
 my $tsbegin_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin);
 Log3 ($name, 5, "DbRep $name - Timestamp begin epocheseconds: $epoch_seconds_begin");   
 Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: $tsbegin_string"); 
        
 # Umwandeln in Epochesekunden Endezeit
 my $epoch_seconds_end = timelocal($sec2, $min2, $hh2, $dd2, $mm2-1, $yyyy2-1900);
 $epoch_seconds_end = AttrVal($hash->{NAME}, "timeOlderThan", undef) ? (time() - AttrVal($hash->{NAME}, "timeOlderThan", undef)) : $epoch_seconds_end;
 Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp end: ".AttrVal($hash->{NAME}, "timeOlderThan", undef)." sec") if(AttrVal($hash->{NAME}, "timeOlderThan", undef)); 
 
 my $tsend_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
 Log3 ($name, 5, "DbRep $name - Timestamp end epocheseconds: $epoch_seconds_end"); 
 Log3 ($name, 4, "DbRep $name - Timestamp end human readable: $tsend_string"); 

 
 # Erstellung Wertehash für "collaggstr"
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
             
 Log3 ($name, 5, "DbRep $name - weekday of start for selection: $wd  ->  wdadd: $wdadd"); 
 
 if ($aggregation eq "hour") {
     $aggsec = 3600;
 } elsif ($aggregation eq "day") {
     $aggsec = 86400;
 } elsif ($aggregation eq "week") {
     $aggsec = 604800;
 } elsif ($aggregation eq "month") {
     $aggsec = 2678400;
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
        ($runtime,$runtime_string,$runtime_string_first,$runtime_string_next,$ll) = collaggstr($hash,$runtime,$i,$runtime_string_next);
        $ts .= $runtime_string."#".$runtime_string_first."#".$runtime_string_next."|";
        $i++;
    } 

 if ($opt eq "sumValue") {
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("sumval_DoParse", "$name§$device§$reading§$ts", "sumval_ParseDone", $to, "ParseAborted", $hash);
     
 } elsif ($opt eq "countEntries") {
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("count_DoParse", "$name§$device§$reading§$ts", "count_ParseDone", $to, "ParseAborted", $hash);

 } elsif ($opt eq "averageValue") {      
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("averval_DoParse", "$name§$device§$reading§$ts", "averval_ParseDone", $to, "ParseAborted", $hash); 
    
 } elsif ($opt eq "fetchrows") {
     $runtime_string_first = defined($epoch_seconds_begin) ? strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin) : "1970-01-01 01:00:00";
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("fetchrows_DoParse", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "fetchrows_ParseDone", $to, "ParseAborted", $hash);
    
 } elsif ($opt eq "exportToFile") {
     $runtime_string_first = defined($epoch_seconds_begin) ? strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin) : "1970-01-01 01:00:00";
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("expfile_DoParse", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "expfile_ParseDone", $to, "ParseAborted", $hash);
    
 } elsif ($opt eq "importFromFile") {             
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("impfile_Push", "$name", "impfile_PushDone", $to, "ParseAborted", $hash);
    
 } elsif ($opt eq "maxValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("maxval_DoParse", "$name§$device§$reading§$ts", "maxval_ParseDone", $to, "ParseAborted", $hash);   
         
 } elsif ($opt eq "minValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("minval_DoParse", "$name§$device§$reading§$ts", "minval_ParseDone", $to, "ParseAborted", $hash);   
         
 } elsif ($opt eq "delEntries") {
     $runtime_string_first = defined($epoch_seconds_begin) ? strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin) : "1970-01-01 01:00:00";
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("del_DoParse", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "del_ParseDone", $to, "ParseAborted", $hash);        
 
 } elsif ($opt eq "diffValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("diffval_DoParse", "$name§$device§$reading§$ts", "diffval_ParseDone", $to, "ParseAborted", $hash);   
         
 } elsif ($opt eq "insert") { 
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("insert_Push", "$name", "insert_Done", $to, "ParseAborted", $hash);   
         
 } elsif ($opt eq "deviceRename") { 
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("devren_Push", "$name", "devren_Done", $to, "ParseAborted", $hash);   
         
 }

return;
}

####################################################################################################
#  delete Readings before new operation
####################################################################################################
sub delread($) {
 # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
 my ($hash) = @_;
 my $name   = $hash->{NAME}; 
 my @rdpfdel = split(",", $hash->{HELPER}{RDPFDEL}) if($hash->{HELPER}{RDPFDEL});
 if (@rdpfdel) {
     my @allrds = keys%{$defs{$name}{READINGS}};
     foreach my $key(@allrds) {
         # Log3 ($name, 3, "DbRep $name - Reading Schlüssel: $key");
         my $dodel = 1;
         foreach my $rdpfdel(@rdpfdel) {
             if($key =~ /$rdpfdel/) {
                 $dodel = 0;
             }
         }
         if($dodel) {
             delete($defs{$name}{READINGS}{$key});
         }
     }
 } else {
     delete $defs{$name}{READINGS};
 }
return undef;
}

####################################################################################################
# nichtblockierende DB-Abfrage averageValue
####################################################################################################
sub averval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall averval_DoParse");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall averval_DoParse finished");
     return "$name|''|$device|$reading|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");   
 
 # SQL-Startzeit
 my $st = [gettimeofday];
      
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 foreach my $row (@ts) {

     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];
     
     # SQL zusammenstellen für DB-Abfrage
     my $sql = "SELECT AVG(VALUE) FROM `history` where ";
     $sql .= "DEVICE LIKE '$device' AND " if($device);
     $sql .= "READING LIKE '$reading' AND " if($reading);
     $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");        
     
     my $line;
     
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall averval_DoParse finished");
         return "$name|''|$device|$reading|''|$err";
     } else {
         Log3 ($name, 5, "DbRep $name - SQL result: $line") if($line);
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."|"; 
         }
     }   
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall averval_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0";
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
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading     =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall averval_ParseDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall averval_ParseDone finished");
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
          $reading_runtime_string = $rsf.$ds.$rds."AVERAGE__".$runtime_string;
      }
         
     readingsBulkUpdate($hash, $reading_runtime_string, $c?sprintf("%.4f",$c):"-");
  }

  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));  
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall averval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage count
####################################################################################################

sub count_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall count_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall count_DoParse finished");
     return "$name|''|$device|$reading|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");  
 
 # SQL-Startzeit
 my $st = [gettimeofday];
    
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 foreach my $row (@ts) {

     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];
     
     # SQL zusammenstellen für DB-Abfrage
     my $sql = "SELECT COUNT(*) FROM `history` where ";
     $sql .= "DEVICE LIKE '$device' AND " if($device);
     $sql .= "READING LIKE '$reading' AND " if($reading);
     $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next';"; 
     
     Log3($name, 4, "DbRep $name - SQL execute: $sql");        
     
     my $line;
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall count_DoParse finished");
         return "$name|''|$device|$reading|''|$err";
     } else {
         Log3 ($name, 5, "DbRep $name - SQL result: $line") if($line);      
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."|"; 
         }  
     } 
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall count_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0";
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
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading     =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall count_ParseDone");
  
   if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall count_ParseDone finished");
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
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."COUNT__".$runtime_string;
      }
         
     readingsBulkUpdate($hash, $reading_runtime_string, $c?$c:"-");
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef)); 
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall count_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage maxValue
####################################################################################################

sub maxval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall maxval_DoParse");
  
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
     return "$name|''|$device|$reading|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
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
     
     # SQL zusammenstellen für DB-Operation
     my $sql = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;"; 
     
     # SQL zusammenstellen für Logausgabe
     my $sql1 = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql1 .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql1 .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql1"); 
     
     $runtime_string = encode_base64($runtime_string,"");
     my $sth = $dbh->prepare($sql);   
     
     eval {$sth->execute($runtime_string_first, $runtime_string_next);};
     
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
         return "$name|''|$device|$reading|''|$err";
     } else {
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
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
  
 Log3 ($name, 5, "DbRep $name -> raw data of row_array result:\n @row_array");
 
  #---------- Berechnung Ergebnishash maxValue ------------------------ 
  my $i = 1;
  my %rh = ();
  my $lastruntimestring;
  my $row_max_time; 
  my $max_value = 0;
  
  foreach my $row (@row_array) {
      my @a = split("[ \t][ \t]*", $row);
      my $runtime_string = decode_base64($a[0]);
      $lastruntimestring = $runtime_string if ($i == 1);
      my $value          = $a[1];
      
      $a[3]              =~ s/:/-/g if($a[3]);          # substituieren unsopported characters -> siehe fhem.pl
      my $timestamp      = $a[3]?$a[2]."_".$a[3]:$a[2];
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in maxValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
          $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
          Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
          return "$name|''|$device|$reading|''|$err";
      }
      
      Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
             
      if ($runtime_string eq $lastruntimestring) {
          if ($value >= $max_value) {
              $max_value    = $value;
              $row_max_time = $timestamp;
              $rh{$runtime_string} = $runtime_string."|".$max_value."|".$row_max_time;            
          }
      } else {
          # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen 
          $lastruntimestring = $runtime_string;
          $max_value         = 0;
          if ($value >= $max_value) {
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
     
 # Ergebnishash als Einzeiler zurückgeben
 my $rows = join('§', %rh); 
 my $rowlist = encode_base64($rows,"");
  
 Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|0";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage maxValue
####################################################################################################

sub maxval_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $rowlist    = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading     =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall maxval_ParseDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_ParseDone finished");
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
      readingsBulkUpdate($hash, $reading_runtime_string, $rv?sprintf("%.4f",$rv):"-");          
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));              
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage minValue
####################################################################################################

sub minval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall minval_DoParse");
  
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall minval_DoParse finished");
     return "$name|''|$device|$reading|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
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
     
     # SQL zusammenstellen für DB-Operation
     my $sql = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;"; 
     
     # SQL zusammenstellen für Logausgabe
     my $sql1 = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql1 .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql1 .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql1"); 
     
     $runtime_string = encode_base64($runtime_string,"");
     my $sth = $dbh->prepare($sql);   
     
     eval {$sth->execute($runtime_string_first, $runtime_string_next);};
     
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall minval_DoParse finished");
         return "$name|''|$device|$reading|''|$err";
     } else {
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
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
  
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
      
      $a[3]              =~ s/:/-/g if($a[3]);          # substituieren unsopported characters -> siehe fhem.pl
      my $timestamp      = $a[3]?$a[2]."_".$a[3]:$a[2];
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in minValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
          $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
          Log3 ($name, 4, "DbRep $name -> BlockingCall minval_DoParse finished");
          return "$name|''|$device|$reading|''|$err";
      }
      
      Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
      
      $rh{$runtime_string} = $runtime_string."|".$min_value."|".$timestamp if ($i == 1);  # minValue des ersten SQL-Statements in hash einfügen
      
      if ($runtime_string eq $lastruntimestring) {
          if ($value < $min_value) {
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
     
 # Ergebnishash als Einzeiler zurückgeben
 my $rows = join('§', %rh); 
 my $rowlist = encode_base64($rows,"");
  
 Log3 ($name, 4, "DbRep $name -> BlockingCall minval_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|0";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage minValue
####################################################################################################

sub minval_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $rowlist    = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading     =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall minval_ParseDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall minval_ParseDone finished");
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
      readingsBulkUpdate($hash, $reading_runtime_string, $rv?sprintf("%.4f",$rv):"-");          
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));              
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall minval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage diffValue
####################################################################################################

sub diffval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbmodel    = $dbloghash->{DBMODEL};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall diffval_DoParse");
  
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
     return "$name|''|$device|$reading|''|''|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");  
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 # SQL zusammenstellen für DB-Operation neu diffValue + prepare
 my $sql;
 if($dbmodel ne "SQLITE") {
     $sql  = "SELECT TIMESTAMP,VALUE,
             if(VALUE-\@V < 0 OR \@RB = 1 , \@diff:= 0, \@diff:= VALUE-\@V ) as DIFF, 
             \@V:= VALUE as VALUEBEFORE,
		     \@RB:= '0' as RBIT 
             FROM `history` where ";
     $sql .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql .= "`READING` LIKE '$reading' AND " if($reading);
	 $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;";
 } else {
     $sql  = "SELECT TIMESTAMP,VALUE FROM `history` where ";
     $sql .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;";
 }
 
 my $sth = $dbh->prepare($sql); 
 
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my @row_array;
 my @array;

 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];  
     $runtime_string           = encode_base64($runtime_string,""); 
     
     # SQL zusammenstellen für Logausgabe
     my $sql1 = "SELECT ... where ";
     $sql1 .= "`DEVICE` LIKE '$device' AND " if($device);
     $sql1 .= "`READING` LIKE '$reading' AND " if($reading); 
     $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql1"); 
     
	 if($dbmodel ne "SQLITE") {
	     eval {$dbh->do("set \@V:= 0, \@diff:= 0, \@diffTotal:= 0, \@RB:= 1;");};   # @\RB = Resetbit wenn neues Selektionsintervall beginnt
     }
	 
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
         return "$name|''|$device|$reading|''|''|''|$err";
     }
	 
     eval {$sth->execute($runtime_string_first, $runtime_string_next);};
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
         return "$name|''|$device|$reading|''|''|''|$err";
     
	 } else {
		 if($dbmodel ne "SQLITE") {
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
 
  # Berechnung diffValue aus Selektionshash
  my %rh = ();                    # Ergebnishash, wird alle Ergebniszeilen enthalten
  my %ch = ();                    # counthash, enthält die Anzahl der verarbeiteten Datasets pro runtime_string
  my $lastruntimestring;
  my $i = 1;
  my $diff_current;               # Differenzwert des aktuellen Datasets 
  my $diff_before;                # Differenzwert vorheriger Datensatz
  my $rejectstr;                  # String der ignorierten Differenzsätze
  my $diff_total;                 # Summenwert aller berücksichtigten Teildifferenzen
  my $max = ($#row_array)+1;      # Anzahl aller Listenelemente

  Log3 ($name, 5, "DbRep $name - data of row_array result assigned to fields:\n");
  
  my $difflimit = AttrVal($name, "diffAccept", "20");   # legt fest, bis zu welchem Wert Differenzen akzeptoert werden (Ausreißer eliminieren)
  
  foreach my $row (@row_array) {
      my @a = split("[ \t][ \t]*", $row, 6);
      my $runtime_string = decode_base64($a[0]);
      $lastruntimestring = $runtime_string if ($i == 1);
      my $timestamp      = $a[2]?$a[1]."_".$a[2]:$a[1];
      my $value          = $a[3]?$a[3]:0;  
      my $diff           = $a[4]?sprintf("%.4f",$a[4]):0;    
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in diffValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
          $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
          Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
          return "$name|''|$device|$reading|''|''|''|$err";
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
          }
          
          if ($diff) {
		      if($diff <= $difflimit) {
                  $diff_total = $diff_total+$diff;
			  }
              $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
              $ch{$runtime_string}++ if($value && $i > 1);			  
          }
      } else {
          # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen 
          $lastruntimestring = $runtime_string;
          $i  = 1;
          $diff_total = $diff?$diff:0 if($diff <= $difflimit);
          $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
          $ch{$runtime_string} = 1 if($value);			  
      } 
      $i++;
  }
  
 Log3 ($name, 4, "DbRep $name - result of diffValue calculation before encoding:");
 foreach my $key (sort(keys(%rh))) {
     Log3 ($name, 4, "runtimestring Key: $key, value: ".$rh{$key}); 
 }
 
 my $ncp = calcount($hash,\%ch);
 
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
 my $rowsrej      = encode_base64($rejectstr,"") if($rejectstr);
 # Ergebnishash  
 my $rows = join('§', %rh); 
 my $rowlist = encode_base64($rows,"");
  
 Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);
 
 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|$rowsrej|$ncpslist|0";
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
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading    =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $rowsrej    = $a[5]?decode_base64($a[5]):undef;     # String von Datensätzen die nicht berücksichtigt wurden (diff Schwellenwert Überschreitung)
  my $ncpslist   = decode_base64($a[6]);                 # Hash von Perioden die nicht kalkuliert werden konnten "no calc in period" 
  my $err        = $a[7]?decode_base64($a[7]):undef;
  my $reading_runtime_string;
  my $difflimit  = AttrVal($name, "diffAccept", "20");   # legt fest, bis zu welchem Wert Differenzen akzeptoert werden (Ausreißer eliminieren)AttrVal($name, "diffAccept", "20");
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall diffval_ParseDone");
  
   if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_ParseDone finished");
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
      readingsBulkUpdate($hash, $reading_runtime_string, $rv?sprintf("%.4f",$rv):"-");          
    
  }
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));           
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "diff-overrun_limit-".$difflimit, $rowsrej) if($rowsrej);
  readingsBulkUpdate($hash, "not_enough_data_in_period", $ncpstr) if($ncpstr);
  readingsBulkUpdate($hash, "state", ($ncpstr||$rowsrej)?"Warning":"done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage sumValue
####################################################################################################

sub sumval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall sumval_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_DoParse finished");
     return "$name|''|$device|$reading|''|$err";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");  
 
 # SQL-Startzeit
 my $st = [gettimeofday];  

 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 foreach my $row (@ts) {

     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];
     
     # SQL zusammenstellen für DB-Abfrage
     my $sql = "SELECT SUM(VALUE) FROM `history` where ";
     $sql .= "DEVICE LIKE '$device' AND " if($device);
     $sql .= "READING LIKE '$reading' AND " if($reading);
     $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");        
     
     my $line;
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_DoParse finished");
         return "$name|''|$device|$reading|''|$err";
     } else {
         Log3($name, 5, "DbRep $name - SQL result: $line") if($line);      
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$line."#".$rsf[0]."|"; 
         } 
     }       
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0";
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
     $device     =~ s/%/\//g;
  my $reading    = $a[3];
     $reading     =~ s/%/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall sumval_ParseDone");
  
   if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_ParseDone finished");
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
         
      readingsBulkUpdate($hash, $reading_runtime_string, $c?sprintf("%.4f",$c):"-");
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef)); 
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});  
  Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierendes DB delete
####################################################################################################

sub del_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $runtime_string_first, $runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall del_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
     return "$name|''|''|$err";
 }
 
 # SQL zusammenstellen für DB-Operation
 my $sql = "DELETE FROM history where ";
 $sql .= "DEVICE = '$device' AND " if($device);
 $sql .= "READING = '$reading' AND " if($reading); 
 $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ;"; 
 
 # SQL zusammenstellen für Logausgabe
 my $sql1 = "DELETE FROM history where ";
 $sql1 .= "DEVICE = '$device' AND " if($device);
 $sql1 .= "READING = '$reading' AND " if($reading); 
 $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next';"; 
    
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql1");        
 
 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sth = $dbh->prepare($sql); 
 
 eval {$sth->execute($runtime_string_first, $runtime_string_next);};
 
 my $rows;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
     return "$name|''|''|$err";
 } else {
     $rows = $sth->rows;
     $dbh->commit() if(!$dbh->{AutoCommit});
     $dbh->disconnect;
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 5, "DbRep $name -> Number of deleted rows: $rows");
 Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rows|$rt|0";
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
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall del_ParseDone");
  
   if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall del_ParseDone finished");
      return;
  }
  
  my $reading = AttrVal($hash->{NAME}, "reading", undef);
  my $device  = AttrVal($hash->{NAME}, "device", undef);
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my $ds   = $device." -- " if ($device);
  my $rds  = $reading." -- " if ($reading);
  my $reading_runtime_string = $ds.$rds." -- DELETED ROWS -- ";
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $reading_runtime_string, $rows);
         
  $rows = $ds.$rds.$rows;
  
  Log3 ($name, 3, "DbRep $name - Entries of database $hash->{DATABASE} deleted: $rows");  
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));     
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall del_ParseDone finished");
  
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
 my $err;
 
 # Background-Startzeit
 my $bst = [gettimeofday];

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall insert_Push");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
     return "$name|''|''|$err";
 }
 
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

 $dbh->begin_work();
 my $sth = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
 
 eval {$sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);};
 
 my $irow;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Failed to insert new dataset into database: $@");
     $dbh->rollback();
     $dbh->disconnect();
     Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
     return "$name|''|''|$err";
 } else {
     $dbh->commit();
     $irow = $sth->rows;
     $dbh->disconnect();
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
 
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
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall insert_Done");
  
  my $i_timestamp = delete $hash->{HELPER}{I_TIMESTAMP};
  my $i_device    = delete $hash->{HELPER}{I_DEVICE};
  my $i_type      = delete $hash->{HELPER}{I_TYPE};
  my $i_event     = delete $hash->{HELPER}{I_EVENT};
  my $i_reading   = delete $hash->{HELPER}{I_READING};
  my $i_value     = delete $hash->{HELPER}{I_VALUE};
  my $i_unit      = delete $hash->{HELPER}{I_UNIT}; 
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Done finished");
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "number_lines_inserted", $irow);    
  readingsBulkUpdate($hash, "data_inserted", $i_timestamp.", ".$i_device.", ".$i_type.", ".$i_event.", ".$i_reading.", ".$i_value.", ".$i_unit);  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef)); 
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);
  
  Log3 ($name, 5, "DbRep $name - Inserted into database $hash->{DATABASE} table 'history': Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");  

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Done finished");
  
return;
}

####################################################################################################
# nichtblockierendes DB deviceRename
####################################################################################################

sub devren_Push($) {
 my ($name)     = @_;
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;
 
 # Background-Startzeit
 my $bst = [gettimeofday];

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall devren_Push");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall devren_Push finished");
     return "$name|''|''|$err";
 }
 
 my $olddev = delete $hash->{HELPER}{OLDDEV};
 my $newdev = delete $hash->{HELPER}{NEWDEV};
      
 # SQL zusammenstellen für DB-Operation
    
 Log3 ($name, 5, "DbRep $name -> Rename old device name \"$olddev\" to new device name \"$newdev\" in database $dblogname ");     
 
 # SQL-Startzeit
 my $st = [gettimeofday];

 $dbh->begin_work();
 my $sth = $dbh->prepare_cached("UPDATE history SET TIMESTAMP=TIMESTAMP,DEVICE=? WHERE DEVICE=? ") ;
 eval {$sth->execute($newdev, $olddev);};
 
 my $urow;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Failed to rename old device name \"$olddev\" to new device name \"$newdev\": $@");
     $dbh->rollback();
     $dbh->disconnect();
     Log3 ($name, 4, "DbRep $name -> BlockingCall devren_Push finished");
     return "$name|''|''|$err";
 } else {
     $dbh->commit();
     $urow = $sth->rows;
     $dbh->disconnect();
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall devren_Push finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$urow|$rt|0|$olddev|$newdev";
}

####################################################################################################
# Auswertungsroutine DB deviceRename
####################################################################################################

sub devren_Done($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $urow       = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $olddev     = $a[4];
  my $newdev     = $a[5]; 
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall devren_Done");
  
   
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall devren_Done finished");
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "number_lines_updated", $urow);    
  readingsBulkUpdate($hash, "device_renamed", "old: ".$olddev." to new: ".$newdev) if ($urow != 0); 
  readingsBulkUpdate($hash, "device_not_renamed", "WARNING - old: ".$olddev." not found, not renamed to new: ".$newdev) if ($urow == 0); 
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef)); 
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);
  
  if ($urow != 0) {
      Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - DEVICE renamed in \"$hash->{DATABASE}\", old: \"$olddev\", new: \"$newdev\", amount: $urow "); 
  } else {
      Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - WARNING - old device \"$olddev\" was not found in database \"$hash->{DATABASE}\" "); 
  }

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall devren_Done finished");
  
return;
}


####################################################################################################
# nichtblockierende DB-Abfrage fetchrows
####################################################################################################

sub fetchrows_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $runtime_string_first, $runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err;
 
 # Background-Startzeit
 my $bst = [gettimeofday];

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall fetchrows_DoParse");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
     return "$name|''|''|$err";
 }
 
 # SQL zusammenstellen
 my $sql = "SELECT DEVICE,READING,TIMESTAMP,VALUE FROM history where ";
 $sql .= "DEVICE LIKE '$device' AND " if($device);
 $sql .= "READING LIKE '$reading' AND " if($reading); 
 $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;";  
         
 # SQL zusammenstellen für Logfileausgabe
 my $sql1 = "SELECT DEVICE,READING,TIMESTAMP,VALUE FROM history where ";
 $sql1 .= "DEVICE LIKE '$device' AND " if($device);
 $sql1 .= "READING LIKE '$reading' AND " if($reading); 
 $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql1");    

 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sth = $dbh->prepare($sql);
 
 eval {$sth->execute($runtime_string_first, $runtime_string_next);};
 
 my $rowlist;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
     return "$name|''|''|$err";
 } else {
     my @row_array = map { $_ -> [0]." ".$_ -> [1]." ".$_ -> [2]." ".$_ -> [3]."\n" } @{$sth->fetchall_arrayref()};     
     $rowlist = join('|', @row_array);
     Log3 ($name, 5, "DbRep $name -> row_array:  @row_array");
 } 
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$rt|0";
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
  my $name       = $hash->{NAME};
  my $reading    = AttrVal($name, "reading", undef);
  my @i;
  my @row;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall fetchrows_ParseDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_ParseDone finished");
      return;
  } 
  
  my @row_array = split("\\|", $rowlist);
  
  Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  foreach my $row (@row_array) {
             my @a = split("[ \t][ \t]*", $row, 5);
             my $dev = $a[0];
             my $rea = $a[1];
             $a[3]   =~ s/:/-/g;          # substituieren unsopported characters ":" -> siehe fhem.pl
             my $ts  = $a[2]."_".$a[3];
             my $val = $a[4];
             
             if ($reading && AttrVal($hash->{NAME}, "readingNameMap", "")) {
                 $reading_runtime_string = $ts."__".AttrVal($hash->{NAME}, "readingNameMap", "") ;
             } else {
                 $reading_runtime_string = $ts."__".$dev."__".$rea;
             }
             
             readingsBulkUpdate($hash, $reading_runtime_string, $val);
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));          
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Funktion expfile
####################################################################################################

sub expfile_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $runtime_string_first, $runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err=0;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall expfile_DoParse");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall expfile_DoParse finished");
     return "$name|''|''|$err";
 }
 
 my $outfile = AttrVal($name, "expimpfile", undef);
 if (open(FH, ">$outfile")) {
     binmode (FH);
 } else {
     $err = encode_base64("could not open ".$outfile.": ".$!,"");
     return "$name|''|''|$err";
 }
 
 
 # SQL zusammenstellen
 my $sql = "SELECT TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT FROM history where ";
 $sql .= "DEVICE LIKE '$device' AND " if($device);
 $sql .= "READING LIKE '$reading' AND " if($reading); 
 $sql .= "TIMESTAMP >= ? AND TIMESTAMP < ? ORDER BY TIMESTAMP ;";   
         
 # SQL zusammenstellen für Logfileausgabe
 my $sql1 = "SELECT TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT FROM FROM history where ";
 $sql1 .= "DEVICE LIKE '$device' AND " if($device);
 $sql1 .= "READING LIKE '$reading' AND " if($reading); 
 $sql1 .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql1");    

 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sth = $dbh->prepare($sql);
 
 eval {$sth->execute($runtime_string_first, $runtime_string_next);};
 
 my $nrows = 0;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     Log3 ($name, 4, "DbRep $name -> BlockingCall expfile_DoParse finished");
     return "$name|''|''|$err";
 } else {
     # only for this block because of warnings of uninitialized values
     no warnings 'uninitialized'; 
     while (my $row = $sth->fetchrow_arrayref) {
        print FH join(',', map { s{"}{""}g; "\"$_\""; } @$row), "\n";
        Log3 ($name, 5, "DbRep $name -> write row:  @$row");
        # Anzahl der Datensätze
        $nrows++;
     }
     close(FH);
 } 
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $sth->finish;
 $dbh->disconnect;
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall expfile_DoParse finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$nrows|$rt|$err";
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
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall expfile_ParseDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall expfile_ParseDone finished");
      return;
  } 
  
  my $reading = AttrVal($hash->{NAME}, "reading", undef);
  my $device  = AttrVal($hash->{NAME}, "device", undef);
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my $ds   = $device." -- " if ($device);
  my $rds  = $reading." -- " if ($reading);
  my $export_string = $ds.$rds." -- ROWS EXPORTED TO FILE -- ";
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $export_string, $nrows); 
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));  
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);
  
  my $rows = $ds.$rds.$nrows;
  Log3 ($name, 3, "DbRep $name - Number of exported datasets from $hash->{DATABASE} to file ".AttrVal($name, "expimpfile", undef).": $rows");


  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall expfile_ParseDone finished");
  
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
 my $dbmodel    = $hash->{dbloghash}{DBMODEL};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $err=0;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall impfile_Push");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
     return "$name|''|''|$err";
 }
 
 my $infile = AttrVal($name, "expimpfile", undef);
 if (open(FH, "$infile")) {
     binmode (FH);
 } else {
     $err = encode_base64("could not open ".$infile.": ".$!,"");
     Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
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
 
 $dbh->begin_work();
 my $sth = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
 my $irowdone = 0;
 my $irowcount = 0;
 my $warn = 0;
 while (<FH>) {
     $al = $_;
     chomp $al; 
     my @alarr = split("\",\"", $al);
     my $i_timestamp = $alarr[0];
     $i_timestamp =~ tr/"//d;
     my $i_device    = $alarr[1];
     my $i_type      = $alarr[2];
     my $i_event     = $alarr[3];
     my $i_reading   = $alarr[4];
     my $i_value     = $alarr[5];
     my $i_unit      = $alarr[6] ? $alarr[6]: " ";
     $i_unit =~ tr/"//d;
     $irowcount++;
     next if(!$i_timestamp);  #leerer Datensatz
     
     # check ob TIMESTAMP Format ok ?
     my ($i_date, $i_time) = split(" ",$i_timestamp);
     if ($i_date !~ /(\d{4})-(\d{2})-(\d{2})/ || $i_time !~ /(\d{2}):(\d{2}):(\d{2})/) {
         $err = encode_base64("Format of date/time is not valid in row $irowcount of $infile. Must be format \"YYYY-MM-DD HH:MM:SS\" !","");
         Log3 ($name, 2, "DbRep $name -> ERROR - Import of datasets of file $infile was NOT done. Invalid date/time field format in row $irowcount !");    
         close(FH);
         $dbh->rollback;
         Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
         return "$name|''|''|$err";
     }
     
     # Daten auf maximale Länge (entsprechend der Feldlänge in DbLog DB create-scripts) beschneiden wenn nicht SQLite
     if ($dbmodel ne 'SQLITE') {
         $i_device   = substr($i_device,0, $dbrep_col{DEVICE});
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
             Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
             return "$name|''|''|$err";
         } else {
             $irowdone++
         }
       
     } else {
         $err = encode_base64("format error in in row $irowcount of $infile.","");
         Log3 ($name, 2, "DbRep $name -> ERROR - Import of datasets of file $infile was NOT done. Formaterror in row $irowcount !");     
         close(FH);
         $dbh->rollback;
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
         return "$name|''|''|$err";
     }   
 }
 
 $dbh->commit;
 $dbh->disconnect;
 close(FH);
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_Push finished");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$irowdone|$rt|$err";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Funktion impfile
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
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall impfile_PushDone");
  
  if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_PushDone finished");
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 

  my $import_string = " -- ROWS IMPORTED FROM FILE -- ";
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $import_string, $irowdone); 
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));  
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Number of imported datasets to $hash->{DATABASE} from file ".AttrVal($name, "expimpfile", undef).": $irowdone");  

  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall impfile_PushDone finished");
  
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
 my $dbuser      = $dbloghash->{dbuser};
 my $dblogname   = $dbloghash->{NAME};
 my $dbpassword  = $attr{"sec$dblogname"}{secret};
 my $dbmodel     = $dbloghash->{DBMODEL};
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall dbmeta_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_DoParse finished");
     return "$name|''|''|''|$err";
 }
 
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Liste der anzuzeigenden Parameter erzeugen, sonst alle ("%"), abhängig von $opt
 my $param = AttrVal($name, "showVariables", "%") if($opt eq "dbvars");
 $param = AttrVal($name, "showSvrInfo", "[A-Z_]") if($opt eq "svrinfo");
 $param = AttrVal($name, "showStatus", "%") if($opt eq "dbstatus");
 $param = "1" if($opt eq "tableinfo");        # Dummy-Eintrag für einen Schleifendurchlauf
 my @parlist = split(",",$param); 
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my @row_array;
 my $sth;
 my $sql;
 
 if ($opt ne "svrinfo") {
    foreach my $ple (@parlist) {
         if ($opt eq "dbvars") {
             $sql = "show global variables like '$ple';";
         } elsif ($opt eq "dbstatus") {
             $sql = "show global status like '$ple';";
         } elsif ($opt eq "tableinfo") {
             $sql = "select 
                     table_name,
                     table_schema,
                     round(sum(data_length+index_length)/1024/1024,2),
                     round(data_free/1024/1024,2),
                     row_format,
                     table_collation,
                     engine,
                     table_type,
                     create_time
                     from information_schema.tables group by table_name;";
         }
     
         Log3($name, 4, "DbRep $name - SQL execute: $sql"); 
 
         $sth = $dbh->prepare($sql); 
         eval {$sth->execute();};
 
         if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_DoParse finished");
             return "$name|''|''|''|$err";
         } else {
             while (my @line = $sth->fetchrow_array()) {
                 Log3 ($name, 5, "DbRep $name - SQL result: @line");
                 my $row = join("§", @line);
                 $row =~ s/ /_/g;
                 @line = split("§", $row);
                 if ($opt eq "tableinfo") {
                     $param = AttrVal($name, "showTableInfo", "[A-Z_]");
                     $param =~ s/,/\|/g;
                     $param =~ tr/%//d;
                     if($line[0] =~ m/($param)/i) {
                         push(@row_array, $line[0].".table_schema ".$line[1]);
                         push(@row_array, $line[0].".data_index_lenth_MB ".$line[2]);
                         push(@row_array, $line[0].".table_name ".$line[1]);
                         push(@row_array, $line[0].".data_free_MB ".$line[3]);
                         push(@row_array, $line[0].".row_format ".$line[4]);
                         push(@row_array, $line[0].".table_collation ".$line[5]);
                         push(@row_array, $line[0].".engine ".$line[6]);
                         push(@row_array, $line[0].".table_type ".$line[7]);
                         push(@row_array, $line[0].".create_time ".$line[8]);
                     }
                 } else {
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
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_DoParse finished");
             return "$name|''|''|''|$err";
         } else {
             my $key = "SQLITE_DB_FILENAME";
             push(@row_array, $key." ".$sf) if($key =~ m/($param)/i);
         }
         my @a = split(' ',qx(du -m /opt/fhem/fhem.db)) if ($^O =~ m/linux/i || $^O =~ m/unix/i);
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
             Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_DoParse finished");
             return "$name|''|''|''|$err";
         } else {
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
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_DoParse finished");
 
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
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall dbmeta_ParseDone");
  
   if ($err) {
      readingsSingleUpdate($hash, "errortext", $err, 1);
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_ParseDone finished");
      return;
  }
    
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  my @row_array = split("§", $rowlist);
  Log3 ($name, 5, "DbRep $name - SQL result decoded: \n@row_array") if(@row_array);
  
  my $pre = "VAR_" if($opt eq "dbvars");
  $pre    = "STAT_" if($opt eq "dbstatus");
  $pre    = "INFO_" if($opt eq "tableinfo");
  $pre    = "" if($opt eq "svrinfo");
  
  foreach my $row (@row_array) {
      my @a = split(" ", $row);
      my $k = $a[0];
      my $v = $a[1];
      readingsBulkUpdate($hash, $pre.$k, $v);
  }
  
  readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef)); 
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);
  
  # InternalTimer(time+0.5, "browser_refresh", $hash, 0);
  
  delete($hash->{HELPER}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall dbmeta_ParseDone finished");
  
return;
}

####################################################################################################
# Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub ParseAborted($) {
my ($hash) = @_;
my $name = $hash->{NAME};
my $dbh = $hash->{DBH}; 
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} timed out");
  $dbh->disconnect() if(defined($dbh));
  readingsSingleUpdate($hash, "state", "timeout", 1);
  delete($hash->{HELPER}{RUNNING_PID});
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
#  Zusammenstellung Aggregationszeiträume
####################################################################################################

sub collaggstr($$$$) {
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
             $runtime_string       = "all_between_timestamps";                                         # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
             $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);  
             $ll = 1;
         }
         
         # Monatsaggregation
         if ($aggregation eq "month") {
             $runtime_orig = $runtime;
             $runtime = $runtime+3600 if(dsttest($hash,$runtime,$aggsec));      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
             
             # Hilfsrechnungen
             my $rm   = strftime "%m", localtime($runtime);                    # Monat des aktuell laufenden Startdatums d. SQL-Select
             my $ry   = strftime "%Y", localtime($runtime);                    # Jahr des aktuell laufenden Startdatums d. SQL-Select
             my $dim  = $rm-2?30+($rm*3%7<4):28+!($ry%4||$ry%400*!($ry%100));  # Anzahl Tage des aktuell laufenden Monats f. SQL-Select
             Log3 ($name, 5, "DbRep $name - act year:  $ry, act month: $rm, days in month: $dim, endyear: $yestr, endmonth: $mestr"); 
                     
             $runtime_string       = strftime "%Y-%m", localtime($runtime);                            # für Readingname
             
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
                     $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>11);                     
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
             $runtime = $runtime+3600 if($i!=1 && dsttest($hash,$runtime,$aggsec));      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
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
                 $runtime = $runtime+3600 if(dsttest($hash,$runtime,$aggsec));           # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
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
             $runtime = $runtime+3600 if(dsttest($hash,$runtime,$aggsec));                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
                                               
             if((($tsstr gt $testr) ? $runtime : ($runtime+$aggsec-1)) > $epoch_seconds_end) {
                 $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime);                    
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
             } else {
                 $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime+$aggsec);   
             }
         Log3 ($name, 5, "DbRep $name - runtime_string: $runtime_string, runtime_string_first(begin): $runtime_string_first, runtime_string_next(end): $runtime_string_next");

         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime+$aggsec;         
         }
     
         # Stundenaggregation
         if ($aggregation eq "hour") {
             $runtime_string       = strftime "%Y-%m-%d_%H", localtime($runtime);                   # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
             $runtime = $runtime+3600 if(dsttest($hash,$runtime,$aggsec));                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
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
#                 Test auf Daylight saving time
####################################################################################################
sub dsttest ($$$) {
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
sub calcount ($$) {
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
#                 Test-Sub zu Testzwecken
####################################################################################################
sub testexit ($) {
my ($hash) = @_;
my $name = $hash->{NAME};

 if ( !DbRep_Connect($hash) ) {
     Log3 ($name, 2, "DbRep $name - DB connect failed. Database down ? ");
     readingsSingleUpdate($hash, "state", "disconnected", 1);
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
     <li> Selecion of datasets by usage of dynamically calclated time limits at execution time. </li>
     <li> Calculation of quantity of datasets of a Device/Reading-combination within adjustable time limits and several aggregations. </li>
     <li> The calculation of summary- , difference- , maximum- , minimum- and averageValues of numeric readings within adjustable time limits and several aggregations. </li>
     <li> The deletion of datasets. The containment of deletion can be done by Device and/or Reading as well as fix or dynamically calculated time limits at execution time. </li>
     <li> export of datasets to file (CSV-format). </li>
     <li> import of datasets from file (CSV-Format). </li>
     <li> rename of device names in datasets </li>
     <li> automatic rename of device names in datasets and other DbRep-definitions after FHEM "rename" command (see <a href="#DbRepAutoRename">DbRep-Agent</a>) </li>
     </ul></ul>
     <br>
     
  To activate the function "Autorename" the attribute "role" has to be assigned to a defined DbRep-device. The standard role after DbRep definition is "Client.
  Please read more in section <a href="#DbRepAutoRename">DbRep-Agent</a> . <br><br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting and Management of database content (DbLog)</a>.<br><br>
 
  <br>
   
  <b>Preparations </b> <br><br>
  
  The module requires the usage of a DbLog instance and the credentials of the database definition will be used. (currently tested with MySQL and SQLite). <br>
  Only the content of table "history" will be included. <br><br>
  
  Overview which other Perl-modules DbRep is using: <br><br>
    
  POSIX           <br>
  Time::HiRes     <br>
  Time::Local     <br>
  Scalar::Util    <br>
  DBI             <br>
  Blocking        (FHEM-module) <br><br>
  
  Due to performance reason the following index should be created in addition: <br>
  <code>
  ALTER TABLE 'fhem'.'history' ADD INDEX `Reading_Time_Idx` (`READING`, `TIMESTAMP`) USING BTREE;
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
    <li><b> averageValue </b> -  calculates the average value of readingvalues DB-column "VALUE") between period given by timestamp-<a href="#DbRepattr">attributes</a> which are set. 
                                 The reading to evaluate must be defined using attribute "reading".  </li> <br>
                                 
    <li><b> countEntries </b> -  provides the number of DB-entries between period given by timestamp-<a href="#DbRepattr">attributes</a> which are set. 
                                 If timestamp-attributes are not set, all entries in db will be count. The <a href="#DbRepattr">attributes</a> "device" and "reading" can be used to limit the evaluation.  </li> <br>
    
    <li><b> deviceRename </b> -  renames the device name of a device inside the connected database (Internal DATABASE).
                                 The devicename will allways be changed in the <b>entire</b> database. Possibly set time limits or restrictions by 
                                 <a href="#DbRepattr">attributes</a> device and/or reading will not be considered.  <br><br>
                                 
                                 <ul>
                                 <b>input format: </b>  set &lt;name&gt; deviceRename &lt;old device name&gt;,&lt;new device name&gt;  <br>               
                                 # The amount of renamed device names (datasets) will be displayed in reading "device_renamed". <br>
                                 # If the device name to be renamed was not found in the database, a WARNUNG would appear in reading "device_not_renamed". <br>
                                 # Appropriate entries will be written to Logfile with verbose=3.
                                 <br><br>
                                 </li> <br>
                                 </ul>                        
    
    <li><b> exportToFile </b> -  exports DB-entries to a file in CSV-format between period given by timestamp. 
                                 Limitations of selections can be set by <a href="#DbRepattr">attributes</a> Device and/or Reading. 
                                 The filename will be defined by <a href="#DbRepattr">attribute</a> "expimpfile" . </li> <br>
                                 
    <li><b> fetchrows </b>    -  provides <b>all</b> DB-entries between period given by timestamp-<a href="#DbRepattr">attributes</a>. 
                                 An aggregation which would possibly be set attribute will <b>not</b> considered.  </li> <br>
                                 
    <li><b> insert </b>       -  use it to insert data ito table "history" manually. Input values for Date, Time and Value are mandatory. The database fields for Type and Event will be filled in with "manual" automatically and the values of Device, Reading will be get from set <a href="#DbRepattr">attributes</a>.  <br><br>
                                 
                                 <ul>
                                 <b>input format: </b>   Date,Time,Value,[Unit]    <br>
                                 # Unit is optional, attributes of device, reading must be set ! <br>
                                 # If "Value=0" has to be inserted, use "Value = 0.0" to do it. <br><br>
                                 
                                 <b>example:</b>         2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # field lenth is maximum 32 (MYSQL) / 64 (POSTGRESQL) characters long, Spaces are NOT allowed in fieldvalues ! <br>
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
                                 # The fields "TIMESTAMP","DEVICE", "READING" have to be set. All other fields are optional.
                                 The file content will be imported transactional. That means all of the content will be imported or, in case of error, nothing of it. 
                                 If an extensive file will be used, DON'T set verbose = 5 because of a lot of datas would be written to the logfile in this case. 
                                 It could lead to blocking or overload FHEM ! <br><br>
                                 
                                 <b>Example: </b>        "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>
                                 </li> <br>
                                 </ul>    
    
    <li><b> sumValue </b>     -  calculates the amount of readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". The reading to evaluate must be defined using attribute "reading". Using this function is mostly reasonable if value-differences of readings are written to the database. </li> <br>  
    
    <li><b> maxValue </b>     -  calculates the maximum value of readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 The evaluation contains the timestamp of the <b>last</b> appearing of the identified maximum value within the given period.  </li> <br>
                                 
    <li><b> minValue </b>     -  calculates the miniimum value of readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 The evaluation contains the timestamp of the <b>first</b> appearing of the identified minimum value within the given period.  </li> <br>    
    
    <li><b> diffValue </b>    -  calculates the defference of the readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 This function is mostly reasonable if readingvalues are increasing permanently and don't write value-differences to the database. 
                                 The difference will be generated from the first available dataset (VALUE-Field) to the last available dataset between the 
								 specified time linits/aggregation. 
								 An possible counter overrun (restart with value "0") will be considered (compare <a href="#DbRepattr">attribute</a> "diffAccept"). <br>
								 If only one dataset will be found within the evalution period, no difference can be calculated  
								 and the reading "not_enough_data_in_period" with a list of concerned periods will be generated in that case. <br><br>
								 
                                 <ul>
                                 <b>Note: </b><br>
                                 Within the evaluation respectively aggregation period (day, week, month, etc.) AT LEAST two datasets per period MUST be 
								 available for calulation. Otherwise no difference can be calculated and diffValue will be print "0" for the respective period !
                                 <br>
                                 <br>
                                 </li>
                                 </ul>
                                 
    <li><b> delEntries </b>   -  deletes all database entries or only the database entries specified by <a href="#DbRepattr">attributes</a> Device and/or 
	                             Reading and the entered time period between "timestamp_begin", "timestamp_end" (if set) or "timeDiffToNow/timeOlderThan". <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" is set:  deletes db entries <b>from</b> this timestamp until current date/time <br>
                                 "timestamp_end" is set  :  deletes db entries <b>until</b> this timestamp <br>
                                 both Timestamps are set :  deletes db entries <b>between</b> these timestamps <br><br>
                                 
                                 Due to security reasons the attribute "allowDeletion" needs to be set to unlock the delete-function. <br>
                                 </li>
                                 </ul>
                                 
  <br>
  </ul></ul>
  
  <b>For all evaluation variants applies: </b> <br>
  In addition to the needed reading the device can be complemented to restrict the datasets for reporting / function. 
  If the time limit attributes are not set, the period from '1970-01-01 01:00:00' to the current date/time will be used as selection criterion.
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
 SQL-Wildcards (% _) can be used to setup the list arguments. 
 <br><br>
 
 <b>Note: </b> <br>
 After executing a get-funktion in detail view please make a browser refresh to see the results ! 
 <br><br>
 
 <ul><ul>
    <li><b> dbstatus </b> -  lists global informations about MySQL server status (e.g. informations related to cache, threads, bufferpools, etc. ). 
                             Initially all available informations are reported. Using the <a href="#DbRepattr">attribute</a> "showStatus" the quantity of
                             results can be limited to show only the desired values. Further detailed informations of items meaning are 
                             explained <a href=http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html>there</a>.  <br>
                             
                                 <br><ul>
                                 Example:  <br>
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
                                 Example:  <br>
                                 get &lt;name&gt; dbvars  <br>
                                 attr &lt;name&gt; showVariables %version%,%query_cache%    <br>               
                                 # Only readings containing "version" and "query_cache" in name will be created
                                 </li> 
                                 <br><br>
                                 </ul>                               

    <li><b> svrinfo </b> -  common database server informations, e.g. DBMS-version, server address and port and so on. The quantity of elements to get depends
                            on the database type. Using the <a href="#DbRepattr">attribute</a> "showSvrInfo" the quantity of results can be limited to show only 
                            the desired values. Further detailed informations of items meaning are explained                             
                            <a href=https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx>there</a>. <br>
                                 
                                 <br><ul>
                                 Example:  <br>
                                 get &lt;name&gt; svrinfo  <br>
                                 attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>               
                                 # Only readings containing "SQL_CATALOG_TERM" and "NAME" in name will be created
                                 </li> 
                                 <br><br>
                                 </ul>                                                      
                                 
    <li><b> tableinfo </b> -  access detailed informations about tables in MySQL database schema. The analyzed schematics are depend on the rights of the 
                              used  database user (default: the database schema of tables current,history). 
                              Using the<a href="#DbRepattr">attribute</a> "showTableInfo" the results can be limited. Further detailed informations  
                              of items meaning are explained <a href=http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html>there</a>.  <br>
                                 
                                 <br><ul>
                                 Example:  <br>
                                 get &lt;name&gt; tableinfo  <br>
                                 attr &lt;name&gt; showTableInfo current,history   <br>               
                                 # Only informations related to tables "current" and "history" will be created
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
  
  <b>Hint to SQL-Wildcard Usage:</b> <br>
  Within the attribute values of "device" and "reading" you may use SQL-Wildcards, "%" and "_". The character "%" stands for any some characters, but  
  the character "_" = stands for only one.  <br>
  This rule is valid to all functions <b>except</b> "insert", "deviceRename" and "delEntries". <br>
  The function "insert" doesn't allow setting the mentioned attributes containing the wildcard "%", the character "_" will evaluated as a normal character.<br>
  The deletion function "delEntries" evaluates both characters "$", "_" <b>NOT</b> as wildcards and delete device/readings only if they are entered in the 
  attribute as exactly as they are stored in the database . 
  In readings the wildcard character "%" will be replaced by "/" to meet the rules of allowed characters in readings.
  <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Aggregation of Device/Reading-selections. Possible is hour, day, week, month or "no". Delivers e.g. the count of database entries for a day (countEntries), Summation of difference values of a reading (sumValue) and so on. Using aggregation "no" (default) an aggregation don't happens but the output contaims all values of Device/Reading in the defined time period.  </li> <br>
  <li><b>allowDeletion </b>   - unlocks the delete-function  </li> <br>
  <li><b>device </b>          - selection of a particular device   </li> <br>
  <li><b>diffAccept </b>      - valid for function diffValue. diffAccept determines the threshold,  up to that a calaculated difference between two 
                                straight sequently datasets should be commenly accepted (default = 20). <br>
                                Hence faulty DB entries with a disproportional high difference value will be eliminated and don't tamper the result.
                                If a threshold overrun happens, the reading "diff-overrun_limit-&lt;diffLimit&gt;" will be generated 
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
  <li><b>expimpfile </b>      - Path/filename for data export/import </li> <br>
  <li><b>reading </b>         - selection of a particular reading   </li> <br>
  <li><b>readingNameMap </b>  - the name of the analyzed reading can be overwritten for output  </li> <br>
  <li><b>role </b>            - the role of the DbRep-device. Standard role is "Client". The role "Agent" is described in section <a href="#DbRepAutoRename">DbRep-Agent</a>. </li> <br>    
  <li><b>readingPreventFromDel </b>  - comma separated list of readings which are should prevent from deletion when a new operation starts  </li> <br>
  <li><b>showproctime </b>    - if set, the reading "sql_processing_time" shows the required execution time (in seconds) for the sql-requests. This is not calculated for a single sql-statement, but the summary of all sql-statements necessara for within an executed DbRep-function in background.   </li> <br>
  <li><b>showStatus </b>      - limits the sample space of command "get ... dbstatus". SQL-Wildcards (% _) can be used.    </li> <br>

                              <ul>
                              Example:    attr ... showStatus %uptime%,%qcache%  <br>
                              # Only readings with containing "uptime" and "qcache" in name will be shown <br>
                              </ul><br>  
  
  <li><b>showVariables </b>   - limits the sample space of command "get ... dbvars". SQL-Wildcards (% _) can be used.   </li> <br>

                              <ul>
                              Example:    attr ... showVariables %version%,%query_cache% <br>
                              # Only readings with containing "version" and "query_cache" in name will be shown <br>
                              </ul><br>  
                              
  <li><b>showSvrInfo </b>     - limits the sample space of command "get ... svrinfo". SQL-Wildcards (% _) can be used.    </li> <br>

                              <ul>
                              Example:    attr ... showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                              # Only readings with containing "SQL_CATALOG_TERM" and "NAME" in name will be shown <br>
                              </ul><br>  
                              
  <li><b>showTableInfo </b>   - limits the sample space of command "get ... tableinfo". SQL-Wildcards (% _) can be used.   </li> <br>

                              <ul>
                              Example:    attr ... showTableInfo current,history  <br>
                              # Only informations about tables "current" and "history" will be shown <br>
                              </ul><br>  
                              
  <li><b>timestamp_begin </b> - begin of data selection (*)  </li> <br>
  <li><b>timestamp_end </b>   - end of data selection. If not set the current date/time combination will be used. (*)  </li> <br>
  <li><b>timeDiffToNow </b>   - the begin of data selection will be set to the timestamp "&lt;current time&gt; - &lt;timeDiffToNow&gt;" dynamically (in seconds). Thereby always the last  &lt;timeDiffToNow&gt;-seconds will be considered (e.g. if set to 86400, always the last 24 hours should assumed). The Timestamp calculation will be done dynamically at execution time.     </li> <br>  
  <li><b>timeOlderThan </b>   - the end of data selection will be set to the timestamp "&lt;aktuelle Zeit&gt; - &lt;timeOlderThan&gt;" dynamically (in seconds). Always the datasets up to timestamp "&lt;current time&gt; - &lt;timeOlderThan&gt;" will be considered (e.g. if set to 86400, all datasets older than one day will be considered). The Timestamp calculation will be done dynamically at execution time. </li> <br> 

  <li><b>timeout </b>         - sets the timeout-value for Blocking-Call Routines in background (default 60 seconds)  </li> <br>
  </ul></ul>
  <br>
  
  (*) The format of timestamp is as used with DbLog "YYYY-MM-DD HH:MM:SS". For the attributes "timestamp_begin", "timestamp_end" you can also use one of: <br><br>
                              <ul>
                              <b>current_year_begin</b>     : set the timestamp-attribute to "&lt;current year&gt;-01-01 00:00:00" dynamically <br>
                              <b>current_year_end</b>       : set the timestamp-attribute to "&lt;current year&gt;-12-31 23:59:59" dynamically <br>
                              <b>previous_year_begin</b>    : set the timestamp-attribute to "&lt;previous year&gt;-01-01 00:00:00" dynamically  <br>
                              <b>previous_year_end</b>      : set the timestamp-attribute to "&lt;previous year&gt;-12-31 23:59:59" dynamically  <br>
                              </ul><br>
  
  Make sure that timestamp_begin < timestamp_end is fulfilled. <br><br>
  
  <b>Note </b> <br>
  
  If the attribute "timeDiffToNow" will be set, the attributes "timestamp_begin" respectively "timestamp_end" will be deleted if they were set before.
  The setting of "timestamp_begin" respectively "timestamp_end" causes the deletion of attribute "timeDiffToNow" if it was set before as well.
  <br><br>

</ul>

<a name="DbRepReadings"></a>
<b>Readings</b>

<br>
<ul>
  Regarding to the selected operation the reasults will be shown as readings. At the beginning of a new operation all old readings will be deleted to avoid 
  that unsuitable or invalid readings would remain.<br><br>
  
  In addition the following readings will be created: <br><br>
  
  <ul><ul>
  <li><b>state                      </b>  - contains the current state of evaluation. If warnings are occured (state = Warning) compare Readings
                                            "diff-overrun_limit-&lt;diffLimit&gt;" and "not_enough_data_in_period"  </li> <br>
  <li><b>errortext                  </b>     - description about the reason of an error state </li> <br>
  <li><b>background_processing_time </b>     - the processing time spent for operations in background/forked operation </li> <br>
  <li><b>sql_processing_time        </b>     - the processing time wasted for all sql-statements used for an operation </li> <br>
  <li><b>diff-overrun_limit-&lt;diffLimit&gt;</b>  - contains a list of pairs of datasets which have overrun the threshold (&lt;diffLimit&gt;) 
                                                     of calculated difference each other determined by attribute "diffAccept" (default=20). </li> <br>
  <li><b>not_enough_data_in_period</b>    - contains a list of time periods within only one dataset was found and therefor no difference calculation 
                                            could be done. Valid for function "diffValue". </li> <br>	
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
  function don't running to timeout set the timeout attribute to an appropriate value, especially if there are databases with huge datasets to evaluate. 
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
        attr Rep.Agent timeout 3600       <br>
        </code>
        <br>
        </ul>
  
  
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
  
  Zur Zeit werden folgende Operationen unterstützt: <br><br>
  
     <ul><ul>
     <li> Selektion aller Datensätze innerhalb einstellbarer Zeitgrenzen. </li>
     <li> Darstellung der Datensätze einer Device/Reading-Kombination innerhalb einstellbarer Zeitgrenzen. </li>
     <li> Selektion der Datensätze unter Verwendung von dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt. </li>
     <li> Berechnung der Anzahl von Datensätzen einer Device/Reading-Kombination unter Berücksichtigung von Zeitgrenzen und verschiedenen Aggregationen. </li>
     <li> Die Berechnung von Summen- , Differenz- , Maximum- , Minimum- und Durchschnittswerten von numerischen Readings in Zeitgrenzen und verschiedenen Aggregationen. </li>
     <li> Löschung von Datensätzen. Die Eingrenzung der Löschung kann durch Device und/oder Reading sowie fixer oder dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt erfolgen. </li>
     <li> Export von Datensätzen in ein File im CSV-Format </li>
     <li> Import von Datensätzen aus File im CSV-Format </li>
     <li> Umbenennen von Device-Namen in Datenbanksätzen </li>
     <li> automatisches Umbenennen von Device-Namen in Datenbanksätzen und DbRep-Definitionen nach FHEM "rename" Befehl (siehe <a href="#DbRepAutoRename">DbRep-Agent</a>) </li>
     </ul></ul>
     <br>
     
  Zur Aktivierung der Funktion "Autorename" wird dem definierten DbRep-Device mit dem Attribut "role" die Rolle "Agent" zugewiesen. Die Standardrolle nach Definition
  ist "Client". Mehr ist dazu im Abschnitt <a href="#DbRepAutoRename">DbRep-Agent</a> beschrieben. <br><br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting und Management von Datenbankinhalten (DbLog)</a>.<br><br>
 
  <b>Voraussetzungen </b> <br><br>
  
  Das Modul setzt den Einsatz einer oder mehrerer DBLog-Instanzen voraus. Es werden die Zugangsdaten dieser Datenbankdefinition genutzt (bisher getestet mit MySQL und SQLite). <br>
  Es werden nur Inhalte der Tabelle "history" berücksichtigt. <br><br>
  
  Überblick welche anderen Perl-Module DbRep verwendet: <br><br>
    
  POSIX           <br>
  Time::HiRes     <br>
  Time::Local     <br>
  Scalar::Util    <br>
  DBI             <br>
  Blocking        (FHEM-Modul) <br><br>
  
  Aus Performancegründen sollten zusätzlich folgender Index erstellt werden: <br>
  <code>
  ALTER TABLE 'fhem'.'history' ADD INDEX `Reading_Time_Idx` (`READING`, `TIMESTAMP`) USING BTREE;
  </code>
</ul>
<br>

<a name="DbRepdefine"></a>
<b>Definition</b>

<br>
<ul>
  <code>
    define &lt;name&gt; DbRep &lt;Name der DbLog-instanz&gt; 
  </code>
  
  <br><br>
  (&lt;Name der DbLog-instanz&gt; - es wird der Name der auszuwertenden DBLog-Datenbankdefinition angegeben <b>nicht</b> der Datenbankname selbst)

</ul>

<br><br>

<a name="DbRepset"></a>
<b>Set </b>
<ul>

 Zur Zeit gibt es folgende Set-Kommandos. Über sie werden die Auswertungen angestoßen und definieren selbst die Auswertungsvariante. 
 Nach welchen Kriterien die Datenbankinhalte durchsucht werden und die Aggregation erfolgt, wird durch <a href="#DbRepattr">Attribute</a> gesteuert. 
 <br><br>
 
 <ul><ul>
    <li><b> averageValue </b> -  berechnet den Durchschnittswert der Readingwerte (DB-Spalte "VALUE") in den gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein.  </li> <br>
                                 
    <li><b> countEntries </b> -  liefert die Anzahl der DB-Einträge in den gegebenen Zeitgrenzen (siehe <a href="#DbRepattr">Attribute</a>). 
                                 Sind die Timestamps nicht gesetzt werden alle Einträge gezählt. 
                                 Beschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading gehen in die Selektion mit ein.  </li> <br>

    <li><b> deviceRename </b> -  benennt den Namen eines Device innerhalb der angeschlossenen Datenbank (Internal DATABASE) um.
                                 Der Gerätename wird immer in der <b>gesamten</b> Datenbank umgesetzt. Eventuell gesetzte Zeitgrenzen oder Beschränkungen 
                                 durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading werden nicht berücksichtigt.  <br><br>
                                 
                                 <ul>
                                 <b>Eingabeformat: </b>  set &lt;name&gt; deviceRename &lt;alter Devicename&gt;,&lt;neuer Devicename&gt;  <br>               
                                 # Die Anzahl der umbenannten Device-Datensätze wird im Reading "device_renamed" ausgegeben. <br>
                                 # Wird der umzubenennende Gerätename in der Datenbank nicht gefunden, wird eine WARNUNG im Reading "device_not_renamed" ausgegeben. <br>
                                 # Entsprechende Einträge erfolgen auch im Logfile mit verbose=3
                                 <br><br>
                                 </li> <br>
                                 </ul>                                                       
                                 
    <li><b> exportToFile </b> -  exportiert DB-Einträge im CSV-Format in den gegebenen Zeitgrenzen. 
                                 Einschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading gehen in die Selektion mit ein. 
                                 Der Filename wird durch das <a href="#DbRepattr">Attribut</a> "expimpfile" bestimmt. </li> <br>
                                 
    <li><b> fetchrows </b>    -  liefert <b>alle</b> DB-Einträge in den gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). 
                                 Eine evtl. gesetzte Aggregation wird <b>nicht</b> berücksichtigt.  </li> <br>
                                 
    <li><b> insert </b>       -  Manuelles Einfügen eines Datensatzes in die Tabelle "history". Obligatorisch sind Eingabewerte für Datum, Zeit und Value. 
                                 Die Werte für die DB-Felder Type bzw. Event werden mit "manual" gefüllt, sowie die Werte für Device, Reading aus den gesetzten  <a href="#DbRepattr">Attributen </a> genommen.  <br><br>
                                 
                                 <ul>
                                 <b>Eingabeformat: </b>   Datum,Zeit,Value,[Unit]  <br>               
                                 # Unit ist optional, Attribute "reading" und "device" müssen gesetzt sein  <br>
                                 # Soll "Value=0" eingefügt werden, ist "Value = 0.0" zu verwenden. <br><br>
                                 
                                 <b>Beispiel: </b>        2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # die Feldlänge ist maximal 64 Zeichen lang , es sind KEINE Leerzeichen im Feldwert erlaubt !<br>
                                 <br>
								 
								 <b>Hinweis: </b><br>
                                 Bei der Eingabe ist darauf zu achten dass im beabsichtigten Aggregationszeitraum (Tag, Woche, Monat, etc.) MINDESTENS zwei 
								 Datensätze für die Funktion diffValue zur Verfügung stehen. Ansonsten kann keine Differenz berechnet werden und diffValue 
								 gibt in diesem Fall "0" in der betroffenen Periode aus !
                                 <br>
                                 <br>
								 </li>
                                 </ul>
    
    <li><b> importFromFile </b> - importiert Datensätze im CSV-Format aus einem File in die Datenbank. Der Filename wird durch das <a href="#DbRepattr">Attribut</a> "expimpfile" bestimmt. <br><br>
                                 
                                 <ul>
                                 <b>Datensatzformat: </b>  "TIMESTAMP","DEVICE","TYPE","EVENT","READING","VALUE","UNIT"  <br><br>              
                                 # Die Felder "TIMESTAMP","DEVICE", "READING" müssen gesetzt sein. Alle anderen Felder sind optional.
                                 Der Fileinhalt wird als Transaktion importiert, d.h. es wird der Inhalt des gesamten Files oder, im Fehlerfall, kein Datensatz des Files importiert. 
                                 Wird eine umfangreiche Datei mit vielen Datensätzen importiert sollte KEIN verbose=5 gesetzt werden. Es würden in diesem Fall sehr viele Sätze in
                                 das Logfile geschrieben werden was FHEM blockieren oder überlasten könnte. <br><br>
                                 
                                 <b>Beispiel: </b>        "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>
                                 </li> <br>
                                 </ul>    
    
    <li><b> sumValue </b>     -  berechnet die Summenwerte eines Readingwertes (DB-Spalte "VALUE") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading im <a href="#DbRepattr">Attribut</a> "reading" angegeben sein. 
                                 Diese Funktion ist sinnvoll wenn fortlaufend Wertedifferenzen eines Readings in die Datenbank geschrieben werden.  </li> <br>
    
    <li><b> maxValue </b>     -  berechnet den Maximalwert eines Readingwertes (DB-Spalte "VALUE") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein. 
                                 Die Auswertung enthält den Zeitstempel des ermittelten Maximumwertes innerhalb der Aggregation bzw. Zeitgrenzen.  
                                 Im Reading wird der Zeitstempel des <b>letzten</b> Auftretens vom Maximalwert ausgegeben falls dieser Wert im Intervall mehrfach erreicht wird. </li> <br>
                                 
    <li><b> minValue </b>     -  berechnet den Minimalwert eines Readingwertes (DB-Spalte "VALUE") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein. 
                                 Die Auswertung enthält den Zeitstempel des ermittelten Minimumwertes innerhalb der Aggregation bzw. Zeitgrenzen.  
                                 Im Reading wird der Zeitstempel des <b>ersten</b> Auftretens vom Minimalwert ausgegeben falls dieser Wert im Intervall mehrfach erreicht wird. </li> <br>
                                 
    <li><b> diffValue </b>    -  berechnet den Differenzwert eines Readingwertes (DB-Spalte "Value") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading im Attribut "reading" angegeben sein. 
                                 Diese Funktion ist z.B. zur Auswertung von Eventloggings sinnvoll, deren Werte sich fortlaufend erhöhen und keine Wertdifferenzen wegschreiben. <br>								 
                                 Es wird immer die Differenz aus dem Value-Wert des ersten verfügbaren Datensatzes und dem Value-Wert des letzten verfügbaren Datensatzes innerhalb der angegebenen
                                 Zeitgrenzen/Aggregation gebildet. <br>
								 Dabei wird ein Zählerüberlauf (Neubeginn bei 0) mit berücksichtigt (vergleiche <a href="#DbRepattr">Attribut</a> "diffAccept"). <br>
								 Wird in einer auszuwertenden Zeit- bzw. Aggregationsperiode nur ein Datensatz gefunden, kann keine Differenz berechnet werden 
								 und das Reading "not_enough_data_in_period" mit einer Liste der betroffenen Perioden wird erzeugt. <br><br>
								 
                                 <ul>
                                 <b>Hinweis: </b><br>
                                 Im Auswertungs- bzw. Aggregationszeitraum (Tag, Woche, Monat, etc.) MÜSSEN dem Modul pro Periode MINDESTENS zwei 
								 Datensätze zur Verfügung stehen. Ansonsten kann keine Differenz berechnet werden und diffValue ergibt in diesem Fall "0" !
                                 <br>
                                 <br>
                                 </li>
                                 </ul>
    
    <li><b> delEntries </b>   -  löscht alle oder die durch die <a href="#DbRepattr">Attribute</a> device und/oder reading definierten Datenbankeinträge. Die Eingrenzung über Timestamps erfolgt folgendermaßen: <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" gesetzt:  gelöscht werden DB-Einträge <b>ab</b> diesem Zeitpunkt bis zum aktuellen Datum/Zeit <br>
                                 "timestamp_end" gesetzt  :  gelöscht werden DB-Einträge <b>bis</b> bis zu diesem Zeitpunkt <br>
                                 beide Timestamps gesetzt :  gelöscht werden DB-Einträge <b>zwischen</b> diesen Zeitpunkten <br>
                                 
                                 <br>
                                 Aus Sicherheitsgründen muss das <a href="#DbRepattr">Attribut</a> "allowDeletion" gesetzt sein um die Löschfunktion freizuschalten. <br>
                                 </li>
                                 </ul>
                                 
  <br>
  </ul></ul>
  
  <b>Für alle Auswertungsvarianten gilt: </b> <br>
  Zusätzlich zu dem auszuwertenden Reading kann das Device mit angegeben werden um das Reporting nach diesen Kriterien einzuschränken. 
  Sind keine Zeitgrenzen-Attribute angegeben, wird '1970-01-01 01:00:00' und das aktuelle Datum/Zeit als Zeitgrenze genutzt. 
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
 Dabei können SQL-Wildcards (% _) verwendet werden. 
 <br><br>
 
 <b>Hinweis: </b> <br>
 Nach der Ausführung einer get-Funktion in der Detailsicht einen Browserrefresh durchführen um die Ergebnisse zu sehen ! 
 <br><br>
 
 
 <ul><ul>
    <li><b> dbstatus </b> -  listet globale Informationen zum MySQL Serverstatus (z.B. Informationen zum Cache, Threads, Bufferpools, etc. ). 
                             Es werden zunächst alle verfügbaren Informationen berichtet. Mit dem <a href="#DbRepattr">Attribut</a> "showStatus" kann die 
                             Ergebnismenge eingeschränkt werden, um nur gewünschte Ergebnisse abzurufen. Detailinformationen zur Bedeutung der einzelnen Readings 
                             sind <a href=http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html>hier</a> verfügbar.  <br>
                             
                                 <br><ul>
                                 Bespiel:  <br>
                                 get &lt;name&gt; dbstatus  <br>
                                 attr &lt;name&gt; showStatus %uptime%,%qcache%    <br>               
                                 # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthalten 
                                 </li> 
                                 <br><br>
                                 </ul>                               
                                 
    <li><b> dbvars </b> -  zeigt die globalen Werte der MySQL Systemvariablen. Enthalten sind zum Beispiel Angaben zum InnoDB-Home, dem Datafile-Pfad, 
                           Memory- und Cache-Parameter, usw. Die Ausgabe listet zunächst alle verfügbaren Informationen auf. Mit dem 
                           <a href="#DbRepattr">Attribut</a> "showVariables" kann die Ergebnismenge eingeschränkt werden um nur gewünschte Ergebnisse 
                           abzurufen. Weitere Informationen zur Bedeutung der ausgegebenen Variablen sind 
                           <a href=http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html>hier</a> verfügbar. <br>
                           
                                 <br><ul>
                                 Bespiel:  <br>
                                 get &lt;name&gt; dbvars  <br>
                                 attr &lt;name&gt; showVariables %version%,%query_cache%    <br>               
                                 # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten
                                 </li> 
                                 <br><br>
                                 </ul>                               

    <li><b> svrinfo </b> -  allgemeine Datenbankserver-Informationen wie z.B. die DBMS-Version, Serveradresse und Port usw. Die Menge der Listenelemente 
                            ist vom Datenbanktyp abhängig. Mit dem <a href="#DbRepattr">Attribut</a> "showSvrInfo" kann die Ergebnismenge eingeschränkt werden.
                            Weitere Erläuterungen zu den gelieferten Informationen sind 
                            <a href=https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx>hier</a> zu finden. <br>
                                 
                                 <br><ul>
                                 Bespiel:  <br>
                                 get &lt;name&gt; svrinfo  <br>
                                 attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>               
                                 # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten
                                 </li> 
                                 <br><br>
                                 </ul>                                                      
                                 
    <li><b> tableinfo </b> -  ruft Detailinformationen der in einem MySQL-Schema angelegten Tabellen ab. Die ausgewerteten Schemata sind abhängig von den Rechten 
                              des verwendeten Datenbankusers (default: das DB-Schema der current/history-Tabelle). 
                              Mit dem <a href="#DbRepattr">Attribut</a> "showTableInfo" können die Ergebnisse eingeschränkt werden. Erläuterungen zu den erzeugten 
                              Readings sind  <a href=http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html>hier</a> zu finden.  <br>
                                 
                                 <br><ul>
                                 Bespiel:  <br>
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
  Innerhalb der Attribut-Werte für "device" und "reading" können SQL-Wildcards, "%" und "_", angegeben werden. Dabei ist "%" = beliebig 
  viele Zeichen und "_" = ein Zeichen.  <br>
  Dies gilt für alle Funktionen <b>außer</b> "insert", "deviceRename" und "delEntries". <br>
  Die Funktion "insert" erlaubt nicht dass die genannten Attribute das Wildcard "%" enthalten, "_" wird als normales Zeichen gewertet.<br>
  Die Löschfunktion "delEntries" wertet die Zeichen "$", "_" <b>NICHT</b> als Wildcards und löscht nur Device/Readings die exakt wie in den Attributen angegeben 
  in der DB gespeichert sind. <br>
  In den Readings wird das Wildcardzeichen "%" durch "/" ersetzt um die Regeln für erlaubte Zeichen in Readings einzuhalten.
  <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Zusammenfassung der Device/Reading-Selektionen in Stunden,Tages,Kalenderwochen,Kalendermonaten oder "no". Liefert z.B. die Anzahl der DB-Einträge am Tag (countEntries), Summation von Differenzwerten eines Readings (sumValue), usw. Mit Aggregation "no" (default) erfolgt keine Zusammenfassung in einem Zeitraum sondern die Ausgabe ergibt alle Werte eines Device/Readings zwischen den definierten Zeiträumen.  </li> <br>
  <li><b>allowDeletion </b>   - schaltet die Löschfunktion des Moduls frei   </li> <br>
  <li><b>device </b>          - Abgrenzung der DB-Selektionen auf ein bestimmtes Device. </li> <br>
  <li><b>diffAccept </b>      - gilt für Funktion diffValue. diffAccept legt fest bis zu welchem Schwellenwert eine berechnete positive Werte-Differenz 
                                zwischen zwei unmittelbar aufeinander folgenden Datensätzen akzeptiert werden soll (Standard ist 20). <br>
								Damit werden fehlerhafte DB-Einträge mit einem unverhältnismäßig hohen Differenzwert von der Berechnung ausgeschlossen und 
								verfälschen nicht das Ergebnis. Sollten Schwellenwertüberschreitungen vorkommen, wird das Reading "diff-overrun_limit-&lt;diffLimit&gt;"
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
  <li><b>expimpfile </b>      - Pfad/Dateiname für Export/Import in/aus einem File.  </li> <br>
  <li><b>reading </b>         - Abgrenzung der DB-Selektionen auf ein bestimmtes Reading   </li> <br>              
  <li><b>readingNameMap </b>  - der Name des ausgewerteten Readings wird mit diesem String für die Anzeige überschrieben   </li> <br>
  <li><b>readingPreventFromDel </b>  - Komma separierte Liste von Readings die vor einer neuen Operation nicht gelöscht werden sollen  </li> <br>
  <li><b>role </b>            - die Rolle des DbRep-Device. Standard ist "Client". Die Rolle "Agent" ist im Abschnitt <a href="#DbRepAutoRename">DbRep-Agent</a> beschrieben.   </li> <br>  
  <li><b>showproctime </b>    - wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die SQL-Ausführung der durchgeführten Funktion. Dabei wird nicht ein einzelnes SQl-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der jeweiligen Funktion betrachtet.   </li> <br>
  <li><b>showStatus </b>      - grenzt die Ergebnismenge des Befehls "get ... dbstatus" ein. Es können SQL-Wildcards (% _) verwendet werden.    </li> <br>

                              <ul>
                              Bespiel:    attr ... showStatus %uptime%,%qcache%  <br>
                              # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthalten <br>
                              </ul><br>  
  
  <li><b>showVariables </b>   - grenzt die Ergebnismenge des Befehls "get ... dbvars" ein. Es können SQL-Wildcards (% _) verwendet werden.    </li> <br>

                              <ul>
                              Bespiel:    attr ... showVariables %version%,%query_cache% <br>
                              # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten <br>
                              </ul><br>  
                              
  <li><b>showSvrInfo </b>     - grenzt die Ergebnismenge des Befehls "get ... svrinfo" ein. Es können SQL-Wildcards (% _) verwendet werden.    </li> <br>

                              <ul>
                              Bespiel:    attr ... showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                              # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten <br>
                              </ul><br>  
                              
  <li><b>showTableInfo </b>   - grenzt die Ergebnismenge des Befehls "get ... tableinfo" ein. Es können SQL-Wildcards (% _) verwendet werden.    </li> <br>

                              <ul>
                              Bespiel:    attr ... showTableInfo current,history  <br>
                              # Es werden nur Information der Tabellen "current" und "history" angezeigt <br>
                              </ul><br>  
                              
  <li><b>timestamp_begin </b> - der zeitliche Beginn für die Datenselektion (*)   </li> <br>
  <li><b>timestamp_end </b>   - das zeitliche Ende für die Datenselektion. Wenn nicht gesetzt wird immer die aktuelle Datum/Zeit-Kombi für das Ende der Selektion eingesetzt. (*)  </li> <br>
  <li><b>timeDiffToNow </b>   - der Selektionsbeginn wird auf den Zeitpunkt "&lt;aktuelle Zeit&gt; - &lt;timeDiffToNow&gt;" gesetzt (in Sekunden). Es werden immer die letzten &lt;timeDiffToNow&gt;-Sekunden berücksichtigt (z.b. 86400 wenn immer die letzten 24 Stunden in die Selektion eingehen sollen). Die Timestampermittlung erfolgt dynamisch zum Ausführungszeitpunkt.     </li> <br>  
  <li><b>timeOlderThan </b>   - das Selektionsende wird auf den Zeitpunkt "&lt;aktuelle Zeit&gt; - &lt;timeOlderThan&gt;" gesetzt (in Sekunden). Dadurch werden alle Datensätze bis zu dem Zeitpunkt "&lt;aktuelle Zeit&gt; - &lt;timeOlderThan&gt;" berücksichtigt (z.b. wenn auf 86400 gesetzt werden alle Datensätze die älter als ein Tag sind berücksichtigt). Die Timestampermittlung erfolgt dynamisch zum Ausführungszeitpunkt. </li> <br> 
  <li><b>timeout </b>         - das Attribut setzt den Timeout-Wert für die Blocking-Call Routinen (Standard 60) in Sekunden  </li> <br>
  </ul></ul>
  <br>
  
  (*) Das Format von Timestamp ist wie in DbLog "YYYY-MM-DD HH:MM:SS". Für die Attribute "timestamp_begin", "timestamp_end" kann ebenso eine der folgenden Eingaben verwendet werden: <br><br>
                              <ul>
                              <b>current_year_begin</b>     : belegt das timestamp-Attribut dynamisch mit "&lt;aktuelles Jahr&gt;-01-01 00:00:00" <br>
                              <b>current_year_end</b>       : belegt das timestamp-Attribut dynamisch mit "&lt;aktuelles Jahr&gt;-12-31 23:59:59" <br>
                              <b>previous_year_begin</b>    : belegt das timestamp-Attribut dynamisch mit "&lt;voriges Jahr&gt;-01-01 00:00:00"   <br>
                              <b>previous_year_end</b>      : belegt das timestamp-Attribut dynamisch mit "&lt;voriges Jahr&gt;-12-31 23:59:59"   <br>
                              </ul><br>
  
  Natürlich sollte man immer darauf achten dass timestamp_begin < timestamp_end ist.  <br><br>
  
  <b>Hinweis </b> <br>
  
  Wird das Attribut "timeDiffToNow" gesetzt, werden die evtentuell gesetzten Attribute "timestamp_begin" bzw. "timestamp_end" gelöscht.
  Das Setzen von "timestamp_begin" bzw. "timestamp_end" bedingt die Löschung von Attribut "timeDiffToNow" wenn es vorher gesetzt war.
  <br><br>

</ul>

<a name="DbRepReadings"></a>
<b>Readings</b>

<br>
<ul>
  Abhängig von der ausgeführten DB-Operation werden die Ergebnisse in entsrechenden Readings dargestellt. Zu Beginn einer neuen Operation werden alle alten Readings
  einer vorangegangenen Operation gelöscht um den Verbleib unpassender bzw. ungültiger Readings zu vermeiden.  <br><br>
  
  Zusätzlich werden folgende Readings erzeugt: <br><br>
  
  <ul><ul>
  <li><b>state                      </b>  - enthält den aktuellen Status der Auswertung. Wenn Warnungen auftraten (state = Warning) vergleiche Readings
                                            "diff-overrun_limit-&lt;diffLimit&gt;" und "not_enough_data_in_period"  </li> <br>
  <li><b>errortext                  </b>  - Grund eines Fehlerstatus </li> <br>
  <li><b>background_processing_time </b>  - die gesamte Prozesszeit die im Hintergrund/Blockingcall verbraucht wird </li> <br>
  <li><b>sql_processing_time        </b>  - der Anteil der Prozesszeit die für alle SQL-Statements der ausgeführten Operation verbraucht wird </li> <br>
  <li><b>diff-overrun_limit-&lt;diffLimit&gt;</b>  - enthält eine Liste der Wertepaare die eine durch das Attribut "diffAccept" festgelegte Differenz
                                                     &lt;diffLimit&gt; (Standard: 20) überschreiten. Gilt für Funktion "diffValue". </li> <br>
  <li><b>not_enough_data_in_period</b>    - enthält eine Liste der Zeitperioden in denen nur ein einziger Datensatz gefunden wurde und dadurch keine 
                                            Differenzberechnung durchgeführt werden konnte.  Gilt für Funktion "diffValue". </li> <br>													 
													
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
        attr Rep.Agent timeout 3600       <br>
        </code>
        <br>
        </ul>
  
</ul>

=end html_DE
=cut
