########################################################################################################################
# $Id: 57_SSCal.pm 21776 2020-04-25 19:53:14Z DS_Starter $
#########################################################################################################################
#       57_SSCal.pm
#
#       (c) 2019 - 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module integrate the Synology Calendar into FHEM
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
# Definition: define <name> SSCal <ServerAddr> [ServerPort] [Protocol]
# 
# Example: define SynCal SSCal 192.168.2.20 [5000] [HTTP(S)]
#
package FHEM::SSCal;                                              ## no critic 'package'

use strict;                           
use warnings;
eval "use JSON;1;" or my $SSCalMM = "JSON";                       ## no critic 'eval' # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use GPUtils qw(GP_Import GP_Export);                              # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use MIME::Base64;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);
use HttpUtils;                                                    
use Encode;
use Blocking;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;                 ## no critic 'eval'
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AnalyzePerlCommand
          asyncOutput
          AttrVal
          BlockingCall
          BlockingKill
          CancelDelayedShutdown
          CommandSet
          CommandAttr
          CommandDelete
          CommandDefine
          CommandGet
          CommandSetReading
          CommandTrigger
          data
          defs
          devspec2array
          fhemTimeLocal
          FmtDateTime
          FmtTime
          FW_makeImage
          getKeyValue
          HttpUtils_NonblockingGet
          init_done
          InternalTimer
          IsDisabled
          Log3 
          modules
          readingFnAttributes          
          ReadingsVal
          RemoveInternalTimer
          readingsDelete 
          readingsBeginUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged 
          readingsEndUpdate
          readingsSingleUpdate
          ReadingsTimestamp           
          sortTopicNum
          setKeyValue
          TimeNow          
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
  "2.4.1"  => "20.05.2020  new function 'evalTimeAndWrite' ",
  "2.4.0"  => "19.05.2020  more changes according to PBP, switch to packages, fix cannot delete (and display in table) EventId of block 0 ",
  "2.3.0"  => "25.04.2020  set compatibility to Calendar package 2.3.4-0631, some changes according to PBP ",
  "2.2.3"  => "24.03.2020  minor code change ",
  "2.2.2"  => "08.03.2020  review commandref ",
  "2.2.1"  => "04.03.2020  expand composite event 'compositeBlockNumbers' by 'none' ",
  "2.2.0"  => "03.03.2020  new composite event 'compositeBlockNumbers' ",
  "2.1.0"  => "01.03.2020  expand composite Event, bugfix API if entry with 'is_all_day' and at first position in 'data' ",
  "2.0.0"  => "28.02.2020  check in release ",
  "1.15.0" => "27.02.2020  fix recurrence WEEKLY by DAY, MONTHLY by MONTHDAY and BYDAY, create commandref ",
  "1.14.0" => "23.02.2020  new setter \"calUpdate\" consistent for both models, calEventList and calToDoList are obsolete ",
  "1.13.0" => "22.02.2020  manage recurring entries if one/more of a series entry is deleted or changed and their reminder times ",
  "1.12.0" => "15.02.2020  create At-devices from calendar entries if FHEM-commands or Perl-routines detected in \"Summary\", minor fixes ", 
  "1.11.0" => "14.02.2020  new function doCompositeEvents to create Composite Events for special notify use in FHEM ",
  "1.10.0" => "13.02.2020  new key cellStyle for attribute tableSpecs, avoid FHEM crash when are design failures in tableSpecs ",
  "1.9.0"  => "11.02.2020  new reading Weekday with localization, more field selection for overview table ",
  "1.8.0"  => "09.02.2020  evaluate icons for DaysLeft, Map and State in sub evalTableSpecs , fix no table is shown after FHEM restart ",
  "1.7.0"  => "09.02.2020  respect global language setting for some presentation, new attributes tableSpecs & tableColumnMap, days left in overview ".
                           "formatting overview table, feature smallScreen for tableSpecs, rename attributes to tableFields, ".
                           "tableInDetail, tableInRoom, correct enddate/time if is_all_day incl. bugfix API, function boolean ".
                           "to avoid fhem crash if an older JSON module is installed ",
  "1.6.1"  => "03.02.2020  rename attributes to \"calOverviewInDetail\",\"calOverviewInRoom\", bugfix of gps extraction ",
  "1.6.0"  => "03.02.2020  new attribute \"tableFields\" to show specified fields in calendar overview in detail/room view, ".
                           "Model Diary/Tasks defined, periodic call of ToDo-Liists now possible ",
  "1.5.0"  => "02.02.2020  new attribute \"calOverviewInDetail\",\"calOverviewInRoom\" to control calendar overview in room or detail view ",
  "1.4.0"  => "02.02.2020  get calAsHtml command or use sub calAsHtml(\$name) ",
  "1.3.1"  => "01.02.2020  add errauthlist hash for login/logout API error codes ",
  "1.3.0"  => "01.02.2020  new command \"cleanCompleteTasks\" to delete completed tasks, \"deleteEventId\" to delete an event id, ".
                           "new get command \"apiInfo\" - detect and show API info, avoid empty readings ",
  "1.2.0"  => "29.01.2020  get tasks from calendar with set command 'calToDoList' ",
  "1.1.14" => "29.01.2020  ignore calendars of type ne 'Event' for set calEventList ",
  "1.1.13" => "20.01.2020  change save and read credentials routine ",
  "1.1.12" => "19.01.2020  add attribute interval, automatic event fetch ",
  "1.1.11" => "18.01.2020  status information added: upcoming, alarmed, started, ended ",
  "1.1.10" => "17.01.2020  attribute asyncMode for parsing events in BlockingCall, some fixes ",
  "1.1.9"  => "14.01.2020  preparation of asynchronous calendar event extraction, some fixes ",
  "1.1.8"  => "13.01.2020  can proces WEEKLY general recurring events, use \$data{SSCal}{\$name}{eventlist} as Hash of Events ",
  "1.1.7"  => "12.01.2020  can proces WEEKLY recurring events BYDAY ",
  "1.1.6"  => "11.01.2020  can proces DAILY recurring events ",
  "1.1.5"  => "10.01.2020  can proces MONTHLY recurring events BYDAY ",
  "1.1.4"  => "07.01.2020  can proces MONTHLY recurring events BYMONTHDAY ",
  "1.1.3"  => "06.01.2020  can proces YEARLY recurring events ",
  "1.1.2"  => "04.01.2020  logout if new credentials are set ",
  "1.1.1"  => "03.01.2020  add array of 'evt_notify_setting' ",
  "1.1.0"  => "01.01.2020  logout command ",
  "1.0.0"  => "18.12.2019  initial "
);

# Versions History extern
my %vNotesExtern = (
  "2.3.0"  => "25.04.2020  The module compatibility is set to Synology Calendar package 2.3.4-0631. ",
  "1.0.0"  => "18.12.2019  initial "
);

# Hints EN
my %vHintsExt_en = (
  "1" => "The module implements the Internet Calendaring and Scheduling Core Object Specification (iCalendar) ".
         "according to <a href=\"https://tools.ietf.org/html/rfc5545\">RFC5545</a>. "
);

# Hints DE
my %vHintsExt_de = (
  "1" => "Das Modul implementiert die Internet Calendaring and Scheduling Core Object Specification (iCalendar) ".
         "gemäß <a href=\"https://tools.ietf.org/html/rfc5545\">RFC5545</a>. "
);

# Aufbau Errorcode-Hashes
my %errauthlist = (
  400 => "No such account or the password is incorrect",
  401 => "Account disabled",
  402 => "Permission denied",
  403 => "2-step verification code required",
  404 => "Failed to authenticate 2-step verification code",
);

my %errlist = (
  100 => "Unknown error",
  101 => "No parameter of API, method or version",
  102 => "The requested API does not exist - may be the Synology Calendar package is stopped",
  103 => "The requested method does not exist",
  104 => "The requested version does not support the functionality",
  105 => "The logged in session does not have permission",
  106 => "Session timeout",
  107 => "Session interrupted by duplicate login",
  114 => "Missing required parameters",
  117 => "Unknown internal error",
  119 => "session id not valid",
  120 => "Invalid parameter",
  160 => "Insufficient application privilege",
  400 => "Invalid parameter of file operation",
  401 => "Unknown error of file operation",
  402 => "System is too busy",
  403 => "The user does not have permission to execute this operation",
  404 => "The group does not have permission to execute this operation",
  405 => "The user/group does not have permission to execute this operation",
  406 => "Cannot obtain user/group information from the account server",
  407 => "Operation not permitted",
  408 => "No such file or directory",
  409 => "File system not supported",
  410 => "Failed to connect internet-based file system (ex: CIFS)",
  411 => "Read-only file system",
  412 => "Filename too long in the non-encrypted file system",
  413 => "Filename too long in the encrypted file system",
  414 => "File already exists",
  415 => "Disk quota exceeded",
  416 => "No space left on device",
  417 => "Input/output error",
  418 => "Illegal name or path",
  419 => "Illegal file name",
  420 => "Illegal file name on FAT file system",
  421 => "Device or resource busy",
  599 => "No such task of the file operation",
  800 => "malformed or unsupported URL",
  805 => "empty API data received - may be the Synology cal Server package is stopped",
  806 => "couldn't get Synology cal API information",
  810 => "The credentials couldn't be retrieved",
  900 => "malformed JSON string received from Synology Calendar Server",
  910 => "Wrong timestamp definition. Check attributes \"cutOlderDays\", \"cutLaterDays\". ",
);

################################################################
sub Initialize {
 my ($hash) = @_;
 $hash->{DefFn}                 = \&Define;
 $hash->{UndefFn}               = \&Undef;
 $hash->{DeleteFn}              = \&Delete; 
 $hash->{SetFn}                 = \&Set;
 $hash->{GetFn}                 = \&Get;
 $hash->{AttrFn}                = \&Attr;
 $hash->{DelayedShutdownFn}     = \&DelayedShutdown;
 
 # Darstellung FHEMWEB
 # $hash->{FW_summaryFn}        = \&FWsummaryFn;
 $hash->{FW_addDetailToSummary} = 1 ;                       # zusaetzlich zu der Device-Summary auch eine Neue mit dem Inhalt von DetailFn angezeigt             
 $hash->{FW_detailFn}           = \&FWdetailFn;
 $hash->{FW_deviceOverview}     = 1;
 
 $hash->{AttrList} = "asyncMode:1,0 ".  
                     "createATDevs:1,0 ".
                     "cutOlderDays ".
                     "cutLaterDays ".
                     "disable:1,0 ".
                     "tableSpecs:textField-long ".
                     "filterCompleteTask:1,2,3 ".
                     "filterDueTask:1,2,3 ".
                     "interval ".
                     "loginRetries:1,2,3,4,5,6,7,8,9,10 ". 
                     "tableColumnMap:icon,data,text ".                   
                     "showRepeatEvent:true,false ".
                     "showPassInLog:1,0 ".
                     "tableInDetail:0,1 ".
                     "tableInRoom:0,1 ".
                     "tableFields:multiple-strict,Symbol,Begin,End,DaysLeft,DaysLeftLong,Weekday,Timezone,Summary,Description,Status,Completion,Location,Map,Calendar,EventId ".
                     "timeout ".
                     "usedCalendars:--wait#for#Calendar#list-- ".
                     $readingFnAttributes;   
         
 FHEM::Meta::InitMod( __FILE__, $hash ) if(!$modMetaAbsent);  # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
# define SyncalBot SSCal 192.168.2.10 [5000] [HTTP(S)] 
#                   [1]      [2]        [3]      [4]  
#
################################################################
sub Define {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SSCalMM." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SSCalMM);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
      return "You need to specify more parameters.\n". "Format: define <name> SSCal <ServerAddress> [Port] [HTTP(S)] [Tasks]";
  }
  
  shift @a; shift @a;

  my $addr = ($a[0] && $a[0] ne "Tasks") ? $a[0]     : "";
  my $port = ($a[1] && $a[1] ne "Tasks") ? $a[1]     : 5000;
  my $prot = ($a[2] && $a[2] ne "Tasks") ? lc($a[2]) : "http";
  
  my $model = "Diary";
  $model    = "Tasks" if( grep {$_ eq "Tasks"} @a );
  
  $hash->{ADDR}                  = $addr;
  $hash->{PORT}                  = $port;
  $hash->{MODEL}                 = "Calendar"; 
  $hash->{PROT}                  = $prot;
  $hash->{MODEL}                 = $model;
  $hash->{RESEND}                = "next planned SendQueue start: immediately by next entry";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                                # Modul Meta.pm nicht vorhanden  
  $hash->{HELPER}{CALFETCHED}    = 0;                                                                   # vorhandene Kalender sind noch nicht abgerufen
  $hash->{HELPER}{APIPARSET}     = 0;                                                                   # es sind keine API Informationen gesetzt -> neu abrufen
  
  CommandAttr(undef,"$name room SSCal");
  CommandAttr(undef,"$name event-on-update-reading .*Summary,state");
  
  $data{SSCal}{$name}{calapi} = {                                                     # in Define um unterschiedliche DSM mit div. Versionen zu ermöglichen
                                 "APIINFO"   => { "NAME" => "SYNO.API.Info"    },     # Info-Seite für alle API's, einzige statische Seite !                                                    
                                 "APIAUTH"   => { "NAME" => "SYNO.API.Auth"    },     # API used to perform session login and logout  
                                 "CALCAL"    => { "NAME" => "SYNO.Cal.Cal"     },     # API to manipulate calendar
                                 "CALEVENT"  => { "NAME" => "SYNO.Cal.Event"   },     # Provide methods to manipulate events in the specific calendar
                                 "CALSHARE"  => { "NAME" => "SYNO.Cal.Sharing" },     # Get/set sharing setting of calendar
                                 "CALTODO"   => { "NAME" => "SYNO.Cal.Todo"    },     # Provide methods to manipulate events in the specific calendar
                                };

  # Versionsinformationen setzen
  setVersionInfo($hash);
  
  # Credentials lesen
  getcredentials($hash,1,"credentials");
  
  # Index der Sendequeue initialisieren
  $data{SSCal}{$name}{sendqueue}{index} = 0;
    
  readingsBeginUpdate         ($hash);
  readingsBulkUpdateIfChanged ($hash, "Errorcode"  , "none");
  readingsBulkUpdateIfChanged ($hash, "Error"      , "none");   
  readingsBulkUpdateIfChanged ($hash, "QueueLength", 0);                     # Länge Sendqueue initialisieren
  readingsBulkUpdate          ($hash, "nextUpdate" , "Manual");              # Abrufmode initial auf "Manual" setzen   
  readingsBulkUpdate          ($hash, "state"      , "Initialized");         # Init state
  readingsEndUpdate           ($hash,1);              

  # initiale Routinen nach Start ausführen , verzögerter zufälliger Start
  initOnBoot($name);

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
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  BlockingKill($hash->{HELPER}{RUNNING_PID}) if($hash->{HELPER}{RUNNING_PID});
  delete $data{SSCal}{$name};
  RemoveInternalTimer($name);
   
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
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  if($hash->{HELPER}{SID}) {
      logout($hash);                      # Session alter User beenden falls vorhanden  
      return 1;
  }
  
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
  my ($hash, $arg) = @_;
  my $name  = $hash->{NAME};
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
  
  # gespeicherte Credentials löschen
  setKeyValue($index, undef);
    
return;
}

################################################################
sub Attr {                                                  ## no critic 'complexity'
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash  = $defs{$name};
    my $model = $hash->{MODEL};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($cmd eq "set") {
        
        if ($aName =~ /filterCompleteTask|filterDueTask/x && $model ne "Tasks") {            
            return qq{The attribute "$aName" is only valid for devices of MODEL "Tasks" ! Please set this attribute in a device of this MODEL.};
        }
        
        if ($aName =~ /showRepeatEvent/x && $model ne "Diary") {            
            return qq{The attribute "$aName" is only valid for devices of MODEL "Diary" ! Please set this attribute in a device of this MODEL.};
        }
        
        if ($aName =~ /tableSpecs/x) {            
            return qq{The attribute "$aName" has wrong syntax. The value must be set into "{ }".} if($aVal !~ m/^\s*?\{.*\}\s*?$/xs);
        }
        
        my $attrVal = $aVal;
        
        if ($attrVal =~ m/^\{.*\}$/xs && $attrVal =~ m/=>/x) {
            $attrVal =~ s/\@/\\\@/gx;
            $attrVal =~ s/\$/\\\$/gx;
            
            my $av = eval $attrVal;                                       ## no critic 'eval'
            if($@) {
                Log3($name, 2, "$name - Error while evaluate: ".$@);
                return $@; 
            } else {
                $attrVal = $av if(ref($av) eq "HASH");
            }
        }
        $hash->{HELPER}{$aName} = $attrVal;         
    } else {
        delete $hash->{HELPER}{$aName};
    }
       
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = $aVal?1:0;
        }
        $do  = 0 if($cmd eq "del");
        
        $val = ($do == 1 ? "disabled" : "initialized");
        
        if ($do == 1) {
            RemoveInternalTimer($name);
        } else {
            InternalTimer(gettimeofday()+2, "FHEM::SSCal::initOnBoot", $name, 0) if($init_done); 
        }
    
        readingsBeginUpdate($hash); 
        readingsBulkUpdate ($hash, "state", $val);                    
        readingsEndUpdate  ($hash,1); 
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/timeout|cutLaterDays|cutOlderDays|interval/x) {
            unless ($aVal =~ /^\d+$/x) { return qq{The value of $aName is not valid. Use only integers 1-9 !}; }
        }     
        if($aName =~ m/interval/x) {
            RemoveInternalTimer($name,"FHEM::SSCal::periodicCall");
            if($aVal > 0) {
                InternalTimer(gettimeofday()+1.0, "FHEM::SSCal::periodicCall", $name, 0);
            }
        }      
    }
    
return;
}

################################################################
sub Set {                                                    ## no critic 'complexity'
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my $prop2   = $a[4];
  my $prop3   = $a[5];
  my $model   = $hash->{MODEL};
  
  my ($success,$setlist);
        
  return if(IsDisabled($name));
  
  my $idxlist = join(",", sort keys %{$data{SSCal}{$name}{sendqueue}{entries}});
  
  # alle aktuell angezeigten Event Id's  ermitteln
  my (@idarray,$evids);
  for my $key (keys %{$defs{$name}{READINGS}}) {
      next if $key !~ /_EventId$/x;
      push (@idarray, $defs{$name}{READINGS}{$key}{VAL});   
  }
  
  if(@idarray) {
      my %seen;
      my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @idarray;                # distinct / unique the keys
      $evids     = join(",", @unique);
  }
  
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials "
                 ;  
  } elsif ($model eq "Diary") {                                                 # Model Terminkalender
      $setlist = "Unknown argument $opt, choose one of ".
                 "calUpdate ".
                 "credentials ".
                 ($evids?"deleteEventId:$evids ":"deleteEventId:noArg ").
                 "eraseReadings:noArg ".
                 "listSendqueue:noArg ".
                 "logout:noArg ".
                 ($idxlist?"purgeSendqueue:-all-,-permError-,$idxlist ":"purgeSendqueue:-all-,-permError- ").
                 "restartSendqueue:noArg "
                 ;
  } else {                                                                      # Model Aufgabenliste
      $setlist = "Unknown argument $opt, choose one of ".
                 "calUpdate ".
                 "cleanCompleteTasks:noArg ".
                 "credentials ".
                 ($evids?"deleteEventId:$evids ":"deleteEventId:noArg ").
                 "eraseReadings:noArg ".
                 "listSendqueue:noArg ".
                 "logout:noArg ".
                 ($idxlist?"purgeSendqueue:-all-,-permError-,$idxlist ":"purgeSendqueue:-all-,-permError- ").
                 "restartSendqueue:noArg "
                 ;
  }
 
  if ($opt eq "credentials") {                                           ## no critic 'Cascading'
      return "The command \"$opt\" needs an argument." if (!$prop); 
      logout($hash) if($hash->{HELPER}{SID});                      # Session alter User beenden falls vorhanden      
      ($success) = setcredentials($hash,$prop,$prop1);
      
      if($success) {
          addQueue($name,"listcal","CALCAL","list","&is_todo=true&is_evt=true");            
          getApiSites($name);
          return "credentials saved successfully";
      } else {
          return "Error while saving credentials - see logfile for details";
      }
      
  } elsif ($opt eq "listSendqueue") {
      my $sub = sub { 
          my ($idx) = @_;
          my $ret;          
          for my $key (reverse sort keys %{$data{SSCal}{$name}{sendqueue}{entries}{$idx}}) {
              $ret .= ", " if($ret);
              $ret .= $key."=>".$data{SSCal}{$name}{sendqueue}{entries}{$idx}{$key};
          }
          return $ret;
      };
        
      if (!keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
          return "SendQueue is empty.";
      }
      my $sq;
      for my $idx (sort{$a<=>$b} keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
          $sq .= $idx." => ".$sub->($idx)."\n";             
      }
      return $sq;
  
  } elsif ($opt eq "purgeSendqueue") {
      if($prop eq "-all-") {
          delete $hash->{OPIDX};
          delete $data{SSCal}{$name}{sendqueue}{entries};
          $data{SSCal}{$name}{sendqueue}{index} = 0;
          return "All entries of SendQueue are deleted";
      } elsif($prop eq "-permError-") {
          for my $idx (keys %{$data{SSCal}{$name}{sendqueue}{entries}}) { 
              delete $data{SSCal}{$name}{sendqueue}{entries}{$idx} 
                  if($data{SSCal}{$name}{sendqueue}{entries}{$idx}{forbidSend});            
          }
          return "All entries with state \"permanent send error\" are deleted";
      } else {
          delete $data{SSCal}{$name}{sendqueue}{entries}{$prop};
          return "SendQueue entry with index \"$prop\" deleted";
      }
  
  } elsif ($opt eq "calUpdate") {                                                             # Termine einer Cal_id (Liste) in Zeitgrenzen abrufen
      return "Obtain the Calendar list first with \"get $name getCalendars\" command." if(!$hash->{HELPER}{CALFETCHED});

      my $cals = AttrVal($name,"usedCalendars", "");
      shift @a; shift @a;
      my $c    = join(" ", @a);
      $cals    = $c ? $c : $cals;
      return "Please set attribute \"usedCalendars\" or specify the Calendar(s) you want read in \"$opt\" command." if(!$cals);
      
      # Kalender aufsplitten und zu jedem die ID ermitteln
      my @ca = split(",", $cals);
      my ($oids,$caltype,@cas);
      if($model eq "Diary") { $caltype = "Event"; } else { $caltype = "ToDo"; }
      for my $cal (@ca) {                                         
          my $oid = $hash->{HELPER}{CALENDARS}{"$cal"}{id};
          next if(!$oid);
          if ($hash->{HELPER}{CALENDARS}{"$cal"}{type} ne $caltype) {
              Log3($name, 3, "$name - The Calendar \"$cal\" is not of type \"$caltype\" and will be ignored.");
              next;
          }          
          $oids .= "," if($oids);
          $oids .= '"'.$oid.'"';
          push (@cas, $cal);
          Log3($name, 2, "$name - WARNING - The Calendar \"$cal\" seems to be unknown because its ID couldn't be found.") if(!$oid);
      }
      return "No Calendar of type \"$caltype\" was selected or its ID(s) couldn't be found." if(!$oids); 

      Log3($name, 5, "$name - Calendar selection for add queue: ".join(',', @cas));

      if($model eq "Diary") {                                                 # Modell Terminkalender
          my ($err,$tstart,$tend) = timeEdge ($name);
          if($err) {
              Log3($name, 2, "$name - ERROR in timestamp: $err");
            
              my $errorcode = "910";

              readingsBeginUpdate         ($hash); 
              readingsBulkUpdateIfChanged ($hash, "Error",           $err);
              readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
              readingsBulkUpdate          ($hash, "state",        "Error");                    
              readingsEndUpdate           ($hash,1);

              return "ERROR in timestamp: $err";          
          }   

          my $lr = AttrVal($name,"showRepeatEvent", "true");
          addQueue($name,"eventlist","CALEVENT","list","&cal_id_list=[$oids]&start=$tstart&end=$tend&list_repeat=$lr"); 
          getApiSites($name);      
      
      } else {                                                                # Modell Aufgabenliste
          my $limit          = "";                                            # Limit of matched tasks
          my $offset         = 0;                                             # offset of mnatched tasks
          my $filterdue      = AttrVal($name,"filterDueTask", 3);             # show tasks with and without due time
          my $filtercomplete = AttrVal($name,"filterCompleteTask", 3);        # show completed and not completed tasks
          
          addQueue($name,"todolist","CALTODO","list","&cal_id_list=[$oids]&limit=$limit&offset=$offset&filter_due=$filterdue&filter_complete=$filtercomplete"); 
          getApiSites($name);      
      }
  
  } elsif ($opt eq "cleanCompleteTasks") {                                                          # erledigte Aufgaben einer Cal_id (Liste) löschen     
      return "Obtain the Calendar list first with \"get $name getCalendars\" command." if(!$hash->{HELPER}{CALFETCHED});  
      
      my $cals = AttrVal($name,"usedCalendars", "");
      
      shift @a; shift @a;
      my $c = join(" ", @a);
      $cals = $c ? $c : $cals;
      return "Please set attribute \"usedCalendars\" or specify the Calendar(s) you want read in \"$opt\" command." if(!$cals);
      
      # Kalender aufsplitten und zu jedem die ID ermitteln
      my @ca = split(",", $cals);
      my $oids;
      for my $cal (@ca) {                                         
          my $oid = $hash->{HELPER}{CALENDARS}{"$cal"}{id};
          next if(!$oid);
          if ($hash->{HELPER}{CALENDARS}{"$cal"}{type} ne "ToDo") {
              Log3($name, 3, "$name - The Calendar \"$cal\" is not of type \"ToDo\" and will be ignored.");
              next;
          }          
          $oids .= "," if($oids);
          $oids .= '"'.$oid.'"';
          Log3($name, 2, "$name - WARNING - The Calendar \"$cal\" seems to be unknown because its ID couldn't be found.") if(!$oid);
      }
      
      return "No Calendar of type \"ToDo\" was selected or its ID(s) couldn't be found." if(!$oids);
      
      Log3($name, 5, "$name - Calendar selection for add queue: $cals");
      
      # <Name, operation mode, API (siehe $data{SSCal}{$name}{calapi}), auszuführende API-Methode, spezifische API-Parameter>
      addQueue($name,"cleanCompleteTasks","CALTODO","clean_complete","&cal_id_list=[$oids]"); 
      getApiSites($name);
  
  } elsif ($opt eq "deleteEventId") {
      return "You must specify an event id (Reading EventId) what is to be deleted." if(!$prop);
      
      my $eventid = $prop;
      
      # Blocknummer ermitteln
      my $bnr;
      my @allrds = keys%{$defs{$name}{READINGS}};
      for my $key(@allrds) {
          next if $key !~ /_EventId$/x;
          $bnr = (split("_", $key))[0] if($defs{$name}{READINGS}{$key}{VAL} == $eventid);   # Blocknummer ermittelt 
      }
      
      return "The blocknumber of specified event id could not be identified. Make sure you have specified a valid event id." if(!defined $bnr);

      # die Summary zur Event Id ermitteln
      my $sum = ReadingsVal($name, $bnr."_01_Summary", "");

      # Kalendername und dessen id und Typ ermitteln 
      my $calname = ReadingsVal($name, $bnr."_90_calName", "");
      my $calid   = $hash->{HELPER}{CALENDARS}{"$calname"}{id};
      my $caltype = $hash->{HELPER}{CALENDARS}{"$calname"}{type};
      
      # Kalender-API in Abhängigkeit des Kalendertyps wählen
      my $api = ($caltype eq "Event")?"CALEVENT":"CALTODO";
      
      Log3($name, 3, "$name - The event \"$sum\" with id \"$eventid\" will be deleted in calendar \"$calname\".");
      
      # <Name, operation mode, API (siehe $data{SSCal}{$name}{calapi}), auszuführende API-Methode, spezifische API-Parameter>
      addQueue($name,"deleteEventId",$api,"delete","&evt_id=$eventid"); 
      getApiSites($name);      
  
  } elsif ($opt eq "restartSendqueue") {
      my $ret = getApiSites($name);
      if($ret) {
          return $ret;
      } else {
          return "The SendQueue has been restarted.";
      }
      
  } elsif ($opt eq 'eraseReadings') {       
        delReadings($name,0);                                                    # Readings löschen
    
  } elsif ($opt eq 'logout') {      
        logout($hash);                                     
    
  } else {
      return "$setlist"; 
  }
  
return;
}

################################################################
sub Get {                                                                       ## no critic 'complexity'
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt  = shift @a;
    my $arg  = shift @a;
    my $arg1 = shift @a;
    my $arg2 = shift @a;
    my $ret = "";
    my $getlist;

    if(!$hash->{CREDENTIALS}) {
        return;
        
    } else {
        $getlist = "Unknown argument $opt, choose one of ".
                   "apiInfo:noArg ".
                   "calAsHtml:noArg ".
                   "getCalendars:noArg ".
                   "storedCredentials:noArg ".
                   "versionNotes " 
                   ;
    }
          
    return if(IsDisabled($name));             
              
    if ($opt eq "storedCredentials") {                                                ## no critic 'Cascading'
        if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials <CREDENTIALS>\"";}
        # Credentials abrufen
        my ($success, $username, $passwd) = getcredentials($hash,0,"credentials");
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        
        return "Stored Credentials:\n".
               "===================\n".
               "Username: $username, Password: $passwd \n"
               ;   
    
    } elsif ($opt eq "apiInfo") {                                                         # Liste aller Kalender abrufen
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
        getclhash($hash,1);
        $hash->{HELPER}{APIPARSET} = 0;                                                   # Abruf API Infos erzwingen

        # <Name, operation mode, API (siehe $data{SSCal}{$name}{calapi}), auszuführende API-Methode, spezifische API-Parameter>
        addQueue($name,"apiInfo","","","");            
        getApiSites($name);
  
    } elsif ($opt eq "getCalendars") {                                                    # Liste aller Kalender abrufen
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
        getclhash($hash,1);
        
        addQueue($name,"listcal","CALCAL","list","&is_todo=true&is_evt=true");            
        getApiSites($name);
  
    } elsif ($opt eq "calAsHtml") {                                                    
        my $out = calAsHtml($name);
        return $out;
  
    } elsif ($opt =~ /versionNotes/x) {
        my $header  = "<b>Module release information</b><br>";
        my $header1 = "<b>Helpful hints</b><br>";
        my %hs;
      
        # Ausgabetabelle erstellen
        my ($val0,$val1);
        my $i = 0;
      
        $ret  = "<html>";
      
        # Hints
        if(!$arg || $arg =~ /hints/x || $arg =~ /[\d]+/x) {
            $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
            $ret .= "<table class=\"block wide internals\">";
            $ret .= "<tbody>";
            $ret .= "<tr class=\"even\">";  
            if($arg && $arg =~ /[\d]+/x) {
                my @hints = split(",",$arg);
                for (@hints) {
                    if(AttrVal("global","language","EN") eq "DE") {
                        $hs{$_} = $vHintsExt_de{$_};
                    } else {
                        $hs{$_} = $vHintsExt_en{$_};
                    }
                }                      
            } else {
                if(AttrVal("global","language","EN") eq "DE") {
                    %hs = %vHintsExt_de;
                } else {
                    %hs = %vHintsExt_en; 
                }
            }          
            $i = 0;
            for my $key (sortTopicNum("desc",keys %hs)) {
                $val0 = $hs{$key};
                $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
                $ret .= "</tr>";
                $i++;
                if ($i & 1) {
                    # $i ist ungerade
                    $ret .= "<tr class=\"odd\">";
                } else {
                    $ret .= "<tr class=\"even\">";
                }
            }
            $ret .= "</tr>";
            $ret .= "</tbody>";
            $ret .= "</table>";
            $ret .= "</div>";
        }
      
        # Notes
        if(!$arg || $arg =~ /rel/x) {
            $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
            $ret .= "<table class=\"block wide internals\">";
            $ret .= "<tbody>";
            $ret .= "<tr class=\"even\">";
            $i = 0;
            for my $key (sortTopicNum("desc",keys %vNotesExtern)) {
                ($val0,$val1) = split(/\s/x,$vNotesExtern{$key},2);
                $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
                $ret .= "</tr>";
                $i++;
                if ($i & 1) {
                    # $i ist ungerade
                    $ret .= "<tr class=\"odd\">";
                } else {
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
  
    } else {
        return "$getlist";
    }

return $ret;                                                        # not generate trigger out of command
}

######################################################################################
#                 Kalenderübersicht in Detailanzeige darstellen 
######################################################################################
sub FWdetailFn {
  my ($FW_wname, $d, $room, $pageHash) = @_;           
  my $hash = $defs{$d};
  my $ret  = "";
  
  $hash->{".calhtml"} = FHEM::SSCal::calAsHtml($d,$FW_wname);

  if($hash->{".calhtml"} ne "" && !$room && AttrVal($d,"tableInDetail",1)) {    # Anzeige Übersicht in Detailansicht
      $ret .= $hash->{".calhtml"};
      return $ret;
  } 
  
  if($hash->{".calhtml"} ne "" && $room && AttrVal($d,"tableInRoom",1)) {       # Anzeige in Raumansicht zusätzlich zur Statuszeile
      $ret = $hash->{".calhtml"};
      return $ret;
  }

return;
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub initOnBoot {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my ($ret);
  
  RemoveInternalTimer($name, "FHEM::SSCal::initOnBoot");
  
  if ($init_done) {
      CommandGet(undef, "$name getCalendars");                      # Kalender Liste initial abrufen     
  } else {
      InternalTimer(gettimeofday()+3, "FHEM::SSCal::initOnBoot", $name, 0);
  }
  
return;
}

#############################################################################################
#      regelmäßiger Intervallabruf
#############################################################################################
sub periodicCall {
  my ($name)   = @_;
  my $hash     = $defs{$name};
  my $interval = AttrVal($name, "interval", 0);
  my $model    = $hash->{MODEL};
  my $new;
   
  if(!$interval) {
      $hash->{MODE} = "Manual";
  } else {
      $new = gettimeofday()+$interval;
      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "nextUpdate", "Automatic - next polltime: ".FmtTime($new));     # Abrufmode initial auf "Manual" setzen   
      readingsEndUpdate   ($hash,1);
  }
  
  RemoveInternalTimer($name,"FHEM::SSCal::periodicCall");
  return if(!$interval);
  
  if($hash->{CREDENTIALS} && !IsDisabled($name)) {
      CommandSet(undef, "$name calUpdate");                                                       # Einträge aller gewählter Kalender oder Aufgabenlisten abrufen (in Queue stellen)
  }
  
  InternalTimer($new, "FHEM::SSCal::periodicCall", $name, 0);
    
return;  
}

######################################################################################
#                            Eintrag zur SendQueue hinzufügen
#    $name   = Name Kalenderdevice
#    $opmode = operation mode
#    $api    = API (siehe $data{SSCal}{$name}{calapi})
#    $method = auszuführende API-Methode 
#    $params = spezifische API-Parameter 
#
######################################################################################
sub addQueue {
   my ($name,$opmode,$api,$method,$params) = @_;
   my $hash                = $defs{$name};
   
   $data{SSCal}{$name}{sendqueue}{index}++;
   my $index = $data{SSCal}{$name}{sendqueue}{index};
   
   Log3($name, 5, "$name - Add sendItem to queue - Idx: $index, Opmode: $opmode, API: $api, Method: $method, Params: $params");
   
   my $pars = {'opmode'     => $opmode, 
               'api'        => $api,   
               'method'     => $method, 
               'params'     => $params,
               'retryCount' => 0               
              };
                      
   $data{SSCal}{$name}{sendqueue}{entries}{$index} = $pars;  

   updQLength ($hash);                        # updaten Länge der Sendequeue     
   
return;
}


#############################################################################################
#              Erfolg einer Rückkehrroutine checken und ggf. Send-Retry ausführen
#              bzw. den SendQueue-Eintrag bei Erfolg löschen
#              $name  = Name des calbot-Devices
#              $retry = 0 -> Opmode erfolgreich (DS löschen), 
#                       1 -> Opmode nicht erfolgreich (Abarbeitung nach ckeck errorcode
#                            eventuell verzögert wiederholen)
#############################################################################################
sub checkRetry {  
  my ($name,$retry) = @_;
  my $hash          = $defs{$name};  
  my $idx           = $hash->{OPIDX};
  my $forbidSend    = "";
  
  if(!keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
      Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
      updQLength ($hash);
      return;  
  } 
  
  if(!$retry) {                                                     # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{SSCal}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, "$name - Opmode \"$hash->{OPMODE}\" finished successfully, Sendqueue index \"$idx\" deleted.");
      updQLength ($hash);
      return getApiSites($name);                                    # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer)
  
  } else {                                                          # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{SSCal}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{retryCount};
  
      my $errorcode = ReadingsVal($name, "Errorcode", 0);
      if($errorcode =~ /119/x) {
          delete $hash->{HELPER}{SID};
      }
      if($errorcode =~ /100|101|103|117|120|407|409|800|900/x) {        # bei diesen Errorcodes den Queueeintrag nicht wiederholen, da dauerhafter Fehler !
          $forbidSend = experror($hash,$errorcode);                     # Fehlertext zum Errorcode ermitteln
          $data{SSCal}{$name}{sendqueue}{entries}{$idx}{forbidSend} = $forbidSend;
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. It seems to be a permanent error. Exclude it from new send attempt !");
          
          delete $hash->{OPIDX};
          delete $hash->{OPMODE};
          
          updQLength ($hash);                                 # updaten Länge der Sendequeue
          
          return getApiSites($name);                          # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer);
      }
      
      if(!$forbidSend) {
          my $rs = 0;
          if($rc <= 1) {
              $rs = 5;
          } elsif ($rc < 3) {
              $rs = 20;
          } elsif ($rc < 5) {
              $rs = 60;
          } elsif ($rc < 7) {
              $rs = 1800;
          } elsif ($rc < 30) {
              $rs = 3600;
          } else {
              $rs = 86400;
          }
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. Restart SendQueue in $rs seconds (retryCount $rc).");
          
          my $rst = gettimeofday()+$rs;                            # resend Timer 
          updQLength ($hash,$rst);                           # updaten Länge der Sendequeue mit resend Timer
          
          RemoveInternalTimer($name, "FHEM::SSCal::getApiSites");
          InternalTimer($rst, "FHEM::SSCal::getApiSites", "$name", 0);
      }
  }

return;
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub getApiSites {
   my ($name)     = @_;
   my $hash       = $defs{$name};
   my $addr       = $hash->{ADDR};
   my $port       = $hash->{PORT};
   my $prot       = $hash->{PROT};  
   my ($url,$param,$idxset,$ret);
   
   $hash->{HELPER}{LOGINRETRIES} = 0;
   
   my ($err,$tstart,$tend) = timeEdge($name);
   $tstart = FmtDateTime($tstart);
   $tend   = FmtDateTime($tend);   
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###      start Synology Calendar operation          "); 
   Log3($name, 4, "$name - ####################################################");

   if(!keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
       $ret = "Sendqueue is empty. Nothing to do ...";
       Log3($name, 4, "$name - $ret"); 
       return $ret;  
   }
   
   # den nächsten Eintrag aus "SendQueue" selektieren und ausführen wenn nicht forbidSend gesetzt ist
   for my $idx (sort{$a<=>$b} keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
       if (!$data{SSCal}{$name}{sendqueue}{entries}{$idx}{forbidSend}) {
           $hash->{OPIDX}  = $idx;
           $hash->{OPMODE} = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{opmode};
           $idxset         = 1;
           last;
       }               
   }
   
   if(!$idxset) {
       $ret = "Only entries with \"forbidSend\" are in Sendqueue. Escaping ...";
       Log3($name, 4, "$name - $ret"); 
       return $ret; 
   }
   
   readingsBeginUpdate         ($hash);                   
   readingsBulkUpdate          ($hash, "state", "running");                    
   readingsEndUpdate           ($hash,1);
   
   Log3($name, 4, "$name - Time selection start: ".$tstart);
   Log3($name, 4, "$name - Time selection end: ".$tend);
   
   if ($hash->{HELPER}{APIPARSET}) {                                 # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
       Log3($name, 4, "$name - API hash values already set - ignore get apisites");
       return checkSID($name);
   }

   my $timeout = AttrVal($name,"timeout",20);
   Log3($name, 5, "$name - HTTP-Call will be done with timeout: $timeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   my $calapi = $data{SSCal}{$name}{calapi};
   $url       = "$prot://$addr:$port/webapi/query.cgi?api=".$calapi->{APIINFO}{NAME}."&method=Query&version=1&query=".
                                                            $calapi->{APIAUTH}{NAME}.",".
                                                            $calapi->{CALCAL}{NAME}.",".
                                                            $calapi->{CALEVENT}{NAME}.",".
                                                            $calapi->{CALSHARE}{NAME}.",".
                                                            $calapi->{CALTODO}{NAME}.",".
                                                            $calapi->{APIINFO}{NAME};

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
               url      => $url,
               timeout  => $timeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&FHEM::SSCal::getApiSites_parse
            };
   HttpUtils_NonblockingGet ($param);  

return;
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub getApiSites_parse {                                                   ## no critic 'complexity'
   my ($param, $err, $myjson) = @_;
   my $hash   = $param->{hash};
   my $name   = $hash->{NAME};
   my $addr   = $hash->{ADDR};
   my $port   = $hash->{PORT};
   my $opmode = $hash->{OPMODE};

   my ($error,$errorcode,$success);
  
    if ($err ne "") {
        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - ERROR message: $err");
       
        readingsBeginUpdate         ($hash); 
        readingsBulkUpdateIfChanged ($hash, "Error",       $err);
        readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
        readingsBulkUpdate          ($hash, "state",    "Error");                    
        readingsEndUpdate           ($hash,1); 
        
        checkRetry($name,1);
        return;
        
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash,$success,$myjson) = evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            checkRetry($name,1);       
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my $logstr;
            my $calapi = $data{SSCal}{$name}{calapi};
                        
          # Pfad und Maxversion von "SYNO.API.Auth" ermitteln
            my $apiauthpath   = $data->{data}->{$calapi->{APIAUTH}{NAME}}->{path};
            $apiauthpath      =~ tr/_//d if (defined($apiauthpath));
            my $apiauthmaxver = $data->{data}->{$calapi->{APIAUTH}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apiauthpath) ? "Path of $calapi->{APIAUTH}{NAME} selected: $apiauthpath" : "Path of $calapi->{APIAUTH}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiauthmaxver) ? "MaxVersion of $calapi->{APIAUTH}{NAME} selected: $apiauthmaxver" : "MaxVersion of $calapi->{APIAUTH}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
                   
          # Pfad und Maxversion von "SYNO.Cal.Cal" ermitteln
            my $apicalpath   = $data->{data}->{$calapi->{CALCAL}{NAME}}->{path};
            $apicalpath      =~ tr/_//d if (defined($apicalpath));
            my $apicalmaxver = $data->{data}->{$calapi->{CALCAL}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apicalpath) ? "Path of $calapi->{CALCAL}{NAME} selected: $apicalpath" : "Path of $calapi->{CALCAL}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apicalmaxver) ? "MaxVersion of $calapi->{CALCAL}{NAME} selected: $apicalmaxver" : "MaxVersion of $calapi->{CALCAL}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");            
            
          # Pfad und Maxversion von "SYNO.Cal.Event" ermitteln
            my $apievtpath   = $data->{data}->{$calapi->{CALEVENT}{NAME}}->{path};
            $apievtpath      =~ tr/_//d if (defined($apievtpath));
            my $apievtmaxver = $data->{data}->{$calapi->{CALEVENT}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apievtpath) ? "Path of $calapi->{CALEVENT}{NAME} selected: $apievtpath" : "Path of $calapi->{CALEVENT}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apievtmaxver) ? "MaxVersion of $calapi->{CALEVENT}{NAME} selected: $apievtmaxver" : "MaxVersion of $calapi->{CALEVENT}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr"); 

          # Pfad und Maxversion von "SYNO.Cal.Sharing" ermitteln
            my $apisharepath   = $data->{data}->{$calapi->{CALSHARE}{NAME}}->{path};
            $apisharepath      =~ tr/_//d if (defined($apisharepath));
            my $apisharemaxver = $data->{data}->{$calapi->{CALSHARE}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apisharepath) ? "Path of $calapi->{CALSHARE}{NAME} selected: $apisharepath" : "Path of $calapi->{CALSHARE}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apisharemaxver) ? "MaxVersion of $calapi->{CALSHARE}{NAME} selected: $apisharemaxver" : "MaxVersion of $calapi->{CALSHARE}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr"); 

          # Pfad und Maxversion von "SYNO.Cal.Todo" ermitteln
            my $apitodopath   = $data->{data}->{$calapi->{CALTODO}{NAME}}->{path};
            $apitodopath      =~ tr/_//d if (defined($apitodopath));
            my $apitodomaxver = $data->{data}->{$calapi->{CALTODO}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apitodopath) ? "Path of $calapi->{CALTODO}{NAME} selected: $apitodopath" : "Path of $calapi->{CALTODO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apitodomaxver) ? "MaxVersion of $calapi->{CALTODO}{NAME} selected: $apitodomaxver" : "MaxVersion of $calapi->{CALTODO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");

          # Pfad und Maxversion von "SYNO.API.Info" ermitteln
            my $apiinfopath   = $data->{data}->{$calapi->{APIINFO}{NAME}}->{path};
            $apiinfopath      =~ tr/_//d if (defined($apiinfopath));
            my $apiinfomaxver = $data->{data}->{$calapi->{APIINFO}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apiinfopath) ? "Path of $calapi->{APIINFO}{NAME} selected: $apiinfopath" : "Path of $calapi->{APIINFO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiinfomaxver) ? "MaxVersion of $calapi->{APIINFO}{NAME} selected: $apiinfomaxver" : "MaxVersion of $calapi->{APIINFO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");             
            
            
            # Downgrades für nicht kompatible API-Versionen
            # hier nur nutzen wenn API zentral downgraded werden soll
            my ($infomod, $authmod, $calmod, $evtmod, $sharemod, $todomod);            
            Log3($name, 4, "$name - ------- Begin of adaption section -------");
            
            $apievtmaxver = 3;
            $evtmod       = "yes";
            Log3($name, 4, "$name - MaxVersion of $calapi->{CALEVENT}{NAME} adapted to: $apievtmaxver");
            
            Log3($name, 4, "$name - ------- End of adaption section -------");
            
            # ermittelte Werte in $hash einfügen
            $calapi->{APIINFO}{PATH}   = $apiinfopath;
            $calapi->{APIINFO}{MAX}    = $apiinfomaxver;
            $calapi->{APIINFO}{MOD}    = $infomod // "no";
            $calapi->{APIAUTH}{PATH}   = $apiauthpath;
            $calapi->{APIAUTH}{MAX}    = $apiauthmaxver;  
            $calapi->{APIAUTH}{MOD}    = $authmod // "no";            
            $calapi->{CALCAL}{PATH}    = $apicalpath;
            $calapi->{CALCAL}{MAX}     = $apicalmaxver;
            $calapi->{CALCAL}{MOD}     = $calmod // "no";     
            $calapi->{CALEVENT}{PATH}  = $apievtpath;
            $calapi->{CALEVENT}{MAX}   = $apievtmaxver;
            $calapi->{CALEVENT}{MOD}   = $evtmod // "no";
            $calapi->{CALSHARE}{PATH}  = $apisharepath;
            $calapi->{CALSHARE}{MAX}   = $apisharemaxver;
            $calapi->{CALSHARE}{MOD}   = $sharemod // "no";   
            $calapi->{CALTODO}{PATH}   = $apitodopath;
            $calapi->{CALTODO}{MAX}    = $apitodomaxver;
            $calapi->{CALTODO}{MOD}    = $todomod // "no";  
        
            # API values sind gesetzt in Hash
            $hash->{HELPER}{APIPARSET} = 1;
            
            if ($opmode eq "apiInfo") {                                     # API Infos in Popup anzeigen             
                my $out  = "<html>";
                $out    .= "<b>Synology Calendar API Info</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>API</b> </td><td> <b>Path</b> </td><td> <b>Version</b> </td><td> <b>Downgraded</b> </td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td> </td></tr>";
        
                for my $key (keys %{$calapi}) {
                    my $apiname = $calapi->{$key}{NAME};
                    my $apipath = $calapi->{$key}{PATH};
                    my $apiver  = $calapi->{$key}{MAX};
                    my $apimod  = $calapi->{$key}{MOD};

                    $out .= "<tr>";
                    $out .= "<td> $apiname </td>";
                    $out .= "<td> $apipath </td>";
                    $out .= "<td style=\"text-align: center\"> $apiver  </td>";
                    $out .= "<td style=\"text-align: center\"> $apimod  </td>";
                    $out .= "</tr>";
                }

                $out .= "</table>";
                $out .= "</html>";
                
                readingsBeginUpdate         ($hash);
                readingsBulkUpdateIfChanged ($hash,"Errorcode","none");
                readingsBulkUpdateIfChanged ($hash,"Error",    "none");
                readingsBulkUpdate          ($hash, "state",   "done");  
                readingsEndUpdate           ($hash,1);
        
                # Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
                asyncOutput($hash->{HELPER}{CL}{1},"$out");
                delete($hash->{HELPER}{CL});
              
                checkRetry($name,0);
                return;
            }
                        
        } else {
            $errorcode = "806";
            $error     = experror($hash,$errorcode);                  # Fehlertext zum Errorcode ermitteln
            
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash, "Error",     $error);
            readingsBulkUpdate          ($hash,"state",      "Error");
            readingsEndUpdate           ($hash, 1);

            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
            
            checkRetry($name,1);    
            return;
        }
    }
    
return checkSID($name);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub calOp {  
   my ($name) = @_;
   my $hash   = $defs{$name};
   my $prot   = $hash->{PROT};
   my $addr   = $hash->{ADDR};
   my $port   = $hash->{PORT};
   my $sid    = $hash->{HELPER}{SID};
   my ($url,$timeout,$param,$error,$errorcode);
      
   my $idx    = $hash->{OPIDX};
   my $opmode = $hash->{OPMODE};
   my $method = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{method};
   my $api    = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{api};
   my $params = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{params};
   my $calapi = $data{SSCal}{$name}{calapi};

   Log3($name, 4, "$name - start SendQueue entry index \"$idx\" ($hash->{OPMODE}) for operation."); 

   $timeout = AttrVal($name, "timeout", 20);
   
   Log3($name, 5, "$name - HTTP-Call will be done with timeout: $timeout s");
        
   $url = "$prot://$addr:$port/webapi/".$calapi->{$api}{PATH}."?api=".$calapi->{$api}{NAME}."&version=".$calapi->{$api}{MAX}."&method=$method".$params."&_sid=$sid";
   
   if($opmode eq "deleteEventId" && $api eq "CALEVENT") {               # Workaround !!! Methode delete funktioniert nicht mit SYNO.Cal.Event version > 1
       $url = "$prot://$addr:$port/webapi/".$calapi->{$api}{PATH}."?api=".$calapi->{$api}{NAME}."&version=1&method=$method".$params."&_sid=$sid";
   }

   my $part = $url;
   if(AttrVal($name, "showPassInLog", "0") == 1) {
       Log3($name, 4, "$name - Call-Out: $url");
   } else {
       $part =~ s/$sid/<secret>/x;
       Log3($name, 4, "$name - Call-Out: $part");
   }
   
   $param = {
            url      => $url,
            timeout  => $timeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&FHEM::SSCal::calOp_parse
            };
   
   HttpUtils_NonblockingGet ($param);

return;   
} 
  
#############################################################################################
#                                Callback from calOp
#############################################################################################
sub calOp_parse {                                                           ## no critic 'complexity'
   my ($param, $err, $myjson) = @_;
   my $hash   = $param->{hash};
   my $name   = $hash->{NAME};
   my $prot   = $hash->{PROT};
   my $addr   = $hash->{ADDR};
   my $port   = $hash->{PORT};
   my $opmode = $hash->{OPMODE};
   my $am     = AttrVal($name, "asyncMode", 0);
   my ($ts,$data,$success,$error,$errorcode,$cherror,$r);
   
   if ($err ne "") {
        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - ERROR message: $err");
        
        $errorcode = "none";
        $errorcode = "800" if($err =~ /:\smalformed\sor\sunsupported\sURL$/xs);

        readingsBeginUpdate         ($hash); 
        readingsBulkUpdateIfChanged ($hash, "Error",           $err);
        readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
        readingsBulkUpdate          ($hash, "state",        "Error");                    
        readingsEndUpdate           ($hash,1);         

        checkRetry($name,1);        
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden 
        ($hash,$success,$myjson) = evaljson($hash,$myjson);        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            checkRetry($name,1);       
            return;
        }
        
        $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};

        if ($success) {       

            if ($opmode eq "listcal") {                                     ## no critic 'Cascading' # alle Kalender abrufen  
                my %calendars = ();   
                my ($cals,$dnm,$typ,$oid,$des,$prv,$psi);                   
                my $i    = 0;
                
                my $out  = "<html>";
                $out    .= "<b>Synology Calendar List</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>Calendar</b> </td><td> <b>ID</b> </td><td> <b>Type</b> </td><td> <b>Description</b> </td><td> <b>Privilege</b> </td><td> <b>Public share ID</b> </td><td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
                
                while ($data->{data}[$i]) {
                    $dnm = $data->{data}[$i]{cal_displayname};
                    next if (!$dnm);
                    $typ = "Event" if($data->{data}[$i]{is_evt});
                    $typ = "ToDo"  if($data->{data}[$i]{is_todo});
                    $oid = $data->{data}[$i]{original_cal_id};
                    $des = encode("UTF-8", $data->{data}[$i]{cal_description});
                    $prv = $data->{data}[$i]{cal_privilege};
                    $psi = $data->{data}[$i]{cal_public_sharing_id};
                    $psi = $psi?$psi:"";
    
                    $calendars{$dnm}{id}            = $oid;
                    $calendars{$dnm}{description}   = $des;
                    $calendars{$dnm}{privilege}     = $prv;
                    $calendars{$dnm}{publicshareid} = $psi;
                    $calendars{$dnm}{type}          = $typ;
                    
                    $cals .= "," if($cals);
                    $cals .= $dnm;
                    $out  .= "<tr><td> $dnm </td><td> $oid </td><td> $typ</td><td> $des </td><td>  $prv </td><td> $psi </td><td></tr>";

                    $i++;
                }
                
                $out .= "</table>";
                $out .= "</html>";
                
                $hash->{HELPER}{CALENDARS}  = \%calendars if(%calendars);
                $hash->{HELPER}{CALFETCHED} = 1;
               
                my @newa;
                my $list = $modules{$hash->{TYPE}}{AttrList};
                my @deva = split(" ", $list);
                for (@deva) {
                     push @newa, $_ if($_ !~ /usedCalendars:/x);
                }

                $cals =~ s/\s/#/gx if($cals);
    
                push @newa, ($cals?"usedCalendars:multiple-strict,$cals ":"usedCalendars:--no#Calendar#selectable--");
                
                $hash->{".AttrList"} = join(" ", @newa);              # Device spezifische AttrList, überschreibt Modul AttrList !      

                # Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
                asyncOutput($hash->{HELPER}{CL}{1},"$out");
                delete($hash->{HELPER}{CL});  
                
                checkRetry($name,0);

                readingsBeginUpdate         ($hash); 
                readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
                readingsBulkUpdateIfChanged ($hash, "Error",      "none");                  
                readingsBulkUpdate          ($hash, "state",      "done");                    
                readingsEndUpdate           ($hash,1); 
            
            } elsif ($opmode eq "eventlist") {                          # Events der ausgewählten Kalender aufbereiten 
                delete $data{SSCal}{$name}{eventlist};                  # zentrales Event/ToDo Hash löschen
                delete $data{SSCal}{$name}{vcalendar};                  # zentrales VCALENDAR Hash löschen
                $hash->{eventlist} = $data;                             # Data-Hashreferenz im Hash speichern
               
                if ($am) {                                              # Extrahieren der Events asynchron (nicht-blockierend)
                    Log3($name, 4, "$name - Event parse mode: asynchronous");
                    my $timeout = AttrVal($name, "timeout", 20)+180;
                    
                    $hash->{HELPER}{RUNNING_PID}           = BlockingCall("FHEM::SSCal::extractEventlist", $name, "FHEM::SSCal::createReadings", $timeout, "FHEM::SSCal::blockingTimeout", $hash);
                    $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057                    
                
                } else {                                                # Extrahieren der Events synchron (blockierend)
                    Log3($name, 4, "$name - Event parse mode: synchronous");
                    extractEventlist ($name);                         
                }    
            
            } elsif ($opmode eq "todolist") {                           # ToDo's der ausgewählten Tasks-Kalender aufbereiten
                delete $data{SSCal}{$name}{eventlist};                  # zentrales Event/ToDo Hash löschen
                $hash->{eventlist} = $data;                             # Data-Hashreferenz im Hash speichern
               
                if ($am) {                                              # Extrahieren der ToDos asynchron (nicht-blockierend)
                    Log3($name, 4, "$name - Task parse mode: asynchronous");
                    my $timeout = AttrVal($name, "timeout", 20)+180;
                    
                    $hash->{HELPER}{RUNNING_PID}           = BlockingCall("FHEM::SSCal::extractToDolist", $name, "FHEM::SSCal::createReadings", $timeout, "FHEM::SSCal::blockingTimeout", $hash);
                    $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057                    
                
                } else {                                                # Extrahieren der ToDos synchron (blockierend)
                    Log3($name, 4, "$name - Task parse mode: synchronous");
                    extractToDolist ($name);                         
                }
                
            } elsif ($opmode eq "cleanCompleteTasks") {                  # abgeschlossene ToDos wurden gelöscht                

                readingsBeginUpdate         ($hash); 
                readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
                readingsBulkUpdateIfChanged ($hash, "Error",      "none");                  
                readingsBulkUpdate          ($hash, "state",      "done");                    
                readingsEndUpdate           ($hash,1); 
                
                Log3($name, 3, "$name - All completed tasks were deleted from selected ToDo lists");
                
                checkRetry($name,0);
            
            } elsif ($opmode eq "deleteEventId") {                      # ein Kalendereintrag mit Event Id wurde gelöscht                

                readingsBeginUpdate         ($hash); 
                readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
                readingsBulkUpdateIfChanged ($hash, "Error",      "none");                  
                readingsBulkUpdate          ($hash, "state",      "done");                    
                readingsEndUpdate           ($hash,1); 
                
                Log3($name, 3, "$name - The specified event id was deleted");
                
                # Queuedefinition sichern vor checkretry
                my $idx = $hash->{OPIDX};
                my $api = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{api};
                
                checkRetry($name,0);
                
                # Kalendereinträge neu einlesen nach dem löschen Event Id
                CommandSet(undef, "$name calUpdate");
                
            }                   
           
        } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{error}->{code};
            $cherror   = $data->{error}->{errors};                       # vom cal gelieferter Fehler
            $error     = experror($hash,$errorcode);               # Fehlertext zum Errorcode ermitteln
            if ($error =~ /not found/) {
                $error .= " New error: ".($cherror // "'  '");
            }
            
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash,"Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash,"Error",     $error);
            readingsBulkUpdate          ($hash,"state",     "Error");
            readingsEndUpdate           ($hash, 1);
       
            Log3($name, 2, "$name - ERROR - Operation $opmode was not successful. Errorcode: $errorcode - $error");
            
            checkRetry($name,1);
        }
                
       undef $data;
       undef $myjson;
   }

return;
}

#############################################################################################
#                    Extrahiert empfangene Kalendertermine (Events)
#############################################################################################
sub extractEventlist {                                    ## no critic 'complexity'
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $data   = delete $hash->{eventlist};                 # zentrales Eventhash löschen !
  my $am     = AttrVal($name, "asyncMode", 0);
  
  my ($tz,$bdate,$btime,$bts,$edate,$etime,$ets,$ci,$bi,$ei,$startEndDiff,$excl,$es,$em,$eh);
  my ($nbdate,$nbtime,$nbts,$nedate,$netime,$nets);
  my @row_array;
  
  my (undef,$tstart,$tend) = timeEdge($name);             # Sollstart- und Sollendezeit der Kalenderereignisse ermitteln
  my $datetimestart        = FmtDateTime($tstart);
  my $datetimeend          = FmtDateTime($tend);
       
  my $n = 0;                                              # Zusatz f. lfd. Nr. zur Unterscheidung exakt zeitgleicher Events
  for my $key (keys %{$data->{data}}) {
      my $i = 0;
  
      while ($data->{data}{$key}[$i]) {
          my $ignore = 0; 
          my $done   = 0;
          my $next   = 0;
          ($nbdate,$nedate) = ("","");  

          my $uid = $data->{data}{$key}[$i]{ical_uid};                    # UID des Events    
          extractIcal ($name,$data->{data}{$key}[$i]);                    # VCALENDAR Extrakt in {HELPER}{VCALENDAR} importieren          
          
          my $isallday                         = $data->{data}{$key}[$i]{is_all_day};
          ($bi,$tz,$bdate,$btime,$bts,$excl)   = explodeDateTime ($hash, $data->{data}{$key}[$i]{dtstart}, 0, 0, 0);         # Beginn des Events
          ($ei,undef,$edate,$etime,$ets,undef) = explodeDateTime ($hash, $data->{data}{$key}[$i]{dtend}, $isallday, 0, 0);   # Ende des Events
            
          my ($byear, $bmonth, $bmday) = $bdate =~ /(\d{4})-(\d{2})-(\d{2})/x;
          $nbtime                      = $btime;                
          
          my ($eyear, $emonth, $emday) = $edate =~ /(\d{4})-(\d{2})-(\d{2})/x;
          $netime                      = $etime;
          
          # Bugfix API - wenn is_all_day und an erster Stelle im 'data' Ergebnis des API-Calls ist Endedate/time nicht korrekt !
          if($isallday && ($bdate ne $edate) && $netime =~ /^00:59:59$/x) {
              ($es, $em, $eh, $emday, $emonth, $eyear, undef, undef, undef) = localtime($ets-=3600);
              $eyear  = sprintf("%02d", $eyear+=1900);
              $emonth = sprintf("%02d", $emonth+=1);
              $emday  = sprintf("%02d", $emday);
              $netime = $eh.$em.$es;
              $nbtime =~ s/://gx;

              ($bi,undef,$bdate,$btime,$bts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, 0, 0);  
              ($ei,undef,$edate,$etime,$ets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, 0, 0);         
          }
          
          $startEndDiff = $ets - $bts;                                          # Differenz Event Ende / Start in Sekunden
                                                        
          if(!$data->{data}{$key}[$i]{is_repeat_evt}) {                         # einmaliger Event
              Log3($name, 5, "$name - Single event Begin: $bdate, End: $edate");
              
              if($ets < $tstart || $bts > $tend) {
                  Log3($name, 4, "$name - Ignore single event -> $data->{data}{$key}[$i]{summary} start: $bdate $btime, end: $edate $etime");
                  $ignore = 1;
                  $done   = 0; 
              } elsif ($excl) {
                  Log3($name, 4, "$name - Ignored by Ical compare -> $data->{data}{$key}[$i]{summary} start: $bdate $btime, end: $edate $etime");
                  $ignore = 1;
                  $done   = 0;               
              } else {
                  writeValuesToArray ({ name        => $name,
                                        eventno     => $n,
                                        calref      => $data->{data}{$key}[$i],
                                        timezone    => $tz,
                                        begindate   => $bdate,
                                        begintime   => $btime,
                                        begints     => $bts,
                                        enddate     => $edate,
                                        endtime     => $etime,
                                        endts       => $ets,
                                        sumarrayref => \@row_array,
                                        uid         => $uid
                                     });
                  $ignore = 0;
                  $done   = 1;
              }       
          
          } elsif ($data->{data}{$key}[$i]{is_repeat_evt}) {                    # Event ist wiederholend
              Log3($name, 5, "$name - Recurring event Begin: $bdate, End: $edate");
              
              my ($freq,$count,$interval,$until,$uets,$bymonthday,$byday);
              my $rr = $data->{data}{$key}[$i]{evt_repeat_setting}{repeat_rule};
              
              # Format: FREQ=YEARLY;COUNT=1;INTERVAL=2;BYMONTHDAY=15;BYMONTH=10;UNTIL=2020-12-31T00:00:00
              my @para  = split(";", $rr);
              
              for my $par (@para) {
                  my ($p1,$p2) = split("=", $par);
                  if ($p1 eq "FREQ") {
                      $freq = $p2;
                  } elsif ($p1 eq "COUNT") {                                    # Event endet automatisch nach x Wiederholungen
                      $count = $p2;                                             
                  } elsif ($p1 eq "INTERVAL") {                                 # Wiederholungsintervall         
                      $interval = $p2;
                  } elsif ($p1 eq "UNTIL") {                                    # festes Intervallende angegeben        
                      $until = $p2;
                      $until =~ s/[-:]//gx;
                      $uets  = (explodeDateTime ($hash, $until, 0, 0, 0))[4];
                  } elsif ($p1 eq "BYMONTHDAY") {                               # Wiederholungseigenschaft -> Tag des Monats z.B. 13 (Tag 13)    
                      $bymonthday = $p2;
                  } elsif ($p1 eq "BYDAY") {                                    # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                          $byday = $p2;
                  } 
              }
              
              if (defined $uets && $uets < $tstart) {
                  Log3($name, 4, "$name - Ignore recurring event -> $data->{data}{$key}[$i]{summary} , interval end \"$nedate $netime\" is less than selection start \"$datetimestart\"");
                  $ignore = 1;
              }
              
              $count      = $count      ? $count      : 9999999;                # $count "unendlich" wenn kein COUNT angegeben
              $interval   = $interval   ? $interval   : 1;
              $bymonthday = $bymonthday ? $bymonthday : "";
              $byday      = $byday      ? $byday      : "";
              $until      = $until      ? $until      : "";
              
              Log3($name, 4, "$name - Recurring params - FREQ: $freq, COUNT: $count, INTERVAL: $interval, BYMONTHDAY: $bymonthday, BYDAY: $byday, UNTIL: $until");
                 
              $count--;                                                         # Korrektur Anzahl Wiederholungen, COUNT ist Gesamtzahl der Ausführungen !   
                 
              if ($freq eq "YEARLY") {                                          # jährliche Wiederholung                             
                  for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {                                    
                      $byear += ($ci>=0?1:0);
                      $eyear += ($ci>=0?1:0);
                      
                      $nbtime =~ s/://gx;
                      $netime =~ s/://gx;
                     
                      my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                      ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                      ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents
  
                      Log3($name, 5, "$name - YEARLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                      ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'YEARLY',
                                                                        name        => $name,
                                                                        excl        => $excl,
                                                                        eventno     => $n,
                                                                        calref      => $data->{data}{$key}[$i],
                                                                        timezone    => $tz,
                                                                        begindate   => $bdate,
                                                                        newbdate    => $nbdate,
                                                                        begintime   => $btime,
                                                                        newbtime    => $nbtime,
                                                                        begints     => $bts,
                                                                        enddate     => $edate,
                                                                        newedate    => $nedate, 
                                                                        endtime     => $etime,
                                                                        newetime    => $netime,
                                                                        endts       => $ets,
                                                                        newendts    => $nets,
                                                                        sumarrayref => \@row_array,
                                                                        untilts     => $uets,
                                                                        newbegints  => $nbts,
                                                                        tstart      => $tstart,
                                                                        tend        => $tend,
                                                                        until       => $until,
                                                                        uid         => $uid
                                                                     });   
                      
                      next if($next);                                       
                      last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                  }                      
              }
              
              if ($freq eq "MONTHLY") {                                        # monatliche Wiederholung                       
                  if ($bymonthday) {                                           # Wiederholungseigenschaft am Tag X des Monats     
                      for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {
                          $bmonth += $interval if($ci>=0);
                          $byear  += int( $bmonth/13);
                          $bmonth %= 12 if($bmonth>12);
                          $bmonth = sprintf("%02d", $bmonth);
                          
                          $emonth += $interval if($ci>=0);
                          $eyear  += int( $emonth/13);
                          $emonth %= 12 if($emonth>12);
                          $emonth = sprintf("%02d", $emonth);
  
                          $nbtime =~ s/://gx;
                          $netime =~ s/://gx;
  
                          my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                          ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                          ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents
  
                          Log3($name, 5, "$name - MONTHLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                          ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'MONTHLY',
                                                                            name        => $name,
                                                                            excl        => $excl,
                                                                            eventno     => $n,
                                                                            calref      => $data->{data}{$key}[$i],
                                                                            timezone    => $tz,
                                                                            begindate   => $bdate,
                                                                            newbdate    => $nbdate,
                                                                            begintime   => $btime,
                                                                            newbtime    => $nbtime,
                                                                            begints     => $bts,
                                                                            enddate     => $edate,
                                                                            newedate    => $nedate, 
                                                                            endtime     => $etime,
                                                                            newetime    => $netime,
                                                                            endts       => $ets,
                                                                            newendts    => $nets,
                                                                            sumarrayref => \@row_array,
                                                                            untilts     => $uets,
                                                                            newbegints  => $nbts,
                                                                            tstart      => $tstart,
                                                                            tend        => $tend,
                                                                            until       => $until,
                                                                            uid         => $uid
                                                                         });   
                          
                          next if($next);                                        
                          last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                      }
                  }
                  if ($byday) {                                                 # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness,$rDayOfWeekNew,$rDaysToAddOrSub,$rNewTime);
                      my @ByDays = split(",", $byday);                          # Array der Wiederholungstage
                      
                      for (@ByDays) {
                          my $rByDay       = $_;                                # das erste Wiederholungselement
                          my $rByDayLength = length($rByDay);                   # die Länge des Strings       
  
                          my $rDayStr;                                          # Tag auf den das Datum gesetzt werden soll
                          my $rDayInterval;                                     # z.B. 2 = 2nd Tag des Monats oder -1 = letzter Tag des Monats
                          if ($rByDayLength > 2) {
                              $rDayStr      = substr($rByDay, -2);
                              $rDayInterval = int(substr($rByDay, 0, $rByDayLength - 2));
                          } else {
                              $rDayStr      = $rByDay;
                              $rDayInterval = 1;
                          }
  
                          my @weekdays     = qw(SU MO TU WE TH FR SA);
                          my ($rDayOfWeek) = grep {$weekdays[$_] eq $rDayStr} 0..$#weekdays;     # liefert Nr des Wochentages: SU = 0 ... SA = 6
                          
                          for ($ci=-1; $ci<($count); $ci++) {
                              if ($rDayInterval > 0) {                                           # Angabe "jeder x Wochentag" ist positiv (-2 wäre z.B. vom Ende des Monats zu zähelen)
                                  $bmonth += $interval if($ci>=0);
                                  $byear  += int( $bmonth/13);
                                  $bmonth %= 12 if($bmonth>12);
                                  $bmonth  = sprintf("%02d", $bmonth);
                                  
                                  ($nbhh,$nbmm,$nbss)  = split(":", $nbtime);
                                  my $firstOfNextMonth = fhemTimeLocal($nbss, $nbmm, $nbhh, 1, $bmonth-1, $byear-1900);
                                  ($nbss, $nbmm, $nbhh, $bmday, $bmonth, $byear, $rDayOfWeekNew, undef, undef) = localtime($firstOfNextMonth);  # den 1. des Monats sowie die dazu gehörige Nr. des Wochentages
  
                                  if ($rDayOfWeekNew <= $rDayOfWeek) {                               # Nr Wochentag des 1. des Monats <= als Wiederholungstag 
                                      $rDaysToAddOrSub = $rDayOfWeek - $rDayOfWeekNew;
                                  } else {
                                      $rDaysToAddOrSub = 7 - $rDayOfWeekNew + $rDayOfWeek;
                                  }
                                  $rDaysToAddOrSub += (7 * ($rDayInterval - 1));                     # addiere Tagesintervall, z.B. 4th Freitag ...
  
                                  $rNewTime = plusNSeconds($firstOfNextMonth, 86400*$rDaysToAddOrSub, 1);                                                                                                
                                  ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = DTfromStartandDiff ($rNewTime,$startEndDiff);
                              
                              } else {
                                  Log3($name, 2, "$name - WARNING - negative values for BYDAY are currently not implemented and will be ignored");
                                  $ignore = 1;
                                  $done   = 0;
                                  $n++;
                                  next;                                            
                              }
                              
                              $nbtime = $nbhh.$nbmm.$nbss;
                              $netime = $nehh.$nemm.$ness;
  
                              my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                              ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                              ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents
  
                              Log3($name, 5, "$name - MONTHLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                              
                              ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'MONTHLY',
                                                                                name        => $name,
                                                                                excl        => $excl,
                                                                                eventno     => $n,
                                                                                calref      => $data->{data}{$key}[$i],
                                                                                timezone    => $tz,
                                                                                begindate   => $bdate,
                                                                                newbdate    => $nbdate,
                                                                                begintime   => $btime,
                                                                                newbtime    => $nbtime,
                                                                                begints     => $bts,
                                                                                enddate     => $edate,
                                                                                newedate    => $nedate, 
                                                                                endtime     => $etime,
                                                                                newetime    => $netime,
                                                                                endts       => $ets,
                                                                                newendts    => $nets,
                                                                                sumarrayref => \@row_array,
                                                                                untilts     => $uets,
                                                                                newbegints  => $nbts,
                                                                                tstart      => $tstart,
                                                                                tend        => $tend,
                                                                                until       => $until,
                                                                                uid         => $uid
                                                                             });   
                              
                              next if($next);                                        
                              last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                          }
                      }   
                  }
              }
  
              if ($freq eq "WEEKLY") {                                              # wöchentliche Wiederholung                                                                             
                  if ($byday) {                                                     # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness,$rNewTime,$rDayOfWeekNew,$rDaysToAddOrSub);                   
                      my @ByDays   = split(",", $byday);                            # Array der Wiederholungstage
                      my $btsstart = $bts;
                      $ci = -1;
                      
                      while ($ci<$count) {                                                   
                          $rNewTime = $btsstart;
                          for (@ByDays) {
                              $ci++;
                              my $rByDay       = $_;                                                # das erste Wiederholungselement    
                              my @weekdays     = qw(SU MO TU WE TH FR SA);
                              my ($rDayOfWeek) = grep {$weekdays[$_] eq $rByDay} 0..$#weekdays;     # liefert Nr des Wochentages: SU = 0 ... SA = 6
                              
                              ($nbss, $nbmm, $nbhh, $bmday, $bmonth, $byear, $rDayOfWeekNew, undef, undef) = localtime($rNewTime);                                        
                              
                              ($nbhh,$nbmm,$nbss)  = split(":", $nbtime);

                              if ($rDayOfWeekNew <= $rDayOfWeek) {                                  # Nr nächster Wochentag <= Planwochentag
                                  $rDaysToAddOrSub = $rDayOfWeek - $rDayOfWeekNew;
                              } else {
                                  $rDaysToAddOrSub = 7 - $rDayOfWeekNew + $rDayOfWeek + (7 * ($interval-1));          
                              }                                            

                              $rNewTime = plusNSeconds($rNewTime, 86400 * $rDaysToAddOrSub, 1);                             
                              ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = DTfromStartandDiff ($rNewTime,$startEndDiff);
               
                              $nbtime = $nbhh.$nbmm.$nbss;
                              $netime = $nehh.$nemm.$ness;

                              my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                              ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                              ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents

                              Log3($name, 5, "$name - WEEKLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                              
                              ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'WEEKLY',
                                                                                name        => $name,
                                                                                excl        => $excl,
                                                                                eventno     => $n,
                                                                                calref      => $data->{data}{$key}[$i],
                                                                                timezone    => $tz,
                                                                                begindate   => $bdate,
                                                                                newbdate    => $nbdate,
                                                                                begintime   => $btime,
                                                                                newbtime    => $nbtime,
                                                                                begints     => $bts,
                                                                                enddate     => $edate,
                                                                                newedate    => $nedate, 
                                                                                endtime     => $etime,
                                                                                newetime    => $netime,
                                                                                endts       => $ets,
                                                                                newendts    => $nets,
                                                                                sumarrayref => \@row_array,
                                                                                untilts     => $uets,
                                                                                newbegints  => $nbts,
                                                                                tstart      => $tstart,
                                                                                tend        => $tend,
                                                                                until       => $until,
                                                                                uid         => $uid
                                                                             });   
                              
                              next if($next);                      
                              last if((defined $uets && ($uets < $nbts)) || $nbts > $tend || $ci == $count);              
                          }
                          last if((defined $uets && ($uets < $nbts)) || $nbts > $tend || $ci == $count);
                          $btsstart += (7 * 86400 * $interval);                              # addiere Tagesintervall, z.B. 4th Freitag ...                             
                      }    
                  
                  } else {    
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness); 
                      my $rNewTime = $bts;
                      
                      for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {
                          $rNewTime += $interval*604800 if($ci>=0);                          # Wochenintervall addieren
                          
                          ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = DTfromStartandDiff ($rNewTime,$startEndDiff);                      
                          $nbtime = $nbhh.$nbmm.$nbss;
                          $netime = $nehh.$nemm.$ness;                
  
                          my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                          ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                          ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents
  
                          Log3($name, 5, "$name - WEEKLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                           
                          ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'WEEKLY',
                                                                            name        => $name,
                                                                            excl        => $excl,
                                                                            eventno     => $n,
                                                                            calref      => $data->{data}{$key}[$i],
                                                                            timezone    => $tz,
                                                                            begindate   => $bdate,
                                                                            newbdate    => $nbdate,
                                                                            begintime   => $btime,
                                                                            newbtime    => $nbtime,
                                                                            begints     => $bts,
                                                                            enddate     => $edate,
                                                                            newedate    => $nedate, 
                                                                            endtime     => $etime,
                                                                            newetime    => $netime,
                                                                            endts       => $ets,
                                                                            newendts    => $nets,
                                                                            sumarrayref => \@row_array,
                                                                            untilts     => $uets,
                                                                            newbegints  => $nbts,
                                                                            tstart      => $tstart,
                                                                            tend        => $tend,
                                                                            until       => $until,
                                                                            uid         => $uid
                                                                         });   
                          
                          next if($next);                      
                          last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                      }                                    
                  }                         
              } 
  
              if ($freq eq "DAILY") {                                         # tägliche Wiederholung
                  my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness);
                  for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {                                    
                      
                      $bts += 86400*$interval if($ci>=0);
  
                      ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = DTfromStartandDiff ($bts,$startEndDiff);                                    
  
                      $nbtime = $nbhh.$nbmm.$nbss;
                      $netime = $nehh.$nemm.$ness;                                    
                      
                      my $dtstart = $byear.$bmonth.$bmday."T".$nbtime;
                      ($bi,undef,$nbdate,$nbtime,$nbts,$excl) = explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime, 0, $uid, $dtstart);  # Beginn des Wiederholungsevents
                      ($ei,undef,$nedate,$netime,$nets,undef) = explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime, 0, $uid, $dtstart);  # Ende des Wiederholungsevents
  
                      Log3($name, 5, "$name - DAILY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                      ($ignore, $done, $n, $next) = evalTimeAndWrite ({ recurring   => 'DAILY',
                                                                        name        => $name,
                                                                        excl        => $excl,
                                                                        eventno     => $n,
                                                                        calref      => $data->{data}{$key}[$i],
                                                                        timezone    => $tz,
                                                                        begindate   => $bdate,
                                                                        newbdate    => $nbdate,
                                                                        begintime   => $btime,
                                                                        newbtime    => $nbtime,
                                                                        begints     => $bts,
                                                                        enddate     => $edate,
                                                                        newedate    => $nedate, 
                                                                        endtime     => $etime,
                                                                        newetime    => $netime,
                                                                        endts       => $ets,
                                                                        newendts    => $nets,
                                                                        sumarrayref => \@row_array,
                                                                        untilts     => $uets,
                                                                        newbegints  => $nbts,
                                                                        tstart      => $tstart,
                                                                        tend        => $tend,
                                                                        until       => $until,
                                                                        uid         => $uid
                                                                     });   
                      
                      next if($next);                      
                      last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                  }                                 
              }                             
          }
          
          if ($ignore == 1) {
              $i++;
              next;
          }
          
          if(!$done) {                                      # für Testzwecke mit $ignore = 0 und $done = 0
              $bdate = $nbdate ? $nbdate : $bdate;
              $btime = $nbtime ? $nbtime : $btime;
              $bts   = $nbts   ? $nbts   : $bts;
              
              $edate = $nedate ? $nedate : $edate;
              $etime = $netime ? $netime : $etime;
              $ets   = $nets   ? $nets   : $ets;                  
              
              writeValuesToArray ({ name        => $name,
                                    eventno     => $n,
                                    calref      => $data->{data}{$key}[$i],
                                    timezone    => $tz,
                                    begindate   => $bdate,
                                    begintime   => $btime,
                                    begints     => $bts,
                                    enddate     => $edate,
                                    endtime     => $etime,
                                    endts       => $ets,
                                    sumarrayref => \@row_array,
                                    uid         => $uid
                                 });          
          }
          
          $i++;
          $n++;
      }
      $n++;
  }  
  
  # encoding result 
  my $rowlist = join('_ESC_', @row_array);
  $rowlist    = encode_base64($rowlist,"");
                                      
  return "$name|$rowlist" if($am);                    # asynchroner Mode mit BlockingCall                                                    
      
return createReadings ("$name|$rowlist");       # synchoner Mode
}

#############################################################################################
#                    Extrahiert empfangene Tasks aus ToDo-Kalender (Aufgabenliste)
#############################################################################################
sub extractToDolist {                               ## no critic 'complexity'
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $data   = delete $hash->{eventlist};
  my $am     = AttrVal($name, "asyncMode", 0);
  
  my ($val,$tz,$td,$d,$t,$uts); 
  my ($bdate,$btime,$bts,$edate,$etime,$ets,$ci,$bi,$ei,$startEndDiff,$excl);
  my ($nbdate,$nbtime,$nbts,$nedate,$netime,$nets);
  my @row_array;
  
  my (undef,$tstart,$tend) = timeEdge($name);       # Sollstart- und Sollendezeit der Kalenderereignisse ermitteln
  my $datetimestart        = FmtDateTime($tstart);
  my $datetimeend          = FmtDateTime($tend);
       
  my $n = 0;       
  for my $key (keys %{$data->{data}}) {
      my $i = 0;
  
      while ($data->{data}{$key}[$i]) {
          my $ignore = 0; 
          my $done   = 0;
          ($nbdate,$nedate) = ("","");  

          my $uid = $data->{data}{$key}[$i]{ical_uid};                          # UID des Events          
          
          ($bi,$tz,$bdate,$btime,$bts,$excl)   = explodeDateTime ($hash, $data->{data}{$key}[$i]{due}, 0, 0, 0);    # Fälligkeit des Tasks (falls gesetzt)
          ($ei,undef,$edate,$etime,$ets,undef) = explodeDateTime ($hash, $data->{data}{$key}[$i]{due}, 0, 0, 0);    # Ende = Fälligkeit des Tasks (falls gesetzt)
  
          if ($bdate && $edate) {                                               # nicht jede Aufgabe hat Date / Time gesetzt
              my ($byear, $bmonth, $bmday) = $bdate =~ /(\d{4})-(\d{2})-(\d{2})/x;
              $nbtime                      = $btime;                
              
              my ($eyear, $emonth, $emday) = $edate =~ /(\d{4})-(\d{2})-(\d{2})/x;
              $netime                      = $etime;
          }
                                              
          if(!$data->{data}{$key}[$i]{is_repeat_evt}) {                         # einmaliger Task (momentan gibt es keine Wiederholungstasks)
              Log3($name, 5, "$name - Single task Begin: $bdate, End: $edate") if($bdate && $edate);
              
              if(($ets && $ets < $tstart) || ($bts && $bts > $tend)) {
                  Log3($name, 4, "$name - Ignore single task -> $data->{data}{$key}[$i]{summary} start: $bdate $btime, end: $edate $etime");
                  $ignore = 1;
                  $done   = 0; 
              
              } else {
                  writeValuesToArray ({ name        => $name,
                                        eventno     => $n,
                                        calref      => $data->{data}{$key}[$i],
                                        timezone    => $tz,
                                        begindate   => $bdate,
                                        begintime   => $btime,
                                        begints     => $bts,
                                        enddate     => $edate,
                                        endtime     => $etime,
                                        endts       => $ets,
                                        sumarrayref => \@row_array,
                                        uid         => $uid
                                     });
                  $ignore = 0;
                  $done   = 1;
              }       
          
          } 
          
          if ($ignore == 1) {
              $i++;
              next;
          }
          
          if(!$done) {                                      # für Testzwecke mit $ignore = 0 und $done = 0
              $bdate = $nbdate ? $nbdate : $bdate;
              $btime = $nbtime ? $nbtime : $btime;
              $bts   = $nbts   ? $nbts   : $bts;
              
              $edate = $nedate ? $nedate : $edate;
              $etime = $netime ? $netime : $etime;
              $ets   = $nets   ? $nets   : $ets;                  
              
              writeValuesToArray ({ name        => $name,
                                    eventno     => $n,
                                    calref      => $data->{data}{$key}[$i],
                                    timezone    => $tz,
                                    begindate   => $bdate,
                                    begintime   => $btime,
                                    begints     => $bts,
                                    enddate     => $edate,
                                    endtime     => $etime,
                                    endts       => $ets,
                                    sumarrayref => \@row_array,
                                    uid         => $uid
                                 });
          }
          $i++;
          $n++;
      }
      $n++;
  }  
  
  # encoding result 
  my $rowlist = join('_ESC_', @row_array);
  $rowlist    = encode_base64($rowlist,"");
                                         
  return "$name|$rowlist" if($am);                      # asynchroner Mode mit BlockingCall          
                                      
return createReadings ("$name|$rowlist");               # synchoner Mode
}

#############################################################################################
#       
#   bewertet Zeitgrenzen und excludierende Parameter - ruft Schreiben der Daten in Ergenis
#   Array auf wenn Prüfung positiv
#
#############################################################################################
sub evalTimeAndWrite {
  my ($argref)  = @_;
  my $name      = $argref->{name};
  my $n         = $argref->{eventno};
  my $calref    = $argref->{calref};
  my $excl      = $argref->{excl};
  my $tz        = $argref->{timezone};
  my $bdate     = $argref->{begindate};
  my $nbdate    = $argref->{newbdate};
  my $btime     = $argref->{begintime};
  my $nbtime    = $argref->{newbtime};
  my $bts       = $argref->{begints};
  my $edate     = $argref->{enddate};
  my $nedate    = $argref->{newedate};
  my $etime     = $argref->{endtime};
  my $netime    = $argref->{newetime};
  my $ets       = $argref->{endts};
  my $uets      = $argref->{untilts};
  my $nbts      = $argref->{newbegints};
  my $tstart    = $argref->{tstart};
  my $tend      = $argref->{tend};
  my $nets      = $argref->{newendts};
  my $aref      = $argref->{sumarrayref};
  my $uid       = $argref->{uid};
  my $recurring = $argref->{recurring};
  my $until     = $argref->{until};
  
  my $ignore    = 0; 
  my $done      = 0;
  my $next      = 0;

  if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
      Log3($name, 4, "$name - Ignore ".$recurring." event due to UNTIL -> ".$calref->{summary}." , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
      $ignore = 1;
      $done   = 0;                                        
  
  } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
      Log3($name, 4, "$name - Ignore ".$recurring." event -> ".$calref->{summary}." , start: $nbdate $nbtime, end: $nedate $netime");
      $ignore = 1;
      $done   = 0;                                        
  
  } elsif ($excl) {
      Log3($name, 4, "$name - ".$recurring." recurring event is deleted -> ".$calref->{summary}." , start: $nbdate $nbtime, end: $nedate $netime");
      $ignore = 1;
      $done   = 0;                      
  
  } else {
      $bdate = $nbdate ? $nbdate : $bdate;
      $btime = $nbtime ? $nbtime : $btime;
      $bts   = $nbts   ? $nbts   : $bts;
      
      $edate = $nedate ? $nedate : $edate;
      $etime = $netime ? $netime : $etime;
      $ets   = $nets   ? $nets   : $ets;                  
      
      writeValuesToArray ({ name        => $name,
                            eventno     => $n,
                            calref      => $calref,
                            timezone    => $tz,
                            begindate   => $bdate,
                            begintime   => $btime,
                            begints     => $bts,
                            enddate     => $edate,
                            endtime     => $etime,
                            endts       => $ets,
                            sumarrayref => $aref,
                            uid         => $uid
                         });  
      $ignore = 0;
      $done   = 1;
      $next   = 1;
      $n++;
  }                                       

return ($ignore, $done, $n, $next);
}

#############################################################################################
#         schreibe Key/Value Pairs in zentrales Valuearray zur Readingerstellung
#         $n           = Zusatz f. lfd. Nr. zur Unterscheidung exakt 
#                        zeitgleicher Events
#         $vh          = Referenz zum Kalenderdatenhash
#         $aref        = Rferenz zum Ergebnisarray
#         $uid         = UID des Ereignisses als Schlüssel im VCALENDER Hash 
#                        (Berechnung der Vorwarnzeitenzeiten)                
#
#         Ergebisarray Aufbau:
#                       0                            1               2
#         (Index aus BeginTimestamp + lfNr) , (Blockindex_Reading) , (Wert)
#
#############################################################################################
sub writeValuesToArray {                                                   ## no critic 'complexity'
  my ($argref)  = @_;
  my $name      = $argref->{name};
  my $n         = $argref->{eventno};
  my $vh        = $argref->{calref};
  my $tz        = $argref->{timezone};
  my $bdate     = $argref->{begindate};
  my $btime     = $argref->{begintime};
  my $bts       = $argref->{begints};
  my $edate     = $argref->{enddate};
  my $etime     = $argref->{endtime};
  my $ets       = $argref->{endts};
  my $aref      = $argref->{sumarrayref};
  my $uid       = $argref->{uid};
  
  my $hash      = $defs{$name};
  my $lang      = AttrVal("global", "language", "EN");
  my $ts        = time();                                                  # Istzeit Timestamp
  my $om        = $hash->{OPMODE};                                         # aktuelle Operation Mode
  my $status    = "initialized";
  my ($val,$uts,$td,$dleft,$bWday,$chts);
  
  my ($upcoming,$alarmed,$started,$ended) = (0,0,0,0);
 
  $upcoming = isUpcoming ($ts,0,$bts);                                     # initiales upcoming
  $started  = isStarted  ($ts,$bts,$ets);
  $ended    = isEnded    ($ts,$ets);
  
  if($bdate && $btime) {
      push(@$aref, $bts+$n." 05_Begin "  .$bdate." ".$btime."\n");
      my ($ny,$nm,$nd,undef) = split(/[\s-]/x, TimeNow());                         # Datum Jetzt
      my ($by,$bm,$bd)       = split("-", $bdate);                                 # Beginn Datum
      my $ntimes             = fhemTimeLocal(00, 00, 00, $nd, $nm-1, $ny-1900);
      my $btimes             = fhemTimeLocal(00, 00, 00, $bd, $bm-1, $by-1900);
      if($btimes >= $ntimes) {
          $dleft = int(($btimes - $ntimes)/86400);
      }
      
      my @days;
      (undef, undef, undef, undef, undef, undef, $bWday, undef, undef) = localtime($btimes);
      if($lang eq "DE") {
          @days = qw(Sontag Montag Dienstag Mittwoch Donnerstag Freitag Samstag);
      } else {
          @days = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
      }
      $bWday = $days[$bWday];
  }
  
  push(@$aref, $bts+$n." 10_End "          .$edate." ".$etime."\n")   if($edate && $etime);
  push(@$aref, $bts+$n." 15_Timezone "     .$tz."\n")                 if($tz);   
  push(@$aref, $bts+$n." 20_daysLeft "     .$dleft."\n")              if(defined $dleft); 
  push(@$aref, $bts+$n." 25_daysLeftLong " ."in ".$dleft." Tagen\n")  if(defined $dleft); 
  push(@$aref, $bts+$n." 30_Weekday "      .$bWday."\n")              if(defined $bWday);
  
  # Vorwarnzeiten für veränderte Serientermine korrigieren/anpassen
  my $origdtstart  = strftime "%Y%m%dT%H%M%S", localtime($bts);
  my $isRecurrence = 0;
  my $isAlldaychanded;                                                                                       # 0 -> Ganztagsevent wurde in Serienelement geändert in kein Ganztagsevent
  
  for (keys %{$data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}}) {                                 # $isRecurrence = 1 setzen wenn für die aktuelle Originalstartzeit ($bts) eine RECURRENCEID vorliegt -> Veränderung ist vorhanden
      next if(!$data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}{$_});
      $isRecurrence = 1 if($data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}{$_} eq $origdtstart);
  }
  
  my $l   = length (keys %{$data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{TIMEVALUE}});                        # Anzahl Stellen (Länge) des aktuellen VALM TIMEVALUE Hashes
  my $ens = 0;
  
  for (keys %{$data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{TIMEVALUE}}) {
      my $z = $_;
      $val  = encode("UTF-8", $data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{TIMEVALUE}{$z});
      
      if(!$data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}{$z} && !$isRecurrence) {                # wenn keine Veränderung vorhanden ist ({RECURRENCEID}{index}=undef) gelten die Erinnerungszeiten Standarderinnerungszeiten
          ($uts,$td) = evtNotTime ($name,$val,$bts);   
          push(@$aref, $bts+$n." 80_".sprintf("%0$l.0f", $ens)."_notifyDateTime " .$td."\n");
          
          $alarmed = isAlarmed ($ts,$uts,$bts) if(!$alarmed);
      
      } elsif ($data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}{$z} &&
               $data{SSCal}{$name}{vcalendar}{"$uid"}{VALM}{RECURRENCEID}{$z} eq $origdtstart) {
          my ($y, $m, $d)  = $bdate =~ /^(\d{4})-(\d{2})-(\d{2})/x;                                  # Timestamp für Berechnung Erinnerungszeit Begindatum/Zeit ...
          my ($h, $mi, $s) = $btime =~ /^(\d{2}):(\d{2}):(\d{2})/x;
          
          eval { $chts = fhemTimeLocal($s, $mi, $h, $d, $m-1, $y-1900);                              # ... neu aus bdate/btime ableiten wegen Änderung durch Recurrance-id
                 1;
          } or do {
              my $err = (split(" at", $@))[0];
              Log3($name, 3, "$name - ERROR - invalid date/time format in 'writeValuesToArray' detected: $err ");
          };                                       
          
          ($uts,$td) = evtNotTime ($name,$val,$chts);   
          push(@$aref, $bts+$n." 80_".sprintf("%0$l.0f", $ens)."_notifyDateTime " .$td."\n");
          
          $alarmed = isAlarmed ($ts,$uts,$chts) if(!$alarmed);  
          
          $isAlldaychanded = 0;          
      }
      
      $ens++;
  }

  # restliche Keys extrahieren
  for my $p (keys %{$vh}) {
      $vh->{$p} = "" if(!defined $vh->{$p});
      $vh->{$p} = jboolmap($vh->{$p});
      next if($vh->{$p} eq "");
        
      $val = encode("UTF-8", $vh->{$p}); 

      push(@$aref, $bts+$n." 01_Summary "       .$val."\n")       if($p eq "summary");
      push(@$aref, $bts+$n." 03_Description "   .$val."\n")       if($p eq "description"); 
      push(@$aref, $bts+$n." 35_Location "      .$val."\n")       if($p eq "location");
      
      if($p eq "gps") {
          my ($address,$lng,$lat) = ("","","");
          for my $r (keys %{$vh->{gps}}) {
              $vh->{$p}{$r} = "" if(!defined $vh->{$p}{$r});
              next if($vh->{$p}{$r} eq "");
              if ($r eq "address") {
                  $address = encode("UTF-8", $vh->{$p}{$r})           if($vh->{$p}{$r});
              }
              if ($r eq "gps") {
                  $lng = encode("UTF-8", $vh->{$p}{$r}{lng});
                  $lat = encode("UTF-8", $vh->{$p}{$r}{lat});
              }              
          }
          push(@$aref, $bts+$n." 40_gpsAddress "      .$address."\n");
          $val = "lat=".$lat.",lng=".$lng;          
          push(@$aref, $bts+$n." 45_gpsCoordinates "  .$val."\n");
      }
      
      push(@$aref, $bts+$n." 50_isAllday "      .(defined $isAlldaychanded ? $isAlldaychanded : $val)."\n")  if($p eq "is_all_day");
      push(@$aref, $bts+$n." 55_isRepeatEvt "   .$val."\n")                                                  if($p eq "is_repeat_evt");
      
      if($p eq "due") {                                                        
          my (undef,undef,$duedate,$duetime,$duets,undef) = explodeDateTime ($hash, $val, 0, 0, 0);
          push(@$aref, $bts+$n." 60_dueDateTime "  .$duedate." ".$duetime."\n"); 
          push(@$aref, $bts+$n." 65_dueTimestamp " .$duets."\n");
      }
      
      push(@$aref, $bts+$n." 85_percentComplete " .$val."\n")                            if($p eq "percent_complete" && $om eq "todolist");     
      push(@$aref, $bts+$n." 90_calName "         .getCalFromId($hash,$val)."\n")  if($p eq "original_cal_id");

      if($p eq "evt_repeat_setting") {
          for my $r (keys %{$vh->{evt_repeat_setting}}) {
              $vh->{$p}{$r} = "" if(!defined $vh->{$p}{$r});
              next if($vh->{$p}{$r} eq "");
              $val = encode("UTF-8", $vh->{$p}{$r});                 
              push(@$aref, $bts+$n." 70_repeatRule ".$val."\n") if($r eq "repeat_rule");
          }
      }     
      
      push(@$aref, $bts+$n." 95_IcalUID " .$val."\n") if($p eq "ical_uid");
      push(@$aref, $bts+$n." 98_EventId " .$val."\n") if($p eq "evt_id");
  }
  
  $status = "upcoming" if($upcoming);
  $status = "alarmed"  if($alarmed);
  $status = "started"  if($started);
  $status = "ended"    if($ended);
  
  push(@$aref, $bts+$n." 17_Status "        .$status."\n");
  push(@$aref, $bts+$n." 99_---------------------- " ."--------------------------------------------------------------------"."\n");
    
return;
}

#############################################################################################
#   - füllt zentrales $data{SSCal}{$name}{eventlist} Valuehash
#   - erstellt Readings aus $data{SSCal}{$name}{eventlist}
#   - ruft Routine auf um zusätzliche Steuerungsevents zu erstellen
#############################################################################################
sub createReadings { 
  my ($string) = @_;
  my @a        = split("\\|",$string);
  my $name     = $a[0];
  my $hash     = $defs{$name};
  my $rowlist  = $a[1] ? decode_base64($a[1]) : "";
  
  my @abnr;
  
  if ($rowlist) {
      my @row_array = split("_ESC_", $rowlist);
      
      # zentrales Datenhash füllen (erzeugt dadurch sortierbare Keys)
      for my $row (@row_array) {
          chomp $row;
          my @r = split(" ", $row, 3);
          $data{SSCal}{$name}{eventlist}{$r[0]}{$r[1]} = $r[2];
      }
  }
  
  # Readings der Eventliste erstellen 
  if($data{SSCal}{$name}{eventlist}) {
      my $l = length(keys %{$data{SSCal}{$name}{eventlist}});                # Anzahl Stellen des max. Index ermitteln
      
      readingsBeginUpdate($hash);
      $data{SSCal}{$name}{lstUpdtTs} = $hash->{".updateTime"};               # letzte Updatezeit speichern (Unix Format)                    
      
      my $k = 0;
      for my $idx (sort keys %{$data{SSCal}{$name}{eventlist}}) {
          my $idxstr = sprintf("%0$l.0f", $k);                               # Blocknummer erstellen 
          push(@abnr, $idxstr);                                              # Array aller vorhandener Blocknummern erstellen
          
          for my $r (keys %{$data{SSCal}{$name}{eventlist}{$idx}}) {
              if($r =~ /.*Timestamp$/x) {                                     # Readings mit Unix Timestamps versteckt erstellen
                  readingsBulkUpdate($hash, ".".$idxstr."_".$r, $data{SSCal}{$name}{eventlist}{$idx}{$r});
              } else {
                  readingsBulkUpdate($hash, $idxstr."_".$r, $data{SSCal}{$name}{eventlist}{$idx}{$r});
              }
          }
          $k += 1;
      }
      readingsEndUpdate($hash, 1);
        
  } else {
      delReadings($name,0);                                            # alle Kalender-Readings löschen
  }
  
  doCompositeEvents ($name,\@abnr,$data{SSCal}{$name}{eventlist}); # spezifische Controlevents erstellen
  
  checkRetry($name,0);

  $data{SSCal}{$name}{lastUpdate} = FmtDateTime($data{SSCal}{$name}{lstUpdtTs}) if($data{SSCal}{$name}{lstUpdtTs});  

  readingsBeginUpdate         ($hash); 
  readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
  readingsBulkUpdateIfChanged ($hash, "Error",      "none");    
  readingsBulkUpdate          ($hash, "lastUpdate", FmtTime(time));                   
  readingsBulkUpdate          ($hash, "state",      "done");                    
  readingsEndUpdate           ($hash,1); 

  delReadings($name,1) if($data{SSCal}{$name}{lstUpdtTs});                  # Readings löschen wenn Timestamp nicht "lastUpdate"
      
  if(AttrVal($name, "createATDevs", 0)) {
      createAtDevices   ($name,\@abnr,$data{SSCal}{$name}{eventlist});      # automatisch at-Devics mit FHEM/Perl-Kommandos erstellen
  }

return;
}

#############################################################################################
#      erstellt zusätzliche Steuerungsevents um einfach per Notify 
#      Gerätesteuerungen aus Kalender einträgen zu generieren
#      
#      $abnr  - Referenz zum Array aller vorhandener Blocknummern
#      $evref - Referenz zum zentralen Valuehash ($data{SSCal}{$name}{eventlist}) 
#    
#############################################################################################
sub doCompositeEvents { 
  my ($name,$abnr,$evref) = @_;
  my $hash                = $defs{$name}; 
  
  my ($summary,$desc,$begin,$status,$isrepeat,$id,$event);
  
  if(@{$abnr}) {
      my $nrs = join(" ", @{$abnr});
      $event = "compositeBlockNumbers: $nrs";
  } else {
      $event = "compositeBlockNumbers: none";
  }
  CommandTrigger(undef, "$name $event");
  
  for my $bnr (@{$abnr}) {
      $summary    = ReadingsVal($name, $bnr."_01_Summary",      "");
      $desc       = ReadingsVal($name, $bnr."_03_Description",  "");
      $begin      = ReadingsVal($name, $bnr."_05_Begin",        "");
      $status     = ReadingsVal($name, $bnr."_17_Status",       "");
      $isrepeat   = ReadingsVal($name, $bnr."_55_isRepeatEvt",   0);
      $id         = ReadingsVal($name, $bnr."_98_EventId",      "");    

      $begin =~ s/\s/T/x;                                                          # Formatierung nach ISO8601 (YYYY-MM-DDTHH:MM:SS) für at-Device
      
      if($begin) {                                                                # einen Composite-Event erstellen wenn Beginnzeit gesetzt ist
          $event = "composite: $bnr $id $isrepeat $begin $status ".($desc?$desc:$summary);
          CommandTrigger(undef, "$name $event");
      }
  }
     
return;
}

#############################################################################################
#      erstellt automatisch AT-Devices aus Kalendereinträgen die FHEM-Befehle oder
#      Perl-Routinen in "Description" enthalten. 
#      FHEM-Befehle sind in { } und Perl-Routinen in {{ }} einzufassen.
#      
#      $abnr  - Referenz zum Array aller vorhandener Blocknummern
#      $evref - Referenz zum zentralen Valuehash ($data{SSCal}{$name}{eventlist}) 
#    
#############################################################################################
sub createAtDevices { 
  my ($name,$abnr,$evref) = @_;
  my $hash                = $defs{$name}; 
    
  my ($desc,$begin,$status,$isrepeat,$id,@devs,$err,$summary,$location);
  
  my $room  = AttrVal($name, "room", "");
  my $assoc = "";
  readingsDelete($hash,".associatedWith");                                               # Deviceassoziationen löschen
  
  @devs = devspec2array("TYPE=at:FILTER=NAME=SSCal.$name.*"); 
  for (@devs) {
      next if(!$defs{$_});
      Log3($name, 4, "$name - delete device: $_");  
      CommandDelete(undef,$_);
  }            
  
  for my $bnr (@{$abnr}) {
      $summary    = ReadingsVal($name, $bnr."_01_Summary",      "");
      $desc       = ReadingsVal($name, $bnr."_03_Description",  "");
      $begin      = ReadingsVal($name, $bnr."_05_Begin",        "");
      $status     = ReadingsVal($name, $bnr."_17_Status",       "");
      $location   = ReadingsVal($name, $bnr."_35_Location",  $room);                     # Location wird als room gesetzt
      $id         = ReadingsVal($name, $bnr."_98_EventId",      "");  

      if($begin && $status =~ /upcoming|alarmed/x && $desc =~ /^\s*\{(.*)\}\s*$/x) {     # ein at-Device erstellen wenn Voraussetzungen erfüllt
          my $cmd = $1;
          $begin  =~ s/\s/T/x;                                                           # Formatierung nach ISO8601 (YYYY-MM-DDTHH:MM:SS) für at-Devices
          my $ao  = $begin;
          $ao     =~ s/[-:]//gx;
          my $atn = "SSCal.$name.$id.$ao";                                               # Name neues at-Device
          Log3($name, 4, "$name - Command detected. Create device \"$atn\" with type \"at\"."); 
          $err = CommandDefine(undef, "$atn at $begin $cmd");
          if ($err) {
              Log3($name, 1, "$name - Error during create \"$atn\": $err"); 
          } else {
              CommandSetReading(undef, "$atn .associatedWith $name");
              CommandAttr(undef,"$atn room    $location");
              CommandAttr(undef,"$atn alias   $summary");
              CommandAttr(undef,"$atn comment created automatically by SSCal \"$name\" ");
              $assoc .= " $atn";
          }        
      }
  }
  
  CommandSetReading(undef, "$name .associatedWith $assoc");
     
return;
}

####################################################################################################
#                               Abbruchroutine BlockingCall
####################################################################################################
sub blockingTimeout {
  my ($hash,$cause) = @_;
  my $name          = $hash->{NAME}; 
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");    
  
  checkRetry($name,0);

  readingsBeginUpdate         ($hash); 
  readingsBulkUpdateIfChanged ($hash, "Error",     $cause);
  readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
  readingsBulkUpdate          ($hash, "state",     "Error");                    
  readingsEndUpdate           ($hash,1);
  
  delete($hash->{HELPER}{RUNNING_PID});

return;
}

#############################################################################################
#   liefert aus Unix Timestamp Beginn $bts und einer Differenz (Sekunden) das Beginn und
#   Endedatum in der Form:
#   Beginn: SS,MM,HH,Tag(01-31),Monat(01-12),Jahr(YYYY)
#   Ende:   SS,MM,HH,Tag(01-31),Monat(01-12),Jahr(YYYY)
#############################################################################################
sub DTfromStartandDiff {
  my ($bts,$diff) = @_;
              
  my ($nbss, $nbmm, $nbhh, $bmday, $bmonth, $byear, $bWday, $bYday, $bisdst);
  my ($ness, $nemm, $nehh, $emday, $emonth, $eyear, $eWday, $eYday, $eisdst);  
  ($nbss, $nbmm, $nbhh, $bmday, $bmonth, $byear, $bWday, $bYday, $bisdst) = localtime($bts);
  $nbss   = sprintf("%02d", $nbss);
  $nbmm   = sprintf("%02d", $nbmm);
  $nbhh   = sprintf("%02d", $nbhh);
  $bmday  = sprintf("%02d", $bmday);
  $bmonth = sprintf("%02d", $bmonth+1);
  $byear += 1900;

  ($ness, $nemm, $nehh, $emday, $emonth, $eyear, $eWday, $eYday, $eisdst) = localtime($bts+$diff);
  $ness   = sprintf("%02d", $ness);
  $nemm   = sprintf("%02d", $nemm);
  $nehh   = sprintf("%02d", $nehh);
  $emday  = sprintf("%02d", $emday);
  $emonth = sprintf("%02d", $emonth+1);
  $eyear += 1900;
  
return ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear);
}

#############################################################################################
#         extrahiere Key/Value Paare des VCALENDAR
#         $vh  = Referenz zum Kalenderdatenhash
#
#  Ergebis Hash:
#  {
#  'RECURRENCEID' => {
#                      '0' => undef,
#                      '2' => 'TZID=Europe/Berlin:20200222T191500 ',
#                      '1' => 'TZID=Europe/Berlin:20200219T191500 '
#                    },
#  'DTSTART' => {
#                 '0' => 'TZID=Europe/Berlin:20200218T191500',
#                 '1' => 'TZID=Europe/Berlin:20200219T191800',
#                 '2' => 'TZID=Europe/Berlin:20200222T192000'
#               },
#  'EXDATES' => {
#                 '1' => undef,
#                 '2' => undef,
#                 '0' => '20200221T191500 20200220T191500 '
#               },
#  'SEQUENCE' => {
#                  '0' => '4',
#                  '2' => '5',
#                  '1' => '5'
#                }
#  }
#
#  Auswertung mit  $data{SSCal}{$name}{vcalendar}{"$uid"}
#
#############################################################################################
sub extractIcal {                                      ## no critic 'complexity' 
  my ($name,$vh) = @_;
  my $hash       = $defs{$name};
  
  my %vcal;
  my %valm;
  my %icals;
  my ($uid,$k,$v,$n);

  if($vh->{evt_ical}) {
      my @ical = split(/\015\012/x, $vh->{evt_ical});
     
      my $do = 0;
      $n     = 0;
      for (@ical) {
          if($_ =~ m/^([-A-Z]*;)/x) {
              ($k,$v) = split(";", $_, 2);
          } else {
              ($k,$v) = split(":", $_, 2);
          }
          
          $v = "" if(!$v);
          if("$k:$v" eq "BEGIN:VEVENT") {$do = 1;};
          if("$k:$v" eq "END:VEVENT")   {$do = 0; $n++;};
          
          if ($do) {
              $vcal{$n}{UID}         = $v     if($k eq "UID");
              $vcal{$n}{SEQUENCE}    = $v     if($k eq "SEQUENCE");
              
              if($k eq "DTSTART") {
                  $v                 = icalTimecheck ($name,$v);
                  $vcal{$n}{DTSTART} = $v;
              }
              
              if($k eq "DTEND") {
                  $v                 = icalTimecheck ($name,$v);
                  $vcal{$n}{DTEND} = $v;
              }
              
              if($k eq "RECURRENCE-ID") {
                  $v                      = icalTimecheck ($name,$v);
                  $vcal{$n}{RECURRENCEID} = $v;
              }
              
              if($k eq "EXDATE") {
                  $v                  = icalTimecheck ($name,$v);
                  $vcal{$n}{EXDATES} .= $v." ";
              }
          }
      }
  }
  
  $n = 0;
  while ($vh->{evt_notify_setting}[$n]) {
      for (keys %{$vh->{evt_notify_setting}[$n]}) {
          if($_ eq "recurrence-id") {
              $valm{$n}{RECURRENCEID} = icalTimecheck ($name,$vh->{evt_notify_setting}[$n]{$_});
          }

          if($_ eq "time_value") {
              $valm{$n}{TIMEVALUE} = $vh->{evt_notify_setting}[$n]{$_};
          }
      }
      $n++;
  }
  
  $n = 0;
  # VCALENDER Einträge konsolidieren
  while ($vcal{$n}) {
      $uid                           = $vcal{$n}{UID};
      $icals{$uid}{SEQUENCE}{$n}     = $vcal{$n}{SEQUENCE};
      $icals{$uid}{DTSTART}{$n}      = $vcal{$n}{DTSTART};
      $icals{$uid}{DTEND}{$n}        = $vcal{$n}{DTEND};
      $icals{$uid}{EXDATES}{$n}      = trim($vcal{$n}{EXDATES});
      $icals{$uid}{RECURRENCEID}{$n} = $vcal{$n}{RECURRENCEID};
      $n++;
  }
  
  $n = 0;
  # VALARM Einträge konsolidieren
  $uid = $vh->{ical_uid};
  while ($valm{$n}) {
      $icals{$uid}{VALM}{RECURRENCEID}{$n} = $valm{$n}{RECURRENCEID};
      $icals{$uid}{VALM}{TIMEVALUE}{$n}    = $valm{$n}{TIMEVALUE};
      $n++;
  }
  
  $data{SSCal}{$name}{vcalendar} = \%icals;                                    # Achtung: bei asynch Mode ist $data{SSCal}{$name}{vcalendar} nur im BlockingCall verfügbar !!
  
  Log3($name, 5, "$name - VCALENDAR extract of UID \"$uid\":\n".Dumper $data{SSCal}{$name}{vcalendar}{"$uid"}); 
  
return;
}

#############################################################################################
#  Checked und korrigiert Zeitformate aus VCALENDAR um sie mit API-Werten vergleichbar
#  zu machen
#############################################################################################
sub icalTimecheck {
  my $name = shift;
  my $v    = shift;
  
  return if(!$v);
  
  my ($sec,$min,$hour,$mday,$month,$year,$zulu,$tstamp,$d,$t,$isdst,$tz);

  $zulu   = 0;
  $v      = (split(":", $v))[-1] if($v =~ /:/x);
  $zulu   = 3600 if($v =~ /Z$/x);                                       # Zulu-Zeit wenn EXDATE mit "Z" endet -> +1 Stunde
    
  ($d,$t) = split("T", $v);
  $year   = substr($d,0,4);     
  $month  = substr($d,4,2);    
  $mday   = substr($d,6,2);

  if($t) {
      $hour = substr($t,0,2);
      $min  = substr($t,2,2);
      $sec  = substr($t,4,2);
      $t    = $hour.$min.$sec;
  } else {
      $hour = "00";
      $min  = "00";
      $sec  = "00";
  }
  
  eval { $tstamp = fhemTimeLocal($sec, $min, $hour, $mday, $month-1, $year-1900); 
         1;
  } or do {
      my $err = (split(" at", $@))[0];
      Log3($name, 3, "$name - ERROR - invalid date/time format in 'icalTimecheck' detected: $err ");
  };
  $isdst   = (localtime($tstamp))[8];
  $zulu    = 7200 if($isdst && $zulu);                                  # wenn Sommerzeit und Zulu-Zeit -> +1 Stunde
  $tstamp += $zulu; 
  $v       = strftime "%Y%m%dT%H%M%S", localtime($tstamp);

return $v;
}

#############################################################################################
#  Ist Event bevorstehend ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts vor Alarmzeit $ats und vor Startzeit $bts,
#  sonst 0
#############################################################################################
sub isUpcoming {
  my ($ts,$ats,$bts) = @_;

  if($ats) {
      return $ts < $ats ? 1 : 0;
  } else {
      return $ts < $bts ? 1 : 0;
  }
}

#############################################################################################
#  Ist Event Alarmzeit erreicht ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts zwischen Alarmzeit $ats und Startzeit $bts,
#  sonst 0
#############################################################################################
sub isAlarmed {
  my ($ts,$ats,$bts) = @_;
  
return $ats ? (($ats <= $ts && $ts < $bts) ? 1 : 0) : 0;
}

#############################################################################################
#  Ist Event gestartet ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts zwischen Startzeit $bts und Endezeit $ets,
#  sonst 0
#############################################################################################
sub isStarted {
  my ($ts,$bts,$ets) = @_;
  
  return 0 unless($bts);
  return 0 if($ts < $bts);
  
  if(defined($ets)) {
      return 0 if($ts >= $ets);
  }
  
return 1;
}

#############################################################################################
#  Ist Event beendet ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts größer Endezeit $ets,
#  sonst 0
#############################################################################################
sub isEnded {
  my ($ts,$ets) = @_;

  return 0 unless($ets && $ts);
  
return $ets <= $ts ? 1 : 0;
}

#############################################################################################
#                                     check SID
#############################################################################################
sub checkSID { 
  my ($name) = @_;
  my $hash   = $defs{$name};
  
  # SID holen bzw. login
  my $subref = "calOp";
  if(!$hash->{HELPER}{SID}) {
      Log3($name, 3, "$name - no session ID found - get new one");
      login($hash,$subref);
      return;
  }
   
return calOp($name);
}

####################################################################################  
#                                 Login for SID
####################################################################################
sub login {
  my ($hash,$fret)  = @_;
  my $name          = $hash->{NAME};
  my $serveraddr    = $hash->{ADDR};
  my $serverport    = $hash->{PORT};
  my $proto         = $hash->{PROT};
  my $apiauth       = $data{SSCal}{$name}{calapi}{APIAUTH}{NAME};
  my $apiauthpath   = $data{SSCal}{$name}{calapi}{APIAUTH}{PATH};
  my $apiauthmaxver = $data{SSCal}{$name}{calapi}{APIAUTH}{MAX};

  my $lrt = AttrVal($name,"loginRetries",3);
  my ($url,$param);
  
  delete $hash->{HELPER}{SID};
    
  # Login und SID ermitteln
  Log3($name, 4, "$name - --- Start Synology Calendar login ---");
  
  # Credentials abrufen
  my ($success, $username, $password) = getcredentials($hash,0,"credentials");
  
  unless ($success) {
      Log3($name, 2, "$name - Credentials couldn't be obtained successfully - make sure you've set it with \"set $name credentials <username> <password>\"");     
      return;
  }
  
  if($hash->{HELPER}{LOGINRETRIES} >= $lrt) {
      # login wird abgebrochen
      Log3($name, 2, "$name - ERROR - Login or privilege of user $username unsuccessful"); 
      return;
  }

  my $timeout = AttrVal($name,"timeout",60);
  $timeout    = 120 if($timeout < 120);
  Log3($name, 4, "$name - HTTP-Call login will be done with http timeout value: $timeout s");
  
  my $urlwopw;      # nur zur Anzeige bei verbose >= 4 und "showPassInLog" == 0
  
  $url     = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=login&account=$username&passwd=$password&format=sid"; 
  $urlwopw = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=login&account=$username&passwd=*****&format=sid";
  
  AttrVal($name, "showPassInLog", "0") == 1 ? Log3($name, 4, "$name - Call-Out now: $url") : Log3($name, 4, "$name - Call-Out now: $urlwopw");
  $hash->{HELPER}{LOGINRETRIES}++;
  
  $param = {
               url      => $url,
               timeout  => $timeout,
               hash     => $hash,
               user     => $username,
               funcret  => $fret,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&FHEM::SSCal::login_return
           };
  HttpUtils_NonblockingGet ($param);
  
return;
}

sub login_return {
  my ($param, $err, $myjson) = @_;
  my $hash     = $param->{hash};
  my $name     = $hash->{NAME};
  my $username = $param->{user};
  my $fret     = $param->{funcret};
  my $subref   = \&$fret;
  my $success; 

  # Verarbeitung der asynchronen Rückkehrdaten aus sub "login_nonbl"
  if ($err ne "") {
      # ein Fehler bei der HTTP Abfrage ist aufgetreten
      Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
      readingsSingleUpdate($hash, "Error", $err, 1);                               
        
      return login($hash,$fret);
   
   } elsif ($myjson ne "") {        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - no JSON-Data returned while login: ".$myjson);
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON decoded: ". Dumper $data);
   
        $success = $data->{'success'};
        
        if ($success) {
            # login war erfolgreich     
            my $sid = $data->{data}{sid};
             
            # Session ID in hash eintragen
            $hash->{HELPER}{SID} = $sid;
       
            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash,"Errorcode","none");
            readingsBulkUpdate  ($hash,"Error","none");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 4, "$name - Login of User $username successful - SID: $sid");
            
            return &$subref($name);
        
        } else {          
            # Errorcode aus JSON ermitteln
            my $errorcode = $data->{error}{code};
       
            # Fehlertext zum Errorcode ermitteln
            my $error = experrorauth($hash,$errorcode);

            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash,"Errorcode", $errorcode);
            readingsBulkUpdate  ($hash,"Error",     $error);
            readingsBulkUpdate  ($hash,"state",     "error");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return login($hash,$fret);
       }
   }
   
return login($hash,$fret);
}

###################################################################################  
#                                Funktion logout
###################################################################################
sub logout {
   my ($hash)        = @_;
   my $name          = $hash->{NAME};
   my $serveraddr    = $hash->{ADDR};
   my $serverport    = $hash->{PORT};
   my $proto         = $hash->{PROT};
   my $apiauth       = $data{SSCal}{$name}{calapi}{APIAUTH}{NAME};
   my $apiauthpath   = $data{SSCal}{$name}{calapi}{APIAUTH}{PATH};
   my $apiauthmaxver = $data{SSCal}{$name}{calapi}{APIAUTH}{MAX};
   my $sid           = $hash->{HELPER}{SID};
   my ($url,$param);
    
   Log3($name, 4, "$name - --- Start Synology Calendar logout ---");
    
   my $timeout = AttrVal($name,"timeout",60);
   $timeout    = 60 if($timeout < 60);
   Log3($name, 4, "$name - HTTP-Call logout will be done with http timeout value: $timeout s");
  
   $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=logout&_sid=$sid"; 

   $param = {
            url      => $url,
            timeout  => $timeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&FHEM::SSCal::logout_return
            };
   
   HttpUtils_NonblockingGet ($param);
  
return;  
}

sub logout_return {  
   my ($param, $err, $myjson) = @_;
   my $hash                   = $param->{hash};
   my $name                   = $hash->{NAME};
   my $sid                    = $hash->{HELPER}{SID};
   my $OpMode                 = $hash->{OPMODE};
   my ($success, $username, $password) = getcredentials($hash,0,"credentials");
   my ($data,$error,$errorcode);
  
   if ($err ne "") {
       # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - ERROR message: $err"); 

       readingsBeginUpdate         ($hash); 
       readingsBulkUpdateIfChanged ($hash, "Error",       $err);
       readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
       readingsBulkUpdate          ($hash, "state",    "Error");                    
       readingsEndUpdate           ($hash,1);      
   
   } elsif ($myjson ne "") {       
       # Evaluiere ob Daten im JSON-Format empfangen wurden
       ($hash,$success,$myjson) = evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);       
            return;
        }
        
       $data = decode_json($myjson);
        
       # Logausgabe decodierte JSON Daten
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};

       if ($success) {
           # die Logout-URL konnte erfolgreich aufgerufen werden                        
           Log3($name, 2, "$name - Session of User \"$username\" terminated - session ID \"$sid\" deleted");
             
       } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{error}->{code};

           # Fehlertext zum Errorcode ermitteln
           $error = experrorauth($hash,$errorcode); 

           Log3($name, 2, "$name - ERROR - Logout of User $username was not successful, however SID: \"$sid\" has been deleted. Errorcode: $errorcode - $error");
       }
   }  
   
   # Session-ID aus Helper-hash löschen
   delete $hash->{HELPER}{SID};
   
   CancelDelayedShutdown($name);
   
return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
###############################################################################
sub evaljson { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  my ($error,$errorcode);

  eval {decode_json($myjson)} or do {
          $success = 0;
          
          $errorcode = "900";

          # Fehlertext zum Errorcode ermitteln
          $error = experror($hash,$errorcode);
            
          readingsBeginUpdate         ($hash);
          readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
          readingsBulkUpdateIfChanged ($hash, "Error",     $error);
          readingsBulkUpdate          ($hash, "state",     "Error");
          readingsEndUpdate           ($hash, 1);  
  };
  
return ($hash,$success,$myjson);
}

##############################################################################
#  Auflösung Errorcodes Calendar AUTH API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub experrorauth {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($errauthlist{"$errorcode"})) {
      $error = "Value of errorcode \"$errorcode\" not found."; 
      return ($error);
  }

  $error = $errauthlist{"$errorcode"};
  
return ($error);
}

##############################################################################
#  Auflösung Errorcodes Calendar API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub experror {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($errlist{"$errorcode"})) {
      $error = "Value of errorcode \"$errorcode\" not found."; 
      return ($error);
  }

  $error = $errlist{"$errorcode"};
  
return ($error);
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersion {
  my ($sseq,@versions) = @_;

  return "" if(!@versions);
  
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

######################################################################################
#                            credentials speichern
######################################################################################
sub setcredentials {
    my ($hash, @credentials) = @_;
    my $name                 = $hash->{NAME};
    my ($success, $credstr, $username, $passwd, $index, $retcode);
    my (@key,$len,$i);   
    
    my $ao   = "credentials";
    $credstr = encode_base64(join('!_ESC_!', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index   = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving Credentials - $retcode");
        $success = 0;
    } else {
        ($success, $username, $passwd) = getcredentials($hash,1,$ao);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
    }

return ($success);
}

######################################################################################
#                             credentials lesen
######################################################################################
sub getcredentials {
    my ($hash,$boot, $ao) = @_;
    my $name              = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot) {
        # mit $boot=1 credentials von Platte lesen und als scrambled-String in RAM legen
        $index               = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read credentials from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            # beim Boot scrambled credentials in den RAM laden
            $hash->{HELPER}{CREDENTIALS} = $credstr;
    
            # "CREDENTIALS" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{CREDENTIALS} = "Set";
            $success = 1;
        }
    
    } else {
        # boot = 0 -> credentials aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{CREDENTIALS};
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "",  
            map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $credstr;   
            # Ende Descramble-Routine
            
            ($username, $passwd) = split("!_ESC_!",decode_base64($credstr));
            
            my $logcre = AttrVal($name, "showPassInLog", "0") == 1 ? $passwd : "********";
        
            Log3($name, 4, "$name - credentials read from RAM: $username $logcre");
        
        } else {
            Log3($name, 2, "$name - credentials not set in RAM !");
        }
    
        $success = (defined($passwd)) ? 1 : 0;
    }

return ($success, $username, $passwd);        
}

#############################################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
#############################################################################################
sub trim {
  my $str = shift;
  
  return if(!$str);
  $str =~ s/^\s+|\s+$//gx;

return ($str);
}

#############################################################################################
#                        Länge Senedequeue updaten          
#############################################################################################
sub updQLength {
  my ($hash,$rst) = @_;
  my $name        = $hash->{NAME};
 
  my $ql = keys %{$data{SSCal}{$name}{sendqueue}{entries}};
  
  readingsBeginUpdate($hash);                                             
  readingsBulkUpdate ($hash, "QueueLength", $ql);                                  # Länge Sendqueue updaten
  readingsEndUpdate  ($hash,1);
  
  my $head = "next planned SendQueue start:";
  if($rst) {                                                                       # resend Timer gesetzt
      $hash->{RESEND} = $head." ".FmtDateTime($rst);
  } else {
      $hash->{RESEND} = $head." immediately by next entry";
  }

return;
}

#############################################################################################
#              Start- und Endezeit ermitteln
#############################################################################################
sub timeEdge {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my ($error,$t1,$t2) = ("","","");
  my ($mday,$mon,$year);
  
  my $t    = time();
  my $corr = 86400;                                                                  # Korrekturbetrag 
  
  my $cutOlderDays = AttrVal($name, "cutOlderDays", 5)."d";
  my $cutLaterDays = AttrVal($name, "cutLaterDays", 5)."d";

  # start of time window
  ($error,$t1) = GetSecondsFromTimeSpec($cutOlderDays);
  if($error) {
      Log3 $hash, 2, "$name: attribute cutOlderDays: $error";
      return ($error,"","");
  } else {
      $t1 = $t-$t1;
      (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime($t1);       # Istzeit Ableitung
      $t1 = fhemTimeLocal(00, 00, 00, $mday, $mon, $year);
  }

  # end of time window
  ($error,$t2) = GetSecondsFromTimeSpec($cutLaterDays);
  if($error) {
      Log3 $hash, 2, "$name: attribute cutLaterDays: $error";
      return ($error,"","");
  } else {
      $t2 = $t+$t2+$corr;
      (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime($t2);       # Istzeit Ableitung
      $t2 = fhemTimeLocal(00, 00, 00, $mday, $mon, $year);
  }

return ("",$t1,$t2);
}

#############################################################################################
#              Erinnerungstermin relativ zur Beginnzeit $bts ermitteln
#              Alarmformat:  'time_value' => '-P2D'
#                            'time_value' => '-PT1H'
#                            'time_value' => '-PT5M'
#                            'time_value' => 'PT0S'
#                            'time_value' => 'PT6H'
#                            'time_value' => '-P1DT15H'
#
#              Rückgabe:    $uts: Unix-Timestamp
#                           $ts:  Timstamp als YYYY-MM-DD HH:MM:SS
#                 
#############################################################################################
sub evtNotTime {
  my ($name,$tv,$bts) = @_;
  my $hash            = $defs{$name};
  my ($uts,$ts)       = ("","");
  my ($corr);
  
  return ("","") if(!$tv || !$bts);
  
  if($tv =~ /^-P(\d)+D$/x) {
      $corr = -1*$1*86400;
  } elsif ($tv =~ /^-PT(\d+)H$/x) {
      $corr = -1*$1*3600;
  } elsif ($tv =~ /^-PT(\d+)M$/x) {
      $corr = -1*$1*60;
  } elsif ($tv =~ /^PT(\d+)S$/x) {
      $corr = $1;
  } elsif ($tv =~ /^PT(\d+)M$/x) {
      $corr = $1*60;
  } elsif ($tv =~ /^PT(\d+)H$/x) {
      $corr = $1*3600;
  } elsif ($tv =~ /^-P(\d)+DT(\d+)H$/x) {
      $corr = -1*($1*86400 + $2*3600);
  }
  
  if(defined $corr) {
      $uts = $bts+$corr;
      $ts  = FmtDateTime($uts);
  }
  
return ($uts,$ts);
}

#############################################################################################
#              Unix timestamp aus Zeitdifferenz berechnen
#############################################################################################
sub GetSecondsFromTimeSpec {
  my ($tspec) = @_;

  # days
  if($tspec =~ m/^([0-9]+)d$/x) {
    return ("", $1*86400);
  }

  # seconds
  if($tspec =~ m/^([0-9]+)s?$/x) {
    return ("", $1);
  }

  # D:HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])$/x) {
    return ("", $4+60*($3+60*($2+24*$1)));
  }

  # HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/x) {
    return ("", $3+60*($2+(60*$1)));
  }

  # HH:MM
  if($tspec =~ m/^([0-9]+):([0-5][0-9])$/x) {
    return ("", 60*($2+60*$1));
  }

return ("Wrong time specification $tspec", undef);
}

#############################################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
#############################################################################################
sub getclhash {      
  my ($hash,$nobgd) = @_;
  my $name          = $hash->{NAME};
  my $ret;
  
  if($nobgd) {
      # nur übergebenen CL-Hash speichern, 
      # keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
      $hash->{HELPER}{CL}{1} = $hash->{CL};
      return;
  }

  if (!defined($hash->{CL})) {
      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
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
  } else {
      # übergebenen CL-Hash in Helper eintragen
      $hash->{HELPER}{CL}{1} = $hash->{CL};
  }
      
  # Clienthash auflösen zur Fehlersuche (aufrufende FHEMWEB Instanz
  if (defined($hash->{HELPER}{CL}{1})) {
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
          Log3($name, 4, "$name - Clienthash number: $k");
          while (my ($key,$val) = each(%{$hash->{HELPER}{CL}{$k}})) {
              $val = $val?$val:" ";
              Log3($name, 4, "$name - Clienthash: $key -> $val");
          }
      }
  } else {
      Log3($name, 2, "$name - Clienthash was neither delivered nor created !");
      $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for function.";
  }
  
return ($ret);
}

################################################################
#         Kalendername aus Kalender-Id liefern
################################################################
sub getCalFromId {      
  my ($hash,$cid) = @_;
  my $cal         = "";
  $cid            = trim($cid);
  
  for my $calname (keys %{$hash->{HELPER}{CALENDARS}}) {
      my $oid = $hash->{HELPER}{CALENDARS}{"$calname"}{id};
      next if(!$oid);
      $oid = trim($oid);
      if($oid eq $cid) {
          $cal = $calname;
          last;          
      }      
  }

return $cal;
}

################################################################
#   addiert Anzahl ($n) Sekunden ($s) zu $t1 
################################################################
sub plusNSeconds {
  my ($t1, $s, $n) = @_;
  
  $n     = 1 unless defined($n);
  my $t2 = $t1+$n*$s;
  
return $t2;
}

################################################################
#    alle Readings außer excludierte löschen
#    $respts -> Respect Timestamp 
#               wenn gesetzt, wird Reading nicht gelöscht
#               wenn Updatezeit identisch zu "lastUpdate"
################################################################
sub delReadings {      
  my ($name,$respts) = @_;
  my ($lu,$rts,$excl);
  
  $excl  = "Error|Errorcode|QueueLength|state|nextUpdate";
  $excl .= "|lastUpdate" if($respts);
  
  my @allrds = keys%{$defs{$name}{READINGS}};
  for my $key(@allrds) {
      if($respts) {
          $lu  = $data{SSCal}{$name}{lastUpdate};
          $rts = ReadingsTimestamp($name, $key, $lu);
          next if($rts eq $lu);
      }
      delete($defs{$name}{READINGS}{$key}) if($key !~ m/^$excl$/x);
  }
  
return;
}

#############################################################################################
#          Datum/Zeit extrahieren
#    Eingangsformat: TZID=Europe/Berlin:20191216T133000   oder
#                    20191216T133000
#    Rückgabe:       invalid, Zeitzone, Date(YYYY-MM-DD), Time (HH:MM:SS), UnixTimestamp
#                    (invalid =1 wenn Datum ungültig, ist nach RFC 5545 diese Wiederholung 
#                                zu ignorieren und auch nicht zu zählen !)
#    $dtstart:       man benötigt originales DTSTART für den Vergleich bei Recurring Terminen
#############################################################################################
sub explodeDateTime {                                    ## no critic 'complexity'
  my ($hash,$dt,$isallday,$uid,$dtstart) = @_;
  my $name                 = $hash->{NAME};
  my ($tz,$t)              = ("","");
  my ($d,$tstamp)          = ("",0);
  my $invalid              = 0;
  my $corrsec              = 0;                          # Korrektursekunde
  my $excl                 = 0;                          # 1 wenn der Eintrag exkludiert werden soll
  
  my ($sec,$min,$hour,$mday,$month,$year,$checkbegin,$changed,$changet,$changedt,$z);
  
  return ($invalid,$tz,$d,$t,$tstamp,$excl) if(!$dt);
  
  $corrsec = 1 if($isallday);                            # wenn Ganztagsevent, Endetermin um 1 Sekunde verkürzen damit Termin am selben Tag 23:59:59 endet (sonst Folgetag 00:00:00)          
  
  if($dt =~ /^TZID=.*$/x) {
      ($tz,$dt) = split(":", $dt);
      $tz       = (split("=", $tz))[1];
  }
  
  if($dtstart) {
      $dtstart = (split(":", $dtstart))[-1] if($dtstart =~ /:/x);
      
      # check ob recurring date excluded werden muss (Serienelement gelöscht)
      my $exdates = $data{SSCal}{$name}{vcalendar}{"$uid"}{EXDATES}{0};   
      my %seen;
      if($exdates) {
          my @exd = split(" ", $exdates);  
          # grep { !$seen{$_}++ } @exd;
          for (@exd) { $seen{$_}++ if(!$seen{$_}) };
      }
      $excl = 1 if($seen{$dtstart});                                            # check erfolgreich -> exclude recurring date weil (Serienelement gelöscht)
  
      # prüfen ob Serienelement verändert wurde
      if($dt eq $dtstart) {$checkbegin = 1} else {$checkbegin = 0};             
      if ($checkbegin) {
          # prüfen ob DTSTART verändert
          for (keys %{$data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}}) {
              next if(!$data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}{$_});
              $z = $_ if($data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}{$_} eq $dtstart);
          }
          if($z) {
              $changedt = $data{SSCal}{$name}{vcalendar}{"$uid"}{DTSTART}{$z};
              my ($y, $m, $dd, $h, $mi, $s) = $changedt =~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/x;
              $changed  = $y."-".$m."-".$dd;                                    # einmalig geändertes Datum
              $changet  = $h.":".$mi.":".$s;                                    # einmalig geänderte Zeit
          }
      } else {
          # prüfen ob DTEND verändert
          for (keys %{$data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}}) {
              next if(!$data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}{$_});
              $z = $_ if($data{SSCal}{$name}{vcalendar}{"$uid"}{RECURRENCEID}{$_} eq $dtstart);
          }
          if($z) {
              $changedt = $data{SSCal}{$name}{vcalendar}{"$uid"}{DTEND}{$z};
              my ($y, $m, $dd, $h, $mi, $s) = $changedt =~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/x;
              $changed  = $y."-".$m."-".$dd;                                    # einmalig geändertes Datum
              $changet  = $h.":".$mi.":".$s;                                    # einmalig geänderte Zeit
          }      
      }
  }
  
  ($d,$t) = split("T", $dt);
  
  $year  = substr($d,0,4);     
  $month = substr($d,4,2);    
  $mday  = substr($d,6,2);
  $d     = $year."-".$month."-".$mday;
  
  if($t) {
      $hour  = substr($t,0,2);
      $min   = substr($t,2,2);
      $sec   = substr($t,4,2);
      $t     = $hour.":".$min.":".$sec;
  } else {
      $hour  = "00";
      $min   = "00";
      $sec   = "00";
      $t     = "00:00:00";
  }
  
  unless ( ($d." ".$t) =~ /^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})/x) {
      Log3($name, 2, "$name - ERROR - invalid DateTime format for explodeDateTime: $d $t");
  }
  
  if ($corrsec) {                              # Termin um 1 Sekunde verkürzen damit Termin am selben Tag 23:59:59 endet (sonst Folgetag 00:00:00)         
      eval { $tstamp = fhemTimeLocal($sec, $min, $hour, $mday, $month-1, $year-1900); 
             1;
      } or do {
          my $err = (split(" at", $@))[0];
          Log3($name, 3, "$name - WARNING - invalid date/time format detected: $err. It will be ignored.");
          $invalid = 1;
      };
      
      if(!$invalid) {
          $tstamp -= $corrsec;
          my $nt   = FmtDateTime($tstamp);
          ($year, $month, $mday, $hour, $min, $sec) = $nt =~ /^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})/x;
          $d                                        = $year."-".$month."-".$mday;
          $t                                        = $hour.":".$min.":".$sec;
      }
  }
  
  eval { $tstamp = fhemTimeLocal($sec, $min, $hour, $mday, $month-1, $year-1900); 
         1;
  } or do {
      my $err = (split(" at", $@))[0];
      Log3($name, 3, "$name - WARNING - invalid format of recurring event: $err. It will be ignored due to RFC 5545 standard.");
      $invalid = 1;
  };

  $d = $changed // $d;                               # mit einmalig geänderten Datum ersetzen
  $t = $changet // $t;                               # mit einmalig geänderter Zeit ersetzen
  
return ($invalid,$tz,$d,$t,$tstamp,$excl);
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SSCal}{META}}
      if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 57_SSCal.pm 21776 2020-04-25 19:53:14Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 57_SSCal.pm 21776 2020-04-25 19:53:14Z DS_Starter $ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );       ## no critic 'VERSION'                                      
      }
  } else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub jboolmap {
  my ($bool) = @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool ? 1 : 0;
  }
  
return $bool;
}

#############################################################################################
#   Kalenderliste als HTML-Tabelle zurückgeben
#############################################################################################
sub calAsHtml {                                                                 ## no critic 'complexity'
  my ($name,$FW_wname) = @_;
  my $hash             = $defs{$name};  
  my $lang             = AttrVal("global", "language", "EN");
  my $mi               = AttrVal($name, "tableColumnMap", "icon");
  
  my ($symbol,$begin,$begind,$begint,$end,$endd,$endt,$summary,$location,$status,$desc,$gps,$gpsa,$gpsc); 
  my ($di,$cal,$completion,$tz,$dleft,$dleftlong,$weekday,$edleft,$id,$isallday);
  my ($colSymbolAlign,$colBeginAlign,$colEndAlign,$colDayAlign,$colDLongAlign,$colWeekdayAlign,$colTzAlign,$colSummaryAlign,$colDescAlign,$colStatusAlign,$colCompAlign,$colLocAlign,$colMapAlign,$colCalAlign,$colIdAlign);

  # alle Readings in Array einlesen
  my @allrds = keys%{$defs{$name}{READINGS}};

  # Sprachsteuerung
  my $de = 0;
  if($lang eq "DE") {$de = 1};
  
  # Entscheidung ob Tabelle für Small Screen optimiert
  my $small = 0;
  if ($FW_wname && $hash->{HELPER}{tableSpecs}{smallScreenStyles}) {                 # Aufruf durch FHEMWEB und smallScreen-Eigenschaft gesetzt
      my %specs;
      my $FW_style = AttrVal($FW_wname, "stylesheetPrefix", "default");
      my @scspecs  = split(",", $hash->{HELPER}{tableSpecs}{smallScreenStyles});     # Eigenschaft smallScreen in Array lesen
      # grep { !$specs{$_}++ } @scspecs; 
      for (@scspecs) { $specs{$_}++ if(!$specs{$_}) };
      $small = 1 if($specs{$FW_style});                                              # Tabelle für small-Style anpassen                                   
  }
  
  # Auswahl der darzustellenden Tabellenfelder
  my %seen;
  my @cof = split(",", AttrVal($name, "tableFields", "Begin,End,Summary,Status,Location"));
  grep { !$seen{$_}++ } @cof; 

  # Gestaltung Headerzeile
  my $nohead  = 0;                                                             # Unterdrückung Anzeige Headerzeile: 0 - nein, 1 - Ja  
  eval { $nohead = evalTableSpecs ( {
                                      href    => $hash,
                                      def     => $nohead,
                                      base    => $hash->{HELPER}{tableSpecs}{cellStyle}{noHeader},
                                      bnr     => "",
                                      readref => \@allrds,
                                      rdtype  => "string" 
                                    } 
                                  ); 1;
  } or do {
      Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"cellStyle\": $@");
  };
    
  my $headalign = "center";                                                      # Ausrichtung der Headerzeile, default: center
  eval { $headalign = evalTableSpecs ( {
                                         href    => $hash,
                                         def     => $headalign,
                                         base    => $hash->{HELPER}{tableSpecs}{cellStyle}{headerAlign},
                                         bnr     => "",
                                         readref => \@allrds,
                                         rdtype  => "string"
                                       }
                                     ); 1;
  } or do {
      Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"cellStyle\": $@");
  };
   
  $headalign = "cal".$headalign;

  # Tabelle erstellen
  my $out  = "<html>";  
  $out    .= "<style>TD.cal       {padding-left:10px; padding-right:10px; border-spacing:5px; margin-left:auto; margin-right:auto;}</style>";
  $out    .= "<style>TD.calbold   {font-weight: bold;}  </style>";
  $out    .= "<style>TD.calright  {text-align: right;}  </style>";
  $out    .= "<style>TD.calleft   {text-align: left;}   </style>";
  $out    .= "<style>TD.calcenter {text-align: center;} </style>";  
  $out    .= "<style>TD.calw150   {width: 150px;}       </style>";
  
  # Wenn Table class=block alleine steht, zieht es bei manchen Styles die Ausgabe auf 100% Seitenbreite
  # lässt sich durch einbetten in eine zusätzliche Table roomoverview eindämmen
  $out    .= "<table class='roomoverview'>";
  $out    .= "<tr>";
  $out    .= "<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px'>";
  
  $out    .= "<table class='block'>";
  
  # Tabellenheader
  if(!$nohead) {
      $out    .= "<tr class='odd'>";
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Symbol'             :'Symbol')."              </td>" if($seen{Symbol});
      if ($small) {                                                                 # nur ein Datumfeld umbrechbar
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'Start'             :'Begin')."               </td>" if($seen{Begin});
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'Ende'              :'End')."                 </td>" if($seen{End});
      } else {
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'Start'             :'Begin')."               </td>" if($seen{Begin});
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'----'              :'----')."                </td>" if($seen{Begin});
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'Ende'              :'End')."                 </td>" if($seen{End});
          $out .= "<td class='cal calbold $headalign'> ".(($de)?'----'              :'----')."                </td>" if($seen{End});  
      }
      
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Resttage'           :'Days left')."           </td>" if($seen{DaysLeft});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Terminziel'         :'Goal')."                </td>" if($seen{DaysLeftLong});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Wochentag'          :'Weekday')."             </td>" if($seen{Weekday});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Zeitzone'           :'Timezone')."            </td>" if($seen{Timezone});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Zusammenfassung'    :'Summary')."             </td>" if($seen{Summary});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Beschreibung'       :'Description')."         </td>" if($seen{Description});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Status'             :'State')."               </td>" if($seen{Status});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Erfüllung&nbsp;(%)' :'Completion&nbsp;(%)')." </td>" if($seen{Completion});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Ort'                :'Location')."            </td>" if($seen{Location});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Karte'              :'Map')."                 </td>" if($seen{Map});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'Kalender'           :'Calendar')."            </td>" if($seen{Calendar});
      $out    .= "<td class='cal calbold $headalign'> ".(($de)?'ID'                 :'ID')."                  </td>" if($seen{EventId});
      $out    .= "</tr>";
  }
  
  my $maxbnr;
  for my $key (keys %{$defs{$name}{READINGS}}) {
      my ($bno) = $key =~ /^(\d+)_\d+_EventId$/x;
      next if(!defined $bno);
      $maxbnr = $bno if(!$maxbnr || $bno > $maxbnr);
  }

  return "" if(!defined $maxbnr);
  
  my $l = length($maxbnr);
  
  my $k;
  for ($k=0;$k<=$maxbnr;$k++) {
      my $bnr = sprintf("%0$l.0f", $k);                               # Prestring erstellen
      last if(!ReadingsVal($name, $bnr."_98_EventId", ""));           # keine Ausgabe wenn es keine EventId mit Blocknummer 0 gibt -> kein Event/Aufgabe vorhanden
      
      ($begind,$begint,$endd,$endt,$gps) = ("","","","","");
      
      # Readings auslesen
      $summary    = ReadingsVal($name, $bnr."_01_Summary",         "");
      $desc       = ReadingsVal($name, $bnr."_03_Description",     "");
      $begin      = ReadingsVal($name, $bnr."_05_Begin",           "");
      $end        = ReadingsVal($name, $bnr."_10_End",             "");
      $tz         = ReadingsVal($name, $bnr."_15_Timezone",        "");
      $status     = ReadingsVal($name, $bnr."_17_Status",          "");
      $dleft      = ReadingsVal($name, $bnr."_20_daysLeft",        "");
      $dleftlong  = ReadingsVal($name, $bnr."_25_daysLeftLong",    "");
      $weekday    = ReadingsVal($name, $bnr."_30_Weekday",         "");
      $location   = ReadingsVal($name, $bnr."_35_Location",        "");
      $gpsa       = ReadingsVal($name, $bnr."_40_gpsAddress",      "");
      $gpsc       = ReadingsVal($name, $bnr."_45_gpsCoordinates",  "");
      $completion = ReadingsVal($name, $bnr."_85_percentComplete", "");
      $cal        = ReadingsVal($name, $bnr."_90_calName",         "");
      $id         = ReadingsVal($name, $bnr."_98_EventId",         "");
      $isallday   = ReadingsVal($name, $bnr."_50_isAllday",        "");
      
      if($gpsc) {
          my $micon;
          if ($mi eq "icon") {
              # Karten-Icon auswählen
              $di           = "it_i-net";
              eval { $micon = evalTableSpecs ( {
                                                 href    => $hash,
                                                 def     => $di,
                                                 base    => $hash->{HELPER}{tableSpecs}{columnMapIcon},
                                                 bnr     => $bnr,
                                                 readref => \@allrds,
                                                 rdtype  => "image" 
                                               }
                                             ); 1;
              } or do {
                  Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnMapIcon\": $@")
              };
                         
          } elsif ($mi eq "data") {
              $micon = join(" ", split(",", $gpsc));
              
          } elsif ($mi eq "text") {
              # Karten-Text auswählen
              my $dt        = "link";
              eval { $micon = evalTableSpecs ( {
                                                 href    => $hash,
                                                 def     => $dt,
                                                 base    => $hash->{HELPER}{tableSpecs}{columnMapText},
                                                 bnr     => $bnr,
                                                 readref => \@allrds,
                                                 rdtype  => "string" 
                                               }
                                             ); 1;
              } or do {
                  Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnMapText\": $@");
              };
              
          } else {
              $micon = "";
          }
          
          my ($lat,$lng) = split(",", $gpsc);
          $lat           = (split("=", $lat))[1];
          $lng           = (split("=", $lng))[1];
                                             
          # Kartenanbieter auswählen
          my $up     = "GoogleMaps";
          eval { $up = evalTableSpecs ( {
                                          href    => $hash,
                                          def     => $up,
                                          base    => $hash->{HELPER}{tableSpecs}{columnMapProvider},
                                          bnr     => $bnr,
                                          readref => \@allrds,
                                          rdtype  => "string"
                                        }
                                      ); 1;
          } or do {
              Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnMapProvider\": $@");
          };
          
          if ($up eq "GoogleMaps") {                                                                                       # Kartenprovider: Google Maps
              $gps = "<a href='https://www.google.de/maps/place/$gpsa/\@$lat,$lng' target='_blank'> $micon </a>";          
          } elsif ($up eq "OpenStreetMap") {
              $gps = "<a href='https://www.openstreetmap.org/?mlat=$lat&mlon=$lng&zoom=14' target='_blank'> $micon </a>";  # Kartenprovider: OpenstreetMap          
          }
      }
      
      if($begin ne "") {                                             # Datum sprachabhängig konvertieren bzw. heute/morgen setzen
          my ($ny,$nm,$nd,undef) = split(/[\s-]/x, TimeNow());         # Jetzt
          my ($by,$bm,$bd,$bt)   = split(/[\s-]/x, $begin);
          my ($ey,$em,$ed,$et)   = split(/[\s-]/x, $end);
          my $ntimes             = fhemTimeLocal(00, 00, 00, $nd, $nm-1, $ny-1900);
          my $btimes             = fhemTimeLocal(00, 00, 00, $bd, $bm-1, $by-1900);
          my $etimes             = fhemTimeLocal(00, 00, 00, $ed, $em-1, $ey-1900);
          
          if($de) {
              $begind = "$bd.$bm.$by";
              $endd   = "$ed.$em.$ey";    
          } else {
              $begind = "$by-$bm-$bd";
              $endd   = "$ey-$em-$ed";            
          }
          my($a,$b,undef) =  split(":", $bt);
          $begint         =  "$a:$b";
          my($c,$d,undef) =  split(":", $et);
          $endt           =  "$c:$d";
          
          $edleft = "";
          
          if($etimes >= $ntimes) {
              $edleft = int(($etimes - $ntimes)/86400);
          }       

          $begind = (($de)?'heute ':'today ')      if($dleft  eq "0");
          $endd   = (($de)?'heute ':'today ')      if($edleft eq "0");
          $begind = (($de)?'morgen ':'tomorrow ')  if($dleft  eq "1");
          $endd   = (($de)?'morgen ':'tomorrow ')  if($edleft eq "1");

          if (($begind eq $endd) && !$isallday) {
              $endd   = "";                                      # bei "Ende" nur Uhrzeit angeben wenn Termin am gleichen Tag beginnt/endet aber kein Ganztagstermin ist    
          } elsif (($begind eq $endd) && $isallday) {
              $begint = "";
              $endt   = "";             
          }
      }

      # Icon für Spalte Resttage spezifizieren
      eval { $dleft = evalTableSpecs ( {
                                         href    => $hash,
                                         def     => $dleft,
                                         base    => $hash->{HELPER}{tableSpecs}{columnDaysLeftIcon},
                                         bnr     => $bnr,
                                         readref => \@allrds,
                                         rdtype  => "image"
                                       }
                                     ); 1;
      } or do {
          Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnDaysLeftIcon\": $@");
      };
            
      # Icon für Spalte Status spezifizieren
      eval { $status = evalTableSpecs ( {
                                          href    => $hash,
                                          def     => $status,
                                          base    => $hash->{HELPER}{tableSpecs}{columnStateIcon},
                                          bnr     => $bnr,
                                          readref => \@allrds,
                                          rdtype  => "image"
                                        }
                                      ); 1;
      } or do {
          Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnStateIcon\": $@");
      };
      
      # Icon für Spalte "Symbol" bestimmen
      $di            = ($hash->{MODEL} eq "Diary") ? "time_calendar" : "time_note";
      eval { $symbol = evalTableSpecs ( {
                                          href    => $hash,
                                          def     => $di,
                                          base    => $hash->{HELPER}{tableSpecs}{columnSymbolIcon},
                                          bnr     => $bnr,
                                          readref => \@allrds,
                                          rdtype  => "image"
                                        }
                                      ); 1;
      } or do {
          Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"columnSymbolIcon\": $@");
      };
      
      # Gestaltung Spaltentext
      my $coldefalign     = "center";                               # Ausrichtung der Spalte, default: center
      eval { 
           $coldefalign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnAlign}             ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colSymbolAlign  = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnSymbolAlign}       ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colBeginAlign   = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnBeginAlign}        ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colEndAlign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnEndAlign}          ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colDayAlign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnDaysLeftAlign}     ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colDLongAlign   = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnDaysLeftLongAlign} ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colWeekdayAlign = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnWeekdayAlign}      ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colTzAlign      = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnTimezoneAlign}     ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colSummaryAlign = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnSummaryAlign}      ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colDescAlign    = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnDescriptionAlign}  ,bnr => "",readref => \@allrds,rdtype => "string"} );  
           $colStatusAlign  = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnStatusAlign}       ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colCompAlign    = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnCompletionAlign}   ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           $colLocAlign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnLocationAlign}     ,bnr => "",readref => \@allrds,rdtype => "string"} );  
           $colMapAlign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnMapAlign}          ,bnr => "",readref => \@allrds,rdtype => "string"} );  
           $colCalAlign     = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnCalendarAlign}     ,bnr => "",readref => \@allrds,rdtype => "string"} );   
           $colIdAlign      = "cal".evalTableSpecs ( {href => $hash,def => $coldefalign,base => $hash->{HELPER}{tableSpecs}{cellStyle}{columnEventIdAlign}      ,bnr => "",readref => \@allrds,rdtype => "string"} ); 
           1;
      } or do {
          Log3($name, 1, "$name - Syntax error in attribute \"tableSpecs\" near \"cellStyle\": $@")
      };

      my $colalign  = $coldefalign;
      
      # TabellenBody 
      $out     .= "<tr class='".($k&1?"odd":"even")."'>";
      $out     .= "<td class='cal $colSymbolAlign'  > $symbol                  </td>" if($seen{Symbol});
      if($small) {
          $out .= "<td class='cal $colBeginAlign'   > ".$begind." ".$begint.  "</td>" if($seen{Begin});
          $out .= "<td class='cal $colEndAlign'     > ".$endd  ." ".$endt.    "</td>" if($seen{End});
      } else {
          $out .= "<td class='cal $colBeginAlign'   > $begind                  </td>" if($seen{Begin});
          $out .= "<td class='cal $colBeginAlign'   > $begint                  </td>" if($seen{Begin});
          $out .= "<td class='cal $colEndAlign'     > $endd                    </td>" if($seen{End});
          $out .= "<td class='cal $colEndAlign'     > $endt                    </td>" if($seen{End});      
      }
      $out     .= "<td class='cal $colDayAlign'    > $dleft                    </td>" if($seen{DaysLeft});
      $out     .= "<td class='cal $colDLongAlign'  > $dleftlong                </td>" if($seen{DaysLeftLong});
      $out     .= "<td class='cal $colWeekdayAlign'> $weekday                  </td>" if($seen{Weekday});
      $out     .= "<td class='cal $colTzAlign'     > $tz                       </td>" if($seen{Timezone});
      $out     .= "<td class='cal $colSummaryAlign'> $summary                  </td>" if($seen{Summary});
      $out     .= "<td class='cal $colDescAlign'   > $desc                     </td>" if($seen{Description});
      $out     .= "<td class='cal $colStatusAlign' > $status                   </td>" if($seen{Status});
      $out     .= "<td class='cal $colCompAlign'   > $completion               </td>" if($seen{Completion});
      $out     .= "<td class='cal $colLocAlign'    > $location                 </td>" if($seen{Location});
      $out     .= "<td class='cal $colMapAlign'    > $gps                      </td>" if($seen{Map});
      $out     .= "<td class='cal $colCalAlign'    > $cal                      </td>" if($seen{Calendar});
      $out     .= "<td class='cal $colIdAlign'     > $id                       </td>" if($seen{EventId});
      $out     .= "</tr>";
  }

  $out .= "</table>";
  $out .= "</td>";
  $out .= "</tr>";
  $out .= "</table>";
  $out .= "</html>";

return $out;
}

######################################################################################
#             Evaluiere Eigenschaften von Attribut "tableSpecs"
#
# $hash:     Devicehash
# $default:  Standardwert - wird wieder zurückgegeben wenn kein Funktionsergebnis
# $specs:    Basisschlüssel (z.B. $hash->{HELPER}{tableSpecs}{columnDaysLeft})
# $allreads: Referenz zum ARRAY was alle vorhandenen Readings des Devices enthält
# $bnr:      Blocknummer Readings
# $rdtype:   erwarteter Datentyp als Rückgabe (image, string)
#
######################################################################################
sub evalTableSpecs {                                                          ## no critic 'complexity'
  # my ($hash,$default,$specs,$bnr,$allrds,$rdtype) = @_;
  my ($argref) = @_;
  my $hash     = $argref->{href};
  my $default  = $argref->{def};
  my $specs    = $argref->{base};
  my $bnr      = $argref->{bnr};
  my $allrds   = $argref->{readref};
  my $rdtype   = $argref->{rdtype};
  
  my $name     = $hash->{NAME};
  my $check;
  
  $rdtype = $rdtype // "string";                                              # "string" als default Rückgabe Datentyp
  
  # anonymous sub für Abarbeitung Perl-Kommandos
  $check = sub {
      my ($cmd) = @_;
      my $ret   = AnalyzePerlCommand(undef, $cmd);
  return $ret;
  };
                          
  no warnings;                                                                ## no critic 'warnings'
  
  if ($specs) {                                                               # Eigenschaft muß Wert haben
      my ($rn,$reading,$uval,$ui,$rval);

      if (ref($specs) eq "ARRAY") {                                           # Wenn Schlüssel ein ARRAY enthält
          my $i = 0;
          while ($specs->[$i]) {              
              my $n = keys %{$specs->[$i]};                                   # Anzahl Elemente (Entscheidungskriterien) in Hash
              
              for my $k (keys %{$specs->[$i]}) {                  
                  if ($k eq "icon") {
                      $ui = $specs->[$i]{$k};
                      $n--;
                      next;
                  }
                  
                  for my $r (@{$allrds}) {                                    # alle vorhandenen Readings evaluieren
                      if($r =~ m/$k$/x) {                                     
                         (undef,$rn,$reading) = split("_", $r);               # Readingnummer evaluieren
                         $uval                = $specs->[$i]{$k};             # Vergleichswert 
                         last;
                      }
                  }
                  
                  $rval = ReadingsVal($name, $bnr."_".$rn."_".$reading, "empty");
                  $rval = "\"".$rval."\"";
                  
                  if ( eval ($rval . $uval) ) {                               ## no critic 'eval'           
                      $ui = $specs->[$i]{icon};
                      $n--;                         
                  } else {                          
                      $ui = "";                          
                  }
              }

              if($n == 0 && $ui) {
                  $default = $ui;                                             # Defaultwert mit Select ersetzen wenn alle Bedingungen erfüllt             
              }               
              $i++;              
          }
          
      } elsif (ref($specs) eq "HASH") {                                       # Wenn Schlüssel ein HASH enthält  
          my $n = keys %{$specs};                                             # Anzahl Elemente (Entscheidungskriterien) in Hash
          
          for my $k (keys %{$specs}) {                  
              if ($k eq "icon") {
                  $ui = $specs->{$k};
                  $n--;
                  next;
              }
              for my $r (@{$allrds}) {                                        # alle vorhandenen Readings evaluieren
                  if($r =~ m/$k$/x) {                                     
                     (undef,$rn,$reading) = split("_", $r);                   # Readingnummer evaluieren
                     $uval                = $specs->{$k};                     # Vergleichswert 
                     last;
                  }
              }
              
              $rval = ReadingsVal($name, $bnr."_".$rn."_".$reading, "empty");
              $rval = "\"".$rval."\"";
              
              if ( eval ($rval . $uval) ) {                                   ## no critic 'eval'
                  $ui = $specs->{icon};
                  $n--;                         
              } else {                          
                  $ui = "";                          
              }
          }

          if($n == 0 && $ui) {
              $default = $ui;                                                 # Defaultwert mit Select ersetzen wenn alle Bedingungen erfüllt       
          }
      
      } else {                                                                # ref Wert der Eigenschaft ist nicht HASH oder ARRAY
          if($specs =~ m/\{.*\}/xs) {                                         # den Wert als Perl-Funktion ausführen wenn in {}
              $specs   =~ s/\$NAME/$name/xg;                                  # Platzhalter $NAME, $BNR ersetzen
              $specs   =~ s/\$BNR/$bnr/xg;
              $default = $check->($specs);
          } else {                                                            # einfache key-value Zuweisung
              eval ($default = $specs);                                       ## no critic 'eval' 
          }
      }   
  }
  
  if($default && $rdtype eq "image") {
      $default = FW_makeImage($default);                                      # Icon aus "string" errechnen wenn "image" als Rückgabe erwartet wird und $default gesetzt  
  }
  
  use warnings;
  
return $default;
}

1;

=pod
=item summary    Module to integrate Synology Calendar
=item summary_DE Modul zur Integration von Synology Calendar
=begin html

<a name="SSCal"></a>
<h3>SSCal</h3>
<ul>

    This module is used to integrate Synology Calendar Server with FHEM. 
    The SSCal module is based on functions of Synology Calendar API. <br><br> 
    
    The connection to the calendar server is established via a session ID after successful login. Requirements/queries of the server 
    are stored internally in a queue and processed sequentially. If the calendar server is temporarily unavailable 
    the saved queries are retrieved as soon as the connection to the server is working again. <br><br>

    Both appointment calendars (Events) and task lists (ToDo) can be processed. For these different calendar types 
    different device models can be defined, Model <b>Diary</b> for appointments and Model <b>Tasks</b> for 
    Task lists. <br><br>
    
    If you want discuss about or like to support the development of this module, there is a thread in the FHEM forum:<br>
    <a href="https://forum.fhem.de/index.php/topic,106963.0.html">57_SSCal - Modul für den Synology Kalender</a>.<br><br>

    Further information about the module you can find in the (german) FHEM Wiki:<br>
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers">SSCal - Integration des Synology Calendar Servers</a>.
    <br><br><br>
    
    
    <b>Preparation </b> <br><br>
    
    <ul>    
    As basic requirement the <b>Synology Calendar Package</b> must be installed on your Synology Disc Station. <br>    
    In Synology DSM a user as member of the administrator group <b>must</b> be defined for access use. This user must also have the rights
    to read and/or write the relevant calendars. The entitlement for the calendars are set directly in the 
    <a href="https://www.synology.com/en-global/knowledgebase/DSM/help/Calendar/calendar_desc">Synology calendar application</a>.
    
    The login credentials are assigned later by the set <b>credentials</b> command to the defined device.
    <br><br>
        
    Furthermore some more Perl modules must be installed or available: <br><br>
    
    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
    <tr><td>JSON                </td><td>                                   </td></tr>
    <tr><td>Data::Dumper        </td><td>                                   </td></tr>
    <tr><td>MIME::Base64        </td><td>                                   </td></tr>
    <tr><td>Time::HiRes         </td><td>                                   </td></tr>
    <tr><td>Encode              </td><td>                                   </td></tr>
    <tr><td>POSIX               </td><td>                                   </td></tr>
    <tr><td>HttpUtils           </td><td>(FHEM module)                       </td></tr>
    <tr><td>Blocking            </td><td>(FHEM module)                       </td></tr>
    <tr><td>Meta                </td><td>(FHEM module)                       </td></tr>
    </table>
    
    <br><br>    
    </ul>

<a name="SSCaldefine"></a>
<b>Definition</b>
  <ul>
  <br>
    The creation of SSCal devices is differed between the definition of diaries and task lists. 
    <br><br>
    
    The definition is done with: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCal &lt;ServerAddr&gt; [&lt;Port&gt;] [&lt;Protocol&gt;] [Tasks] </code></b> <br><br>
    </ul>
    
    The parameters are in detail:
    <br>
    <br>    
    
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
    <tr><td><b>Name</b>           </td><td>Name of the device in FHEM </td></tr>
    <tr><td><b>ServerAddr</b>     </td><td>IP address of Synology Disc Station. <b>Note:</b> If you use DNS name instead of IP address, don't forget to set the attribute dnsServer in global device ! </td></tr>
    <tr><td><b>Port</b>           </td><td>optional - Port of Synology Disc Station (default: 5000). </td></tr>
    <tr><td><b>Protocol</b>       </td><td>optional - Protocol used for communication with the calendar server, http or https (default: http). </td></tr>
    <tr><td><b>Tasks</b>          </td><td>optional - to define a task list device add "Tasks" to the definition </td></tr>
    </table>

    <br><br>

    <b>Examples:</b>
     <pre>
      <code>define Appointments SSCal 192.168.2.10 </code>
      <code>define Appointments SSCal 192.168.2.10 5001 https </code>
      # creates a diary device on default port (5000/http) respectively https on port 5001

      <code>define Tasklist SSCal ds.myds.org 5001 https Tasks </code>
      # creates a task list device with protocol https on port 5001
     </pre>
     
    After definition of a device only the command <a href="#SSCalcredentials">credentials</a> is available.
    First of all you have to set the credentials for communication with the Synology calendar server by using this command. <br><br>

    If the login was successful, all for the user accessible calendars will be determined. The calendars to retrieve  
    are selectable by attribute <a href="#usedCalendars">usedCalendars</a>. 
    <br><br><br>
    </ul>
  
<a name="SSCalset"></a>
<b>Set </b>

<ul>
  <br>
  The following set commands are valid for both device models Diary/Tasks or partly for one of these device models.
  <br><br>
  
  <ul>
  <a name="SSCalcalUpdate"></a>
  <li><b> calUpdate [&lt;list of calendars&gt;] </b> <br>
  
  Fetch entries of the selected calendars (see attribute <a href="#usedCalendars">usedCalendars</a>). 
  Alternatively you can enter a list of calendars to fetch separated by comma. The calendar names may contain spaces. 
  <br><br>
  
  <ul>
    <b>Examples:</b> <br><br>

    set Appointments calUpdate  <br>
    # fetch the entries of calendars specified in attribute usedCalendars <br><br>
  
    set Appointments calUpdate Heikos Kalender,Abfall <br>
    # fetch the entries of both calendars "Heikos Kalender" and "Abfall". <br><br>
  </ul>

  </li><br>
  </ul>

  <ul>
  <a name="SSCalcleanCompleteTasks"></a>
  <li><b> cleanCompleteTasks </b> &nbsp;&nbsp;&nbsp;&nbsp;(only model "Tasks") <br>
  
  All completed tasks in the specified task lists (see attribute <a href="#usedCalendars">usedCalendars</a>) are deleted. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCaldeleteEventId"></a>
  <li><b> deleteEventId &lt;Id&gt; </b> <br>
  
  The specified Event Id (see reading x_x_EventId) will be delted from calendar or tas list. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalcredentials"></a>
  <li><b> credentials &lt;User&gt; &lt;Passwort&gt; </b> <br>
  
  Store the credentials for calendar communication. <br>
  
  </li><br>
  </ul> 
  
  <ul>
  <a name="SSCaleraseReadings"></a>
  <li><b> eraseReadings </b> <br>
  
  Delete all calendar readings. It doesn't effect the calendar entries itself ! <br> 
  
  </li><br>
  </ul>  
  
  <ul>
  <a name="SSCallistSendqueue"></a>
  <li><b> listSendqueue </b> <br>
  
  Shows all entries in the sendqueue. Normally the queue is filled only for a short time, but may contain entries  
  permanently in case of problems. Thereby the occured failures can be identified and assigned. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCallogout"></a>
  <li><b> logout </b> <br>
  
  The user will be logged out and the session to the Synology Disc Station will be cleared. <br> 
  
  </li><br>
  </ul> 
  
  <ul>
  <a name="SSCalpurgeSendqueue"></a>
  <li><b> purgeSendqueue </b> <br>
  
  Deletes entries from the sendqueue. Several options are usable dependend from situation: <br><br> 
   <ul>
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>-all-         </td><td>deletes all entries from sendqueue </td></tr>
      <tr><td>-permError-   </td><td>deletes all entries which are suspended from further processing caused by a permanent error </td></tr>
      <tr><td>&lt;Index&gt; </td><td>deletes the specified entry from sendqueue </td></tr>
    </table>
   </ul>
   
  </li><br>
  </ul>
   
  <ul>
  <a name="SSCalrestartSendqueue"></a>
  <li><b> restartSendqueue </b> <br>
  
  The processing of entries in sendqueue will be new started manually. Because of the sendqueue will be restarted automatically by
  every new retrieval it is normally not necessary to execute this command. <br>
  
  </li><br>
  </ul>   
   
 </ul>

<a name="SSCalget"></a>
<b>Get</b>
 <ul>
  <br>
 
  <ul>
  <a name="SSCalapiInfo"></a>
  <li><b> apiInfo </b> <br>
  
  Retrieves the API informations of the Synology calendar server and open a popup window with its data.
  <br>
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalcalAsHtml"></a>
  <li><b> calAsHtml </b> <br>
  
  Shows a popup with the time summary. In own perl routines and for integration in a weblink device this  
  overview can be used as follows: <br><br>
  
    <ul>
      { FHEM::SSCal::calAsHtml ("&lt;SSCal-Device&gt;") }
    </ul>  
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalgetCalendars"></a>
  <li><b> getCalendars </b> <br>
  
  Requests the existing calendars from your Synology Disc Station and open a popup window with informations about each available calendar. 
  </li><br>  
  
  <br>
  </ul>
  
  <ul>
  <a name="SSCalstoredCredentials"></a>
  <li><b> storedCredentials </b> <br>
  
  Shows the stored User/Password combination. 
  </li><br>  
  
  <br>
  </ul>
  
  <ul>
  <a name="SSCalversionNotes"></a>
  <li><b> versionNotes </b> <br>
  
  Shows important informations and hints about the module.
  </li><br>  
  
  <br>
  </ul>
 </ul>  
  
<a name="SSCamattr"></a>
<b>Attribute</b>
 <br><br>
 <ul>
  
  <ul>  
  <a name="asyncMode"></a>
  <li><b>asyncMode</b> <br> 
  
    If set to "1", the data parsing will be executed within a background process and avoid possible blocking situations. <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="createATDevs"></a>
  <li><b>createATDevs</b> <br> 
  
    If set to "1", FHEM commands and Perl routines to be executed are recognised automatically in a calendar entry by SSCal.
    In this case SSCal defines, changes or deletes at-devices to execute these commands independently. <br>
    A FHEM command to be executed has to be included into <b>{ }</b> in the field <b>Description</b> of Synology Calendar 
    application WebUI, Perl routines has to be included into double <b>{{ }}</b>. <br>    
    For further detailed information please read the Wiki (germnan) section:
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers#at-Devices_f.C3.BCr_Steuerungen_automatisch_erstellen_und_verwalten_lassen">at-Devices für Steuerungen automatisch erstellen und verwalten lassen</a>.
    <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="cutOlderDays"></a>
  <li><b>cutOlderDays</b> <br> 
  
    Entries in calendars are ignored if the due date is older than the number of specified days. <br>
    (default: 5) <br><br>
    
    <ul>
      <b>Example:</b> <br><br>

      attr &lt;Name&gt; cutOlderDays 30  <br>
    </ul>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="cutLaterDays"></a>
  <li><b>cutLaterDays</b> <br> 
  
    Entries in calendars are ignored if the due date is later than the number of specified days. <br>
    (default: 5) <br><br>
    
    <ul>
      <b>Example:</b> <br><br>

      attr &lt;Name&gt; cutLaterDays 90  <br>
    </ul>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="filterCompleteTask"></a>
  <li><b>filterCompleteTask </b> &nbsp;&nbsp;&nbsp;&nbsp;(only model "Tasks") <br> 
  
    Entries of the calendar are filtered dependend from their completion: <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>1  </td><td>only completed tasks are shown                        </td></tr>
      <tr><td>2  </td><td>only not completed tasks are shown                    </td></tr>
      <tr><td>3  </td><td>completed and not completed tasks are shown (default) </td></tr>
     </table>
    </ul>   
    
  </li><br>
  </ul> 

  <ul>  
  <a name="filterDueTask"></a>
  <li><b>filterDueTask </b> &nbsp;&nbsp;&nbsp;&nbsp;(only model "Tasks") <br> 
  
    Entries in taks lists with/without due date are filtered: <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>1  </td><td>only tasks with due date are shown                  </td></tr>
      <tr><td>2  </td><td>only tasks without due date are shown               </td></tr>
      <tr><td>3  </td><td>tasks with and without due date are shown (default) </td></tr>
     </table>
    </ul>   
    
  </li><br>
  </ul> 

  <ul>  
  <a name="interval"></a>
  <li><b>interval &lt;seconds&gt;</b> <br> 
  
    Interval in seconds to fetch calendar entries automatically. If "0" is specified, no calendar fetch is  
    executed. (default) <br><br>
    
    <ul>
      <b>Example:</b> <br><br>
    
      Set the attribute as follows if the calendar entries should retrieved every hour: <br>
      attr &lt;Name&gt; interval 3600  <br>
    </ul>    
    
  </li><br>
  </ul>  
  
  <ul>  
  <a name="loginRetries"></a>
  <li><b>loginRetries</b> <br> 
  
    Number of attempts for the initial user login. <br>
    (default: 3)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="showRepeatEvent"></a>
  <li><b>showRepeatEvent</b> &nbsp;&nbsp;&nbsp;&nbsp;(only model "Diary") <br> 
  
    If "true", one-time events as well as recurrent events are fetched. Otherwise only one-time events are retrieved. <br>
    (default: true)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="showPassInLog"></a>
  <li><b>showPassInLog</b> <br> 
  
    If "1", the password respectively the SID will be shown in the logfile. <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableColumnMap"></a>
  <li><b>tableColumnMap </b> <br> 
  
    Determines how the link to a map is shown in the table column "Map": <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td><b>icon</b>   </td><td>shows a user customisable symbol (default)  </td></tr>
      <tr><td><b>data</b>   </td><td>shows the GPS data                          </td></tr>
      <tr><td><b>text</b>   </td><td>shows a text adjustable by the user         </td></tr>
     </table>
    </ul>  

    <br>
    To make further adjustments, there are some more possibilities to specify properties in the attribute tableSpecs.
    For detailed informations about the possibilities to configure the overview table please consult the (german) Wiki
    chapter 
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers#Darstellung_der_.C3.9Cbersichtstabelle_in_Raum-_und_Detailansicht_beeinflussen">Darstellung der Übersichtstabelle in Raum- und Detailansicht beeinflussen</a>.
    <br>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableInDetail"></a>
  <li><b>tableInDetail</b> <br> 
  
    An overview diary or taks table will be displayed in detail view. <br>
    (default: 1)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableInRoom"></a>
  <li><b>tableInRoom</b> <br> 
  
    An overview diary or taks table will be displayed in room view. <br>
    (default: 1)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableFields"></a>
  <li><b>tableFields</b> <br> 
  
    Selection of the fields to be displayed in the overview table in room or detail view. <br>
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableSpecs"></a>
  <li><b>tableSpecs</b> <br> 
  
    By several key-value pair combinations the presentation of informations in the overview table can be adjusted. 
    The (german) Wiki chapter 
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers#Darstellung_der_.C3.9Cbersichtstabelle_in_Raum-_und_Detailansicht_beeinflussen">Darstellung der Übersichtstabelle in Raum- und Detailansicht beeinflussen</a>
    provides more detailed help for it.
     
  </li><br>
  </ul>
  
  <ul>  
  <a name="timeout"></a>
  <li><b>timeout  &lt;seconds&gt;</b> <br> 
  
    Timeout for calendar fetch in seconds. <br>
    (default: 20)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="usedCalendars"></a>
  <li><b>usedCalendars</b> <br> 
  
    Selection of calendars to fetch from a popup window. The list of accessible calendars will initial be created during 
    FHEM startup. At all times it can also be done manually with command: <br><br>

    <ul>
      get &lt;Name&gt; getCalendars  <br>
    </ul>   
    
    <br>
     
    As long as the accessible calendars are not successfully fetched, this attribute only contains simply the entry: <br><br>
    
    <ul>
      --wait for Calendar list--  <br>
    </ul>    
    
  </li><br>
  </ul> 
  
 </ul> 
 <br>
 
<a name="SSCalEvents"></a>
<b>Hints for event generation </b>

  <ul>
  <br>
  Depending on the volume of the retrieved data, a large number of readings can be created. 
  To avoid too extensive event generation in FHEM, the attribute <b>event-on-update-reading</b> is preset after  
  definition of the calendar device to: <br><br>
  
  <ul>
    attr <name> event-on-update-reading.*Summary.*,state
  </ul>
  <br>
  
  If events are to be created for all readings, event-on-update-reading must be set to .* and mustn't be deleted. 
  <br><br>
  
  SSCal generates additional events for each event, which contains a start time, with each new read-in 
  of a calendar. These events provide the user with assistance in creating his own control logic in FHEM based on 
  calendar entries. <br><br>
  
  The event <b>composite</b> contains the information fields: <br><br>

   <ul>
    <li> block number of the appointment </li>
    <li>Event ID of the appointment </li>
    <li>indicator for a serial appointment (0=no serial appointment or 1=serial appointment) </li>
    <li>start time in ISO 8601 format </li>
    <li>Status of the event </li>
    <li>the text in Description (corresponds to the Description field in Synology Calendar WebUI) or the text in Summary 
        if Description is not set </li>
   </ul>
   <br>
   
  The event <b>compositeBlockNumbers</b> contains the block numbers of all events of the calendar. 
  If there are no appointments, this event has only the value <b>none</b>. 
    
  </ul>
 
</ul>

=end html
=begin html_DE

<a name="SSCal"></a>
<h3>SSCal</h3>
<ul>

    Mit diesem Modul erfolgt die Integration des Synology Calendar Servers in FHEM. 
    Das Modul SSCal basiert auf Funktionen der Synology Calendar API. <br><br> 
    
    Die Verbindung zum Kalenderserver erfolgt über eine Session ID nach erfolgreichem Login. Anforderungen/Abfragen des Servers 
    werden intern in einer Queue gespeichert und sequentiell abgearbeitet. Steht der Kalenderserver temporär nicht zur Verfügung, 
    werden die gespeicherten Abfragen nachgeholt sobald die Verbindung zum Server wieder funktioniert. <br><br>

    Es können sowohl Terminkalender (Events) und Aufgabenlisten (ToDo) verarbeitet werden. Für diese verschiedenen Kalenderarten 
    können verschiedene Device-Models definiert werden, Model <b>Diary</b> für Terminkalender und Model <b>Tasks</b> für 
    Aufgabenlisten. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="https://forum.fhem.de/index.php/topic,106963.0.html">57_SSCal - Modul für den Synology Kalender</a>.<br><br>

    Weitere Infomationen zum Modul sind im FHEM-Wiki zu finden:<br>
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers">SSCal - Integration des Synology Calendar Servers</a>.
    <br><br><br>
    
    
    <b>Vorbereitung </b> <br><br>
    
    <ul>    
    Als Grundvoraussetzung muss das <b>Synology Calendar Package</b> auf der Diskstation installiert sein. <br>    
    Im Synology DSM wird ein User benutzt, der Mitglied der Administrator-Group sein <b>muß</b> und zusätzlich die benötigte Berechtigung
    zum Lesen und/oder Schreiben der relevanten Kalender hat. Die Kalenderberechtigungen werden direkt in der 
    <a href="https://www.synology.com/de-de/knowledgebase/DSM/help/Calendar/calendar_desc">Synology Kalenderapplikation</a> eingestellt.
    
    Die Zugangsdaten werden später über ein Set <b>credentials</b> Kommando dem angelegten Device zugewiesen.
    <br><br>
        
    Weiterhin müssen diverse Perl-Module installiert sein: <br><br>
    
    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
    <tr><td>JSON                </td><td>                                   </td></tr>
    <tr><td>Data::Dumper        </td><td>                                   </td></tr>
    <tr><td>MIME::Base64        </td><td>                                   </td></tr>
    <tr><td>Time::HiRes         </td><td>                                   </td></tr>
    <tr><td>Encode              </td><td>                                   </td></tr>
    <tr><td>POSIX               </td><td>                                   </td></tr>
    <tr><td>HttpUtils           </td><td>(FHEM-Modul)                       </td></tr>
    <tr><td>Blocking            </td><td>(FHEM-Modul)                       </td></tr>
    <tr><td>Meta                </td><td>(FHEM-Modul)                       </td></tr>
    </table>
    
    <br><br>    
    </ul>

<a name="SSCaldefine"></a>
<b>Definition</b>
  <ul>
  <br>
    Bei der Definition wird zwischen einem Kalenderdevice für Termine (Events) und Aufgaben (Tasks) unterschieden. 
    <br><br>
    
    Die Definition erfolgt mit: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCal &lt;ServerAddr&gt; [&lt;Port&gt;] [&lt;Protocol&gt;] [Tasks] </code></b> <br><br>
    </ul>
    
    Die Parameter beschreiben im Einzelnen:
    <br>
    <br>    
    
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
    <tr><td><b>Name</b>           </td><td>der Name des neuen Kalenderdevices in FHEM </td></tr>
    <tr><td><b>ServerAddr</b>     </td><td>die IP-Addresse der Synology DS. <b>Hinweis:</b> Wird der DNS-Name statt IP-Adresse verwendet, sollte das Attribut dnsServer im global Device gesetzt werden ! </td></tr>
    <tr><td><b>Port</b>           </td><td>optional - Port der Synology DS (default: 5000). </td></tr>
    <tr><td><b>Protocol</b>       </td><td>optional - Protokoll zur Kommunikation mit dem Kalender-Server, http oder https (default: http). </td></tr>
    <tr><td><b>Tasks</b>          </td><td>optional - zur Definition einer Aufgabenliste wird "Tasks" hinzugefügt </td></tr>
    </table>

    <br><br>

    <b>Beispiele:</b>
     <pre>
      <code>define Appointments SSCal 192.168.2.10 </code>
      <code>define Appointments SSCal 192.168.2.10 5001 https </code>
      # erstellt Terminkalenderdevice mit Standardport (5000/http) bzw. https auf Port 5001

      <code>define Tasklist SSCal ds.myds.org 5001 https Tasks </code>
      # erstellt Aufgabenlistendevice mit https auf Port 5001
     </pre>
     
    Nach der Definition eines Devices steht nur der set-Befehl <a href="#SSCalcredentials">credentials</a> zur Verfügung.
    Mit diesem Befehl werden zunächst die Zugangsparameter dem Device bekannt gemacht. <br><br>

    War der Login erfolgreich, werden alle dem User zugänglichen Kalender ermittelt und im 
    Attribut <a href="#usedCalendars">usedCalendars</a> zur Auswahl bereitgestellt. 
    <br><br><br>
    </ul>
  
<a name="SSCalset"></a>
<b>Set </b>

<ul>
  <br>
  Die aufgeführten set-Kommandos sind sowohl für die Devicemodels Diary/Tasks oder teilweise nur für einen dieser Devicemodels gültig.
  <br><br>
  
  <ul>
  <a name="SSCalcalUpdate"></a>
  <li><b> calUpdate [&lt;Kalenderliste&gt;] </b> <br>
  
  Ruft die Einträge der selektierten Kalender (siehe Attribut <a href="#usedCalendars">usedCalendars</a>) ab. 
  Alternativ kann eine Komma getrennte Liste der abzurufenden Kalender dem Befehl übergeben werden. Die Kalendernamen können 
  Leerzeichen enthalten. 
  <br><br>
  
  <ul>
    <b>Beispiel:</b> <br><br>

    set Appointments calUpdate  <br>
    # ruft die Einträge der im Attribut usedCalendars spezifizierten Kalender ab <br><br>
  
    set Appointments calUpdate Heikos Kalender,Abfall <br>
    # ruft die Einträge der Kalender "Heikos Kalender" und "Abfall" ab. <br><br>
  </ul>

  </li><br>
  </ul>

  <ul>
  <a name="SSCalcleanCompleteTasks"></a>
  <li><b> cleanCompleteTasks </b> &nbsp;&nbsp;&nbsp;&nbsp;(nur Model "Tasks") <br>
  
  In den selektierten Aufgabenlisten (siehe Attribut <a href="#usedCalendars">usedCalendars</a>) werden alle 
  abgeschlossenen Aufgaben gelöscht. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCaldeleteEventId"></a>
  <li><b> deleteEventId &lt;Id&gt; </b> <br>
  
  Die angegebene Event Id (siehe Reading x_x_EventId) wird aus dem Kalender bzw. der Aufgabenliste gelöscht. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalcredentials"></a>
  <li><b> credentials &lt;User&gt; &lt;Passwort&gt; </b> <br>
  
  Speichert die Zugangsdaten. <br>
  
  </li><br>
  </ul> 
  
  <ul>
  <a name="SSCaleraseReadings"></a>
  <li><b> eraseReadings </b> <br>
  
  Löscht alle Kalenderreadings. <br> 
  
  </li><br>
  </ul>  
  
  <ul>
  <a name="SSCallistSendqueue"></a>
  <li><b> listSendqueue </b> <br>
  
  Zeigt alle Einträge in der Sendequeue. Die Queue ist normalerweise nur kurz gefüllt, kann aber im Problemfall 
  dauerhaft Einträge enthalten. Dadurch kann ein bei einer Abrufaufgabe aufgetretener Fehler ermittelt und zugeordnet
  werden. <br> 
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCallogout"></a>
  <li><b> logout </b> <br>
  
  Der User wird ausgeloggt und die Session mit der Synology DS beendet. <br> 
  
  </li><br>
  </ul> 
  
  <ul>
  <a name="SSCalpurgeSendqueue"></a>
  <li><b> purgeSendqueue </b> <br>
  
  Löscht Einträge in der Sendequeue. Es stehen verschiedene Optionen je nach Situation zur Verfügung: <br><br> 
   <ul>
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>-all-         </td><td>löscht alle in der Sendequeue vorhandenen Einträge </td></tr>
      <tr><td>-permError-   </td><td>löscht alle Einträge, die durch einen permanenten Fehler von der weiteren Verarbeitung ausgeschlossen sind </td></tr>
      <tr><td>&lt;Index&gt; </td><td>löscht einen eindeutigen Eintrag der Sendequeue </td></tr>
    </table>
   </ul>
   
  </li><br>
  </ul>
   
  <ul>
  <a name="SSCalrestartSendqueue"></a>
  <li><b> restartSendqueue </b> <br>
  
  Die Abarbeitung der Einträge in der Sendequeue wird manuell neu angestoßen. Normalerweise nicht nötig, da die Sendequeue bei der 
  Initialisierung jedes neuen Abrufs impliziz neu gestartet wird. <br>
  
  </li><br>
  </ul>   
   
 </ul>

<a name="SSCalget"></a>
<b>Get</b>
 <ul>
  <br>
 
  <ul>
  <a name="SSCalapiInfo"></a>
  <li><b> apiInfo </b> <br>
  
  Ruft die API Informationen des Synology Calendar Servers ab und öffnet ein Popup mit diesen Informationen.
  <br>
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalcalAsHtml"></a>
  <li><b> calAsHtml </b> <br>
  
  Zeigt ein Popup mit einer Terminübersicht. In eigenen perl-Routinen und für die Einbindung in weblink kann 
  diese Übersicht aufgerufen werden mit: <br><br>
  
    <ul>
      { FHEM::SSCal::calAsHtml ("&lt;SSCal-Device&gt;") }
    </ul>  
  
  </li><br>
  </ul>
  
  <ul>
  <a name="SSCalgetCalendars"></a>
  <li><b> getCalendars </b> <br>
  
  Ruft die auf der Synology vorhandenen Kalender ab und öffnet ein Popup mit Informationen über die jeweiligen Kalender. 
  </li><br>  
  
  <br>
  </ul>
  
  <ul>
  <a name="SSCalstoredCredentials"></a>
  <li><b> storedCredentials </b> <br>
  
  Zeigt die gespeicherten User/Passwort Kombination. 
  </li><br>  
  
  <br>
  </ul>
  
  <ul>
  <a name="SSCalversionNotes"></a>
  <li><b> versionNotes </b> <br>
  
  Zeigt Informationen und Hilfen zum Modul.
  </li><br>  
  
  <br>
  </ul>
 </ul>  
  
<a name="SSCamattr"></a>
<b>Attribute</b>
 <br><br>
 <ul>
  
  <ul>  
  <a name="asyncMode"></a>
  <li><b>asyncMode</b> <br> 
  
    Wenn "1" wird das Datenparsing in einen Hintergrundprozess ausgelagert und vermeidet Blockierungssituationen. <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="createATDevs"></a>
  <li><b>createATDevs</b> <br> 
  
    Wenn "1" werden bei der Erkennung von FHEM-Kommandos bzw. auszuführenden Perl-Routinen im Kalendereintrag durch SSCal 
    automatisiert at-Devices zur termingerechten Ausführung dieser Kommandos erstellt, geändert und gelöscht. <br>
    Auszuführende FHEM-Kommandos werden in <b>{ }</b> eingeschlossen im Feld <b>Beschreibung</b> im Synology Kalender WebUI
    hinterlegt, Perl Routinen werden in doppelte <b>{{ }}</b> eingeschlossen. <br>    
    Lesen sie bitte dazu die detailliierte Beschreibung im Wiki Abschnitt
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers#at-Devices_f.C3.BCr_Steuerungen_automatisch_erstellen_und_verwalten_lassen">at-Devices für Steuerungen automatisch erstellen und verwalten lassen</a>.
    <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="cutOlderDays"></a>
  <li><b>cutOlderDays</b> <br> 
  
    Terminkalendereinträge und Aufgabenkalendereinträge mit Fälligkeitstermin älter als die angegeben Tage werden von der 
    Verarbeitung ausgeschlossen. <br>
    (default: 5) <br><br>
    
    <ul>
      <b>Beispiel:</b> <br><br>

      attr &lt;Name&gt; cutOlderDays 30  <br>
    </ul>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="cutLaterDays"></a>
  <li><b>cutLaterDays</b> <br> 
  
    Terminkalendereinträge und Aufgabenkalendereinträge mit Fälligkeitstermin später als die angegeben Tage werden von der 
    Verarbeitung ausgeschlossen. <br>
    (default: 5) <br><br>
    
    <ul>
      <b>Beispiel:</b> <br><br>

      attr &lt;Name&gt; cutLaterDays 90  <br>
    </ul>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="filterCompleteTask"></a>
  <li><b>filterCompleteTask </b> &nbsp;&nbsp;&nbsp;&nbsp;(nur Model "Tasks") <br> 
  
    Es werden Einträge in Aufgabenkalendern entsprechend der Fertigstellung gefiltert: <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>1  </td><td>nur fertig gestellte Aufgaben werden angezeigt                   </td></tr>
      <tr><td>2  </td><td>nur nicht fertige Aufgaben werden angezeigt                      </td></tr>
      <tr><td>3  </td><td>es werden fertige und nicht fertige Aufgaben angezeigt (default) </td></tr>
     </table>
    </ul>   
    
  </li><br>
  </ul> 

  <ul>  
  <a name="filterDueTask"></a>
  <li><b>filterDueTask </b> &nbsp;&nbsp;&nbsp;&nbsp;(nur Model "Tasks") <br> 
  
    Es werden Einträge in Aufgabenkalendern mit/ohne Fälligkeit gefiltert: <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>1  </td><td>nur Einträge mit Fälligkeitstermin werden angezeigt                   </td></tr>
      <tr><td>2  </td><td>nur Einträge ohne Fälligkeitstermin werden angezeigt                  </td></tr>
      <tr><td>3  </td><td>es werden Einträge mit und ohne Fälligkeitstermin angezeigt (default) </td></tr>
     </table>
    </ul>   
    
  </li><br>
  </ul> 

  <ul>  
  <a name="interval"></a>
  <li><b>interval &lt;Sekunden&gt;</b> <br> 
  
    Automatisches Abrufintervall der Kalendereintträge in Sekunden. Ist "0" agegeben, wird kein automatischer Datenabruf 
    ausgeführt. (default) <br>
    Sollen z.B. jede Stunde die Einträge der gewählten Kalender abgerufen werden, wird das Attribut wie 
    folgt gesetzt: <br><br>
    
    <ul>
      attr &lt;Name&gt; interval 3600  <br>
    </ul>    
    
  </li><br>
  </ul>  
  
  <ul>  
  <a name="loginRetries"></a>
  <li><b>loginRetries</b> <br> 
  
    Anzahl der Versuche für das inititiale User login. <br>
    (default: 3)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="showRepeatEvent"></a>
  <li><b>showRepeatEvent</b> &nbsp;&nbsp;&nbsp;&nbsp;(nur Model "Diary") <br> 
  
    Wenn "true" werden neben einmaligen Terminen ebenfalls wiederkehrende Termine ausgewertet. <br>
    (default: true)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="showPassInLog"></a>
  <li><b>showPassInLog</b> <br> 
  
    Wenn "1" wird das Passwort bzw. die SID im Log angezeigt. <br>
    (default: 0)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableColumnMap"></a>
  <li><b>tableColumnMap </b> <br> 
  
    Legt fest, wie der Link zur Karte in der Tabellspalte "Map" bzw. "Karte" gestaltet wird: <br><br>
    
    <ul>
     <table>
     <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td><b>icon</b>   </td><td>es wird ein durch den User anpassbares Symbol angezeigt (default)  </td></tr>
      <tr><td><b>data</b>   </td><td>es werden die GPS-Daten angezeigt                                  </td></tr>
      <tr><td><b>text</b>   </td><td>es wird ein durch den Nutzer einstellbarer Text verwendet          </td></tr>
     </table>
    </ul>  

    <br>
    Der Nutzer kann weitere Anpassungen des verwendeten Icons oder Textes in den Eigenschaften des Attributs tableSpecs 
    vornehmen. Für detailliierte Informationen dazu siehe Wiki-Kapitel 
    <a href="https://wiki.fhem.de/wiki/-_Integration_des_Synology_Calendar_Servers#Darstellung_der_.C3.9Cbersichtstabelle_in_Raum-_und_Detailansicht_beeinflussen">Darstellung der Übersichtstabelle in Raum- und Detailansicht beeinflussen</a>.
    <br>    
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableInDetail"></a>
  <li><b>tableInDetail</b> <br> 
  
    Eine Termin/Aufgabenübersicht wird in der Detailansicht erstellt bzw. ausgeschaltet. <br>
    (default: 1)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableInRoom"></a>
  <li><b>tableInRoom</b> <br> 
  
    Eine Termin/Aufgabenübersicht wird in der Raumansicht erstellt bzw. ausgeschaltet. <br>
    (default: 1)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableFields"></a>
  <li><b>tableFields</b> <br> 
  
    Auswahl der in der Termin/Aufgabenübersicht (Raum- bzw. Detailansicht) anzuzeigenden Felder über eine Drop-Down 
    Liste. <br>
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="tableSpecs"></a>
  <li><b>tableSpecs</b> <br> 
  
    Über verschiedene Schlüssel-Wertpaar Kombinationen kann die Darstellung der Informationen in der Übersichtstabelle 
    angepasst werden. Das Wiki-Kapitel
    <a href="https://wiki.fhem.de/wiki/SSCal_-_Integration_des_Synology_Calendar_Servers#Darstellung_der_.C3.9Cbersichtstabelle_in_Raum-_und_Detailansicht_beeinflussen">Darstellung der Übersichtstabelle in Raum- und Detailansicht beeinflussen</a>
    liefert detailiierte Informationen dazu.
     
  </li><br>
  </ul>
  
  <ul>  
  <a name="timeout"></a>
  <li><b>timeout  &lt;Sekunden&gt;</b> <br> 
  
    Timeout für den Datenabruf in Sekunden. <br>
    (default: 20)
    
  </li><br>
  </ul>
  
  <ul>  
  <a name="usedCalendars"></a>
  <li><b>usedCalendars</b> <br> 
  
    Auswahl der abzurufenden Kalender über ein Popup. Die Liste der Kalender wird beim Start des Moduls initial gefüllt, 
    kann danach aber ebenfalls durch den Befehl: <br><br>

    <ul>
      get &lt;Name&gt; getCalendars  <br>
    </ul>   
    
    <br>
    manuell ausgeführt werden. 
    Wurde noch kein erfolgreicher Kalenderabruf ausgeführt, enthält dieses Attribut lediglich den Eintrag: <br><br>
    
    <ul>
      --wait for Calendar list--  <br>
    </ul>    
    
  </li><br>
  </ul> 
  
 </ul> 
 <br>

<a name="SSCalEvents"></a>
<b>Hinweise zur Eventgenerierung </b>

  <ul>
  <br>
  Je nach Umfang der abgerufenen Daten können sehr viele Readings erstellt werden. Um eine zu umfangreiche Eventgenerierung 
  in FHEM zu verhindern, ist nach der Definition des Kalenderdevices das Attribut <b>event-on-update-reading</b> 
  voreingestellt auf: <br><br>
  
  <ul>
    attr <Name> event-on-update-reading .*Summary.*,state
  </ul>
  <br>
  
  Sollen Events für alle Readings erstellt werden, muss event-on-update-reading auf .* eingestellt und nicht gelöscht 
  werden. <br><br>
  
  SSCal generiert für jedes Ereignis, welches einen Begin-Zeitpunkt enthält, zusätzliche Events bei jedem erneuten Einlesen 
  eines Kalenders. Diese Events bieten dem Anwender Hilfe zur Erstellung eigener Steuerungslogiken in FHEM auf Grundlage 
  von Kalendereinträgen. <br><br>
  
  Der Event <b>composite</b> enthält die Informationsfelder: <br><br>

   <ul>
    <li>Blocknummer des Termins </li>
    <li>Event-ID des Termins </li>
    <li>Kennzeichen für ein Serientermin (0=kein Serientermin oder 1=Serientermin) </li>
    <li>Startzeitpunkt im ISO 8601 Format </li>
    <li>Status des Events </li>
    <li>den Text in Description (entspricht dem Feld Beschreibung im Synology Kalender WebUI) bzw. den Text in Summary 
        falls Description nicht gesetzt ist </li>
   </ul>
   <br>
   
  Der Event <b>compositeBlockNumbers</b> enthält die Blocknummern aller Termine des Kalenders. Sind keine Termine vorhanden, enthält 
  dieser Event nur den Wert <b>none</b>. 
    
  </ul>
 
</ul>

=end html_DE

=for :application/json;q=META.json 57_SSCal.pm
{
  "abstract": "Integration of Synology Calendar.",
  "x_lang": {
    "de": {
      "abstract": "Integration des Synology Calendars."
    }
  },
  "keywords": [
    "Synology",
    "Calendar",
    "Appointments"
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
        "JSON": 4.020,
        "Data::Dumper": 0,
        "MIME::Base64": 0,
        "Time::HiRes": 0,
        "HttpUtils": 0,
        "Blocking": 0,
        "Encode": 0     
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
      "web": "https://wiki.fhem.de/wiki/SSCal - Integration des Synology Calendar Servers",
      "title": "SSCal - Integration des Synology Calendar Servers"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/57_SSCal.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/57_SSCal.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
