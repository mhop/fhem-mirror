########################################################################################################################
# $Id: $
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

package main;

use strict;                           
use warnings;
eval "use JSON;1;" or my $SSChatBotMM = "JSON";                   # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use MIME::Base64;
use Time::HiRes;
use HttpUtils;                                                    
use Encode;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;
eval "use Net::Domain qw(hostname hostfqdn hostdomain domainname);1"  or my $SSChatBotNDom = "Net::Domain";
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Versions History intern
our %SSChatBot_vNotesIntern = (
  "1.2.2"  => "07.02.2020  add new permanent error 410 'message too long' ",
  "1.2.1"  => "27.01.2020  replace \" H\" with \"%20H\" in payload due to problem in HttpUtils ",
  "1.2.0"  => "04.01.2020  check that Botname with type SSChatBot does exist and write Log if not ",
  "1.1.0"  => "27.12.2019  both POST- and GET-method are now valid in CGI ",
  "1.0.1"  => "11.12.2019  check OPIDX in parse sendItem, change error code list, complete forbidSend with error text ",
  "1.0.0"  => "29.11.2019  initial "
);

# Versions History extern
our %SSChatBot_vNotesExtern = (
  "1.0.1"  => "11.12.2019 check OPIDX in parse sendItem, change error code list, complete forbidSend with error text ",
  "1.0.0"  => "08.12.2019 initial "
);

my %SSChatBot_errlist = (
  100 => "Unknown error",
  101 => "Payload is empty",
  102 => "API does not exist - may be the Synology Chat Server package is stopped",
  117 => "illegal file name or path",
  120 => "payload has wrong format",
  404 => "bot is not legal - may be the bot is not active or the botToken is wrong",
  407 => "record not valid",
  409 => "exceed max file size",
  410 => "message too long",
  800 => "malformed or unsupported URL",
  805 => "empty API data received - may be the Synology Chat Server package is stopped",
  806 => "couldn't get Synology Chat API informations",
  810 => "The botToken couldn't be retrieved",
  900 => "malformed JSON string received from Synology Chat Server",
);

# Standardvariablen und Forward-Deklaration                                          
use vars qw(%SSChatBot_vHintsExt_en);
use vars qw(%SSChatBot_vHintsExt_de);

################################################################
sub SSChatBot_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}             = "SSChatBot_Define";
 $hash->{UndefFn}           = "SSChatBot_Undef";
 $hash->{DeleteFn}          = "SSChatBot_Delete"; 
 $hash->{SetFn}             = "SSChatBot_Set";
 $hash->{GetFn}             = "SSChatBot_Get";
 $hash->{AttrFn}            = "SSChatBot_Attr";
 $hash->{DelayedShutdownFn} = "SSChatBot_DelayedShutdown";
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
         
 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
# define SynChatBot SSChatBot 192.168.2.10 [5000] [HTTP(S)] 
#         ($hash)     [1]         [2]        [3]      [4]  
#
################################################################
sub SSChatBot_Define($@) {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SSChatBotMM." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SSChatBotMM);
 return "Error: Perl module ".$SSChatBotNDom." is missing." if($SSChatBotNDom);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
      return "You need to specify more parameters.\n". "Format: define <name> SSChatBot <ServerAddress> [Port] [HTTP(S)]";
  }
        
  my $inaddr = $a[2];
  my $inport = $a[3] ? $a[3] : 5000;
  my $inprot = $a[4] ? lc($a[4]) : "http";
  
  $hash->{INADDR}                = $inaddr;
  $hash->{INPORT}                = $inport;
  $hash->{MODEL}                 = "ChatBot"; 
  $hash->{INPROT}                = $inprot;
  $hash->{RESEND}                = "next planned SendQueue start: immediately by next entry";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  $hash->{HELPER}{USERFETCHED}   = 0;                                            # Chat User sind noch nicht abgerufen
  
  CommandAttr(undef,"$name room Chat");
  
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}       = "SYNO.API.Info";                              # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{CHATEXTERNAL}  = "SYNO.Chat.External"; 
    
  # Versionsinformationen setzen
  SSChatBot_setVersionInfo($hash);
  
  # Token lesen
  SSChatBot_getToken($hash,1,"botToken");
  
  # Index der Sendequeue initialisieren
  $data{SSChatBot}{$name}{sendqueue}{index} = 0;
    
  readingsBeginUpdate         ($hash);                                             
  readingsBulkUpdateIfChanged ($hash, "QueueLenth", 0);                          # Länge Sendqueue initialisieren  
  readingsBulkUpdate          ($hash, "state", "Initialized");                   # Init state
  readingsEndUpdate           ($hash,1);              

  # initiale Routinen nach Start ausführen , verzögerter zufälliger Start
  SSChatBot_initonboot($hash);

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
sub SSChatBot_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  delete $data{SSChatBot}{$name};
  SSChatBot_removeExtension($hash->{HELPER}{INFIX});
  RemoveInternalTimer($hash);
   
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub SSChatBot_DelayedShutdown($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

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
sub SSChatBot_Delete($$) {
  my ($hash, $arg) = @_;
  my $name  = $hash->{NAME};
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_botToken";
  
  # gespeicherte Credentials löschen
  setKeyValue($index, undef);
    
return undef;
}

################################################################
sub SSChatBot_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val,$cache);
      
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
            InternalTimer(gettimeofday()+2, "SSChatBot_initonboot", $hash, 0) if($init_done); 
		}
    
        readingsBeginUpdate($hash); 
        readingsBulkUpdate ($hash, "state", $val);                    
        readingsEndUpdate  ($hash,1); 
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout/) {
            unless ($aVal =~ /^\d+$/) { return "The Value for $aName is not valid. Use only figures 1-9 !";}
        }     

        if ($aName =~ m/ownCommand([1-9][0-9]*)$/) {
            my $num = $1;
			return "The value of $aName must start with a slash like \"/Weather \"." unless ($aVal =~ /^\/.*$/);
			addToDevAttrList($name, "ownCommand".($num+1));                        # add neue ownCommand dynamisch
        }        
    }
    
return undef;
}

################################################################
sub SSChatBot_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my $prop2   = $a[4];
  my $prop3   = $a[5];
  my ($success,$setlist);
        
  return if(IsDisabled($name));
  
  my $idxlist = join(",", SSChatBot_sortVersion("asc",keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}));
 
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
                 "restartSendqueue:noArg ".
                 "sendItem:textField-long "
                 ;
  }
 
  if ($opt eq "botToken") {
      return "The command \"$opt\" needs an argument." if (!$prop);         
      ($success) = SSChatBot_setToken($hash,$prop,"botToken");
	  
	  if($success) {
          CommandGet(undef, "$name chatUserlist");                      # Chatuser Liste abrufen
		  return "botToken saved successfully";
	  } else {
          return "Error while saving botToken - see logfile for details";
	  }
      
  } elsif ($opt eq "listSendqueue") {
      my $sub = sub ($) { 
          my ($idx) = @_;
          my $ret;          
          foreach my $key (reverse sort keys %{$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}}) {
              $ret .= ", " if($ret);
              $ret .= $key."=>".$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{$key};
          }
          return $ret;
      };
	    
      if (!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
          return "SendQueue is empty.";
      }
      my $sq;
	  foreach my $idx (sort{$a<=>$b} keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
          $sq .= $idx." => ".$sub->($idx)."\n"; 			
      }
	  return $sq;
  
  } elsif ($opt eq "purgeSendqueue") {
      if($prop eq "-all-") {
          delete $hash->{OPIDX};
          delete $data{SSChatBot}{$name}{sendqueue}{entries};
          $data{SSChatBot}{$name}{sendqueue}{index} = 0;
          return "All entries of SendQueue are deleted";
      } elsif($prop eq "-permError-") {
	      foreach my $idx (keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) { 
              delete $data{SSChatBot}{$name}{sendqueue}{entries}{$idx} 
                  if($data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend}); 			
          }
          return "All entries with state \"permanent send error\" are deleted";
      } else {
          delete $data{SSChatBot}{$name}{sendqueue}{entries}{$prop};
          return "SendQueue entry with index \"$prop\" deleted";
      }
  
  } elsif ($opt eq "sendItem") {
      # einfachster Sendetext users="user1"
      # text="First line of message to post.\nAlso you can have a second line of message." users="user1"
      # text="<https://www.synology.com>" users="user1"
      # text="Check this!! <https://www.synology.com|Click here> for details!" users="user1,user2" 
      # text="a fun image" fileUrl="http://imgur.com/xxxxx" users="user1,user2"  
      return undef if(!$hash->{HELPER}{USERFETCHED});
      my $cmd = join(" ", @a);
      my ($text,$users);
      my $fileUrl = "";
      my ($a,$h)  = parseParams($cmd);
      if($h) {
          $text    = $h->{text}    if(defined $h->{text});
          $users   = $h->{users}   if(defined $h->{users});
          $fileUrl = $h->{fileUrl} if(defined $h->{fileUrl});
      }
      
      if($a) {
          my @t = @{$a};
          shift @t; shift @t;
          $text = join(" ", @t) if(!$text);
      }      
       
      return "Your sendstring is incorrect. It must contain at least text with the \"text=\" tag like text=\"...\"\nor only some text like \"this is a test\" without the \"text=\" tag." if(!$text);
      
      $text = SSChatBot_formText($text);
      
      $users = AttrVal($name,"defaultPeer", "") if(!$users);
      return "You haven't defined any receptor for send the message to. ".
             "You have to use the \"users\" tag or define default receptors with attribute \"defaultPeer\"." if(!$users);
      
      # User aufsplitten und zu jedem die ID ermitteln
      my @ua = split(/,/, $users);
      foreach (@ua) {
          next if(!$_);
          my $uid = $hash->{HELPER}{USERS}{$_}{id};
          return "The receptor \"$_\" seems to be unknown because its ID coulnd't be found." if(!$uid);
           
          # Eintrag zur SendQueue hinzufügen
          # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
          SSChatBot_addQueue($name, "sendItem", "chatbot", $uid, $text, $fileUrl, "", "");
      }
       
      SSChatBot_getapisites($name);
  
  } elsif ($opt eq "restartSendqueue") {
      my $ret = SSChatBot_getapisites($name);
      if($ret) {
          return $ret;
      } else {
          return "The SendQueue has been restarted.";
      }
      
  } else {
      return "$setlist"; 
  }
  
return;
}

################################################################
sub SSChatBot_Get($@) {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
	my $arg = shift @a;
	my $arg1 = shift @a;
	my $arg2 = shift @a;
	my $ret = "";
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
              
    if ($opt eq "storedToken") {
	    if (!$hash->{TOKEN}) {return "Token of $name is not set - make sure you've set it with \"set $name botToken <TOKEN>\"";}
        # Token abrufen
        my ($success, $token) = SSChatBot_getToken($hash,0,"botToken");
        unless ($success) {return "Token couldn't be retrieved successfully - see logfile"};
        
        return "Stored Token to act as Synology Chat Bot:\n".
               "=========================================\n".
               "$token \n"
               ;   
    
	} elsif ($opt eq "chatUserlist") {
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSChatBot_getclhash($hash,1);
        
        # Eintrag zur SendQueue hinzufügen
        # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
        SSChatBot_addQueue($name, "chatUserlist", "user_list", "", "", "", "", "");
        
        SSChatBot_getapisites($name);
    
    } elsif ($opt eq "chatChannellist") {
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSChatBot_getclhash($hash,1);
        
        # Eintrag zur SendQueue hinzufügen
        # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
        SSChatBot_addQueue($name, "chatChannellist", "channel_list", "", "", "", "", "");
        
        SSChatBot_getapisites($name);
    
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
                      $hs{$_} = $SSChatBot_vHintsExt_de{$_};
                  } else {
                      $hs{$_} = $SSChatBot_vHintsExt_en{$_};
                  }
              }                      
          } else {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = %SSChatBot_vHintsExt_de;
              } else {
                  %hs = %SSChatBot_vHintsExt_en; 
              }
          }          
          $i = 0;
          foreach my $key (SSChatBot_sortVersion("desc",keys %hs)) {
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
          foreach my $key (SSChatBot_sortVersion("desc",keys %SSChatBot_vNotesExtern)) {
              ($val0,$val1) = split(/\s/,$SSChatBot_vNotesExtern{$key},2);
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
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub SSChatBot_initonboot ($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my ($ret,$csrf,$fuuid);
  
  RemoveInternalTimer($hash, "SSChatBot_initonboot");
  
  if ($init_done) {
      # check ob FHEMWEB Instanz für SSChatBot angelegt ist -> sonst anlegen
      my @FWports;
      my $FWname = "sschat";                                        # der Pfad nach http://hostname:port/ der neuen FHEMWEB Instanz -> http://hostname:port/sschat
      my $FW     = "WEBSSChatBot";                                  # Name der FHEMWEB Instanz für SSChatBot
      foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
          $hash->{FW} = $_ if ( AttrVal( $_, "webname", "fhem" ) eq $FWname );
          push @FWports, $defs{$_}{PORT};
      }

      if (!defined($hash->{FW})) {                                          # FHEMWEB für SSChatBot ist noch nicht angelegt
          my $room = AttrVal($name, "room", "Chat");
          my $port = 8082;
          
          while (grep(/^$port$/ , @FWports)) {                              # den ersten freien FHEMWEB-Port ab 8082 finden
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
		  chop($fqdn) if($fqdn =~ /^.*\.$/);                            # eventuellen "." nach dem FQDN entfernen
		  my $FWchatport  = $defs{$FW}{PORT};
		  my $FWprot      = AttrVal($FW, "HTTPS", 0);
		  $FWname         = AttrVal($FW, "webname", 0);
          CommandAttr(undef, "$FW csrfToken none") if(!AttrVal($FW, "csrfToken", ""));
          $csrf           = $defs{$FW}{CSRFTOKEN}?$defs{$FW}{CSRFTOKEN}:"";
     
          $hash->{OUTDEF} = ($FWprot?"https":"http")."://".($fqdn?$fqdn:$host).":".$FWchatport."/".$FWname."/outchat?botname=".$name."&fwcsrf=".$csrf; 

		  SSChatBot_addExtension($name, "SSChatBot_CGI", "outchat");
		  $hash->{HELPER}{INFIX} = "outchat"; 
	  }
			  
  } else {
      InternalTimer(gettimeofday()+3, "SSChatBot_initonboot", $hash, 0);
  }
  
return;
}

######################################################################################
#                            Eintrag zur SendQueue hinzufügen
######################################################################################
sub SSChatBot_addQueue ($$$$$$$$) {
    my ($name,$opmode,$method,$userid,$text,$fileUrl,$channel,$attachment) = @_;
    my $hash                = $defs{$name};
    
    if(!$text && $opmode !~ /chatUserlist|chatChannellist/) {
        Log3($name, 2, "$name - ERROR - can't add message to queue: \"text\" is empty");
        
        readingsBeginUpdate         ($hash);
        readingsBulkUpdateIfChanged ($hash,"Errorcode", "none");
        readingsBulkUpdateIfChanged ($hash,"Error",     "can't add message to queue: \"text\" is empty");
        readingsBulkUpdate          ($hash,"state",     "Error");
        readingsEndUpdate           ($hash, 1);       

        return;        
    }
   
   $data{SSChatBot}{$name}{sendqueue}{index}++;
   my $index = $data{SSChatBot}{$name}{sendqueue}{index};
   
   Log3($name, 5, "$name - Add sendItem to queue - Idx: $index, Opmode: $opmode, Text: $text, fileUrl: $fileUrl, userid: $userid");
   
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

   SSChatBot_updQLength ($hash);                        # updaten Länge der Sendequeue     
   
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
sub SSChatBot_checkretry ($$) {  
  my ($name,$retry) = @_;
  my $hash          = $defs{$name};  
  my $idx           = $hash->{OPIDX};
  my $forbidSend    = "";
  
  if(!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
      Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
      SSChatBot_updQLength ($hash);
      return;  
  } 
  
  if(!$retry) {                                                     # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{SSChatBot}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, "$name - Opmode \"$hash->{OPMODE}\" finished successfully, Sendqueue index \"$idx\" deleted.");
      SSChatBot_updQLength ($hash);
      return SSChatBot_getapisites($name);                          # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer)
  
  } else {                                                          # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount};
  
      my $errorcode = ReadingsVal($name, "Errorcode", 0);
      if($errorcode =~ /100|101|117|120|407|409|410|800|900/) {     # bei diesen Errorcodes den Queueeintrag nicht wiederholen, da dauerhafter Fehler !
          $forbidSend = SSChatBot_experror($hash,$errorcode);       # Fehlertext zum Errorcode ermitteln
          $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend} = $forbidSend;
          
          Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" SendQueue index \"$idx\" not executed. It seems to be a permanent error. Exclude it from new send attempt !");
          
          delete $hash->{OPIDX};
          delete $hash->{OPMODE};
          
          SSChatBot_updQLength ($hash);                             # updaten Länge der Sendequeue
          
          return SSChatBot_getapisites($name);                      # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer);
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
          
          my $rst = gettimeofday()+$rs;                        # resend Timer 
          SSChatBot_updQLength ($hash,$rst);                   # updaten Länge der Sendequeue mit resend Timer
          
          RemoveInternalTimer($hash, "SSChatBot_getapisites");
          InternalTimer($rst, "SSChatBot_getapisites", "$name", 0);
      }
  }

return
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub SSChatBot_getapisites($) {
   my ($name)       = @_;
   my $hash         = $defs{$name};
   my $inaddr       = $hash->{INADDR};
   my $inport       = $hash->{INPORT};
   my $inprot       = $hash->{INPROT}; 
   my $apiinfo      = $hash->{HELPER}{APIINFO};                # Info-Seite für alle API's, einzige statische Seite ! 
   my $chatexternal = $hash->{HELPER}{CHATEXTERNAL};   
   my ($url,$param,$idxset,$ret);
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###            start Chat operation Send            "); 
   Log3($name, 4, "$name - ####################################################");

   if(!keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
       $ret = "Sendqueue is empty. Nothing to do ...";
       Log3($name, 4, "$name - $ret"); 
       return $ret;  
   }
   
   # den nächsten Eintrag aus "SendQueue" selektieren und ausführen wenn nicht forbidSend gesetzt ist
   foreach my $idx (sort{$a<=>$b} keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) {
       if (!$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{forbidSend}) {
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
   
   if ($hash->{HELPER}{APIPARSET}) {                     # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
	   Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       return SSChatBot_chatop($name);
   }

   my $httptimeout = AttrVal($name,"httptimeout",20);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout: $httptimeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "$inprot://$inaddr:$inport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$chatexternal";

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSChatBot_getapisites_parse
            };
   HttpUtils_NonblockingGet ($param);  

return;
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub SSChatBot_getapisites_parse ($) {
   my ($param, $err, $myjson) = @_;
   my $hash         = $param->{hash};
   my $name         = $hash->{NAME};
   my $inaddr       = $hash->{INADDR};
   my $inport       = $hash->{INPORT};
   my $chatexternal = $hash->{HELPER}{CHATEXTERNAL};   

   my ($error,$errorcode,$chatexternalmaxver,$chatexternalpath);
  
    if ($err ne "") {
	    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - ERROR message: $err");
       
        readingsBeginUpdate         ($hash); 
        readingsBulkUpdateIfChanged ($hash, "Error",       $err);
        readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
        readingsBulkUpdate          ($hash, "state",    "Error");                    
        readingsEndUpdate           ($hash,1); 
        
        SSChatBot_checkretry($name,1);
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, my $success) = SSChatBot_evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            SSChatBot_checkretry($name,1);       
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my $logstr;
                        
          # Pfad und Maxversion von "SYNO.Chat.External" ermitteln
            my $chatexternalpath   = $data->{'data'}->{$chatexternal}->{'path'};
            $chatexternalpath      =~ tr/_//d if (defined($chatexternalpath));
            my $chatexternalmaxver = $data->{'data'}->{$chatexternal}->{'maxVersion'}; 
       
            $logstr = defined($chatexternalpath) ? "Path of $chatexternal selected: $chatexternalpath" : "Path of $chatexternal undefined - Synology Chat Server may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($chatexternalmaxver) ? "MaxVersion of $chatexternal selected: $chatexternalmaxver" : "MaxVersion of $chatexternal undefined - Synology Chat Server may be stopped";
            Log3($name, 4, "$name - $logstr");
			       
            # ermittelte Werte in $hash einfügen
            if(defined($chatexternalpath) && defined($chatexternalmaxver)) {
                $hash->{HELPER}{CHATEXTERNALPATH}   = $chatexternalpath;
                $hash->{HELPER}{CHATEXTERNALMAXVER} = $chatexternalmaxver;            
       
                readingsBeginUpdate         ($hash);
                readingsBulkUpdateIfChanged ($hash,"Errorcode","none");
                readingsBulkUpdateIfChanged ($hash,"Error",    "none");
                readingsEndUpdate           ($hash,1);
			
			    # Webhook Hash values sind gesetzt
			    $hash->{HELPER}{APIPARSET} = 1;
            
            } else {
                $errorcode = "805";
                $error = SSChatBot_experror($hash,$errorcode);                   # Fehlertext zum Errorcode ermitteln
			
                readingsBeginUpdate         ($hash);
                readingsBulkUpdateIfChanged ($hash,"Errorcode", $errorcode);
                readingsBulkUpdateIfChanged ($hash,"Error",     $error);
                readingsBulkUpdate          ($hash,"state",     "Error");
                readingsEndUpdate           ($hash, 1); 
 
                SSChatBot_checkretry($name,1);  
                return;                
            }
                        
        } else {
            $errorcode = "806";
            $error     = SSChatBot_experror($hash,$errorcode);                  # Fehlertext zum Errorcode ermitteln
            
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash, "Error",     $error);
            readingsBulkUpdate          ($hash,"state",      "Error");
            readingsEndUpdate           ($hash, 1);

            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
            
            SSChatBot_checkretry($name,1);    
            return;
        }
	}
    
return SSChatBot_chatop($name);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub SSChatBot_chatop ($) {  
   my ($name) = @_;
   my $hash               = $defs{$name};
   my $inprot             = $hash->{INPROT};
   my $inaddr             = $hash->{INADDR};
   my $inport             = $hash->{INPORT};
   my $chatexternal       = $hash->{HELPER}{CHATEXTERNAL}; 
   my $chatexternalpath   = $hash->{HELPER}{CHATEXTERNALPATH};
   my $chatexternalmaxver = $hash->{HELPER}{CHATEXTERNALMAXVER};
   my ($url,$httptimeout,$param,$error,$errorcode);
   
   # Token abrufen
   my ($success, $token) = SSChatBot_getToken($hash,0,"botToken");
   unless ($success) {
       $errorcode = "810";
       $error     = SSChatBot_experror($hash,$errorcode);                  # Fehlertext zum Errorcode ermitteln
       
       readingsBeginUpdate         ($hash);
       readingsBulkUpdateIfChanged ($hash, "Errorcode",  $errorcode);
       readingsBulkUpdateIfChanged ($hash, "Error",      $error);
       readingsBulkUpdate          ($hash,"state",      "Error");
       readingsEndUpdate           ($hash, 1);

       Log3($name, 2, "$name - ERROR - $error"); 
       
       SSChatBot_checkretry($name,1);
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

   if ($opmode =~ /^chatUserlist$|^chatChannellist$/) {
      $url = "$inprot://$inaddr:$inport/webapi/$chatexternalpath?api=$chatexternal&version=$chatexternalmaxver&method=$method&token=\"$token\"";
   }
   
   if ($opmode eq "sendItem") {
      # Form: payload={"text": "a fun image", "file_url": "http://imgur.com/xxxxx" "user_ids": [5]} 
      #       payload={"text": "First line of message to post in the channel" "user_ids": [5]}
      #       payload={"text": "Check this!! <https://www.synology.com|Click here> for details!" "user_ids": [5]}
      
      $url  = "$inprot://$inaddr:$inport/webapi/$chatexternalpath?api=$chatexternal&version=$chatexternalmaxver&method=$method&token=\"$token\"";
      $url .= "&payload={";
      $url .= "\"text\": \"$text\","        if($text);
      $url .= "\"file_url\": \"$fileUrl\"," if($fileUrl);
      $url .= "\"user_ids\": [$userid]"     if($userid);
      $url .= "}";
   }

   my $part = $url;
   if(AttrVal($name, "showTokenInLog", "0") == 1) {
       Log3($name, 4, "$name - Call-Out: $url");
   } else {
       $part =~ s/$token/<secret>/;
       Log3($name, 4, "$name - Call-Out: $part");
   }
   
   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&SSChatBot_chatop_parse
            };
   
   HttpUtils_NonblockingGet ($param);   
} 
  
#############################################################################################
#                                Callback from SSChatBot_chatop
#############################################################################################
sub SSChatBot_chatop_parse ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash   = $param->{hash};
   my $name   = $hash->{NAME};
   my $inprot = $hash->{INPROT};
   my $inaddr = $hash->{INADDR};
   my $inport = $hash->{INPORT};
   my $opmode = $hash->{OPMODE};
   my ($rectime,$data,$success,$error,$errorcode,$cherror);
   
   my $lang = AttrVal("global","language","EN");
   
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

        SSChatBot_checkretry($name,1);        
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden 
        ($hash,$success,$myjson) = SSChatBot_evaljson($hash,$myjson);        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            SSChatBot_checkretry($name,1);       
            return;
        }
        
        $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};

        if ($success) {       

            if ($opmode eq "chatUserlist") {    
                my %users = ();   
                my ($un,$ui,$st,$nn,$em,$uids);           
				my $i    = 0;
                
                my $out  = "<html>";
                $out    .= "<b>Synology Chat Server visible Users</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>Username</b> </td><td> <b>ID</b> </td><td> <b>state</b> </td><td> <b>Nickname</b> </td><td> <b>Email</b> </td><td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
                
                while ($data->{'data'}->{'users'}->[$i]) {
                    my $deleted = SSChatBot_jboolmap($data->{'data'}->{'users'}->[$i]->{'deleted'});
                    my $isdis   = SSChatBot_jboolmap($data->{'data'}->{'users'}->[$i]->{'is_disabled'});
                    if($deleted ne "true" && $isdis ne "true") {
                        $un = $data->{'data'}->{'users'}->[$i]->{'username'};
                        $ui = $data->{'data'}->{'users'}->[$i]->{'user_id'};
                        $st = $data->{'data'}->{'users'}->[$i]->{'status'};
                        $nn = $data->{'data'}->{'users'}->[$i]->{'nickname'};
                        $em = $data->{'data'}->{'users'}->[$i]->{'user_props'}->{'email'};
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
                foreach (@deva) {
                     push @newa, $_ if($_ !~ /defaultPeer:|allowedUserFor(Set|Get|Code|Own):/);
                }
                push @newa, ($uids?"defaultPeer:multiple-strict,$uids ":"defaultPeer:--no#userlist#selectable--");
                push @newa, ($uids?"allowedUserForSet:multiple-strict,$uids ":"allowedUserForSet:--no#userlist#selectable--");
                push @newa, ($uids?"allowedUserForGet:multiple-strict,$uids ":"allowedUserForGet:--no#userlist#selectable--");
                push @newa, ($uids?"allowedUserForCode:multiple-strict,$uids ":"allowedUserForCode:--no#userlist#selectable--");
                push @newa, ($uids?"allowedUserForOwn:multiple-strict,$uids ":"allowedUserForOwn:--no#userlist#selectable--");
                
                $hash->{".AttrList"} = join(" ", @newa);              # Device spezifische AttrList, überschreibt Modul AttrList !      
               
                $out .= "</table>";
                $out .= "</html>";

				# Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$out");
				delete($hash->{HELPER}{CL});                
			
            } elsif ($opmode eq "chatChannellist") {    
                my %channels = ();   
                my ($cn,$ci,$cr,$mb,$ty,$cids);             
				my $i    = 0;
                
                my $out  = "<html>";
                $out    .= "<b>Synology Chat Server visible Channels</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>Channelname</b> </td><td> <b>ID</b> </td><td> <b>Creator</b> </td><td> <b>Members</b> </td><td> <b>Type</b> </td><td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
                
                while ($data->{'data'}->{'channels'}->[$i]) {
                    my $cn = SSChatBot_jboolmap($data->{'data'}->{'channels'}->[$i]->{'name'});
                    if($cn) {
                        $ci = $data->{'data'}->{'channels'}->[$i]->{'channel_id'};
                        $cr = $data->{'data'}->{'channels'}->[$i]->{'creator_id'};
                        $mb = $data->{'data'}->{'channels'}->[$i]->{'members'};
                        $ty = $data->{'data'}->{'channels'}->[$i]->{'type'};
                        $channels{$cn}{id}       = $ci;
                        $channels{$cn}{creator}  = $cr;
                        $channels{$cn}{members}  = $mb;
                        $channels{$cn}{type}     = $ty;
                        $cids                .= "," if($cids);
                        $cids                .= $cn;
                        $out                 .= "<tr><td> $cn </td><td> $ci </td><td> $cr </td><td>  $mb </td><td> $ty </td><td></tr>";
                    }
					$i++;
                }
                $hash->{HELPER}{CHANNELS} = \%channels if(%channels);
                
                $out .= "</table>";
                $out .= "</html>";  

				# Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$out");
				delete($hash->{HELPER}{CL});                
			
            } elsif ($opmode eq "sendItem" && $hash->{OPIDX}) {
                my $postid = "";
                my $idx    = $hash->{OPIDX};
                my $uid    = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{userid}; 
                if($data->{data}{succ}{user_id_post_map}{$uid}) {
                    $postid = $data->{data}{succ}{user_id_post_map}{$uid};   
                }                
                     
                readingsBeginUpdate ($hash);
                readingsBulkUpdate  ($hash, "sendPostId", $postid); 
                readingsBulkUpdate  ($hash, "sendUserId", $uid);                    
                readingsEndUpdate   ($hash,1); 
            }            

            SSChatBot_checkretry($name,0);

            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash, "Errorcode", "none");
            readingsBulkUpdateIfChanged ($hash, "Error",     "none");            
            readingsBulkUpdate          ($hash, "state",     "active");                    
            readingsEndUpdate           ($hash,1); 
           
        } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};
            $cherror   = $data->{'error'}->{'errors'};                       # vom Chat gelieferter Fehler
            $error     = SSChatBot_experror($hash,$errorcode);               # Fehlertext zum Errorcode ermitteln
            if ($error =~ /not found/) {
                $error .= " New error: ".($cherror?$cherror:"");
            }
			
            readingsBeginUpdate         ($hash);
            readingsBulkUpdateIfChanged ($hash,"Errorcode", $errorcode);
            readingsBulkUpdateIfChanged ($hash,"Error",     $error);
            readingsBulkUpdate          ($hash,"state",     "Error");
            readingsEndUpdate           ($hash, 1);
       
            Log3($name, 2, "$name - ERROR - Operation $opmode was not successful. Errorcode: $errorcode - $error");
            
            SSChatBot_checkretry($name,1);
        }
                
       undef $data;
       undef $myjson;
   }

return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
###############################################################################
sub SSChatBot_evaljson($$) { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  my ($error,$errorcode);
  
  eval {decode_json($myjson)} or do {
          $success = 0;
          
          $errorcode = "900";

          # Fehlertext zum Errorcode ermitteln
          $error = SSChatBot_experror($hash,$errorcode);
            
          readingsBeginUpdate         ($hash);
          readingsBulkUpdateIfChanged ($hash, "Errorcode", $errorcode);
          readingsBulkUpdateIfChanged ($hash, "Error",     $error);
          readingsEndUpdate           ($hash, 1);  
  };
  
return($hash,$success,$myjson);
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub SSChatBot_jboolmap($){ 
  my ($bool) = @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool?"true":"false";
  }
  
return $bool;
}


##############################################################################
#  Auflösung Errorcodes SVS API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSChatBot_experror ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSChatBot_errlist{"$errorcode"})) {
      $error = "Value of errorcode \"$errorcode\" not found."; 
      return ($error);
  }

  # Fehlertext aus Hash-Tabelle %errorlist ermitteln
  $error = $SSChatBot_errlist{"$errorcode"};
  
return ($error);
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub SSChatBot_sortVersion (@){
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
#                            botToken speichern
######################################################################################
sub SSChatBot_setToken ($$@) {
    my ($hash, $token, $ao) = @_;
    my $name           = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);   
    
    $credstr = encode_base64($token);
    
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
        Log3($name, 2, "$name - Error while saving Token - $retcode");
        $success = 0;
    } else {
        ($success, $token) = SSChatBot_getToken($hash,1,$ao);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
    }

return ($success);
}

######################################################################################
#                             botToken lesen
######################################################################################
sub SSChatBot_getToken ($$$) {
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
            $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) - $key[$i] + 256) % 256) }  
            split //, $credstr;   
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
sub SSChatBot_addExtension($$$) {
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
sub SSChatBot_removeExtension($) {
  my ($link) = @_;

  my $url  = "/$link";
  my $name = $data{FWEXT}{$url}{deviceName};
  
  my @chatdvs = devspec2array("TYPE=SSChatBot");
  foreach (@chatdvs) {                                 # /outchat erst deregistrieren wenn keine SSChat-Devices mehr vorhanden sind außer $name
      if($defs{$_} && $_ ne $name) {
          Log3($name, 2, "$name - Skip unregistering SSChatBot for URL $url");
          return;
      }
  }
  
  Log3($name, 2, "$name - Unregistering SSChatBot for URL $url...");
  delete $data{FWEXT}{$url};
  
return;
}

#############################################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
#############################################################################################
sub SSChatBot_trim ($) {
  my $str = shift;
  $str =~ s/^\s+|\s+$//g;

return ($str);
}

#############################################################################################
#                        Länge Senedequeue updaten          
#############################################################################################
sub SSChatBot_updQLength ($;$) {
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
#############################################################################################
sub SSChatBot_formText ($) {
  my $txt = shift;
  my (%replacements,$pat);
  
  %replacements = (
      '"'  => "´",                              # doppelte Hochkomma sind im Text nicht erlaubt
      " H" => "%20H",                           # Bug in HttpUtils(?) wenn vor großem H ein Zeichen + Leerzeichen vorangeht
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
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
#############################################################################################
sub SSChatBot_getclhash($;$$) {      
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

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SSChatBot_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (SSChatBot_sortVersion("desc",keys %SSChatBot_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SSChatBot}{META}}
	  if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 50_SSChatBot.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 50_SSChatBot.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
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

#############################################################################################
#                         Common Gateway Interface
#                   parsen von outgoing Messages Chat -> FHEM       
#############################################################################################
sub SSChatBot_CGI() {
  my ($request) = @_;
  my ($hash,$name,$link,$args);
  my ($text,$timestamp,$channelid,$channelname,$userid,$username,$postid,$triggerword) = ("","","","","","","","");
  my ($command,$cr,$au,$arg) = ("","","","");
  my @aul;
  my $state = "active";
  my $do    = 0;  
  my $ret   = "success";

  return ( "text/plain; charset=utf-8", "Booting up" ) unless ($init_done);

  # data received
  if ($request =~ /^\/outchat(\?|&).*/) {                   # POST- oder GET-Methode empfangen
      $args = (split(/outchat\?/, $request))[1];            # GET-Methode empfangen 
      if(!$args) {                                          # POST-Methode empfangen wenn keine GET_Methode ?
          $args = (split(/outchat&/, $request))[1];
          if(!$args) {
       	      Log 1, "TYPE SSChatBot - ERROR - no expected data received";
              return ("text/plain; charset=utf-8", "no expected data received");
          }
      }
	  $args =~ s/&/" /g;
	  $args =~ s/=/="/g;
	  $args .= "\"";
      
	  my($a,$h) = parseParams($args);
	  
      if (!defined($h->{botname})) {
	        Log 1, "TYPE SSChatBot - ERROR - no Botname received";
            return ("text/plain; charset=utf-8", "no FHEM SSChatBot name in message");
      }
	  
	  # check ob angegebenes SSChatBot Device definiert, wenn ja Kontext auf botname setzen
	  $name = $h->{botname};                                # das SSChatBot Device
	  unless (IsDevice($name, 'SSChatBot')) {
          Log 1, "ERROR - No SSChatBot device \"$name\" of Type \"SSChatBot\" exists";
          return ( "text/plain; charset=utf-8", "No SSChatBot device for webhook \"/outchat\" exists" );
      }
	  
      $hash = $defs{$name};                                 # hash des SSChatBot Devices
	  
      if (!defined($h->{token})) {
            Log3($name, 5, "$name - received insufficient data:\n".Dumper($args));
            return ("text/plain; charset=utf-8", "Insufficient data");
      }
      
      # CSRF Token check
      my $FWdev    = $hash->{FW};                           # das FHEMWEB Device für SSChatBot Device -> ist das empfangene Device
      my $FWhash   = $defs{$FWdev};
      my $want     = $FWhash->{CSRFTOKEN};
      $want        = $want?$want:"none";
      my $supplied = $h->{fwcsrf};
      if($want eq "none" || $want ne $supplied) {           # $FW_wname enthält ebenfalls das aufgerufenen FHEMWEB-Device
          Log3 ($FW_wname, 2, "$FW_wname - WARNING - FHEMWEB CSRF error for client \"$FWdev\": ".
                              "received $supplied token is not $want. ".
                              "For details see the csrfToken FHEMWEB attribute. ".
                              "The csrfToken must be identical to the token in OUTDEF of $name device.");
          return ("text/plain; charset=utf-8", "400 Bad Request");          
      }
	  
	  Log3($name, 4, "$name - ####################################################"); 
	  Log3($name, 4, "$name - ###          start Chat operation Receive           "); 
	  Log3($name, 4, "$name - ####################################################"); 
	  Log3($name, 5, "$name - data received:\n".Dumper($h));
      
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

	  if ($h->{channel_id}) {
	      $channelid = urlDecode($h->{channel_id});                           
          Log3($name, 4, "$name - channel_id received: ".$channelid);
      }	  
	  
	  if ($h->{channel_name}) {
	      $channelname = urlDecode($h->{channel_name});                           
          Log3($name, 4, "$name - channel_name received: ".$channelname);
      }
	  
	  if ($h->{user_id}) {
	      $userid = urlDecode($h->{user_id});                           
          Log3($name, 4, "$name - user_id received: ".$userid);
      }
	  
	  if ($h->{username}) {
	      $username = urlDecode($h->{username});                           
          Log3($name, 4, "$name - username received: ".$username);
      }
	  
	  if ($h->{post_id}) {
	      $postid = urlDecode($h->{post_id});                           
          Log3($name, 4, "$name - postid received: ".$postid);
      }
	  
	  if ($h->{timestamp}) {
          $timestamp = FmtDateTime(($h->{timestamp})/1000);
          Log3($name, 4, "$name - timestamp received: ".$timestamp);
	  }
	  
	  if ($h->{text}) {
	      $text = urlDecode($h->{text});                          
          Log3($name, 4, "$name - text received: ".$text);
   
          if($text =~ /^\/([Ss]et.*?|[Gg]et.*?|[Cc]ode.*?)\s+(.*)$/) {                # vordefinierte Befehle in FHEM ausführen
              my $p1 = $1;
              my $p2 = $2;
              
              if($p1 =~ /set.*/i) {
                  $command = "set ".$p2;
				  $do      = 1;
                  $au      = AttrVal($name,"allowedUserForSet", "all");
                  @aul     = split(",",$au);
                  if($au eq "all" || $username ~~ @aul) {
                      Log3($name, 4, "$name - Synology Chat user \"$username\" execute FHEM command: ".$command);
                      $cr = CommandSet(undef, $p2);                                   # set-Befehl in FHEM ausführen
                  } else {
                      $cr    = "User \"$username\" is not allowed execute \"$command\" command";
                      $state = "command execution denied";
                      Log3($name, 2, "$name - WARNING - Chat user \"$username\" is not authorized for \"$command\" command. Execution denied !");
                  }
                  
              } elsif ($p1 =~ /get.*/i) {
                  $command = "get ".$p2;      
                  $do      = 1;				  
                  $au      = AttrVal($name,"allowedUserForGet", "all");
                  @aul     = split(",",$au);
                  if($au eq "all" || $username ~~ @aul) {
                      Log3($name, 4, "$name - Synology Chat user \"$username\" execute FHEM command: ".$command);
                      $cr = CommandGet(undef, $p2);                                   # get-Befehl in FHEM ausführen  
                  } else {
                      $cr    = "User \"$username\" is not allowed execute \"$command\" command";
                      $state = "command execution denied";
                      Log3($name, 2, "$name - WARNING - Chat user \"$username\" is not authorized for \"$command\" command. Execution denied !");
                  }
                  
              } elsif ($p1 =~ /code.*/i) {
                  $command = $p2;
				  $do      = 1;
                  $au      = AttrVal($name,"allowedUserForCode", "all");
                  @aul     = split(",",$au);
                  if($au eq "all" || $username ~~ @aul) {
                      my $code = $p2;
                      if($p2 =~ m/^\s*(\{.*\})\s*$/s) {
                          $p2 = $1;
                      } else {
                          $p2 = '';
                      } 
                      Log3($name, 4, "$name - Synology Chat user \"$username\" execute FHEM command: ".$p2);
                      $cr = AnalyzePerlCommand(undef, $p2) if($p2);                  # Perl Code in FHEM ausführen  
                  } else {
                      $cr    = "User \"$username\" is not allowed execute \"$command\" command";
                      $state = "command execution denied";
                      Log3($name, 2, "$name - WARNING - Chat user \"$username\" is not authorized for \"$command\" command. Execution denied !");
                  }                 
              } 
                  
              $cr = $cr ne ""?$cr:"command '$command' executed";
              Log3($name, 4, "$name - FHEM command return: ".$cr);
              
              $cr = SSChatBot_formText($cr);   

              SSChatBot_addQueue($name, "sendItem", "chatbot", $userid, $cr, "", "", "");                                 
          }
                                  
          my $ua = $attr{$name}{userattr};                                            # Liste aller ownCommand.. zusammenstellen
          $ua    = "" if(!$ua);
          my %hc = map { ($_ => 1) } grep { "$_" =~ m/ownCommand(\d+)/ } split(" ","ownCommand1 $ua");
       
		  foreach my $ca (sort keys %hc) {
			  my $uc = AttrVal($name, $ca, "");
			  next if (!$uc);
			  ($uc,$arg) = split(/\s+/, $uc, 2);
			  
			  if($uc && $text =~ /^$uc\s?$/) {                                        # User eigener Slash-Befehl, z.B.: /Wetter 
			      $command = $arg;
				  $do      = 1;
				  $au      = AttrVal($name,"allowedUserForOwn", "all");               # Berechtgung des Chat-Users checken
				  @aul     = split(",",$au);
				  if($au eq "all" || $username ~~ @aul) { 
					  Log3($name, 4, "$name - Synology Chat user \"$username\" execute FHEM command: ".$arg);  
					  $cr = AnalyzeCommandChain(undef, $arg);                         # FHEM Befehlsketten ausführen  
				  } else {
					  $cr    = "User \"$username\" is not allowed execute \"$arg\" command";
					  $state = "command execution denied";
					  Log3($name, 2, "$name - WARNING - Chat user \"$username\" is not authorized for \"$arg\" command. Execution denied !");
				  }                 
									
				  $cr = $cr ne ""?$cr:"command '$arg' executed";
				  Log3($name, 4, "$name - FHEM command return: ".$cr);
				  
				  $cr = SSChatBot_formText($cr);   

				  SSChatBot_addQueue($name, "sendItem", "chatbot", $userid, $cr, "", "", "");                                
			  }
		  }
		  
		  # Wenn Kommando ausgeführt wurde Ergebnisse aus Queue übertragen
		  if($do) {
		      RemoveInternalTimer($hash, "SSChatBot_getapisites");
		      InternalTimer(gettimeofday()+1, "SSChatBot_getapisites", "$name", 0); 
          }		  
      }
	  
	  if ($h->{trigger_word}) {
	      $triggerword = urlDecode($h->{trigger_word});                          
          Log3($name, 4, "$name - trigger_word received: ".$triggerword);
      }

	  readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "recChannelId",      $channelid);  
	  readingsBulkUpdate  ($hash, "recChannelname",    $channelname); 
	  readingsBulkUpdate  ($hash, "recUserId",         $userid); 
	  readingsBulkUpdate  ($hash, "recUsername",       $username); 
	  readingsBulkUpdate  ($hash, "recPostId",         $postid); 
      readingsBulkUpdate  ($hash, "recTimestamp",      $timestamp); 
	  readingsBulkUpdate  ($hash, "recText",           $text); 
	  readingsBulkUpdate  ($hash, "recTriggerword",    $triggerword);
	  readingsBulkUpdate  ($hash, "recCommand",        $command);       
      readingsBulkUpdate  ($hash, "sendCommandReturn", $cr);       
      readingsBulkUpdate  ($hash, "Errorcode",         "none");
      readingsBulkUpdate  ($hash, "Error",             "none");
      readingsBulkUpdate  ($hash, "state",             $state);        
	  readingsEndUpdate   ($hash,1);
	  
	  return ("text/plain; charset=utf-8", $ret);
		
  } else {
      # no data received
      return ("text/plain; charset=utf-8", "Missing data");
  }

}

#############################################################################################
#                                       Hint Hash EN           
#############################################################################################
%SSChatBot_vHintsExt_en = (
);

#############################################################################################
#                                       Hint Hash DE           
#############################################################################################
%SSChatBot_vHintsExt_de = (

);

1;

=pod
=item summary    module to integrate Synology Chat into FHEM
=item summary_DE Modul zur Integration von Synology Chat in FHEM
=begin html

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>

The guide for this module is currently only available in the german <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">Wiki</a>.

</ul>


=end html
=begin html_DE

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>

Die Beschreibung des Moduls ist momentan nur im <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">Wiki</a> vorhanden.
 
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
