########################################################################################
#
# FBTAM.pm
#
# FHEM module for FritzBox telephone answering machine
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################

package main;

use strict;
use warnings;

use XML::Simple;
use Digest::MD5 qw(md5_hex);
use HttpUtils;
use HTTP::Request;
use HTTP::Request::Common qw(POST);
use HTML::Entities;
use URI::Escape;
use LWP::UserAgent;

my $fbtam_version = "0.4";

#########################################################################################
#
# FBTAM_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub FBTAM_Initialize {
  my ($hash) = @_;
  
  $hash->{DefFn}    = \&FBTAM_Define;
  $hash->{UndefFn}  = \&FBTAM_Undef;
  $hash->{SetFn}    = \&FBTAM_Set;
  $hash->{AttrFn}   = \&FBTAM_Attr;
  $hash->{AttrList} = "interval targetdir username TTSFun TTSDev MsgrType MsgrFun MsgrRecList MailFun MailRecList Wav2MP3Fun";
  
   $hash->{FW_summaryFn}       = \&FBTAM_FW_Detail;
   $hash->{FW_detailFn}        = \&FBTAM_FW_Detail;

}

#########################################################################################
#
# FBTAM_Define 
# 
# Parameter hash = hash of device addressed 
#           def  = definition line
#
#########################################################################################

sub FBTAM_Define {
  my ($hash, $def) = @_;
  my @args = split(/[ \t]+/, $def);
  return "Usage: define <name> FBTAM <FritzBoxDevice> <TAM-Index 1-4>" unless(@args == 4);

  my ($name, $type, $fbDev, $tamNr) = @args;

  return "[FBTAM] Device '$fbDev' not found" unless defined($defs{$fbDev});
  return "[FBTAM] TAM number must be 1-4" unless $tamNr =~ /^[1-4]$/;

  $hash->{FBDev}     = $fbDev;
  #-- careful, tamIndex=tamNr-1
  $hash->{TAM}       = $tamNr;
  $hash->{INTERVAL}  = AttrVal($name, 'interval', 60);
  
  #-- credentials
  my $savedUser = AttrVal($name, "username", undef);
  $hash->{USERNAME} = $savedUser if defined $savedUser;
  #my $pwKey = AttrVal($name, "passwordKey", undef);
  #if ($pwKey) {
  #  $hash->{PASSWORD_KEY} = $pwKey;
  #  my $pw = getKeyValue($pwKey);
  #  $hash->{PASSWORD} = $pw if defined $pw;
  #}
  $hash->{STATE}     = 'Initialized';

  $modules{FBTAM}{defptr}{$name} = $hash;

  InternalTimer(gettimeofday()+5, "FBTAM_Update", $hash, 0);

  return undef;
}

#########################################################################################
#
# FBTAM_FW_Detail Detail-Ansicht (komplette Tabelle)
#
#########################################################################################

sub FBTAM_FW_Detail($$$$) {
    my ($FW_wname, $name, $room, $pageHash) = @_;
    my $hash = $defs{$name};

    return FBTAM_renderMsgTable($hash);
}

#########################################################################################
#
# FBTAM_FW_Summary Kompakte Zusammenfassung für die Geräte-Liste
#
#########################################################################################
# 
sub FBTAM_FW_Summary($$$$) {
  my ($FW_wname, $name, $room, $pageHash) = @_;
  my $hash = $defs{$name};

  my $tamName = ReadingsVal($name,"tam_name","");
  my $newMsg  = ReadingsVal($name,"tam_newMsg","");
  my $oldMsg  = ReadingsVal($name,"tam_oldMsg","");
  my $tamState= ReadingsVal($name,"tam_state","");

  my $html =  "<html><div><b>$tamName ($tamState): $newMsg neue / $oldMsg alte Nachrichten</b></div></html>";
  return $html;
}

#########################################################################################
#
# FBTAM_Attr 
#
#########################################################################################

sub FBTAM_Attr {
  my ($cmd, $name, $attr, $val) = @_;
  if($cmd eq 'set' && $attr eq 'interval') {
    return "Invalid interval" unless $val =~ /^\d+$/;
  #}elsif($cmd eq 'set' && $attr eq 'targetdir') {
  #  TODO: Check existence targetdir
  }
  return undef;
}

#########################################################################################
#
# FBTAM_Undef
#
#########################################################################################

sub FBTAM_Undef {
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  delete $modules{FBTAM}{defptr}{$name};
  
  my $index = $hash->{TYPE}."_".$name."_passwd";
  setKeyValue($index, undef);
  return undef;
}

#########################################################################################
#
# FBTAM_storepassword
#
#########################################################################################

sub FBTAM_storepassword {
  my ($hash,$keyvalue) = @_;
  my $name = $hash->{NAME};   
  my $keyname  = 'FBTAM_' . $name . '_PASSWORD';
  my $key     = getUniqueId() . $keyname;
  my $enc_key = "";
   if ( eval "use Digest::MD5;1" ) {
    $key = Digest::MD5::md5_hex( unpack "H*", $key );
    $key .= Digest::MD5::md5_hex($key);
  }
  for my $char ( split //, $keyvalue ) {
    my $encode = chop($key);
    $enc_key .= sprintf( "%.2x", ord($char) ^ ord($encode) );
    $key = $encode . $key;
  }
  my $err = setKeyValue( $keyname, $enc_key );
  if ( defined($err) ){
     Log 1,"[FBTAM_storekey] $name: error while saving the value for key $keyname - $err" ;
     readingsSingleUpdate($hash, "msg", "Passwort konnte nicht gespeichert werden", 1);
  }else{
    Log 4,"[FBTAM_storekey] $name: password saved" ;
    readingsSingleUpdate($hash, "msg", "Passwort gespeichert", 1);
  }
  return undef;
}

#########################################################################################
#
# FBTAM_readpassword
#
#########################################################################################

sub FBTAM_readpassword {
    my ($hash) = @_;
    my $name = $hash->{NAME};
  
    my $keyname  = 'FBTAM_' . $name . '_PASSWORD';
    my $key   = getUniqueId() . $keyname;

    my ($err, $keyvalue ) = getKeyValue($keyname);

    if ( defined($err) ) {
      Log 1,"[FBTAM_readpassword] $name: unable to read value for key $keyname from file";
      readingsSingleUpdate($hash, "msg", "Passwort nicht lesbar", 1);
      return;
    }

    if ( defined($keyvalue) ) {
      if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
      }
      my $dec_key = '';
      for my $char ( map { pack( 'C', hex($_) ) } ( $keyvalue =~ /(..)/g ) ) {
        my $decode = chop($key);
        $dec_key .= chr( ord($char) ^ ord($decode) );
        $key = $decode . $key;
      }
      return $dec_key;
    }else{
      Log 1,"[FBTAM_readpassword] $name: no value for password $keyname in file";
      readingsSingleUpdate($hash, "msg", "Passwort nicht vorhanden", 1);
      return;
    }
    return;
}

#########################################################################################
#
# FBTAM_Update
#
#########################################################################################

sub FBTAM_Update {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  my $next = gettimeofday() + ($hash->{INTERVAL} || 60);
  InternalTimer($next, "FBTAM_Update", $hash, 0);

  my $fbDev = $hash->{FBDev};
  return unless defined($defs{$fbDev});

  my $fbip = InternalVal($fbDev, 'HOST', undef);
  readingsSingleUpdate($hash, 'fritzbox_ip', $fbip, 0) if $fbip;

  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $tam = $hash->{TAM};

  return unless $fbip && $username && $password;

  #-- read data from FB device
  my $nameReading    = ReadingsVal($fbDev, "tam$tam", '?');
  my $newMsgReading  = ReadingsVal($fbDev, "tam${tam}_newMsg", '0');
  my $oldMsgReading  = ReadingsVal($fbDev, "tam${tam}_oldMsg", '0');
  my $stateReading   = ReadingsVal($fbDev, "tam${tam}_state", '0');

  my $prevNew  = ReadingsVal($name, "tam_newMsg", "");
  my $prevOld  = ReadingsVal($name, "tam_oldMsg", "");
  my $prevState = ReadingsVal($name, "tam_state", "");

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "tam_name",   $nameReading);
  readingsBulkUpdate($hash, "tam_newMsg", $newMsgReading);
  readingsBulkUpdate($hash, "tam_oldMsg", $oldMsgReading);
  readingsBulkUpdate($hash, "tam_state",  $stateReading);
  readingsEndUpdate($hash,1);

  if ($prevState ne $stateReading || $prevNew ne $newMsgReading || $prevOld ne $oldMsgReading ||  $hash->{STATE} eq 'Initialized') {
    FBTAM_getMsgList($hash);
  }else{
    readingsSingleUpdate($hash, 'msg', 'Nachrichtenliste unverändert', 1);
  }
  #-- obsolete $hash->{STATE}=FBTAM_renderMsgTable($hash);
}

#########################################################################################
#
# FBTAM_Set 
#
#########################################################################################

sub FBTAM_Set {
  my ($hash, @args) = @_;
  return "" if IsDisabled($hash->{NAME});

  my $name = shift @args;
  return "Usage: set $name <command> [arguments]" unless @args;

  my $cmd = shift @args;
  my $fbDev = $hash->{FBDev};
  #-- careful: tamIndex = tamNr -1 
  my $tamNr = $hash->{TAM};
     
  if ($cmd eq 'username') {
    my $user = join(" ", @args);
    $hash->{USERNAME} = $user;
    CommandAttr(undef, "$name username $user");
    readingsSingleUpdate($hash, "msg", "Username gespeichert", 1);
    return undef;

  } elsif ($cmd eq 'password') {
    my $pass = join(" ", @args);
    FBTAM_storepassword($hash,$pass);
    return undef;
 
  } elsif ($cmd eq 'update') {
    $hash->{STATE}=FBTAM_getMsgList($hash);
    return undef;

  } elsif ($cmd eq 'on') {
    #-- local device
    if( defined($fbDev) ){
      fhem("set $fbDev tam $tamNr on");
    #-- soap call
    }else{
      FBTAM_enableTAM($hash,1);
    }
    readingsSingleUpdate($hash,"tam_state","on",1);
    return undef;

  } elsif ($cmd eq 'off') {
    #-- local device
    if( defined($fbDev) ){
      fhem("set $fbDev tam $tamNr off");
    #-- soap call
    }else{
      FBTAM_enableTAM($hash,0);
    }
    readingsSingleUpdate($hash,"tam_state","off",1);
    return undef;
    
  } elsif ($cmd eq 'downloadMsg') {
    return "Usage: set $name downloadMsg <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    FBTAM_downloadMsg($hash, $msgIndex);
    return undef;
    
  } elsif ($cmd eq "deleteMsg") {
    return "Usage: set $name deleteMsg <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    FBTAM_deleteMsg($hash, $msgIndex);
    return undef;
    
  } elsif ($cmd eq 'sendMessengerMsg') {
    return "Usage: set $name sendMessengerMsg <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    #-- todo: join all remaining args in one list
    my $recipients = $args[1] // '';
    FBTAM_sendMsgrMsg ($hash, $msgIndex, $recipients);
    return undef;
    
  } elsif ($cmd eq 'sendEmailMsg') {
    return "Usage: set $name sendEmailMsg <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    #-- todo: join all remaining args in one list
    my $recipients = $args[1] // '';
    FBTAM_sendEmailMsg($hash, $msgIndex, $recipients);
    return undef;
    
  } elsif ($cmd eq 'getInfo') {
    FBTAM_getinfo($hash);
    return undef;
    
  #--- currentyl disabled for user
  } elsif ($cmd eq 'markRead') {
    return "Usage: set $name markRead <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    FBTAM_markMsg($hash,$msgIndex,1);
    return undef;
    
  } elsif ($cmd eq 'markUnread') {
    return "Usage: set $name markUnread <index>" unless defined $args[0];
    my $msgIndex = $args[0];
    FBTAM_markMsg($hash,$msgIndex,0);
    return undef;
    
  } else {
    return "Unknown command '$cmd', choose one of getInfo:noArg update:noArg deleteMsg downloadMsg sendMessengerMsg sendEmailMsg on:noArg off:noArg username password";
  }
}

#########################################################################################
#
# FBTAM_getMsgListUrl 
#
#########################################################################################

sub FBTAM_getMsgListUrl {
  my ($hash) = @_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  my $tamIndex = $hash->{TAM}-1;
  
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new(timeout => 10);
  $ua->credentials("$fbip:49000", "HTTPS Access", $username, $password);

  my $soap_url = "http://$fbip:49000/upnp/control/x_tam";
  my $soap_action   = "urn:dslforum-org:service:X_AVM-DE_TAM:1#GetMessageList";
  my $soap_content = <<"EOFA";
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope 
    xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" 
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:GetMessageList xmlns:u="urn:dslforum-org:service:X_AVM-DE_TAM:1">
            <NewIndex>$tamIndex</NewIndex>
        </u:GetMessageList>
    </s:Body>
</s:Envelope>
EOFA

  my $req = HTTP::Request->new(POST => $soap_url);
    $req->header('Content-Type' => 'text/xml; charset="utf-8"');
    $req->header('SOAPAction' => "\"$soap_action\"");
    $req->content($soap_content);

  my $res = $ua->request($req);
  unless ($res->is_success) {
    Log 1,"[FBTAM] $name: Error, retrieval of getMessageListUrl failed: " . $res->status_line;
    return undef;
  }

  my $content = $res->decoded_content;
  if ($content =~ m|<NewURL>([^<]+)</NewURL>|) {
    my $newUrl = $1;
    # Optional: &amp; durch & ersetzen
    $newUrl =~ s/&amp;/&/g;
    if ($newUrl && $newUrl =~ /[?&]sid=([a-fA-F0-9]+)/) {
      $hash->{SID} = $1;
      Log 4, "[FBTAM] $name: SID extracted successfully: $1";
    } else {
      Log 1, "[FBTAM] $name: no valid SID in response";
    }
    return $newUrl;
  }else {
    Log 1,"[FBTAM] $name: Error, no NewURL in response";
    return undef;
  }
}

#########################################################################################
#
# FBTAM_getMsgList 
#
#########################################################################################

sub FBTAM_getMsgList {
  my ($hash) = @_;

  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  my $tamIndex = $hash->{TAM}-1;
  
  my $listUrl = FBTAM_getMsgListUrl($hash);
  unless ($listUrl) {
    Log 1, "[FBTAM] $name: no message list url obtained";
    readingsSingleUpdate($hash, 'msg', 'Fehler: keine URL der Nachrichtenliste erhalten', 1);
    return undef;
  }
   
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new;
  $ua->credentials($fbip . ':49000', 'HTTPS Access', $username, $password);

  my $res = $ua->get($listUrl);
  unless ($res->is_success) {
    Log 1, "[FBTAM] $name: Error, retrieval of message list failed: " . $res->status_line;
    readingsSingleUpdate($hash, 'msg', 'Fehler beim Abruf der Nachrichtenliste', 1);
    return undef;
  }

  my $xml = $res->decoded_content;
  unless ($xml) {
    Log 1, "[FBTAM] $name: Error, retrieval of message list returned empty XML";
    readingsSingleUpdate($hash, 'msg', 'Fehler: leere XML-Antwort', 1);
    return undef;
  }

  if( $xml =~ /tam\scalls\:0/ ){
    Log 4, "[FBTAM] $name: message list retrieved, but no messages";
    readingsSingleUpdate($hash, 'msg', 'Nachrichtenliste erfolgreich geladen, aber leer', 1);
    $hash->{MessageList} = {};
  }else{
    my $parsed;
    eval {
      $parsed = XMLin($xml, ForceArray => ['Message'], KeyAttr => []);
    };
  
    if ($@ || !$parsed->{Message}) {
     Log 1, "[FBTAM] $name: Error in parsing XML: $@";
      readingsSingleUpdate($hash, 'msg', 'Fehler beim Parsen der Nachrichtenliste', 1);
      $hash->{MessageList} = {};
      return undef;
    }
    $hash->{MessageList} = $parsed;
    Log 4, "[FBTAM] $name: message list retrieved";
    readingsSingleUpdate($hash, 'msg', 'Nachrichtenliste erfolgreich geladen', 1);
  }
  return 1;
}

#########################################################################################
#
# FBTAM_renderMsgTable
#
#########################################################################################

sub FBTAM_renderMsgTable($) {
  my ($hash)=@_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful, tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  my $sid = $hash->{SID} // '';

  my $tamName = ReadingsVal($name,"tam_name","");
  my $newMsg  = ReadingsVal($name,"tam_newMsg","");
  my $oldMsg  = ReadingsVal($name,"tam_oldMsg","");
  my $tamState= ReadingsVal($name,"tam_state","");
  
  #-- header
  my $html = "<html>";
  #$html .= qq{<span style="display:none;">&lt;script src="/fhem/pgm2/fbtam.js"&gt;&lt;/script&gt;</span>};
  $html .=  "<div><b>$tamName ($tamState): $newMsg neue / $oldMsg alte Nachrichten</b></div>";

  
  #-- get current list
  my $parsed = $hash->{MessageList};
  unless ($parsed && ref($parsed) eq 'HASH') {
    Log 1, "[FBTAM] $name: Error, no valid message list";
    $html .= "<div style='color:red;'>Keine gültige Nachrichtenliste</div>";
    return $html;
  }
  my $messages;
  $messages = $parsed->{Message} 
    if($parsed->{Message});
  
  if( !($parsed->{Message}) || int(@$messages) == 0) {
    Log 4, "[FBTAM] $name: empty message list";
    $html .= "<div style='color:red;'>Leere Nachrichtenliste</div>";
    return $html;
  }
  
  #-- start collecting
  $html .= "<table border='1' style='border-collapse:collapse;'>";
  $html .= "<tr style='background:#ccc;'>
              <th>Index</th>
              <th>Datum</th>
              <th>Anrufer</th>
              <th>Aktion</th>
            </tr>";

  foreach my $msg (@$messages) {
    my $index   = $msg->{Index}    // '';
    my $date    = encode_entities($msg->{Date} // '');
    my ($d, $t) = split(/\s+/, $date);
    my $dur     = encode_entities($msg->{Duration} // '');
    my $fname;
    if (ref($msg->{Name}) eq 'HASH') {
      $fname = $msg->{Name}->{value} // '';
      #Log 1,"=================> name= ".Dumper($msg->{Name});
    } else {
      $fname = $msg->{Name} // '';
    }
    $fname = encode_entities($fname);
    my $fnumber   = encode_entities($msg->{Number} // '');
    #-- pull up number if no name
    if(!$fname){
      $fname=$fnumber;
      $fnumber="";
    }
    my $fnew    = $msg->{New};

    #-- buttons  
    my $emailBtn = AttrVal($name, "MailFun", undef) ? 
                   "<input type=\"button\" value=\"&#128231;E-Mail\" style=\"width:100px;\" onclick=\"callTAMAction('sendEmailMsg', '$name', $index); return false;\"/><br>": "";
    my $msgrBtn  = AttrVal($name, "MsgrFun", undef) ? 
                   "<input type=\"button\" value=\"&#128172;".AttrVal($name,"MsgrType","Messenger").
                        "\" style=\"width:100px;\" onclick=\"callTAMAction('sendMessengerMsg', '$name', $index); return false;\"/><br>": "";
    my $delBtn   = "<input type=\"button\" value=\"&#128465;Löschen\" style=\"width:100px;\" onclick=\"callTAMAction('deleteMsg',   '$name', $index); return false;\"/>";
    my $dlBtn    = "<input type=\"button\" value=\"&#11015;Download\" style=\"width:100px;\" onclick=\"callTAMAction('downloadMsg', '$name', $index); return false;\"/>";
    #-- buttons in output
    $html .= "<script src=\"/fhem/pgm2/fbtam.js\"></script>";
    $html .= "<tr>
                <td>$index ".(($fnew == 1)?"*":"")."</td>
                <td>$d<br><small>$t (Dauer: $dur)</small></td>
                <td><b>$fname</b><br><small>$fnumber</small></td>
                <td style='text-align:center;'>$emailBtn$msgrBtn\n$delBtn<br>\n$dlBtn</td>
              </tr>";
  }
  $html .= "</table></html>";

  return $html;
}

#########################################################################################
#
# FBTAM_renderTgTable
#
#########################################################################################

sub FBTAM_renderTgTable($) {
  my ($hash)=@_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful, tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  my $sid = $hash->{SID} // '';

  my $tamName = ReadingsVal($name,"tam_name","");
  my $newMsg  = ReadingsVal($name,"tam_newMsg","");
  my $oldMsg  = ReadingsVal($name,"tam_oldMsg","");
  my $tamState= ReadingsVal($name,"tam_state","");
  
  #-- result
  my $result = "";
  
  #-- get current list
  my $parsed = $hash->{MessageList};
  unless ($parsed && ref($parsed) eq 'HASH') {
    Log 4, "[FBTAM] $name:no message list";
    $result = " ENDMENU $tamName=$tamState, Keine Nachrichtenliste";
    return $result;
  }
  my $messages;
  $messages = $parsed->{Message} 
    if($parsed->{Message});
  
  if( !($parsed->{Message}) || int(@$messages) == 0) {
    Log 4, "[FBTAM] $name: empty message list";
    $result = " ENDMENU $tamName=$tamState, Leere Nachrichtenliste";
    return $result;
  }
  
  #-- start collecting
  foreach my $msg (@$messages) {
    my $index   = $msg->{Index}    // '';
    my $date    = $msg->{Date} // '';
    my ($d, $t) = split(/\s+/, $date);
    #my $dur     = $msg->{Duration} // '';
    my $fname;
    if (ref($msg->{Name}) eq 'HASH') {
      $fname = $msg->{Name}->{value} // '';
    } else {
      $fname = $msg->{Name} // '';
    }
    my $fnumber   = $msg->{Number} // '';
    #-- pull up number if no name
    $fname = $fnumber unless $fname;
    my $fnew    = $msg->{New};
    $result .= "([$index".(($fnew == 1)?"*":"")."] $fname, $d:tam_line ".$tamIndex."_".$index.") ";         
  }
  #-- Umlaute
  $result =~ s/\xe4/ä/g;
  $result =~ s/\xc4/Ä/g;
  $result =~ s/\xfc/ü/g;
  $result =~ s/\xdc/Ü/g;
  $result =~ s/\xf6/ö/g;
  $result =~ s/\xd6/Ö/g;
  $result =~ s/\xdf/ss/g;
  $result .= " ENDMENU $tamName=$tamState, $newMsg neue / $oldMsg alte Nachrichten";
  return $result;
}

#########################################################################################
#
# FBTAM_sendMsgEmail
#
#########################################################################################

sub FBTAM_sendEmailMsg {
  my ($hash, $dlIndex, $recipients) = @_;
  
  my $name  = $hash->{NAME};
 
  my $MailFun=AttrVal($name,"MailFun",undef);
  if( !$MailFun){
    Log 1,"[FBTAM] $name: Error, attribute MailFun is not defined";
    readingsSingleUpdate($hash,"msg","Fehler: Attribut MailFun ist nicht vorhanden",1);
    return;
  };
  my @mrl;
  if( !$recipients || $recipients eq ''){  
    my $MailRecList=AttrVal($name,"MailRecList",undef);
    if( !defined($MailRecList) || $MailRecList eq ""){
      Log 1,"[FBTAM] $name: Error, no recipient given and attribute MailRecList is not defined or empty";
      readingsSingleUpdate($hash,"msg","Fehler: Keine Angabe des Empfängers und Attribut MailRecList ist nicht vorhanden oder leer",1);
      return;
    }
    @mrl = split(' ',$MailRecList);
  }else{
    @mrl = split(' ',$recipients);
  }
  readingsSingleUpdate($hash,"tam_recipients",join(' ',@mrl),0);
  
  FBTAM_downloadMsg($hash,$dlIndex);
  my $target  = ReadingsVal($name,"tam_msgurl","");
  my $meta = ReadingsVal($name,"tam_msgmsg","");
  my $cmd;
  foreach my $rec (@mrl){
    $cmd = $MailFun;
    $cmd =~ s/REC/$rec/;
    $cmd =~ s/META/$meta/;
    $cmd =~ s/FILE/$target/;
    eval($cmd);
  }
}
    
#########################################################################################
#
# FBTAM_sendMsgMsgr
#
#########################################################################################

sub FBTAM_sendMsgrMsg{
  my ($hash, $dlIndex, $recipients) = @_;
  
  my $name  = $hash->{NAME};
 
  my $MsgrFun=AttrVal($name,"MsgrFun",undef);
  if( !$MsgrFun){
    Log 1,"[FBTAM] $name: Error, attribute MsgrFun is not defined";
    readingsSingleUpdate($hash,"msg","Fehler: Attribut MsgrFun ist nicht vorhanden",1);
    return;
  };
  my @mrl;
  if( !$recipients || $recipients eq ''){  
    my $MsgrRecList=AttrVal($name,"MsgrRecList",undef);
    if( !defined($MsgrRecList) || $MsgrRecList eq ""){
      Log 1,"[FBTAM] $name: Error, not recipient given and attribute MsgrRecList is not defined or empty";
      readingsSingleUpdate($hash,"msg","Fehler: Keine Angabe des Empfängers und Attribut MsgrRecList ist nicht vorhanden oder leer",1);
      return;
    }
    @mrl = split(' ',$MsgrRecList);
  }else{
    @mrl = split(' ',$recipients);
  }
  readingsSingleUpdate($hash,"tam_recipients",join(' ',@mrl),0);
  
  FBTAM_downloadMsg($hash,$dlIndex);
  my $target  = ReadingsVal($name,"tam_msgurl","");
  my $meta = ReadingsVal($name,"tam_msgmsg","");
  my $cmd;
  foreach my $rec (@mrl){
    $cmd = $MsgrFun;
    $cmd =~ s/REC/$rec/;
    $cmd =~ s/META/$meta/;
    $cmd =~ s/FILE/$target/;
    eval($cmd);
  }
}  
  
#########################################################################################
#
# FBTAM_downloadMsg - Download zum FHEM-Server
#
#########################################################################################

sub FBTAM_downloadMsg {
  my ($hash, $dlIndex) = @_;

  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  my $tamNr = $hash->{TAM};
  my $sid   = $hash->{SID};
  
  #-- get current list
  my $parsed = $hash->{MessageList};
  unless ($parsed && ref($parsed) eq 'HASH') {
    Log 1, "[FBTAM] $name: Error, no valid message list";
    readingsSingleUpdate($hash,'msg',"Keine gültige Nachrichtenliste",1);
    return undef;
  }
  unless ($parsed && ref($parsed) eq 'HASH' && $parsed->{Message}) {
    Log 4, "[FBTAM] $name: empty message list";
    readingsSingleUpdate($hash,'msg',"Leere Nachrichtenliste",1);
    return undef;
  }
  
  my $found = 0;
  my $rawPath;
  
  my $msgmsg;
  my $messages = $parsed->{Message};
  foreach my $msg (@$messages) {
    my $index = $msg->{Index}    // '';
    if( $index == $dlIndex ){
      $found = 1;
      my $date    = $msg->{Date} // '';
      my ($d, $t) = split(/\s+/, $date);
      my $fname;
      if (ref($msg->{Name}) eq 'HASH') {
        $fname = $msg->{Name}->{value} // '';
      } else {
        $fname = $msg->{Name} // '';
      }
      my $fnumber   = $msg->{Number} // '';
      #-- pull up number if no name
      $fname  = $fnumber unless $fname;
      $msgmsg = "Nachricht $index von $fname am $d um $t"; 
      if (ref($msg->{Path}) eq 'HASH') {
        $rawPath = $msg->{Path}->{value} // '';
      } else {
        $rawPath = $msg->{Path} // '';
      }
      last;
    }
  }  
   unless( $found ) {
    Log 1, "[FBTAM] $name: Error, no message found with index $dlIndex";
    readingsSingleUpdate($hash,'msg',"Keine Nachricht gefunden mit Index $dlIndex",1);
    return undef;
  } 
  unless( $rawPath ) {
    Log 1, "[FBTAM] $name: Error, no path given for message with index $dlIndex";
    readingsSingleUpdate($hash,'msg',"Keine Pfadangabe für Nachricht $dlIndex",1);
    return undef;
  } 
  #-- Umlaute
  $msgmsg =~ s/\xe4/ä/g;
  $msgmsg =~ s/\xc4/Ä/g;
  $msgmsg =~ s/\xfc/ü/g;
  $msgmsg =~ s/\xdc/Ü/g;
  $msgmsg =~ s/\xf6/ö/g;
  $msgmsg =~ s/\xd6/Ö/g;
  $msgmsg =~ s/\xdf/ss/g;
  readingsSingleUpdate($hash,'tam_msgmsg',$msgmsg,1);
  
  $rawPath =~ /.*path=(.*)/;
  my $filePath = uri_escape($1);
  my $script = uri_escape('/lua/photo.lua');

  my $msgUrl = "http://$fbip/cgi-bin/luacgi_notimeout" .
            "?sid=" . $sid .
            "&script=" . $script . 
            "&myabfile=" . $filePath;

  Log 4, "[FBTAM] $name: starting async download for index $dlIndex from $msgUrl";

  # Callback für NonblockingGet
  my $callback = sub {
    my ($param, $err, $data) = @_;

    if ($err) {
      Log 1, "[FBTAM] $name: Download failed for index $dlIndex - $err";
      readingsSingleUpdate($hash, "msg", "Download fehlgeschlagen: $err", 1);
      return undef;
    }

    if (!defined $data || $data eq '' || length($data)<12) {
      Log 1, "[FBTAM] $name: Download failed for index $dlIndex - no data received";
      readingsSingleUpdate($hash, "msg", "Keine Daten empfangen", 1);
      return;
    }
    
    if ( substr($data, 0, 4) ne 'RIFF' ||  substr($data, 8, 4) ne 'WAVE' ){
      Log 1, "[FBTAM] $name: Download failed for index $dlIndex - invalid wave file received";
      readingsSingleUpdate($hash, "msg", "Keine WAV-Daten empfangen", 1);
      Log 1,"====> 0-4 = ".substr($data, 0, 4)."    8-4 = ". substr($data, 8, 4);
      #return;
    }
    
    my $targetdir = AttrVal($name, "targetdir", "/opt/fhem/www/audio");
    my $target    = "$targetdir/fbtam${tamNr}_msg${dlIndex}.wav";
    readingsSingleUpdate($hash,"tam_msgurl",$target,1);

    #-- write file
    if (!open(my $fh, '>:raw', $target)) {
      Log 1, "[FBTAM] $name: Cannot open $target for writing: $!";
      readingsSingleUpdate($hash, "msg", "Kann $target nicht zum Schreiben öffnen", 1);
      return undef;
    }else{
      print $fh $data;
      close $fh;
      Log 4, "[FBTAM] $name: Message with index $dlIndex saved to $target";
      readingsSingleUpdate($hash, "msg", "Nachricht mit Index $dlIndex gespeichert in $target", 1);
    }
    #-- mark as read
    FBTAM_markMsg($hash,$dlIndex,1);
    
    #-- change into MP3 if function is defined, otherwise delete existing file
    my $cmd = AttrVal($name,"Wav2MP3Fun",undef);
    my $target2    = "$targetdir/fbtam${tamNr}_msg${dlIndex}.mp3"; 
    if( $cmd ){
      $cmd =~ s/INPUT/$target/;
      $cmd =~ s/OUTPUT/$target2/;
      $cmd =~ s/META/$msgmsg/;
      #Log 1,"==========> cmd=$cmd";
      eval($cmd);
      Log 4, "[FBTAM] $name: Message with index $dlIndex converted to $target2";
      readingsSingleUpdate($hash, "msg", "Nachricht mit Index $dlIndex konvertiert nach $target2", 1);
      readingsSingleUpdate($hash,"tam_msgurl",$target2,1);
    }else{
      system('rm '.$target2);
    }
  };

  # Non-blocking HTTP-Request starten
  HttpUtils_NonblockingGet({
    url        => $msgUrl,
    timeout    => 100,
    keepalive  => 0,
    noshutdown => 1,
    hash       => $hash,
    callback   => $callback,
  });
  
  return;
}

#########################################################################################
#
# FBTAM_deleteMsg
#
#########################################################################################

sub FBTAM_deleteMsg {
  my ($hash, $dlIndex) = @_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful: tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  
  #-- get current list from menory
  my $parsed = $hash->{MessageList};
  unless ($parsed && ref($parsed) eq 'HASH') {
    Log 1, "[FBTAM] $name: Error, no valid message list";
    readingsSingleUpdate($hash,'msg',"Keine gültige Nachrichtenliste",1);
    return
  }
  unless ($parsed && ref($parsed) eq 'HASH' && $parsed->{Message}) {
    Log 4, "[FBTAM] $name: empty message list";
    readingsSingleUpdate($hash,'msg',"Leere Nachrichtenliste",1);
    return
  }
  
  #-- find proper entry
  my $found = 0;
  my $foundIndex;
  my $rawPath;
  my $messages = $parsed->{Message};
  for (my $i=0;$i<int(@$messages);$i++){
    my $msg = (@$messages)[$i];
    my $index = $msg->{Index}    // '';
    if( $index == $dlIndex ){
      $found = 1;
      $foundIndex = $i;
      last;
    }
  }  
  
  unless( $found ) {
    Log 1, "[FBTAM] $name: Error, no message found with index $dlIndex";
    readingsSingleUpdate($hash,'msg',"Keine Nachricht gefunden mit Index $dlIndex",1);
    return
  } 
  
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new(timeout => 10);
  $ua->credentials("$fbip:49000", "HTTPS Access", $username, $password);
  
  my $soap_url = "http://$fbip:49000/upnp/control/x_tam";
  my $soap_action = "urn:dslforum-org:service:X_AVM-DE_TAM:1#DeleteMessage";
  my $soap_content = <<"EOFB";
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:DeleteMessage xmlns:u="urn:dslforum-org:service:X_AVM-DE_TAM:1">
      <NewIndex>$tamIndex</NewIndex>
      <NewMessageIndex>$dlIndex</NewMessageIndex>
    </u:DeleteMessage>
  </s:Body>
</s:Envelope>
EOFB

  my $req = HTTP::Request->new(POST => $soap_url);
  $req->header('Content-Type' => 'text/xml; charset="utf-8"');
  $req->header('SOAPAction' => "\"$soap_action\"");
  $req->content($soap_content);
      
  my $res = $ua->request($req);
  if (!$res->is_success) {
    Log 1, "[FBTAM] $name: Error, delete request for index $dlIndex failed: " . $res->status_line;
    readingsSingleUpdate($hash, "msg", "Fehler beim Löschen von (Index $dlIndex): " . $res->status_line, 1);
    return undef;
  }
  
  my $content = $res->decoded_content;
  if ($content !~ m|<u:DeleteMessageResponse|) {
    Log 1, "[FBTAM] $name: Error, obtained invalid answer on delete $dlIndex: $content";
    readingsSingleUpdate($hash, "msg", "Fehler beim Löschen (Index $dlIndex)", 1);
    return undef;
  }
 
  Log 4, "[FBTAM] $name: Message w. index $dlIndex deleted successfully.";
  readingsSingleUpdate($hash, "msg", "Nachricht mit Index $dlIndex gelöscht", 1);

  #-- remove from memory and get list again
  splice(@$messages, $foundIndex, 1);
  $hash->{STATE}=FBTAM_getMsgList($hash);
}

#########################################################################################
#
# FBTAM_markMsg
#
#########################################################################################

sub FBTAM_markMsg {
  my ($hash, $dlIndex,$parm) = @_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful: tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  
  
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new(timeout => 10);
  $ua->credentials("$fbip:49000", "HTTPS Access", $username, $password);
  
  my $soap_url = "http://$fbip:49000/upnp/control/x_tam";
  my $soap_action = "urn:dslforum-org:service:X_AVM-DE_TAM:1#MarkMessage";
  my $soap_content = <<"EOFI";
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:MarkMessage xmlns:u="urn:dslforum-org:service:X_AVM-DE_TAM:1">
      <NewIndex>$tamIndex</NewIndex>
      <NewMessageIndex>$dlIndex</NewMessageIndex>
      <NewMarkedAsRead>$parm</NewMarkedAsRead>
    </u:MarkMessage>
  </s:Body>
</s:Envelope>
EOFI

  my $req = HTTP::Request->new(POST => $soap_url);
  $req->header('Content-Type' => 'text/xml; charset="utf-8"');
  $req->header('SOAPAction' => "\"$soap_action\"");
  $req->content($soap_content);
      
  my $res = $ua->request($req);
  if (!$res->is_success) {
    Log 1, "[FBTAM] $name: Error, marking request for index $dlIndex failed: " . $res->status_line;
    readingsSingleUpdate($hash, "msg", "Fehler beim Markieren von (Index $dlIndex): " . $res->status_line, 1);
    return undef;
  }
  
  my $content = $res->decoded_content;
  
  if ($content !~ m|<u:MarkMessageResponse|) {
    Log 1, "[FBTAM] $name: Error, obtained invalid answer on MarkMessage: $content";
    readingsSingleUpdate($hash, "msg", "Fehler beim ".(($parm == 0)?"De-Markierung ":"Markierung "). $content, 1);
    return undef;
  }
  Log 4, "[FBTAM] $name: ".(($parm == 0)?"unmarking ":"marking ")." successful";
  readingsSingleUpdate($hash, "msg", (($parm == 0)?"De-Markierung ":"Markierung ")." erfolgreich",1);
}

#########################################################################################
#
# FBTAM_enableTAM
#
#########################################################################################

sub FBTAM_enableTAM {
  my ($hash,$parm) = @_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful: tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new(timeout => 10);
  $ua->credentials("$fbip:49000", "HTTPS Access", $username, $password);
  
  my $soap_url = "http://$fbip:49000/upnp/control/x_tam";
  my $soap_action = "urn:dslforum-org:service:X_AVM-DE_TAM:1#SetEnable";
  my $soap_content = <<"EOFD";
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetEnable xmlns:u="urn:dslforum-org:service:X_AVM-DE_TAM:1">
      <NewIndex>$tamIndex</NewIndex>
      <NewEnable>$parm</NewEnable>
    </u:SetEnable>
  </s:Body>
</s:Envelope>
EOFD

  my $req = HTTP::Request->new(POST => $soap_url);
  $req->header('Content-Type' => 'text/xml; charset="utf-8"');
  $req->header('SOAPAction' => "\"$soap_action\"");
  $req->content($soap_content);
      
  my $res = $ua->request($req);
  if (!$res->is_success) {
    Log 1, "[FBTAM] $name: Error, SetEnable failed: " . $res->status_line;
    readingsSingleUpdate($hash, "msg", "Fehler beim ".(($parm == 0)?"Ausschalten: ":"Einschalten: "). $res->status_line, 1);
    return undef;
  }
  
  my $content = $res->decoded_content;
  if ($content !~ m|<u:SetEnableResponse|) {
    Log 1, "[FBTAM] $name: Error, obtained invalid answer on SetEnable: $content";
    readingsSingleUpdate($hash, "msg", "Fehler beim ".(($parm == 0)?"Ausschalten: ":"Einschalten: "). $content, 1);
    return undef;
  }
  Log 4, "[FBTAM] $name: ".(($parm == 0)?"disable ":"enable ")." successful";
  readingsSingleUpdate($hash, "msg", (($parm == 0)?"Ausschalten ":"Einschalten ")." erfolgreich",1);
}

sub FBTAM_getinfo {
  my ($hash) = @_;
  
  my $name  = $hash->{NAME};
  my $fbDev = $hash->{FBDev};
  my $fbip  = InternalVal($fbDev, 'HOST', undef);
  #-- careful: tamIndex = tamNr-1
  my $tamIndex = $hash->{TAM}-1;
  
  my $username = $hash->{USERNAME} // '';
  my $password = FBTAM_readpassword($hash);
  my $ua = LWP::UserAgent->new(timeout => 10);
  $ua->credentials("$fbip:49000", "HTTPS Access", $username, $password);
  
  my $soap_url = "http://$fbip:49000/upnp/control/x_tam";
  my $soap_action = "urn:dslforum-org:service:X_AVM-DE_TAM:1#GetInfo";
  my $soap_content = <<"EOFC";
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetInfo xmlns:u="urn:dslforum-org:service:X_AVM-DE_TAM:1">
      <NewIndex>$tamIndex</NewIndex>
    </u:GetInfo>
  </s:Body>
</s:Envelope>
EOFC

  my $req = HTTP::Request->new(POST => $soap_url);
  $req->header('Content-Type' => 'text/xml; charset="utf-8"');
  $req->header('SOAPAction' => "\"$soap_action\"");
  $req->content($soap_content);
      
  my $res = $ua->request($req);
  if (!$res->is_success) {
    Log 1, "[FBTAM] $name: Error, GetInfo failed: " . $res->status_line;
    #readingsSingleUpdate($hash, "msg", "Fehler beim Löschen von (Index $dlIndex): " . $res->status_line, 1);
    return undef;
  }
  
  my $content = $res->decoded_content;
  #if ($content !~ m|<u:GetInfo|) {
  #  Log 1, "[FBTAM] $name: Error, obtained invalid answer on GetInfo: $content";
  #  #readingsSingleUpdate($hash, "msg", "Fehler beim Löschen (Index $dlIndex)", 1);
  #  return undef;
  #}
  Log 1,"==============> $content";
}

1;

=pod
=item helper
=item summary Administration of a FritzBox telephone answering machine 
=item summary_DE Verwaltung eines FritzBox-Anwufbeantworters
=begin html

<a name="FBTAM"></a>
<h3>FBTAM</h3>
<ul>
    <p> Administration of a FritzBox telephone answering machine</p>
    <a name="FBTAMusage"></a>
    <h4>Usage</h4>
    <br />
    <a name="FBTAMdefine"></a>
    <h4>Define</h4>
    <p>
        <code>define &lt;name&gt; FBTAM &lt;device name of FritzBox&gt; &lt;Internal number
            of TAM, 1..4&gt;</code>
        <br />Defines the FBTAM system. </p> Notes: <ul>
        <li>The module requires that the accompanying JavaScript file fbtam.js is stored in
            /opt/fhem/www/pgm2</li>
    </ul>
    <a name="FBTAMset"></a>
    <h4>Set</h4>
    <ul>
        <li><a name="fbtam_username">
                <code>set &lt;name&gt; username &lt;username&gt;</code></a><br /> sets a
            username for the FritzBox and stores it</li>
        <li><a name="fbtam_password">
                <code>set &lt;name&gt; password &lt;password&gt;</code></a><br /> sets a
            password for the FritzBox and stores it as hidden value</li>
        <li><a name="fbtam_deletemsg">
                <code>set &lt;name&gt; deleteMsg &lt;number&gt;</code></a><br /> delete the message with index <i>number</i>.</li>
        <li><a name="fbtam_downloadmsg">
                <code>set &lt;name&gt; downloadMsg &lt;number&gt;</code></a><br /> download the message with index <i>number</i>. 
                Note, that this download goes to the directory on the FHEM server specified in attribute <i>targetdir</i>. 
                A direct download to another system fails according to CORS prevention.</li>
        <li><a name="fbtam_sendemail">
                <code>set &lt;name&gt; sendEmailMsg &lt;number&gt; [&lt;recipients&gt;]</code></a><br /> send the message with index <i>number</i> 
                by mail to all recipients. Only available if MailFun attribute is set.</li>
        <li><a name="fbtam_sendmsgr">
                <code>set &lt;name&gt; sendMessengerMsg &lt;number&gt; [&lt;recipients&gt;]</code></a><br /> send the message with index <i>number</i> 
                by messenger to all recipients.  Only available if MsgrFun attribute is set.</li>
       </ul>         
    <a name="FBTAMattr"></a>
    <h4>Attributes</h4>
    <ul>
       <li><a name="fbtam_mailfun"><code>attr &lt;name&gt; MailFun 
                &lt;string&gt;</code></a>
            <br />FHEM code to be exceuted when a message is send by messenger. 
            Replacements are made for the strings REC=receiver of the message, META=metadata of the message and FILE=filename of the recorded message</li>
       <li><a name="fbtam_mailreclist"><code>attr &lt;name&gt; MailRecList
                &lt;string&gt;</code></a>
            <br />space-separated list of recipients for the message. Used only if no direct recipient is given</li> 
       <li><a name="fbtam_msgrtype"><code>attr &lt;name&gt; MsgrType 
                &lt;string&gt;</code></a>
            <br />Type of the messenger to appear in the send button, e.g. "Telegram";</li>
       <li><a name="fbtam_msgrfun"><code>attr &lt;name&gt; MsgrFun 
                &lt;string&gt;</code></a>
            <br />FHEM code to be exceuted when a message is send by messenger. 
            Replacements are made for the strings REC=receiver of the message, META=metadata of the message and FILE=filename of the recorded message</li>
       <li><a name="fbtam_msgrreclist"><code>attr &lt;name&gt; MsgrRecList
                &lt;string&gt;</code></a>
            <br />space-separated list of recipients for the message. Used only if no direct recipient is given</li> 
       <li><a name="fbtam_targetdir"><code>attr &lt;name&gt; targetdir
                &lt;string&gt;</code></a>
            <br />target directory at the FHEM server for dowloaded messages</li> 
    </ul>
</ul>

=end html

=begin html_DE

<a name="FBTAM"></a>
<h3>FBTAM</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_FBTAM">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="commandref.html#FBTAM">FBTAM</a> 
</ul>
=end html_DE
<ul>
=cut
