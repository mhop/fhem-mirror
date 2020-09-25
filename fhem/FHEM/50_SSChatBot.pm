########################################################################################################################
# $Id$
#########################################################################################################################
#       50_SSChatBot.pm
#
#       (c) 2019-2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to operate as Bot for Synology Chat.
#       It's based on and uses Synology Chat Webhook.
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
# Definition: define <name> SSChatBot <ServerAddr> [ServerPort] [Protocol]
# 
# Example of defining a Bot: define SynChatBot SSChatBot 192.168.2.20 [5000] [HTTP(S)]
#

package FHEM::SSChatBot;                                                                                      ## no critic 'package'

use strict;                           
use warnings;
use GPUtils qw(GP_Import GP_Export);                                                                          # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

my $vAPI;
use FHEM::SynoModules::SMUtils qw(jboolmap 
                                  sortVersion 
								  setReadingErrorNone 
								  setReadingErrorState
								 );  
my $vSMUtils  = FHEM::SynoModules::SMUtils->VERSION();                                                        # Hilfsroutinen Modul

use FHEM::SynoModules::ErrCodes qw(:all); 
my $vErrCodes = FHEM::SynoModules::ErrCodes->VERSION();                                                       # Error Code Modul

use Data::Dumper;                                                                                             # Perl Core module
use MIME::Base64;
use Time::HiRes qw(gettimeofday);
use HttpUtils;                                                    
use Encode;   
eval "use JSON;1;"                                                    or my $SSChatBotMM = "JSON";            ## no critic 'eval' # Debian: apt-get install libjson-perl
eval "use FHEM::Meta;1"                                               or my $modMetaAbsent = 1;               ## no critic 'eval'
eval "use Net::Domain qw(hostname hostfqdn hostdomain domainname);1"  or my $SSChatBotNDom = "Net::Domain";   ## no critic 'eval'
no if $] >= 5.017011, warnings => 'experimental::smartmatch';                                   

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AnalyzePerlCommand
          AnalyzeCommandChain
          asyncOutput
          addToDevAttrList
          AttrVal
          attr
          CancelDelayedShutdown
          CommandSet
          CommandAttr
          CommandDefine
          CommandGet
          data
          defs
          devspec2array
          FmtDateTime
          getKeyValue
          HttpUtils_NonblockingGet
          init_done
          InternalTimer
          IsDisabled
          IsDevice
          Log
          Log3 
          modules
          parseParams
          plotAsPng
          readingFnAttributes          
          ReadingsVal
          RemoveInternalTimer
          readingsBeginUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged 
          readingsEndUpdate         
          setKeyValue  
          urlDecode
          FW_wname          
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
  "1.10.5" => "25.09.2020  get error Codes from FHEM::SynoModules::ErrCodes, unify setVersionInfo, integrate FHEM::SynoModules::SMUtils ",
  "1.10.4" => "22.08.2020  minor code changes ",
  "1.10.3" => "20.08.2020  more code refactoring according PBP ",
  "1.10.2" => "19.08.2020  more code refactoring and little improvements ",
  "1.10.1" => "18.08.2020  more code changes according PBP ",
  "1.10.0" => "17.08.2020  switch to packages, finalise for repo checkin ",
  "1.9.0"  => "30.07.2020  restartSendqueue option 'force' added ",
  "1.8.0"  => "27.05.2020  send SVG Plots with options like svg='<SVG-Device>,<zoom>,<offset>' possible ",
  "1.7.0"  => "26.05.2020  send SVG Plots possible ",
  "1.6.1"  => "22.05.2020  changes according to PBP ",
  "1.6.0"  => "22.05.2020  replace \" H\" with \"%20H\" in attachments due to problem in HttpUtils ",
  "1.5.0"  => "15.03.2020  slash commands set in interactive answer field 'value' will be executed ",
  "1.4.0"  => "15.03.2020  rename '1_sendItem' to 'asyncSendItem' because of Aesthetics ",
  "1.3.1"  => "14.03.2020  new reading recActionsValue which extract the value from actions, review logs of botCGI ",
  "1.3.0"  => "13.03.2020  rename 'sendItem' to '1_sendItem', allow attachments ",
  "1.2.2"  => "07.02.2020  add new permanent error 410 'message too long' ",
  "1.2.1"  => "27.01.2020  replace \" H\" with \"%20H\" in payload due to problem in HttpUtils ",
  "1.2.0"  => "04.01.2020  check that Botname with type SSChatBot does exist and write Log if not ",
  "1.1.0"  => "27.12.2019  both POST- and GET-method are now valid in CGI ",
  "1.0.1"  => "11.12.2019  check OPIDX in parse sendItem, change error code list, complete forbidSend with error text ",
  "1.0.0"  => "29.11.2019  initial "
);

# Versions History extern
my %vNotesExtern = (
  "1.7.0"  => "26.05.2020 Now it is possible to send SVG plots very easily with the command asyncSendItem ",
  "1.4.0"  => "15.03.2020 Command '1_sendItem' renamed to 'asyncSendItem' because of Aesthetics ",
  "1.3.0"  => "13.03.2020 The set command 'sendItem' was renamed to '1_sendItem' to avoid changing the botToken by chance. ".
                          "Also attachments are allowed now in the '1_sendItem' command. ",
  "1.0.1"  => "11.12.2019 check OPIDX in parse sendItem, change error code list, complete forbidSend with error text ",
  "1.0.0"  => "08.12.2019 initial "
);

# Hint hash EN
my %vHintsExt_en = (

);

# Hint hash DE
my %vHintsExt_de = (

);

my %hapi = (                                                                # Hash Template der API's
    INFO     => { NAME => "SYNO.API.Info",     }, 
    EXTERNAL => { NAME => "SYNO.Chat.External" },
);

$hapi{INFO}{PATH} = "query.cgi";
$hapi{INFO}{VER}  = 1;

my %hset = (                                                                # Hash für Set-Funktion
    botToken         => { fn => "_setbotToken"         }, 
    listSendqueue    => { fn => "_setlistSendqueue"    },   
    purgeSendqueue   => { fn => "_setpurgeSendqueue"   },
    asyncSendItem    => { fn => "_setasyncSendItem"    },
    restartSendqueue => { fn => "_setrestartSendqueue" },
);

my %hget = (                                                                # Hash für Get-Funktion
    storedToken     => { fn => "_getstoredToken"     }, 
    chatUserlist    => { fn => "_getchatUserlist"    },   
    chatChannellist => { fn => "_getchatChannellist" },
    versionNotes    => { fn => "_getversionNotes"    },
);

my %hmodep = (                                                              # Hash für Opmode Parse
    chatUserlist    => { fn => "_parseUsers"    }, 
    chatChannellist => { fn => "_parseChannels" },   
    sendItem        => { fn => "_parseSendItem" },
);

my %hrecbot = (                                                             # Hash für botCGI receice Slash-commands (/set, /get, /code)
    set => { fn => "__botCGIrecSet" }, 
    get => { fn => "__botCGIrecGet" },   
    cod => { fn => "__botCGIrecCod" },
);

################################################################
sub Initialize {
 my ($hash) = @_;
 $hash->{DefFn}             = \&Define;
 $hash->{UndefFn}           = \&Undef;
 $hash->{DeleteFn}          = \&Delete; 
 $hash->{SetFn}             = \&Set;
 $hash->{GetFn}             = \&Get;
 $hash->{AttrFn}            = \&Attr;
 $hash->{DelayedShutdownFn} = \&delayedShutdown;
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} = "disable:1,0 ".
                     "defaultPeer:--wait#for#userlist-- ".
                     "allowedUserForSet:--wait#for#userlist-- ".
                     "allowedUserForGet:--wait#for#userlist-- ".
                     "allowedUserForCode:--wait#for#userlist-- ".
                     "allowedUserForOwn:--wait#for#userlist-- ".
                     "ownCommand1 ".
                     "showTokenInLog:1,0 ".
                     "httptimeout ".
                     $readingFnAttributes;   
         
 FHEM::Meta::InitMod( __FILE__, $hash ) if(!$modMetaAbsent);    # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
# define SynChatBot SSChatBot 192.168.2.10 [5000] [HTTP(S)] 
#         ($hash)     [1]         [2]        [3]      [4]  
#
################################################################
sub Define {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SSChatBotMM." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SSChatBotMM);
 return "Error: Perl module ".$SSChatBotNDom." is missing." if($SSChatBotNDom);
  
  my @a = split m{\s+}x, $def;
  
  if(int(@a) < 2) {
      return "You need to specify more parameters.\n". "Format: define <name> SSChatBot <ServerAddress> [Port] [HTTP(S)]";
  }
        
  my $inaddr = $a[2];
  my $inport = $a[3] ? $a[3]     : 5000;
  my $inprot = $a[4] ? lc($a[4]) : "http";
  
  $hash->{INADDR}                = $inaddr;
  $hash->{INPORT}                = $inport;
  $hash->{MODEL}                 = "ChatBot"; 
  $hash->{INPROT}                = $inprot;
  $hash->{RESEND}                = "next planned SendQueue start: immediately by next entry";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  $hash->{HELPER}{USERFETCHED}   = 0;                                            # Chat User sind noch nicht abgerufen
  
  CommandAttr(undef,"$name room Chat");
  
  $hash->{HELPER}{API}           = \%hapi;                                       # API Template in HELPER kopieren 
  setVersionInfo ($hash, \%vNotesIntern);                                        # Versionsinformationen setzen
  getToken($hash,1,"botToken");                                                  # Token lesen
  $data{SSChatBot}{$name}{sendqueue}{index} = 0;                                 # Index der Sendequeue initialisieren
    
  readingsBeginUpdate         ($hash);                                             
  readingsBulkUpdateIfChanged ($hash, "QueueLenth", 0);                          # Länge Sendqueue initialisieren  
  readingsBulkUpdate          ($hash, "state", "Initialized");                   # Init state
  readingsEndUpdate           ($hash,1);              

  initOnBoot($hash);                                                             # initiale Routinen nach Start ausführen , verzögerter zufälliger Start

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
  
  delete $data{SSChatBot}{$name};
  
  removeExtension     ($hash->{HELPER}{INFIX});
  RemoveInternalTimer ($hash);
   
return;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub delayedShutdown {
  my $hash = shift;
  my $name = $hash->{NAME};

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
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_botToken";
  
  # gespeicherte Credentials löschen
  setKeyValue($index, undef);
    
return;
}

################################################################
sub Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
       
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = $aVal?1:0;
        }
        $do  = 0 if($cmd eq "del");
        
        $val = ($do == 1 ? "disabled" : "initialized");
        
        if ($do == 1) {
            RemoveInternalTimer($hash);
        } else {
            InternalTimer(gettimeofday()+2, "FHEM::SSChatBot::initOnBoot", $hash, 0) if($init_done); 
        }
    
        readingsBeginUpdate($hash); 
        readingsBulkUpdate ($hash, "state", $val);                    
        readingsEndUpdate  ($hash,1); 
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout/x) {
            unless ($aVal =~ /^\d+$/x) { return "The Value for $aName is not valid. Use only figures 1-9 !";}
        }     

        if ($aName =~ m/ownCommand([1-9][0-9]*)$/x) {
            my $num = $1;
            return qq{The value of $aName must start with a slash like "/Weather ".} unless ($aVal =~ /^\//x);
            addToDevAttrList($name, "ownCommand".($num+1));                        # add neue ownCommand dynamisch
        }        
    }
    
return;
}

################################################################
#                   Set und Subroutinen
################################################################
sub Set {                             
  my ($hash, @a) = @_;
  return qq{"set X" needs at least an argument} if ( @a < 2 );
  my @items   = @a;
  my $name    = shift @a;
  my $opt     = shift @a;
  my $prop    = shift @a;
  
  my $setlist;
        
  return if(IsDisabled($name));
  
  my $idxlist = join(",", sortVersion("asc",keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}));
 
  if(!$hash->{TOKEN}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "botToken "
                 ;  
  } else {
      $setlist = "Unknown argument $opt, choose one of ".
                 "botToken ".
                 "listSendqueue:noArg ".
                 ($idxlist?"purgeSendqueue:-all-,-permError-,$idxlist ":"purgeSendqueue:-all-,-permError- ").
                 "restartSendqueue ".
                 "asyncSendItem:textField-long "
                 ;
  }
  
  my $params = {
      hash => $hash,
      name => $name,
      opt  => $opt,
      prop => $prop,
      aref => \@items,
  };
  
  no strict "refs";                                                        ## no critic 'NoStrict'  
  if($hset{$opt}) {
      my $ret = "";
      $ret = &{$hset{$opt}{fn}} ($params) if(defined &{$hset{$opt}{fn}}); 
      return $ret;
  }
  use strict "refs";
  
return $setlist; 
}

################################################################
#                      Setter botToken
################################################################
sub _setbotToken {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return qq{The command "$opt" needs an argument.} if (!$prop);         
  my ($success) = setToken($hash, $prop, "botToken");
  
  if($success) {
      CommandGet(undef, "$name chatUserlist");                      # Chatuser Liste abrufen
      return qq{botToken saved successfully};
  } else {
      return qq{Error while saving botToken - see logfile for details};
  }

return;
}

################################################################
#                      Setter listSendqueue
################################################################
sub _setlistSendqueue {                  ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};
  
  my $sub = sub { 
      my $idx = shift;
      my $ret;          
      for my $key (reverse sort keys %{$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}}) {
          $ret .= ", " if($ret);
          $ret .= $key."=>".$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{$key};
      }
      return $ret;
  };
        
  if (!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
      return qq{SendQueue is empty.};
  }
  
  my $sq;
  for my $idx (sort{$a<=>$b} keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
      $sq .= $idx." => ".$sub->($idx)."\n";             
  }
      
return $sq;
}

################################################################
#                      Setter purgeSendqueue
################################################################
sub _setpurgeSendqueue {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  if($prop eq "-all-") {
      delete $hash->{OPIDX};
      delete $data{SSChatBot}{$name}{sendqueue}{entries};
      $data{SSChatBot}{$name}{sendqueue}{index} = 0;
      return "All entries of SendQueue are deleted";
  
  } elsif($prop eq "-permError-") {
      for my $idx (keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) { 
          delete $data{SSChatBot}{$name}{sendqueue}{entries}{$idx} 
              if($data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend});            
      }
      return qq{All entries with state "permanent send error" are deleted};
  
  } else {
      delete $data{SSChatBot}{$name}{sendqueue}{entries}{$prop};
      return qq{SendQueue entry with index "$prop" deleted};
  }
      
return;
}

######################################################################################################
#                                          Setter asyncSendItem
#
# einfachster Sendetext users="user1"
# text="First line of message to post.\nAlso you can have a second line of message." users="user1"
# text="<https://www.synology.com>" users="user1"
# text="Check this!! <https://www.synology.com|Click here> for details!" users="user1,user2" 
# text="a fun image" fileUrl="http://imgur.com/xxxxx" users="user1,user2" 
# text="aktuelles SVG-Plot" svg="<SVG-Device>,<zoom>,<offset>" users="user1,user2" 
#
######################################################################################################
sub _setasyncSendItem {                                                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $aref  = $paref->{aref};
  
  delete $hash->{HELPER}{RESENDFORCE};                                                      # Option 'force' löschen (könnte durch restartSendqueue gesetzt sein)      
  return if(!$hash->{HELPER}{USERFETCHED});
  
  my ($text,$users,$svg);
  
  my ($fileUrl,$attachment) = ("","");
  my $cmd                   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @$aref;     ## no critic 'Map blocks'
  my ($arr,$h)              = parseParams($cmd);
  
  if($h) {
      $text       = $h->{text}                                   if(defined $h->{text});
      $users      = $h->{users}                                  if(defined $h->{users});
      $fileUrl    = $h->{fileUrl}                                if(defined $h->{fileUrl});       # ein File soll über einen Link hochgeladen und versendet werden
      $svg        = $h->{svg}                                    if(defined $h->{svg});           # ein SVG-Plot soll versendet werden
      $attachment = formString($h->{attachments}, "attachement") if(defined $h->{attachments});
  }
  
  if($arr) {
      my @t = @{$arr};
      shift @t; shift @t;
      $text = join(" ", @t) if(!$text);
  }      

  if($svg) {                                                             # Versenden eines Plotfiles         
      my ($err, $file) = plotToFile ($name, $svg);
      return if($err);
      
      my $FW    = $hash->{FW};
      my $csrf  = $defs{$FW}{CSRFTOKEN} // "";
      $fileUrl  = (split("sschat", $hash->{OUTDEF}))[0];
      $fileUrl .= "sschat/www/images/$file?&fwcsrf=$csrf";
      
      $fileUrl  = formString($fileUrl, "text");
      $text     = $svg if(!$text);                                       # Name des SVG-Plots + Optionen als Standardtext
  }
  
  return qq{Your sendstring is incorrect. It must contain at least text with the "text=" tag like text="..."\nor only some text like "this is a test" without the "text=" tag.} if(!$text);
  
  $text  = formString($text, "text");
  
  $users = AttrVal($name,"defaultPeer", "") if(!$users);
  return "You haven't defined any receptor for send the message to. ".
         "You have to use the \"users\" tag or define default receptors with attribute \"defaultPeer\"." if(!$users);
  
  # User aufsplitten und zu jedem die ID ermitteln
  my @ua = split(/,/x, $users);
  for my $user (@ua) {
      next if(!$user);
      my $uid = $hash->{HELPER}{USERS}{$user}{id};
      return qq{The receptor "$user" seems to be unknown because its ID coulnd't be found.} if(!$uid);
       
      # Eintrag zur SendQueue hinzufügen
      # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
      my $params = { 
          name       => $name,
          opmode     => "sendItem",
          method     => "chatbot",
          userid     => $uid,
          text       => $text,
          fileUrl    => $fileUrl,
          channel    => "",
          attachment => $attachment
      };
      addQueue ($params);
  }
   
  getApiSites($name);
      
return;
}

################################################################
#                      Setter restartSendqueue
################################################################
sub _setrestartSendqueue {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  if($prop && $prop eq "force") {
      $hash->{HELPER}{RESENDFORCE} = 1;
  } else {
      delete $hash->{HELPER}{RESENDFORCE};
  }
  
  my $ret = getApiSites($name);
  
return $ret if($ret);
return qq{The SendQueue has been restarted.};
}

################################################################
#                           Get
################################################################
sub Get {                                  
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt  = shift @a;
    my $arg  = shift @a;

    my $getlist;

    if(!$hash->{TOKEN}) {
        return;
        
    } else {
        $getlist = "Unknown argument $opt, choose one of ".
                   "storedToken:noArg ".
                   "chatUserlist:noArg ".
                   "chatChannellist:noArg ".
                   "versionNotes " 
                   ;
    }
          
    return if(IsDisabled($name)); 

    my $pars = {
        hash => $hash,
        name => $name,
        opt  => $opt,
        arg  => $arg,
    };
  
    no strict "refs";                                                        ## no critic 'NoStrict'  
    if($hget{$opt}) {
        my $ret = "";
        $ret = &{$hget{$opt}{fn}} ($pars) if(defined &{$hget{$opt}{fn}}); 
        return $ret;
    }
    use strict "refs";

return $getlist;                                                        # not generate trigger out of command
}

################################################################
#                      Getter storedToken
################################################################
sub _getstoredToken {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  if (!$hash->{TOKEN}) {return qq{Token of $name is not set - make sure you've set it with "set $name botToken <TOKEN>"};}
 
  my ($success, $token) = getToken($hash,0,"botToken");                                        # Token abrufen
  unless ($success) {return qq{Token couldn't be retrieved successfully - see logfile}};

  return qq{Stored Token to act as Synology Chat Bot:\n}.
         qq{=========================================\n}.
         qq{$token \n}
         ; 
}

################################################################
#                      Getter chatUserlist
################################################################
sub _getchatUserlist {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
  delClhash ($name);
  getClhash ($hash,1);

  # Eintrag zur SendQueue hinzufügen
  my $params = { 
      name       => $name,
      opmode     => "chatUserlist",
      method     => "user_list",
      userid     => "",
      text       => "",
      fileUrl    => "",
      channel    => "",
      attachment => ""
  };
  addQueue    ($params);
  getApiSites ($name);
        
return;
}

################################################################
#                      Getter chatChannellist
################################################################
sub _getchatChannellist {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  # übergebenen CL-Hash (FHEMWEB) in Helper eintragen
  delClhash ($name);       
  getClhash ($hash,1);
    
  # Eintrag zur SendQueue hinzufügen
  my $params = { 
      name       => $name,
      opmode     => "chatChannellist",
      method     => "channel_list",
      userid     => "",
      text       => "",
      fileUrl    => "",
      channel    => "",
      attachment => ""
  };
  addQueue    ($params);
  getApiSites ($name);
        
return;
}

################################################################
#                      Getter versionNotes
################################################################
sub _getversionNotes {                   ## no critic "not used"
  my $paref = shift;
  my $arg   = $paref->{arg};
  
  my $header  = "<b>Module release information</b><br>";
  my $header1 = "<b>Helpful hints</b><br>";
  my $ret     = "";
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
          for my $hint (@hints) {
              if(AttrVal("global","language","EN") eq "DE") {
                  $hs{$hint} = $vHintsExt_de{$hint};
              } else {
                  $hs{$hint} = $vHintsExt_en{$hint};
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
      for my $key (sortVersion("desc",keys %hs)) {
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
      for my $key (sortVersion("desc",keys %vNotesExtern)) {
          ($val0,$val1) = split(/\s/x, $vNotesExtern{$key},2);
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
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub initOnBoot {
  my $hash = shift;
  my $name = $hash->{NAME};
  my ($ret,$csrf,$fuuid);
  
  RemoveInternalTimer($hash, "FHEM::SSChatBot::initOnBoot");
  
  if ($init_done) {
      # check ob FHEMWEB Instanz für SSChatBot angelegt ist -> sonst anlegen
      my @FWports;
      my $FWname = "sschat";                                        # der Pfad nach http://hostname:port/ der neuen FHEMWEB Instanz -> http://hostname:port/sschat
      my $FW     = "WEBSSChatBot";                                  # Name der FHEMWEB Instanz für SSChatBot
      
      for my $dev ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
          $hash->{FW} = $dev if ( AttrVal( $dev, "webname", "fhem" ) eq $FWname );
          push @FWports, $defs{$dev}{PORT};
      }

      if (!defined($hash->{FW})) {                                          # FHEMWEB für SSChatBot ist noch nicht angelegt
          my $room = AttrVal($name, "room", "Chat");
          my $port = 8082;
          
          while (grep {/^$port$/x} @FWports) {                              # den ersten freien FHEMWEB-Port ab 8082 finden
              $port++;
          }

          if (!defined($defs{$FW})) {                                       # wenn Device "WEBSSChat" wirklich nicht existiert
              Log3($name, 3, "$name - Creating new FHEMWEB instance \"$FW\" with webname \"$FWname\"... ");
              $ret = CommandDefine(undef, "$FW FHEMWEB $port global");
          }
          
          if(!$ret) {
              Log3($name, 3, "$name - FHEMWEB instance \"$FW\" with webname \"$FWname\" created");
              $hash->{FW} = $FW;
              
              $fuuid = $defs{$FW}{FUUID};
              $csrf  = (split("-", $fuuid, 2))[0];
              
              CommandAttr(undef, "$FW closeConn 1");
              CommandAttr(undef, "$FW webname $FWname"); 
              CommandAttr(undef, "$FW room $room");
              CommandAttr(undef, "$FW csrfToken $csrf");
              CommandAttr(undef, "$FW comment WEB Instance for SSChatBot devices.\nIt catches outgoing messages from Synology Chat server.\nDon't edit this device manually (except such attributes like \"room\", \"icon\") !");
              CommandAttr(undef, "$FW stylesheetPrefix default");            
          
          } else {
              Log3($name, 2, "$name - ERROR while creating FHEMWEB instance ".$hash->{FW}." with webname \"$FWname\" !");
              readingsBeginUpdate($hash); 
              readingsBulkUpdate ($hash, "state", "ERROR in initialization - see logfile");                             
              readingsEndUpdate  ($hash,1);
          }
      }
     
      if(!$ret) {
          CommandGet(undef, "$name chatUserlist");                      # Chatuser Liste initial abrufen 
      
          my $host        = hostname();                                 # eigener Host
          my $fqdn        = hostfqdn();                                 # MYFQDN eigener Host 
          chop($fqdn)     if($fqdn =~ /\.$/x);                          # eventuellen "." nach dem FQDN entfernen
          my $FWchatport  = $defs{$FW}{PORT};
          my $FWprot      = AttrVal($FW, "HTTPS", 0);
          $FWname         = AttrVal($FW, "webname", 0);
          
          CommandAttr(undef, "$FW csrfToken none") if(!AttrVal($FW, "csrfToken", ""));
          
          $csrf           = $defs{$FW}{CSRFTOKEN} // "";
          $hash->{OUTDEF} = ($FWprot ? "https" : "http")."://".($fqdn // $host).":".$FWchatport."/".$FWname."/outchat?botname=".$name."&fwcsrf=".$csrf; 

          addExtension($name, "FHEM::SSChatBot::botCGI", "outchat");
          $hash->{HELPER}{INFIX} = "outchat"; 
      }
              
  } else {
      InternalTimer(gettimeofday()+3, "FHEM::SSChatBot::initOnBoot", $hash, 0);
  }
  
return;
}

######################################################################################
#                            Eintrag zur SendQueue hinzufügen
#
# ($name,$opmode,$method,$userid,$text,$fileUrl,$channel,$attachment)
######################################################################################
sub addQueue {
    my $paref      = shift;
    my $name       = $paref->{name}    // do {my $err = qq{internal ERROR -> name is empty}; Log 1, "SSChatBot - $err"; return};
    my $hash       = $defs{$name};
    my $opmode     = $paref->{opmode}  // do {my $err = qq{internal ERROR -> opmode is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $method     = $paref->{method}  // do {my $err = qq{internal ERROR -> method is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $userid     = $paref->{userid}  // do {my $err = qq{internal ERROR -> userid is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $text       = $paref->{text};
    my $fileUrl    = $paref->{fileUrl};
    my $channel    = $paref->{channel};
    my $attachment = $paref->{attachment};
    
    if(!$text && $opmode !~ /chatUserlist|chatChannellist/x) {
        my $err = qq{can't add message to queue: "text" is empty};
        Log3($name, 2, "$name - ERROR - $err");
        
        setReadingErrorState ($hash, $err);      

        return;        
    }
   
   $data{SSChatBot}{$name}{sendqueue}{index}++;
   my $index = $data{SSChatBot}{$name}{sendqueue}{index};
   
   Log3($name, 5, "$name - Add Item to queue - Idx: $index, Opmode: $opmode, Text: $text, fileUrl: $fileUrl, attachment: $attachment, userid: $userid");
   
   my $pars = {'opmode'     => $opmode,   
               'method'     => $method, 
               'userid'     => $userid,
               'channel'    => $channel,
               'text'       => $text,
               'attachment' => $attachment,
               'fileUrl'    => $fileUrl,  
               'retryCount' => 0               
              };
                      
   $data{SSChatBot}{$name}{sendqueue}{entries}{$index} = $pars;  

   updQLength ($hash);                        # updaten Länge der Sendequeue     
   
return;
}

################################################################
#                asynchrone Queue starten
#                $rst = resend Timer
################################################################
sub startQueue {                   
  my $name = shift // return;
  my $rst  = shift // return;
  my $hash = $defs{$name};

  RemoveInternalTimer ($hash, "FHEM::SSChatBot::getApiSites");
  InternalTimer       ($rst,  "FHEM::SSChatBot::getApiSites", "$name", 0);   
                    
return;
}

#############################################################################################
#              Erfolg einer Rückkehrroutine checken und ggf. Send-Retry ausführen
#              bzw. den SendQueue-Eintrag bei Erfolg löschen
#              $name  = Name des Chatbot-Devices
#              $retry = 0 -> Opmode erfolgreich (DS löschen), 
#                       1 -> Opmode nicht erfolgreich (Abarbeitung nach ckeck errorcode
#                            eventuell verzögert wiederholen)
#############################################################################################
sub checkRetry {  
  my ($name,$retry) = @_;
  my $hash          = $defs{$name};  
  my $idx           = $hash->{OPIDX};
  my $forbidSend    = "";
  
  if(!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
      Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
      updQLength ($hash);
      return;  
  } 
  
  if(!$retry) {                                                                           # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{SSChatBot}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, qq{$name - Opmode "$hash->{OPMODE}" finished successfully, Sendqueue index "$idx" deleted.});
      updQLength ($hash);
      return getApiSites($name);                                                          # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer)
  
  } else {                                                                                # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount};
  
      my $errorcode = ReadingsVal($name, "Errorcode", 0);
      if($errorcode =~ /100|101|117|120|407|409|410|800|900/x) {                          # bei diesen Errorcodes den Queueeintrag nicht wiederholen, da dauerhafter Fehler !
          $forbidSend = expErrors($hash,$errorcode);                                      # Fehlertext zum Errorcode ermitteln
          $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend} = $forbidSend;
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. It seems to be a permanent error. Exclude it from new send attempt !");
          
          delete $hash->{OPIDX};
          delete $hash->{OPMODE};
          
          updQLength ($hash);                                                             # updaten Länge der Sendequeue
          
          return getApiSites($name);                                                      # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer);
      }
      
      if(!$forbidSend) {
          my $rs = 0;
          $rs = $rc <= 1 ? 5 
              : $rc <  3 ? 20
              : $rc <  5 ? 60
              : $rc <  7 ? 1800
              : $rc < 30 ? 3600
              : 86400
              ;
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. Restart SendQueue in $rs seconds (retryCount $rc).");
          
          my $rst = gettimeofday()+$rs;                                                  # resend Timer 
          updQLength ($hash,$rst);                                                       # updaten Länge der Sendequeue mit resend Timer
          startQueue ($name,$rst);
      }
  }

return
}

################################################################
#              API Versionen und Pfade ermitteln
################################################################
sub getApiSites {
   my $name   = shift;
   my $hash   = $defs{$name};
   my $inaddr = $hash->{INADDR};
   my $inport = $hash->{INPORT};
   my $inprot = $hash->{INPROT};  
   
   my ($url,$param,$idxset,$ret);
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###            start Chat operation Send            "); 
   Log3($name, 4, "$name - ####################################################");
   Log3($name, 4, "$name - Send Queue force option is set, send also messages marked as 'forbidSend'") if($hash->{HELPER}{RESENDFORCE});

   if(!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
       $ret = "Sendqueue is empty. Nothing to do ...";
       Log3($name, 4, "$name - $ret"); 
       return $ret;  
   }
   
   # den nächsten Eintrag aus "SendQueue" selektieren und ausführen wenn nicht forbidSend gesetzt ist
   for my $idx (sort{$a<=>$b} keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
       if (!$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend} || $hash->{HELPER}{RESENDFORCE}) {
           $hash->{OPIDX}  = $idx;
           $hash->{OPMODE} = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{opmode};
           $idxset         = 1;
           last;
       }               
   }
   
   if(!$idxset) {
       $ret = "Only entries with \"forbidSend\" are in Sendqueue. Escaping ...";
       Log3($name, 4, "$name - $ret"); 
       return $ret; 
   }
   
   if ($hash->{HELPER}{API}{PARSET}) {                     # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
       Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       return chatOp($name);
   }

   my $httptimeout = AttrVal($name,"httptimeout",20);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout: $httptimeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "$inprot://$inaddr:$inport/webapi/$hash->{HELPER}{API}{INFO}{PATH}?".
              "api=$hash->{HELPER}{API}{INFO}{NAME}".
              "&method=Query".
              "&version=$hash->{HELPER}{API}{INFO}{VER}".
              "&query=$hash->{HELPER}{API}{EXTERNAL}{NAME}";

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
       url      => $url,
       timeout  => $httptimeout,
       hash     => $hash,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&getApiSites_parse
   };
   
   HttpUtils_NonblockingGet ($param);  

return;
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub getApiSites_parse {
   my $param    = shift;
   my $err      = shift;
   my $myjson   = shift;
   my $hash     = $param->{hash};
   my $name     = $hash->{NAME};
   my $inaddr   = $hash->{INADDR};
   my $inport   = $hash->{INPORT};
   my $external = $hash->{HELPER}{API}{EXTERNAL}{NAME};   

   my ($error,$errorcode,$success);
  
    if ($err ne "") {
        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - ERROR message: $err");
       
        setReadingErrorState ($hash, $err);              
        checkRetry           ($name,1);
        
        return;
        
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = evalJSON($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            checkRetry ($name,1);       
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my ($logp,$logv);
            
            my $pundef = "Path: undefined - Surveillance Station may be stopped";
            my $vundef = "Version: undefined - Surveillance Station may be stopped";
                        
          # Pfad und Maxversion von "SYNO.Chat.External" ermitteln
            my $externalpath = $data->{'data'}->{$external}->{'path'};
            $externalpath    =~ tr/_//d if (defined($externalpath));
            my $externalver  = $data->{'data'}->{$external}->{'maxVersion'}; 
       
            $logp = defined($externalpath) ? "Path: $externalpath"   : $pundef;
            $logv = defined($externalver)  ? "Version: $externalver" : $vundef;
            Log3($name, 4, "$name - API $external -> $logp, $logv");
                   
            # ermittelte Werte in $hash einfügen
            if(defined($externalpath) && defined($externalver)) {
                $hash->{HELPER}{API}{EXTERNAL}{PATH} = $externalpath;
                $hash->{HELPER}{API}{EXTERNAL}{VER}  = $externalver;

                $hash->{HELPER}{API}{PARSET}         = 1;               # Webhook Hash values sind gesetzt               
       
                setReadingErrorNone($hash, 1);                
            
            } else {
                $errorcode = "805";
                $error     = expErrors($hash,$errorcode);               # Fehlertext zum Errorcode ermitteln
            
                setReadingErrorState ($hash, $error, $errorcode);   
                checkRetry              ($name,1);  
                return;                
            }
                        
        } else {
            $errorcode = "806";
            $error     = expErrors($hash,$errorcode);                   # Fehlertext zum Errorcode ermitteln
            
            setReadingErrorState ($hash, $error, $errorcode);
            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
            
            checkRetry ($name,1);    
            return;
        }
    }
    
return chatOp ($name);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub chatOp {  
   my $name         = shift;
   my $hash         = $defs{$name};
   my $inprot       = $hash->{INPROT};
   my $inaddr       = $hash->{INADDR};
   my $inport       = $hash->{INPORT};
   my $external     = $hash->{HELPER}{API}{EXTERNAL}{NAME}; 
   my $externalpath = $hash->{HELPER}{API}{EXTERNAL}{PATH};
   my $externalver  = $hash->{HELPER}{API}{EXTERNAL}{VER};
   my ($url,$httptimeout,$param,$error,$errorcode);
   
   # Token abrufen
   my ($success, $token) = getToken($hash,0,"botToken");
   unless ($success) {
       $errorcode = "810";
       $error     = expErrors($hash,$errorcode);                  # Fehlertext zum Errorcode ermitteln
       
       setReadingErrorState ($hash, $error, $errorcode);
       Log3($name, 2, "$name - ERROR - $error"); 
       
       checkRetry ($name,1);
       return;
   }
      
   my $idx         = $hash->{OPIDX};
   my $opmode      = $hash->{OPMODE};
   my $method      = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{method};
   my $userid      = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{userid};
   my $channel     = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{channel};
   my $text        = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{text};
   my $attachment  = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{attachment};
   my $fileUrl     = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{fileUrl};
   
   Log3($name, 4, "$name - start SendQueue entry index \"$idx\" ($hash->{OPMODE}) for operation."); 

   $httptimeout   = AttrVal($name, "httptimeout", 20);
   
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout: $httptimeout s");

   if ($opmode =~ /^chatUserlist$|^chatChannellist$/x) {
      $url = "$inprot://$inaddr:$inport/webapi/$externalpath?api=$external&version=$externalver&method=$method&token=\"$token\"";
   }
   
   if ($opmode eq "sendItem") {
      # Form: payload={"text": "a fun image", "file_url": "http://imgur.com/xxxxx" "user_ids": [5]} 
      #       payload={"text": "First line of message to post in the channel" "user_ids": [5]}
      #       payload={"text": "Check this!! <https://www.synology.com|Click here> for details!" "user_ids": [5]}
      
      $url  = "$inprot://$inaddr:$inport/webapi/$externalpath?api=$external&version=$externalver&method=$method&token=\"$token\"";
      $url .= "&payload={";
      $url .= "\"text\": \"$text\","          if($text);
      $url .= "\"file_url\": \"$fileUrl\","   if($fileUrl);
      $url .= "\"attachments\": $attachment," if($attachment);
      $url .= "\"user_ids\": [$userid]"       if($userid);
      $url .= "}";
   }

   my $part = $url;
   if(AttrVal($name, "showTokenInLog", "0") == 1) {
       Log3($name, 4, "$name - Call-Out: $url");
   
   } else {
       $part =~ s/$token/<secret>/x;
       Log3($name, 4, "$name - Call-Out: $part");
   }
   
   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&chatOp_parse
            };
   
   HttpUtils_NonblockingGet ($param);   

return;
} 
  
#############################################################################################
#                                Callback from chatOp
#############################################################################################
sub chatOp_parse {                                                                           
   my ($param, $err, $myjson) = @_;
   my $hash   = $param->{hash};
   my $name   = $hash->{NAME};
   my $inprot = $hash->{INPROT};
   my $inaddr = $hash->{INADDR};
   my $inport = $hash->{INPORT};
   my $opmode = $hash->{OPMODE};
   my ($data,$success,$error,$errorcode,$cherror);
   
   my $lang = AttrVal("global","language","EN");
   
   if ($err ne "") {
       # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - ERROR message: $err");
        
       $errorcode = "none";
       $errorcode = "800" if($err =~ /:\smalformed\sor\sunsupported\sURL$/xs);

       setReadingErrorState ($hash, $err, $errorcode);
       checkRetry    ($name,1);        
       return;
   
   } elsif ($myjson ne "") {    
       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
       # Evaluiere ob Daten im JSON-Format empfangen wurden 
       ($hash,$success) = evalJSON ($hash,$myjson);        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
           checkRetry ($name,1);       
           return;
       }
        
       $data = decode_json($myjson);
        
       # Logausgabe decodierte JSON Daten
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};

       if ($success) {  

           no strict "refs";                                                        ## no critic 'NoStrict'  
           if($hmodep{$opmode} && defined &{$hmodep{$opmode}{fn}}) {
               &{$hmodep{$opmode}{fn}} ($hash, $data); 
           }
           use strict "refs";                  

           checkRetry ($name,0);

           readingsBeginUpdate         ($hash);
           readingsBulkUpdateIfChanged ($hash, "Errorcode", "none"  );
           readingsBulkUpdateIfChanged ($hash, "Error",     "none"  );            
           readingsBulkUpdate          ($hash, "state",     "active");                    
           readingsEndUpdate           ($hash,1);
           
       } else {
           # die API-Operation war fehlerhaft
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};
           $cherror   = $data->{'error'}->{'errors'};                       # vom Chat gelieferter Fehler
           $error     = expErrors($hash,$errorcode);                        # Fehlertext zum Errorcode ermitteln
           if ($error =~ /not\sfound\sfor\serror\scode:/x) {
               $error .= " New error: ".($cherror // "");
           }
            
           setReadingErrorState ($hash, $error, $errorcode);       
           Log3($name, 2, "$name - ERROR - Operation $opmode was not successful. Errorcode: $errorcode - $error");
            
           checkRetry ($name,1);
       }
            
       undef $data;
       undef $myjson;
   }

return;
}

################################################################
#                  parse Opmode chatUserlist
################################################################
sub _parseUsers {                        ## no critic "not used"
  my $hash = shift;
  my $data = shift;
  my $name = $hash->{NAME};
     
  my ($un,$ui,$st,$nn,$em,$uids);     
  my %users = ();                
  my $i     = 0;

  my $out = "<html>";
  $out   .= "<b>Synology Chat Server visible Users</b> <br><br>";
  $out   .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
  $out   .= "<tr><td> <b>Username</b> </td><td> <b>ID</b> </td><td> <b>state</b> </td><td> <b>Nickname</b> </td><td> <b>Email</b> </td><td></tr>";
  $out   .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";

  while ($data->{'data'}->{'users'}->[$i]) {
      my $deleted = jboolmap($data->{'data'}->{'users'}->[$i]->{'deleted'});
      my $isdis   = jboolmap($data->{'data'}->{'users'}->[$i]->{'is_disabled'});
      if($deleted ne "true" && $isdis ne "true") {
          $un                   = $data->{'data'}->{'users'}->[$i]->{'username'};
          $ui                   = $data->{'data'}->{'users'}->[$i]->{'user_id'};
          $st                   = $data->{'data'}->{'users'}->[$i]->{'status'};
          $nn                   = $data->{'data'}->{'users'}->[$i]->{'nickname'};
          $em                   = $data->{'data'}->{'users'}->[$i]->{'user_props'}->{'email'};
          $users{$un}{id}       = $ui;
          $users{$un}{status}   = $st;
          $users{$un}{nickname} = $nn;
          $users{$un}{email}    = $em;
          $uids                .= "," if($uids);
          $uids                .= $un;
          $out                 .= "<tr><td> $un </td><td> $ui </td><td> $st </td><td>  $nn </td><td> $em </td><td></tr>";
      }
      $i++;
  }

  $hash->{HELPER}{USERS}       = \%users if(%users);
  $hash->{HELPER}{USERFETCHED} = 1;

  my @newa;
  my $list = $modules{$hash->{TYPE}}{AttrList};
  my @deva = split(" ", $list);

  for my $da (@deva) {
      push @newa, $da if($da !~ /defaultPeer:|allowedUserFor(?:Set|Get|Code|Own):/x);
  }

  push @newa, ($uids ? "defaultPeer:multiple-strict,$uids "       : "defaultPeer:--no#userlist#selectable--"       );
  push @newa, ($uids ? "allowedUserForSet:multiple-strict,$uids " : "allowedUserForSet:--no#userlist#selectable--" );
  push @newa, ($uids ? "allowedUserForGet:multiple-strict,$uids " : "allowedUserForGet:--no#userlist#selectable--" );
  push @newa, ($uids ? "allowedUserForCode:multiple-strict,$uids ": "allowedUserForCode:--no#userlist#selectable--");
  push @newa, ($uids ? "allowedUserForOwn:multiple-strict,$uids " : "allowedUserForOwn:--no#userlist#selectable--" );

  $hash->{".AttrList"} = join(" ", @newa);              # Device spezifische AttrList, überschreibt Modul AttrList !      

  $out .= "</table>";
  $out .= "</html>";

  # Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
  # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
  asyncOutput   ($hash->{HELPER}{CL}{1},"$out");
  InternalTimer (gettimeofday()+10.0, "FHEM::SSChatBot::delClhash", $name, 0); 
      
return;
}

################################################################
#                  parse Opmode chatChannellist
################################################################
sub _parseChannels {                     ## no critic "not used"
  my $hash = shift;
  my $data = shift;
  my $name = $hash->{NAME};
                 
  my ($ci,$cr,$mb,$ty,$cids);  
  my %channels = ();                
  my $i        = 0;
    
  my $out  = "<html>";
  $out    .= "<b>Synology Chat Server visible Channels</b> <br><br>";
  $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
  $out    .= "<tr><td> <b>Channelname</b> </td><td> <b>ID</b> </td><td> <b>Creator</b> </td><td> <b>Members</b> </td><td> <b>Type</b> </td><td></tr>";
  $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
    
  while ($data->{'data'}->{'channels'}->[$i]) {
      my $cn = jboolmap($data->{'data'}->{'channels'}->[$i]->{'name'});
      if($cn) {
          $ci                     = $data->{'data'}->{'channels'}->[$i]->{'channel_id'};
          $cr                     = $data->{'data'}->{'channels'}->[$i]->{'creator_id'};
          $mb                     = $data->{'data'}->{'channels'}->[$i]->{'members'};
          $ty                     = $data->{'data'}->{'channels'}->[$i]->{'type'};
          $channels{$cn}{id}      = $ci;
          $channels{$cn}{creator} = $cr;
          $channels{$cn}{members} = $mb;
          $channels{$cn}{type}    = $ty;
          $cids                  .= "," if($cids);
          $cids                  .= $cn;
          $out                   .= "<tr><td> $cn </td><td> $ci </td><td> $cr </td><td>  $mb </td><td> $ty </td><td></tr>";
      }
      $i++;
  }
  $hash->{HELPER}{CHANNELS} = \%channels if(%channels);
    
  $out .= "</table>";
  $out .= "</html>";  

  # Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
  # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
  asyncOutput  ($hash->{HELPER}{CL}{1},"$out");
  InternalTimer(gettimeofday()+5.0, "FHEM::SSChatBot::delClhash", $name, 0);
      
return;
}

################################################################
#                  parse Opmode sendItem
################################################################
sub _parseSendItem {                     ## no critic "not used"
  my $hash = shift;
  my $data = shift;
  my $name = $hash->{NAME};
                 
  my $postid = "";
  my $idx    = $hash->{OPIDX};
  my $uid    = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{userid}; 
  if($data->{data}{succ}{user_id_post_map}{$uid}) {
      $postid = $data->{data}{succ}{user_id_post_map}{$uid};   
  }                
        
  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "sendPostId", $postid); 
  readingsBulkUpdate  ($hash, "sendUserId", $uid   );                    
  readingsEndUpdate   ($hash,1); 
      
return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
###############################################################################
sub evalJSON { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  my ($error,$errorcode);
  
  eval {decode_json($myjson)} or do {
          $success   = 0;
          $errorcode = "900";         
          $error     = expErrors($hash,$errorcode);                     # Fehlertext zum Errorcode ermitteln
            
          setReadingErrorState ($hash, $error, $errorcode);
  };
  
return($hash,$success,$myjson);
}

######################################################################################
#                            botToken speichern
######################################################################################
sub setToken {
    my ($hash, $token, $ao) = @_;
    my $name           = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);   
    
    $credstr = encode_base64($token);
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //x, $credstr;  ## no critic 'Map blocks'
    # End Scramble-Routine    
       
    $index   = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving Token - $retcode");
        $success = 0;
    } else {
        ($success, $token) = getToken($hash,1,$ao);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
    }

return $success;
}

######################################################################################
#                             botToken lesen
######################################################################################
sub getToken {
    my ($hash,$boot, $ao) = @_;
    my $name               = $hash->{NAME};
    my ($success, $token, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot) {
        # mit $boot=1 botToken von Platte lesen und als scrambled-String in RAM legen
        $index               = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read botToken from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            # beim Boot scrambled botToken in den RAM laden
            $hash->{HELPER}{TOKEN} = $credstr;
    
            # "TOKEN" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{TOKEN} = "Set";
            $success = 1;
        }
    
    } else {
        # boot = 0 -> botToken aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{TOKEN};
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //x, $credstr;   ## no critic 'Map blocks' 
            # Ende Descramble-Routine
            
            $token = decode_base64($credstr);
            
            my $logtok = AttrVal($name, "showTokenInLog", "0") == 1 ? $token : "********";
        
            Log3($name, 4, "$name - botToken read from RAM: $logtok");
        
        } else {
            Log3($name, 2, "$name - botToken not set in RAM !");
        }
    
        $success = (defined($token)) ? 1 : 0;
    }

return ($success, $token);        
}

#############################################################################################
#                      FHEMWEB Extension hinzufügen           
#############################################################################################
sub addExtension {
  my ($name, $func, $link) = @_;

  my $url                        = "/$link";  
  $data{FWEXT}{$url}{deviceName} = $name;
  $data{FWEXT}{$url}{FUNC}       = $func;
  $data{FWEXT}{$url}{LINK}       = $link;
  
  Log3($name, 3, "$name - SSChatBot \"$name\" for URL $url registered");
  
return;
}

#############################################################################################
#                      FHEMWEB Extension löschen           
#############################################################################################
sub removeExtension {
  my ($link) = @_;

  my $url  = "/$link";
  my $name = $data{FWEXT}{$url}{deviceName};
  
  my @chatdvs = devspec2array("TYPE=SSChatBot");
  for my $cd (@chatdvs) {                                            # /outchat erst deregistrieren wenn keine SSChat-Devices mehr vorhanden sind außer $name
      if($defs{$cd} && $cd ne $name) {
          Log3($name, 2, "$name - Skip unregistering SSChatBot for URL $url");
          return;
      }
  }
  
  Log3($name, 2, "$name - Unregistering SSChatBot for URL $url...");
  delete $data{FWEXT}{$url};
  
return;
}

#############################################################################################
#                        Länge Senedequeue updaten          
#############################################################################################
sub updQLength {
  my ($hash,$rst) = @_;
  my $name        = $hash->{NAME};
 
  my $ql = keys %{$data{SSChatBot}{$name}{sendqueue}{entries}};
  
  readingsBeginUpdate         ($hash);                                             
  readingsBulkUpdateIfChanged ($hash, "QueueLenth", $ql);                          # Länge Sendqueue updaten
  readingsEndUpdate           ($hash,1);
  
  my $head = "next planned SendQueue start:";
  if($rst) {                                                                       # resend Timer gesetzt
      $hash->{RESEND} = $head." ".FmtDateTime($rst);
  } else {
      $hash->{RESEND} = $head." immediately by next entry";
  }

return;
}

#############################################################################################
#             Text für den Versand an Synology Chat formatieren 
#             und nicht erlaubte Zeichen entfernen 
#
#             $txt  : der zu formatierende String
#             $func : ein Name zur Identifizierung der aufrufenden Funktion
#############################################################################################
sub formString {
  my $txt  = shift;
  my $func = shift;
  my (%replacements,$pat);
  
  if($func ne "attachement") {
      %replacements = (
          '"'  => "´",                              # doppelte Hochkomma sind im Text nicht erlaubt
          " H" => "%20H",                           # Bug in HttpUtils(?) wenn vor großem H ein Zeichen + Leerzeichen vorangeht
          "#"  => "%23",                            # Hashtags sind im Text nicht erlaubt und wird encodiert
          "&"  => "%26",                            # & ist im Text nicht erlaubt und wird encodiert    
          "%"  => "%25",                            # % ist nicht erlaubt und wird encodiert
          "+"  => "%2B",
      );
  
  } else {
      %replacements = (
          " H" => "%20H"                            # Bug in HttpUtils(?) wenn vor großem H ein Zeichen + Leerzeichen vorangeht
      );    
  }
  
  $txt    =~ s/\n/ESC_newline_ESC/xg;
  my @acr = split (/\s+/x, $txt);
              
  $txt = "";
  for my $line (@acr) {                             # Einzeiligkeit für Versand herstellen
      $txt .= " " if($txt);
      $line =~ s/ESC_newline_ESC/\\n/xg;
      $txt .= $line;
  }
  
  $pat = join '|', map { quotemeta; } keys(%replacements);
  
  $txt =~ s/($pat)/$replacements{$1}/xg;   
  
return ($txt);
}

#############################################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
#############################################################################################
sub getClhash {      
  my ($hash,$nobgd)= @_;
  my $name  = $hash->{NAME};
  my $ret;
  
  if($nobgd) {
      # nur übergebenen CL-Hash speichern, 
      # keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
      $hash->{HELPER}{CL}{1} = $hash->{CL};
      return;
  }

  if (!defined($hash->{CL})) {
      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
      my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=canAsyncOutput=1:FILTER=STATE=Connected");
      my $i = 1;
      for my $outdev (@webdvs) {
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

#############################################################################################
#            Clienthash löschen
#############################################################################################
sub delClhash {
  my $name = shift;
  my $hash = $defs{$name};
  
  delete($hash->{HELPER}{CL});
  
return;
}

####################################################################################
#       Ausgabe der SVG-Funktion "plotAsPng" in eine Datei schreiben
#       Die Datei wird im Verzeichnis "/opt/fhem/www/images" erstellt
#
####################################################################################
sub plotToFile {
    my $name   = shift;
    my $svg    = shift;
    my $hash   = $defs{$name};
    my $file   = $name."_SendPlot.png";
    my $path   = $attr{global}{modpath}."/www/images";
    my $err    = "";
    
    my @options = split ",", $svg;
    my $svgdev  = $options[0];
    my $zoom    = $options[1];
    my $offset  = $options[2];
    
    if(!$defs{$svgdev}) {
        $err = qq{SVG device "$svgdev" doesn't exist};
        Log3($name, 1, "$name - ERROR - $err !");
        
        setReadingErrorState ($hash, $err);
        return $err;
    }
    
    open (my $FILE, ">", "$path/$file") or do {
                                                $err = qq{>PlotToFile< can't open $path/$file for write access};
                                                Log3($name, 1, "$name - ERROR - $err !");
                                                setReadingErrorState ($hash, $err);
                                                return $err;
                                              };
    binmode $FILE;
    print   $FILE plotAsPng(@options);
    close   $FILE;

return ($err, $file);
}

#############################################################################################
#                         Common Gateway Interface      
#############################################################################################
sub botCGI {                                                     
  my $request = shift;

  if(!$init_done) {
      return ( "text/plain; charset=utf-8", "FHEM server is booting up" );
  }
      
  if ($request =~ /^\/outchat(\?|&)/x) {                  # POST- oder GET-Methode empfangen
      return _botCGIdata ($request);  
  }
  
return ("text/plain; charset=utf-8", "Missing data");
}

#############################################################################################
#                         Common Gateway data receive         
#                 parsen von outgoing Messages Chat -> FHEM 
#############################################################################################
sub _botCGIdata {                                                  
  my $request = shift;
  
  my ($text,$triggerword,$command,$cr) = ("","","","");
  my ($actions,$actval,$avToExec)      = ("","","");

  my ($mime, $err, $dat) = __botCGIcheckData ($request);
  return ($mime, $err) if($err);
  
  my $name = $dat->{name};
  my $args = $dat->{args};
  my $h    = $dat->{h};
  
  Log3($name, 4, "$name - ####################################################"); 
  Log3($name, 4, "$name - ###          start Chat operation Receive           "); 
  Log3($name, 4, "$name - ####################################################");
  Log3($name, 5, "$name - raw data received (urlDecoded):\n".Dumper($args));

  my $hash  = $defs{$name};                                                            # hash des SSChatBot Devices  
  my $rst   = gettimeofday()+1;                                                        # Standardwert resend Timer
  my $state = "active";                                                                # Standardwert state 
  my $ret   = "success";
  
  if (defined($h->{payload})) {                                                        # Antwort auf ein interaktives Objekt 
      ($mime, $err) = __botCGIcheckPayload ($hash, $h);
      return ($mime, $err) if($err);
  }   
  
  if (!defined($h->{token})) {
      Log3   ($name, 5, "$name - received insufficient data:\n".Dumper($args));
      return ("text/plain; charset=utf-8", "Insufficient data");
  }
  
  my $neg = __botCGIcheckToken ($name, $h, $rst);                                      # CSRF Token check
  return $neg if($neg);
  
  if ($h->{timestamp}) {                                                               # Timestamp dekodieren
      $h->{timestamp} = FmtDateTime(($h->{timestamp})/1000);
  }
   
  Log3($name, 4, "$name - received data decoded:\n".Dumper($h));
  
  $hash->{OPMODE} = "receiveData";
  
  # ausgehende Datenfelder (Chat -> FHEM), die das Chat senden kann
  # ===============================================================
  # token: bot token
  # channel_id
  # channel_name
  # user_id
  # username
  # post_id
  # timestamp
  # text
  # trigger_word: which trigger word is matched 
  #

  my $channelid   = $h->{channel_id}   // q{};                      
  my $channelname = $h->{channel_name} // q{};  
  my $userid      = $h->{user_id}      // q{};
  my $username    = $h->{username}     // q{};
  my $postid      = $h->{post_id}      // q{};
  my $callbackid  = $h->{callback_id}  // q{};
  my $timestamp   = $h->{timestamp}    // q{};
  
  if ($h->{actions}) {                                                   # interaktive Schaltflächen (Aktionen) auswerten 
      $actions  = $h->{actions};        
      ($actval) = $actions =~ m/^type:\s+button.*?value:\s+(.*?),\s+text:/x;

      if($actval =~ /^\//x) {
          Log3 ($name, 4, "$name - slash command \"$actval\" got from interactive data and execute it with priority");
          $avToExec = $actval;        
      }
  }
  
  if ($h->{text} || $avToExec) {                                         # Interpretation empfangener Daten als auszuführende Kommandos 
      my $params = { 
          name     => $name,
          username => $username,
          userid   => $userid,
          rst      => $rst,
          state    => $state,
          h        => $h,
          avToExec => $avToExec
      };
      
      ($command, $cr, $text) = __botCGIdataInterprete ($params);       
  }
  
  if ($h->{trigger_word}) {
      $triggerword = urlDecode($h->{trigger_word});                          
      Log3($name, 4, "$name - trigger_word received: ".$triggerword);
  }

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "recActions",        $actions     );  
  readingsBulkUpdate  ($hash, "recCallbackId",     $callbackid  ); 
  readingsBulkUpdate  ($hash, "recActionsValue",   $actval      );                   
  readingsBulkUpdate  ($hash, "recChannelId",      $channelid   );  
  readingsBulkUpdate  ($hash, "recChannelname",    $channelname ); 
  readingsBulkUpdate  ($hash, "recUserId",         $userid      ); 
  readingsBulkUpdate  ($hash, "recUsername",       $username    ); 
  readingsBulkUpdate  ($hash, "recPostId",         $postid      ); 
  readingsBulkUpdate  ($hash, "recTimestamp",      $timestamp   ); 
  readingsBulkUpdate  ($hash, "recText",           $text        ); 
  readingsBulkUpdate  ($hash, "recTriggerword",    $triggerword );
  readingsBulkUpdate  ($hash, "recCommand",        $command     );       
  readingsBulkUpdate  ($hash, "sendCommandReturn", $cr          );       
  readingsBulkUpdate  ($hash, "Errorcode",         "none"       );
  readingsBulkUpdate  ($hash, "Error",             "none"       );
  readingsBulkUpdate  ($hash, "state",             $state       );        
  readingsEndUpdate   ($hash,1);
  
return ("text/plain; charset=utf-8", $ret);
}

################################################################
#                      botCGI 
#            Daten auf Validität checken
################################################################
sub __botCGIcheckData { 
  my $request = shift;

  my $args = (split(/outchat\?/x, $request))[1];        # GET-Methode empfangen 
  
  if(!$args) {                                          # POST-Methode empfangen wenn keine GET_Methode ?
      $args = (split(/outchat&/x, $request))[1];
      if(!$args) {
          Log 1, "TYPE SSChatBot - ERROR - no expected data received";
          return ("text/plain; charset=utf-8", "no expected data received");
      }
  }
  
  $args =~ s/&/" /gx;
  $args =~ s/=/="/gx;
  $args .= "\"";
  
  $args     = urlDecode($args);
  my($a,$h) = parseParams($args);
  
  if (!defined($h->{botname})) {
      Log 1, "TYPE SSChatBot - ERROR - no Botname received";
      return ("text/plain; charset=utf-8", "no FHEM SSChatBot name in message");
  }
  
  # check ob angegebenes SSChatBot Device definiert
  # wenn ja, Kontext auf botname setzen
  my $name = $h->{botname};                                                            # das SSChatBot Device
  if(!IsDevice($name, 'SSChatBot')) {
      Log 1, qq{ERROR - No SSChatBot device "$name" of Type "SSChatBot" exists};
      return ( "text/plain; charset=utf-8", "No SSChatBot device for webhook \"/outchat\" exists" );
  } 
  
  my $dat = {
      name       => $name,
      args       => $args,
      h          => $h,
  };
                    
return ('','',$dat);
}

################################################################
#                      botCGI 
#                check CSRF Token 
################################################################
sub __botCGIcheckToken {                   
  my $name     = shift;
  my $h        = shift;
  my $rst      = shift;
  my $hash     = $defs{$name};

  my $FWdev    = $hash->{FW};                           # das FHEMWEB Device für SSChatBot Device -> ist das empfangene Device
  my $FWhash   = $defs{$FWdev};
  my $want     = $FWhash->{CSRFTOKEN} // "none";
  my $supplied = $h->{fwcsrf};
 
  if($want eq "none" || $want ne $supplied) {           # $FW_wname enthält ebenfalls das aufgerufenen FHEMWEB-Device
      Log3 ($FW_wname, 2, "$FW_wname - ERROR - FHEMWEB CSRF error for client $FWdev: ".
                          "received $supplied token is not $want. ".
                          "For details see the FHEMWEB csrfToken attribute. ".
                          "The csrfToken must be identical to the token in OUTDEF of the $name device.");
                          
      my $cr     = formString("CSRF error in client '$FWdev' - see logfile", "text");   
      my $userid = $h->{user_id} // q{};
      
      my $params = { 
          name       => $name,
          opmode     => "sendItem",
          method     => "chatbot",
          userid     => $userid,
          text       => $cr,
          fileUrl    => "",
          channel    => "",
          attachment => ""
      };
      addQueue   ($params);
      startQueue ($name, $rst);
          
      return ("text/plain; charset=utf-8", "400 Bad Request");          
  }  
                    
return;
}

################################################################
#                      botCGI 
#     Payload checken (interaktives Element ausgelöst ?)
#
# ein Benutzer hat ein interaktives Objekt ausgelöst (Button). 
# Die Datenfelder sind nachfolgend beschrieben:
#   "actions":     Array des Aktionsobjekts, das sich auf die 
#                  vom Benutzer ausgelöste Aktion bezieht
#   "callback_id": Zeichenkette, die sich auf die Callback_id 
#                  des Anhangs bezieht, in dem sich die vom 
#                  Benutzer ausgelöste Aktion befindet
#   "post_id"
#   "token"
#   "user":        { "user_id","username" }
################################################################
sub __botCGIcheckPayload { 
  my $hash = shift;
  my $h    = shift;
  my $name = $hash->{NAME};

      my $pldata           = $h->{payload};
      my (undef, $success) = evalJSON($hash,$pldata);
      
      if (!$success) {
          Log3($name, 1, "$name - ERROR - invalid JSON data received:\n".Dumper $pldata); 
          return ("text/plain; charset=utf-8", "invalid JSON data received");
      }
      
      my $data = decode_json ($pldata);
      Log3($name, 5, "$name - interactive object data (JSON decoded):\n". Dumper $data);
      
      $h->{token}       = $data->{token};
      $h->{post_id}     = $data->{post_id};
      $h->{user_id}     = $data->{user}{user_id};
      $h->{username}    = $data->{user}{username};
      $h->{callback_id} = $data->{callback_id};
      $h->{actions}     = "type: ".$data->{actions}[0]{type}.", ". 
                          "name: ".$data->{actions}[0]{name}.", ". 
                          "value: ".$data->{actions}[0]{value}.", ". 
                          "text: ".$data->{actions}[0]{text}.", ". 
                          "style: ".$data->{actions}[0]{style};
           
return;
}

################################################################
#                      botCGI 
#     Interpretiere empfangene Daten als Kommandos
################################################################
sub __botCGIdataInterprete { 
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $userid   = $paref->{userid};
  my $rst      = $paref->{rst};
  my $state    = $paref->{state};
  my $h        = $paref->{h};
  my $avToExec = $paref->{avToExec};
  
  my $do       = 0; 
  my $cr       = q{};
  my $command  = q{};
  my $text     = $h->{text};
  $text        = $avToExec if($avToExec);                            # Vorrang für empfangene interaktive Data (Schaltflächenwerte) die Slash-Befehle enthalten        
  
  if($text =~ /^\/(set.*?|get.*?|code.*?)\s+(.*)$/ix) {              # vordefinierte Befehle in FHEM ausführen
      my $p1 = substr lc $1, 0, 3;
      my $p2 = $2;
      
      my $pars = {
          name     => $name,
          username => $username,
          state    => $state,
          p2       => $p2,
      };

      if($hrecbot{$p1} && defined &{$hrecbot{$p1}{fn}}) {
          $do = 1;
          no strict "refs";                                          ## no critic 'NoStrict'  
          ($command, $cr, $state) = &{$hrecbot{$p1}{fn}} ($pars); 
          use strict "refs";
      } 
          
      $cr = $cr ne q{} ? $cr : qq{command '$command' executed};
      Log3($name, 4, "$name - FHEM command return: ".$cr);
      
      $cr = formString($cr, "command");   

      my $params = { 
          name       => $name,
          opmode     => "sendItem",
          method     => "chatbot",
          userid     => $userid,
          text       => $cr,
          fileUrl    => "",
          channel    => "",
          attachment => ""
      };
      addQueue ($params);                                 
  }
                          
  my $ua = $attr{$name}{userattr};                                            # Liste aller ownCommandxx zusammenstellen
  $ua    = "" if(!$ua);
  my %hc = map { ($_ => 1) } grep { "$_" =~ m/ownCommand(\d+)/x } split(" ","ownCommand1 $ua");

  for my $ca (sort keys %hc) {
      my $uc = AttrVal($name, $ca, "");
      next if (!$uc);
      
      my $arg = q{};
      ($uc,$arg) = split(/\s+/x, $uc, 2);
      
      if($uc && $text =~ /^$uc\s*?$/x) {                                      # User eigener Slash-Befehl, z.B.: /Wetter 
          $do      = 1;
          
          my $pars = {
              name     => $name,
              username => $username,
              state    => $state,
              arg      => $arg,
              uc       => $uc,
          };

          ($cr, $state) = __botCGIownCommand ($pars);             
                            
          $cr = $cr ne q{} ? $cr : qq{command '$arg' executed};
          Log3($name, 4, "$name - FHEM command return: ".$cr);
          
          $cr = formString($cr, "command");

          my $params = { 
              name       => $name,
              opmode     => "sendItem",
              method     => "chatbot",
              userid     => $userid,
              text       => $cr,
              fileUrl    => "",
              channel    => "",
              attachment => ""
          };
          addQueue ($params);                                                 
      }
  }
  
  if($do) {                                                                  # Wenn Kommando ausgeführt wurde -> Queue übertragen
      startQueue ($name, $rst);       
  }  
   
return ($command, $cr, $text);
}

################################################################
#                      botCGI /set
#            set-Befehl in FHEM ausführen
################################################################
sub __botCGIrecSet {                     ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $state    = $paref->{state};
  my $p2       = $paref->{p2};
  
  my $cr       = q{};
  my $command  = "set ".$p2;
  my $au       = AttrVal($name,"allowedUserForSet", "all");

  $paref->{au}    = $au;
  $paref->{order} = "Set";
  $paref->{cmd}   = $command;
   
  ($cr, $state)   = ___botCGIorder ($paref); 
                    
return ($command, $cr, $state);
}

################################################################
#                      botCGI /get
#            get-Befehl in FHEM ausführen
################################################################
sub __botCGIrecGet {                     ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $state    = $paref->{state};
  my $p2       = $paref->{p2};
  
  my $cr       = q{};
  my $command  = "get ".$p2;              
  my $au       = AttrVal($name,"allowedUserForGet", "all");

  $paref->{au}    = $au;
  $paref->{order} = "Get";
  $paref->{cmd}   = $command;
   
  ($cr, $state)   = ___botCGIorder ($paref);  
                    
return ($command, $cr, $state);
}

################################################################
#                      botCGI /code
#            Perl Code in FHEM ausführen
################################################################
sub __botCGIrecCod {                     ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $state    = $paref->{state};
  my $p2       = $paref->{p2};
  
  my $cr       = q{};  
  my $command  = $p2;
  my $au       = AttrVal($name,"allowedUserForCode", "all");
  
  $paref->{au}    = $au;
  $paref->{order} = "Code";
  $paref->{cmd}   = $command;
  
  ($cr, $state)   = ___botCGIorder ($paref);
                    
return ($command, $cr, $state);
}

################################################################
#                      botCGI 
#            User ownCommand in FHEM ausführen
################################################################
sub __botCGIownCommand { 
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $state    = $paref->{state};
  my $arg      = $paref->{arg};
  my $uc       = $paref->{uc};
  
  my $cr       = q{};

  if(!$arg) {
      $cr = qq{format error: your own command '$uc' doesn't have a mandatory argument};
      return ($cr, $state);
  }
  
  my $au       = AttrVal($name,"allowedUserForOwn", "all");               # Berechtgung des Chat-Users checken
  
  $paref->{au}    = $au;
  $paref->{order} = "Own";
  $paref->{cmd}   = $arg;
  
  ($cr, $state)   = ___botCGIorder ($paref);
                    
return ($cr, $state);
}

################################################################
#            Order ausführen und Ergebnis zurückliefern         
################################################################
sub ___botCGIorder {                     
  my $paref    = shift;
  my $name     = $paref->{name};
  my $username = $paref->{username};
  my $state    = $paref->{state};
  my $p2       = $paref->{p2};            # Kommandoargument, z.B. "get <argument>" oder "code <argument>"
  my $au       = $paref->{au};
  my $order    = $paref->{order};         # Kommandotyp, z.B. "set"
  my $cmd      = $paref->{cmd};           # komplettes Kommando
  
  my @aul      = split ",", $au;
  my $cr       = q{}; 
  
  if($au eq "all" || $username ~~ @aul) {      
      if ($order =~ /^[GS]et$/x) {
          Log3($name, 4, qq{$name - Synology Chat user "$username" execute FHEM command: }.$cmd);
          no strict "refs";                                          ## no critic 'NoStrict' 
          $cr = &{"Command".$order} (undef, $p2);
          use strict "refs";   
      }

      if ($order eq "Code") {
          my ($arg) = $p2 =~ m/^\s*(\{.*\})\s*$/xs;

          if($arg) {
              Log3($name, 4, qq{$name - Synology Chat user "$username" execute FHEM command: }.$arg);
              $cr = AnalyzePerlCommand(undef, $arg);
          } else {
              $cr = qq{function format error: may be you didn't use the format {...}};    
          }     
      }   

      if ($order eq "Own") {                                                                         # FHEM ownCommand Befehlsketten ausführen
          Log3($name, 4, qq{$name - Synology Chat user "$username" execute FHEM command: }.$cmd);  
          $cr = AnalyzeCommandChain(undef, $cmd);                         
      }          
 
  } else {
      $cr    = qq{User "$username" is not allowed execute "$cmd" command};
      $state = qq{command execution denied};
      Log3($name, 2, qq{$name - WARNING - Chat user "$username" is not authorized for "$cmd" command. Execution denied !});
  }
                    
return ($cr, $state);
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub setVersionInfo {
  my $hash  = shift;
  my $notes = shift;

  my $v                    = (sortVersion("desc",keys %{$notes}))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  $hash->{HELPER}{VERSION_API}      = $vAPI      // "unused";
  $hash->{HELPER}{VERSION_SMUtils}  = $vSMUtils  // "unused";
  $hash->{HELPER}{VERSION_ErrCodes} = $vErrCodes // "unused";
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {          # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                           # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{<TYPE>}{META}}
      
      if($modules{$type}{META}{x_version}) {                                             # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
      
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {                         # es wird mit Packages gearbeitet -> mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get($hash, 'version');            ## no critic 'VERSION'                                      
      }
  
  } else {                                                                               # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

1;

=pod
=item summary    module to integrate Synology Chat into FHEM
=item summary_DE Modul zur Integration von Synology Chat in FHEM
=begin html

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>
  This module is used to integrate Synology Chat Server with FHEM. This makes it possible, 
  Exchange messages between FHEM and Synology Chat Server. <br>
  A detailed description of the module is available in the 
  <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">Wiki</a> available. <br>     
  <br><br> 

  <a name="SSChatBotDefine"></a>
  <b>Definition</b>
  <br><br>
  <ul>    
  
    The definition is made with: <br><br>
    <ul>
      <b>define &lt;Name&gt; SSChatBot &lt;IP&gt; [Port] [Protokoll] </b>
    </ul>
    <br>

    The Port and Protocol entries are optional.
    <br><br>
    
    <ul>
     <li><b>IP:</b> IP address or name of Synology DiskStation. If the name is used, set the dnsServer global attribute. </li>
     <li><b>Port:</b> Port of Synology DiskStation (default 5000) </li>
     <li><b>Protocol:</b> Protocol for messages towards chat server, http or https (default http) </li>    </ul>
    <br>
  
    During the definition, an extra FHEMWEB device for receiving messages is created in addition to the SSChaBot device
    in the "Chat" room. The port of the FHEMWEB device is automatically determined with start port 8082. If this port is occupied, 
    the ports are checked in ascending order for possible assignment by an FHEMWEB device and the next 
    free port is assigned to the new Device. <br>

    The chat integration distinguishes between "Incoming messages" (FHEM -> Chat) and "Outgoing messages 
    (Chat -> FHEM). <br>
     
  </ul>
  <br><br> 

  <a name="SSChatBotConfig"></a>
  <b>Configuration</b>
  <br><br>
  <ul>    

    For the <b>activation of incoming messages (FHEM -> Chat)</b> a bot token is required. This token can be activated via the user-defined 
    Embedding functions in the Synology Chat application can be created or modified from within the Synology Chat application. 
    (see also the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#Aktivierung_eingehende_Nachrichten_.28FHEM_-.3E_Chat.29">wiki section</a> ) <br>
  
    The token is inserted into the newly defined SSChatBot device with the command:
    <br><br>
    <ul>
      <b>set &lt;Name&gt; botToken U6FOMH9IgT22ECJceaIW0fNwEi7VfqWQFPMgJQUJ6vpaGoWZ1SJkOGP7zlVIscCp </b>
    </ul>
    <br>
    Use of course the real token created by the chat application.
    <br><br>
  
    For <b> activation of outgoing messages (Chat -> FHEM)</b> the field Outgoing URL must be filled in the chat application. 
    To do so, click the Profile Photo icon in the upper right corner of the called Synology Chat Application and select 
    "Integration." Then select the bot created in the first step in the "Bots" menu.
    
    The value of the internal <b>OUTDEF</b> of the created SSChatBot device is now copied into the field Outgoing URL. <br>
    For example, the string could look like this: <br><br>
  
    <ul>
      http://myserver.mydom:8086/sschat/outchat?botname=SynChatBot&fwcsrf=5de17731
    </ul>
    <br>
  
    (see also the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#Aktivierung_ausgehende_Nachrichten_.28Chat_-.3E_FHEM.29">wiki section</a> ) <br>
    
    <br><br>
    <b>General information on sending messages </b> <br>
    Messages that FHEM sends to the chat server (incoming messages) are first placed in a queue in FHEM. 
    The send process is started immediately. If the transmission was successful, the message is deleted from the queue. 
    Otherwise, it remains in the queue and the send process will, in a time interval, restarted. <br>
    With the Set command <b>restartSendqueue</b> the processing of the queue can be started manually 
    (for example, after Synology maintenance). 
    
    <br><br>

    <b>Allgemeine Information zum Nachrichtempfang </b> <br>
    Um Befehle vom Chat Server an FHEM zu senden, werden Slash-Befehle (/) verwendet. Sie sind vor der Verwendung im Synology 
    Chat und ggf. zusätzlich im SSChatBot Device (User spezifische Befehle) zu konfigurieren. <br><br>

    The following command forms are supported: <br><br>
    <ul> 
      <li> /set </li>
      <li> /get </li>
      <li> /code </li>
      <li> /&lt;User specific command&gt; (see attribute <a href="#ownCommandx">ownCommandx</a>) </li>
    </ul>
    <br>
    
    Further detailed information on configuring message reception is available in the corresponding 
    <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#FHEM-Befehle_aus_dem_Chat_an_FHEM_senden">wiki section</a>.
  </ul>
  <br><br> 

  <a name="SSChatBotSet"></a>
  <b>Set </b>
  <br><br>
  <ul>

    <ul>
      <a name="asyncSendItem"></a>
      <li><b> asyncSendItem &lt;Item&gt; </b> <br>
  
      Sends a message to one or more chat recipients. <br>      
      For more information about the available options for asyncSendItem, especially the use of interactive
      objects (buttons), please consult this  
      <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#verschiedene_Arten_Nachrichten_an_Chatempf.C3.A4nger_senden">wiki section</a>.
      <br><br>
      
      <ul>
        <b>Beispiele:</b> <br>        
        set &lt;Name&gt; asyncSendItem First message line to post.\n You can also have a second message line. [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="First message line to post.\n You can also have a second message line. [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="https://www.synology.com" [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="Check this! &lt;https://www.synology.com|Click here&gt; for details!" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;name&gt; asyncSendItem text="a funny picture" fileUrl="http://imgur.com/xxxxx" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="current plot file" svg="&lt;SVG-Device&gt;[,&lt;Zoom&gt;][,&lt;Offset&gt;]" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="&lt;Message text&gt;" attachments="[{
                                            "callback_id": "&lt;Text for Reading recCallbackId&gt;", "text": "&lt;Heading of the button&gt;", 
                                            "actions":[{"type": "button", "name": "&lt;text&gt;", "value": "&lt;value&gt;", "text": "&lt;text&gt;", "style": "&lt;color&gt;"}] }]" <br>      </ul>
  
      </li><br>
    </ul>
   
    <ul>
      <a name="botToken"></a>
      <li><b> botToken &lt;Token&gt; </b> <br>
  
      Saves the token for access to the chat as a bot.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="listSendqueue"></a>
      <li><b> listSendqueue </b> <br>
  
      Shows the messages still to be transmitted to the chat. <br>
      All messages to be sent are first stored in a queue and transmitted asynchronously to the chat server.
  
      </li><br>
    </ul>
   
    <ul>
      <a name="purgeSendqueue"></a>
      <li><b> purgeSendqueue  &lt;-all- | -permError- | index&gt; </b> <br>
  
      Deletes entries from the send queue. <br><br>
      
      <ul>
        <li><b> -all- :</b> Deletes all entries of the send queue. </li>
        <li><b> -permError- :</b> Deletes all entries of the send queue with "permanent Error" status. </li>
        <li><b> index : </b> Deletes selected entry with "index". <br>
                             The entries in the send queue can be viewed beforehand with "set listSendqueue" to find the desired index. </li>
      </ul>
    
      </li><br>
    </ul>
    
    <ul>
      <a name="restartSendqueue"></a>
      <li><b> restartSendqueue [force] </b> <br>
  
      Restarts the processing of the send queue manually. <br>
      Any entries in the send queue marked <b>forbidSend</b> are not sent again. <br>
      If the call is made with the option <b>force</b>, entries marked forbidSend are also taken into account.
  
      </li><br>
    </ul>
   
  </ul>
  
  <a name="SSChatBotGet"></a>
  <b>Get </b>
  <br><br>
  <ul>
    
    <ul>
      <a name="chatChannellist"></a>
      <li><b> chatChannellist </b> <br>
  
      Creates a list of channels visible to the bot.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="chatUserlist"></a>
      <li><b> chatUserlist </b> <br>
  
      Creates a list of users visible to the bot. <br>
      If no users are listed, the users on Synology must have permission to use the chat application 
      can be assigned.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="storedToken"></a>
      <li><b> storedToken </b> <br>
  
      Displays the stored token.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="versionNotes"></a>
      <li><b> versionNotes </b> <br>
  
      Lists significant changes in the version history of the module.
  
      </li><br>
    </ul>
   
  </ul>
  
  <a name="SSChatBotAttr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
  
    <ul>  
      <a name="allowedUserForCode"></a>
      <li><b>allowedUserForCode</b> <br> 
  
        Names the chat users who are allowed to trigger Perl code in FHEM when the slash command /code is received. <br>
        (default: all users allowed)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="allowedUserForGet"></a>
      <li><b>allowedUserForGet</b> <br> 
  
        Names the chat users who may trigger Get commands in FHEM when the slash command /get is received. <br>
        (default: all users allowed)
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="allowedUserForOwn"></a>
      <li><b>allowedUserForOwn</b> <br> 
  
        Names the chat users who are allowed to trigger the commands defined in the attribute "ownCommand" in FHEM. <br>
        (default: all users allowed)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="allowedUserForSet"></a>
      <li><b>allowedUserForSet</b> <br> 
  
        Names the chat users who are allowed to trigger set commands in FHEM when the slash command /set is received. <br>
        (default: all users allowed)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="defaultPeer"></a>
      <li><b>defaultPeer</b> <br> 
  
        One or more (default) recipients for messages. Can be specified with the <b>users=</b> tag in the command <b>asyncSendItem</b> 
        can be overridden.
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="httptimeout"></a>
      <li><b>httptimeout &lt;seconds&gt; </b> <br> 
  
        Sets the connection timeout to the chat server. <br>
        (default 20 seconds)
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="ownCommandx"></a>
      <li><b>ownCommandx &lt;Slash command&gt; &lt;Command&gt; </b> <br> 
  
        Defines a &lt;Slash command&gt; &lt;Command&gt; pair. The slash command and the command are separated by a 
        Separate spaces. <br>
        The command is executed when the SSChatBot receives the slash command. 
        The command can be an FHEM command or Perl code. Perl code must be enclosed in <b>{ }</b>. <br><br>

        <ul>
        <b>Examples:</b> <br> 
          attr &lt;Name&gt; ownCommand1 /Wozi_Temp {ReadingsVal("eg.wz.wallthermostat","measured-temp",0)} <br>       
          attr &lt;Name&gt; ownCommand2 /Wetter get MyWetter wind_speed <br>
        </ul>       
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="showTokenInLog"></a>
      <li><b>showTokenInLog</b> <br> 
  
        If set, the transmitted bot token is displayed in the log with verbose 4/5. <br>
        (default: 0)
    
      </li><br>
    </ul>
 
  </ul>

</ul>

=end html
=begin html_DE

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>
  Mit diesem Modul erfolgt die Integration des Synology Chat Servers in FHEM. Dadurch ist es möglich, 
  Nachrichten zwischen FHEM und Synology Chat Server auszutauschen. <br>
  Eine ausführliche Beschreibung des Moduls ist im 
  <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">Wiki</a> vorhanden. <br>     
  <br><br> 

  <a name="SSChatBotDefine"></a>
  <b>Definition</b>
  <br><br>
  <ul>    
  
    Die Definition erfolgt mit: <br><br>
    <ul>
      <b>define &lt;Name&gt; SSChatBot &lt;IP&gt; [Port] [Protokoll] </b>
    </ul>
    <br>

    Die Angaben Port und Protokoll sind optional.
    <br><br>
    <ul>
     <li><b>IP:</b> IP-Adresse oder Name der Synology Diskstation. Wird der Name benutzt, ist das globale Attribut dnsServer zu setzen. </li>
     <li><b>Port:</b> Port der Synology Diskstation (default 5000) </li>
     <li><b>Protokoll:</b> Protokoll für Messages Richtung Chat-Server, http oder https (default http) </li>
    </ul>
    <br>
  
    Bei der Definition wird neben dem SSChaBot Device ebenfalls ein extra FHEMWEB Device zum Nachrichtenempfang automatisiert
    im Raum "Chat" angelegt. Der Port des FHEMWEB Devices wird automatisch ermittelt mit Startport 8082. Ist dieser Port belegt, 
    werden die Ports in aufsteigender Reihenfolge auf eine eventuelle Belegung durch ein FHEMWEB Device geprüft und der nächste 
    freie Port wird dem neuen Device zugewiesen. <br>

    Die Chatintegration unterscheidet zwischen "Eingehende Nachrichten" (FHEM -> Chat) und "Ausgehende Nachrichten" 
    (Chat -> FHEM). <br> 
     
  </ul>
  <br><br> 

  <a name="SSChatBotConfig"></a>
  <b>Konfiguration</b>
  <br><br>
  <ul>    

    Für die <b>Aktivierung eingehender Nachrichten (FHEM -> Chat)</b> wird ein Bot-Token benötigt. Dieser Token wird über die benutzerdefinierte 
    Einbindungsfunktionen in der Synology Chat-Applikation erstellt bzw. kann darüber auch verändert werden. 
    (siehe dazu auch den <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#Aktivierung_eingehende_Nachrichten_.28FHEM_-.3E_Chat.29">Wiki-Abschnitt</a> ) <br>
     
    Der Token wird in das neu definierten SSChatBot-Device eingefügt mit dem Befehl:
    <br><br>
    <ul>
      <b>set &lt;Name&gt; botToken U6FOMH9IgT22ECJceaIW0fNwEi7VfqWQFPMgJQUJ6vpaGoWZ1SJkOGP7zlVIscCp </b>
    </ul>
    <br>
    Es ist natürlich der reale, durch die Chat-Applikation erstellte Token einzusetzen.
    <br><br>
  
    Zur <b>Aktivierung ausgehende Nachrichten (Chat -> FHEM)</b> muß in der Chat-Applikation das Feld Ausgehende URL gefüllt werden. 
    Klicken Sie dazu auf das Symbol Profilfoto oben rechts in der aufgerufenen Synology Chat-Applikation und wählen Sie 
    "Einbindung". Wählen sie dann im Menü "Bots" den im ersten Schritt erstellten Bot aus.

    In das Feld Ausgehende URL wird nun der Wert des Internals <b>OUTDEF</b> des erstellten SSChatBot Devices hineinkopiert. <br>
    Zum Beispiel könnte der String so aussehen: <br><br>
  
    <ul>
      http://myserver.mydom:8086/sschat/outchat?botname=SynChatBot&fwcsrf=5de17731
    </ul>
    <br>
  
    (siehe dazu auch den <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#Aktivierung_ausgehende_Nachrichten_.28Chat_-.3E_FHEM.29">Wiki-Abschnitt</a> ) <br>
    
    <br><br>
    <b>Allgemeine Information zum Nachrichtenversand </b> <br>
    Nachrichten, die FHEM an den Chat Server sendet (eingehende Nachrichten), werden in FHEM zunächst in eine Queue gestellt. 
    Der Sendeprozess wird sofort gestartet. War die Übermittlung erfolgreich, wird die Nachricht aus der Queue gelöscht. 
    Anderenfalls verbleibt sie in der Queue und der Sendeprozess wird, in einem von der Anzahl der Fehlversuche abhängigen 
    Zeitintervall, erneut gestartet. <br>
    Mit dem Set-Befehl <b>restartSendqueue</b> kann die Abarbeitung der Queue manuell angestartet werden 
    (zum Beispiel nach einer Synology Wartung). 
    
    <br><br>

    <b>Allgemeine Information zum Nachrichtempfang </b> <br>
    Um Befehle vom Chat Server an FHEM zu senden, werden Slash-Befehle (/) verwendet. Sie sind vor der Verwendung im Synology 
    Chat und ggf. zusätzlich im SSChatBot Device (User spezifische Befehle) zu konfigurieren. <br><br>

    Folgende Befehlsformen werden unterstützt: <br><br>
    <ul> 
      <li> /set </li>
      <li> /get </li>
      <li> /code </li>
      <li> /&lt;User spezifischer Befehl&gt; (siehe Attribut <a href="#ownCommandx">ownCommandx</a>) </li>
    </ul>
    <br>
    
    Weitere ausfühliche Informationen zur Konfiguration des Nachrichtenempfangs sind im entsprechenden 
    <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#FHEM-Befehle_aus_dem_Chat_an_FHEM_senden">Wiki-Abschnitt</a> enthalten.

  </ul>
  <br><br> 

  <a name="SSChatBotSet"></a>
  <b>Set </b>
  <br><br>
  <ul>

    <ul>
      <a name="asyncSendItem"></a>
      <li><b> asyncSendItem &lt;Item&gt; </b> <br>
  
      Sendet eine Nachricht an einen oder mehrere Chatempfänger. <br>      
      Für weitere Informationen zu den verfügbaren Optionen für asyncSendItem, insbesondere zur Benutzung von interaktiven
      Objekten (Schaltflächen), konsultieren sie bitte diesen  
      <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers#verschiedene_Arten_Nachrichten_an_Chatempf.C3.A4nger_senden">Wiki-Abschnitt</a>.
      <br><br>
      
      <ul>
        <b>Beispiele:</b> <br>        
        set &lt;Name&gt; asyncSendItem Erste zu postende Nachrichtenzeile.\n Sie können auch eine zweite Nachrichtenzeile haben. [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="Erste zu postende Nachrichtenzeile.\n Sie können auch eine zweite Nachrichtenzeile haben." [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="https://www.synology.com" [users="&lt;User&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="Überprüfen Sie dies!! &lt;https://www.synology.com|Click hier&gt; für Einzelheiten!" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="ein lustiges Bild" fileUrl="http://imgur.com/xxxxx" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="aktuelles Plotfile" svg="&lt;SVG-Device&gt;[,&lt;Zoom&gt;][,&lt;Offset&gt;]" [users="&lt;User1&gt;,&lt;User2&gt;"] <br>
        set &lt;Name&gt; asyncSendItem text="&lt;Mitteilungstext&gt;" attachments="[{
                                            "callback_id": "&lt;Text für Reading recCallbackId&gt;", "text": "&lt;Überschrift des Buttons&gt;", 
                                            "actions":[{"type": "button", "name": "&lt;Text&gt;", "value": "&lt;Wert&gt;", "text": "&lt;Text&gt;", "style": "&lt;Farbe&gt;"}] }]" <br>
      </ul>
  
      </li><br>
    </ul>
   
    <ul>
      <a name="botToken"></a>
      <li><b> botToken &lt;Token&gt; </b> <br>
  
      Seichert den Token für den Zugriff auf den Chat als Bot.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="listSendqueue"></a>
      <li><b> listSendqueue </b> <br>
  
      Zeigt die noch an den Chat zu übertragenden Nachrichten. <br>
      Alle zu sendenden Nachrichten werden zunächst in einer Queue gespeichert und asynchron zum Chatserver übertragen.
  
      </li><br>
    </ul>
   
    <ul>
      <a name="purgeSendqueue"></a>
      <li><b> purgeSendqueue  &lt;-all- | -permError- | index&gt; </b> <br>
  
      Löscht Einträge aus der Sendequeue. <br><br>
      
      <ul>
        <li><b> -all- :</b>       Löscht alle Einträge der Sendqueue. </li>
        <li><b> -permError- :</b> Löscht alle Einträge der Sendqueue mit "permanent Error" Status. </li>
        <li><b> index : </b>      Löscht ausgewählten Eintrag mit "index". <br>
                                  Die Einträge in der Sendqueue kann man sich vorher mit "set listSendqueue" ansehen um den gewünschten Index zu finden. </li>
      </ul>
    
      </li><br>
    </ul>
    
    <ul>
      <a name="restartSendqueue"></a>
      <li><b> restartSendqueue [force] </b> <br>
  
      Startet die Abarbeitung der Sendequeue manuell neu. <br>
      Eventuell in der Sendequeue vorhandene Einträge mit der Kennzeichnung <b>forbidSend</b> werden nicht erneut versendet. <br>
      Erfolgt der Aufruf mit der Option <b>force</b>, werden auch Einträge mit der Kennzeichnung forbidSend berücksichtigt.
  
      </li><br>
    </ul>
   
  </ul>
  
  <a name="SSChatBotGet"></a>
  <b>Get </b>
  <br><br>
  <ul>
    
    <ul>
      <a name="chatChannellist"></a>
      <li><b> chatChannellist </b> <br>
  
      Erstellt eine Liste der für den Bot sichtbaren Channels.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="chatUserlist"></a>
      <li><b> chatUserlist </b> <br>
  
      Erstellt eine Liste der für den Bot sichtbaren Usern. <br>
      Sollten keine User gelistet werden, muss den Usern auf der Synology die Berechtigung für die Chat-Anwendung 
      zugewiesen werden.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="storedToken"></a>
      <li><b> storedToken </b> <br>
  
      Zeigt den gespeicherten Token an.
  
      </li><br>
    </ul>
    
    <ul>
      <a name="versionNotes"></a>
      <li><b> versionNotes </b> <br>
  
      Listet wesentliche Änderungen in der Versionshistorie des Moduls auf.
  
      </li><br>
    </ul>
   
  </ul>
  
  <a name="SSChatBotAttr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
  
    <ul>  
      <a name="allowedUserForCode"></a>
      <li><b>allowedUserForCode</b> <br> 
  
        Benennt die Chat-User, die Perl-Code in FHEM auslösen dürfen wenn der Slash-Befehl /code empfangen wurde. <br>
        (default: alle User erlaubt)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="allowedUserForGet"></a>
      <li><b>allowedUserForGet</b> <br> 
  
        Benennt die Chat-User, die Get-Kommandos in FHEM auslösen dürfen wenn der Slash-Befehl /get empfangen wurde. <br>
        (default: alle User erlaubt)
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="allowedUserForOwn"></a>
      <li><b>allowedUserForOwn</b> <br> 
  
        Benennt die Chat-User, die die im Attribut "ownCommand" definierte Kommandos in FHEM auslösen dürfen. <br>
        (default: alle User erlaubt)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="allowedUserForSet"></a>
      <li><b>allowedUserForSet</b> <br> 
  
        Benennt die Chat-User, die Set-Kommandos in FHEM auslösen dürfen wenn der Slash-Befehl /set empfangen wurde. <br>
        (default: alle User erlaubt)
    
      </li><br>
    </ul>
  
    <ul>  
      <a name="defaultPeer"></a>
      <li><b>defaultPeer</b> <br> 
  
        Ein oder mehrere (default) Empfänger für Nachrichten. Kann mit dem <b>users=</b> Tag im Befehl <b>asyncSendItem</b> 
        übersteuert werden.
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="httptimeout"></a>
      <li><b>httptimeout &lt;Sekunden&gt; </b> <br> 
  
        Stellt den Verbindungstimeout zum Chatserver ein. <br>
        (default 20 Sekunden)
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="ownCommandx"></a>
      <li><b>ownCommandx &lt;Slash-Befehl&gt; &lt;Kommando&gt; </b> <br> 
  
        Definiert ein &lt;Slash-Befehl&gt; &lt;Kommando&gt; Paar. Der Slash-Befehl und das Kommando sind durch ein 
        Leerzeichen zu trennen. <br>
        Das Kommando wird ausgeführt wenn der SSChatBot den Slash-Befehl empfängt. 
        Das Kommando kann ein FHEM Befehl oder Perl-Code sein. Perl-Code ist in <b>{ }</b> einzuschließen. <br><br>

        <ul>
        <b>Beispiele:</b> <br> 
          attr &lt;Name&gt; ownCommand1 /Wozi_Temp {ReadingsVal("eg.wz.wandthermostat","measured-temp",0)} <br>       
          attr &lt;Name&gt; ownCommand2 /Wetter get MyWetter wind_speed <br>
        </ul>       
    
      </li><br>
    </ul>
    
    <ul>  
      <a name="showTokenInLog"></a>
      <li><b>showTokenInLog</b> <br> 
  
        Wenn gesetzt, wird im Log mit verbose 4/5 der übermittelte Bot-Token angezeigt. <br>
        (default: 0)
    
      </li><br>
    </ul>
 
  </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 50_SSChatBot.pm
{
  "abstract": "Integration of Synology Chat Server into FHEM.",
  "x_lang": {
    "de": {
      "abstract": "Integration des Synology Chat Servers in FHEM."
    }
  },
  "keywords": [
    "synology",
    "synologychat",
    "chatbot",
    "chat",
    "messenger"
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
        "JSON": 0,
        "Data::Dumper": 0,
        "MIME::Base64": 0,
        "Time::HiRes": 0,
        "HttpUtils": 0,
        "Encode": 0,
        "Net::Domain": 0        
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
      "web": "https://wiki.fhem.de/wiki/SSChatBot - Integration des Synology Chat Servers",
      "title": "SSChatBot - Integration des Synology Chat Servers"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/50_SSChatBot.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/50_SSChatBot.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
