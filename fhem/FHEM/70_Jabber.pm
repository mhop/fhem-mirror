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
# Version: 1.0 - 2014-04-10
#
# Changelog:
# v1.0 2014-04-10 Stable Release - Housekeeping & Add to SVN
# v0.3 2014-03-19 Fixed SetPresence() & Added extensive debugging capabilities by setting $debug to 1
# v0.2 2014-01-28 Added SSL option in addition to TLS 
# v0.1 2014-01-18 Initial Release
##############################################################################
# You will need the following perl Module and all it's depencies for this to work: 
# Net::Jabber
# For using the SSL features and to connect securly to a Jabber server you also need this perl Module:
# Authen::SASL
#
# The recommended debian packages to be installed are these: 
# libnet-jabber-perl libnet-xmpp-perl libxml-stream-perl libdigest-sha1-perl libauthen-sasl-perl
#
# Have Phun!
#
package main;

use strict;
use warnings;
use utf8;
use Time::HiRes qw(gettimeofday);
use Net::Jabber;


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
  $hash->{AttrList}   = "dummy:1,0 loglevel:0,1,2,3,4,5 OnlineStatus:available,unavailable PollTimer RecvWhitelist ResourceName ".$readingFnAttributes;
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

  if ($cmd eq 'subscribe')
  {
    return Jabber_Subcribe_To($hash, @args);
  }

}

###################################
sub Jabber_Set_Message($@)
{
  my ($hash,$dst,@tmpMsg) = @_;
  my $message = join(" ", @tmpMsg);
  if (Jabber_CheckConnection($hash)) {
    $hash->{JabberDevice}->MessageSend(to=>$dst,
                      subject=>"",
                      body=>$message,
                      type=>"chat",
                      priority=>10);  
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
	  }
	}
	return undef;
}

###################################
sub
Jabber_PollMessages($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
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

    #We do Process() and if the connection died we reconnect. 
    if ($doProcess == 1) {
      Log 0, "$hash->{NAME} DoProcess Call" if $debug;
      if (!defined($hash->{JabberDevice}->Process(1))) {
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
###################################
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
    
    #Needed for Message handling:
    $hash->{JabberDevice}->SetMessageCallBacks(normal => sub { \&Jabber_INC_Message($hash,@_) }, chat => sub { \&Jabber_INC_Message($hash,@_) } );
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

  }

  if (!$hash->{JabberDevice}->Connected()) {
    my $connectionstatus = $hash->{JabberDevice}->Connect(
                            hostname=>$hash->{helper}{server}, 
                            port=>$hash->{helper}{port}, 
                            tls=>$hash->{helper}{tls},
			    ssl=>$hash->{helper}{ssl}
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
sub Jabber_INC_Subscribe
{
  my($hash,$session_id, $presence) = @_;
  my $name = $hash->{NAME};
  Log 0, "$hash->{NAME} INC_Subscribe: Recv Prsence from: " . $presence->GetFrom() . " Type: ". $presence->GetType() if $debug;
  
  my $sender = $presence->GetFrom();
  my $JID = new Net::Jabber::JID($sender);
  my $senderShort = $JID->GetJID("base");
  
  #Check the Whitelist if the sender is allowed to send us.
  if ($senderShort =~ m/$attr{$name}{RecvWhitelist}/) {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ matched" if $debug;

    if ($presence->GetType() eq "subscribe") {
      #respond with authorization so they can see our online state
      $hash->{JabberDevice}->Subscription(type=>"subscribed",
                     to=>$presence->GetFrom());
      #ask for authorization also so we can also see their online state (for future)
      $hash->{JabberDevice}->Subscription(type=>"subscribe",
                     to=>$presence->GetFrom());      
    }
  } else {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ did not match" if $debug;
  }

}
##########################################
sub Jabber_INC_Message {
  my($hash,$session_id, $xmpp_message) = @_;
  my $name = $hash->{NAME};
  
  my $sender = $xmpp_message->GetFrom();
  my $message = $xmpp_message->GetBody();
  Log 0, "$hash->{NAME} INC_Message: $sender: $message\n" if $debug;
  my $JID = new Net::Jabber::JID($sender);
  my $senderShort = $JID->GetJID("base");
  
  #Check the Whitelist if the sender is allowed to send us.
  if ($senderShort =~ m/$attr{$name}{RecvWhitelist}/) {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ matched" if $debug;
    
    readingsBeginUpdate($hash);
    # Some IM clients send HTML, we need
    # to convert it to plain text
    # remove tags
    $message =~ s/<(.|\n)+?>//g;
    # convert "'s
    $message =~ s/"/\"/g;
    
    
    readingsBulkUpdate($hash,"Message","$sender: $message");
    readingsBulkUpdate($hash,"LastSenderJID","$sender");
    readingsBulkUpdate($hash,"LastMessage","$message");
    
    my $response = "\n";
    my $checkfordel = substr($message, 0, 3);
    Log 0, "$hash->{NAME} ReadingsUpdate: $message\n" if $debug;
    
    
    #$response = $message;
    #if (($response eq "\n") || $response eq "") {
    #$response = $response."Nothing to display for command todo $message."
    #}
    
    #  $hash->{JabberDevice}->MessageSend(to=>$sender,body=>$response,type=>'chat');
    readingsEndUpdate($hash, 1);
  } else {
    Log 0, "$hash->{NAME} Regex m/$attr{$name}{RecvWhitelist}/ did not match" if $debug;
  }
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
  but free, Open Source and normally encrypted.<br>
  <br> 
  You need an account on a Jabber Server, you can find free services and more information on <a href="http://www.jabber.org/">jabber.org</a><br>
  Discuss the module in the <a href="http://forum.fhem.de/index.php/topic,16215.0.html">specific thread here</a>.<br>
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
    <li>OnlineStatus <code>available|unavailable</code><br>
        Sets the online status of the client, available (online in Clients) or unavailable (offline in Clients)<br>
        It is possible, on some servers, that FHEM can even recieve messages if the status is unavailable<br>
        <br>
        Default: <code>available</code>
    </li><br>
    <a name="ResourceName"></a>
    <li>ResourceName <code>&lt;name&gt;</code><br>
        In XMPP/Jabber you can have multiple clients connected with the same username. <br>
        The resource name finally makes the Jabber-ID unique to each client.<br>
        Here you can define the resource name.<br>
        <br>
        Default: <code>FHEM</code>
    </li><br>
    <a name="RecvWhitelist"></a>
    <li>RecvWhitelist <code>&lt;Regex&gt;</code><br>
        Only if the Regex match, the client accepts and interpret the message. Everything else will be discarded.<br>
        <br>
        Default: <code>.*</code><br>
        Examples:<br>
        <ul>
          <code>myname@jabber.org</code><br>
          <code>(myname1@jabber.org|myname2@xmpp.de)</code><br>
        </ul>
    </li><br>
    <a name="PollTimer"></a>
    <li>PollTimer <code>&lt;seconds&gt;</code><br>
        This is the interval in seconds at which the jabber server get polled.<br>
        Every interval the client checks if there are messages waiting and checks the connection to the server.<br>
        Don't set it over 10 seconds, as the client could get disconnected.<br>
         <br>
        Default: <code>2</code>
    </li><br>    
  </ul>
  <br>
  <a name="JabberEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
  <br>
  <a name="JabberNotes"></a>
  <b>Author's Notes:</b>
    <ul>
      <li>You can react and reply on incoming messages with a notify like this:<br>
        <pre><code>define Jabber_Notify notify JabberClient1:Message.* {
  my $lastsender=ReadingsVal("JabberClient1","LastSenderJID","0");
  my $lastmsg=ReadingsVal("JabberClient1","LastMessage","0");
  my $temperature=ReadingsVal("BU_Temperatur","temperature","0");
  fhem("set JabberClient1 msg ". $lastsender . " Temp: ".$temperature);
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
  Diskussionen zu diesem Modul findet man im <a href="http://forum.fhem.de/index.php/topic,16215.0.html">FHEM Forum hier</a>.<br>
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
    <li>OnlineStatus <code>available|unavailable</code><br>
        Setzt den Online-status, ob der Client anderen gegen&uuml;ber Online ist (available) oder Offline erscheint (unavailable)<br>
        Es ist m&ouml;glich dass einige Server eingehende Nachrichten trotzdem FHEM zustellen obwohl er "unavailable" ist<br>
        <br>
        Standard: <code>available</code>
    </li><br>
    <a name="ResourceName"></a>
    <li>ResourceName <code>&lt;name&gt;</code><br>
        In der Jabber-Welt kann ein Client mit einem Usernamen &ouml;fter mit einem Server verbunden sein (z.b. Handy, Computer, FHEM). <br>
        Der "resource name" ergibt die finale Jabber-ID und macht die verschiedenen Verbindungen einzigartig (z.B. bios@jabber.org/FHEM).<br>
        Hier kannst du den "resource name" setzen.<br>
        <br>
        Standard: <code>FHEM</code>
    </li><br>
    <a name="RecvWhitelist"></a>
    <li>RecvWhitelist <code>&lt;Regex&gt;</code><br>
        Nur wenn die Jabber-ID einer empfangenen Nachricht auf diese Regex zutrifft, akzeptiert FHEM die Nachricht und gibt sie an Notifys weiter. Alles andere wird verworfen.<br>
        <br>
        Standard: <code>.*</code><br>
        Beispiele:<br>
        <ul>
          <code>myname@jabber.org</code><br>
          <code>(myname1@jabber.org|myname2@xmpp.de)</code><br>
        </ul>
    </li><br>
    <a name="PollTimer"></a>
    <li>PollTimer <code>&lt;seconds&gt;</code><br>
        Dies ist der Intervall in der &uuml;berpr&uuml;ft wird ob neue Nachrichten zur Verarbeitung beim Jabber Server anstehen.<br>
        Ebenfalls wird hiermit die Verbindung zum Server &uuml;berpr&uuml;ft (Timeouts, DSL Disconnects etc.).<br>
        Setze es nicht &uuml;ber 10 Sekunden, die Verbindung kann sonst die ganze Zeit getrennt werden, Sie wird zwar wieder aufgebaut, aber nach 10 Sekunden brechen die meisten Server die Verbindung automatisch ab.<br>
         <br>
        Standard: <code>2</code>
    </li><br>    
  </ul>
  <br>
  <a name="JabberEvents"></a>
  <b>Generierte events:</b>
  <ul>
     N/A
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
    </ul>    
</ul>
=end html_DE
=cut
