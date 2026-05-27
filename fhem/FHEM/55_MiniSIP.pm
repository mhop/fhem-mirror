#  $Id$

################################################################
#
#  Copyright notice
#
#  (c) 2026 - today
#  Copyright: betateilchen (betateilchen dot quantentunnel dot de)
#  All rights reserved
#
#  This program is part of FHEM; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
#  See the GNU General Public License V2 for more details.
#
################################################################

package FHEM::MiniSIP;

use strict;
use warnings;

require FHEM::Core::MiniSIP;

sub ::MiniSIP_Initialize { goto &Initialize }

sub Initialize($) {
  my ($hash) = @_;
  $hash->{parseParams} = 1;
  $hash->{DefFn}       = \&FHEM::Core::MiniSIP::Define;
  $hash->{ReadFn}      = \&FHEM::Core::MiniSIP::Read;
  $hash->{SetFn}       = \&FHEM::Core::MiniSIP::Set;
  $hash->{GetFn}       = \&FHEM::Core::MiniSIP::Get;
#  $hash->{AttrFn}      = \&FHEM::Core::MiniSIP::Attr;
  $hash->{ShutdownFn}  = \&FHEM::Core::MiniSIP::Shutdown;
  $hash->{UndefFn}     = \&FHEM::Core::MiniSIP::Undef;
  $hash->{DeleteFn}    = \&FHEM::Core::MiniSIP::Delete;

  $hash->{AttrList}    = ""
                        ."logFullMessage:0,1 "
                        ."showFullMessage:0,1 "
                        ."parseFn "
                        ."disable:1,0 "
                        ."disabledForIntervals "
                        .$::readingFnAttributes;
}

1;


__END__

=pod
=item summary    build SIP endpoint to receive and answer SIP requests
=item summary_DE erstellt einen SIP Endpunkt f&uuml;r SIP Nachrichten
=begin html

<a id="MiniSIP"></a>
<h3>MiniSIP</h3>
<br><br>
This FHEM module allows you to create a SIP endpoint capable of  
processing incoming SIP messages and events.<br>
It enables you to trigger specific actions by sending some codes from 
a registered VoIP phone.<br>
Furthermore you can send a SIP message to a registered peer.<br>
<br>
Two methods are available for receiving data from sip peers:
<ul>
  <li><b>Method 1:</b> Simply dialing a 'number' e.g. **55<br>
  This message arrives as a SIP INVITE and generates a value for the 'input' reading.<br>
  This method is vendor-independent.</li><br>
<br>
  <li><b>Method 2:</b> Snom SIP phones can also send SIP MESSAGES<br>
  when a function key — previously configured for this purpose — is pressed on the phone.<br>
  This MESSAGE also generates a value for the 'input' reading.<br>
  In this case, the value is always the immutable ID of the specific function key.</li><br>
</ul>

The 'input' reading can be evaluated and processed using 'notify', 'DOIF', <br> 
or any other event-processing mechanisms in FHEM.<br>
<br>
The SIP endpoint performs no authentication whatsoever.<br>
This means that the username and password used for registration<br>
can be chosen arbitrarily.<br>
Every incoming SIP request of the types REGISTER, INVITE, MESSAGE, SUBSCRIBE, BYE<br>
is answered with "200 OK" and subsequently processed.<br>
<br>
<b>Prerequisits</b><br>
<br>
This module needs additional perl module Net::SIP (libnet-sip-perl).<br>
All other dependencies should be fulfilled in a standard FHEM installation.<br>

<ul>
  <br>
  <a id="MiniSIP-define"></a>
  <b>Define</b>
  <br><br>
  <ul>
    <code>define &lt;name&gt; MiniSIP port=&lt;port&gt; from=&lt;from-uri&gt;</code>
    <br><br>
  </ul>
  <br>

  <a id="MiniSIP-set"></a>
  <b>Set</b>
  <br><br>
  <ul>
		<a id="MiniSIP-set-backup_peers"></a>
		<li><b>backup_peers</b><br>
		  <br>
			<code>set &lt;deviceName&gt; backup_peers</code><br>
			<br>
			Used to backup all registered peers into FHEM keystore.<br>
			<br>
			Will be called automatically on FHEM shutdown.
		</li>
		<br>
		<a id="MiniSIP-set-restore_peers"></a>
		<li><b>restore_peers</b><br>
		  <br>
			<code>set &lt;deviceName&gt; restore_peers</code><br>
			<br>
			Used to restore peers from FHEM keystore.<br>
			A peer will only be restored if
			<ul>
			<li>- last registration not expired</li>
			<li>- peer not registered already</li>
			</ul><br>
			Will be called automatically on FHEM start.
		</li>
		<br>
		<a id="MiniSIP-set-sendmsg"></a>
		<li><b>sendmsg</b><br>
		  <br>
			<code>set &lt;deviceName&gt; sendmsg peer=&lt;peerName&gt; type=&lt;data|base64&gt; msg=&lt;payload&gt;</code><br>
			<br>

      This command allows you to send a SIP message to a SIP peer.<br>
      Two options are available for passing the message:<br>
      <br>
      <b>1. type=data (highly recommended!)</b><br>
      <br>
      In this case, the generated SIP message is stored in the `%data` hash<br>
      within FHEM, and the key used to retrieve the data from the hash<br>
      is passed as a parameter.<br>
      <br>
      <b>Example:</b><pre><code>
# --- code snippet start

my $res = Net::SIP::Response->new(
  200,
  'OK',
  { 'Via'            => [ $req->get_header('Via') ],
    'From'           => $req->get_header('From'),
    ... add more data here ...
    'Content-Length' => '0',
  }
);

my $uuid = createUniqueId();
$data{$uuid} = $res->as_string;
fhem("set &lt;deviceName&gt; sendmsg peer=$peer type=data msg=$uuid");

# --- code snippet end
</code></pre>
<br>
      <b>2. type=base64</b><br>
      <br>
      In this case, the generated SIP message is transferred<br>
      as a base64-coded string without newLine<br>
      <br>
      <b>Example:</b><pre><code>
# --- code snippet start

my $res = Net::SIP::Response->new(
  200,
  'OK',
  { 'Via'            => [ $req->get_header('Via') ],
    'From'           => $req->get_header('From'),
    ... add more data here ...
    'Content-Length' => '0',
  }
);

# use base64 for transfer with "set ... sendmsg"
# Important: trailing == must not be transferred!
#
my $msg = encode_base64($res->as_string,"");
$msg =~ s/=//g;
fhem("set &lt;deviceName&gt; sendmsg peer=$peer type=base64 msg=$msg");

# --- code snippet end
</code></pre>
		</li>
		<br/>
  </ul>
  <br>

  <a id="MiniSIP-get"></a>
  <b>Get</b>
  <br><br>
  <ul>
		<a id="MiniSIP-get-peer"></a>
		<li><b>peer</b><br>
		  <br>
			<code>get &lt;deviceName&gt; peer &lt;peerName&gt;</code><br>
			<br>
			Returns peer data for a given peer if the peer exists.
		</li>
		<br>
		<a id="MiniSIP-get-peers"></a>
		<li><b>peers</b><br>
		  <br>
			<code>get &lt;deviceName&gt; peers [table|json]</code><br>
			<br>
			Returns the list of all registered peers.
		</li>
  </ul>
  <br>

  <a id="MiniSIP-attr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><a href="#disable">disable</a></li><br>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li><br>

    <a id="MiniSIP-attr-logFullMessage"></a>
    <li><b>logFullMessage</b><br>
		  <br>
			<code>attr &lt;deviceName&gt; logFullMessage 0|1</code><br>
			<br>
      Decides wether the full SIP message will be logged,<br>
      otherwise only the infoline will be logged.<br>
      Default: 0 (short message)<br>
      <br>
      Note: logging will use loglevel 4 except for errors.
    </li>
    <br>
    <a id="MiniSIP-attr-showFullMessage"></a>
    <li><b>showFullMessage</b><br>
		  <br>
			<code>attr &lt;deviceName&gt; showFullMessage 0|1</code><br>
			<br>
      Decides wether the full SIP message will be shown in reading,<br>
      otherwise only the infoline will be stored in a reading.<br>
      Default: 0 (short message)
    </li>
    <br>
    <a id="MiniSIP-attr-parseFn"></a>
    <li><b>parseFn</b><br>
		  <br>
			<code>attr &lt;deviceName&gt; parseFn &lt;functionName&gt;</code><br>
			<br>
      Defines the name of an alternative function used to parse<br>
      incoming MESSAGE requests. This function should return <br>
      a valid value for the reading "input".<br>
      <br>
      <b>The attribut value should contain a package name!</b><br>
      e.g. a function named 'sipParser' in 99_myUtils.pm should be given as<br>
      <br>
      <code>attr &lt;device&gt; parseFn main::sipParser</code><br>
    </li>
    <br>
  </ul>
  <br>

  <b>Readings</b>
  <br><br>
  <ul>
    <li><b>input</b><br>
      <br>
      Contains the input value found in either INVITE or MESSAGE request.
    </li><br>
    <li><b>state</b><br>
      <br>
      Contains some more or less useful informations about current state.
    </li><br>
    <li><b>REGISTER | INVITE | MESSAGE | SUBSCRIBE | BYE</b><br>
      <br>
      Contains the SIP message from corresponding request either<br>
      in short or full format, depending on attr 'showFullMessage'.
    </li><br>
    <br>
  </ul>
  <br>
  <br>
</ul>

=end html
=cut

