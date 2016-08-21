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
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.# 
#
###########################################################################################################
#
# create additional indexes due to performance purposes:
#
# ALTER TABLE 'fhem'.'history' ADD INDEX `Reading_Time_Idx` (`READING`, `TIMESTAMP`) USING BTREE;
#
# Definition: define <name> DbRep <DbLog-Device>
#
# This module uses credentials of 93_DbLog.pm - devices
#
###########################################################################################################
#  Versions History:
#
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
use DBI;
use Blocking;
use Time::Local;
no if $] >= 5.017011, warnings => 'experimental';  


###################################################################################
# DbRep_Initialize
###################################################################################
sub DbRep_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}        = "DbRep_Define";
 $hash->{UndefFn}      = "DbRep_Undef"; 
 # $hash->{NotifyFn}     = "DbRep_Notify";
 $hash->{SetFn}        = "DbRep_Set";
 $hash->{AttrFn}       = "DbRep_Attr";
 
 $hash->{AttrList} =   "disable:1,0 ".
                       "reading ".
                       "allowDeletion:1,0 ".
                       "readingNameMap ".
                       "device ".
                       "aggregation:hour,day,week,month,no ".
                       "showproctime:1,0 ".
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
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define <name> DbRep <DbLog-Device> 
  #       ($hash)  [1]        [2]      
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
        return "You need to specify more parameters.\n". "Format: define <name> DbRep <DbLog-Device> <Reading> <Timestamp-Begin> <Timestamp-Ende>";
        }
        
  $hash->{HELPER}{DBLOGDEVICE} = $a[2];
  
  RemoveInternalTimer($hash);
  InternalTimer(time+5, 'DbRep_firstconnect', $hash, 0);
  
  Log3 ($name, 3, "DbRep $name - initialized");
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
  my $setlist; 
  
  $setlist = "Unknown argument $opt, choose one of ".
             "sumValue:noArg ".
             "averageValue:noArg ".
             "delEntries:noArg ".
             "maxValue:noArg ".
             "fetchrows:noArg ".
             "diffValue:noArg ".
             "insert ".
             "countEntries:noArg ";
  
  return if(IsDisabled($name));
  
  if ($opt eq "sumValue") {
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading for analyze is not set !";
      }
      sqlexec($hash,"sum");
      
  } elsif ($opt eq "countEntries") {
      sqlexec($hash,"count"); 
      
  } elsif ($opt eq "averageValue") {  
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading for analyze is not set !";
      }
      sqlexec($hash,"average");
      
  } elsif ($opt eq "fetchrows") {
      sqlexec($hash,"fetchrows");
      
  } elsif ($opt eq "maxValue") {   
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading for analyze is not set !";
      }
      sqlexec($hash,"max");
      
  } elsif ($opt eq "delEntries") {
      if (!AttrVal($hash->{NAME}, "allowDeletion", undef)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }        
      sqlexec($hash,"del");
      
  } elsif ($opt eq "diffValue") {   
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading for analyze is not set !";
      }
      sqlexec($hash,"diff");
  
  } elsif ($opt eq "insert") { 
      if ($prop) {
          if (!AttrVal($hash->{NAME}, "device", "") || !AttrVal($hash->{NAME}, "reading", "") ) {
              return " The attribute \"device\" and/or \"reading\" is not set. It's mandatory to complete dataset for manual insert !";
          }
    
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
          
          # Daten auf maximale Länge (entsprechend der Feldlänge in DbLog DB create-scripts) beschneiden
          $i_device   = substr($i_device,0, 32);
          $i_reading  = substr($i_reading,0, 32);
          $i_value    = substr($i_value,0, 32);
          $i_unit     = substr($i_unit,0, 32) if($i_unit);
          
          $hash->{helper}{I_TIMESTAMP} = $i_timestamp;
          $hash->{helper}{I_DEVICE}    = $i_device;
          $hash->{helper}{I_READING}   = $i_reading;
          $hash->{helper}{I_VALUE}     = $i_value;
          $hash->{helper}{I_UNIT}      = $i_unit;
          $hash->{helper}{I_TYPE}      = my $i_type = "manual";
          $hash->{helper}{I_EVENT}     = my $i_event = "manual";          
          
      } else {
          return "Data to insert to table 'history' are needed like this pattern: 'Date,Time,Value,[Unit]'. \"Unit\" is optional. Spaces are not allowed !";
      }
      
      sqlexec($hash,"insert");
  }
  else  
  {
      return "$setlist";
  }  
return undef;
}

###################################################################################
# DbRep_Attr
###################################################################################
sub DbRep_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
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
        if ($aName eq "timeout") {
            unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
        } 
        if ($aName eq "readingNameMap") {
            unless ($aVal =~ m/^[A-Za-z\d_\.-]+$/) { return " Unsupported character in $aName found. Use only A-Z a-z _ . -";}
        }
        if ($aName eq "timeDiffToNow") {
            unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places. It's the time (in seconds) before current time used as start of selection. Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
        } 
        if ($aName eq "timeOlderThan") {
            unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places. It's the time (in seconds) before current time used as end of selection. Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
        } 
    }
return undef;
}


###################################################################################
# DbRep_Notify Eventverarbeitung
###################################################################################

sub DbRep_Notify($$) {
 my ($dbrep, $dev) = @_;
 my $myName  = $dbrep->{NAME}; # Name des eigenen Devices
 my $devName = $dev->{NAME}; # Name des Devices welches Events erzeugt hat
 
 return if(IsDisabled($myName)); # Return if the module is disabled

 my $max = int(@{$dev->{CHANGED}}); # number of events / changes

 for (my $i = 0; $i < $max; $i++) {
     my $s = $dev->{CHANGED}[$i];
     next if(!defined($s));
     my ($evName, $val) = split(" ", $s, 2); # resets $1
     next if($devName !~ m/^$myName$/);
     
     if ($evName =~ m/done/) {
         # Log3 ($myName, 3, "DbRep $myName - Event received - device: $myName Event: $evName");
         # fhem ("trigger WEB JS:location.reload('false')");
         # FW_directNotify("#FHEMWEB:WEB", "location.reload('false')", "");
         # map {FW_directNotify("#FHEMWEB:$_", "location.reload('false')", "")} devspec2array("WEB.*");
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
 
 BlockingKill($hash->{helper}{RUNNING_PID}) if (exists($hash->{helper}{RUNNING_PID}));
    
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
  
  if ( !DbRep_Connect($hash) ) {
      Log3 ($name, 2, "DbRep $name - DB connect failed. Credentials of $hash->{dbloghash}{NAME} are valid and database reachable ?");
      readingsSingleUpdate($hash, "state", "disconnected", 1);
  } else {
      Log3 ($name, 3, "DbRep $name - Connectiontest to db $dbconn was successful");
      my $dbh = $hash->{DBH}; 
      $dbh->disconnect();
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
    
    Log3 ($name, 3, "DbRep $name - Waiting for database connection to test");
    
    return 0;
  }

  $hash->{DBH} = $dbh;

  readingsSingleUpdate($hash, "state", "connected", 1);
  
  return 1;
}

################################################################################################################
#  Hauptroutine
################################################################################################################

sub sqlexec($$) {
 my ($hash,$opt) = @_;
 my $name        = $hash->{NAME}; 
 my $to          = AttrVal($name, "timeout", "60");
 my $reading     = AttrVal($hash->{NAME}, "reading", undef);
 my $aggregation = AttrVal($hash->{NAME}, "aggregation", "no");   # wichtig !! aggregation niemals "undef"
 my $device      = AttrVal($hash->{NAME}, "device", undef);
 my $aggsec;
 
 # Test-Aufbau DB-Connection
 #if ( !DbRep_Connect($hash) ) {
 #    Log3 ($name, 2, "DbRep $name - DB connect failed. Database down ? ");
 #    readingsSingleUpdate($hash, "state", "disconnected", 1);
 #    return;
 #} else {
 #    my $dbh = $hash->{DBH};
 #    $dbh->disconnect;
 #}
 
 if (exists($hash->{helper}{RUNNING_PID})) {
     Log3 ($name, 3, "DbRep $name - Warning: old process $hash->{helper}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
     BlockingKill($hash->{helper}{RUNNING_PID});
 }
 
 # alte Readings löschen
 delete $defs{$name}{READINGS};
 
 readingsSingleUpdate($hash, "state", "running", 1);
 
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # Ausgaben und Zeitmanipulationen
 Log3 ($name, 4, "DbRep $name - -------- New selection --------- "); 
 Log3 ($name, 4, "DbRep $name - Aggregation: $aggregation"); 
        
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
     $tsbegin = AttrVal($hash->{NAME}, "timestamp_begin", "");  
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
        
 # Umwandeln in Epochesekunden bzw. setzen Differenz zur akt. Zeit wenn attr "timeDiffToNow" gesetzt Beginn
 my $epoch_seconds_begin = timelocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900) if($tsbegin);
 $epoch_seconds_begin = AttrVal($hash->{NAME}, "timeDiffToNow", undef) ? (time() - AttrVal($hash->{NAME}, "timeDiffToNow", undef)) : $epoch_seconds_begin;
 Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp begin: ".AttrVal($hash->{NAME}, "timeDiffToNow", undef)." sec") if(AttrVal($hash->{NAME}, "timeDiffToNow", undef)); 
 
 Log3 ($name, 5, "DbRep $name - Timestamp begin epocheseconds: $epoch_seconds_begin"); 
 my $tsbegin_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin);
 Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: $tsbegin_string"); 

 
 # extrahieren der Einzelwerte von Datum/Zeit Ende bzw. Selektionsende dynamisch auf <aktuelle Zeit>-timeOlderThan setzen
 my ($yyyy2, $mm2, $dd2, $hh2, $min2, $sec2) = ($tsend =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
        
 # Umwandeln in Epochesekunden Endezeit
 my $epoch_seconds_end = timelocal($sec2, $min2, $hh2, $dd2, $mm2-1, $yyyy2-1900);
 $epoch_seconds_end = AttrVal($hash->{NAME}, "timeOlderThan", undef) ? (time() - AttrVal($hash->{NAME}, "timeOlderThan", undef)) : $epoch_seconds_end;
 Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp end: ".AttrVal($hash->{NAME}, "timeOlderThan", undef)." sec") if(AttrVal($hash->{NAME}, "timeOlderThan", undef)); 
 
 Log3 ($name, 5, "DbRep $name - Timestamp end epocheseconds: $epoch_seconds_end"); 
 my $tsend_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
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

 if ($opt eq "sum") {
     $hash->{helper}{RUNNING_PID} = BlockingCall("sumval_DoParse", "$name§$device§$reading§$ts", "sumval_ParseDone", $to, "ParseAborted", $hash);
     
 } elsif ($opt eq "count") {
     $hash->{helper}{RUNNING_PID} = BlockingCall("count_DoParse", "$name§$device§$reading§$ts", "count_ParseDone", $to, "ParseAborted", $hash);

 } elsif ($opt eq "average") {      
     $hash->{helper}{RUNNING_PID} = BlockingCall("averval_DoParse", "$name§$device§$reading§$ts", "averval_ParseDone", $to, "ParseAborted", $hash); 
    
 } elsif ($opt eq "fetchrows") {
     $runtime_string_first = defined($epoch_seconds_begin) ? strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin) : "1970-01-01 01:00:00";
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
             
     $hash->{helper}{RUNNING_PID} = BlockingCall("fetchrows_DoParse", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "fetchrows_ParseDone", $to, "ParseAborted", $hash);
    
 } elsif ($opt eq "max") {        
     $hash->{helper}{RUNNING_PID} = BlockingCall("maxval_DoParse", "$name§$device§$reading§$ts", "maxval_ParseDone", $to, "ParseAborted", $hash);   
         
 } elsif ($opt eq "del") {
     $runtime_string_first = AttrVal($hash->{NAME}, "timestamp_begin", undef) ? strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin) : "1970-01-01 01:00:00";
     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
         
     $hash->{helper}{RUNNING_PID} = BlockingCall("del_DoParse", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "del_ParseDone", $to, "ParseAborted", $hash);        
 
 }  elsif ($opt eq "diff") {        
     $hash->{helper}{RUNNING_PID} = BlockingCall("diffval_DoParse", "$name§$device§$reading§$ts", "diffval_ParseDone", $to, "ParseAborted", $hash);   
         
 }  elsif ($opt eq "insert") { 
     $hash->{helper}{RUNNING_PID} = BlockingCall("insert_Push", "$name", "insert_Done", $to, "ParseAborted", $hash);   
         
 }

return;
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

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall averval_DoParse");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall averval_DoParse finished");
     return "$name|''|$device|$reading|''|1";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 
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
     my $sql = "SELECT AVG(VALUE) FROM `history` ";
     $sql .= "where " if($reading || $device || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME}, "timeOlderThan",undef));
     $sql .= "DEVICE = '$device' " if($device);
     $sql .= "AND " if($device && $reading);
     $sql .= "READING = '$reading' " if($reading);
     $sql .= "AND " if((AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME}, "timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef)) && ($device || $reading));
     $sql .= "TIMESTAMP BETWEEN '$runtime_string_first' AND '$runtime_string_next' " if(AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef));
     $sql .= ";";
     
     Log3 ($name, 4, "DbRep $name - SQL to execute: $sql");        
     
     my $line;
     
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall averval_DoParse finished");
         return "$name|''|$device|$reading|''|1";
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
  my $reading    = $a[3];
  my $rt         = $a[4];
  my $dberr      = $a[5];
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall averval_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
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

  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  
  readingsEndUpdate($hash, 1);
  
  delete($hash->{helper}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall averval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage count
####################################################################################################

sub count_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash        = $defs{$name};
 
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall count_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall count_DoParse finished");
     return "$name|''|$device|$reading|''|1";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 
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
     my $sql = "SELECT COUNT(*) FROM `history` ";
     $sql .= "where " if($reading || $device || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME}, "timeOlderThan",undef));
     $sql .= "DEVICE = '$device' " if($device);
     $sql .= "AND " if($device && $reading);
     $sql .= "READING = '$reading' " if($reading);
     $sql .= "AND " if((AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME}, "timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef)) && ($device || $reading));
     $sql .= "TIMESTAMP BETWEEN '$runtime_string_first' AND '$runtime_string_next' " if(AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef));
     $sql .= ";";
     
     Log3($name, 4, "DbRep $name - SQL to execute: $sql");        
     
     my $line;
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall count_DoParse finished");
         return "$name|''|$device|$reading|''|1";
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
  my $reading    = $a[3];
  my $rt         = $a[4];
  my $dberr      = $a[5];
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall count_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
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

  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{helper}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall count_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage maxValue
####################################################################################################

sub maxval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash         = $defs{$name};
 
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall maxval_DoParse");
  
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
     return "$name|''|$device|$reading|''|1";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 
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
     $sql .= "`DEVICE` = '$device' AND " if($device);
     $sql .= "`READING` = '$reading' AND " if($reading); 
     $sql .= "TIMESTAMP BETWEEN ? AND ? ORDER BY TIMESTAMP ;"; 
     
     # SQL zusammenstellen für Logausgabe
     my $sql1 = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql1 .= "`DEVICE` = '$device' AND " if($device);
     $sql1 .= "`READING` = '$reading' AND " if($reading); 
     $sql1 .= "TIMESTAMP BETWEEN '$runtime_string_first' AND '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL to execute: $sql1"); 
     
     $runtime_string = encode_base64($runtime_string,"");
     my $sth = $dbh->prepare($sql);   
     
     eval {$sth->execute($runtime_string_first, $runtime_string_next);};
     
     if ($@) {
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
         return "$name|''|$device|$reading|''|1";
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
  
 my $rowlist = join('|', @row_array); 
 Log3 ($name, 5, "DbRep $name -> row_array: @row_array");
     
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
  
 Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_DoParse finished");
 
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
  my $reading    = $a[3];
  my $rt         = $a[4];
  my $dberr      = $a[5];
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall maxval_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_ParseDone finished");
      return;
  }
  
  my @row_array = split("\\|", $rowlist);
  
  Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");
  
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
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          readingsSingleUpdate($hash, "state", "error", 1);
          delete($hash->{helper}{RUNNING_PID});
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in maxValue function. Faulty dataset was \nTIMESTAMP: $a[2] $a[3], DEVICE: $device, READING: $reading, VALUE: $value. \nLeaving ...");
          Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_ParseDone finished");
          return;
      }
      
      $a[3]              =~ s/:/-/g if($a[3]);          # substituieren unsopported characters -> siehe fhem.pl
      my $timestamp      = $a[3]?$a[2]."_".$a[3]:$a[2];
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      Log3 ($name, 4, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
             
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
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
 
  foreach my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key});
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
             
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{helper}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall maxval_ParseDone finished");
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage diffValue
####################################################################################################

sub diffval_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash         = $defs{$name};
 
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall diffval_DoParse");
  
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
     return "$name|''|$device|$reading|''|1";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 
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
     $sql .= "`DEVICE` = '$device' AND " if($device);
     $sql .= "`READING` = '$reading' AND " if($reading); 
     $sql .= "TIMESTAMP BETWEEN ? AND ? ORDER BY TIMESTAMP ;"; 
     
     # SQL zusammenstellen für Logausgabe
     my $sql1 = "SELECT VALUE,TIMESTAMP FROM `history` where ";
     $sql1 .= "`DEVICE` = '$device' AND " if($device);
     $sql1 .= "`READING` = '$reading' AND " if($reading); 
     $sql1 .= "TIMESTAMP BETWEEN '$runtime_string_first' AND '$runtime_string_next' ORDER BY TIMESTAMP;"; 
     
     Log3 ($name, 4, "DbRep $name - SQL to execute: $sql1"); 
     
     $runtime_string = encode_base64($runtime_string,"");
     my $sth = $dbh->prepare($sql);   
     
     eval {$sth->execute($runtime_string_first, $runtime_string_next);};
     
     if ($@) {
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
         return "$name|''|$device|$reading|''|1";
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
  
 my $rowlist = join('|', @row_array); 
 Log3 ($name, 5, "DbRep $name -> row_array: @row_array");
     
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
  
 Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_DoParse finished");
 
 return "$name|$rowlist|$device|$reading|$rt|0";
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
  my $reading    = $a[3];
  my $rt         = $a[4];
  my $dberr      = $a[5];
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall diffval_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_ParseDone finished");
      return;
  }
  
  my @row_array = split("\\|", $rowlist);
  
  Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");
  
 
  my %rh = ();
  my $lastruntimestring;
  my $i = 1;
  my $fe;                         # Startelement Value
  my $le;                         # letztes Element Value
  my $max = ($#row_array)+1;      # Anzahl aller Listenelemente

  foreach my $row (@row_array) {
      my @a = split("[ \t][ \t]*", $row);
      my $runtime_string = decode_base64($a[0]);
      $lastruntimestring = $runtime_string if ($i == 1);
      
      my $value          = $a[1];      
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          readingsSingleUpdate($hash, "state", "error", 1);
          delete($hash->{helper}{RUNNING_PID});
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in diffValue function. Faulty dataset was \nTIMESTAMP: $a[2] $a[3], DEVICE: $device, READING: $reading, VALUE: $value. \nLeaving ...");
          Log3 ($name, 4, "DbRep $name -> BlockingCall diffval_ParseDone finished");
          return;
      }
      
      $a[3]              =~ s/:/-/g if($a[3]);          # substituieren unsopported characters -> siehe fhem.pl
      my $timestamp      = $a[3]?$a[2]."_".$a[3]:$a[2];
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
             
      if ($runtime_string eq $lastruntimestring) {
          if ($i == 1) {
              $fe = $value;
              $le = $value;
          }
          
          if ($value >= $le) {
              $le    = $value;
              my $diff  = $le - $fe;
              
              $rh{$runtime_string} = $runtime_string."|".$diff."|".$timestamp;            
          }
      } else {
          # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen 
          $lastruntimestring = $runtime_string;
          $i  = 1;
          $fe = $value;
          $le = $value;
          
          if ($value >= $le) {
              $le    = $value;
              my $diff  = $le - $fe;
              
              $rh{$runtime_string} = $runtime_string."|".$diff."|".$timestamp;
          }
      }
      $i++;
  }
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
 
  foreach my $key (sort(keys(%rh))) {
      Log3 ($name, 4, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key});
      my @k    = split("\\|",$rh{$key});
      my $rsf  = $k[2]."__";
  
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."DIFF__".$k[0];
      }
      my $rv = $k[1];
      readingsBulkUpdate($hash, $reading_runtime_string, $rv?sprintf("%.4f",$rv):"-");          
    
  }
             
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{helper}{RUNNING_PID});
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

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall sumval_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_DoParse finished");
     return "$name|''|$device|$reading|''|1";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 
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
     my $sql = "SELECT SUM(VALUE) FROM `history` ";
     $sql .= "where " if($reading || $device || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME}, "timeOlderThan",undef));
     $sql .= "DEVICE = '$device' " if($device);
     $sql .= "AND " if($device && $reading);
     $sql .= "READING = '$reading' " if($reading);
     $sql .= "AND " if((AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME}, "timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef)) && ($device || $reading));
     $sql .= "TIMESTAMP BETWEEN '$runtime_string_first' AND '$runtime_string_next' " if(AttrVal($hash->{NAME}, "aggregation", "no") ne "no" || AttrVal($hash->{NAME},"timestamp_begin",undef) || AttrVal($hash->{NAME},"timestamp_end",undef) || AttrVal($hash->{NAME},"timeDiffToNow",undef) || AttrVal($hash->{NAME},"timeOlderThan",undef));
     $sql .= ";";
     
     Log3 ($name, 4, "DbRep $name - SQL to execute: $sql");        
     
     my $line;
     # DB-Abfrage -> Ergebnis in $arrstr aufnehmen
     eval {$line = $dbh->selectrow_array($sql);};
     
     if ($@) {
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         Log3 ($name, 4, "DbRep $name -> BlockingCall sumval_DoParse finished");
         return "$name|''|$device|$reading|''|1";
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
  my $reading    = $a[3];
  my $rt         = $a[4];
  my $dberr      = $a[5];
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall sumval_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
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
  
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{helper}{RUNNING_PID});  
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
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall del_DoParse");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
     return "$name|''|''|1";
 }
 
 # SQL zusammenstellen für DB-Operation
 my $sql = "DELETE FROM history where ";
 $sql .= "DEVICE = '$device' AND " if($device);
 $sql .= "READING = '$reading' AND " if($reading); 
 $sql .= "TIMESTAMP BETWEEN ? AND ?;";
 
 # SQL zusammenstellen für Logausgabe
 my $sql1 = "DELETE FROM history where ";
 $sql1 .= "DEVICE = '$device' AND " if($device);
 $sql1 .= "READING = '$reading' AND " if($reading); 
 $sql1 .= "TIMESTAMP BETWEEN $runtime_string_first AND $runtime_string_next;"; 
    
 Log3 ($name, 4, "DbRep $name - SQL to execute: $sql1");        
 
 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sth = $dbh->prepare($sql); 
 
 eval {$sth->execute($runtime_string_first, $runtime_string_next);};
 
 my $rows;
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
     return "$name|''|''|1";
 } else {
     $rows = $sth->rows;
     $dbh->commit() if(!$dbh->{AutoCommit});
     $dbh->disconnect;
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 5, "DbRep $name -> Number of deleted rows: $rows");
 Log3 ($name, 4, "DbRep $name -> BlockingCall del_DoParse finished");
 
 return "$name|$rows|$rt|0";
}

####################################################################################################
# Auswertungsroutine DB delete
####################################################################################################

sub del_ParseDone($) {
  my ($string) = @_;
  my @a     = split("\\|",$string);
  my $hash  = $defs{$a[0]};
  my $name  = $hash->{NAME};
  my $rows  = $a[1];
  my $rt    = $a[2];
  my $dberr = $a[3];
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall del_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
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
  
  Log3 ($name, 3, "DbRep $name - Entries of database $hash->{dbloghash}{NAME} deleted: $rows");  
    
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);

  delete($hash->{helper}{RUNNING_PID});
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
 
 Log3 ($name, 4, "DbRep $name -> Start BlockingCall insert_Push");
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
     return "$name|''|''|1";
 }
 
 my $i_timestamp = $hash->{helper}{I_TIMESTAMP};
 my $i_device    = $hash->{helper}{I_DEVICE};
 my $i_type      = $hash->{helper}{I_TYPE};
 my $i_event     = $hash->{helper}{I_EVENT};
 my $i_reading   = $hash->{helper}{I_READING};
 my $i_value     = $hash->{helper}{I_VALUE};
 my $i_unit      = $hash->{helper}{I_UNIT} ? $hash->{helper}{I_UNIT} : " "; 
 
 # SQL zusammenstellen für DB-Operation
    
 Log3 ($name, 5, "DbRep $name -> data to insert Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");     
 
 # SQL-Startzeit
 my $st = [gettimeofday];

 $dbh->begin_work();
 my $sth = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
 
 eval {$sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);};
 
 my $irow;
 if ($@) {
     Log3 ($name, 2, "DbRep $name - Failed to insert new dataset into database: $@");
     $dbh->rollback();
     $dbh->disconnect();
     Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
     return "$name|''|''|1";
 } else {
     $dbh->commit();
     $irow = $sth->rows;
     $dbh->disconnect();
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Push finished");
 
 return "$name|$irow|$rt|0";
}

####################################################################################################
# Auswertungsroutine DB insert
####################################################################################################

sub insert_Done($) {
  my ($string) = @_;
  my @a     = split("\\|",$string);
  my $hash  = $defs{$a[0]};
  my $name  = $hash->{NAME};
  my $irow  = $a[1];
  my $rt    = $a[2];
  my $dberr = $a[3];
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall insert_Done");
  
  my $i_timestamp = delete $hash->{helper}{I_TIMESTAMP};
  my $i_device    = delete $hash->{helper}{I_DEVICE};
  my $i_type      = delete $hash->{helper}{I_TYPE};
  my $i_event     = delete $hash->{helper}{I_EVENT};
  my $i_reading   = delete $hash->{helper}{I_READING};
  my $i_value     = delete $hash->{helper}{I_VALUE};
  my $i_unit      = delete $hash->{helper}{I_UNIT}; 
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Done finished");
      return;
  } 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "number_lines_inserted", $irow);    
  readingsBulkUpdate($hash, "data_inserted", $i_timestamp.", ".$i_device.", ".$i_type.", ".$i_event.", ".$i_reading.", ".$i_value.", ".$i_unit);   
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done"); 
  readingsEndUpdate($hash, 1);
  
  Log3 ($name, 5, "DbRep $name - Inserted into database $hash->{dbloghash}{NAME} table 'history': Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");  

  delete($hash->{helper}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall insert_Done finished");
  
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

 Log3 ($name, 4, "DbRep $name -> Start BlockingCall fetchrows_DoParse");

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
     return "$name|''|''|1";
 }
 
 # SQL zusammenstellen
 my $sql = "SELECT DEVICE,READING,TIMESTAMP,VALUE FROM history where ";
 $sql .= "DEVICE = '$device' AND " if($device);
 $sql .= "READING = '$reading' AND " if($reading); 
 $sql .= "TIMESTAMP BETWEEN ? AND ? ORDER BY TIMESTAMP;";   
         
 # SQL zusammenstellen für Logfileausgabe
 my $sql1 = "SELECT DEVICE,READING,TIMESTAMP,VALUE FROM history where ";
 $sql1 .= "DEVICE = '$device' AND " if($device);
 $sql1 .= "READING = '$reading' AND " if($reading); 
 $sql1 .= "TIMESTAMP BETWEEN $runtime_string_first AND $runtime_string_next ORDER BY TIMESTAMP;"; 
     
 Log3 ($name, 4, "DbRep $name - SQL to execute: $sql1");    

 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sth = $dbh->prepare($sql);
 
 eval {$sth->execute($runtime_string_first, $runtime_string_next);};
 
 my $rowlist;
 if ($@) {
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
     return "$name|''|''|1";
 } else {
     my @row_array = map { $_ -> [0]." ".$_ -> [1]." ".$_ -> [2]." ".$_ -> [3]."\n" } @{ $sth->fetchall_arrayref() };     
     $rowlist = join('|', @row_array); 
     Log3 ($name, 5, "DbRep $name -> row_array:  @row_array");
 } 
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
 
 Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_DoParse finished");
 
 return "$name|$rowlist|$rt|0";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage fetchrows
####################################################################################################

sub fetchrows_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash     = $defs{$a[0]};
  my $rowlist  = decode_base64($a[1]);
  my $rt       = $a[2];
  my $dberr    = $a[3];
  my $name     = $hash->{NAME};
  my $reading  = AttrVal($name, "reading", undef);
  my @i;
  my @row;
  my $reading_runtime_string;
  
  Log3 ($name, 4, "DbRep $name -> Start BlockingCall fetchrows_ParseDone");
  
  if ($dberr) {
      readingsSingleUpdate($hash, "state", "error", 1);
      delete($hash->{helper}{RUNNING_PID});
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
             
  readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(AttrVal($name, "showproctime", undef));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  delete($hash->{helper}{RUNNING_PID});
  Log3 ($name, 4, "DbRep $name -> BlockingCall fetchrows_ParseDone finished");
  
return;
}

####################################################################################################
# Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub ParseAborted($) {
my ($hash) = @_;
my $name = $hash->{NAME};

  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{helper}{RUNNING_PID}{fn} timed out");
  readingsSingleUpdate($hash, "state", "timeout", 1);
  delete($hash->{helper}{RUNNING_PID});
}



################################################################################################################
#  Zusammenstellung Aggregationszeiträume
################################################################################################################

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
             $runtime_string       = "all between timestamps";                                         # für Readingname
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
             my $dim  = $rm-2?30+($rm*3%7<4):28+!($ry%4||$ry%400*!($ry%100));  # Anzahl Tage des aktuell laufenden Monats f. SQL-Select
             Log3 ($name, 5, "DbRep $name - act year:  $ry, act month: $rm, days in month: $dim, endyear: $yestr, endmonth: $mestr"); 
             
             
             $runtime_string       = strftime "%Y-%m", localtime($runtime);                            # für Readingname
             
             if ($i==1) {
                 # nur im ersten Durchlauf
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
             }
             
             if ($ysstr == $yestr && $msstr == $mestr || $ry ==  $yestr && $rm == $mestr) {
                 $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
                
             } else {
                 if(($runtime) > $epoch_seconds_end) {
                     $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);                     
                     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                     $ll=1;
                 } else {
                     $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);
                     $runtime_string_next  = strftime "%Y-%m-01", localtime($runtime+($dim*86400));
                     
                 } 
             }
         # my $help_string  = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
         my ($yyyy1, $mm1, $dd1) = ($runtime_string_next =~ /(\d+)-(\d+)-(\d+)/);
         $runtime = timelocal("00", "00", "00", "01", $mm1-1, $yyyy1-1900);
         
         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime_orig+$aggsec;
         }
         
         # Wochenaggregation
         if ($aggregation eq "week") {
             
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
                 $runtime = $runtime+$wdadd;
                 $runtime_orig = $runtime-$aggsec;                             
                 
                 # die Woche Beginn ist gleich der Woche von Ende Auswertung
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
             $runtime_string       = strftime "%Y-%m-%d", localtime($runtime);                         # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
             $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime) if($i>1);
                                 
             if((($tsstr gt $testr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
                 $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime);                    
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
             } else {
                 $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime+$aggsec);   
             }
         
         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime+$aggsec;         
         }
     
         # Stundenaggregation
         if ($aggregation eq "hour") {
             $runtime_string       = strftime "%Y-%m-%d_%H", localtime($runtime);                      # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
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

1;

=pod
=item helper
=item summary    browsing / managing content of DbLog-databases. Content is depicted as readings
=item summary_DE durchsuchen / bearbeiten von DbLog-DB Content. Darstellung als Readings
=begin html

<a name="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  The purpose of this module is browsing of DbLog-databases. The searchresults can be evaluated concerning to various aggregations and the appropriate 
  Readings will be filled. The data selection will been done by declaration of device, reading and the time settings of selection-begin and selection-end.  <br><br>
  
  All database operations are implemented nonblocking. Optional the execution time of SQL-statements in background can also be determined and provided as reading.
  (refer to <a href="#DbRepattr">attributes</a>). <br><br>
  
  Currently the following functions are provided: <br><br>
  
     <ul><ul>
     <li> Selection of all datasets within adjustable time limits. </li>
     <li> Exposure of datasets of a Device/Reading-combination within adjustable time limits. </li>
     <li> Selecions of datasets by usage of dynamically calclated time limits at execution time. </li>
     <li> Calculation of quantity of datasets of a Device/Reading-combination within adjustable time limits and several aggregations. </li>
     <li> The calculation of summary- , difference- , maximal- and averageValues of numeric readings within adjustable time limits and several aggregations. </li>
     <li> The deletion of datasets. The containment of deletion can be done by Device and/or Reading as well as fix or dynamically calculated time limits at execution time. </li>
     </ul></ul>
     <br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">neues Modul 93_DbRep - Auswertungen und Reporting von Datenbankinhalten (DbLog)</a>.<br><br>
 
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
    <li><b> averageValue </b> -  calculates the average value of readingvalues DB-column "VALUE") between period given by timestamp-<a href="#DbRepattr">attributes</a> which are set. The reading to evaluate must be defined using attribute "reading".  </li> <br>
    <li><b> countEntries </b> -  provides the number of DB-entries between period given by timestamp-<a href="#DbRepattr">attributes</a> which are set. If timestamp-attributes are not set, all entries in db will be count. The <a href="#DbRepattr">attributes</a> "device" and "reading" can be used to limit the evaluation.  </li> <br>
    <li><b> fetchrows </b>    -  provides <b>all</b> DB-entries between period given by timestamp-<a href="#DbRepattr">attributes</a>. An aggregation which would possibly be set attribute will <b>not</b> considered.  </li> <br>
    <li><b> insert </b>       -  use it to insert data ito table "history" manually. Input values for Date, Time and Value are mandatory. The database fields for Type and Event will be filled in with "manual" automatically and the values of Device, Reading will be get from set <a href="#DbRepattr">attributes</a>.  <br><br>
                                 
                                 <ul>
                                 <b>input format: </b>   Date,Time,Value,[Unit]    <br>
                                 # Unit is optional, attributes of device, reading must be set ! <br><br>
                                 
                                 <b>example:</b>         2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # field lenth is maximum 32 characters, NO spaces are allowed in fieldvalues ! <br>
                                 </li> <br>
                                 </ul>
                                 

    <li><b> sumValue </b>     -  calculates the amount of readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow". The reading to evaluate must be defined using attribute "reading". Using this function is mostly reasonable if value-differences of readings are written to the database. </li> <br>  
    <li><b> maxValue </b>     -  calculates the maximum value of readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow". The reading to evaluate must be defined using attribute "reading". The evaluation contains the timestamp of the identified max values within the given period.  </li> <br>
    <li><b> diffValue </b>    -  calculates the defference of the readingvalues DB-column "VALUE") between period given by <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow". The reading to evaluate must be defined using attribute "reading". This function is mostly reasonable if readingvalues are increasing permanently and don't write value-differences to the database. </li> <br>
    <li><b> delEntries </b>   -  deletes all database entries or only the database entries specified by <a href="#DbRepattr">attributes</a> Device and/or Reading and the entered time period between "timestamp_begin", "timestamp_end" (if set) or "timeDiffToNow". <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" is set:  deletes db entries <b>from</b> this timestamp until current date/time <br>
                                 "timestamp_end" is set  :  deletes db entries <b>until</b> this timestamp <br>
                                 both Timestamps are set :  deletes db entries <b>between</b> these timestamps <br>
                                 </li>
                                 </ul>
                                 
  <br>
  </ul></ul>
  
  Due to security reasons the attribute "allowDeletion" needs to be set to unlock the delete-function. <br><br>
  
  <b>For all evaluation variants applies: </b> <br>
  In addition to the needed reading the device can be complemented to restrict the datasets for reporting / function. 
  If the attributes "timestamp_begin" and "timestamp_end" are not set, the period from '1970-01-01 01:00:00' to the current date/time will be used as selection criterion.. 
  <br><br>
  
  <b>Note </b> <br>
  
  All database action will excuted in background ! It could be necessary to refresh the browser to see the answer of operation if you are in detail view once the "state = done" is shown. 
  <br><br>

</ul>  


<a name="DbRepattr"></a>
<b>Attribute</b>

<br>
<ul>
  Using the module specific attributes you are able to define the scope of evaluation and the aggregation. <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Aggregation of Device/Reading-selections. Possible is hour, day, week, month or "no". Delivers e.g. the count of database entries for a day (countEntries), Summation of difference values of a reading (sumValue) and so on. Using aggregation "no" (default) an aggregation don't happens but the output contaims all values of Device/Reading in the defined time period.  </li> <br>
  <li><b>allowDeletion </b>   - unlocks the delete-function  </li> <br>
  <li><b>device </b>          - selection of a particular device   </li> <br>
  <li><b>disable </b>         - deactivates the module  </li> <br>
  <li><b>reading </b>         - selection of a particular reading   </li> <br>
  <li><b>readingNameMap </b>  - the name of the analyzed reading can be overwritten for output  </li> <br>
  <li><b>showproctime </b>    - if set, the reading "sql_processing_time" shows the required execution time (in seconds) for the sql-requests. This is not calculated for a single sql-statement, but the summary of all sql-statements necessara for within an executed DbRep-function in background.   </li> <br>
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


=end html
=begin html_DE

<a name="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  Zweck des Moduls ist es, den Inhalt von DbLog-Datenbanken nach bestimmten Kriterien zu durchsuchen und das Ergebnis hinsichtlich verschiedener 
  Aggregationen auszuwerten und als Readings darzustellen. Die Abgrenzung der zu berücksichtigenden Datenbankinhalte erfolgt durch die Angabe von Device, Reading und
  die Zeitgrenzen für Auswertungsbeginn bzw. Auswertungsende.  <br><br>
  
  Alle Datenbankoperationen werden nichtblockierend ausgeführt. Die Ausführungszeit der SQL-Hintergrundoperationen kann optional ebenfalls als Reading bereitgestellt
  werden (siehe <a href="#DbRepattr">Attribute</a>). <br><br>
  
  Zur Zeit werden folgende Operationen unterstützt: <br><br>
  
     <ul><ul>
     <li> Selektion aller Datensätze innerhalb einstellbarer Zeitgrenzen. </li>
     <li> Darstellung der Datensätze einer Device/Reading-Kombination innerhalb einstellbarer Zeitgrenzen. </li>
     <li> Die Selektion der Datensätze unter Verwendung von dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt. </li>
     <li> Berechnung der Anzahl von Datensätzen einer Device/Reading-Kombination unter Berücksichtigung von Zeitgrenzen und verschiedenen Aggregationen. </li>
     <li> Die Berechnung von Summen- , Differenz- , Maximal- und Durchschnittswerten von numerischen Readings in Zeitgrenzen und verschiedenen Aggregationen. </li>
     <li> Die Löschung von Datensätzen. Die Eingrenzung der Löschung kann durch Device und/oder Reading sowie fixer oder dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt erfolgen. </li>
     </ul></ul>
     <br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">neues Modul 93_DbRep - Auswertungen und Reporting von Datenbankinhalten (DbLog)</a>.<br><br>
 
  <b>Voraussetzungen </b> <br><br>
  
  Das Modul setzt den Einsatz einer DBLog-Instanz voraus. Es werden die Zugangsdaten dieser Datenbankdefinition genutzt (bisher getestet mit MySQL und SQLite). <br>
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
  (&lt;Name der DbLog-instanz&gt; - es wird der Name der auszuwertenden DBLog-Datenbankdefinition angegeben)

</ul>

<br><br>

<a name="DbRepset"></a>
<b>Set </b>
<ul>

 Zur Zeit gibt es folgende Set-Kommandos. Über sie werden die Auswertungen angestoßen und definieren selbst die Auswertungsvariante. 
 Nach welchen Kriterien die Datenbankinhalte durchsucht werden und die Aggregation erfolgt, wird durch <a href="#DbRepattr">Attribute</a> gesteuert. 
 <br><br>
 
 <ul><ul>
    <li><b> averageValue </b> -  berechnet den Durchschnittswert der Readingwerte (DB-Spalte "VALUE") in den gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein.  </li> <br>
    <li><b> countEntries </b> -  liefert die Anzahl der DB-Einträge in den gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). Sind die Timestamps nicht gesetzt werden alle Einträge gezählt. Beschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading gehen in die Selektion mit ein.  </li> <br>
    <li><b> fetchrows </b>    -  liefert <b>alle</b> DB-Einträge in den gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). Eine evtl. gesetzte Aggregation wird <b>nicht</b> berücksichtigt.  </li> <br>
    <li><b> insert </b>       -  Manuelles Einfügen eines Datensatzes in die Tabelle "history". Obligatorisch sind Eingabewerte für Datum, Zeit und Value. Die Werte für die DB-Felder Type bzw. Event werden mit "manual" gefüllt, sowie die Werte für Device, Reading aus den gesetzten  <a href="#DbRepattr">Attributen </a> genommen.  <br><br>
                                 
                                 <ul>
                                 <b>Eingabeformat: </b>   Datum,Zeit,Value,[Unit]  <br>               
                                 # Unit ist optional, Attribute "reading" und "device" müssen gesetzt sein  <br><br>
                                 
                                 <b>Beispiel: </b>        2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # die Feldlänge ist maximal 32 Zeichen lang, es sind KEINE Leerzeichen im Feldwert erlaubt !<br><br>
                                 </li> <br>
                                 </ul>
                                 
    <li><b> sumValue </b>     -  berechnet die Summenwerte eines Readingwertes (DB-Spalte "VALUE") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow". Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein. Diese Funktion ist sinnvoll wenn fortlaufend Wertedifferenzen eines Readings in die Datenbank geschrieben werden.  </li> <br>
    <li><b> maxValue </b>     -  berechnet den Maximalwert eines Readingwertes (DB-Spalte "VALUE") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow". Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" angegeben sein. Die Auswertung enthält den Zeitstempel des ermittelten Maximalwertes innerhalb der Aggregation bzw. Zeitgrenzen.  </li> <br>
    <li><b> diffValue </b>    -  berechnet den Differenzwert eines Readingwertes (DB-Spalte "Value") in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw "timeDiffToNow". Es muss das auszuwertende Reading über das Attribut "reading" angegeben sein. Diese Funktion ist z.B. zur Auswertung von Eventloggings sinnvoll, deren Werte sich fortlaufend erhöhen und keine Wertdifferenzen wegschreiben. </li> <br>
    <li><b> delEntries </b>   -  löscht alle oder die durch die <a href="#DbRepattr">Attribute</a> device und/oder reading definierten Datenbankeinträge. Die Eingrenzung über Timestamps erfolgt folgendermaßen: <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" gesetzt:  gelöscht werden DB-Einträge <b>ab</b> diesem Zeitpunkt bis zum aktuellen Datum/Zeit <br>
                                 "timestamp_end" gesetzt  :  gelöscht werden DB-Einträge <b>bis</b> bis zu diesem Zeitpunkt <br>
                                 beide Timestamps gesetzt :  gelöscht werden DB-Einträge <b>zwischen</b> diesen Zeitpunkten <br>
                                 </li>
                                 </ul>
                                 
  <br>
  </ul></ul>
  
  Aus Sicherheitsgründen muss das <a href="#DbRepattr">Attribut</a> "allowDeletion" gesetzt sein um die Löschfunktion freizuschalten. <br><br>
  
  <b>Für alle Auswertungsvarianten gilt: </b> <br>
  Zusätzlich zu dem auszuwertenden Reading kann das Device mit angegeben werden um das Reporting nach diesen Kriterien einzuschränken. 
  Sind die <a href="#DbRepattr">Attribute</a> "timestamp_begin", "timestamp_end" nicht angegeben, wird '1970-01-01 01:00:00' und das aktuelle Datum/Zeit als Zeitgrenze genutzt. 
  <br><br>
  
  <b>Hinweis </b> <br>
  
  Da alle DB-Operationen im Hintergrund ausgeführt werden, kann in der Detailansicht ein Browserrefresh nötig sein um die Operationsergebnisse zu sehen sobald "state = done" angezeigt wird. 
  <br><br>

</ul>  


<a name="DbRepattr"></a>
<b>Attribute</b>

<br>
<ul>
  Über die modulspezifischen Attribute wird die Abgrenzung der Auswertung und die Aggregation der Werte gesteuert. <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Zusammenfassung der Device/Reading-Selektionen in Stunden,Tages,Kalenderwochen,Kalendermonaten oder "no". Liefert z.B. die Anzahl der DB-Einträge am Tag (countEntries), Summation von Differenzwerten eines Readings (sumValue), usw. Mit Aggregation "no" (default) erfolgt keine Zusammenfassung in einem Zeitraum sondern die Ausgabe ergibt alle Werte eines Device/Readings zwischen den definierten Zeiträumen.  </li> <br>
  <li><b>allowDeletion </b>   - schaltet die Löschfunktion des Moduls frei   </li> <br>
  <li><b>device </b>          - Abgrenzung der DB-Selektionen auf ein bestimmtes Device   </li> <br>
  <li><b>disable </b>         - deaktiviert das Modul   </li> <br>
  <li><b>reading </b>         - Abgrenzung der DB-Selektionen auf ein bestimmtes Reading   </li> <br>
  <li><b>readingNameMap </b>  - der Name des ausgewerteten Readings wird mit diesem String für die Anzeige überschrieben   </li> <br>
  <li><b>showproctime </b>    - wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die SQL-Ausführung der durchgeführten Funktion. Dabei wird nicht ein einzelnes SQl-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der jeweiligen Funktion betrachtet.   </li> <br>
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

=end html_DE
=cut