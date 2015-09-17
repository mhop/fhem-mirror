##############################################################################
#
#     70_Jabber.pm
#     An FHEM Perl module for connecting to an Jabber XMPP Server and 
#     send/recieve messages.
#     Thanks to Predictor who had the initial idea for such a module.
#
#     Copyright by BioS
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# Version: 1.5 - 2015-09-17
#
# Changelog:
# v1.5 2015-09-17 Added OTR (Off the Record) end to end encryption
#                 Added MUC (Multi-User-Channel) joining and handling
# v1.4 2015-08-27 Fixed broken callback registration in Net::XMPP >= 1.04
# v1.3 2015-01-10 Fixed DNS SRV resolving and resulting wrong to: address
# v1.2 2015-01-09 hardening XML::Stream Process() call and fix of ssl_verify
# v1.1 2014-07-28 Added UTF8 encoding / decoding to Messages
# v1.0 2014-04-10 Stable Release - Housekeeping & Add to SVN
# v0.3 2014-03-19 Fixed SetPresence() & Added extensive debugging capabilities by setting $debug to 1
# v0.2 2014-01-28 Added SSL option in addition to TLS 
# v0.1 2014-01-18 Initial Release
##############################################################################
# You will need the following perl Module and all it's depencies for this to work: 
# Net::Jabber
# For using the SSL features and to connect securly to a Jabber server you also need this perl Module:
# Net::SSLeay
#
# For using OTR you need to compile Crypt::OTR from CPAN on your own
#
# The recommended debian packages to be installed are these: 
# libnet-jabber-perl libnet-xmpp-perl libxml-stream-perl libdigest-sha1-perl libauthen-sasl-perl libnet-ssleay-perl
#
# Have Phun!
#
package main;

use strict;
use warnings;
use utf8;
use Time::HiRes qw(gettimeofday);
use Net::Jabber;
use base qw( Net::XMPP::Namespaces );
use Blocking;

sub Jabber_Set($@);
sub Jabber_Define($$);
sub Jabber_UnDef($$);
sub Jabber_PollMessages($);
sub Jabber_CheckConnection($);

# If you want extended logging and debugging infomations
# in fhem.log please set the following value to 1
my $debug = 0;

my %sets = (
  "msg" => 1,
  "msgmuc" => 1,
  "msgotr" => 1,
  "subscribe" => 1
);

###################################
sub
Jabber_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}      = "Jabber_Set";
  $hash->{DefFn}      = "Jabber_Define";
  $hash->{UndefFn}    = "Jabber_UnDef";
  $hash->{AttrFn}     = "Jabber_Attr";
  $hash->{AttrList}   = "dummy:1,0 loglevel:0,1,2,3,4,5 OnlineStatus:available,unavailable PollTimer RecvWhitelist ResourceName MucJoin MucRecvWhitelist OTREnable OTRSharedSecret ".$readingFnAttributes;
}

###################################
sub Jabber_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  
  if (!defined($sets{$cmd}))
  {
    return "Unknown argument " . $cmd . ", choose one of " . join(" ", sort keys %sets);
  }

  if ($cmd eq 'msg')
  {
    return Jabber_Set_Message($hash, @args);
  }

  if ($cmd eq 'msgmuc')
  {
    return Jabber_Set_MUCMessage($hash, @args);
  }

  if ($cmd eq 'msgotr')
  {
    return Jabber_Set_OTRMessage($hash, @args);
  }


  if ($cmd eq 'subscribe')
  {
    return Jabber_Subcribe_To($hash, @args);
  }

}
###################################
# Set's
###################################
sub Jabber_Set_Message($@)
{
  my ($hash,$dst,@tmpMsg) = @_;
  my $message = join(" ", @tmpMsg);
  utf8::decode($message);
  if (Jabber_CheckConnection($hash)) {

    $hash->{JabberDevice}->MessageSend(to=>$dst,
                      body=>$message,
                      type=>"chat",
                      priority=>10);  
  }
}

###################################
sub Jabber_Set_MUCMessage($@)
{
  my ($hash,$dst,@tmpMsg) = @_;
  my $message = join(" ", @tmpMsg);
  utf8::decode($message);
  if (Jabber_CheckConnection($hash)) {

    #convert the groupchat id to a short id else this would be a private message which is not allowed via "groupchat" type
    my $JID = new Net::Jabber::JID($dst);
    my $senderShort = $JID->GetJID("base");
    $hash->{JabberDevice}->MessageSend(to=>$senderShort,
                      body=>$message,
                      type=>"groupchat",
                      priority=>10);
  }
}

###################################
sub Jabber_Set_OTRMessage($@)
{
  my ($hash,$dst,@tmpMsg) = @_;
  my $message = join(" ", @tmpMsg);
  utf8::decode($message);
  if (Jabber_CheckConnection($hash)) {
    if ($hash->{helper}{otractive}) {
      my $JID = new Net::Jabber::JID($dst);

      if (defined($hash->{helper}{otrJIDs}{$JID->GetJID("full")}) && defined($hash->{helper}{otrJIDs}{$JID->GetJID("full")}{verified}) ) {
        #send a encrypted message as we have an connection
        if (my $ciphertext = $hash->{OTR}->encrypt($JID->GetJID("full"), $message)) {
            Log 0, "$hash->{NAME} Secure sending to ".$JID->GetJID("full") if $debug;
            Jabber_Set_Message($hash,$dst,$ciphertext);
        } else {
            Log 0, "$hash->{NAME} Your message was not sent - no encrypted conversation is established" if $debug;
        }
      } else {
        #establish a secure connection and send the message then.
        Log 0, "$hash->{NAME} No secure connection to ".$JID->GetJID("full")." - establishing and sending message later..." if $debug;
        #send it later
        push @{ $hash->{helper}{otrJIDs}{$JID->GetJID("full")}{waitingMsgs} }, {"jid" => $JID->GetJID("full"), "msg" => $message} ;
        #establish...
        $hash->{OTR}->establish($JID->GetJID("full"));
      }          
    } else {
      return "OTR not activated. Activate by using  'attr $hash->{NAME} OTREnable 1'"; 
    }
  }
}

###################################
sub Jabber_Subcribe_To($@)
{
  my ($hash,$dst) = @_;
  if (Jabber_CheckConnection($hash)) {
    #respond with authorization so they can see our online state
    $hash->{JabberDevice}->Subscription(type=>"subscribed",
                   to=>$dst);
    #ask for authorization also so we can also see their online state (for future)
    $hash->{JabberDevice}->Subscription(type=>"subscribe",
                   to=>$dst);
  }
}

###################################
sub
Jabber_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 8)
  {
    return "Invalid number of arguments: define <name> Jabber <server> <port> <username> <password> <tls> <ssl>";
  }
  my ($tmp1,$tmp2,$server, $port, $username, $password, $tls, $ssl) = @args;
  
  $hash->{STATE} = 'Initialized';
  
  #defaults:
  $attr{$name}{PollTimer}=2;
  $attr{$name}{ResourceName}='FHEM';
  $attr{$name}{RecvWhitelist}='.*';
  $attr{$name}{OnlineStatus}='available';

  if(defined($server) && defined($port) && defined($username) && defined($password) && defined($tls) && defined($ssl))
  {    
    $hash->{helper}{server} = $server;
    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{helper}{port} = $port;
    $hash->{helper}{tls} = $tls;
    $hash->{helper}{ssl} = $ssl;
    $hash->{helper}{otractive} = 0;
    $hash->{helper}{otrJIDs} = {}; #hash
    
    if ($tls == 1 || $ssl == 1) {
       if(!eval("require Net::SSLeay;")) {
          $hash->{STATE} = "Disconnected (Module error)";
          $hash->{CONNINFO} = "Missing perl Module Net::SSLeay for TLS or SSL connection.";
          return undef;
       }
    }
    if(!eval("require Authen::SASL;")) {
       $hash->{STATE} = "Disconnected (Module error)";
       $hash->{CONNINFO} = "Missing perl Module Authen::SASL for Jabber Authentication.";
       return undef;
    }    
    Jabber_CheckConnection($hash) if($init_done);
    InternalTimer(gettimeofday()+$attr{$name}{PollTimer}, "Jabber_PollMessages", $hash,0);
    return undef;
  }
  else
  {
    return "define not correct: define <name> Jabber <server> <port> <username> <password> <tls> <ssl>";
  }  
}

###################################
sub
Jabber_UnDef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  $hash->{JabberDevice}->Disconnect();
  return undef;
}

###################################
# Attrib
sub
Jabber_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
  if ($cmd eq "set") {
    if ($aName eq "OnlineStatus") {
      if (defined($aVal) && defined($hash->{JabberDevice}) && $init_done) {
        #Send Presence type only if we do not want to be available
        if ($aVal ne "available") {
          $hash->{JabberDevice}->PresenceSend(type=>$aVal);
        } else {
          $hash->{JabberDevice}->PresenceSend();
        }
      }
    } elsif ($aName eq "MucJoin") {
      #Join the MUC
      if (defined($aVal) && defined($hash->{JabberDevice}) && $init_done) {
        Jabber_MUCs_Join($hash,$aVal);
      }
    } elsif ($aName eq "OTREnable") {
      #We dont care if Jabber is not connected already
      if (defined($aVal) && $init_done) {
        #OTR Enabled, init OTR
        if ($aVal == 1) {
          Jabber_OTR_Init($hash);
        }
      }
    } elsif ($aName eq "OTRSharedSecret") {
      #Nothing special to do will be used later..
    }
  }
	return undef;
}

##########################################
# Joins a MUC and save the nick/name for later processing
sub
Jabber_MUCs_Join($$)
{
  my ($hash,$MUCJID) = @_;
  my $name = $hash->{NAME};

  #find rooms to leave
  my %oldrooms;
  if (defined($hash->{helper}{myMUCJIDs})) {
    foreach my $oldroom (@{$hash->{helper}{myMUCJIDs}}) {
      $oldrooms{$oldroom} = 1;
    }
    
  }
  $hash->{helper}{myMUCJIDs} = ();
  
  #format of line: room@server/nick:pass,room2@server/nick2:pass
  my @rooms = split /,/, $MUCJID;
  
  foreach my $roompass (@rooms) {
    my ($room,$pass) = split /:/,$roompass;

    #add room to array 
    push @{ $hash->{helper}{myMUCJIDs} }, $room;

    #remove from rooms to leave
    if (exists($oldrooms{$room})) {
      delete $oldrooms{$room};
    }
    #create new presence object
    my $presence = Net::Jabber::Presence->new;
    $presence->SetTo($room);
    my $muc = $presence->NewChild('http://jabber.org/protocol/muc');

    if($pass) {
      $muc->SetPassword($pass);
    }
    #remove history
    my $hist = $muc->AddHistory();
    $hist->SetMaxChars(0);

    #join the room (or change the nick)
    $hash->{JabberDevice}->Send($presence);
  }

  #leave old rooms
  foreach my $room (keys %oldrooms) {
    $hash->{JabberDevice}->PresenceSend(to => $room, type => 'unavailable');
  }

}

##########################################
# Checking for waiting Messages from the Jabber Server
sub
Jabber_PollMessages($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $connectiondied = 0;
  RemoveInternalTimer($hash);
  
  if(!$init_done) {
    InternalTimer(gettimeofday()+$attr{$name}{PollTimer}, "Jabber_PollMessages", $hash,0);  
    return undef; # exit if FHEM is not ready yet.
  }
  
  if (Jabber_CheckConnection($hash)) {
    Log 0, "$hash->{NAME} Jabber PollMessages" if $debug;
    #We need to manually do what XML::Stream normally do on 'Process()' as we do not want to block it for too long.
    #They only accept a multiple of second as timeout, but that is too much if we block FHEM every second a second
    #If we find that there is something to do we call Process()
    my $doProcess = 0;
    
    #If there is something to read from the XMPP Server
    if (defined($hash->{JabberDevice}->{STREAM}->{SELECT}->can_read(0.01))) {
      $doProcess = 1;
    }
    
    #From XML::Stream - Check if a connection needs a keepalive or has been timed out.
    #Again, we would block for at least one second (every 10 seconds) if we call Process() here
    if ($doProcess == 0) {
  
      #From XML::Stream - Check if a connection needs a keepalive, and send that keepalive.
      foreach my $sid (keys(%{$hash->{JabberDevice}->{STREAM}->{SIDS}}))
      {
        next if ($sid eq "default");
        next if ($sid =~ /^server/);
        next if ($hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{status} == -1);
        if ((time - $hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{keepalive}) > 10)
        {
          $hash->{JabberDevice}->{STREAM}->IgnoreActivity($sid,1);
          $hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{status} = -1 if !defined($hash->{JabberDevice}->{STREAM}->Send($sid," "));
          if (! $hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{status} == 1)
          {
            #Keep-Alive failed - we must call Process() to handle it
            $doProcess = 1;
            Log 0, "$hash->{NAME} Keep Alive Failed" if $debug;
          }
          $hash->{JabberDevice}->{STREAM}->IgnoreActivity($sid,0);
        }
      }
      
      #From XML::Stream - Check if a connection timed out, if not respond, if it timed out, call Process()
      foreach my $sid (keys(%{$hash->{JabberDevice}->{STREAM}->{SIDS}}))
      {
        next if ($sid eq "default");
        next if ($sid =~ /^server/);

        $hash->{JabberDevice}->{STREAM}->Respond($sid)
          if (exists($hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{activitytimeout}) && 
             defined($hash->{JabberDevice}->{STREAM}->GetRoot($sid)));        
        
        $doProcess = 1
          if (exists($hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{activitytimeout}) &&
            ((time - $hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{activitytimeout}) > 10) &&
            ($hash->{JabberDevice}->{STREAM}->{SIDS}->{$sid}->{status} != 1));
      }
    }

    #We do Process() - if the connection has died we reconnect. 
    if ($doProcess == 1) {
      Log 0, "$hash->{NAME} DoProcess Call" if $debug;

      #Check for previous errors in process(), before XMPP::Connection will break down FHEM
      $connectiondied = 0;
      if (defined($hash->{JabberDevice})) {
        if (exists($hash->{JabberDevice}->{PROCESSERROR}) && ($hash->{JabberDevice}->{PROCESSERROR} == 1)) {
          #XMPP::Connection would kill FHEM now.. But we try to handle it.
          $hash->{STATE} = "Disconnected";
          $hash->{CONNINFO} = "Jabber connection error (Previous XMPP Process() error!)";
          Log 0, "$hash->{NAME} Jabber connection error (Previous XMPP Process() error!)" if $debug;
          $connectiondied = 1;
        } else {
	  #Do Process(), if it is undef, connection is gone or some other problem...
          if (!defined($hash->{JabberDevice}->Process(1))) {
            $hash->{STATE} = "Disconnected";
            $hash->{CONNINFO} = "Jabber connection died";
            Log 0, "$hash->{NAME} Jabber connection error (Process() is undef!)" if $debug;
            $connectiondied = 1;
          }
        }
      } else {
        $connectiondied = 1;
      }

      if ($connectiondied == 1) {
        #connection died
        Log 0, "$hash->{NAME} Connection died" if $debug;
        $hash->{JabberDevice} = undef;
        if (Jabber_CheckConnection($hash)) {
          #Send Presence type only if we do not want to be availible
          if ($attr{$name}{OnlineStatus} ne "available") {
            $hash->{JabberDevice}->PresenceSend(type=>$attr{$name}{OnlineStatus});
          } else {
            $hash->{JabberDevice}->PresenceSend();
          }
        }
      }
    }
    Log 0, "$hash->{NAME} Poll End" if $debug;
  }
  InternalTimer(gettimeofday()+$attr{$name}{PollTimer}, "Jabber_PollMessages", $hash,0);
}

##########################################
# Checking the Connection to the Jabber Server
sub Jabber_CheckConnection($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  if (!defined($hash->{JabberDevice})) {
    #Not defined, create a new Jabber connection
    my $dev = undef;
    if ($debug > 0) {
      $dev = new Net::Jabber::Client(debuglevel=>2,debugfile=>"/tmp/jabberdebug.log"); 
    } else {
      $dev = new Net::Jabber::Client();
    }
    $hash->{JabberDevice} = $dev;

    #Default to SSL = nonverify (0x00) - this has been changed in XML::Stream 1.23_04 and cause problems because you need a CA verify list.
    if (defined($hash->{JabberDevice}->{STREAM}->{SIDS}->{default}->{ssl_verify})) {
      $hash->{JabberDevice}->{STREAM}->{SIDS}->{default}->{ssl_verify} = 0x00;
    }

    #Default to to SRV lookups, ugly hack because older versions of XMPP::Connection dont call the respective value in XML::Stream..
    $hash->{JabberDevice}->{STREAM}->{SIDS}->{default}->{srv} = "_xmpp-client._tcp";

    #fix for weak callbacks, since Net::XMPP v.1.05 they "weaken" the reference to prevent *possible* memory problems,
    #but that causes the callbacks to not work anymore, so we unweaken it here by initializing the callbacks again :)
    $hash->{JabberDevice}->InitCallbacks();

    #For MUC we need to check if the history function is in the namespace, if not our libraries are old and we need to hack it in
    #I found this option in NET::Jabber::Owl
    if (!exists($Net::XMPP::Namespaces::NS{'__netjabber__:iq:muc:history'})) {
      $hash->{JabberDevice}->AddNamespace(ns    => '__netjabber__:iq:muc:history',
             tag   => 'history',
             xpath => {
                       MaxChars   => { path => '@maxchars' },
                       MaxStanzas => { path => '@maxstanzas' },
                       Seconds    => { path => '@seconds' },
                       Since      => { path => '@since' }
            },
            docs  => {
                      module => 'Net::Jabber',
            },
      );
      #patch the already existing muc namespace to support the history function so we can call "AddHistory" later...
      $Net::XMPP::Namespaces::NS{'http://jabber.org/protocol/muc'}->{xpath}->{History} = {
          type  => 'child',
          path  => 'history',
          child => { ns => '__netjabber__:iq:muc:history' },
          calls => ['Add', 'Get', 'Set', 'Defined' ],
          };
    }

    #Needed for Message handling:
    $hash->{JabberDevice}->SetMessageCallBacks(normal => sub { \&Jabber_INC_Message($hash,@_) }, chat => sub { \&Jabber_INC_Message($hash,@_) }, groupchat => sub { \&Jabber_INC_MUCMessage($hash,@_) } );
    #Needed if someone wants to subscribe to us and is on the WhiteList
    $hash->{JabberDevice}->SetPresenceCallBacks(
                           subscribe => sub { \&Jabber_INC_Subscribe($hash,@_) }, 
                           subscribed => sub { \&Jabber_INC_Subscribe($hash,@_) },
                           available => sub { \&Jabber_INC_Subscribe($hash,@_) },
                           unavailable => sub { \&Jabber_INC_Subscribe($hash,@_) },
                           unsubscribe => sub { \&Jabber_INC_Subscribe($hash,@_) },
                           unsubscribed => sub { \&Jabber_INC_Subscribe($hash,@_) },
                           error => sub { \&Jabber_INC_Subscribe($hash,@_) }
                         );
    if(exists($attr{$name}{OTREnable}) && $attr{$name}{OTREnable} == 1) {
      Jabber_OTR_Init($hash);
    }
  }

  if (!$hash->{JabberDevice}->Connected()) {
    
    my $connectionstatus = $hash->{JabberDevice}->Connect(
                            hostname=>$hash->{helper}{server}, 
                            port=>$hash->{helper}{port}, 
                            tls=>$hash->{helper}{tls},
                            ssl=>$hash->{helper}{ssl},
                            componentname=>$hash->{helper}{server}
                            );
                            
    if (!defined($connectionstatus)) {
      $hash->{STATE} = "Disconnected";
      $hash->{CONNINFO} = "Jabber connect error ($!)";
      return 0;
    }
    my @authresult = $hash->{JabberDevice}->AuthSend(username=>$hash->{helper}{username},
                                 password=>$hash->{helper}{password},
                                 resource=>$attr{$name}{ResourceName});

    if (!defined($authresult[0])) {
      $hash->{STATE} = "Disconnected";
      $hash->{CONNINFO} = "Jabber authentication error: Cannot Authenticate for an unknown reason. Connectionstatus is: $connectionstatus";
      return 0;      
    }

    if ($authresult[0] ne "ok") {
      $hash->{STATE} = "Disconnected";
      $hash->{CONNINFO} = "Jabber authentication error: @authresult";
      return 0;
    }    
    $hash->{STATE} = "Connected";
    $hash->{CONNINFO} = "Connected to $hash->{helper}{server} with username $hash->{helper}{username}";
    $hash->{JabberDevice}->RosterRequest();
    #join MUCs
    if (defined($attr{$name}{MucJoin})) {
      Jabber_MUCs_Join($hash,$attr{$name}{MucJoin}) if $attr{$name}{MucJoin} ne "";
    }

    #Send Presence type only if we do not want to be availible
    if ($attr{$name}{OnlineStatus} ne "available") {
      $hash->{JabberDevice}->PresenceSend(type=>$attr{$name}{OnlineStatus});
    } else {
      $hash->{JabberDevice}->PresenceSend();
    }
  }
  if (!$hash->{JabberDevice}->Connected()) {
    $hash->{STATE} = "Disconnected";
    $hash->{CONNINFO} = "Cannot connect for an unknown reason";
    return 0;
  } else {
    return 1;
  }
  
}

##########################################
# Incoming Subscribe events
sub Jabber_INC_Subscribe
{
  my($hash,$session_id, $presence) = @_;
  my $name = $hash->{NAME};
  Log 0, "$hash->{NAME} INC_Subscribe: Recv presence from: " . $presence->GetFrom() . " Type: ". $presence->GetType() if $debug;
  
  my $sender = $presence->GetFrom();
  my $JID = new Net::Jabber::JID($sender);
  my $senderShort = $JID->GetJID("base");
  my $senderLong = $JID->GetJID("full");
  my $mucRegexMatch = 0;

  #Check the Whitelist if the sender is allowed to send us.
  if (defined($attr{$name}{MucRecvWhitelist})) {
    if ($senderLong =~ m/$attr{$name}{MucRecvWhitelist}/) {
      $mucRegexMatch = 1;
    }
  }
  if ($senderShort =~ m/$attr{$name}{RecvWhitelist}/ || $mucRegexMatch) {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ matched" if $debug && $senderShort =~ m/$attr{$name}{RecvWhitelist}/;
    Log 0, "$hash->{NAME} Regex (MUC) m/$attr{$name}{MucRecvWhitelist}/ matched" if $debug && $mucRegexMatch && $senderLong =~ m/$attr{$name}{MucRecvWhitelist}/;

    if ($presence->GetType() eq "subscribe") {
      #respond with authorization so they can see our online state
      $hash->{JabberDevice}->Subscription(type=>"subscribed",
                     to=>$presence->GetFrom());
      #ask for authorization also so we can also see their online state (for future)
      $hash->{JabberDevice}->Subscription(type=>"subscribe",
                     to=>$presence->GetFrom());      
    }
  } else {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ and m/$attr{$name}{MucRecvWhitelist}/ did not match" if $debug;
  }
}

##########################################
# Incoming Private (encrypted or plaintext) Message
sub Jabber_INC_Message {
  my($hash,$session_id, $xmpp_message) = @_;
  my $name = $hash->{NAME};
  
  my $sender = $xmpp_message->GetFrom();
  my $message = $xmpp_message->GetBody();
  utf8::encode($message);
  Log 0, "$hash->{NAME} INC_Message: $sender: $message" if $debug;
  my $JID = new Net::Jabber::JID($sender);
  my $senderShort = $JID->GetJID("base");
  
  #Check the Whitelist if the sender is allowed to send us, but not the "shortname" as this will strip the sendernickname off
  if ($senderShort =~ m/$attr{$name}{RecvWhitelist}/) {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ matched" if $debug;
    
    # check to see if this is a OTR Message, if OTR is enabled
    my $otr_message_recv = 0;
    if ($hash->{helper}{otractive}) {
      if ($message =~ m/^\?OTR/) {
        #try to decrypt it
        my $discard_msg = 0;
        ($message, $discard_msg) = $hash->{OTR}->decrypt($JID->GetJID("full"), $message);
        if (!$discard_msg && $message ne "") {
          Log 0, "$hash->{NAME} INC_Message [OTR]: $sender: $message" if $debug;
          utf8::encode($message);
          $otr_message_recv = 1;
        } elsif(!$discard_msg && $message eq "") {
          Log 0, "$hash->{NAME} INC_Message [OTR]: We received an encrypted message from $senderShort but were unable to decrypt it (maybe also a control message)" if $debug;
        } 
      }
    }
    #When we have got no message after the OTR decrypt, we can leave this function.

    if (!defined($message) || $message eq "") {
      Log 0, "$hash->{NAME} Message is empty after OTR decrypt.";
      return undef;
    }

    # Some IM clients send HTML, we need
    # to convert it to plain text
    # remove tags
    $message =~ s/<(.|\n)+?>//g;
    # convert "'s
    $message =~ s/"/\\"/g;
    # trim whitespaces at beginning and end
    $message =~ s/^[\n\r\s]+|[\n\r\s]+$//g;

    #now, if the message is empty, (or was only filled with xml tags for various status infos), drop it
    if ($message ne "") {
     
      readingsBeginUpdate($hash);
      if ($otr_message_recv) {
        readingsBulkUpdate($hash,"OTRMessage","$sender: $message");
        readingsBulkUpdate($hash,"OTRLastSenderJID","$sender");
        readingsBulkUpdate($hash,"OTRLastMessage","$message");
        Log 0, "$hash->{NAME} ReadingsUpdate [OTR]: $message" if $debug;
      } else {
        readingsBulkUpdate($hash,"Message","$sender: $message");
        readingsBulkUpdate($hash,"LastSenderJID","$sender");
        readingsBulkUpdate($hash,"LastMessage","$message");
        Log 0, "$hash->{NAME} ReadingsUpdate: $message" if $debug;
      }

      readingsEndUpdate($hash, 1);
    } else {
      Log 0, "$hash->{NAME} Message was empty or full of xml tags - no readings update" if $debug;
    }
  } else {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ did not match" if $debug;
  }
}

##########################################
# Incoming MUC (Multi-User-Channel) Message
sub Jabber_INC_MUCMessage {
  my($hash,$session_id, $xmpp_message) = @_;

  my $name = $hash->{NAME};

  my $sender = $xmpp_message->GetFrom();
  my $message = $xmpp_message->GetBody();
  utf8::encode($message);
  Log 0, "$hash->{NAME} INC_MUCMessage: $sender: $message\n" if $debug;
  my $JID = new Net::Jabber::JID($sender);
  my $senderShort = $JID->GetJID("base");
  my $senderLong = $JID->GetJID("full");

  #filter MUC messages (ie subject set on join)
  #filter own messages to prevent loop
  foreach my $muc (@{$hash->{helper}{myMUCJIDs}}) {
    my $mucJID = new Net::Jabber::JID($muc);
    if ($JID->GetJID("full") eq $mucJID->GetJID("base")) {
      #room send something to us
      Log 0, "$hash->{NAME} ignoring message from room $senderShort" if $debug;
      return undef;
    } elsif ($JID->GetJID("full") eq $mucJID->GetJID("full")) {
      #we received our own message
      Log 0, "$hash->{NAME} ignoring message from ourself" if $debug;
      return undef;
    }
  }

  #Check the Whitelist if the sender is allowed to send us, but not the "shortname" as this will strip the sendernickname off
  if ($senderLong =~ m/$attr{$name}{MucRecvWhitelist}/) {
    Log 0, "$hash->{NAME} Regex (MUC) m/$attr{$name}{MucRecvWhitelist}/ matched" if $debug;

    # Some IM clients send HTML, we need
    # to convert it to plain text
    # remove tags
    $message =~ s/<(.|\n)+?>//g;
    # convert "'s
    $message =~ s/"/\\"/g;
    # trim whitespaces at beginning and end
    $message =~ s/^[\n\r\s]+|[\n\r\s]+$//g;

    #now, if the message is empty, (or was only filled with xml tags for various status infos), drop it
    if ($message ne "") {
      readingsBeginUpdate($hash);

      readingsBulkUpdate($hash,"MucMessage","$sender: $message");
      readingsBulkUpdate($hash,"MucLastSenderJID","$sender");
      readingsBulkUpdate($hash,"MucLastMessage","$message");
      Log 0, "$hash->{NAME} ReadingsUpdate: $message" if $debug;

      readingsEndUpdate($hash, 1);
    } else {
      Log 0, "$hash->{NAME} Message was empty or full of xml tags - no readings update" if $debug;
    }
  } else {
    Log 0, "$hash->{NAME} Regex (MUC) m/$attr{$name}{MucRecvWhitelist}/ did not match" if $debug;
  }
}

##########################################
# OTR Specific functions
##########################################
sub
Jabber_OTR_Init($)
{
  my ($hash) = @_;
  #check if Crypt::OTR is installed
  if(!eval("require Crypt::OTR;")) {
    $hash->{helper}{otractive} = 0;
    $hash->{STATE} = $hash->{STATE}. " (OTR Error)";
    $hash->{OTR_STATE} = "Missing perl Module Crypt::OTR, OTR disabled.";
#    $hash->{CONNINFO} = "Missing perl Module Crypt::OTR, OTR disabled.";
    return undef;
  }

  #find if the current directory is writeable to store our key, if not we will use /tmp as this is the most availible one.
  my $otrCfgDir = AttrVal('global','modpath','.')."/log";
  $otrCfgDir = "/tmp" if ! -e $otrCfgDir || ! -w $otrCfgDir;
  
  Crypt::OTR->init;
  my $otr_accname = $hash->{NAME};
  my $otr_proto = "FHEMJabber";
  my $otr = new Crypt::OTR(
        account_name  => $otr_accname,
        protocol      => $otr_proto, 
        config_dir    => $otrCfgDir, 
    );

  $hash->{OTR} = $otr;
  $hash->{OTR}->set_callback('inject' => sub { \&Jabber_OTR_inject($hash,@_) });
  $hash->{OTR}->set_callback('otr_message' => sub { \&Jabber_OTR_system_message($hash,@_) });
  $hash->{OTR}->set_callback('verified' => sub { \&Jabber_OTR_connected_verified($hash,@_) });
  $hash->{OTR}->set_callback('unverified' => sub { \&Jabber_OTR_connected_unverified($hash,@_) });
  $hash->{OTR}->set_callback('disconnect' => sub { \&Jabber_OTR_disconnected($hash,@_) });
  $hash->{OTR}->set_callback('smp_request' => sub { \&Jabber_OTR_smprequest($hash,@_) });
  

  if (! -e $otrCfgDir."/otr.private_key-".lc($otr_accname)."-".lc($otr_proto)) {
    #say we are genning Private key, and log the info, then execute it in another fork of fhem to prevent a 2h block
    Log 0, "$hash->{NAME} Generating OTR private key, be prepared that this will take 2 hours or more. Check OTR_STATE (this is a one-time task)";
    $hash->{OTR_STATE} = "Generating OTR private key...";
    if(!exists($hash->{helper}{OTR_GENKEY_PID})) {
      $hash->{helper}{OTR_GENKEY_PID} = BlockingCall("Jabber_OTR_GenPrivateKey", $hash->{NAME}."|".$otr_accname."|".$otr_proto."|".$otrCfgDir, "Jabber_OTR_GenPrivateKeyComplete");
    } else {
      $hash->{OTR_STATE} = "Still generating OTR private key. Please be patient!";
    }
  } else {
    if(!exists($hash->{helper}{OTR_GENKEY_PID})) {
      #Private key is there, everything is fine.
      Log 0, "$hash->{NAME} OTR found privatekey, good!" if $debug;
      $hash->{helper}{otractive} = 1;
      $hash->{OTR_STATE} = "OTR enabled and active";
      Log 3, "$hash->{NAME} OTR successfully enabled and active" if $debug;
    } else {
       $hash->{OTR_STATE} = "Still generating OTR private key. Please be patient!";
       Log 3, "$hash->{NAME} OTR still generating OTR private key. Please be patient!";
    }
  }
}
##########################################
# Generating private key in another process via Blocking.pm
sub Jabber_OTR_GenPrivateKey($) 
{
  my ($callargs) = @_;
  my ($hashname, $otr_accname,$otr_proto,$otrCfgDir) = split("\\|", $callargs);
  my $otr = new Crypt::OTR(
        account_name  => $otr_accname,
        protocol      => $otr_proto,
        config_dir    => $otrCfgDir, 
    );
      
  $otr->load_privkey();
  return "$hashname";
}

##########################################
# Completing generating private key
sub Jabber_OTR_GenPrivateKeyComplete($) 
{
  my ($hashname) = @_;
  return unless(defined($hashname));
  
  my $hash = $defs{$hashname};
  $hash->{OTR_STATE} = "Finished generating OTR private key. OTR is now active.";
  Log 0, "$hash->{NAME} Finished generating OTR private key";
  
  delete($hash->{helper}{OTR_GENKEY_PID});
  
  $hash->{helper}{otractive} = 1;
  log 0, "$hash->{NAME} OTR successfully enabled and active" if $debug;  
}

##########################################
# called when OTR is ready to send a message after function calls (e.g. decrypt / smp / etc).
sub Jabber_OTR_inject {
  my ($hash, $self, $account_name, $protocol, $dest_account, $message) = @_;
  Log 0, "$hash->{NAME} [OTR Inject] Inject called: $message" if $debug;
  Jabber_Set_Message($hash, $dest_account, $message); 
  #most times we await an answer, ignore the polltimer and check for new messages immediantly
  Jabber_PollMessages($hash);
}

##########################################
# called to display an OTR control message for a particular user or protocol
sub Jabber_OTR_system_message {
  my ($hash, $self, $account_name, $protocol, $other_user, $otr_message) = @_;
  Log 0, "$hash->{NAME} [OTR Sys MSG] $otr_message" if $debug;
  return 1;
}

##########################################
#called when an OTR Session has been established and has been verified by the SMP Protocol
sub Jabber_OTR_connected_verified {
  my ($hash, $self, $from_account) = @_;
  Log 0, "$hash->{NAME} [OTR] verified connection with $from_account established" if $debug;
  $hash->{helper}{otrJIDs}{$from_account}{verified} = 1;

  #after this callback, OTR sends another message before the connection is fully established, so we have to delay that again for 5 secs before sending the actual message
  my %h = (hash => $hash, from_account => $from_account);
  InternalTimer(gettimeofday()+5, "Jabber_OTRDelaySend", \%h,0);
}

##########################################
#called when an OTR Session has been established and is not verified
sub Jabber_OTR_connected_unverified {
  my ($hash, $self, $from_account) = @_;
  Log 0, "$hash->{NAME} [OTR] unverified connection with $from_account established" if $debug;
  $hash->{helper}{otrJIDs}{$from_account}{verified} = 0;

  
  #after this callback, OTR sends another message before the connection is fully established, so we have to delay that again for 5 secs before sending the actual message
  my %h = (hash => $hash, from_account => $from_account);
  InternalTimer(gettimeofday()+5, "Jabber_OTRDelaySend", \%h,0);
}

##########################################
#called when the other end want to verify our identity
sub Jabber_OTR_smprequest {
  my ($hash, $self, $account_name, $other_user) = @_;

  my $name = $hash->{NAME};
  Log 0, "$hash->{NAME} [OTR] User $other_user wants to verify our identity, sending shared secret response" if $debug;
  if (defined($attr{$name}{OTRSharedSecret})) {
    $hash->{OTR}->continue_smp($other_user, $attr{$name}{OTRSharedSecret});
  } else {
    Log 0, "$hash->{NAME} [OTR] Error, no shared secret defined, sending bogus secret" if $debug;
    $hash->{OTR}->continue_smp($other_user, "ImaBogusSecretBecauseNothingDefined");
  }
}

##########################################
# Delayed sending message after established a secure connection
# This is needed because AFTER the function "un/verified" is called
# the system is still in the process of opening the encrypted communication
# 
sub Jabber_OTRDelaySend($$) {
  my $h = shift;
  my $hash = $h->{hash};
  my $from_account = $h->{from_account};
  
  #if we have unsent messages, send them now.
  if (defined($hash->{helper}{otrJIDs}{$from_account}{waitingMsgs})) {
    foreach my $waitingMsg (@{$hash->{helper}{otrJIDs}{$from_account}{waitingMsgs}}) {
       Jabber_Set_OTRMessage($hash,$waitingMsg->{jid},$waitingMsg->{msg});
    }
  }
  
}

##########################################
#called when an OTR Session has been disconnected
sub Jabber_OTR_disconnected {
  my ($hash, $self, $from_account) = @_;
  Log 0, "$hash->{NAME} [OTR] $from_account disconnected secure channel" if $debug;
  delete ($hash->{helper}{otrJIDs}{$from_account});
}

1;


=pod
=begin html

<a name="Jabber"></a>
<h3>Jabber</h3>
<ul>
  This Module allows FHEM to connect to the Jabber Network, send and receiving messages from and to a Jabber server.<br>
  <br> 
  Jabber is another description for (XMPP) - a communications protocol for message-oriented middleware based 
  on XML and - depending on the server - encrypt the communications channels.<br> 
  For the user it is similar to other instant messaging Platforms like Facebook Chat, ICQ or Google's Hangouts 
  but free, Open Source and by default encrypted between the Jabber servers.<br>
  <br> 
  You need an account on a Jabber Server, you can find free services and more information on <a href="http://www.jabber.org/">jabber.org</a><br>
  Discuss the module in the <a href="http://forum.fhem.de/index.php/topic,18967.0.html">specific thread here</a>.<br>
  <br>
  This Module requires the following perl Modules to be installed (using SSL):<br>
  <ul>
    <li>Net::Jabber</li>
    <li>Net::XMPP</li>
    <li>Authen::SASL</li>
    <li>XML::Stream</li>
    <li>Net::SSLeay</li>
  </ul>
  <br>
  Since version 1.5 it allows FHEM also to join MUC (Multi-User-Channels) and the use of OTR for end to end encryption<br>
  If you want to use OTR you must compile and install Crypt::OTR from CPAN on your own.<br>
  <br>
  <br>
  <a name="JabberDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Jabber &lt;server&gt; &lt;port&gt; &lt;username&gt; &lt;password&gt; &lt;TLS&gt; &lt;SSL&gt;</code><br>
    <br>
    You have to create an account on a free Jabber server or setup your own Jabber server.<br>
    <br>
    Example:
    <ul>
      <code>define JabberClient1 Jabber jabber.org 5222 myusername mypassword 1 0</code>
    </ul>
    <br>
  </ul>
  <br>
  <a name="JabberSet"></a>
  <b>Set</b>
  <ul>
    <li>
      <code>set &lt;name&gt; msg &lt;username&gt; &lt;msg&gt;</code>
      <br>
      sends a message to the specified username
      <br>
      Examples:
      <ul>
        <code>set JabberClient1 msg myname@jabber.org It is working!</code><br>
      </ul>
    </li>
    <br>
    <li>
      <code>set &lt;name&gt; msgmuc &lt;channel&gt; &lt;msg&gt;</code>
      <br>
      sends a message to the specified MUC group channel
      <br>
      Examples:
      <ul>
        <code>set JabberClient1 msgmuc roomname@jabber.org Woot!</code><br>
      </ul>
    </li>
    <br>
    <li>
      <code>set &lt;name&gt; msgotr &lt;username&gt; &lt;msg&gt;</code>
      <br>
      sends an Off-the-Record encrypted message to the specified username, if no OTR session is currently established it is being tried to esablish an OTR session with the specified user.<br>
      If the user does not have OTR support the message is discarded.
      <br>
      Examples:
      <ul>
        <code>set JabberClient1 msgotr myname@jabber.org Meet me at 7pm at the place today :*</code><br>
      </ul>
    </li>
    <br>    
    <li>
      <code>set &lt;name&gt; subscribe &lt;username&gt;</code>
      <br>
      asks the username for authorization (not needed normally)
      <br>
      Example:
      <ul>
        <code>set JabberClient1 subscribe myname@jabber.org</code><br>
      </ul>
    </li>
  </ul>  
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="JabberAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="OnlineStatus"></a>
    <li><code>OnlineStatus available|unavailable</code><br>
        Sets the online status of the client, available (online in Clients) or unavailable (offline in Clients)<br>
        It is possible, on some servers, that FHEM can even recieve messages if the status is unavailable<br>
        <br>
        Default: <code>available</code>
    </li><br>
    <a name="ResourceName"></a>
    <li><code>ResourceName &lt;name&gt;</code><br>
        In XMPP/Jabber you can have multiple clients connected with the same username. <br>
        The resource name finally makes the Jabber-ID unique to each client.<br>
        Here you can define the resource name.<br>
        <br>
        Default: <code>FHEM</code>
    </li><br>
    <a name="PollTimer"></a>
    <li><code>PollTimer &lt;seconds&gt;</code><br>
        This is the interval in seconds at which the jabber server get polled.<br>
        Every interval the client checks if there are messages waiting and checks the connection to the server.<br>
        Don't set it over 10 seconds, as the client could get disconnected.<br>
         <br>
        Default: <code>2</code>
    </li><br>    
    <a name="RecvWhitelist"></a>
    <li><code>RecvWhitelist &lt;Regex&gt;</code><br>
        Only if the Regex match, the client accepts and interpret the message. Everything else will be discarded.<br>
        <br>
        Default: <code>.*</code><br>
        Examples:<br>
        <ul>
          <code>myname@jabber.org</code><br>
          <code>(myname1@jabber.org|myname2@xmpp.de)</code><br>
        </ul>
    </li><br>
    <a name="MucJoin"></a>
    <li><code>MucJoin channel1@server.com/mynick[:password]</code><br>
        Allows you to join one or more MUC's (Multi-User-Channel) with a specific Nick and a optional Password<br>
        <br>
        Default: empty (no messages accepted)<br>
        Examples:<br>
        <ul>
          Join a channel: <code>channel1@server.com/mynick</code><br>
          Join more channels: <code>channel1@server.com/mynick,channel2@server.com/myothernick</code><br>
          Join a channel with a password set: <code>channel1@server.com/mynick:password</code><br>
        </ul>
    </li><br>  
    <a name="MucRecvWhitelist"></a>
    <li><code>MucRecvWhitelist &lt;Regex&gt;</code><br>
        Same as RecvWhitelist but for MUC: Only if the Regex match, the client accepts and interpret the message. Everything else will be discarded.<br>
        <br>
        Default: empty (no messages accepted)<br>
        Examples:<br>
        <ul>
          All joined channels allowed: <code>.*</code><br>
          Specific channel allowed only: <code>mychannel@jabber.org</code><br>
          Specific Nick in channel allowed only: <code>mychannel@jabber.org/NickOfFriend</code><br>
        </ul>
    </li><br>  
    <a name="OTREnable"></a>
    <li><code>OTREnable 1|0</code><br>
        Enabled the use of Crypt::OTR for end to end encryption between a device and FHEM<br>
        You must have Crypt::OTR installed and a private key is being generated the first time you enable this option<br>
        Key generation can take more than 2 hours on a quiet system but will not block FHEM instead it will inform you if it has been finished<br>
        Key generation is a one-time-task<br>
         <br>
        Default: empty (OTR disabled)
    </li><br>  
    <a name="OTRSharedSecret"></a>
    <li><code>OTRSharedSecret aSecretKeyiOnlyKnow@@*</code><br>
        Optional shared secret to allow the other end to start a trust verification against FHEM with this shared key.<br>
        If the user starts a trust verification process the fingerprint of the FHEM private key will be saved at the user's device and the connection is trusted.<br>
        This will allow to inform the user if the private key has changed (ex. in Man-in-the-Middle attacks)<br>
         <br>
        Default: empty, please define a shared secret on your own.
    </li><br>  
  </ul>
  <br>
  <a name="JabberReadings"></a>
  <b>Generated Readings/Events:</b>
  <ul>
     <li>Private Messages
      <ul>
        <li><b>Message</b> - Complete message including JID and text</li>
        <li><b>LastMessage</b> - Only text portion of the Message</li>
        <li><b>LastSenderJID</b> - Only JID portion of the Message</li>
      </ul>
     </li><br>
     <li>Encrypted Private Messages (if OTREnable=1)
      <ul>
        <li><b>OTRMessage</b> - Complete decrypted message including JID and text</li>
        <li><b>OTRLastMessage</b> - Only text portion of the Message</li>
        <li><b>OTRLastSenderJID</b> - Only JID portion of the Message</li>
      </ul>
     </li><br>
     <li>MUC Room Messages  (if MUCJoin is set)
      <ul>
        <li><b>MucMessage</b> - Complete message including room's JID and text</li>
        <li><b>MucLastMessage</b> - Only text portion of the Message</li>
        <li><b>MucLastSenderJID</b> - Only JID portion of the Message</li>
      </ul>
     </li>
  </ul>
  <br>
  <a name="JabberNotes"></a>
  <b>Author's Notes:</b>
    <ul>
      <li>You can react and reply on incoming private messages with a notify like this:<br>
        <pre><code>define Jabber_Notify notify JabberClient1:Message.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msg ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>
      <li>You can react and reply on MUC messages with a notify like this, be aware that the nickname in $lastsender is stripped off in the msgmuc function<br>
        <pre><code>define Jabber_Notify notify JabberClient1:MucMessage.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msgmuc ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>
      <li>You can react and reply on OTR private messages with a notify like this:<br>
        <pre><code>define Jabber_Notify notify JabberClient1:OTRMessage.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msgotr ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>
    </ul>    
</ul>
=end html
=begin html_DE

<a name="Jabber"></a>
<h3>Jabber</h3>
<ul>
  Dieses Modul verbindet sich mit dem Jabber Netzwerk, sendet und empf&auml;ngt Nachrichten von und zu einem Jabber Server.<br>
  <br> 
  Jabber ist eine andere Beschreibung f&uuml;r "XMPP", ein Kommunikationsprotokoll f&uuml;r Nachrichtenorientierte "middleware", basierend
  auf XML.<br>
  Fester bestandteil des Protokolls ist die Verschl&uuml;sselung zwischen Client und Server.<br> 
  F&uuml;r den Benutzer ist es &auml;hnlich anderer Chat-Plattformen wie zum Beispiel dem facebook Chat, ICQ oder Google Hangouts - 
  jedoch frei Verf&uuml;gbar, open Source und normalerweise Verschl&uuml;sselt (was Serverabh&auml;ngig ist).<br>
  <br> 
  F&uuml;r dieses Modul brauchst du einen Account auf einem Jabber Server. Kostenlose accounts und Server findet man unter <a href="http://www.jabber.org/">jabber.org</a><br>
  Diskussionen zu diesem Modul findet man im <a href="http://forum.fhem.de/index.php/topic,18967.0.html">FHEM Forum hier</a>.<br>
  <br>
  Dieses Modul ben&ouml;tigt die folgenden Perl Module (inkl. SSL M&ouml;glichkeit)<br>
  <ul>
    <li>Net::Jabber</li>
    <li>Net::XMPP</li>
    <li>Authen::SASL</li>
    <li>XML::Stream</li>
    <li>Net::SSLeay</li>
  </ul>
  <br>
  Seit Version 1.5 kann dieses Modul in Multi-User-Channel (sogenannte MUC) beitreten und Off-the-Record (OTR) Ende-zu-Ende Verschl&uuml;sselung benutzen.<br>
  Wenn du OTR benutzen m&ouml;chtest musst du dir Crypt::OTR von CPAN selbst installieren.<br>
  OTR ist nochmal ein zus&auml;tzlicher Sicherheitsrelevater Punkt, da die Kommunikation wirklich von Endger&auml;t zu FHEM verschl&uuml;sselt wird und man sich nicht auf die Jabber Server Transportverschl&uuml;sselung verlassen muss.<br>
  <br>
  <br>
  <a name="JabberDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Jabber &lt;server&gt; &lt;port&gt; &lt;username&gt; &lt;password&gt; &lt;TLS&gt; &lt;SSL&gt;</code><br>
    <br>
    Du ben&ouml;tigst nat&uuml;rlich echte Accountdaten.<br>
    <br>
    Beispiel:
    <ul>
      <code>define JabberClient1 Jabber jabber.org 5222 myusername mypassword 1 0</code>
    </ul>
    <br>
  </ul>
  <br>
  <a name="JabberSet"></a>
  <b>Set</b>
  <ul>
    <li>
      <code>set &lt;name&gt; msg &lt;username&gt; &lt;msg&gt;</code>
      <br>
      Sendet eine Nachricht "msg" an den Jabberuser "username"
      <br>
      Beispiel:
      <ul>
        <code>set JabberClient1 msg myname@jabber.org It is working!</code><br>
      </ul>
    </li>
    <br>
    <li>
      <code>set &lt;name&gt; msgmuc &lt;channel&gt; &lt;msg&gt;</code>
      <br>
      Sendet eine Nachricht "msg" an dieJabber-MUC-Gruppe "channel".<br>
      Dabei wird ein eventuell mitgegebener Nickname von "channel" entfernt, so kann man direkt das Reading LastMessageJID benutzen.<br>
      <br>
      Beispiel:
      <ul>
        <code>set JabberClient1 msgmuc roomname@jabber.org Woot!</code><br>
      </ul>
    </li>
    <br>
    <li>
      <code>set &lt;name&gt; msgotr &lt;username&gt; &lt;msg&gt;</code>
      <br>
      Sendet eine OTR verschl&uuml;sselte Nachricht an den "username", wenn keine aktive OTR Sitzung aufgebaut ist, wird versucht eine aufzubauen.<br>
      Wenn der Empf&auml;nger OTR nicht versteht, wird die Nachricht verworfen, d.h. sie wird auf keinen Fall im Klartext &uuml;bertragen.
      <br>
      Beispiel:
      <ul>
        <code>set JabberClient1 msgotr myname@jabber.org Wir sehen uns heute um 18:00 Uhr :*</code><br>
      </ul>
    </li>
    <br> 
    <li>
      <code>set &lt;name&gt; subscribe &lt;username&gt;</code>
      <br>
      Fr&auml;gt eine Authorisierung beim "username" an (normalerweise wird das nicht ben&ouml;tigt)
      <br>
      Beispiel:
      <ul>
        <code>set JabberClient1 subscribe myname@jabber.org</code><br>
      </ul>
    </li>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="JabberAttr"></a>
  <b>Attribute</b>
  <ul>
    <a name="OnlineStatus"></a>
    <li><code>OnlineStatus available|unavailable</code><br>
        Setzt den Online-status, ob der Client anderen gegen&uuml;ber Online ist (available) oder Offline erscheint (unavailable)<br>
        Es ist m&ouml;glich dass einige Server eingehende Nachrichten trotzdem FHEM zustellen obwohl er "unavailable" ist<br>
        <br>
        Standard: <code>available</code>
    </li><br>
    <a name="ResourceName"></a>
    <li><code>ResourceName &lt;name&gt;</code><br>
        In der Jabber-Welt kann ein Client mit einem Usernamen &ouml;fter mit einem Server verbunden sein (z.b. Handy, Computer, FHEM). <br>
        Der "resource name" ergibt die finale Jabber-ID und macht die verschiedenen Verbindungen einzigartig (z.B. bios@jabber.org/FHEM).<br>
        Hier kannst du den "resource name" setzen.<br>
        <br>
        Standard: <code>FHEM</code>
    </li><br>
    <a name="PollTimer"></a>
    <li><code>PollTimer &lt;seconds&gt;</code><br>
        Dies ist der Intervall in der &uuml;berpr&uuml;ft wird ob neue Nachrichten zur Verarbeitung beim Jabber Server anstehen.<br>
        Ebenfalls wird hiermit die Verbindung zum Server &uuml;berpr&uuml;ft (Timeouts, DSL Disconnects etc.).<br>
        Setze es nicht &uuml;ber 10 Sekunden, die Verbindung kann sonst die ganze Zeit getrennt werden, Sie wird zwar wieder aufgebaut, aber nach 10 Sekunden brechen die meisten Server die Verbindung automatisch ab.<br>
         <br>
        Standard: <code>2</code>
    </li><br>      
    <a name="RecvWhitelist"></a>
    <li><code>RecvWhitelist &lt;Regex&gt;</code><br>
        Nur wenn die Jabber-ID einer privaten empfangenen Nachricht auf diese Regex zutrifft, akzeptiert FHEM die Nachricht und gibt sie an Notifys weiter. Alles andere wird verworfen.<br>
        <br>
        Standard: <code>.*</code><br>
        Beispiele:<br>
        <ul>
          <code>myname@jabber.org</code><br>
          <code>(myname1@jabber.org|myname2@xmpp.de)</code><br>
        </ul>
    </li><br>
    <a name="MucJoin"></a>
    <li><code>MucJoin channel1@server.com/mynick[:passwort]</code><br>
        Tritt dem MUC mit dem spezifizierten Nickname und dem optionalem Passwort bei.<br>
        <br>
        Standard: nicht definiert<br>
        Beispiele:<br>
        <ul>
          Einen Raum betreten: <code>channel1@server.com/mynick</code><br>
          Mehrere R&auml;ume betreten: <code>channel1@server.com/mynick,channel2@server.com/myothernick</code><br>
          Einen Raum mit Passwort betreten: <code>channel1@server.com/mynick:password</code><br>
        </ul>
    </li><br>  
    <a name="MucRecvWhitelist"></a>
    <li><code>MucRecvWhitelist &lt;Regex&gt;</code><br>
        Selbe funktion wie RecvWhitelist, aber f&uuml;r Gruppenr&auml;ume: Nur wenn die Regex zutrifft, wird die Nachricht verarbeitet. Alles andere wird ignoriert.<br>
        <br>
        Standard: nicht definiert (keine Nachricht wird akzeptiert)<br>
        Beispiele:<br>
        <ul>
          Alle Nachrichten aller betretenen R&auml;ume erlauben: <code>.*</code><br>
          Alle Nachrichten bestimmter betretenen R&auml;ume erlauben: <code>mychannel@jabber.org</code><br>
          Nur bestimmte User in bestimmten betretenen R&auml;umen erlauben: <code>mychannel@jabber.org/NickOfFriend</code><br>
        </ul>
    </li><br>  
    <a name="OTREnable"></a>
    <li><code>OTREnable 1|0</code><br>
        Schaltet die Verschl&uuml;sselungsfunktionen von Crypt::OTR f&uuml;r sichere Ende-zu-Ende Kummunikation in FHEM an oder aus.<br>
        Es muss zwangsl&auml;ufig daf&uuml;r Crypt::OTR installiert sein.<br>
        <i>Ein Privater Schl&uuml;ssel wird bei Erstbenutzung generiert, das kann mehr als 2 Stunden dauern!</i><br>
        Daf&uuml;r ist das eine einmalige Sache und FHEM wird dadurch nicht blockiert. Im Device sieht man im OTR_STATE wenn der Private Schl&uuml;ssel fertig ist.<br>
        Erst danach ist OTR aktiv.<br>
         <br>
        Default: nicht definiert (OTR deaktiviert)
    </li><br>  
    <a name="OTRSharedSecret"></a>
    <li><code>OTRSharedSecret aSecretKeyiOnlyKnow@@*</code><br>
        Optionales geheimes Passwort, dass man vom Endger&auml;t an FHEM schicken kann um zu beweisen, dass es sich tats&auml;chlich um FHEM handelt und nicht um einen
        Hacker der sich (z.b. bei dem Internetprovider) zwischengeschaltet hat. 
        Normalerweise bekommt das Endger&auml;t eine Warnung wenn sich an einer bereits verifizierten Verbindung etwas ge&auml;ndert hat.<br>
        Diese Warnung sollte man dann sehr ernst nehmen.
         <br>
        Default: nicht definiert, setze hier dein geheimes Passwort.
    </li><br>  
        
  
  </ul>
  <br>
  <a name="JabberReadings"></a>
  <b>Generierte Readings/Events:</b>
  <ul>
     <li>Privat Nachrichten
      <ul>
        <li><b>Message</b> - Komplette Nachricht inkl. JID und Text</li>
        <li><b>LastMessage</b> - Nur der Textteil der Nachricht</li>
        <li><b>LastSenderJID</b> - Nur die Sender-JID der Nachricht</li>
      </ul>
     </li><br>
     <li>Verschl&uuml;sselte Private Nachrichten (wenn OTREnable=1)
      <ul>
        <li><b>OTRMessage</b> - Komplette entschl&uuml;sselte Nachricht inkl. JID und Text</li>
        <li><b>OTRLastMessage</b> - Nur der Textteil der Nachricht</li>
        <li><b>OTRLastSenderJID</b> - Nur die Sender-JID der Nachricht</li>
      </ul>
     </li><br>
     <li>MUC Raum Nachrichten (wenn MUCJoin gesetzt ist)
      <ul>
        <li><b>MucMessage</b> - Komplette Nachricht (Raumname/Nickname und Text)</li>
        <li><b>MucLastMessage</b> - Nur der Textteil der Nachricht</li>
        <li><b>MucLastSenderJID</b> - Nur die Sender-JID der Nachricht</li>
      </ul>
     </li>
  </ul>
  <br>
  <a name="JabberNotes"></a>
  <b>Notizen des Entwicklers:</b>
    <ul>
      <li>Mit folgendem Notify-Beispiel kannst du auf eingehende Nachrichten reagieren, dieses Beispiel schickt das Reading "Temperatur" des Sensors "BU_Temperatur" bei jeder ankommenden Nachricht an den Sender zur&uuml;ck:<br>
        <pre><code>define Jabber_Notify notify JabberClient1:Message.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msg ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>
      <li>Auf MUC Nachrichten l&auml;sst sich folgend reagieren, Augenmerk darauf legen dass der Nickname aus $lastsender in der msgmuc Funktion entfernt wird, damit die Nachricht an den Raum geht<br>
        <pre><code>define Jabber_Notify notify JabberClient1:MucMessage.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msgmuc ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>
      <li>Auf OTR Nachrichten wird reagiert, wie auf normale private Nachrichten auch, jedoch wird mit der msgotr Funktion geantwortet:<br>
        <pre><code>define Jabber_Notify notify JabberClient1:OTRMessage.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msgotr ". $lastsender . " Temp: ".$temperature);
}
        </code></pre>
      </li>      
    </ul>    
</ul>
=end html_DE
=cut
