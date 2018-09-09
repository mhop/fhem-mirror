# $Id$
####################################################################################################
#
#	12_HProtocolTank.pm
#
#	Copyright: Stephan Eisler
#	Email: fhem.dev@hausautomatisierung.co
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package main;

sub HProtocolTank_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}          = "HProtocolTank_Define";
  $hash->{ParseFn}        = "HProtocolTank_Parse";
  $hash->{FingerprintFn}  = "HProtocolTank_Fingerprint";
  $hash->{Match}          = "^[a-zA-Z0-9_]+ [a-zA-Z0-9_]+ [+-]*[0-9]+([.][0-9]+)?";
  $hash->{AttrList}       = $readingFnAttributes;
}

sub HProtocolTank_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> HProtocolTank <gateway_name>" if(int(@a) != 3);

  my $name = $a[0];
  my $gateway = $a[2];

  if (!$hash->{IODev}) {
    AssignIoPort($hash, $gateway);
  }

  if (defined($hash->{IODev})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  if (defined($hash->{IODev})) {
      $iodev = $hash->{IODev}->{NAME};
  }

  $hash->{STATE} = "Initialized";

  $attr{$name}{room} = "HProtocol";

  # TODO This has to be updated when renaming the device.
  $modules{HProtocolTank}{defptr}{$name} = $hash;

  # TODO A Tank has to be unregistered when it's removed or renamed.
  HProtocolGateway_RegisterTank($hash);

  return undef;
}

sub HProtocolTank_Parse($$) {
  my ($iohash, $message) = @_;

  # $message = "<tankName> <reading> <value>"
  my @array = split("[ \t][ \t]*", $message);
  my $tankName = @array[0];
  my $reading = @array[1];
  my $value = @array[2];

  my $hash = $modules{HProtocolTank}{defptr}{$tankName};

  readingsSingleUpdate($hash, $reading, $value, 1);

	return $tankName;
}

sub HProtocolTank_Fingerprint($$) {
  # this subroutine is called before running Parse to check if
  # this message is a duplicate message. Refer to FHEM Wiki.
}

1;


=pod
=item summary   devices communicating via the HProtocolGateway 
=begin html

<a name="HProtocolTank"></a>
<h3>HProtocolTank</h3>
<ul>
    The HProtocolTank is a fhem module defines a device connected to a HProtocolGateway.

  <br /><br /><br />

  <a name="HProtocolTank"></a>
  <b>Define</b>
  <ul>
    <code>define tank01 HProtocolTank HProtocolGateway<br />
          setreading tank01 hID 01<br />
    </code>
    <br />

    Defines an HProtocolTank connected to a HProtocolGateway.<br /><br />

  </ul><br />

  <a name="HProtocolTank"></a>
  <b>Readings</b>
  <ul>
    <li>hID<br />
    01 - 99 Tank Number / Tank Address</li>
    <li>ullage<br />
    0..999999 Ullage in litres</li>
    <li>filllevel<br />
    0..99999 Fill level in cm</li>
    <li>volume<br />
    0..999999 Volume in litres</li>
    <li>volume_15C<br />
    0..999999 Volume in litres at 15 °C</li>
    <li>temperature<br />
    -999 - +999 Temperature in °C</li>
    <li>waterlevel<br />
    0..9999 Water level in mm</li>
    <li>probe_offset<br />
    -9999 - +9999 Probe offset in mm)</li>
    <li>version<br />
    00..999 Software version</li>
    <li>error<br />
    0..9 00.. Probe error</li>
  </ul><br />


</ul><br />

=end html

=cut
