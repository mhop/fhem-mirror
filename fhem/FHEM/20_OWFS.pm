################################################################
#
#  Copyright notice
#
#  (c) 2008 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
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
################################################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use OW;

my %models = (
  "DS1420"     => "",
  "DS9097"     => "",
);
my %fc = (
  "1:DS9420"   => "01",
  "2:DS1420"   => "81",
  "3:DS1820"   => "10",
);

my %gets = (
  "address"     => "",
  "alias"       => "",
  "crc8"        => "",
  "family"      => "",
  "id"          => "",
  "locator"     => "",
  "present"     => "",
#  "r_address"   => "",
#  "r_id"        => "",
#  "r_locator"   => "",
  "type"        => "",
);

##############################################
sub
OWFS_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn}    = "OWFS_Write";
  $hash->{Clients}    = ":OWTEMP:";

# Normal devices
  $hash->{DefFn}      = "OWFS_Define";
  $hash->{UndefFn}    = "OWFS_Undef";
  $hash->{GetFn}      = "OWFS_Get";
  #$hash->{SetFn}      = "OWFS_Set";
  $hash->{AttrList}   = "IODev do_not_notify:1,0 dummy:1,0 temp-scale:C,F,K,R ".
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6"; }

#####################################
sub
OWFS_Get($$)
{
  my ($hash,@a) = @_;

  return "argument is missing @a" if (@a != 2);
  return "Passive Adapter defined. No Get function implemented."
    if(!defined($hash->{OW_ID}));
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));

  my $ret = OWFS_GetData($hash,$a[1]);

  return "$a[0] $a[1] => $ret"; 
}

#####################################
sub
OWFS_GetData($$)
{
  my ($hash,$query) = @_;
  my $name = $hash->{NAME};
  my $path = $hash->{OW_PATH};
  my $ret = undef;
  
  $ret = OW::get("/uncached/$path/$query");
  if ($ret) {
    # strip spaces
    $ret =~ s/^\s+//g;
    Log 4, "OWFS $name $query $ret";
    $hash->{READINGS}{$query}{VAL} = $ret;
    $hash->{READINGS}{$query}{TIME} = TimeNow();
    return $ret;
  } else {
    return undef;
  }
}

#####################################
sub
OWFS_DoInit($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $path;
  my $ret;

  if (defined($hash->{OWFS_ID})) {
    $path = $hash->{OW_FAMILY}.".".$hash->{OWFS_ID};
 
    foreach my $q (sort keys %gets) {
      $ret = OWFS_GetData($hash,$q);
    }
  }

  $hash->{STATE} = "Initialized" if (!$hash->{STATE});  
  return undef;
}

#####################################
sub
OWFS_Define($$)
{
  my ($hash, $def) = @_;

  # define <name> OWFS <owserver:port> <model> <id>
  # define foo OWFS 127.0.0.1:4304 DS1420 93302D000000

  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> OWFS <owserver:port> <model> [<id>]"
    if (@a < 2 && int(@a) > 5);

  my $name  = $a[0];
  my $dev   = $a[2];
#  return "wrong device format: use ip:port"
#    if ($device !~ m/^(.+):(0-9)+$/);

  my $model = $a[3];
  return "Define $name: wrong model: specify one of " . join ",", sort keys %models
    if (!grep { $_ eq $model } keys %models);

  if (@a > 4) {
    my $id     = $a[4];
    return "Define $name: wrong ID format: specify a 12 digit value"
      if (uc($id) !~ m/^[0-9|A-F]{12}$/); 

    $hash->{FamilyCode} = \%fc;
    my $fc = $hash->{FamilyCode};
    if (defined ($fc)) {
      foreach my $c (sort keys %{$fc}) {
        if ($c =~ m/$model/) {
          $hash->{OW_FAMILY} = $fc->{$c};
        }
      }
    }
    delete ($hash->{FamilyCode});
    $hash->{OW_ID} = $id;
    $hash->{OW_PATH} = $hash->{OW_FAMILY}.".".$hash->{OW_ID};
  }

  $hash->{STATE} = "Defined";

  # default temperature-scale: C
  # C: Celsius, F: Fahrenheit, K: Kelvin, R: Rankine
  $attr{$name}{"temp-scale"} = "C";

  if ($dev eq "none") {
    $attr{$name}{dummy} = 1;
    Log 1, "OWFS device is none, commands will be echoed only";
    return undef;
  }

  Log 3, "OWFS opening OWFS device $dev";

  my $po;
  $po = OW::init($dev);

  return "Can't connect to $dev: $!" if(!$po);

  Log 3, "OWFS opened $dev for $name";

  $hash->{DeviceName} = $dev;
  $hash->{STATE}="";
  my $ret  = OWFS_DoInit($hash);
  return undef;
}

#####################################
sub
OWFS_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if (defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash) {
      my $lev = ($reread_active ? 4 : 2);
      Log GetLogLevel($name,$lev), "deleting port for $d";
      delete $defs{$d}{IODev};
    }
  }
  return undef;
}

1;

=pod
=begin html

<a name="OWFS"></a>
<h3>OWFS</h3>
<ul>
  OWFS is a suite of programs that designed to make the 1-wire bus and its
  devices easily accessible. The underlying priciple is to create a virtual
  filesystem, with the unique ID being the directory, and the individual
  properties of the device are represented as simple files that can be read
  and written.<br><br>

  Note: You need the owperl module from
  <a href="http://owfs.org/index.php?page=owperl">http://owfs.org/</a>.
  <br><br>

  <a name="OWFSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWFS &lt;owserver-ip:port&gt; &lt;model&gt; [&lt;id&gt;]</code>
    <br><br>

    Define a 1-wire device to communicate with an OWFS-Server.<br><br>

    <code>&lt;owserver-ip:port&gt;</code>
    <ul>
      IP-address:port from OW-Server.
    </ul>
    <code>&lt;model&gt;</code>
    <ul>
      Define the <a href="#owfs_type">type</a> of the input device.
      Currently supportet: <code>DS1420, DS9097 (for passive Adapter)</code>
    </ul>
    <code>&lt;id&gt;</code>
    <ul>
      Corresponding to the <a href="#owfs_id">id</a> of the input device. Only for active Adapter.
      <br><br>
    </ul>

    Note:<br>
    If the <code>owserver-ip:port</code> is called <code>none</code>, then
    no device will be opened, so you can experiment without hardware attached.<br><br>

    Example:
    <ul>
      <code>#define an active Adapter:<br>
      define DS9490R OWFS 127.0.0.1:4304 DS1420 93302D000000</code><br>
    </ul>
    <br>
    <ul>
      <code>#define a passive Adapter:<br>
      define DS9097 OWFS 127.0.0.1:4304 DS9097</code><br>
    </ul>
    <br>
  </ul>

  <b>Set</b> <ul>N/A</ul><br>

  <a name="OWFSget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of (not supported by passive Devices e.g. DS9097):<br>
    <ul>
      <li><a name="owfs_address"></a>
        <code>address</code> (read-only)<br>
        The entire 64-bit unique ID. address starts with the family code.<br>
        Given as upper case hexidecimal digits (0-9A-F).
      </li>
      <li><a name="owfs_crc8"></a>
        <code>crc8</code> (read-only)<br>
        The 8-bit error correction portion. Uses cyclic redundancy check. Computed
        from the preceeding 56 bits of the unique ID number.<br>
        Given as upper case hexidecimal digits (0-9A-F).
      </li>
      <li><a name="owfs_family"></a>
        <code>family</code> (read-only)<br>
        The 8-bit family code. Unique to each type of device.<br>
        Given as upper case hexidecimal digits (0-9A-F).
      </li>
      <li><a name="owfs_id"></a>
        <code>id</code> (read-only)<br>
        The 48-bit middle portion of the unique ID number. Does not include the
        family code or CRC.<br>
        Given as upper case hexidecimal digits (0-9A-F).
      </li>
      <li><a name="owfs_locator"></a>
        <code>locator</code> (read-only)<br>
        Uses an extension of the 1-wire design from iButtonLink company that
        associated 1-wire physical connections with a unique 1-wire code. If
        the connection is behind a Link Locator the locator will show a unique
        8-byte number (16 character hexidecimal) starting with family code FE.<br>
        If no Link Locator is between the device and the master, the locator
        field will be all FF.
      </li>
      <li><a name="owfs_present"></a>
        <code>present</code> (read-only)<br>
        Is the device currently present on the 1-wire bus?
      </li>
      <li><a name="owfs_type"></a>
        <code>type</code> (read-only)<br>
        Part name assigned by Dallas Semi. E.g. DS2401 Alternative packaging
       (iButton vs chip) will not be distiguished.
      </li>
      <br>
    </ul>
    Examples:
    <ul>
      <code>get DS9490R type</code><br>
      <code>DS9490R type => DS1420</code><br><br>
      <code>get DS9490R address</code><br>
      <code>DS9490R address => 8193302D0000002B</code>
    </ul>
    <br>
  </ul>

  <a name="OWFSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="owfs_temp-scale"></a>
      temp-scale<br>
      Specifies the temperature-scale unit:
      <ul>
        <li><code>C</code><br>
          Celsius. This is the default.</li>
        <li><code>F</code><br>
          Fahrenheit</li>
        <li><code>K</code><br>
          Kelvin</li>
        <li><code>R</code><br>
          Rankine</li>
      </ul>
    </li>
  </ul>
  <br>

</ul>

=end html
=cut
