###############################################################
# $Id$
#
#  98_CDCOpenData.pm
#
#  (c) 2021-2023 modul implementation by jowiemann https://forum.fhem.de/index.php?action=profile
# 
#  (c) 2023 basic works for getting and decoding data from DWD by F. Ahlers https://forum.fhem.de/index.php?action=profile;u=3346
#  (c) herrmannj (https://forum.fhem.de/index.php?action=profile;u=769) Original work for cron functions taken from 98_JsonMod.pm
#  (c) Jamo (https://forum.fhem.de/index.php?msg=1292677) basierend auf den html bars der älteren Module '59_RainTMC.pm' und '59_Buienradar.pm',
#                                                         und adaptiert für CDCOpenData rain_radar
# 
#  The module extracts data for daily rainfall from binary files supplied 
#  by DWD's (German weather service) open data server. The data are based on rain radar data which 
#  are interpolated on a grid of 1x1 km² resolution and calibrated with measured data from nearby
#  weatherstations.
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> CDCOpenData <[latitude] [longitude]>
#
##############################################################################
# defmod DWD_Regen CDCOpenData
# attr DWD_Regen INTERVAL 3600
# attr DWD_Regen disable 0
# attr DWD_Regen locations Bad_Soden:50.1461,8.4986
#
##############################################################################
# eval "use Net::SSLGlue::FTP;1"                   or $missingModul .= "Net::SSLGlue::FTP install: sudo apt-get install libnet-sslglue-perl ";

package main;

use strict;
use warnings;
use Blocking;
use HttpUtils;

my $ModulVersion = "01.12f";
my $missingModul = "";

sub CDCOpenData_Log($$$);
sub CDCOpenData_DebugLog($$$$;$);
sub CDCOpenData_dbgLogInit($@);
sub CDCOpenData_Initialize($);
sub CDCOpenData_Readout_Add_Reading ($$$$@);
sub CDCOpenData_Readout_Process($$);

use Net::FTP;
eval "use IO::Uncompress::Gunzip qw(gunzip);1"   or $missingModul .= "IO::Uncompress::Gunzip install: sudo apt-get install libio-compress-perl ";
eval "use IO::Uncompress::Bunzip2 qw(bunzip2);1" or $missingModul .= "IO::Uncompress::Bunzip2 install: sudo apt-get install libio-compress-perl ";
eval "use Archive::Tar;1"                        or $missingModul .= "Archive::Tar install: sudo apt-get install libarchive-extract-perl ";
eval "use POSIX;1"                               or $missingModul .= "POSIX install: sudo apt-get install libtemplate-plugin-posix-perl ";
eval "use File::Path;1"                          or $missingModul .= "File::Path not available ";
eval "use FHEM::Scheduler::Cron;1"               or $missingModul .= "FHEM::Scheduler::Cron: update Fhem ";
eval "use List::Util qw(pairs);1"                or $missingModul .= "List::Util: update Perl ";

# FIFO Buffer for commands
my @cmdBuffer=();
my $cmdBufferTimeout=0;

my %LOG_Text = (
   0 => "SERVER:",
   1 => "ERROR:",
   2 => "SIGNIFICANT:",
   3 => "BASIC:",
   4 => "EXPANDED:",
   5 => "DEBUG:"
); 

#######################################################################
sub CDCOpenData_Log($$$)
{

   my ( $hash, $loglevel, $text ) = @_;

   my $instHash = ( ref($hash) eq "HASH" ) ? $hash : $defs{$hash};
   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   
   if ($instHash->{helper}{FhemLog3Std}) {
      Log3 $hash, $loglevel, $instName . ": " . $text;
      return undef;
   }

   my $xline       = ( caller(0) )[2];

   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/CDCOpenData_// if ( defined $sub );;
   $sub ||= 'no-subroutine-specified';

   $text = $LOG_Text{$loglevel} . $text;
   $text = "[$instName | $sub.$xline] - " . $text;

   if ( $instHash->{helper}{logDebug} ) {
     CDCOpenData_DebugLog $instHash, $instHash->{helper}{debugLog} . "-%Y-%m.dlog", $loglevel, $text;
   } else {
     Log3 $hash, $loglevel, $text;
   }

} # End CDCOpenData_Log

#######################################################################
sub CDCOpenData_DebugLog($$$$;$) {

  my ($hash, $filename, $loglevel, $text, $timestamp) = @_;
  my $name = $hash->{'NAME'};
  my $tim;

  $loglevel  .= ":" if ($loglevel);
  $loglevel ||= "";

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards("%L/" . $filename, @t);
  my $fh;

  unless ($timestamp) {

    $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);

    if ($attr{global}{mseclog}) {
      $tim .= sprintf(".%03d", $microseconds / 1000);
    }

    $tim .= " ";
    open($fh, '>>', $nfile);

  } elsif ( $timestamp eq "no") {

    $tim = "";
    open($fh, '>', $nfile);

  } else {

    $tim = $timestamp . " ";
    open($fh, '>>', $nfile);
  }

  print $fh "$tim$loglevel$text\n";
  close $fh;

  return undef;

} # end CDCOpenData__DebugLog

#######################################################################
sub CDCOpenData_dbgLogInit($@) {

   my ($hash, $cmd, $aName, $aVal) = @_;
   my $name = $hash->{NAME};

   if ($cmd eq "init" ) {
     $hash->{DEBUGLOG}             = "OFF";
     $hash->{helper}{debugLog}     = $name . "_debugLog";
     $hash->{helper}{logDebug}     = AttrVal($name, "verbose", 0) == 5;
     if ($hash->{helper}{logDebug}) {
       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG} = '<html>'
                         . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                         . $hash->{helper}{debugLog}
                         . '&amp;type=text&amp;file='
                         . $nfile
                         . '">DEBUG Log kann hier eingesehen werden</a>'
                         . '</html>';
     }
   }

   return if $aVal && $aVal == -1; 

   my $dirdef     = Logdir() . "/";
   my $dbgLogFile = $dirdef . $hash->{helper}{debugLog} . '-%Y-%m.dlog';

   if ($cmd eq "set" ) {
     
     if($aVal == 5) {
     
       unless (defined $defs{$hash->{helper}{debugLog}}) {
         my $dMod  = 'defmod ' . $hash->{helper}{debugLog} . ' FileLog ' . $dbgLogFile . ' FakeLog readonly';

         fhem($dMod, 1);

         if (my $dRoom = AttrVal($name, "room", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' room ' . $dRoom;
           fhem($dMod, 1);
         }

         if (my $dGroup = AttrVal($name, "group", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' group ' . $dGroup;
           fhem($dMod, 1);
         }
       }

       CDCOpenData_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       $hash->{helper}{logDebug} = 1;

       CDCOpenData_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG}      = '<html>'
                              . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                              . $hash->{helper}{debugLog}
                              . '&amp;type=text&amp;file='
                              . $nfile
                              . '">DEBUG Log kann hier eingesehen werden</a>'
                              . '</html>';

     } elsif($aVal < 5 && $hash->{helper}{logDebug}) {
       fhem("delete " . $hash->{helper}{debugLog}, 1);

       CDCOpenData_Log $name, 3, "redirection debugLog: $hash->{helper}{debugLog} deleted";

       $hash->{helper}{logDebug} = 0;
       $hash->{DEBUGLOG}         = "OFF";

       CDCOpenData_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

#       unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
#         return "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
#       }
     }
   }

   if ($cmd eq "del" ) {
     fhem("delete " . $hash->{helper}{debugLog}, 1) if $hash->{helper}{logDebug};

     CDCOpenData_Log $name, 3, "redirection debugLog: $hash->{helper}{debugLog} deleted";

     $hash->{helper}{logDebug} = 0;
     $hash->{DEBUGLOG}         = "OFF";

     CDCOpenData_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

     unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
       CDCOpenData_Log $name, 3, "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
     }

   }

} # end CDCOpenData_dbgLogInit

#######################################################################
sub CDCOpenData_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash
 
  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
  my $devName = $dev_hash->{NAME}; # Device that created the events
  my $events = deviceEvents($dev_hash, 1);

  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
  {
     # initialize DEGUB LOg function
     CDCOpenData_dbgLogInit($own_hash, "init", "verbose", AttrVal($ownName, "verbose", -1));
     # end initialize DEGUB LOg function
  }
}

#######################################################################
sub CDCOpenData_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "CDCOpenData_Define";
  $hash->{UndefFn}  = "CDCOpenData_Undefine";
  $hash->{DeleteFn} = "CDCOpenData_Delete";
  $hash->{RenameFn} = "CDCOpenData_Rename";
  $hash->{NotifyFn} = "CDCOpenData_Notify";

  $hash->{SetFn}    = "CDCOpenData_Set";
  $hash->{GetFn}    = "CDCOpenData_Get";
  $hash->{AttrFn}   = "CDCOpenData_Attr";
  $hash->{AttrList} = "INTERVAL "
                    ."cronTime "
                    ."nonblockingTimeOut:50,75,100,125 "
                    ."locations "
                    ."numberOfDays:1,2,3,4,5,6,7,8,9,10 "
                    ."tmpRadolanData "
                    ."disable:0,1 "
                    ."FhemLog3Std:0,1 "
                    ."updateOnStart:0,1 "
                    ."enableDWDdata:multiple-strict,rainByDay,rainSinceMidnight,rainRadarbyLocation "
                    ."clearRadarFileLog "
                    ."RainRadarFileLog "
                    ."ownRadarFileLog:0,1 "
                    .$readingFnAttributes;

} # end CDCOpenData_Initialize


#######################################################################
sub CDCOpenData_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   if ($init_done) {
   }

   return "CDCOpenData_Define: define <name> CDCOpenData <[name:]latitude,longitude>" . @args if(@args < 1 && @args > 2);

   my $name = $args[0];

   if (!defined $args[2]) {
      my $home = AttrVal("global", "latitude", 49.473067) . "," . AttrVal("global", "longitude", 6.800607);
      $hash->{LOCATION} = $home eq "49.473067,6.800607" ? "Germany:" : "Home:" . $home;
      CDCOpenData_Log $name, 4, "<[name:]latitude,longitude> was not provided and will be set to " . $hash->{LOCATION};
   } else {
      my $location = $args[2];
      $location =~ s/.*?://;

      return "Invalid location format <[name:]latitude,longitude>" if $location !~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/;

      $hash->{LOCATION} = $location;
   }
   
   # initialize DEGUB Log function
   CDCOpenData_dbgLogInit($hash, "init", "verbose", AttrVal($name, "verbose", -1));
   # end initialize DEGUB Log function

   # stop if certain perl moduls are missing
   my $msg;
   if ( $missingModul ) {
      $msg = "ERROR: Cannot define a CDCOpenData device. Perl modul $missingModul is missing.";
      CDCOpenData_Log $name, 1, $msg;
      $hash->{PERL} = $msg;
      return $msg;
   }

   $hash->{NAME}         = $name;
   $hash->{VERSION}      = $ModulVersion;

   $hash->{STATE}        = "Initializing";
   $hash->{INTERVAL}     = 300;
   $hash->{TIMEOUT}      = 55;
   $hash->{TMPDIR}       = "temp_radolan_data_" . $name;
   $hash->{DWDHOST}      = "opendata.dwd.de";

   $hash->{fhem}{UPDATE} = 0;

   $hash->{helper}{TimerReadout} = $name . ".Readout";
   $hash->{helper}{TimerCmd}     = $name . ".Cmd";
   $hash->{helper}{baseTMPDIR}   = "temp_radolan_data_" . $name;
   $hash->{helper}{FhemLog3Std}  = AttrVal($name, "FhemLog3Std", 0);
   $hash->{helper}{CronTime}     = AttrVal($name, "cronTime", 0) ? 1 : 0;
   $hash->{helper}{rainLog}      = $name . "_rainLog";

   eval {File::Path::make_path($hash->{helper}{baseTMPDIR}) };

   if($@) {
     return "Temporary directory: $hash->{helper}{baseTMPDIR} could not be created.";
   }

   # Vorbereitung für CRON Prozess
   $hash->{'CONFIG'}->{'IN_REQUEST'} = 0;

   my $cron = AttrVal($name, 'cronTime', '0 * * * *');
   $hash->{'CONFIG'}->{'CRON'} = \$cron;

   CDCOpenData_Log $name, 4, "start timer: CDCOpenData_Readout_Start -> hash";
   InternalTimer(gettimeofday() + 1, \&CDCOpenData_Cron_Run, $hash, 0);

   CDCOpenData_Log $name, 4, "start of Device readout parameters";

   return undef;
} #end CDCOpenData_Define

#######################################################################
sub CDCOpenData_Undefine($$)
{
  my ($hash, $args) = @_;

  if ($hash->{helper}{CronTime}) {
    CDCOpenData_Log $hash, 3, "removing InternalTimer: CDCOpenData_StopTimer";
    CDCOpenData_StopTimer($hash);
  } else {
    RemoveInternalTimer($hash->{helper}{TimerReadout});
  }

  RemoveInternalTimer($hash->{helper}{TimerCmd});

  BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} ) if exists $hash->{helper}{READOUT_RUNNING_PID};

  BlockingKill( $hash->{helper}{CMD_RUNNING_PID} ) if exists $hash->{helper}{CMD_RUNNING_PID};

  return undef;
} # end CDCOpenData_Undefine

#######################################################################
sub CDCOpenData_Delete ($$)
{
   my ( $hash, $name ) = @_;

   #my $index = $hash->{TYPE} . "_" . $name . "_passwd";
   #setKeyValue($index, undef);

   if (my $dLog = AttrVal($name, "RainRadarFileLog", undef)) {
     fhem('delete ' . $dLog, 1) if defined $defs{$dLog};
   }

   if (my $dLog = AttrVal($name, "ownRadarFileLog", undef)) {
     fhem('delete ' . $dLog, 1) if defined $defs{$dLog};
   }

   if ( -e $hash->{TMPDIR} and -d $hash->{TMPDIR}) {

     my @delDirs   = split(/\//, $hash->{TMPDIR});
     my $dirDeepth = @delDirs;
         
     for(my $cnt = $dirDeepth; $cnt > 0; $cnt--) {

       my $delPath = join("/", @delDirs);

       CDCOpenData_Log $hash, 3, "deleting $delPath";

       eval {File::Path::remove_tree( $delPath )};
       if($@) {
         CDCOpenData_Log $hash, 3, "Temporary directory: $hash->{TMPDIR} could not be removed.";
         return undef;
       }

       pop @delDirs;
     }

   } else {
     CDCOpenData_Log $hash, 3, "no tmpDir $hash->{TMPDIR} found.";
   }

   return undef;

}  # end CDCOpenData_Delete 

#######################################################################
sub CDCOpenData_Rename($$)
{
   my ($new, $old) = @_;

   #my $old_index = "CDCOpenData_".$old."_passwd";
   #my $new_index = "CDCOpenData_".$new."_passwd";

   #my ($err, $old_pwd) = getKeyValue($old_index);

   #setKeyValue($new_index, $old_pwd);
   #setKeyValue($old_index, undef);

   if (my $dLog = AttrVal($new, "RainRadarFileLog", undef)) {
     return undef unless defined $defs{$dLog};

     my $dMod  = 'defmod ' . $dLog . ' FileLog ./log/' . $new . '-%Y-%m.log ' . $new . ':Home_rain_radar/.*';
     fhem($dMod, 1);

     $dMod = 'attr ' . $dLog . ' -silent outputFormat { return $1 . " " . $NAME ." " . $EVENT . "\n" if $EVENT =~ /radar:(\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d)/;; return $TIMESTAMP . " " . $NAME ." " . $EVENT . "\n";; }';
     fhem($dMod, 1);
   }

   return undef;
}

#######################################################################
sub CDCOpenData_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value

   my $hash = $defs{$name};

   if ($aName eq "verbose") {
     CDCOpenData_dbgLogInit($hash, $cmd, $aName, $aVal) if !$hash->{helper}{FhemLog3Std};
   }
   
   if($aName eq "FhemLog3Std") {
     if ($cmd eq "set") {
       return "FhemLog3Std: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{helper}{FhemLog3Std} = $aVal;
       if ($aVal) {
         CDCOpenData_dbgLogInit($hash, "del", "verbose", 0) if AttrVal($name, "verbose", 0) == 5;
       } else {
         CDCOpenData_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5 && $aVal == 0;
       }
     } else {
       $hash->{helper}{FhemLog3Std} = 0;
       CDCOpenData_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5;
     }
   }

   if ($cmd eq "set") {

     if ($aName eq "INTERVAL") {
       return "the INTERVAL timer ($aVal sec) should be graeter than the non BlockingCall tiemout ($hash->{TIMEOUT} sec)" if $aVal < $hash->{TIMEOUT};
     }

     if ($aName eq "nonblockingTimeOut") {
       return "the non BlockingCall timeout ($aVal sec) should be less than the INTERVAL timer ($hash->{INTERVAL} sec)" if $aVal > $hash->{INTERVAL};
     }

     if ($aName eq "locations") {
       foreach my $location (split / /, $aVal) {
         $location =~ s/.*?://;
         CDCOpenData_Log $hash, 4, "la,lo -> $location";
         return "The location attribute is a space-separated list of locations in the format latitude,longitude." if $location !~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/;
       }
     }

     if($aName eq "clearRadarFileLog" && $init_done) {
       return "no FileLog device: $aVal defined." unless defined $defs{$aVal};
     }
   }

   if ($aName eq "numberOfDays") {
     if ($cmd eq "set") {
       return "number of days: $aVal for which data is fetched in the past. Default is 5 days." if $aVal !~ /[1-9]|1[0]/;
       fhem( "deletereading $name .*_day_rain:.*", 1 );
     } else {
       fhem( "deletereading $name .*_day_rain:.*", 1 );
     }
   }

   if ($aName eq 'cronTime') {
     if ($cmd eq "set") {
       if (split(/ /, $aVal) == 5) {
         my $err;
         ($hash->{'CRON'}, $err) = FHEM::Scheduler::Cron->new($aVal);
         unless ($err) {
           $hash->{'CONFIG'}->{'CRON'} = \$aVal;
           $hash->{helper}{CronTime} = 1;
           unless ( IsDisabled($name) ) {
             CDCOpenData_StartTimer($hash);
             CDCOpenData_Log $hash, 4, "Attr $cmd $aName -> Neustart internal Timer: hash";
           }
         } else {
           $hash->{'NEXT'} = sprintf('NEVER (%s)', $err);
           CDCOpenData_Log $hash, 2, 'cron returned error: ' . $err;
           $hash->{helper}{CronTime} = 0;
           return $err;
         }
       } else {
         $hash->{helper}{CronTime} = 0;
         return "wrong interval expression: " . split(/ /, $aVal);
       }
     }

     if ($cmd eq "del") {
       $hash->{'CONFIG'}->{'CRON'} = \'0 * * * *';
       $hash->{'NEXT'} = "no CRON";
       CDCOpenData_StopTimer($hash);
       $hash->{helper}{CronTime} = 0;
     }
   }

   if ($aName eq "tmpRadolanData") {

     return undef if $aVal eq $hash->{TMPDIR};

     if ($cmd eq "set") {

       eval {File::Path::make_path($aVal) };
       if($@) {
         return "Temporary directory: $aVal could not be created.";
       }

       if ($hash->{TMPDIR} ne $hash->{helper}{baseTMPDIR}) {

         if ( -e $hash->{TMPDIR} and -d $hash->{TMPDIR}) {
           my @delDirs   = split(/\//, $hash->{TMPDIR});
           my $dirDeepth = @delDirs;
          
           for(my $cnt = $dirDeepth; $cnt > 0; $cnt--) {

             my $delPath = join("/", @delDirs);

             CDCOpenData_Log $hash, 4, "deleting $delPath";

             eval {File::Path::remove_tree( $delPath )};
             if($@) {
               return "Temporary directory: $hash->{TMPDIR} could not be removed.";
             }

             pop @delDirs;
           }
         }
       }

       $hash->{TMPDIR} = $aVal;

     }

     if ($cmd eq "del") {

       return undef if $hash->{helper}{baseTMPDIR} eq $hash->{TMPDIR};

       if ( -e $hash->{TMPDIR} and -d $hash->{TMPDIR}) {

         my @delDirs   = split(/\//, $hash->{TMPDIR});
         my $dirDeepth = @delDirs;
         
         for(my $cnt = $dirDeepth; $cnt > 0; $cnt--) {

           my $delPath = join("/", @delDirs);

           CDCOpenData_Log $hash, 4, "deleting $delPath";

           eval {File::Path::remove_tree( $delPath )};
           if($@) {
             return "Temporary directory: $hash->{TMPDIR} could not be removed.";
           }

           pop @delDirs;
         }

          $hash->{TMPDIR} = $hash->{helper}{baseTMPDIR};

       } else {
         CDCOpenData_Log $hash, 4, "no tmpDir $hash->{TMPDIR} found.";
       }

     }

   } # end tmpRadolanData

   if ($aName eq "room") {
     if (my $dLog = AttrVal($name, "RainRadarFileLog", undef)) {
       if ($cmd eq "set") {
         my $dMod = 'attr -silent ' . $dLog . ' room ' . $aVal;
         fhem($dMod, 1);
       }
       if ($cmd eq "del") {
         my $dMod = 'deleteattr -silent ' . $dLog . ' room ';
         fhem($dMod, 1);
       }
     }
   }

   if ($aName eq "group") {
     if (my $dLog = AttrVal($name, "RainRadarFileLog", undef)) {
       if ($cmd eq "set") {
         my $dMod = 'attr -silent ' . $dLog . ' group ' . $aVal;
         fhem($dMod, 1);
       }
       if ($cmd eq "del") {
         my $dMod = 'deleteattr -silent ' . $dLog . ' group ';
         fhem($dMod, 1);
       }
     }
   }

   if ($aName eq "ownRadarFileLog") {
     my $dirdef   = Logdir() . "/";
     my $rLogFile = $dirdef . $hash->{helper}{rainLog} . '.log';

     if ($cmd eq "set") {
       return "ownRadarFileLog: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;

       my $dMod  = 'defmod ' . $hash->{helper}{rainLog} . ' FileLog ' . $rLogFile . ' FakeLog readonly';

       fhem($dMod, 1);

       if (my $dRoom = AttrVal($name, "room", undef)) {
         $dMod = 'attr -silent ' . $hash->{helper}{rainLog} . ' room ' . $dRoom;
         fhem($dMod, 1);
       }

       if (my $dGroup = AttrVal($name, "group", undef)) {
         $dMod = 'attr -silent ' . $hash->{helper}{rainLog} . ' group ' . $dGroup;
         fhem($dMod, 1);
       }
     }
     if ($cmd eq "del") {
       fhem("delete " . $hash->{helper}{rainLog});
     }
   } # end ownRadarFileLog

   if ($aName eq "RainRadarFileLog") {
     if ($cmd eq "set") {

       return "Device: $aVal already defined." if defined $defs{$aVal};

       CDCOpenData_Log $hash, 3, "Attr $cmd $aName -> $init_done";

       if (my $dLog = AttrVal($name, $aName, undef)) {

         fhem('rename ' . $dLog . ' ' . $aVal, 1);

       } else {

         my $dMod  = 'defmod ' . $aVal . ' FileLog ./log/' . $name . '-%Y-%m.log ' . $name . ':.*?_rain_radar/..:.*';
         fhem($dMod, 1);

         $dMod  = 'attr -silent ' . $aVal . ' outputFormat { return $TIMESTAMP." ".$NAME." ".$1." ".$2."\n" if $EVENT =~ /(.*?)\/.*?:\s(.*)/}';
         fhem($dMod, 1);

         if (my $dRoom = AttrVal($name, "room", undef)) {
           $dMod = 'attr -silent ' . $aVal . ' room ' . $dRoom;
           fhem($dMod, 1);
         }

         if (my $dGroup = AttrVal($name, "group", undef)) {
           $dMod = 'attr -silent ' . $aVal . ' group ' . $dGroup;
           fhem($dMod, 1);
         }
       }
     }

     if ($cmd eq "del") {
       if (my $dLog = AttrVal($name, $aName, undef)) {
         return "FileLog Device: $dLog not defined." unless defined $defs{$dLog};
         fhem('delete ' . $dLog, 1);
       }
     }
   } # end RainRadarFileLog
 
   if ($aName eq "enableDWDdata") {
     CDCOpenData_Log $hash, 5, "Attr $cmd $aName -> " . $aVal;
     if ($aVal !~ /rainByDay/) {
       fhem( "deletereading $name .*_day_rain:.*", 1 );
     }
     if ($aVal !~ /rainSinceMidnight/) {
       fhem( "deletereading $name .*_since_midnight:.*", 1 );
     }
     if ($aVal !~ /rainRadarbyLocation/) {
       fhem( "deletereading $name .*_rain_radar:.*", 1 );
     }
   }

   if ($aName eq "updateOnStart") {
     if ($cmd eq "set") {
       return "updateOnStart: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
   }

   # Stop the sub if FHEM is not initialized yet
   unless ($init_done) {
     CDCOpenData_Log $hash, 5, "Attr $cmd $aName -> no action while init running";
     return undef;
   }

   if ( $aName eq "disable") {
     if ($hash->{helper}{CronTime}) {
       CDCOpenData_StopTimer($hash);
       if ( $cmd eq "del" || $aVal == 0) {
         CDCOpenData_StartTimer($hash);
         CDCOpenData_Log $hash, 4, "Attr $cmd $aName -> Neustart internal Timer: hash";
       }
     } else {
       RemoveInternalTimer($hash->{helper}{TimerReadout});
       if ( $cmd eq "del" || $aVal == 0) {
         InternalTimer(gettimeofday()+1, "CDCOpenData_Readout_Start", $hash->{helper}{TimerReadout}, 1);
         CDCOpenData_Log $hash, 4, "Attr $cmd $aName -> Neustart internal Timer: hash->helper->TimerReadout";
       }
     }
   }

   if ( $aName =~ /INTERVAL|nonblockingTimeOut/ ) {
     CDCOpenData_Log $hash, 5, "Attr $cmd $aName -> INTERVAL|nonblockingTimeOut";
     unless ($hash->{helper}{CronTime}) {
       RemoveInternalTimer($hash->{helper}{TimerReadout});
       unless (IsDisabled($name)) {
         InternalTimer(gettimeofday()+1, "CDCOpenData_Readout_Start", $hash->{helper}{TimerReadout}, 1);
         CDCOpenData_Log $hash, 3, "Attr $cmd $aName -> Neustart internal Timer: hash->helper->TimerReadout";
       }
     }
   }

   return undef;
} # end CDCOpenData_Attr

# Starts the data capturing and sets the new readout timer
#######################################################################
sub CDCOpenData_Cron_Run($)
{
  my ($hash) = @_;
  my $name = $hash->{'NAME'};

  if (IsDisabled($name)) {
    CDCOpenData_Log $hash, 2, 'cron not startet while disabled device';
    return;
  }

  unless ($hash->{helper}{CronTime}) {
    CDCOpenData_Log $name, 4, "start timer: CDCOpenData_Readout_Start -> hash->helper->TimerReadout";
    RemoveInternalTimer($hash->{helper}{TimerReadout});
    InternalTimer(gettimeofday() + 1 , "CDCOpenData_Readout_Start", $hash->{helper}{TimerReadout}, 0);

  } else {

    my $cron = AttrVal($name, 'cronTime', '0 * * * *');
    $hash->{'CONFIG'}->{'CRON'} = \$cron;

    my $err;
    ($hash->{'CRON'}, $err) = FHEM::Scheduler::Cron->new($cron);
    if ($err) {
      $hash->{'NEXT'} = sprintf('NEVER (%s)', $err);
      CDCOpenData_Log $hash, 2, 'cron returned error: ' . $err;
    } else {
      CDCOpenData_Log $hash, 4, 'cron startet ';
      CDCOpenData_StartTimer($hash);
      CDCOpenData_Readout_Run_Data($name, undef, undef, 0) if AttrVal($name, 'updateOnStart', 0);
    }
  }
  return;

} # end CDCOpenData__Cron_Run

#######################################################################
sub CDCOpenData_Set($$@)
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";

   my $list =  " update:noArg"
            .  " htmlBarAsStateFormat:on,off";

   if ( lc $cmd eq 'update' ) {
      CDCOpenData_Log $hash, 3, "set $name $cmd " . join(" ", @val);
      $hash->{fhem}{UPDATE} = 1;
      CDCOpenData_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{UPDATE} = 0;
      return undef;
   }

   elsif ( lc $cmd eq 'htmlbarasstateformat' ) {
      return "wrong parameter" if int @val != 1 || $val[0] !~ /on|off/;
      if ($val[0] eq "on") {
        fhem("attr $name stateFormat {CDCOpenData_radar2html('" . $name . "','Home_rain_radar',0)}");
      } else {
        fhem("deleteattr -silent $name stateFormat");
        $hash->{STATE} = ReadingsVal($name, "state", "");
      }
      return 'please save the change in the stateFormat attribute by clicking on “Save config”';
   }

   return "Unknown argument $cmd or wrong parameter(s), choose one of $list";

} # end CDCOpenData_Set

#######################################################################
sub CDCOpenData_Get($@)
{
   my ($hash, $name, $cmd, @val) = @_;
   my $returnStr;

   my $cntVal = int @val;

   if( lc $cmd eq "rainbylatlongdate") {
      CDCOpenData_Log $hash, 3, "get $name $cmd " . join(" ", @val);

      if ($cntVal == 0) {
        $returnStr = CDCOpenData_Readout_Run_getRain($name, undef, undef, 1);
      } elsif ( $cntVal == 1) {
        my $vld1 = ($val[0] =~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/);
        my $vld2 = CDCOpenData_valid_date_time($val[0]);
        if ( !$vld1 || !$vld2 ) {
          $returnStr = "argument: $val[0] is not a valid date (yyyy-mm-dd) or a valid coordinate (latitude,longitude).";
        }
        $returnStr = CDCOpenData_Readout_Run_getRain($name, undef, $val[0], 1) if $vld1;
        $returnStr = CDCOpenData_Readout_Run_getRain($name, $val[0], undef, 1) if $vld2;
      } elsif ( $cntVal == 2) {
        my $vld1 = ($val[0] =~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/);
        my $vld2 = CDCOpenData_valid_date_time($val[1]);
        if ( !$vld1 || !$vld2 ) {
          $returnStr = "argument date: $val[0] not valid. please enter a correct latitude, longitude in the form latitude,longitude." unless $vld1;
          $returnStr = "argument date: $val[1] not valid. please enter a correct date in the form yyyy-mm-dd." unless $vld2;
        }
        $returnStr = CDCOpenData_Readout_Run_getRain($name, $val[1], $val[0], 1);
      } else {
        return "Wrong number of arguments, usage: get $name rainbyLatLong [latitude,longitude] [date]";
      }

      return $returnStr;
   }

   if( lc $cmd eq "rainsincemidnight") {
      CDCOpenData_Log $hash, 3, "get $name $cmd " . join(" ", @val);

      if ($cntVal == 0) {
        $returnStr = CDCOpenData_Readout_Run_Rain_Since_Midnight($name, undef, undef, 1);
      } elsif ( $cntVal == 1) {
        my $vld1 = ($val[0] =~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/);
        if ( !$vld1 ) {
          $returnStr = "argument: $val[0] is not a valid coordinate (latitude,longitude).";
        }
        $returnStr = CDCOpenData_Readout_Run_Rain_Since_Midnight($name, undef, $val[0], 1) if $vld1;
      } else {
        return "Wrong number of arguments, usage: get $name rainbyLatLong [latitude,longitude]";
      }

      return $returnStr;
   }

   if( lc $cmd eq "rainradar") {
      CDCOpenData_Log $hash, 3, "get $name $cmd " . join(" ", @val);

      if ($cntVal == 0) {
        $returnStr = CDCOpenData_get_RegenRadar_atLocations($name, undef, undef, 1);
      } elsif ( $cntVal == 1) {
        my $vld1 = ($val[0] =~ /[0-9]*\.[0-9]*,[0-9]*\.[0-9]*/);
        if ( !$vld1 ) {
          $returnStr = "argument: $val[0] is not a valid coordinate (latitude,longitude).";
        }
        $returnStr = CDCOpenData_get_RegenRadar_atLocations($name, undef, $val[0], 1) if $vld1;
      } else {
        return "Wrong number of arguments, usage: get $name rainRadar [latitude,longitude]";
      }

#      push @cmdBuffer, "rainradar " . join(" ", @val);
#      return CDCOpenData_Set_Cmd_Start $hash->{helper}{TimerCmd};

      return $returnStr;
   }

   my $list;
   $list .= "rainbyLatLongDate ";
   $list .= "rainSinceMidnight ";
   $list .= "rainRadar";

   return "Unknown argument $cmd, choose one of $list" if defined $list;

} # end CDCOpenData_Get

# übernommen von : https://www.regular-expressions.info/dates.html
#######################################################################
sub CDCOpenData_valid_date_time {

  my $input = shift;

#  if ($input =~ m!^((?:19|20)\d\d)[- /.](0[1-9]|1[012])[- /.](0[1-9]|[12][0-9]|3[01])T\s+([01][0-9]|2[0-3])[/:.]([0-5][0-9])[/:.]([0-5][0-9]) $!) {
  if ($input =~ m!^((?:19|20)\d\d)[- /.](0[1-9]|1[012])[- /.](0[1-9]|[12][0-9]|3[01])$!) {
    # At this point, $1 holds the year, $2 the month and $3 the day,
    # $4 the hours, $5 the minutes and $6 the seconds of the date/time entered
    if ($3 == 31 and ($2 == 4 or $2 == 6 or $2 == 9 or $2 == 11))
    {
      return 0; # 31st of a month with 30 days
    } elsif ($3 >= 30 and $2 == 2) {
      return 0; # February 30th or 31st
    } elsif ($2 == 2 and $3 == 29 and not ($1 % 4 == 0 and ($1 % 100 != 0 or $1 % 400 == 0))) {
      return 0; # February 29th outside a leap year
    } else {
      return 1; # Valid date/time
    }
  } else {
    return 0; # No valid date/time
  }
}

# Starts the data capturing and sets the new readout timer
#######################################################################
sub CDCOpenData_Readout_Start($)
{
   my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );                           # rechter Punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};

   CDCOpenData_Log $name, 4, "start CDCOpenData_Readout_Start with $name, $func, $index";

   my $runFn;
   my $timeout;

   if( AttrVal( $name, "disable", 0 ) ) {
     RemoveInternalTimer($hash->{helper}{TimerReadout});
     readingsSingleUpdate( $hash, "state", "disabled", 1 );
     $hash->{'CONFIG'}->{'IN_REQUEST'} = 0;
     CDCOpenData_Log $hash, 3, "disabled or set update: $hash->{fhem}{UPDATE} or in request: $hash->{'CONFIG'}->{'IN_REQUEST'}";
     return undef;
   }

   # Set timeout for BlockinCall
   $hash->{TIMEOUT} = AttrVal( $name, "nonblockingTimeOut", 55 );
   $timeout = $hash->{TIMEOUT};

   if ( $hash->{helper}{CronTime} ) {
     CDCOpenData_Log $hash, 4, 'INFO: start request';

     CDCOpenData_StopTimer($hash);
     CDCOpenData_StartTimer($hash);
   } else {

     # Set timer value (min. 60)
     $hash->{INTERVAL} = AttrVal( $name, "INTERVAL", 300 );
     $hash->{INTERVAL} = 60 if $hash->{INTERVAL} < 60 && $hash->{INTERVAL} != 0;

     my $interval = $hash->{INTERVAL};

     $hash->{TIMEOUT} = $interval - 10 if $hash->{TIMEOUT} > $hash->{INTERVAL};

     $timeout = $hash->{TIMEOUT};

     if ($hash->{fhem}{UPDATE} == 0) {

       if( $interval != 0 ) {
         RemoveInternalTimer($hash->{helper}{TimerReadout});
         InternalTimer(gettimeofday() + $interval, "CDCOpenData_Readout_Start", $hash->{helper}{TimerReadout}, 1);
       }
     }
   }

   # prevent simultaneous request
   return undef if ($hash->{'CONFIG'}->{'IN_REQUEST'});

   $hash->{'CONFIG'}->{'IN_REQUEST'} = 1;

# Kill running process if "set update" is used
   $runFn = "CDCOpenData_Readout_Run_Data";

   if ( exists( $hash->{helper}{READOUT_RUNNING_PID} ) && $hash->{fhem}{UPDATE} == 1 ) {
      CDCOpenData_Log $hash, 4, "Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID};

      BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} );

      delete( $hash->{helper}{READOUT_RUNNING_PID} );
   }

   $hash->{fhem}{UPDATE} = 2 if $hash->{fhem}{UPDATE} == 1;

   unless( exists $hash->{helper}{READOUT_RUNNING_PID} ) {
      CDCOpenData_Log $name, 5, "BlockingCall $runFn with $name, $timeout";

      $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall($runFn, $name,
                                                       "CDCOpenData_Readout_Done", $timeout,
                                                       "CDCOpenData_Readout_Aborted", $hash);
#      $hash->{helper}{READOUT_RUNNING_PID}->{loglevel} = GetVerbose($name);

      CDCOpenData_Log $hash, 4, "Fork process $runFn";
   }
   else {
      CDCOpenData_Log $hash, 4, "Skip fork process $runFn";
   }

} # end CDCOpenData_Readout_Start

# Starts the readout and sets the new timer
#######################################################################
sub CDCOpenData_Readout_Run_Data($@)
{
   my ($name, $time, $latlong, $fromGet) = @_;
   my $hash = $defs{$name};

   $fromGet = $fromGet ||= 0;

   my $result;
   my $rName;
   my @roReadings;
   my $startTime  = time();
   my $returnStrM = "";
   my $returnStrD = "";
   my $returnStrR = "";
   my $returnStr  = "";

   use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

   my $dwdData = AttrVal($name, "enableDWDdata", ""); #rainByDay, rainSinceMidnight, rainRadarbyLocation

   if ( $dwdData =~ /rainSinceMidnight/ ) {
     CDCOpenData_Log $name, 5, "start CDCOpenData_Readout_Run_Rain_Since_Midnight with $name, $fromGet";
     $returnStrM = CDCOpenData_Readout_Run_Rain_Since_Midnight($name, $time, $latlong, $fromGet);
     return $name . "|" . encode_base64($returnStrM,"") if $returnStrM =~ /Error\|/;
   }

   if ( $dwdData =~ /rainByDay/ ) {
     my $holdCnt = AttrVal( $name, "numberOfDays", 5);

     for (my $i = 1; $i <= $holdCnt; $i++) {
       my $holdTime = $i * 86400;
       my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time - (time % 86400) - $holdTime);
       $time = ($Jahr + 1900) . "-" . sprintf("%02d",$Monat + 1) . "-" . substr("00" . $Monatstag, -2);
       CDCOpenData_Log $name, 3, "start CDCOpenData_Readout_Run_getRain with $name, $fromGet, $time";
       $returnStrD .= CDCOpenData_Readout_Run_getRain($name, $time, $latlong, $fromGet, $i) . "|";
       return $name . "|" . encode_base64($returnStrR,"") if $returnStrD =~ /Error\|/;
     }
     chop($returnStrD);
   }

   if ( $dwdData =~ /rainRadarbyLocation/ ) {
     if (my $cFileLog = AttrVal($name, "clearRadarFileLog", undef)) {
       fhem("set $cFileLog clear", 1) if defined $defs{$cFileLog};
     }
     if (my $cFileLog = AttrVal($name, "RainRadarFileLog", undef)) {
       fhem("set $cFileLog clear", 1) if defined $defs{$cFileLog};
     }
     CDCOpenData_Log $name, 5, "start CDCOpenData_Readout_Run_Rain_Since_Midnight with $name, $fromGet";
     $returnStrR = CDCOpenData_get_RegenRadar_atLocations($name, $time, $latlong, $fromGet);
     return $name . "|" . encode_base64($returnStrR,"") if $returnStrR =~ /Error\|/;
   }

   $returnStr .= $returnStrM . "|" if $returnStrM ne "";

   $returnStr .= $returnStrD . "|" if $returnStrD ne "";

   $returnStr .= $returnStrR . "|" if $returnStrR ne "";

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   $returnStr .= join('|', @roReadings );

   CDCOpenData_Log $name, 5, "returnStr: \n" . $name . "|\n" . $returnStr;

   return $name . "|" . encode_base64($returnStr,"");

}

# get rain radar at a location
#######################################################################
sub CDCOpenData_get_RegenRadar_atLocations($$$$) {

   my ($name, $time, $latlong, $fromGet) = @_;
   my $hash = $defs{$name};

   $fromGet = $fromGet ||= 0;

   my $result;
   my $rName;
   my @roReadings;
   my $startTime = time();
   my $targettime_0050;
   my $returnStr;

   my $HOST    = $hash->{DWDHOST};
   my $DWDpath = "/weather/radar/composite/rv/";

   CDCOpenData_Log $name, 5, "################ get_RegenRadar_atLocations called ################";

   use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);

   # create ftp instance to DWD opendata server:
   my $ftp = Net::FTP->new($HOST, Debug => 0, Timeout => 10);
   if (defined($ftp)) {

      unless ($ftp->login()) {

         CDCOpenData_Log $name, 3, "ftp login failed: $ftp->message";

         if ($fromGet) {
           $ftp->quit;
           $returnStr = "ERROR: ftp login failed: " . $ftp->message;
           return $returnStr;
         } else {
           $ftp->quit;
           $returnStr = "Error|ftp login failed: " . $ftp->message;
           $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
           return $returnStr;
         }
      }

      $ftp->cwd($DWDpath);
      $ftp->binary;

   } else {

     CDCOpenData_Log $name, 3, "no ftp instance available";

     if ($fromGet) {
       $returnStr = "ERROR: no ftp instance available";
       return $returnStr;
     } else {
       $returnStr = "Error|no ftp instance available";
       $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
       return $returnStr;
     }
   }

   my $geoRef;

   if ($latlong) {
     $geoRef = $latlong
   } else {
     # calculate index of rainfall data for the given geo position:
     $geoRef = $hash->{LOCATION};

     my $geoRefAttr = AttrVal($name, "locations", undef);
     $geoRef .= " " . $geoRefAttr if $geoRefAttr;
     CDCOpenData_Log $name, 5, "geoRefsAttr: " . $geoRef;
   }

   my $geoCnt = 0;
   my $geoName = "";

   # get handle to the remote file "DE1200_RV_LATEST.tar.bz2":
   my $remote_tar_bz2_file_handle = $ftp->retr("DE1200_RV_LATEST.tar.bz2");

   unless( $remote_tar_bz2_file_handle ) {
     if ($fromGet) {
       $ftp->quit;
       $returnStr = "ERROR: reading 'DE1200_RV_LATEST.tar.bz2' failed";
       return $returnStr;
     } else {
       $ftp->quit;
       $returnStr = "Error|reading 'DE1200_RV_LATEST.tar.bz2' failed";
       $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
       return $returnStr;
     }
   }

   # uncompress tar file in-memory and get handle to the in-memory file:
   my $uncompressed_fh;
   unless ( $uncompressed_fh = IO::Uncompress::Bunzip2->new($remote_tar_bz2_file_handle) ) {
     if ($fromGet) {
       close $remote_tar_bz2_file_handle;
       $ftp->quit;
       $returnStr = "ERROR: IO::Uncompress::Bunzip2 failed: $IO::Uncompress::Bunzip2::Bunzip2Error";
       return $returnStr;
     } else {
       close $remote_tar_bz2_file_handle;
       $ftp->quit;
       $returnStr = "Error|IO::Uncompress::Bunzip2 failed: $IO::Uncompress::Bunzip2::Bunzip2Error";
       $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
       return $returnStr;
     }

   } else {

     # Read the tar archive from the uncompressed file handle
     my $tar = Archive::Tar->new;
     $tar->read($uncompressed_fh);

     my @list_of_files_in_tar = $tar->list_files;
     my $filename = $list_of_files_in_tar[0];

     $filename =~ /DE1200_RV(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)_000/;
     my $firsttime = timegm( 0, $5, $4, $3, $2-1, $1);

     my $timestamp;
     my $file_content;
     my $ETX_index;
     my $geo_index;
     my $rain_forecast;

     foreach my $location (split / /, $geoRef) {
       CDCOpenData_Log $name, 5, "geoLocation: " . $location;

       if ($location =~ /(.*?):/) {
         $geoName = $1;
         $location =~ s/.*?://;
       } else {
         $geoName = "loc" . $geoCnt;
       }
       $geoName .= "_rain_radar";

       CDCOpenData_Log $name, 5, "geoName: " . $geoName;

       $location =~ s/(.*?)://;
       $geo_index = CDCOpenData_index_for_geo_position( (split(/,/,$location))[0], (split(/,/,$location))[1], "WGS84");

       foreach my $file (@list_of_files_in_tar) {
         # parse forecast timestamp from filename
         $file =~ /DE1200_RV(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)_(\d\d\d)/;
         $timestamp = strftime ("%Y-%m-%d_%H:%M:%S", localtime($firsttime + 60 * $6));
		
         $file_content = $tar->get_content($file);
         if ($file_content) {
           my $rName = $geoName . ":" . $timestamp;
 
           # find index of ETX character (it marks the end of the header)
           $ETX_index = index($file_content,"\x03");

           $rain_forecast = substr($file_content, $ETX_index + 1 + 2 * $geo_index, 2);  # read 2 bytes at that position

           # unpack the little-endian number and mask out bits 13..16
           # unit of precipitation is 0.01 ltr/m²/h

           $rain_forecast = unpack( 'v*', $rain_forecast ) & 0xFFF;

           # A value of 2500 in the file marks invalid data.
           # It is reset to -1 in order to keep the y-axis scale small when plotting.

           if ($rain_forecast == 2500) {
             $rain_forecast = -1 ;
             CDCOpenData_Log $name, 4, "Regen Radar: " . $rName . ": error in value";
           } else {
             $rain_forecast *= 0.01;
           }
		 
           CDCOpenData_Log $name, 5, "Regen Radar: " . $rName . ": $rain_forecast";

           CDCOpenData_Readout_Add_Reading $hash, \@roReadings, $rName, $rain_forecast;
           $returnStr .= $rName . ": " . $rain_forecast . "|";

         } else {
           CDCOpenData_Log $name, 4, "Regen Radar: no filecontent: " . $file;
         }
       }
     }

     # Close the file handles
     close $uncompressed_fh;

   }

   close $remote_tar_bz2_file_handle;
   $ftp->quit;

   CDCOpenData_Log $name, 5, "################ End get_RegenRadar_atLocations ################";

   chop($returnStr);
   return $returnStr if $fromGet;

   CDCOpenData_Log $hash, 4, "Captured " . @roReadings . " values";
   CDCOpenData_Log $hash, 5, "Handover to calling process (" . length ($returnStr) . "): " . $returnStr;

   CDCOpenData_Log $name, 5, "returnStr: " . $returnStr;

   return join('|', @roReadings);

}

# get rain data since midnight for a location
#######################################################################
sub CDCOpenData_Readout_Run_Rain_Since_Midnight ($@) {

   my ($name, $time, $latlong, $fromGet) = @_;
   my $hash = $defs{$name};

   $fromGet = $fromGet ||= 0;

   my $result;
   my $rName;
   my @roReadings;
   my $startTime = time();
   my $targettime_0050;
   my $returnStr;

   CDCOpenData_Log $name, 5, "################ get_rain_since_midnight called ################";

   if (!defined $time) { 
     # 00:50 today:
     $targettime_0050 = timelocal(gmtime(3000 + time - (time % 86400)));
   } else {
     if ($time =~ /(\d{4}).(\d\d).(\d\d)/) {
       # if a target date is provided, the target time will be set to midnight of that day:
       $targettime_0050 = timelocal("00", "50", "00", $3, $2 - 1, $1 - 1900);
     }
   }
   CDCOpenData_Log $name, 4, "targettime ($targettime_0050) is " . strftime("%Y-%m-%d  %H:%M:%S", localtime($targettime_0050));
   
   my $HOST    = $hash->{DWDHOST};
   my $DWDpath = "/climate_environment/CDC/grids_germany/hourly/radolan/recent/bin/";

   # create ftp instance to DWD opendata server:
   my $ftp = Net::FTP->new($HOST, Debug => 0, Timeout => 10);
   if (defined($ftp)) {

      unless ($ftp->login()) {

         CDCOpenData_Log $name, 3, "ftp login failed: $ftp->message";

         if ($fromGet) {
           $ftp->quit;
           $returnStr = "ERROR: ftp login failed: " . $ftp->message;
           return $returnStr;
         } else {
           $ftp->quit;
           $returnStr = "Error|ftp login failed: " . $ftp->message;
           $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
           return $returnStr;
         }
      }

      $ftp->cwd($DWDpath);
      $ftp->binary;

   } else {

     CDCOpenData_Log $name, 3, "no ftp instance available";

     if ($fromGet) {
       $returnStr = "ERROR: no ftp instance available";
       return $returnStr;
     } else {
       $returnStr = "Error|no ftp instance available";
       $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
       return $returnStr;
     }
   }

   # select only files with minute=50 in their filename:
   # Hourly files are provided every 10 minutes, but only the ones taken at 00:50 are used.
   # They fit without overlap to the 00:50 time boundaries provided by radolan's daily data files
   my @files = grep /10000.........50/, $ftp->ls();

   if (! @files) {
     $returnStr = "Error|grep received no files";
     $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
     return $returnStr;
   }

   my $remotename; 
   my $filetime;

   my @files_today;

   $files[-1] =~ /10000-(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;

   my $most_recent_filetime = fhemTimeGm(0,$5,$4,$3,$2-1,$1+100);

   # select only files for today:
   # (I found no way to achieve this with a simple grep pattern since due to UTC usage, files stem from different days)

   foreach my $file (reverse @files) {	
     $file =~ /10000-(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;

     # extract file's timestamp from its name:
     $filetime = fhemTimeGm(0, $5, $4, $3, $2-1, $1+100); 
     push(@files_today, $file);

     last if ( $filetime <= $targettime_0050);
   }

   my $tmpDir = AttrVal($name, "tmpRadolanData", $hash->{helper}{baseTMPDIR}) . "/";

   my $geoRef;

   if ($latlong) {
     $geoRef = $latlong
   } else {
     # calculate index of rainfall data for the given geo position:
     $geoRef = $hash->{LOCATION};

     my $geoRefAttr = AttrVal($name, "locations", undef);
     $geoRef .= " " . $geoRefAttr if $geoRefAttr;
     CDCOpenData_Log $name, 5, "geoRefsAttr: " . $geoRef;
   }

   my $geoCnt = 0;
   my $geoName = "";
   my $regenmenge = -1;

   foreach my $location (split / /, $geoRef) {

     CDCOpenData_Log $name, 5, "geoLocation: " . $location;

     if ($location =~ /(.*?):/) {
       $geoName = $1;
       $location =~ s/.*?://;
     } else {
       $geoName = "loc" . $geoCnt;
     }

     $geoName .= "_since_midnight";

     CDCOpenData_Log $name, 5, "geoName: " . $geoName;

   # calculate index of rainfall data for the given geo position:
     my $index = CDCOpenData_index_for_geo_position( (split(/,/,$location))[0], (split(/,/,$location))[1], "" );
     my $regenmenge = 0;
	
     # extract amount of rain from today's files:
     foreach my $file (@files_today) {	
		
       # extract file's timestamp from its name:
       $file =~ /10000-(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
       $filetime = fhemTimeGm(0, $5, $4, $3, ($2-1), ($1+100));
 
       CDCOpenData_Log $name, 5, "file $file taken into account for rain_since_midnight: $filetime - $targettime_0050";

       if ($file =~ /(.*)\.gz/ ) {
         my $localname = $1;

         if (! -e $tmpDir . $localname ) {

           # get handle to the remote file:
           my $retr_fh = $ftp->retr($file);

           # use this handle to unzip the remote file 'on-the-fly':
           if (my $status = gunzip $retr_fh => $tmpDir . $localname, AutoClose => 1) {
             CDCOpenData_Log $name, 4,  "Rain_Since_Midnight - Loaded new local file $tmpDir$localname: $status";
           } else {
             CDCOpenData_Log $name, 3, "Rain_Since_Midnight - $GunzipError";
           }
         }

         # read value at index matching the geo-position:
         my $twobytes = get_2bytes_from_binfile($tmpDir . $localname, $index);

         # unpack the little-endian number and mask out bits 13..16:
         my $upMenge = (unpack( 'v*', $twobytes ) & 0xFFF);

         # A value of 2500 in the file marks invalid data.
         # It is reset to -1 in order to keep the y-axis scale small when plotting.

         if ($upMenge == 2500) {
           CDCOpenData_Log $name, 4, "Rain_Since_Midnight: error in value";
         } else {
           $regenmenge += 0.1 * $upMenge;
         }
       }

       # if old files in the directory
       last if ( $filetime <= $targettime_0050);
     }

     $geoName .= ":" . strftime("%Y-%m-%d_%H:%M:%S",localtime($most_recent_filetime));
     CDCOpenData_Readout_Add_Reading $hash, \@roReadings, $geoName, $regenmenge;
     CDCOpenData_Log $name, 5, "Regenmenge: " . $geoName . " Menge: " . $regenmenge;
     $returnStr .= $geoName . ": " . $regenmenge . "|";

     $geoCnt++;
   }

   # close ftp session:
   $ftp->quit;
	
   # remove old files from tmp_ftp/
   @files = glob($tmpDir . "*");
   foreach my $file (@files) {
     if ((-M $file > 3)) { 
       unlink $file;
       CDCOpenData_Log $hash, 4, "old local file: $file removed";
     }
   }

   CDCOpenData_Log $name, 5, "################ End get_rain_since_midnight ################";

   chop($returnStr);
   return $returnStr if $fromGet;

   CDCOpenData_Log $hash, 4, "Captured " . @roReadings . " values";
   CDCOpenData_Log $hash, 5, "Handover to calling process (" . length ($returnStr) . "): " . $returnStr;

   CDCOpenData_Log $name, 5, "returnStr: " . $returnStr;

   return join('|', @roReadings);

}

# Starts the rain capturing via FTP and sets the new timer
#######################################################################
sub CDCOpenData_Readout_Run_getRain($@)
{
   my ($name, $time, $latlong, $fromGet, $cnt) = @_;
   my $hash = $defs{$name};

   $fromGet = $fromGet ||= 0;

   my $result;
   my $rName;
   my @roReadings;
   my $startTime = time();
   my $numberOfDays = AttrVal($hash, "numberOfDays", 0);
   my $returnStr;

   CDCOpenData_Log $name, 5, "################ get_Regenmenge called ################";

   my $targettime;

   if (!defined $time) { 
     # time is not provided and will be set to yesterday midnight:
     $targettime = strftime("%Y-%m-%d 23:50:00",localtime(time-DAYSECONDS));
   } else {
     if ($time =~ /(\d{4}).(\d\d).(\d\d)/) {
       # if a target date is provided, the target time will be set to midnight of that day:
       $targettime = "$1-$2-$3 23:50:00";
     }
   }

   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime(time_str2num($targettime));
   my $localname = sprintf("raa01-sf_10000-%02d%02d%02d%02d%02d-dwd---bin",$year-100,$mon+1,$mday,$hour,$min);
   my $filetime  = time_str2num($targettime);
   
   CDCOpenData_Log $name, 5, "targettime is ". $targettime;
   
   my $tmpDir     = AttrVal($name, "tmpRadolanData", $hash->{helper}{baseTMPDIR}) . "/";
   my $remotename = $localname . ".gz";; 
	
   CDCOpenData_Log $name, 5, "file $remotename on CDC ftp-server is nearest to targettime";
   CDCOpenData_Log $name, 5, "localname $localname";
	
   # ftp-download only if file $localname does not exist:
   if (! -e $tmpDir . $localname ) {

     my $HOST    = $hash->{DWDHOST};
     my $DWDpath = "/climate_environment/CDC/grids_germany/daily/radolan/recent/bin/";

     # create ftp instance to DWD opendata server:
     my $ftp = Net::FTP->new($HOST, Debug => 0, Timeout => 10);

     if (defined($ftp)) {

       unless ($ftp->login()) {

         CDCOpenData_Log $name, 3, "ftp login failed: $ftp->message";

         if ($fromGet) {
           $ftp->quit;
           $returnStr = "ERROR: ftp login failed: $ftp->message";
           return $returnStr;
         } else {
           $ftp->quit;
           $returnStr = "Error|ftp login failed: " . $ftp->message;
           $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
           return $returnStr;
         }
       }
     } else {
       CDCOpenData_Log $name, 3, "no ftp instance available";

       if ($fromGet) {
         $returnStr = "ERROR: no ftp instance available";
         return $returnStr;
       } else {
         $returnStr = "Error|no ftp instance available";
         $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
         return $returnStr;
       }
     }

     $ftp->cwd($DWDpath);
     $ftp->binary;

     # get handle to the remote file:
     my $retr_fh = $ftp->retr($remotename); 

     if (defined $retr_fh) {
       CDCOpenData_Log $name, 4, "Trying to load new local file $tmpDir$localname " . $retr_fh
     } else {
       $ftp->quit;
       CDCOpenData_Log $name, 4, "ftp $tmpDir$remotename not found";
       if ($fromGet) {
         $returnStr = "ERROR: $tmpDir$remotename not found";
         $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
         return $returnStr;
       } else {
         CDCOpenData_Log $name, 4, "$tmpDir$remotename not found";
         $returnStr = "Error|$tmpDir$remotename not found";
         $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
         return $returnStr;
       }
     }

     # use this handle to unzip the remote file 'on-the-fly':
     if (my $status = gunzip $retr_fh => $tmpDir . $localname, AutoClose => 1) {
       CDCOpenData_Log $name, 4,  "getRain - Loaded new local file $tmpDir$localname: $status";
     } else {
       $ftp->quit;
       CDCOpenData_Log $name, 3, "getRain - $GunzipError";
       $returnStr = "Error|$tmpDir$remotename -> error while unpacking file";
       $returnStr .= "|" . join('|', @roReadings ) if int @roReadings;
       return $returnStr;
     }

     # close ftp session:
     $ftp->quit;
   }
	
   my $geoRef;
   if ($latlong) {
     $geoRef = $latlong;
   } else {
     # calculate index of rainfall data for the given geo position:
     $geoRef = $hash->{LOCATION};

     my $geoRefAttr = AttrVal($name, "locations", undef);
     $geoRef .= " " . $geoRefAttr if $geoRefAttr;
   }

   CDCOpenData_Log $name, 5, "geoRefsAttr: " . $geoRef;

   my $geoCnt = 0;
   my $geoName = "";
   my $regenmenge = -1;
   my $index;

   foreach my $location (split / /, $geoRef) {

     CDCOpenData_Log $name, 5, "geoLocation: " . $location;

     if ($location =~ /(.*?):/) {
       $geoName = $1;
       $location =~ s/.*?://;
     } else {
       $geoName = "loc" . $geoCnt;
     }

     $geoName .= "_day_rain";

     CDCOpenData_Log $name, 5, "geoName: " . $geoName;

     $index = CDCOpenData_index_for_geo_position( (split(/,/,$location))[0], (split(/,/,$location))[1], "" );

     CDCOpenData_Log $name, 5, "geoIndex: " . $index;

     # read value at index matching the geo-position:
     $regenmenge = get_2bytes_from_binfile($tmpDir . $localname, $index);

     # unpack the little-endian number and mask out bits 13..16
     # unit of precipitation is 0.1 ltr/m²:

     $regenmenge = unpack( 'v*', $regenmenge ) & 0xFFF;

     # A value of 2500 in the file marks invalid data.
     # It is reset to -1 in order to keep the y-axis scale small when plotting.
     if ($regenmenge == 2500) {
       $regenmenge = -1 ;
       CDCOpenData_Log $name, 4, "day rain: " . $tmpDir . $localname . ": error in rain value";
     } else {
       $regenmenge *= 0.1;
     }

     CDCOpenData_Log $name, 5, "Regenmenge extracted from: " . $tmpDir . $localname;

     $geoName .= "/" . substr( "00" . ($cnt - 1), -2) if $cnt;
     $geoName .= ":" . strftime("%Y-%m-%d_%H:%M:%S",localtime($filetime));
     CDCOpenData_Readout_Add_Reading $hash, \@roReadings, $geoName, $regenmenge;
     CDCOpenData_Log $name, 5, "Regenmenge: " . $geoName . " Menge: " . $regenmenge;
     $returnStr .= $geoName . ": " . $regenmenge . "|";
   
     $geoCnt++;

   }

   CDCOpenData_Log $name, 5, "################ End get_Regenmenge ################";

   chop($returnStr);
   return $returnStr if $fromGet;

   CDCOpenData_Log $hash, 4, "Captured " . @roReadings . " values";
   CDCOpenData_Log $hash, 5, "Handover to calling process (" . length ($returnStr) . "): " . $returnStr;

   CDCOpenData_Log $name, 5, "returnStr: " . $returnStr;

   return join('|', @roReadings );

} # End CDCOpenData_Readout_Run_getRain

#######################################################################
sub CDCOpenData_Readout_Done($)
{
   my ($string) = @_;
   unless (defined $string)
   {
      Log 1, "Fatal Error: no parameter handed over";
      return;
   }

   my ($name,$string2) = split("\\|", $string, 2);
   my $hash = $defs{$name};

   CDCOpenData_Log $hash, 5, "Back at main process.";

   # delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});

   # request done
   $hash->{'CONFIG'}->{'IN_REQUEST'} = 0;

   $string2 = decode_base64($string2);
   CDCOpenData_Readout_Process ($hash, $string2);

} # end CDCOpenData_Readout_Done

#######################################################################
sub CDCOpenData_Readout_Process($$)
{
   my ($hash,$string) = @_;

 # Fatal Error: no hash parameter handed over
   unless (defined $hash) {
      Log 1, "Fatal Error: no hash parameter handed over";
      return;
   }

   my $name = $hash->{NAME};

   my (%values) = split("\\|", $string);

   my @results = split("\\|", $string);

   my $merkNameRR = "";
   my $counter = 0;
   my $offset  = 0;
   my $dayRainCnt = 0;
   my $ownRadarFLog = AttrVal($name, "ownRadarFileLog", 0);
   my $dirdef   = Logdir() . "/";
   my $rLogFile = $dirdef . $hash->{helper}{rainLog} . '.log';

   my $textRadarLog = "";

   readingsBeginUpdate($hash);

   if ( defined $values{Error} ) {
      readingsBulkUpdate( $hash, "retStat_lastReadout", $values{Error} );
      readingsBulkUpdate( $hash, "state", $values{Error} );
   } else {
     foreach (keys %{ $hash->{READINGS} }) {
       if ( $_ =~ /^.*?_since_midnight.*?/ ) {
         if (exists $hash->{READINGS}{$_}{VAL}) {
           delete $hash->{READINGS}{$_};
           CDCOpenData_Log $hash, 4, "delete old readings: $_";
         }
       }
       if ( $_ =~ /^.*?_rain_radar.*?/ ) {
         if (exists $hash->{READINGS}{$_}{VAL}) {
           delete $hash->{READINGS}{$_};
           CDCOpenData_Log $hash, 4, "delete old readings: $_";
#           unlink $rLogFile if $ownRadarFLog;
         }
       }
     }

   # Statistics

   # Fill all handed over readings
     my $x = 0;

     use List::Util qw(pairs);
     my @pairs = {};
        @pairs = pairs @results;

     foreach my $t (@pairs) {

       my $rName  = $t->[0];
       my $rValue = $t->[1];

       if ($rName =~ /->/) {
       # 4 levels
          my ($rName1, $rName2, $rName3, $rName4) = split /->/, $rName;
       # 4th level (Internal Value)
          if ($rName1 ne "" && defined $rName4) {
             $hash->{$rName1}{$rName2}{$rName3}{$rName4} = $rValue;
          }
       # 3rd level (Internal Value)
          elsif ($rName1 ne "" && defined $rName3) {
             $hash->{$rName1}{$rName2}{$rName3} = $rValue;
          }
       # 1st level (Internal Value)
          elsif ($rName1 eq "") {
             $hash->{$rName2} = $rValue;
          }
       # 2nd levels
          else {
             $hash->{$rName1}{$rName2} = $rValue;
          }
       }

       my $newName = $rName;
       if ($newName =~ /:(\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d)/) {
         my $TS = $1;
         $TS =~ s/_/ /;
         $newName =~ s/:\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d//;

         if ($newName =~ /_since_midnight|_day_rain/) {
           my $vTS = ReadingsTimestamp($name, $newName, "");
           readingsBulkUpdate($hash, $newName, $rValue, undef, $TS) if $vTS ne $TS;

         } else {

           if ($merkNameRR ne $newName) {
             $merkNameRR = $newName;
             $counter = 0;
             $offset = 0;
           } else {
             $counter ++;
           }

           $offset = 0 if $offset == 60;
           $newName .= "/" . substr("00" . $counter, -2);
           $newName =~ s/://;
           readingsBulkUpdate($hash, $newName, $rValue, undef, $TS);

           my $text = $newName;
           $text =~ s/\/\d+//;
           $TS =~ s/ /_/;
           
           $textRadarLog .= $TS . " " . $name . " " . $text. ": " . $rValue . "\n";

           $offset += 5;

         }

       }

       # writing all other readings
       if ($rName !~ /->|readoutTime|_rain_radar|_since_midnight|_day_rain/) {
          if ($rValue ne "") {
             readingsBulkUpdate( $hash, $rName, $rValue );
             CDCOpenData_Log $hash, 5, "SET $rName = '$rValue'";
          }
          elsif ( exists $hash->{READINGS}{$rName} ) {
             delete $hash->{READINGS}{$rName};
             CDCOpenData_Log $hash, 5, "Delete reading $rName.";
          }
          else  {
             CDCOpenData_Log $hash, 5, "Ignore reading $rName.";
          }
       }
     }

     CDCOpenData_DebugLog($hash, $hash->{helper}{rainLog} . '.log', undef, $textRadarLog, "no") if $ownRadarFLog;

     my $msg = keys( %values ) . " values captured in " . $values{readoutTime} . " s";
     readingsBulkUpdate( $hash, "retStat_lastReadout", $msg );
     readingsBulkUpdate( $hash, "state", $msg);
     CDCOpenData_Log $hash, 5, "BulkUpdate lastReadout: " . $msg;
   }

   readingsEndUpdate( $hash, 1 );

} # end CDCOpenData_Readout_Process

#######################################################################
sub CDCOpenData_Readout_Aborted($)
{
   my ($hash) = @_;
   
   my $msg = "Error: Timeout when reading DWD data.";

   # delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});
   
   # request done
   $hash->{'CONFIG'}->{'IN_REQUEST'} = 0;

   readingsSingleUpdate($hash, "retStat_lastReadout", $msg, 1);
   readingsSingleUpdate($hash, "state", $msg, 1);
   CDCOpenData_Log $hash, 1, $msg;

} # end CDCOpenData_Readout_Aborted

# Auswertung des Format Parameters
#######################################################################
sub CDCOpenData_Readout_Format($$$)
{
   my ($hash, $format, $readout) = @_;

   $readout = "" unless defined $readout;

   return $readout unless defined( $format ) && $format ne "";

   if ($format eq "01" && $readout ne "1") {
      $readout = "0";
   }

   return $readout unless $readout ne "";

   return $readout;

} # end CDCOpenData_Readout_Format

#######################################################################
sub CDCOpenData_Readout_Add_Reading ($$$$@)
{
   my ($hash, $roReadings, $rName, $rValue, $rFormat) = @_;

   $rFormat = "" unless defined $rFormat;
   $rValue = CDCOpenData_Readout_Format ($hash, $rFormat, $rValue);

   push @{$roReadings}, $rName . "|" . $rValue ;

   CDCOpenData_Log $hash, 5, "$rName: $rValue";

} # end CDCOpenData_Readout_Add_Reading

##############################################################################################################################################
sub CDCOpenData_Set_Cmd_Start($)
{
   my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );

   my $index = rindex( $timerpara, "." );                            # rechter punkt
   my $func  = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name  = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash  = $defs{$name};
   my $cmdFunction;
   my $timeout;
   my $handover;

   return "no command in buffer." unless int @cmdBuffer;

 # kill old process if timeout + 10s is reached
   if ( exists( $hash->{helper}{CMD_RUNNING_PID}) && time()> $cmdBufferTimeout + 10 ) {
      CDCOpenData_Log $hash, 1, "Old command still running. Killing old command: ".$cmdBuffer[0];
      shift @cmdBuffer;
      BlockingKill( $hash->{helper}{CMD_RUNNING_PID} );
      # stop FHEM, giving FritzBox some time to free the memory
      delete $hash->{helper}{CMD_RUNNING_PID};
      return "no command in buffer." unless int @cmdBuffer;
   }

 # (re)start timer if command buffer is still filled
   if (int @cmdBuffer >1) {
      CDCOpenData_Log $hash, 3, "restarting internal Timer: command buffer is still filled";
      RemoveInternalTimer($hash->{helper}{TimerCmd});
      InternalTimer(gettimeofday()+1, "CDCOpenData_Set_Cmd_Start", $hash->{helper}{TimerCmd}, 1);
   }

# do not continue until running command has finished or is aborted

   my @val = split / /, $cmdBuffer[0];
   my $xline       = ( caller(0) )[2];
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/CDCOpenData_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   CDCOpenData_Log $hash, 5, "Set_CMD_Start -> $sub.$xline -> $val[0]";

   return "Process " . $hash->{helper}{CMD_RUNNING_PID} . " is still running" if exists $hash->{helper}{CMD_RUNNING_PID};

# Preparing SET Call
   if ($val[0] eq "call") {
      shift @val;
      $timeout = 60;
      $timeout = $val[2] if defined $val[2] && $val[2] =~/^\d+$/;
      $timeout += 30;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "CDCOpenData_Run_Call_Web";
   }
# Preparing GET fritzlog information
   elsif ($val[0] eq "rainradar") {
      $timeout = 40;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "CDCOpenData_get_RegenRadar_atLocations";
   }
# No valid set operation 
   else {
      my $msg = "Unknown command '".join( " ", @val )."'";
      CDCOpenData_Log $hash, 4, "" . $msg;
      return $msg;
   }

# Starting new command
   CDCOpenData_Log $hash, 4, "Fork process $cmdFunction";
   $hash->{helper}{CMD_RUNNING_PID} = BlockingCall($cmdFunction, $handover,
                                       "CDCOpenData_Set_Cmd_Done", $timeout,
                                       "CDCOpenData_Set_Cmd_Aborted", $hash);
#   $hash->{helper}{READOUT_RUNNING_PID}->{loglevel} = GetVerbose($name);
   return undef;
} # end CDCOpenData_Set_Cmd_Start

#######################################################################
sub CDCOpenData_Set_Cmd_Done($)
{
   my ($string) = @_;

   unless (defined $string)
   {
      Log 1, "FATAL ERROR: no parameter handed over";
      return;
   }

   my ($name, $success, $result) = split("\\|", $string, 3);
   my $hash = $defs{$name};

   CDCOpenData_Log $hash, 4, "Back at main process";

   shift (@cmdBuffer);
   delete($hash->{helper}{CMD_RUNNING_PID});

   if ( $success !~ /1|2|3/ )
   {
      CDCOpenData_Log $hash, 1, "" . $result;
      CDCOpenData_Readout_Process ( $hash, "Error|" . $result );
   }
   elsif ( $success == 1 )
   {
      CDCOpenData_Log $hash, 4, "" . $result;
   }
   elsif  ($success == 2 )
   {
      $result = decode_base64($result);
      CDCOpenData_Readout_Process ( $hash, $result );
   }
   elsif  ($success == 3 )
   {
      my ($resultOut, $cmd, $logJSON) = split("\\|", $result, 3);
      $result = decode_base64($resultOut);
      CDCOpenData_Readout_Process ( $hash, $result );

      CDCOpenData_Log $hash, 5, "fritzLog to Sub: $cmd \n" . $logJSON;

      my $jsonResult = eval { JSON->new->latin1->decode( $logJSON ) };
      if ($@) {
        CDCOpenData_Log $hash, 2, "Decode JSON string: decode_json failed, invalid json. error:$@";
      }

      CDCOpenData_Log $hash, 5, "Decode JSON string: " . ref($jsonResult);

      my $returnStr = eval { myUtilsFritzLogExPost ($hash, $cmd, $jsonResult); };

      if ($@) {
        CDCOpenData_Log $hash, 2, "fritzLogExPost: " . $@;
        readingsSingleUpdate($hash, "retStat_fritzLogExPost", "->ERROR: " . $@, 1);
      } else {
        readingsSingleUpdate($hash, "retStat_fritzLogExPost", $returnStr, 1);
      }
   }

} # end CDCOpenData_Set_Cmd_Done

#######################################################################
sub CDCOpenData_Set_Cmd_Aborted($)
{
  my ($hash) = @_;
  my $lastCmd = shift (@cmdBuffer);
  delete($hash->{helper}{CMD_RUNNING_PID});
  CDCOpenData_Log $hash, 1, "Timeout reached for: $lastCmd";

} # end CDCOpenData_Set_Cmd_Aborted

# create error response for return
############################################
sub CDCOpenData_ERR_Result($$;@) {

   my ($hash, $result, $retData) = @_;
   $retData = 0 unless defined $retData;
   my $name = $hash->{NAME};

   my $tmp;

   if (defined $result->{Error} ) {
     $tmp = "ERROR: " . $result->{Error};
   }
   elsif (ref ($result->{result}) eq "ARRAY" || ref ($result->{data}) eq "HASH" ){
     $tmp = Dumper ($result);
   }
   elsif (defined $result->{result} ) {
     $tmp = $result->{result};
   }
   elsif (defined $result->{pid} ) {
     $tmp = "$result->{pid}";
     if (ref ($result->{data}) eq "ARRAY" || ref ($result->{data}) eq "HASH" ) {
       $tmp .= "\n" . Dumper ($result) if $retData == 1;
     }
     elsif (defined $result->{data} ) {
       $tmp .= "\n" . $result->{data} if $retData == 1;
     }
   }
   elsif (defined $result->{sid} ) {
     $tmp = $result->{sid};
   }
   else {
     $tmp = "Unexpected result: " . Dumper ($result);
   }

   return $tmp;

} # end CDCOpenData_ERR_Result

# 
############################################
sub get_2bytes_from_binfile ($$) {
   my ($infile,$index) = @_;
   open my $in, '<:raw', $infile;             # open $infile in binary mode
   my $buf = '';
   my $success = read $in, $buf, 2000;        # read enough bytes to safely catch the header
   my $a = index($buf,"\x03");                # find index of ETX character 
                                              # (it marks the end of the header)
   seek $in, $a + 1 + 2 * $index, SEEK_SET;   # set file position to index, with ETX character at index-1
   $success = read $in, $buf, 2 ;             # read 2 bytes at that position
   close $in;                                 # close the file
   return $buf

} # end get_2bytes_from_binfile

# 
############################################
sub CDCOpenData_index_for_geo_position ($$$) {

   my ($lat,$long,$projection) = @_;
   $lat  *= pi/180;
   $long *= pi/180;
   my $index;
   my $lambda0 = 10*pi/180; 		#	lon_0: 10 * degToRad,
	
   if ($projection ne "WGS84") {
     # reference: https://www.dwd.de/DE/leistungen/radolan/radolan_info/radolan_radvor_op_komposit_format_pdf.html
     my $phi0 = 60*pi/180;
     my $M =(1 + sin($phi0))/(1 + sin($lat));
     my $k = 6370.04 * $M * cos($lat);
     my $x =  $k * sin($long - $lambda0) + 523.464340008831;#+ 523.4622;
     my $y = -$k * cos($long - $lambda0) + 4658.64211729744;#+ 4658.645;
     # $x: -523.464340008831,  $y: -4658.64211729744
     #print "\$x: $x,  \$y: $y\n";
     $index = 900 * floor($y) + floor($x);

   } else {  # WGS84 calculation
     # corner point coordinates From https://www.dwd.de/DE/leistungen/radarprodukte/formatbeschreibung_rv.pdf?__blob=publicationFile&v=3:
       # NW 55.86208711 1.463301510
       # NO 55.84543856 18.73161645
       # SO 45.68460578 16.58086935
       # SW 45.69642538 3.566994635		
     # data and code are from https://gitlab.cs.fau.de/since/radolan/-/blob/31ed7598ae1d/projection_wgs84.go
       # lon_0: 10 * degToRad,
       # ecc:   0.08181919084262032,
       # k_0:   11862667.042661695,
       # x_0:   543196.83521776402,
       # y_0:   3622588.861931001,	
       # scale: 1000, // unit per km		

     my $ecc   = 0.08181919084262032;
     my $k0    = 11862667.042661695;
     my $x0    = 543196.83521776402;
     my $y0    = 3622588.861931001;
     my $scale = 1000;
		
     my $sinlat = sin($lat); 
     my $s = $k0 * tan(pi/4 - $lat/2) / ((1 - $ecc * $sinlat)/(1 + $ecc * $sinlat))**(0.5*$ecc);
		
     my $x =  ($x0 + ($s * sin($long - $lambda0))) / $scale;
     my $y =  ($y0 - ($s * cos($long - $lambda0))) / $scale;

     $index  = 1100 * floor($y + 1199.5) +  floor($x + 0.5);
   }

   return $index

} # end CDCOpenData_index_for_geo_position

# 
############################################
sub CDCOpenData_StartTimer {
   my ($hash) = @_;
   my $name = $hash->{'NAME'};

   return if (!$init_done);

   my $cron = ${$hash->{'CONFIG'}->{'CRON'}};
   my @t = localtime(Time::HiRes::time());
 
   $t[4] += 1;
   $t[5] += 1900;
	
   my ($r, $err) = $hash->{'CRON'}->next(sprintf('%04d%02d%02d%02d%02d%02d', $t[5], $t[4], $t[3], $t[2], $t[1], $t[0]));

   if ($err) {

     $hash->{'NEXT'} = sprintf('NEVER (%s)', $err);
     CDCOpenData_Log $hash, 2, 'cron returned error: '. $err;

   } else {

     my @u = ($r =~ m/([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/);
     my $ts = timelocal($u[5], $u[4], $u[3], $u[2], $u[1] -1, $u[0] -1900);
     $hash->{'NEXT'} = sprintf('%04d-%02d-%02d %02d:%02d:%02d', @u);
     CDCOpenData_Log $hash, 4, "next request: " . $hash->{'NEXT'};
#     InternalTimer($ts, \&CDCOpenData_DoTimer, $hash);
     InternalTimer($ts, "CDCOpenData_Readout_Start", $hash->{helper}{TimerReadout}, 1);

   }

   return;

} # end CDCOpenData_StartTimer

# 
############################################
sub CDCOpenData_StopTimer {
   my ($hash) = @_;

   $hash->{'NEXT'} = 'NEVER' if ref($hash) eq 'HASH';
   CDCOpenData_Log $hash, 4, "remove CRON Timer: " . $hash->{'NEXT'};

#   RemoveInternalTimer($hash, \&CDCOpenData_DoTimer);
   RemoveInternalTimer($hash->{helper}{TimerReadout});

   return;

} # end CDCOpenData_StopTimer

# 
############################################
sub CDCOpenData_DoTimer {
   my ($hash) = @_;
   CDCOpenData_Log $hash, 4, 'INFO: start request';

   CDCOpenData_StartTimer($hash);
   # request in flight ? cancel
   return if ($hash->{'CONFIG'}->{'IN_REQUEST'});

   CDCOpenData_Readout_Start($hash->{helper}{TimerReadout});

   return;

} # end CDCOpenData_DoTimer

############################################
# Unterverzeichnisse erstellen
# Parameter
# Directory ... z.B. ../test/test1/test2
# Rechte im oktalen Format
# http://www.hidemail.de/blog/mkdir-perl.shtml
############################################
sub CDCOpenData_mk_subdirs{
   my $dir    = shift;
   my $rights = shift;
   my @dirs   = split(/\//,$dir);
   my $akdir='';

   $dir=~ s/^\s+//;                     # wenn führende Leerzeichen, dann entfernen
   $dir=~ s/\s+$//;                     # wenn abschließende Leerzeichen, dann entfernen
   $dir=~ s/^\///;                      # wenn führendes /, dann entfernen
   $dir=~ s/\/$//;                      # wenn abschließendes /, dann entfernen

   foreach (@dirs){
     $akdir.=$_;                        # Aktuelle Laufvariable, hier steht das aktuell zu erstellende Verzeichnis
     if (!-e $akdir){                   # wenn Ordner noch nicht vorhanden
       my $res = mkdir($akdir,$rights);   # Verzeichnis erstellen
       return 0 if ($res != 1);         # zurück mit 0 bei Fehler
     }
     $akdir.='/';
   }

   return 1;                            # OK, alles ging gut!!!

} # end CDCOpenData_mk_subdirs

############################################
# This is for htmlCode {radar2html('CDC','loc0_rain_radar')} Niederschlagsvorhersage (CDCOpenData)
# to create a HTML bar table with raincolors for the radarvalues
sub CDCOpenData_radar2html {

  my $name           = shift // 'CDC';                # return "Error, sub color2html: we need name as parameter!";
  my $reading        = shift // 'loc0_rain_radar';    # return "Error, sub color2html: we need reading as parameter!";
  my $headline       = shift // 1;

  my $as_htmlBarhead = '<tr style="font-size:x-small">';
  my $as_htmlTitel   = '';
  my $as_htmlBar     = '';
  my $count          = 1;
  my $num            = 25;
  my $i2;

  for (my $i = 0; $i < $num; $i++) {
    if ($i <= 9) {
      $i2 = '0'.$i
    } else { 
      $i2 = $i
    }
    my $radarvalue = ReadingsNum ($name,$reading.'/'.$i2,'-1');
    my $timestamp  = substr(ReadingsTimestamp($name,$reading.'/'.$i2,'2000-01-01 00:00:00'),11,5);
    my $color      = CDCOpenData_myColor2RGB($radarvalue);

    #Log 3, "[radar2html] i2=$i2, radarvalue=$radarvalue, color=$color, count=$count, timestamp=$timestamp"; #starttime=$starttime,

    if ($count > 1) {
      if ( ( ($count+2) % 4 ) == 0 || $i == 24) {
        $as_htmlBarhead .= '<td style="padding-left: 0; padding-right: 0">' . $timestamp . '</td>';
      } else {
        $as_htmlBarhead .= '<td style="padding-left: 0; padding-right: 0">&nbsp;&nbsp;&nbsp;&nbsp;</td>';
      }
      $as_htmlBar .= '<td style="padding-left: 0; padding-right: 0" bgcolor="' . $color . '">&nbsp;&nbsp;&nbsp;</td>';
    }
    $count++;
  }

  my $location  = '<b>' . AttrVal($name,'alias','MeineLocation') . '</b>'; # "<font color='red'>" . $body. "</font>"

  $as_htmlTitel = "Niederschlagsvorhersage f&uuml;r $location (<a href=./fhem?detail=$name>$name</a>)<br>" if $headline;
  $as_htmlBar = $as_htmlTitel . "<table>" . $as_htmlBarhead . "</tr><tr style='border:2pt solid black'>" . $as_htmlBar . '</tr></table>';

  return $as_htmlBar;

} # end CDCOpenData_radar2html


############################################
sub CDCOpenData_myColor2RGB {

  my $value = shift // return "Error, sub CDCOpenData_myColor2RGB: we need value as parameter!";
  my $a     = $value*4;
  my $b     = ($value-int($value))*2;
  my $RGB1  = CDCOpenData_myCalcColor($a);
  my $RGB2  = CDCOpenData_myCalcColor($b);
  return $RGB1.$RGB2.$RGB1.$RGB2.'FF';

} # end CDCOpenData_myColor2RGB

############################################
sub CDCOpenData_myCalcColor {

  my $a = shift // return "Error, sub CDCOpenData_myCalcColor: we need a as parameter!";
  if    ($a == 0)      {return 'F'} #transparent
  elsif ($a <= 0.0625) {return 'E'} #transparent
  elsif ($a <= 0.125)  {return 'D'}
  elsif ($a <= 0.1875) {return 'C'}
  elsif ($a <= 0.25)   {return 'B'}
  elsif ($a <= 0.3125) {return 'A'}
  elsif ($a <= 0.375)  {return '9'}
  elsif ($a <= 0.4375) {return '8'}
  elsif ($a <= 0.5)    {return '7'}
  elsif ($a <= 0.5625) {return '6'}
  elsif ($a <= 0.625)  {return '5'}
  elsif ($a <= 0.6875) {return '4'}
  elsif ($a <= 0.75)   {return '3'}
  elsif ($a <= 0.8125) {return '2'}
  elsif ($a <= 0.875)  {return '1'}
  elsif ($a <= 0.9375) {return '0'}
  else                 {return '0'}

} # end CDCOpenData_myCalcColor

###############################################################################

1;

=pod
=item device
=item summary Controls some features of AVM's FRITZ!BOX, FRITZ!Repeater and Fritz!Fon.
=item summary_DE Steuert einige Funktionen von AVM's FRITZ!BOX, Fritz!Repeater und Fritz!Fon.

=begin html

<a name="CDCOpenData"></a>
<h3>CDCOpenData</h3>
<div>
<ul>
   The DWD provides values ​​for the amount of rain that has fallen per day, which are based on rain radar measurements and whose values ​​have been adjusted to the amounts measured by the weather station. The spatial resolution is 1 km, which makes the data interesting for those who do not have their own rainfall measurement available.
   <br>
   <br>

   <a name="CDCOpenDatadefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; CDCOpenData [&lt;name&gt;:]latitude,longitude&gt;</code>
      <br/>
      The parameters latitude,longitude define the location.<br>
      [&lt;name&gt;:] is an optional descriptive name for the location.<br>
      If the parameters are not specified, the location is determined from the global attributes latitude,longitude.<br>
      If these are not defined, the standard location 49.473067 6.3851 for Germany is used.<br>
      <br/><br/>
      Example: <code>define DWDRain CDCOpenData ....</code>
      <br/><br/>
   </ul>

   <a name="CDCOpenDataset"></a>
   <b>Set</b>
   <ul>

      <li><a name="update"></a>
         <dt><code>set &lt;name&gt; update</code></dt>
         <br>
         Starts an update of the data.
      </li><br>

      <li><a name="htmlBarAsStateFormat"></a>
         <dt><code>set &lt;name&gt; htmlBarAsStateFormat &lt;on|off&gt;</code></dt>
         <br>
         Defines an HTML bar to display the rain radar in the stateFormat attribute.<br>
         In order to persist the change, it must be saved by clicking on 'Save config'.<br>
         The generation function can also be used to define a weblink device.
         <dt><code>defmod &lt;barName&gt; weblink htmlCode {CDCOpenData_radar2html('&lt;nameCDCDevice&gt;', '&lt;readingName_rain_radar&gt;')}</code></dt>
      </li><br>

   </ul>

   <a name="CDCOpenDataget"></a>
   <b>Get</b>
   <ul>

      <li><a name="rainbyLatLongDate"></a>
         <dt><code>get &lt;name&gt; rainbyLatLongDate [latitude,longitude] [date]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Value-Latitude,Value-Longitude
         &lt;date&gt; Date formatted as yyyy-mm-dd
      </li><br>

      <li><a name="rainSinceMidnight"></a>
         <dt><code>get &lt;name&gt; rainSinceMidnight [latitude,longitude]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Value-Latitude,Value-Longitude
      </li><br>

      <li><a name="rainRadar"></a>
         <dt><code>get &lt;name&gt; rainRadar [latitude,longitude]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Value-Latitude,Value-Longitude
      </li><br>

   </ul>

   <a name="CDCOpenDataattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a name="INTERVAL"></a>
         <dt><code>INTERVAL &lt;seconds&gt;</code></dt>
         <br>
         Polling-Interval. Default is 300 (seconds). Smallest possible value is 60.
         If the attribut cronTime is set, INTERVAL will be deactivated.
      </li><br>

      <li><a name="verbose"></a>
        <dt><code>attr &lt;name&gt; verbose &lt;0 .. 5&gt;</code></dt>
        If verbose is set to the value 5, all log data will be saved in its own log file.<br>
        Log file name:deviceName_debugLog.dlog<br>
        In the INTERNAL Reading DEBUGLOG there is a link &lt;DEBUG log can be viewed here&gt; for direct viewing of the log.<br>
        Furthermore, a FileLog device:deviceName_debugLog is created in the same room and the same group as the CDCOpenData device.<br>
        If verbose is set to less than 5, the FileLog device is deleted and the log file is retained.
        If verbose is deleted, the FileLog device and the log file are deleted.
      </li><br>

      <li><a name="FhemLog3Std"></a>
        <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
        If set, the log information will be written in standard Fhem format.<br>
        If the output to a separate log file was activated by a verbose 5, this will be ended.<br>
        The separate log file and the associated FileLog device are deleted.<br>
        If the attribute is set to 0 or deleted and the device verbose is set to 5, all log data will be written to a separate log file.<br>
        Log file name: deviceName_debugLog.dlog<br>
        In the INTERNAL Reading DEBUGLOG there is a link &lt;DEBUG log can be viewed here&gt; for direct viewing of the log.<br>
      </li><br>

      <li><a name="clearRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; clearRadarFileLog &ltname of FileLog device&gt;</code></dt>
        If set, the FileLog of the FileLog Device will be emptied when the Regen Radar is updated.<br>
        Only makes sense for FileLogs that use the Regen Radar data for a graphic.<br>
      </li><br>

      <li><a name="RainRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; RainRadarFileLog &ltname of FileLog device&gt;</code></dt>
        If set, a FileLog device will be created.<br>
        The FileLog of the FileLog Device will be emptied when the Regen Radar is updated.<br>
        Only makes sense for FileLogs that use the Regen Radar data for a graphic.<br>
      </li><br>

      <li><a name="ownRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; ownRadarFileLog &lt0 | 1&gt;</code></dt>
        If set, a log file: deviceName_rainLog.log will be generated directly via the module.<br>
        The log file always only contains the current values.<br>
        Additionally, a FileLog device with the name deviceName_rainLog is created in the same room and the same group.<br>
      </li><br>

      <li><a name="cronTime"></a>
        <dt><code>attr &lt;name&gt; cronTime &lt;* * * * *&gt;</code></dt>
        CRON Expression. If set, then execution is controlled via the CRON expression.<br>
        Default is one hour. 			
      </li><br>

      <li><a name="enableDWDdata"></a>
         <dt><code>attr &lt;name&gt; enableDWDdata &lt;rainByDay, rainSinceMidnight, rainRadarbyLocation&gt;</code></dt>
         <br>
         Select which data will be collected periodically. In the standard setting, no data is fetched from the DWD.
      </li><br>

      <li><a name="locations"></a>
         <dt><code>attr &lt;name&gt; locations &lt;[name:]latitude,longitude&gt; [[name:]&lt;latitude,longitude&gt;] ...</code></dt>
         <br>
         Space-separated list of locations to be queried in addition to the default location.<br>
         &lt;name[:]&gt; is an optional descriptive name for the location.<br>
      </li><br>

      <li><a name="nonblockingTimeOut"></a>
         <dt><code>attr &lt;name&gt; nonblockingTimeOut &lt;50|75|100|125&gt;</code></dt>
         <br>
         Timeout for fetching data. Default is 55 (seconds).
      </li><br>

      <li><a name="numberOfDays"></a>
         <dt><code>attr &lt;name&gt; numberOfDays &lt;0..9&gt;</code></dt>
         <br>
         Number of days for which data *_day_rain is held as a reading. The standard is 5 readings.
      </li><br>

      <li><a name="updateOnStart"></a>
         <dt><code>attr &lt;name&gt; updateOnStart &lt;0 | 1gt;</code></dt>
         <br>
         If set and if choosen CRON Timer, the data will be fetched immediately after the definition or start of Fhem. Otherwise when the timer expires.
      </li><br>

   </ul>
   <br>

   <a name="CDCOpenDatareading"></a>
   <b>Readings</b>
   <br>
   <ul>
      The value -1 indicates an incorrect value on the part of the DWD.<br>
      <li>name | loc<i>0..n</i>_day_rain:timestamp - Rainfall of the location <i>name | n</i></li>
      <li>name | loc<i>0..n</i>_since_midnight:timestamp - Rainfall of the location <i>name | n</i></li>
      <li>name | loc<i>0..n</i>_rain_radar:timestamp - Rainfall of the location <i>name | n</i></li>
   </ul>
   <br>

</ul>
</div>

=end html

=begin html_DE

<a name="CDCOpenData"></a>
<h3>CDCOpenData</h3>
<div>
<ul>
   Der DWD stellt Werte der pro Tag gefallenen Regenmengen zur Verfügung, die auf Regenradar-Messungen beruhen und deren Werte an die gemessenen Mengen der Wetterstation angeeicht wurden. Die räumliche Auflösung beträgt dabei 1 km, was die Daten für diejenigen interessant macht, die keine eigene Regenmengenmessung zur Verfügung haben.
   <br>
   <br>

   <a name="CDCOpenDatadefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; CDCOpenData [&lt;name&gt;:]latitude,longitude&gt;</code>
      <br/>
      Die Parameter latitude,longitude definieren die Lokation.<br>
      [&lt;name&gt;:] ist ein optionaler sprechender Name für die Lokation.<br>
      Werden die Parameter nicht angegeben wird die Lokation aus den globalen Attribute latitude,longitude ermittelt.<br>
      Sind diese nicht definiert wird die Standardlokation 49.473067,6.3851 für Deutschland herangezogen.
      <br/><br/>
      Beispiel: <code>define DWDRegen CDCOpenData ...</code>
      <br/><br/>
   </ul>

   <a name="CDCOpenDataset"></a>
   <b>Set</b>
   <ul>

      <li><a name="update"></a>
         <dt><code>set &lt;name&gt; update</code></dt>
         <br>
         Startet eine Aktualisierung der Daten.
      </li><br>

      <li><a name="htmlBarAsStateFormat"></a>
         <dt><code>set &lt;name&gt; htmlBarAsStateFormat &lt;on|off&gt;</code></dt>
         <br>
         Definiert eine HTML Bar zur Anzeige des Regen Radars im Attribut stateFormat.<br>
         Um die Änderung zu persistieren muss sie durch klicken auf 'Save config' gesichert werden.<br>
         Die Funktion zur Generierung kann auch für die Defintion eines weblink Device genutzt werden.
         <dt><code>defmod &lt;barName&gt; weblink htmlCode {CDCOpenData_radar2html('&lt;nameCDCDevice&gt;', '&lt;readingName_rain_radar&gt;')}</code></dt>
      </li><br>

   </ul>

   <a name="CDCOpenDataget"></a>
   <b>Get</b>
   <ul>

      <li><a name="rainbyLatLongDate"></a>
         <dt><code>get &lt;name&gt; rainbyLatLongDate [latitude,longitude] [date]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Wert-Latitude,Wert-Longitude
         &lt;date&gt; Datum in der Formatierung yyyy-mm-dd
      </li><br>

      <li><a name="rainSinceMidnight"></a>
         <dt><code>get &lt;name&gt; rainSinceMidnight [latitude,longitude]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Wert-Latitude,Wert-Longitude
      </li><br>

      <li><a name="rainRadar"></a>
         <dt><code>get &lt;name&gt; rainRadar [latitude,longitude]</code></dt>
         <br>
         &lt;latitude,longitude&gt; Wert-Latitude,Wert-Longitude
      </li><br>

   </ul>

   <a name="CDCOpenDataattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a name="INTERVAL"></a>
         <dt><code>INTERVAL &lt;seconds&gt;</code></dt>
         <br>
         Abfrage-Interval. Standard ist 300 (Sekunden). Der kleinste m&ouml;gliche Wert ist 60.<br>
         Wird das Attribut cronTime gesetzt, dann ist INTERVAL deaktiviert.
      </li><br>

      <li><a name="verbose"></a>
        <dt><code>attr &lt;name&gt; verbose &lt;0 .. 5&gt;</code></dt>
        Wird verbose auf den Wert 5 gesetzt, so werden alle Log-Daten in eine eigene Log-Datei geschrieben.<br>
        Name der Log-Datei:deviceName_debugLog.dlog<br>
        Im INTERNAL Reading DEBUGLOG wird ein Link &lt;DEBUG Log kann hier eingesehen werden&gt; zur direkten Ansicht des Logs angezeigt.<br>
        Weiterhin wird ein FileLog Device:deviceName_debugLog im selben Raum und der selben Gruppe wie das CDCOpenData Device erzeugt.<br>
        Wird verbose auf kleiner 5 gesetzt, so wird das FileLog Device gelöscht, die Log-Datei bleibt erhalten.
        Wird verbose gelöscht, so werden das FileLog Device und die Log-Datei gelöscht.
      </li><br>

      <li><a name="FhemLog3Std"></a>
        <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
        Wenn gesetzt, werden die Log Informationen im Standard Fhem Format geschrieben.<br>
        Sofern durch ein verbose 5 die Ausgabe in eine seperate Log-Datei aktiviert wurde, wird diese beendet.<br>
        Die seperate Log-Datei und das zugehörige FileLog Device werden gelöscht.<br>
        Wird das Attribut auf 0 gesetzt oder gelöscht und ist das Device verbose auf 5 gesetzt, so werden alle Log-Daten in eine eigene Log-Datei geschrieben.<br>
        Name der Log-Datei:deviceName_debugLog.dlog<br>
        Im INTERNAL Reading DEBUGLOG wird ein Link &lt;DEBUG Log kann hier eingesehen werden&gt; zur direkten Ansicht des Logs angezeigt.<br>
      </li><br>

      <li><a name="clearRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; clearRadarFileLog &ltname of FileLog device&gt;</code></dt>
        Wenn gesetzt wird das FileLog des FileLog Device bei einem Update Regen Radar geleert.<br>
        Macht nur Sinn für FileLogs, die die Daten des Regen Radars für eine Grafik verwenden.<br>
      </li><br>

      <li><a name="RainRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; RainRadarFileLog &ltname of FileLog device&gt;</code></dt>
        Wenn gesetzt, wird ein FileLog Device angelegt.<br>
        Das FileLog des FileLog Device wird bei jedem Update Regen Radar geleert.<br>
        Macht nur Sinn für FileLogs, die die Daten des Regen Radars für eine Grafik verwenden.<br>
      </li><br>

      <li><a name="ownRadarFileLog"></a>
        <dt><code>attr &lt;name&gt; ownRadarFileLog &lt0 | 1&gt;</code></dt>
        Wenn gesetzt, wird eine Log Datei: deviceName_rainLog.log direkt über das Modul erzeugt.<br>
        Die Log Datei beinhaltet immer nur die aktuellen Werte.<br>
        Zusätzlich wird ein FileLog Device mit dem Namen deviceName_rainLog im selben Raum und der selben Gruppe erzeugt.<br>
      </li><br>

      <li><a name="cronTime"></a>
        <dt><code>attr &lt;name&gt; cronTime &lt;* * * * *&gt;</code></dt>
        CRON Regel. Wenn gesetzt, dann wird die Ausführung über diese Regel gesteuert.<br>
        Standard ist jede Stunde. 			
      </li><br>

      <li><a name="enableDWDdata"></a>
         <dt><code>attr &lt;name&gt; enableDWDdata &lt;rainByDay, rainSinceMidnight, rainRadarbyLocation&gt;</code></dt>
         <br>
         Anwählen, welche Daten periodisch abgeholt werden. In der Standardeinstellung werden keine Daten vom DWD abgeholt.
      </li><br>

      <li><a name="locations"></a>
         <dt><code>attr &lt;name&gt; locations &lt;[name:]latitude,longitude&gt; [[name:]&lt;latitude,longitude&gt;] ...</code></dt>
         <br>
         Durch Leerzeichen getrennte Liste von Lokationen, die zusätzlich zur Standard-Lokation abgefragt werden sollen.<br>
         &lt;name[:]&gt; ist ein optionaler sprechender Name für die Lokation.<br>
      </li><br>

      <li><a name="nonblockingTimeOut"></a>
         <dt><code>attr &lt;name&gt; nonblockingTimeOut &lt;50|75|100|125&gt;</code></dt>
         <br>
         Timeout f&uuml;r das regelm&auml;&szlig;ige Holen der Daten. Standard ist 55 (Sekunden).
      </li><br>

      <li><a name="numberOfDays"></a>
         <dt><code>attr &lt;name&gt; numberOfDays &lt;0..9&gt;</code></dt>
         <br>
         Anzahl der Tage, für die Daten *_day_rain als Reading vorgehalten werden. Standard sind 5 Readings.
      </li><br>

      <li><a name="updateOnStart"></a>
         <dt><code>attr &lt;name&gt; updateOnStart &lt;0 | 1&gt;</code></dt>
         <br>
         Wenn gesetzt und der CRON Timer ist aktiv, dann werden die Daten direkt nach der Definition oder Start von Fhem geholt. Ansonsten mit Ablauf des Timers.
      </li><br>

   </ul>
   <br>

   <a name="CDCOpenDatareading"></a>
   <b>Readings</b>
   <br>
   <ul>
      Der Wert -1 kennzeichnet einen fehlerhaften Wert seitens des DWD<br>
      <li>name | loc<i>0..n</i>_day_rain/nn - Regenmenge der Lokation <i>name | n</i></li>
      <li>name | loc<i>0..n</i>_since_midnight - Regenmenge der Lokation <i>name | n</i></li>
      <li>name | loc<i>0..n</i>_rain_radar/nn - Regenmenge der Lokation <i>name | n</i></li>
   </ul>
   <br>

</ul>
</div>
=end html_DE

=cut--
