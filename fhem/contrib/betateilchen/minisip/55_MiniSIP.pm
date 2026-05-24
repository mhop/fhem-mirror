#  $Id: 55_minisip.pm 31259 2026-05-22 07:08:28Z betateilchen $

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

sub ::MiniSIP_Initialize { goto &Initialize}

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
=item helper
=item summary    build SIP endpoint to receive and answer SIP requests
=item summary_DE erstellt einen SIP Endpunkt f&uuml;r SIP Nachrichten
=begin html

<a id="MiniSIP"></a>
<h3>MiniSIP</h3>
<br><br>
This FHEM module allows you to create a SIP endpoint capable of  
processing incoming SIP messages and events.<br>
This enables you to trigger specific actions by sending some codes from 
a registered VoIP phone.<br>
<br>
Two methods are available for receiving such codes:
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
			Used to backup all registered peers into FHEM keystore.<br>
			<br>
			Will be called automatically on FHEM shutdown.
		</li><br>
		<a id="MiniSIP-set-restore_peers"></a>
		<li><b>restore_peers</b><br>
			Used to restore peers from FHEM keystore.<br>
			A peer will only be restored if
			<ul>
			<li>- last registration not expired</li>
			<li>- peer not registered already</li>
			</ul><br>
			Will be called automatically on FHEM start.
		</li><br>
		<a id="MiniSIP-set-sendmsg"></a>
		<li><b>sendmsg</b><br>
			Will be <br>
			documented later.
		</li>
		<br/>
  </ul>
  <br>

  <a id="MiniSIP-get"></a>
  <b>Get</b>
  <br><br>
  <ul>
		<a id="MiniSIP-get-peers"></a>
		<li>peers [table|json]<br>
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
    <li><b>logFullMessage</b> 0|1<br>
      Decides wether the full SIP message will be logged,<br>
      otherwise only the infoline will be logged.<br>
      Default: 0 (short message)<br>
      <br>
      Note: logging will use loglevel 4 except for errors.
    </li><br>

    <a id="MiniSIP-attr-showFullMessage"></a>
    <li><b>showFullMessage</b> 0|1<br>
      Decides wether the full SIP message will be shown in reading,<br>
      otherwise only the infoline will be stored in a reading.<br>
      Default: 0 (short message)
    </li><br>

    <a id="MiniSIP-attr-parseFn"></a>
    <li><b>parseFn</b><br>
      Defines the name of an alternative function used to parse<br>
      incoming MESSAGE requests.<br> This function should return<br>
      a valid value for the reading "input".<br>
      <br>
      <b>The attribut value should contain a package name!</b><br>
      e.g. a function named 'sipParser' in 99_myUtils.pm should be given as<br>
      <br>
      <code>attr &lt;device&gt; parseFn main::sipParser</code><br>
    </li><br>

  </ul>
  <br>

  <b>Readings</b>
  <br><br>
  <ul>
    <li><b>input</b><br>
      Contains the input value found in either INVITE or MESSAGE request.
    </li><br>
    <li><b>state</b><br>
      Contains the input value found in either INVITE or MESSAGE request.
    </li><br>
    <li><b>REGISTER | INVITE | MESSAGE | SUBSCRIBE | BYE</b><br>
      Contains the SIP message from corresponding request either<br>
      in short or full format, depending on attr 'showFullMessage'.<br>
    </li><br>
  </ul>
  <br>

</ul>

=end html
=cut

