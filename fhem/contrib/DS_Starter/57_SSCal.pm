########################################################################################################################
# $Id: $
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

package main;

use strict;                           
use warnings;
eval "use JSON;1;" or my $SSCalMM = "JSON";                       # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use MIME::Base64;
use Time::HiRes;
use HttpUtils;                                                    
use Encode;
use Blocking;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Versions History intern
my %SSCal_vNotesIntern = (
  "1.6.1"  => "03.02.2020  rename attributes to \"calOverviewInDetail\",\"calOverviewInRoom\" ",
  "1.6.0"  => "03.02.2020  new attribute \"calOverviewFields\" to show specified fields in calendar overview in detail/room view, ".
                           "Model Diary/Tasks defined, periodic call of ToDo-Liists now possible ",
  "1.5.0"  => "02.02.2020  new attribute \"calOverviewInDetail\",\"calOverviewInRoom\" to control calendar overview in room or detail view ",
  "1.4.0"  => "02.02.2020  get calAsHtml command or use sub SSCal_calAsHtml(\$name) ",
  "1.3.1"  => "01.02.2020  add SSCal_errauthlist hash for login/logout API error codes ",
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
my %SSCal_vNotesExtern = (
  "1.0.0"  => "18.12.2019  initial "
);

# Aufbau Errorcode-Hashes
my %SSCal_errauthlist = (
  400 => "No such account or the password is incorrect",
  401 => "Account disabled",
  402 => "Permission denied",
  403 => "2-step verification code required",
  404 => "Failed to authenticate 2-step verification code",
);

my %SSCal_errlist = (
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

# Standardvariablen und Forward-Deklaration                                          
use vars qw(%SSCal_vHintsExt_en);
use vars qw(%SSCal_vHintsExt_de);
our %SSCal_api;

################################################################
sub SSCal_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}                 = "SSCal_Define";
 $hash->{UndefFn}               = "SSCal_Undef";
 $hash->{DeleteFn}              = "SSCal_Delete"; 
 $hash->{SetFn}                 = "SSCal_Set";
 $hash->{GetFn}                 = "SSCal_Get";
 $hash->{AttrFn}                = "SSCal_Attr";
 $hash->{DelayedShutdownFn}     = "SSCal_DelayedShutdown";
 
 # Darstellung FHEMWEB
 # $hash->{FW_summaryFn}        = "SSCal_FWsummaryFn";
 $hash->{FW_addDetailToSummary} = 1 ;                       # zusaetzlich zu der Device-Summary auch eine Neue mit dem Inhalt von DetailFn angezeigt             
 $hash->{FW_detailFn}           = "SSCal_FWdetailFn";
 $hash->{FW_deviceOverview}     = 1;
 
 $hash->{AttrList} = "asyncMode:1,0 ".  
                     "calOverviewInDetail:0,1 ".
                     "calOverviewInRoom:0,1 ".
                     "calOverviewFields:multiple-strict,Begin,End,Summary,Status,Location,Description,GPS,Calendar,Completion,Timezone ".
					 "cutOlderDays ".
					 "cutLaterDays ".
                     "disable:1,0 ".
					 "filterCompleteTask:1,2,3 ".
					 "filterDueTask:1,2,3 ".
                     "interval ".
                     "loginRetries:1,2,3,4,5,6,7,8,9,10 ".                     
                     "showRepeatEvent:true,false ".
                     "showPassInLog:1,0 ".
                     "timeout ".
                     "usedCalendars:--wait#for#Calendar#list-- ".
                     $readingFnAttributes;   
         
 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
# define SyncalBot SSCal 192.168.2.10 [5000] [HTTP(S)] 
#                   [1]      [2]        [3]      [4]  
#
################################################################
sub SSCal_Define($@) {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SSCalMM." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SSCalMM);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
      return "You need to specify more parameters.\n". "Format: define <name> SSCal <ServerAddress> [Port] [HTTP(S)] [Tasks]";
  }
  
  shift @a; shift @a;
  my $addr = $a[0]  if($a[0] ne "Tasks");
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
  CommandAttr(undef,"$name event-on-update-reading .*Summary.*,state");
  
  %SSCal_api = (
    "APIINFO"   => { "NAME" => "SYNO.API.Info" },               # Info-Seite für alle API's, einzige statische Seite !                                                    
    "APIAUTH"   => { "NAME" => "SYNO.API.Auth" },               # API used to perform session login and logout  
    "CALCAL"    => { "NAME" => "SYNO.Cal.Cal" },                # API to manipulate calendar
    "CALEVENT"  => { "NAME" => "SYNO.Cal.Event" },              # Provide methods to manipulate events in the specific calendar
    "CALSHARE"  => { "NAME" => "SYNO.Cal.Sharing" },            # Get/set sharing setting of calendar
    "CALTODO"   => { "NAME" => "SYNO.Cal.Todo" },               # Provide methods to manipulate events in the specific calendar
  ); 
  
  # Versionsinformationen setzen
  SSCal_setVersionInfo($hash);
  
  # Credentials lesen
  SSCal_getcredentials($hash,1,"credentials");
  
  # Index der Sendequeue initialisieren
  $data{SSCal}{$name}{sendqueue}{index} = 0;
    
  readingsBeginUpdate         ($hash);
  readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
  readingsBulkUpdateIfChanged ($hash, "Error",     "none");   
  readingsBulkUpdateIfChanged ($hash, "QueueLenth", 0);                          # Länge Sendqueue initialisieren
  readingsBulkUpdate          ($hash, "nextUpdate", "Manual");                   # Abrufmode initial auf "Manual" setzen   
  readingsBulkUpdate          ($hash, "state", "Initialized");                   # Init state
  readingsEndUpdate           ($hash,1);              

  # initiale Routinen nach Start ausführen , verzögerter zufälliger Start
  SSCal_initonboot($name);

return undef;
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
sub SSCal_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  BlockingKill($hash->{HELPER}{RUNNING_PID}) if($hash->{HELPER}{RUNNING_PID});
  delete $data{SSCal}{$name};
  RemoveInternalTimer($name);
   
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub SSCal_DelayedShutdown($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  if($hash->{HELPER}{SID}) {
      SSCal_logout($hash);                      # Session alter User beenden falls vorhanden  
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
sub SSCal_Delete($$) {
  my ($hash, $arg) = @_;
  my $name  = $hash->{NAME};
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
  
  # gespeicherte Credentials löschen
  setKeyValue($index, undef);
    
return undef;
}

################################################################
sub SSCal_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash  = $defs{$name};
	my $model = $hash->{MODEL};
    my ($do,$val,$cache);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
	
	if ($cmd eq "set") {
		if ($aName =~ /filterCompleteTask|filterDueTask/ && $model ne "Tasks") {            
			return " The attribute \"$aName\" is only valid for devices of MODEL \"Tasks\"! Please set this attribute in a device of this model.";
		}
		
		if ($aName =~ /showRepeatEvent/ && $model ne "Diary") {            
			return " The attribute \"$aName\" is only valid for devices of MODEL \"Diary\"! Please set this attribute in a device of this model.";
		}
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
            InternalTimer(gettimeofday()+2, "SSCal_initonboot", $name, 0) if($init_done); 
		}
    
        readingsBeginUpdate($hash); 
        readingsBulkUpdate ($hash, "state", $val);                    
        readingsEndUpdate  ($hash,1); 
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/timeout|cutLaterDays|cutOlderDays|interval/) {
            unless ($aVal =~ /^\d+$/) { return "The Value for $aName is not valid. Use only figures 1-9 !";}
        }     
        if($aName =~ m/interval/) {
            RemoveInternalTimer($name,"SSCal_periodicCall");
            if($aVal > 0) {
                InternalTimer(gettimeofday()+1.0, "SSCal_periodicCall", $name, 0);
            }
        }      
    }
    
return undef;
}

################################################################
sub SSCal_Set($@) {
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
  
  my $idxlist = join(",", SSCal_sortVersion("asc",keys %{$data{SSCal}{$name}{sendqueue}{entries}}));
  
  # alle aktuell angezeigten Event Id's  ermitteln
  my (@idarray,$evids);
  foreach my $key (keys %{$defs{$name}{READINGS}}) {
      next if $key !~ /^.*_EventId$/;
      push (@idarray, $defs{$name}{READINGS}{$key}{VAL});   
  }
  
  if(@idarray) {
      my %seen;
      my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @idarray;                        # distinct / unique the keys
      $evids     = join(",", @unique);
  }
  
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
	             "credentials "
                 ;  
  } elsif ($model eq "Diary") {
      $setlist = "Unknown argument $opt, choose one of ".
                 "calEventList ".
                 "credentials ".
                 ($evids?"deleteEventId:$evids ":"deleteEventId:noArg ").
                 "eraseReadings:noArg ".
                 "listSendqueue:noArg ".
                 "logout:noArg ".
                 ($idxlist?"purgeSendqueue:-all-,-permError-,$idxlist ":"purgeSendqueue:-all-,-permError- ").
                 "restartSendqueue:noArg "
                 ;
  } else {                                                                      # Model ist "Tasks"
      $setlist = "Unknown argument $opt, choose one of ".
                 "calToDoList ".
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
 
  if ($opt eq "credentials") {
      return "The command \"$opt\" needs an argument." if (!$prop); 
      SSCal_logout($hash) if($hash->{HELPER}{SID});                      # Session alter User beenden falls vorhanden      
      ($success) = SSCal_setcredentials($hash,$prop,$prop1);
	  
	  if($success) {
		  SSCal_addQueue($name,"listcal","CALCAL","list","&is_todo=true&is_evt=true");            
          SSCal_getapisites($name);
          return "credentials saved successfully";
	  } else {
          return "Error while saving credentials - see logfile for details";
	  }
      
  } elsif ($opt eq "listSendqueue") {
      my $sub = sub ($) { 
          my ($idx) = @_;
          my $ret;          
          foreach my $key (reverse sort keys %{$data{SSCal}{$name}{sendqueue}{entries}{$idx}}) {
              $ret .= ", " if($ret);
              $ret .= $key."=>".$data{SSCal}{$name}{sendqueue}{entries}{$idx}{$key};
          }
          return $ret;
      };
	    
      if (!keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
          return "SendQueue is empty.";
      }
      my $sq;
	  foreach my $idx (sort{$a<=>$b} keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
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
	      foreach my $idx (keys %{$data{SSCal}{$name}{sendqueue}{entries}}) { 
              delete $data{SSCal}{$name}{sendqueue}{entries}{$idx} 
                  if($data{SSCal}{$name}{sendqueue}{entries}{$idx}{forbidSend}); 			
          }
          return "All entries with state \"permanent send error\" are deleted";
      } else {
          delete $data{SSCal}{$name}{sendqueue}{entries}{$prop};
          return "SendQueue entry with index \"$prop\" deleted";
      }
  
  } elsif ($opt eq "calEventList") {                                                          # Termine einer Cal_id (Liste) in Zeitgrenzen abrufen 	  
      return "Obtain the Calendar list first with \"get $name getCalendars\" command." if(!$hash->{HELPER}{CALFETCHED});
	  my ($err,$tstart,$tend) = SSCal_timeEdge ($name);
      
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
	  
	  my $cals = AttrVal($name,"usedCalendars", "");
      
      shift @a; shift @a;
      my $c = join(" ", @a);
      $cals = $c?$c:$cals;
	  return "Please set attribute \"usedCalendars\" or specify the Calendar(s) you want read in \"$opt\" command." if(!$cals);
	  
      # Kalender aufsplitten und zu jedem die ID ermitteln
      my @ca = split(",", $cals);
	  my $oids;
      foreach (@ca) {                                         
          my $oid = $hash->{HELPER}{CALENDARS}{"$_"}{id};
          next if(!$oid);
          if ($hash->{HELPER}{CALENDARS}{"$_"}{type} ne "Event") {
              Log3($name, 3, "$name - The Calendar \"$_\" is not of type \"Event\" and will be ignored.");
              next;
          }          
		  $oids .= "," if($oids);
		  $oids .= '"'.$oid.'"';
		  Log3($name, 2, "$name - WARNING - The Calendar \"$_\" seems to be unknown because its ID couldn't be found.") if(!$oid);
      }
	  
	  return "No Calendar of type \"Event\" was selected or its ID(s) couldn't be found." if(!$oids);
      
      Log3($name, 5, "$name - Calendar selection for add queue: $cals");
      my $lr = AttrVal($name,"showRepeatEvent", "true");
	  SSCal_addQueue($name,"eventlist","CALEVENT","list","&cal_id_list=[$oids]&start=$tstart&end=$tend&list_repeat=$lr"); 
      SSCal_getapisites($name);
  
  } elsif ($opt eq "calToDoList") {                                                          # Aufgaben einer Cal_id (Liste) abrufen 	  
      return "Obtain the Calendar list first with \"get $name getCalendars\" command." if(!$hash->{HELPER}{CALFETCHED});  
	  
	  my $cals = AttrVal($name,"usedCalendars", "");
      
      shift @a; shift @a;
      my $c = join(" ", @a);
      $cals = $c?$c:$cals;
	  return "Please set attribute \"usedCalendars\" or specify the Calendar(s) you want read in \"$opt\" command." if(!$cals);
	  
      # Kalender aufsplitten und zu jedem die ID ermitteln
      my @ca = split(",", $cals);
	  my $oids;
      foreach (@ca) {                                         
          my $oid = $hash->{HELPER}{CALENDARS}{"$_"}{id};
          next if(!$oid);
          if ($hash->{HELPER}{CALENDARS}{"$_"}{type} ne "ToDo") {
              Log3($name, 3, "$name - The Calendar \"$_\" is not of type \"ToDo\" and will be ignored.");
              next;
          }          
		  $oids .= "," if($oids);
		  $oids .= '"'.$oid.'"';
		  Log3($name, 2, "$name - WARNING - The Calendar \"$_\" seems to be unknown because its ID couldn't be found.") if(!$oid);
      }
	  
	  return "No Calendar of type \"ToDo\" was selected or its ID(s) couldn't be found." if(!$oids);
      
      Log3($name, 5, "$name - Calendar selection for add queue: $cals");
      
      my $limit          = "";                                      # Limit of matched tasks
      my $offset         = 0;                                       # offset of mnatched tasks
      my $filterdue      = AttrVal($name,"filterDueTask", 3);       # show tasks with and without due time
      my $filtercomplete = AttrVal($name,"filterCompleteTask", 3);  # show completed and not completed tasks
      
	  SSCal_addQueue($name,"todolist","CALTODO","list","&cal_id_list=[$oids]&limit=$limit&offset=$offset&filter_due=$filterdue&filter_complete=$filtercomplete"); 
      SSCal_getapisites($name);
  
  } elsif ($opt eq "cleanCompleteTasks") {                                                          # erledigte Aufgaben einer Cal_id (Liste) löschen 	  
      return "Obtain the Calendar list first with \"get $name getCalendars\" command." if(!$hash->{HELPER}{CALFETCHED});  
	  
	  my $cals = AttrVal($name,"usedCalendars", "");
      
      shift @a; shift @a;
      my $c = join(" ", @a);
      $cals = $c?$c:$cals;
	  return "Please set attribute \"usedCalendars\" or specify the Calendar(s) you want read in \"$opt\" command." if(!$cals);
	  
      # Kalender aufsplitten und zu jedem die ID ermitteln
      my @ca = split(",", $cals);
	  my $oids;
      foreach (@ca) {                                         
          my $oid = $hash->{HELPER}{CALENDARS}{"$_"}{id};
          next if(!$oid);
          if ($hash->{HELPER}{CALENDARS}{"$_"}{type} ne "ToDo") {
              Log3($name, 3, "$name - The Calendar \"$_\" is not of type \"ToDo\" and will be ignored.");
              next;
          }          
		  $oids .= "," if($oids);
		  $oids .= '"'.$oid.'"';
		  Log3($name, 2, "$name - WARNING - The Calendar \"$_\" seems to be unknown because its ID couldn't be found.") if(!$oid);
      }
	  
	  return "No Calendar of type \"ToDo\" was selected or its ID(s) couldn't be found." if(!$oids);
      
      Log3($name, 5, "$name - Calendar selection for add queue: $cals");
      
	  # <Name, operation mode, API (siehe %SSCal_api), auszuführende API-Methode, spezifische API-Parameter>
	  SSCal_addQueue($name,"cleanCompleteTasks","CALTODO","clean_complete","&cal_id_list=[$oids]"); 
      SSCal_getapisites($name);
  
  } elsif ($opt eq "deleteEventId") {
      return "You must specify an event id (Reading EventId) what is to be deleted." if(!$prop);
      
      my $eventid = $prop;
      
      # Blocknummer ermitteln
      my $bnr;
      my @allrds = keys%{$defs{$name}{READINGS}};
      foreach my $key(@allrds) {
          next if $key !~ /^.*_EventId$/;
          $bnr = (split("_", $key))[0] if($defs{$name}{READINGS}{$key}{VAL} == $eventid);   # Blocknummer ermittelt 
      }
      
      return "The blocknumber of specified event id could not be identified. Make sure you have specified a valid event id." if(!$bnr);

      # die Summary zur Event Id ermitteln
      my $sum = ReadingsVal($name, $bnr."_01_Summary", "");

      # Kalendername und dessen id und Typ ermitteln 
      my $calname = ReadingsVal($name, $bnr."_90_calName", "");
      my $calid   = $hash->{HELPER}{CALENDARS}{"$calname"}{id};
      my $caltype = $hash->{HELPER}{CALENDARS}{"$calname"}{type};
      
      # Kalender-API in Abhängigkeit des Kalendertyps wählen
      my $api = ($caltype eq "Event")?"CALEVENT":"CALTODO";
      
      Log3($name, 3, "$name - The event \"$sum\" with id \"$eventid\" will be deleted in calendar \"$calname\".");
      
	  # <Name, operation mode, API (siehe %SSCal_api), auszuführende API-Methode, spezifische API-Parameter>
	  SSCal_addQueue($name,"deleteEventId",$api,"delete","&evt_id=$eventid"); 
      SSCal_getapisites($name);      
  
  } elsif ($opt eq "restartSendqueue") {
      my $ret = SSCal_getapisites($name);
      if($ret) {
          return $ret;
      } else {
          return "The SendQueue has been restarted.";
      }
      
  } elsif ($opt eq 'eraseReadings') {		
        SSCal_delReadings($name,0);                                                    # Readings löschen
    
  } elsif ($opt eq 'logout') {		
        SSCal_logout($hash);                                     
    
  } else {
      return "$setlist"; 
  }
  
return;
}

################################################################
sub SSCal_Get($@) {
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
              
    if ($opt eq "storedCredentials") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials <CREDENTIALS>\"";}
        # Credentials abrufen
        my ($success, $username, $passwd) = SSCal_getcredentials($hash,0,"credentials");
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        
        return "Stored Credentials:\n".
               "===================\n".
               "Username: $username, Password: $passwd \n"
               ;   
    
	} elsif ($opt eq "apiInfo") {                                                         # Liste aller Kalender abrufen
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSCal_getclhash($hash,1);
        $hash->{HELPER}{APIPARSET} = 0;                                                   # Abruf API Infos erzwingen

        # <Name, operation mode, API (siehe %SSCal_api), auszuführende API-Methode, spezifische API-Parameter>
		SSCal_addQueue($name,"apiInfo","","","");            
        SSCal_getapisites($name);
  
    } elsif ($opt eq "getCalendars") {                                                    # Liste aller Kalender abrufen
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSCal_getclhash($hash,1);
		
		SSCal_addQueue($name,"listcal","CALCAL","list","&is_todo=true&is_evt=true");            
        SSCal_getapisites($name);
  
    } elsif ($opt eq "calAsHtml") {                                                    
        my $out = SSCal_calAsHtml($name);
        return $out;
  
    } elsif ($opt =~ /versionNotes/) {
	    my $header  = "<b>Module release information</b><br>";
        my $header1 = "<b>Helpful hints</b><br>";
        my %hs;
	  
	    # Ausgabetabelle erstellen
	    my ($ret,$val0,$val1);
        my $i = 0;
	  
        $ret  = "<html>";
      
        # Hints
        if(!$arg || $arg =~ /hints/ || $arg =~ /[\d]+/) {
            $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
            $ret .= "<table class=\"block wide internals\">";
            $ret .= "<tbody>";
            $ret .= "<tr class=\"even\">";  
            if($arg && $arg =~ /[\d]+/) {
                my @hints = split(",",$arg);
                foreach (@hints) {
                    if(AttrVal("global","language","EN") eq "DE") {
                        $hs{$_} = $SSCal_vHintsExt_de{$_};
                    } else {
                        $hs{$_} = $SSCal_vHintsExt_en{$_};
                    }
                }                      
            } else {
                if(AttrVal("global","language","EN") eq "DE") {
                    %hs = %SSCal_vHintsExt_de;
                } else {
                    %hs = %SSCal_vHintsExt_en; 
                }
            }          
            $i = 0;
            foreach my $key (SSCal_sortVersion("desc",keys %hs)) {
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
        if(!$arg || $arg =~ /rel/) {
            $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
            $ret .= "<table class=\"block wide internals\">";
            $ret .= "<tbody>";
            $ret .= "<tr class=\"even\">";
            $i = 0;
            foreach my $key (SSCal_sortVersion("desc",keys %SSCal_vNotesExtern)) {
                ($val0,$val1) = split(/\s/,$SSCal_vNotesExtern{$key},2);
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
sub SSCal_FWdetailFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_;           
  my $hash = $defs{$d};
  my $ret  = "";
  
  $hash->{".calhtml"} = SSCal_calAsHtml($d);

  if($hash->{".calhtml"} ne "" && !$room && AttrVal($d,"calOverviewInDetail",1)) {    # Anzeige Übersicht in Detailansicht
      $ret .= $hash->{".calhtml"};
      return $ret;
  } 
  
  if($hash->{".calhtml"} ne "" && $room && AttrVal($d,"calOverviewInRoom",1)) {       # Anzeige in Raumansicht zusätzlich zur Statuszeile
      $ret = $hash->{".calhtml"};
      return $ret;
  }

return undef;
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub SSCal_initonboot ($) {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my ($ret);
  
  RemoveInternalTimer($name, "SSCal_initonboot");
  
  if ($init_done) {
	  CommandGet(undef, "$name getCalendars");                      # Kalender Liste initial abrufen     
  } else {
      InternalTimer(gettimeofday()+3, "SSCal_initonboot", $name, 0);
  }
  
return;
}

#############################################################################################
#      regelmäßiger Intervallabruf
#############################################################################################
sub SSCal_periodicCall($) {
  my ($name)   = @_;
  my $hash     = $defs{$name};
  my $interval = AttrVal($name, "interval", 0);
  my $model    = $hash->{MODEL};
  my $new;
   
  if(!$interval) {
      $hash->{MODE} = "Manual";
  } else {
      $new          = gettimeofday()+$interval;
      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "nextUpdate", "Automatic - next polltime: ".FmtTime($new));     # Abrufmode initial auf "Manual" setzen   
      readingsEndUpdate   ($hash,1);
  }
  
  RemoveInternalTimer($name,"SSCal_periodicCall");
  return if(!$interval);
  
  if($hash->{CREDENTIALS} && !IsDisabled($name)) {
      if($model eq "Diary") { CommandSet(undef, "$name calEventList") };                      # Einträge aller gewählter Terminkalender abrufen (in Queue stellen)
	  if($model eq "Tasks") { CommandSet(undef, "$name calToDoList")  };                      # Einträge aller gewählter Aufgabenlisten abrufen (in Queue stellen)
  }
  
  InternalTimer($new, "SSCal_periodicCall", $name, 0);
    
return;  
}

######################################################################################
#                            Eintrag zur SendQueue hinzufügen
#    $name   = Name Kalenderdevice
#    $opmode = operation mode
#    $api    = API (siehe %SSCal_api)
#    $method = auszuführende API-Methode 
#    $params = spezifische API-Parameter 
#
######################################################################################
sub SSCal_addQueue ($$$$$) {
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

   SSCal_updQLength ($hash);                        # updaten Länge der Sendequeue     
   
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
sub SSCal_checkretry ($$) {  
  my ($name,$retry) = @_;
  my $hash          = $defs{$name};  
  my $idx           = $hash->{OPIDX};
  my $forbidSend    = "";
  
  if(!keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
      Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
      SSCal_updQLength ($hash);
      return;  
  } 
  
  if(!$retry) {                                                     # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{SSCal}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, "$name - Opmode \"$hash->{OPMODE}\" finished successfully, Sendqueue index \"$idx\" deleted.");
      SSCal_updQLength ($hash);
      return SSCal_getapisites($name);                              # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer)
  
  } else {                                                          # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{SSCal}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{SSCal}{$name}{sendqueue}{entries}{$idx}{retryCount};
  
      my $errorcode = ReadingsVal($name, "Errorcode", 0);
      if($errorcode =~ /119/) {
          delete $hash->{HELPER}{SID};
      }
      if($errorcode =~ /100|101|103|117|120|407|409|800|900/) {         # bei diesen Errorcodes den Queueeintrag nicht wiederholen, da dauerhafter Fehler !
          $forbidSend = SSCal_experror($hash,$errorcode);               # Fehlertext zum Errorcode ermitteln
          $data{SSCal}{$name}{sendqueue}{entries}{$idx}{forbidSend} = $forbidSend;
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. It seems to be a permanent error. Exclude it from new send attempt !");
          
          delete $hash->{OPIDX};
          delete $hash->{OPMODE};
          
          SSCal_updQLength ($hash);                                 # updaten Länge der Sendequeue
          
          return SSCal_getapisites($name);                          # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer);
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
          SSCal_updQLength ($hash,$rst);                           # updaten Länge der Sendequeue mit resend Timer
          
          RemoveInternalTimer($name, "SSCal_getapisites");
          InternalTimer($rst, "SSCal_getapisites", "$name", 0);
      }
  }

return
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub SSCal_getapisites($) {
   my ($name)     = @_;
   my $hash       = $defs{$name};
   my $addr       = $hash->{ADDR};
   my $port       = $hash->{PORT};
   my $prot       = $hash->{PROT};  
   my ($url,$param,$idxset,$ret);
   
   $hash->{HELPER}{LOGINRETRIES} = 0;
   
   my ($err,$tstart,$tend) = SSCal_timeEdge($name);
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
   foreach my $idx (sort{$a<=>$b} keys %{$data{SSCal}{$name}{sendqueue}{entries}}) {
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
       return SSCal_checkSID($name);
   }

   my $timeout = AttrVal($name,"timeout",20);
   Log3($name, 5, "$name - HTTP-Call will be done with timeout: $timeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "$prot://$addr:$port/webapi/query.cgi?api=$SSCal_api{APIINFO}{NAME}&method=Query&version=1&query=$SSCal_api{APIAUTH}{NAME},$SSCal_api{CALCAL}{NAME},$SSCal_api{CALEVENT}{NAME},$SSCal_api{CALSHARE}{NAME},$SSCal_api{CALTODO}{NAME},$SSCal_api{APIINFO}{NAME}";

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
               url      => $url,
               timeout  => $timeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSCal_getapisites_parse
            };
   HttpUtils_NonblockingGet ($param);  

return;
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub SSCal_getapisites_parse ($) {
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
        
        SSCal_checkretry($name,1);
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash,$success,$myjson) = SSCal_evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            SSCal_checkretry($name,1);       
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my $logstr;
                        
          # Pfad und Maxversion von "SYNO.API.Auth" ermitteln
            my $apiauthpath   = $data->{data}->{$SSCal_api{APIAUTH}{NAME}}->{path};
            $apiauthpath      =~ tr/_//d if (defined($apiauthpath));
            my $apiauthmaxver = $data->{data}->{$SSCal_api{APIAUTH}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apiauthpath) ? "Path of $SSCal_api{APIAUTH}{NAME} selected: $apiauthpath" : "Path of $SSCal_api{APIAUTH}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiauthmaxver) ? "MaxVersion of $SSCal_api{APIAUTH}{NAME} selected: $apiauthmaxver" : "MaxVersion of $SSCal_api{APIAUTH}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
			       
          # Pfad und Maxversion von "SYNO.Cal.Cal" ermitteln
            my $apicalpath   = $data->{data}->{$SSCal_api{CALCAL}{NAME}}->{path};
            $apicalpath      =~ tr/_//d if (defined($apicalpath));
            my $apicalmaxver = $data->{data}->{$SSCal_api{CALCAL}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apicalpath) ? "Path of $SSCal_api{CALCAL}{NAME} selected: $apicalpath" : "Path of $SSCal_api{CALCAL}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apicalmaxver) ? "MaxVersion of $SSCal_api{CALCAL}{NAME} selected: $apicalmaxver" : "MaxVersion of $SSCal_api{CALCAL}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");            
            
          # Pfad und Maxversion von "SYNO.Cal.Event" ermitteln
            my $apievtpath   = $data->{data}->{$SSCal_api{CALEVENT}{NAME}}->{path};
            $apievtpath      =~ tr/_//d if (defined($apievtpath));
            my $apievtmaxver = $data->{data}->{$SSCal_api{CALEVENT}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apievtpath) ? "Path of $SSCal_api{CALEVENT}{NAME} selected: $apievtpath" : "Path of $SSCal_api{CALEVENT}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apievtmaxver) ? "MaxVersion of $SSCal_api{CALEVENT}{NAME} selected: $apievtmaxver" : "MaxVersion of $SSCal_api{CALEVENT}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr"); 

          # Pfad und Maxversion von "SYNO.Cal.Sharing" ermitteln
            my $apisharepath   = $data->{data}->{$SSCal_api{CALSHARE}{NAME}}->{path};
            $apisharepath      =~ tr/_//d if (defined($apisharepath));
            my $apisharemaxver = $data->{data}->{$SSCal_api{CALSHARE}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apisharepath) ? "Path of $SSCal_api{CALSHARE}{NAME} selected: $apisharepath" : "Path of $SSCal_api{CALSHARE}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apisharemaxver) ? "MaxVersion of $SSCal_api{CALSHARE}{NAME} selected: $apisharemaxver" : "MaxVersion of $SSCal_api{CALSHARE}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr"); 

          # Pfad und Maxversion von "SYNO.Cal.Todo" ermitteln
            my $apitodopath   = $data->{data}->{$SSCal_api{CALTODO}{NAME}}->{path};
            $apitodopath      =~ tr/_//d if (defined($apitodopath));
            my $apitodomaxver = $data->{data}->{$SSCal_api{CALTODO}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apitodopath) ? "Path of $SSCal_api{CALTODO}{NAME} selected: $apitodopath" : "Path of $SSCal_api{CALTODO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apitodomaxver) ? "MaxVersion of $SSCal_api{CALTODO}{NAME} selected: $apitodomaxver" : "MaxVersion of $SSCal_api{CALTODO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");

          # Pfad und Maxversion von "SYNO.API.Info" ermitteln
            my $apiinfopath   = $data->{data}->{$SSCal_api{APIINFO}{NAME}}->{path};
            $apiinfopath      =~ tr/_//d if (defined($apiinfopath));
            my $apiinfomaxver = $data->{data}->{$SSCal_api{APIINFO}{NAME}}->{maxVersion}; 
       
            $logstr = defined($apiinfopath) ? "Path of $SSCal_api{APIINFO}{NAME} selected: $apiinfopath" : "Path of $SSCal_api{APIINFO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiinfomaxver) ? "MaxVersion of $SSCal_api{APIINFO}{NAME} selected: $apiinfomaxver" : "MaxVersion of $SSCal_api{APIINFO}{NAME} undefined - Synology cal Server may be stopped";
            Log3($name, 4, "$name - $logstr");             
            
            
            # ermittelte Werte in $hash einfügen
            $SSCal_api{APIINFO}{PATH}   = $apiinfopath;
            $SSCal_api{APIINFO}{MAX}    = $apiinfomaxver;
            $SSCal_api{APIAUTH}{PATH}   = $apiauthpath;
            $SSCal_api{APIAUTH}{MAX}    = $apiauthmaxver;            
            $SSCal_api{CALCAL}{PATH}    = $apicalpath;
            $SSCal_api{CALCAL}{MAX}     = $apicalmaxver;
            $SSCal_api{CALEVENT}{PATH}  = $apievtpath;
            $SSCal_api{CALEVENT}{MAX}   = $apievtmaxver;            
            $SSCal_api{CALSHARE}{PATH}  = $apisharepath;
            $SSCal_api{CALSHARE}{MAX}   = $apisharemaxver;
            $SSCal_api{CALTODO}{PATH}   = $apitodopath;
            $SSCal_api{CALTODO}{MAX}    = $apitodomaxver;
        
            # API values sind gesetzt in Hash
            $hash->{HELPER}{APIPARSET} = 1;
            
            if ($opmode eq "apiInfo") {                                     # API Infos in Popup anzeigen             
                my $out  = "<html>";
                $out    .= "<b>Synology Calendar API Info</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>API</b> </td><td> <b>Path</b> </td><td> <b>Version</b> </td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td></tr>";
        
                foreach my $key (keys %SSCal_api) {
                    my $apiname = $SSCal_api{$key}{NAME};
                    my $apipath = $SSCal_api{$key}{PATH};
                    my $apiver  = $SSCal_api{$key}{MAX};

                    $out  .= "<tr><td> $apiname </td><td> $apipath </td><td> $apiver</td></tr>";
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
              
                SSCal_checkretry($name,0);
                return;
            }
                        
        } else {
            $errorcode = "806";
            $error     = SSCal_experror($hash,$errorcode);                  # Fehlertext zum Errorcode ermitteln
            
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash, "Error",     $error);
            readingsBulkUpdate          ($hash,"state",      "Error");
            readingsEndUpdate           ($hash, 1);

            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
            
            SSCal_checkretry($name,1);    
            return;
        }
	}
    
return SSCal_checkSID($name);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub SSCal_calop ($) {  
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

   Log3($name, 4, "$name - start SendQueue entry index \"$idx\" ($hash->{OPMODE}) for operation."); 

   $timeout = AttrVal($name, "timeout", 20);
   
   Log3($name, 5, "$name - HTTP-Call will be done with timeout: $timeout s");
        
   $url = "$prot://$addr:$port/webapi/".$SSCal_api{$api}{PATH}."?api=".$SSCal_api{$api}{NAME}."&version=".$SSCal_api{$api}{MAX}."&method=$method".$params."&_sid=$sid";
   
   if($opmode eq "deleteEventId" && $api eq "CALEVENT") {               # Workaround !!! Methode delete funktioniert nicht mit SYNO.Cal.Event version > 1
       $url = "$prot://$addr:$port/webapi/".$SSCal_api{$api}{PATH}."?api=".$SSCal_api{$api}{NAME}."&version=1&method=$method".$params."&_sid=$sid";
   }

   my $part = $url;
   if(AttrVal($name, "showPassInLog", "0") == 1) {
       Log3($name, 4, "$name - Call-Out: $url");
   } else {
       $part =~ s/$sid/<secret>/;
       Log3($name, 4, "$name - Call-Out: $part");
   }
   
   $param = {
            url      => $url,
            timeout  => $timeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&SSCal_calop_parse
            };
   
   HttpUtils_NonblockingGet ($param);   
} 
  
#############################################################################################
#                                Callback from SSCal_calop
#############################################################################################
sub SSCal_calop_parse ($) {  
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
        $errorcode = "800" if($err =~ /: malformed or unsupported URL$/s);

        readingsBeginUpdate         ($hash); 
        readingsBulkUpdateIfChanged ($hash, "Error",           $err);
        readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
        readingsBulkUpdate          ($hash, "state",        "Error");                    
        readingsEndUpdate           ($hash,1);         

        SSCal_checkretry($name,1);        
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden 
        ($hash,$success,$myjson) = SSCal_evaljson($hash,$myjson);        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            SSCal_checkretry($name,1);       
            return;
        }
        
        $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};

        if ($success) {       

            if ($opmode eq "listcal") {                                     # alle Kalender abrufen
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
                foreach (@deva) {
                     push @newa, $_ if($_ !~ /usedCalendars:/);
                }

     		    $cals =~ s/ /#/g if($cals);
	
                push @newa, ($cals?"usedCalendars:multiple-strict,$cals ":"usedCalendars:--no#Calendar#selectable--");
                
                $hash->{".AttrList"} = join(" ", @newa);              # Device spezifische AttrList, überschreibt Modul AttrList !      

				# Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$out");
				delete($hash->{HELPER}{CL});  
                
                SSCal_checkretry($name,0);

                readingsBeginUpdate         ($hash); 
                readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
                readingsBulkUpdateIfChanged ($hash, "Error",      "none");                  
                readingsBulkUpdate          ($hash, "state",      "done");                    
                readingsEndUpdate           ($hash,1); 
            
			} elsif ($opmode eq "eventlist") {                          # Events der ausgewählten Kalender aufbereiten 
                delete $data{SSCal}{$name}{eventlist};                  # zentrales Event/ToDo Hash löschen
                $hash->{eventlist} = $data;                             # Data-Hashreferenz im Hash speichern
               
                if ($am) {                                              # Extrahieren der Events asynchron (nicht-blockierend)
                    Log3($name, 4, "$name - Event parse mode: asynchronous");
                    my $timeout = AttrVal($name, "timeout", 20)+180;
                    
                    $hash->{HELPER}{RUNNING_PID}           = BlockingCall("SSCal_extractEventlist", $name, "SSCal_createReadings", $timeout, "SSCal_blockingTimeout", $hash);
                    $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057                    
                
                } else {                                                # Extrahieren der Events synchron (blockierend)
                    Log3($name, 4, "$name - Event parse mode: synchronous");
                    SSCal_extractEventlist ($name);                         
                }    
            
            } elsif ($opmode eq "todolist") {                           # ToDo's der ausgewählten Tasks-Kalender aufbereiten
                delete $data{SSCal}{$name}{eventlist};                  # zentrales Event/ToDo Hash löschen
                $hash->{eventlist} = $data;                             # Data-Hashreferenz im Hash speichern
               
                if ($am) {                                              # Extrahieren der ToDos asynchron (nicht-blockierend)
                    Log3($name, 4, "$name - Task parse mode: asynchronous");
                    my $timeout = AttrVal($name, "timeout", 20)+180;
                    
                    $hash->{HELPER}{RUNNING_PID}           = BlockingCall("SSCal_extractToDolist", $name, "SSCal_createReadings", $timeout, "SSCal_blockingTimeout", $hash);
                    $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057                    
                
                } else {                                                # Extrahieren der ToDos synchron (blockierend)
                    Log3($name, 4, "$name - Task parse mode: synchronous");
                    SSCal_extractToDolist ($name);                         
                }
                
            } elsif ($opmode eq "cleanCompleteTasks") {                  # abgeschlossene ToDos wurden gelöscht                

                readingsBeginUpdate         ($hash); 
                readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
                readingsBulkUpdateIfChanged ($hash, "Error",      "none");                  
                readingsBulkUpdate          ($hash, "state",      "done");                    
                readingsEndUpdate           ($hash,1); 
                
                Log3($name, 3, "$name - All completed tasks were deleted from selected ToDo lists");
                
                SSCal_checkretry($name,0);
            
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
                my $set = ($api eq "CALEVENT")?"calEventList":"calToDoList";
                
                SSCal_checkretry($name,0);
                
                # Kalendereinträge neu einlesen nach dem löschen Event Id
                CommandSet(undef, "$name $set");
                
            }					
           
        } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{error}->{code};
            $cherror   = $data->{error}->{errors};                       # vom cal gelieferter Fehler
            $error     = SSCal_experror($hash,$errorcode);               # Fehlertext zum Errorcode ermitteln
            if ($error =~ /not found/) {
                $error .= " New error: ".($cherror?$cherror:"");
            }
			
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash,"Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash,"Error",     $error);
            readingsBulkUpdate          ($hash,"state",     "Error");
            readingsEndUpdate           ($hash, 1);
       
            Log3($name, 2, "$name - ERROR - Operation $opmode was not successful. Errorcode: $errorcode - $error");
            
            SSCal_checkretry($name,1);
        }
                
       undef $data;
       undef $myjson;
   }

return;
}

#############################################################################################
#                    Extrahiert empfangene Kalendertermine (Events)
#############################################################################################
sub SSCal_extractEventlist ($) { 
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $data   = delete $hash->{eventlist};
  my $am     = AttrVal($name, "asyncMode", 0);
  
  my ($tz,$bdate,$btime,$bts,$edate,$etime,$ets,$ci,$bi,$ei,$startEndDiff);
  my ($bmday,$bmonth,$emday,$emonth,$byear,$eyear,$nbdate,$nbtime,$nbts,$nedate,$netime,$nets);
  my @row_array;
  
  my (undef,$tstart,$tend) = SSCal_timeEdge($name);       # Sollstart- und Sollendezeit der Kalenderereignisse ermitteln
  my $datetimestart        = FmtDateTime($tstart);
  my $datetimeend          = FmtDateTime($tend);
       
  my $n = 0;       
  foreach my $key (keys %{$data->{data}}) {
      my $i = 0;
  
      while ($data->{data}{$key}[$i]) {
          my $ignore = 0; 
          my $done   = 0;
          ($nbdate,$nedate) = ("","");		
          
          ($bi,$tz,$bdate,$btime,$bts)   = SSCal_explodeDateTime ($hash,$data->{data}{$key}[$i]{dtstart});    # Beginn des Events
          ($ei,undef,$edate,$etime,$ets) = SSCal_explodeDateTime ($hash,$data->{data}{$key}[$i]{dtend});      # Ende des Events
          $startEndDiff = $ets - $bts;                                                                        # Differenz Event Ende / Start in Sekunden
  
          $bdate  =~ /(\d{4})-(\d{2})-(\d{2})/;
          $bmday  = $3;
          $bmonth = $2;
          $byear  = $1;
          $nbtime = $btime;                
          
          $edate  =~ /(\d{4})-(\d{2})-(\d{2})/;
          $emday  = $3;
          $emonth = $2;
          $eyear  = $1;
          $netime = $etime;
                                              
          if(!$data->{data}{$key}[$i]{is_repeat_evt}) {                         # einmaliger Event
              Log3($name, 5, "$name - Single event Begin: $bdate, End: $edate");
              
              if($ets < $tstart || $bts > $tend) {
                  Log3($name, 4, "$name - Ignore single event -> $data->{data}{$key}[$i]{summary} start: $bdate $btime, end: $edate $etime");
                  $ignore = 1;
                  $done   = 0; 
              } else {
                  @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
                  $ignore = 0;
                  $done   = 1;
              }       
          
          } elsif ($data->{data}{$key}[$i]{is_repeat_evt}) {                    # Event ist wiederholend
              Log3($name, 5, "$name - Recurring event Begin: $bdate, End: $edate");
              
              my ($freq,$count,$interval,$until,$uets,$bymonthday,$byday);
              my $rr = $data->{data}{$key}[$i]{evt_repeat_setting}{repeat_rule};
              
              # Format: FREQ=YEARLY;COUNT=1;INTERVAL=2;BYMONTHDAY=15;BYMONTH=10;UNTIL=2020-12-31T00:00:00
              my @para  = split(";", $rr);
              
              foreach my $par (@para) {
                  my ($p1,$p2) = split("=", $par);
                  if ($p1 eq "FREQ") {
                      $freq = $p2;
                  } elsif ($p1 eq "COUNT") {                                    # Event endet automatisch nach x Wiederholungen
                      $count = $p2;                                             
                  } elsif ($p1 eq "INTERVAL") {                                 # Wiederholungsintervall         
                      $interval = $p2;
                  } elsif ($p1 eq "UNTIL") {                                    # festes Intervallende angegeben        
                      $until = $p2;
                      $until =~ s/[-:]//g;
                      (undef,undef,undef,undef,$uets) = SSCal_explodeDateTime ($hash,$until);
                      if ($uets < $tstart) {
                          Log3($name, 4, "$name - Ignore recurring event -> $data->{data}{$key}[$i]{summary} , interval end \"$nedate $netime\" is less than selection start \"$datetimestart\"");
                          $ignore = 1;
                      }
                  } elsif ($p1 eq "BYMONTHDAY") {                               # Wiederholungseigenschaft -> Tag des Monats z.B. 13 (Tag 13)    
                      $bymonthday = $p2;
                  } elsif ($p1 eq "BYDAY") {                                    # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                          $byday = $p2;
                  } 
              }
              
              $count      = $count?$count:9999999;                              # $count "unendlich" wenn kein COUNT angegeben
              $interval   = $interval?$interval:1;
              $bymonthday = $bymonthday?$bymonthday:"";
              $byday      = $byday?$byday:"";
              $until      = $until?$until:"";
              
              Log3($name, 4, "$name - Recurring params - FREQ: $freq, COUNT: $count, INTERVAL: $interval, BYMONTHDAY: $bymonthday, BYDAY: $byday, UNTIL: $until");
                 
              if ($freq eq "YEARLY") {                                          # jährliche Wiederholung                             
                  for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {                                    
                      $byear += ($ci>=0?1:0);
                      $eyear += ($ci>=0?1:0);
                      
                      $nbtime =~ s/://g;
                      $netime =~ s/://g;
                     
                      ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                      ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                      Log3($name, 5, "$name - YEARLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                      if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
                          Log3($name, 4, "$name - Ignore YEARLY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                          $ignore = 1;
                          $done   = 0;                                        
                      } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                          Log3($name, 4, "$name - Ignore YEARLY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                          $ignore = 1;
                          $done   = 0;                                        
                      } else {
                          $bdate = $nbdate?$nbdate:$bdate;
                          $btime = $nbtime?$nbtime:$btime;
                          $bts   = $nbts?$nbts:$bts;
                          
                          $edate = $nedate?$nedate:$edate;
                          $etime = $netime?$netime:$etime;
                          $ets   = $nets?$nets:$ets;                  
                          
                          @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
  
                          $ignore = 0;
                          $done   = 1;
                          $n++;
                          next;
                      }                                       
                      last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                  }                      
              }
              
              if ($freq eq "MONTHLY") {                                        # monatliche Wiederholung                       
                  if ($bymonthday) {                                           # Wiederholungseigenschaft am Tag X des Monats     
                      for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {
                          $bmonth += $interval;
                          $byear  += int( $bmonth/13);
                          $bmonth %= 12 if($bmonth>12);
                          $bmonth = sprintf("%02d", $bmonth);
                          
                          $emonth += $interval;
                          $eyear  += int( $emonth/13);
                          $emonth %= 12 if($emonth>12);
                          $emonth = sprintf("%02d", $emonth);
  
                          $nbtime =~ s/://g;
                          $netime =~ s/://g;
  
                          ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                          ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                          Log3($name, 5, "$name - MONTHLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                          if (defined $uets && ($uets < $nbts)) {                                              # Event Ende (UNTIL) kleiner aktueller Select Start 
                              Log3($name, 4, "$name - Ignore MONTHLY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                              $ignore = 1;
                              $done   = 0;                                        
                          } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                              Log3($name, 4, "$name - Ignore MONTHLY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                              $ignore = 1;
                              $done   = 0;                                        
                          } else {
                              $bdate = $nbdate?$nbdate:$bdate;
                              $btime = $nbtime?$nbtime:$btime;
                              $bts   = $nbts?$nbts:$bts;
                              
                              $edate = $nedate?$nedate:$edate;
                              $etime = $netime?$netime:$etime;
                              $ets   = $nets?$nets:$ets;                  
                              
                              @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
  
                              $ignore = 0;
                              $done   = 1;
                              $n++;
                              next;
                          }                                       
                          last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                      }
                  }
                  if ($byday) {                                                 # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness,$rDayOfWeekNew,$rDaysToAddOrSub,$rNewTime,$rbYday);
                      my @ByDays = split(",", $byday);                          # Array der Wiederholungstage
                      
                      foreach (@ByDays) {
                          my $rByDay       = $_;	                              # das erste Wiederholungselement
                          my $rByDayLength = length($rByDay);                   # die Länge des Strings       
  
                          my $rDayStr;		                                  # Tag auf den das Datum gesetzt werden soll
                          my $rDayInterval;	                                  # z.B. 2 = 2nd Tag des Monats oder -1 = letzter Tag des Monats
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
                                  $bmonth += $interval;
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
  
                                  $rNewTime = SSCal_plusNSeconds($firstOfNextMonth, 86400*$rDaysToAddOrSub, 1);                                                                                                
                                  ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = SSCal_DTfromStartandDiff ($rNewTime,$startEndDiff);
                              
                              } else {
                                  Log3($name, 2, "$name - WARNING - negative values for BYDAY are currently not implemented and will be ignored");
                                  $ignore = 1;
                                  $done   = 0;
                                  $n++;
                                  next;                                            
                              }
                              
                              $nbtime = $nbhh.$nbmm.$nbss;
                              $netime = $nehh.$nemm.$ness;
  
                              ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                              ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                              Log3($name, 5, "$name - MONTHLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                              
                              if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
                                  Log3($name, 4, "$name - Ignore MONTHLY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                                  $ignore = 1;
                                  $done   = 0;                                        
                              } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                                  Log3($name, 4, "$name - Ignore MONTHLY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                                  $ignore = 1;
                                  $done   = 0;                                        
                              } else {
                                  $bdate = $nbdate?$nbdate:$bdate;
                                  $btime = $nbtime?$nbtime:$btime;
                                  $bts   = $nbts?$nbts:$bts;
                                  
                                  $edate = $nedate?$nedate:$edate;
                                  $etime = $netime?$netime:$etime;
                                  $ets   = $nets?$nets:$ets;                  
                                  
                                  @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
  
                                  $ignore = 0;
                                  $done   = 1;
                                  $n++;
                                  next;
                              }                                       
                              last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                          }
                      }   
                  }
              }
  
              if ($freq eq "WEEKLY") {                                          # wöchentliche Wiederholung                            						                            
                  if ($byday) {                                                 # Wiederholungseigenschaft -> Wochentag z.B. 2WE,-1SU,4FR (kann auch Liste bei WEEKLY sein)              
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness,$rDayOfWeekNew,$rDaysToAddOrSub); 
                      my @ByDays   = split(",", $byday);                        # Array der Wiederholungstage
                      my $btsstart = $bts;
                      
                      foreach (@ByDays) {
                          my $rNewTime     = $btsstart;
                          my $rByDay       = $_;	                            # das erste Wiederholungselement
                          my $rByDayLength = length($rByDay);                   # die Länge des Strings       
  
                          my $rDayStr;		                                    # Tag auf den das Datum gesetzt werden soll
                          my $rDayInterval;	                                    # z.B. 2 = 2nd Tag des Monats oder -1 = letzter Tag des Monats
                          if ($rByDayLength > 2) {
                              $rDayStr      = substr($rByDay, -2);
                              $rDayInterval = int(substr($rByDay, 0, $rByDayLength - 2));
                          } else {
                              $rDayStr      = $rByDay;
                              $rDayInterval = 1;
                          }
  
                          my @weekdays     = qw(SU MO TU WE TH FR SA);
                          my ($rDayOfWeek) = grep {$weekdays[$_] eq $rDayStr} 0..$#weekdays;     # liefert Nr des Wochentages: SU = 0 ... SA = 6
                          
                          for ($ci=-1; $ci<($count*$interval); $ci++) {
                              
                              $rNewTime += $interval*604800 if($ci>=0);                          # Wochenintervall addieren
                              ($nbss, $nbmm, $nbhh, $bmday, $bmonth, $byear, $rDayOfWeekNew, undef, undef) = localtime($rNewTime);                                        
                              
                              ($nbhh,$nbmm,$nbss)  = split(":", $nbtime);
  
                              if ($rDayOfWeekNew <= $rDayOfWeek) {                               # Nr aktueller Wochentag <= Sollwochentag
                                  $rDaysToAddOrSub = $rDayOfWeek - $rDayOfWeekNew;
                              } else {
                                  $rDaysToAddOrSub = 7 - $rDayOfWeekNew + $rDayOfWeek;          
                                  $rNewTime       -= 604800;                                     # eine Woche zurückgehen wenn Korrektur aufaddiert wurde
                              }                                            
                    
                              $rDaysToAddOrSub += (7 * ($rDayInterval - 1));                     # addiere Tagesintervall, z.B. 4th Freitag ...
  
                              $rNewTime = SSCal_plusNSeconds($rNewTime, 86400*$rDaysToAddOrSub, 1);                                                                                                
                              ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = SSCal_DTfromStartandDiff ($rNewTime,$startEndDiff);
                                               
                              $nbtime = $nbhh.$nbmm.$nbss;
                              $netime = $nehh.$nemm.$ness;
  
                              ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                              ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                              Log3($name, 5, "$name - WEEKLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                              
                              if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
                                  Log3($name, 4, "$name - Ignore WEEKLY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                                  $ignore = 1;
                                  $done   = 0;                                        
                              } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                                  Log3($name, 4, "$name - Ignore WEEKLY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                                  $ignore = 1;
                                  $done   = 0;                                        
                              } else {
                                  $bdate = $nbdate?$nbdate:$bdate;
                                  $btime = $nbtime?$nbtime:$btime;
                                  $bts   = $nbts?$nbts:$bts;
                                  
                                  $edate = $nedate?$nedate:$edate;
                                  $etime = $netime?$netime:$etime;
                                  $ets   = $nets?$nets:$ets;                  
                                  
                                  @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
  
                                  $ignore = 0;
                                  $done   = 1;
                                  $n++;
                                  next;
                              }                                       
                              last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                          }
                      }   
                  
                  } else {    
                      my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness,$rDayOfWeekNew,$rDaysToAddOrSub); 
                      my $rNewTime = $bts;
                      
                      for ($ci=-1; $ci<($count*$interval); $ci++) {
                          $rNewTime += $interval*604800 if($ci>=0);                          # Wochenintervall addieren
                          
                          ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = SSCal_DTfromStartandDiff ($rNewTime,$startEndDiff);                      
                          $nbtime = $nbhh.$nbmm.$nbss;
                          $netime = $nehh.$nemm.$ness;                
  
                          ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                          ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                          Log3($name, 5, "$name - WEEKLY event - Begin: $nbdate $nbtime, End: $nedate $netime");
                           
                          if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
                              Log3($name, 4, "$name - Ignore WEEKLY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                              $ignore = 1;
                              $done   = 0;                                        
                          } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                              Log3($name, 4, "$name - Ignore WEEKLY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                              $ignore = 1;
                              $done   = 0;                                        
                          } else {
                              $bdate = $nbdate?$nbdate:$bdate;
                              $btime = $nbtime?$nbtime:$btime;
                              $bts   = $nbts?$nbts:$bts;
                              
                              $edate = $nedate?$nedate:$edate;
                              $etime = $netime?$netime:$etime;
                              $ets   = $nets?$nets:$ets; 
                                  
                              @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
                              
                              $ignore = 0;
                              $done   = 1;
                              $n++;
                              next;
                          }
                          last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                      }                                    
                  }							
              }	
  
              if ($freq eq "DAILY") {                                         # tägliche Wiederholung
                  my ($nbhh,$nbmm,$nbss,$nehh,$nemm,$ness);
                  for ($ci=-1; $ci<($count*$interval); $ci+=$interval) {                                    
                      
                      $bts += 86400 if($ci>=0);
  
                      ($nbss,$nbmm,$nbhh,$bmday,$bmonth,$byear,$ness,$nemm,$nehh,$emday,$emonth,$eyear) = SSCal_DTfromStartandDiff ($bts,$startEndDiff);                                    
  
                      $nbtime = $nbhh.$nbmm.$nbss;
                      $netime = $nehh.$nemm.$ness;                                    
                     
                      ($bi,undef,$nbdate,$nbtime,$nbts) = SSCal_explodeDateTime ($hash, $byear.$bmonth.$bmday."T".$nbtime);  # Beginn des Wiederholungsevents
                      ($ei,undef,$nedate,$netime,$nets) = SSCal_explodeDateTime ($hash, $eyear.$emonth.$emday."T".$netime);  # Ende des Wiederholungsevents
  
                      Log3($name, 5, "$name - DAILY event - Begin: $nbdate $nbtime, End: $nedate $netime");
  
                      if (defined $uets && ($uets < $nbts)) {                                    # Event Ende (UNTIL) kleiner aktueller Select Start 
                          Log3($name, 4, "$name - Ignore DAILY event due to UNTIL -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime, until: $until");
                          $ignore = 1;
                          $done   = 0;                                        
                      } elsif ($nets < $tstart || $nbts > $tend) {                               # Event Ende kleiner Select Start oder Beginn Event größer als Select Ende
                          Log3($name, 4, "$name - Ignore DAILY event -> $data->{data}{$key}[$i]{summary} , start: $nbdate $nbtime, end: $nedate $netime");
                          $ignore = 1;
                          $done   = 0;                                        
                      } else {
                          $bdate = $nbdate?$nbdate:$bdate;
                          $btime = $nbtime?$nbtime:$btime;
                          $bts   = $nbts?$nbts:$bts;
                          
                          $edate = $nedate?$nedate:$edate;
                          $etime = $netime?$netime:$etime;
                          $ets   = $nets?$nets:$ets;                  
                          
                          @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
  
                          $ignore = 0;
                          $done   = 1;
                          $n++;
                          next;
                      }                                       
                      last if((defined $uets && ($uets < $nbts)) || $nbts > $tend);
                  }   								
              }	                            
          }
          
          if ($ignore == 1) {
              $i++;
              next;
          }
          
          if(!$done) {                                      # für Testzwecke mit $ignore = 0 und $done = 0
              $bdate = $nbdate?$nbdate:$bdate;
              $btime = $nbtime?$nbtime:$btime;
              $bts   = $nbts?$nbts:$bts;
              
              $edate = $nedate?$nedate:$edate;
              $etime = $netime?$netime:$etime;
              $ets   = $nets?$nets:$ets;                  
              
              @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
          }
          $i++;
          $n++;
      }
      $n++;
  }  
  
  # encoding result 
  my $rowlist = join('_ESC_', @row_array);
  $rowlist    = encode_base64($rowlist,"");
     
  if($am) {                                      # asynchroner Mode mit BlockingCall
      return "$name|$rowlist";                       
  } else {                                       # synchoner Modes
      return SSCal_createReadings ("$name|$rowlist"); 
  }
}

#############################################################################################
#                    Extrahiert empfangene Tasks aus ToDo-Kalender (Aufgabenliste)
#############################################################################################
sub SSCal_extractToDolist ($) { 
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $data   = delete $hash->{eventlist};
  my $am     = AttrVal($name, "asyncMode", 0);
  
  my ($val,$tz,$td,$d,$t,$uts); 
  my ($bdate,$btime,$bts,$edate,$etime,$ets,$ci,$numday,$bi,$ei,$startEndDiff);
  my ($bmday,$bmonth,$emday,$emonth,$byear,$eyear,$nbdate,$nbtime,$nbts,$nedate,$netime,$nets,$ydiff);
  my @row_array;
  
  my (undef,$tstart,$tend) = SSCal_timeEdge($name);       # Sollstart- und Sollendezeit der Kalenderereignisse ermitteln
  my $datetimestart        = FmtDateTime($tstart);
  my $datetimeend          = FmtDateTime($tend);
       
  my $n = 0;       
  foreach my $key (keys %{$data->{data}}) {
      my $i = 0;
  
      while ($data->{data}{$key}[$i]) {
          my $ignore = 0; 
          my $done   = 0;
          ($nbdate,$nedate) = ("","");		
          
          ($bi,$tz,$bdate,$btime,$bts)   = SSCal_explodeDateTime ($hash,$data->{data}{$key}[$i]{due});    # Fälligkeit des Tasks (falls gesetzt)
          ($ei,undef,$edate,$etime,$ets) = SSCal_explodeDateTime ($hash,$data->{data}{$key}[$i]{due});    # Ende = Fälligkeit des Tasks (falls gesetzt)
  
          if ($bdate && $edate) {                                               # nicht jede Aufgabe hat 
              $bdate  =~ /(\d{4})-(\d{2})-(\d{2})/;
              $bmday  = $3;
              $bmonth = $2;
              $byear  = $1;
              $nbtime = $btime;                
              
              $edate  =~ /(\d{4})-(\d{2})-(\d{2})/;
              $emday  = $3;
              $emonth = $2;
              $eyear  = $1;
              $netime = $etime;
          }
                                              
          if(!$data->{data}{$key}[$i]{is_repeat_evt}) {                         # einmaliger Task (momentan gibt es keine Wiederholungstasks)
              Log3($name, 5, "$name - Single task Begin: $bdate, End: $edate") if($bdate && $edate);
              
              if(($ets && $ets < $tstart) || ($bts && $bts > $tend)) {
                  Log3($name, 4, "$name - Ignore single task -> $data->{data}{$key}[$i]{summary} start: $bdate $btime, end: $edate $etime");
                  $ignore = 1;
                  $done   = 0; 
              } else {
                  @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
                  $ignore = 0;
                  $done   = 1;
              }       
          
          } 
          
          if ($ignore == 1) {
              $i++;
              next;
          }
          
          if(!$done) {                                      # für Testzwecke mit $ignore = 0 und $done = 0
              $bdate = $nbdate?$nbdate:$bdate;
              $btime = $nbtime?$nbtime:$btime;
              $bts   = $nbts?$nbts:$bts;
              
              $edate = $nedate?$nedate:$edate;
              $etime = $netime?$netime:$etime;
              $ets   = $nets?$nets:$ets;                  
              
              @row_array = SSCal_writeValuesToArray ($name,$n,$data->{data}{$key}[$i],$tz,$bdate,$btime,$bts,$edate,$etime,$ets,\@row_array);
          }
          $i++;
          $n++;
      }
      $n++;
  }  
  
  # encoding result 
  my $rowlist = join('_ESC_', @row_array);
  $rowlist    = encode_base64($rowlist,"");
     
  if($am) {                                      # asynchroner Mode mit BlockingCall
      return "$name|$rowlist";                       
  } else {                                       # synchoner Modes
      return SSCal_createReadings ("$name|$rowlist"); 
  }
}

#############################################################################################
#         füllt zentrales Datenhash 
#         $data{SSCal}{$name}{eventlist} = Referenz zum zentralen Valuehash
#         erstellt Readings aus zentralen Eventarray
#############################################################################################
sub SSCal_createReadings ($) { 
  my ($string) = @_;
  my @a        = split("\\|",$string);
  my $name     = $a[0];
  my $hash     = $defs{$name};
  my $rowlist  = decode_base64($a[1]) if($a[1]);
  
  if ($rowlist) {
      my @row_array = split("_ESC_", $rowlist);
      
      # zentrales Datenhash füllen (erzeugt dadurch sortierbare Keys)
      foreach my $row (@row_array) {
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
      foreach my $idx (sort keys %{$data{SSCal}{$name}{eventlist}}) {
          my $idxstr = sprintf("%0$l.0f", $k);                               # Prestring erstellen 
          foreach my $r (keys %{$data{SSCal}{$name}{eventlist}{$idx}}) {
              if($r =~ /.*Timestamp$/) {                                     # Readings mit Unix Timestamps versteckt erstellen
                  readingsBulkUpdate($hash, ".".$idxstr."_".$r, $data{SSCal}{$name}{eventlist}{$idx}{$r});
              } else {
                  readingsBulkUpdate($hash, $idxstr."_".$r, $data{SSCal}{$name}{eventlist}{$idx}{$r});
              }
          }
          $k += 1;
      }
      
      readingsEndUpdate($hash, 1);
  
  } else {
      SSCal_delReadings($name,0);                                            # alle Kalender-Readings löschen
  }
  
  SSCal_checkretry($name,0);

  $data{SSCal}{$name}{lastUpdate} = FmtDateTime($data{SSCal}{$name}{lstUpdtTs}) if($data{SSCal}{$name}{lstUpdtTs});  

  readingsBeginUpdate         ($hash); 
  readingsBulkUpdateIfChanged ($hash, "Errorcode",  "none");
  readingsBulkUpdateIfChanged ($hash, "Error",      "none");    
  readingsBulkUpdate          ($hash, "lastUpdate", $data{SSCal}{$name}{lastUpdate});                   
  readingsBulkUpdate          ($hash, "state",      "done");                    
  readingsEndUpdate           ($hash,1); 

  SSCal_delReadings($name,1) if($data{SSCal}{$name}{lstUpdtTs});                  # Readings löschen wenn Timestamp nicht "lastUpdate"
       
return;
}

####################################################################################################
#                               Abbruchroutine BlockingCall
####################################################################################################
sub SSCal_blockingTimeout(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME}; 
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");    
  
  SSCal_checkretry($name,0);

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
sub SSCal_DTfromStartandDiff ($$) {
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
#         schreibe Key/Value Pairs in zentrales Valuearray zur Readingerstellung
#         $n                             = Zusatz f. lfd. Nr. zur Unterscheidung exakt 
#                                          zeitgleicher Events
#         $vh                            = Referenz zum Kalenderdatenhash
#
#         Ergebisarray Aufbau:
#                       0                            1               2
#         (Index aus BeginTimestamp+lfNr) , (Blockindex_Reading) , (Wert)
#
#############################################################################################
sub SSCal_writeValuesToArray ($$$$$$$$$$$) {                 
  my ($name,$n,$vh,$tz,$bdate,$btime,$bts,$edate,$etime,$ets,$aref) = @_;
  my @row_array = @{$aref};
  my $hash      = $defs{$name};
  my $ts        = time();                           # Istzeit Timestamp
  my $om        = $hash->{OPMODE};                  # aktuelle Operation Mode
  my $status    = "initialized";
  my ($val,$uts,$td);
  
  my ($upcoming,$alarmed,$started,$ended) = (0,0,0,0);
  
  $upcoming = SSCal_isUpcoming ($ts,0,$bts);        # initiales upcoming
  $started  = SSCal_isStarted  ($ts,$bts,$ets);
  $ended    = SSCal_isEnded    ($ts,$ets);
  
  push(@row_array, $bts+$n." 02_Begin "      .$bdate." ".$btime."\n") if($bdate && $btime);
  push(@row_array, $bts+$n." 03_End "        .$edate." ".$etime."\n") if($edate && $etime);
  push(@row_array, $bts+$n." 02_bTimestamp " .$bts."\n")              if($bts);
  push(@row_array, $bts+$n." 03_eTimestamp " .$ets."\n")              if($ets);   
  push(@row_array, $bts+$n." 09_Timezone "   .$tz."\n")               if($tz); 

  foreach my $p (keys %{$vh}) {
      $vh->{$p} = "" if(!defined $vh->{$p});
	  $vh->{$p} = SSCal_jboolmap($vh->{$p});
      next if($vh->{$p} eq "");
        
      # Log3($name, 4, "$name - bts: $bts, Parameter: $p, Value: ".$vh->{$p}) if(ref $p ne "HASH");
        
      $val = encode("UTF-8", $vh->{$p}); 

      push(@row_array, $bts+$n." 01_Summary "       .$val."\n")       if($p eq "summary");
      push(@row_array, $bts+$n." 04_Description "   .$val."\n")       if($p eq "description");
      push(@row_array, $bts+$n." 05_EventId "       .$val."\n")       if($p eq "evt_id"); 
      push(@row_array, $bts+$n." 07_Location "      .$val."\n")       if($p eq "location");
      push(@row_array, $bts+$n." 08_GPS "           .$val."\n")       if($p eq "gps");
      push(@row_array, $bts+$n." 11_isAllday "      .$val."\n")       if($p eq "is_all_day");
      push(@row_array, $bts+$n." 12_isRepeatEvt "   .$val."\n")       if($p eq "is_repeat_evt");
      
      if($p eq "due") {                                                        
          my (undef,undef,$duedate,$duetime,$duets) = SSCal_explodeDateTime ($hash,$val);
          push(@row_array, $bts+$n." 15_dueDateTime "  .$duedate." ".$duetime."\n"); 
          push(@row_array, $bts+$n." 15_dueTimestamp " .$duets."\n");
      }
      
      push(@row_array, $bts+$n." 16_percentComplete " .$val."\n")                            if($p eq "percent_complete" && $om eq "todolist");     
      push(@row_array, $bts+$n." 90_calName "         .SSCal_getCalFromId($hash,$val)."\n")  if($p eq "original_cal_id");

      if($p eq "evt_repeat_setting") {
          foreach my $r (keys %{$vh->{evt_repeat_setting}}) {
              $vh->{$p}{$r} = "" if(!defined $vh->{$p}{$r});
              next if($vh->{$p}{$r} eq "");
              $val = encode("UTF-8", $vh->{$p}{$r});                 
              push(@row_array, $bts+$n." 13_repeatRule ".$val."\n") if($r eq "repeat_rule");
          }
      }
      if($p eq "evt_notify_setting") {              
          my $l   = length (scalar @{$vh->{evt_notify_setting}});                        # Anzahl Stellen (Länge) des aktuellen Arrays
          my $ens = 0; 
          
          while ($vh->{evt_notify_setting}[$ens]) {
              foreach my $r (keys %{$vh->{evt_notify_setting}[$ens]}) {
                  $vh->{$p}[$ens]{$r} = "" if(!$vh->{$p}[$ens]{$r});
                  $val                = encode("UTF-8", $vh->{$p}[$ens]{$r}); 
                    
                  if($r eq "time_value") {                                               # Erinnerungstermine (Array) relativ zur Beginnzeit ermitteln
                      ($uts,$td) = SSCal_evtNotTime ($name,$val,$bts);   
                      push(@row_array, $bts+$n." 14_".sprintf("%0$l.0f", $ens)."_notifyTimestamp ".$uts."\n");
                      push(@row_array, $bts+$n." 14_".sprintf("%0$l.0f", $ens)."_notifyDateTime " .$td."\n");
                      $alarmed = SSCal_isAlarmed ($ts,$uts,$bts) if(!$alarmed);
                  }
              }
              $ens++; 
          }
      }
  }
  
  $status = "upcoming"        if($upcoming);
  $status = "alarmed"         if($alarmed);
  $status = "started"         if($started);
  $status = "ended"           if($ended);
  
  push(@row_array, $bts+$n." 10_Status "        .$status."\n");
  push(@row_array, $bts+$n." 99_---------------------- " ."--------------------------------------------------------------------"."\n");
    
return @row_array;
}

#############################################################################################
#  Ist Event bevorstehend ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts vor Alarmzeit $ats und vor Startzeit $bts,
#  sonst 0
#############################################################################################
sub SSCal_isUpcoming ($$$) {
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
sub SSCal_isAlarmed ($$$) {
  my ($ts,$ats,$bts) = @_;
  
  return $ats ? (($ats <= $ts && $ts < $bts) ? 1 : 0) : 0;
}

#############################################################################################
#  Ist Event gestartet ?
#  Rückkehrwert 1 wenn aktueller Timestamp $ts zwischen Startzeit $bts und Endezeit $ets,
#  sonst 0
#############################################################################################
sub SSCal_isStarted ($$$) {
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
sub SSCal_isEnded ($$) {
  my ($ts,$ets) = @_;

  return 0 unless($ets && $ts);
  return $ets <= $ts ? 1 : 0;
}

#############################################################################################
#                                     check SID
#############################################################################################
sub SSCal_checkSID ($) { 
  my ($name) = @_;
  my $hash   = $defs{$name};
  
  # SID holen bzw. login
  my $subref = "SSCal_calop";
  if(!$hash->{HELPER}{SID}) {
      Log3($name, 3, "$name - no session ID found - get new one");
	  SSCal_login($hash,$subref);
	  return;
  }
   
return SSCal_calop($name);
}

####################################################################################  
#                                 Login for SID
####################################################################################
sub SSCal_login ($$) {
  my ($hash,$fret) = @_;
  my $name          = $hash->{NAME};
  my $serveraddr    = $hash->{ADDR};
  my $serverport    = $hash->{PORT};
  my $proto         = $hash->{PROT};
  my $apiauth       = $SSCal_api{APIAUTH}{NAME};
  my $apiauthpath   = $SSCal_api{APIAUTH}{PATH};
  my $apiauthmaxver = $SSCal_api{APIAUTH}{MAX};

  my $lrt = AttrVal($name,"loginRetries",3);
  my ($url,$param);
  
  delete $hash->{HELPER}{SID};
    
  # Login und SID ermitteln
  Log3($name, 4, "$name - --- Start Synology Calendar login ---");
  
  # Credentials abrufen
  my ($success, $username, $password) = SSCal_getcredentials($hash,0,"credentials");
  
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
  $timeout    = 60 if($timeout < 60);
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
               callback => \&SSCal_login_return
           };
  HttpUtils_NonblockingGet ($param);
}

sub SSCal_login_return ($) {
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
        
      return SSCal_login($hash,$fret);
   
   } elsif ($myjson ne "") {        
		# Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = SSCal_evaljson($hash,$myjson);
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
            my $error = SSCal_experrorauth($hash,$errorcode);

            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash,"Errorcode", $errorcode);
            readingsBulkUpdate  ($hash,"Error",     $error);
            readingsBulkUpdate  ($hash,"state",     "error");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return SSCal_login($hash,$fret);
       }
   }
   
return SSCal_login($hash,$fret);
}

###################################################################################  
#                                Funktion logout
###################################################################################
sub SSCal_logout ($) {
   my ($hash) = @_;
   my $name          = $hash->{NAME};
   my $serveraddr    = $hash->{ADDR};
   my $serverport    = $hash->{PORT};
   my $proto         = $hash->{PROT};
   my $apiauth       = $SSCal_api{APIAUTH}{NAME};
   my $apiauthpath   = $SSCal_api{APIAUTH}{PATH};
   my $apiauthmaxver = $SSCal_api{APIAUTH}{MAX};
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
            callback => \&SSCal_logout_return
            };
   
   HttpUtils_NonblockingGet ($param);
   
}

sub SSCal_logout_return ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash                   = $param->{hash};
   my $name                   = $hash->{NAME};
   my $sid                    = $hash->{HELPER}{SID};
   my $OpMode                 = $hash->{OPMODE};
   my ($success, $username, $password) = SSCal_getcredentials($hash,0,"credentials");
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
       ($hash,$success,$myjson) = SSCal_evaljson($hash,$myjson);
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
           $error = SSCal_experrorauth($hash,$errorcode); 

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
sub SSCal_evaljson($$) { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  my ($error,$errorcode);

  eval {decode_json($myjson)} or do {
          $success = 0;
          
          $errorcode = "900";

          # Fehlertext zum Errorcode ermitteln
          $error = SSCal_experror($hash,$errorcode);
            
          readingsBeginUpdate         ($hash);
          readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
          readingsBulkUpdateIfChanged ($hash, "Error",     $error);
          readingsBulkUpdate          ($hash, "state",     "Error");
          readingsEndUpdate           ($hash, 1);  
  };
  
return($hash,$success,$myjson);
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub SSCal_jboolmap($){ 
  my ($bool) = @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool?"true":"false";
  }
  
return $bool;
}


##############################################################################
#  Auflösung Errorcodes Calendar AUTH API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSCal_experrorauth ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSCal_errauthlist{"$errorcode"})) {
      $error = "Value of errorcode \"$errorcode\" not found."; 
      return ($error);
  }

  $error = $SSCal_errauthlist{"$errorcode"};
  
return ($error);
}

##############################################################################
#  Auflösung Errorcodes Calendar API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSCal_experror ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSCal_errlist{"$errorcode"})) {
      $error = "Value of errorcode \"$errorcode\" not found."; 
      return ($error);
  }

  $error = $SSCal_errlist{"$errorcode"};
  
return ($error);
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub SSCal_sortVersion (@){
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

######################################################################################
#                            credentials speichern
######################################################################################
sub SSCal_setcredentials ($@) {
    my ($hash, @credentials) = @_;
    my $name              = $hash->{NAME};
    my ($success, $credstr, $username, $passwd, $index, $retcode);
    my (@key,$len,$i);   
    
    my $ao   = "credentials";
    $credstr = encode_base64(join('!_ESC_!', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index   = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving Credentials - $retcode");
        $success = 0;
    } else {
        ($success, $username, $passwd) = SSCal_getcredentials($hash,1,$ao);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
    }

return ($success);
}

######################################################################################
#                             credentials lesen
######################################################################################
sub SSCal_getcredentials ($$$) {
    my ($hash,$boot, $ao) = @_;
    my $name               = $hash->{NAME};
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
            map { $i = ($i + 1) % $len;  
            chr((ord($_) - $key[$i] + 256) % 256) }  
            split //, $credstr;   
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
sub SSCal_trim ($) {
  my $str = shift;
  $str =~ s/^\s+|\s+$//g;

return ($str);
}

#############################################################################################
#                        Länge Senedequeue updaten          
#############################################################################################
sub SSCal_updQLength ($;$) {
  my ($hash,$rst) = @_;
  my $name        = $hash->{NAME};
 
  my $ql = keys %{$data{SSCal}{$name}{sendqueue}{entries}};
  
  readingsBeginUpdate($hash);                                             
  readingsBulkUpdate ($hash, "QueueLenth", $ql);                                   # Länge Sendqueue updaten
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
#             Text für den Versand an Synology cal formatieren 
#             und nicht erlaubte Zeichen entfernen           
#############################################################################################
sub SSCal_formText ($) {
  my $txt = shift;
  my (%replacements,$pat);
  
  %replacements = (
      '"'  => "´",                              # doppelte Hochkomma sind im Text nicht erlaubt
      " H" => " h",                             # Bug im cal wenn vor großem H ein Zeichen + Leerzeichen vorangeht
      "#"  => "%23",                            # Hashtags sind im Text nicht erlaubt und wird encodiert
      "&"  => "%26",                            # & ist im Text nicht erlaubt und wird encodiert    
      "%"  => "%25",                            # % ist nicht erlaubt und wird encodiert
      "+"  => "%2B",
  );
  
  $txt =~ s/\n/ESC_newline_ESC/g;
  my @acr = split (/\s+/, $txt);
              
  $txt = "";
  foreach (@acr) {                              # Einzeiligkeit für Versand herstellen
      $txt .= " " if($txt);
      $_ =~ s/ESC_newline_ESC/\\n/g;
      $txt .= $_;
  }
  
  $pat = join '|', map quotemeta, keys(%replacements);
  
  $txt =~ s/($pat)/$replacements{$1}/g;   
  
return ($txt);
}

#############################################################################################
#              Start- und Endezeit ermitteln
#############################################################################################
sub SSCal_timeEdge ($) {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my ($error,$t1,$t2) = ("","","");
  my ($mday,$mon,$year);
  
  my $t    = time();
  my $corr = 86400;                                                                  # Korrekturbetrag 
  
  my $cutOlderDays = AttrVal($name, "cutOlderDays", 5)."d";
  my $cutLaterDays = AttrVal($name, "cutLaterDays", 5)."d";

  # start of time window
  ($error,$t1) = SSCal_GetSecondsFromTimeSpec($cutOlderDays);
  if($error) {
	  Log3 $hash, 2, "$name: attribute cutOlderDays: $error";
	  return ($error,"","");
  } else {
	  $t1 = $t-$t1;
	  (undef,undef,undef,$mday,$mon,$year,undef,undef,undef) = localtime($t1);       # Istzeit Ableitung
	  $t1 = fhemTimeLocal(00, 00, 00, $mday, $mon, $year);
  }

  # end of time window
  ($error,$t2) = SSCal_GetSecondsFromTimeSpec($cutLaterDays);
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
sub SSCal_evtNotTime ($$$) {
  my ($name,$tv,$bts) = @_;
  my $hash            = $defs{$name};
  my ($uts,$ts)       = ("","");
  my ($corr);
  
  return ("","") if(!$tv || !$bts);
  
  if($tv =~ /^-P(\d)+D$/) {
      $corr = -1*$1*86400;
  } elsif ($tv =~ /^-PT(\d+)H$/) {
      $corr = -1*$1*3600;
  } elsif ($tv =~ /^-PT(\d+)M$/) {
      $corr = -1*$1*60;
  } elsif ($tv =~ /^PT(\d+)S$/) {
      $corr = $1;
  } elsif ($tv =~ /^PT(\d+)M$/) {
      $corr = $1*60;
  } elsif ($tv =~ /^PT(\d+)H$/) {
      $corr = $1*3600;
  } elsif ($tv =~ /^-P(\d)+DT(\d+)H$/) {
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
sub SSCal_GetSecondsFromTimeSpec($) {
  my ($tspec) = @_;

  # days
  if($tspec =~ m/^([0-9]+)d$/) {
    return ("", $1*86400);
  }

  # seconds
  if($tspec =~ m/^([0-9]+)s?$/) {
    return ("", $1);
  }

  # D:HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])$/) {
    return ("", $4+60*($3+60*($2+24*$1)));
  }

  # HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
    return ("", $3+60*($2+(60*$1)));
  }

  # HH:MM
  if($tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
    return ("", 60*($2+60*$1));
  }

return ("Wrong time specification $tspec", undef);
}

#############################################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
#############################################################################################
sub SSCal_getclhash($;$$) {      
  my ($hash,$nobgd)= @_;
  my $name  = $hash->{NAME};
  my $ret;
  
  if($nobgd) {
      # nur übergebenen CL-Hash speichern, 
	  # keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
	  $hash->{HELPER}{CL}{1} = $hash->{CL};
	  return undef;
  }

  if (!defined($hash->{CL})) {
      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
	  my $outdev;
	  my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=canAsyncOutput=1:FILTER=STATE=Connected");
	  my $i = 1;
      foreach (@webdvs) {
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
sub SSCal_getCalFromId ($$) {      
  my ($hash,$cid) = @_;
  my $cal         = "";
  $cid            = SSCal_trim($cid);
  
  foreach my $calname (keys %{$hash->{HELPER}{CALENDARS}}) {
      my $oid = $hash->{HELPER}{CALENDARS}{"$calname"}{id};
      next if(!$oid);
      $oid = SSCal_trim($oid);
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
sub SSCal_plusNSeconds ($$$) {
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
sub SSCal_delReadings ($$) {      
  my ($name,$respts) = @_;
  my ($lu,$rts,$excl);
  
  $excl  = "Error|Errorcode|QueueLenth|state|nextUpdate";
  $excl .= "|lastUpdate" if($respts);
  
  my @allrds = keys%{$defs{$name}{READINGS}};
  foreach my $key(@allrds) {
      if($respts) {
          $lu  = $data{SSCal}{$name}{lastUpdate};
          $rts = ReadingsTimestamp($name, $key, $lu);
          next if($rts eq $lu);
      }
      delete($defs{$name}{READINGS}{$key}) if($key !~ m/^($excl)$/);
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
#############################################################################################
sub SSCal_explodeDateTime ($$) {      
  my ($hash,$dt)  = @_;
  my $name        = $hash->{NAME};
  my ($tz,$t)     = ("","");
  my ($d,$tstamp) = ("",0);
  my $invalid     = 0;
  my ($sec,$min,$hour,$mday,$month,$year);
  
  return ($invalid,$tz,$d,$t,$tstamp) if(!$dt);

  if($dt =~ /^TZID=.*$/) {
      ($tz,$dt) = split(":", $dt);
      $tz       = (split("=", $tz))[1];
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
  
  unless ( ($d." ".$t) =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
      Log3($name, 2, "$name - ERROR - invalid DateTime format for explodeDateTime: $d $t");
  }
  
  eval { timelocal($sec, $min, $hour, $mday, $month-1, $year-1900); };
  if ($@) {
      Log3($name, 3, "$name - WARNING - invalid format of recurring event: $@. It will be ignored due to RFC 5545 standard.");
      $invalid = 1;
  }

  eval { $tstamp = fhemTimeLocal($sec, $min, $hour, $mday, $month-1, $year-1900); };

return ($invalid,$tz,$d,$t,$tstamp);
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SSCal_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (SSCal_sortVersion("desc",keys %SSCal_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SSCal}{META}}
	  if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 50_SSCal.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g if($modules{$type}{META}{x_version} =~ /^1.1.1$/);
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 50_SSCal.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
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

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub SSCal_jboolmap($){ 
  my ($bool)= @_;
  
  if(JSON::is_bool($bool)) {
	  my $b = JSON::boolean($bool);
	  $bool = 1 if($b == $JSON::true);
	  $bool = 0 if($b == $JSON::false);
  }
  
return $bool;
}

#############################################################################################
#   Kalenderliste als HTML-Tabelle zurückgeben
#############################################################################################
sub SSCal_calAsHtml($) {      
  my ($name)= @_;
  my $hash = $defs{$name}; 

  my ($begin,$end,$summary,$location,$status,$desc,$gps,$cal,$completion,$tz);  
  
  my %seen;
  my @cof = split(",", AttrVal($name, "calOverviewFields", "Begin,End,Summary,Status,Location"));
  grep { !$seen{$_}++ } @cof;                        

  my $out  = "<html>";
  $out    .= "<style>TD.sscal       {text-align: left; padding-left:15px; padding-right:15px; border-spacing:5px; margin-left:auto; margin-right:auto;}</style>";
  $out    .= "<style>TD.sscalbold   {font-weight: bold;}</style>";
  $out    .= "<style>TD.sscalcenter {text-align: center;}</style>";
  $out    .= "<table class='block'>";
  
  $out    .= "<tr>";
  $out    .= "<td class='sscal sscalbold sscalcenter'> Begin             </td>"         if($seen{Begin});
  $out    .= "<td class='sscal sscalbold sscalcenter'> End               </td>"         if($seen{End});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Timezone          </td>"         if($seen{Timezone});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Summary           </td>"         if($seen{Summary});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Description       </td>"         if($seen{Description});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Status            </td>"         if($seen{Status});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Completion<br>(%) </td>"         if($seen{Completion});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Location          </td>"         if($seen{Location});
  $out    .= "<td class='sscal sscalbold sscalcenter'> GPS               </td>"         if($seen{GPS});
  $out    .= "<td class='sscal sscalbold sscalcenter'> Calendar          </td>"         if($seen{Calendar});
  
  $out    .= "<tr><td>  </td></tr>";
  $out    .= "<tr><td>  </td></tr>";

  my $l = length(keys %{$data{SSCal}{$name}{eventlist}});
  
  my $maxbnr;
  foreach my $key (keys %{$defs{$name}{READINGS}}) {
      next if $key !~ /^(\d+)_\d+_EventId$/;
      $maxbnr = $1 if(!$maxbnr || $1>$maxbnr);
  }
  
  my $k;
  for ($k=0;$k<=$maxbnr;$k++) {
      my $prestr = sprintf("%0$l.0f", $k);                               # Prestring erstellen 
      last if(!ReadingsVal($name, $prestr."_05_EventId", ""));           # keine Ausgabe wenn es keine EventId mit Blocknummer 0 gibt -> kein Event/Aufage vorhanden
      
      $summary    = ReadingsVal($name, $prestr."_01_Summary",         "");
      $begin      = ReadingsVal($name, $prestr."_02_Begin",           "not set");
      $end        = ReadingsVal($name, $prestr."_03_End",             "not set");
      $desc       = ReadingsVal($name, $prestr."_04_Description",     "");
      $location   = ReadingsVal($name, $prestr."_07_Location",        "");
      $gps        = ReadingsVal($name, $prestr."_08_GPS",             "");
	  $tz         = ReadingsVal($name, $prestr."_09_Timezone",        "");
      $status     = ReadingsVal($name, $prestr."_10_Status",          "");
	  $completion = ReadingsVal($name, $prestr."_16_percentComplete", "");
      $cal        = ReadingsVal($name, $prestr."_90_calName",         "");
      
      $out     .= "<tr class='odd'>";
      $out     .= "<td class='sscal'> $begin      </td>"      if($seen{Begin});
      $out     .= "<td class='sscal'> $end        </td>"      if($seen{End});
	  $out     .= "<td class='sscal'> $tz         </td>"      if($seen{Timezone});
      $out     .= "<td class='sscal'> $summary    </td>"      if($seen{Summary});
      $out     .= "<td class='sscal'> $desc       </td>"      if($seen{Description});
      $out     .= "<td class='sscal'> $status     </td>"      if($seen{Status});
	  $out     .= "<td class='sscal'> $completion </td>"      if($seen{Completion});
      $out     .= "<td class='sscal'> $location   </td>"      if($seen{Location});
      $out     .= "<td class='sscal'> $gps        </td>"      if($seen{GPS});
      $out     .= "<td class='sscal'> $cal        </td>"      if($seen{Calendar});
      $out     .= "</tr>";
  }

  $out .= "</table>";
  $out .= "</html>";

return $out;
}

#############################################################################################
#                                       Hint Hash EN           
#############################################################################################
%SSCal_vHintsExt_en = (
);

#############################################################################################
#                                       Hint Hash DE           
#############################################################################################
%SSCal_vHintsExt_de = (

);

1;

=pod
=item summary    module to integrate Synology Calendar
=item summary_DE Modul zur Integration von Synology Calendar
=begin html

<a name="SSCal"></a>
<h3>SSCal</h3>
<ul>

The guide for this module is currently only available in the german <a href="https://wiki.fhem.de/wiki/SSCal - Integration des Synology Calendar Servers">Wiki</a>.

</ul>


=end html
=begin html_DE

<a name="SSCal"></a>
<h3>SSCal</h3>
<ul>

Die Beschreibung des Moduls ist momentan nur im <a href="https://wiki.fhem.de/wiki/SSCal - Integration des Synology Calendar Servers">Wiki</a> vorhanden.
 
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
        "JSON": 0,
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
