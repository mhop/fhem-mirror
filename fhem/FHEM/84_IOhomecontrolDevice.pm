# $Id$

##############################################################################
#
#     84_IOhomecontrolDevice.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
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
##############################################################################

package main;

use strict;
use warnings;

sub IOhomecontrolDevice_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}       = "IOhomecontrolDevice_Define";
    $hash->{SetFn}       = "IOhomecontrolDevice_Set";
    $hash->{parseParams} = 1;
    $hash->{AttrList}    = "setCmds " . $readingFnAttributes;
}

sub IOhomecontrolDevice_Define($$) {

    # define <name> IOhomecontrolDevice <interface>
    my ( $hash, $argref, undef ) = @_;

    my @def = @{$argref};
    if ( $#def != 2 ) {
        my $msg = "wrong syntax: define <name> IOhomecontrolDevice <interface>";
        Log 2, $msg;
        return $msg;
    }

    my $name   = $def[0];
    my $master = $def[2];

    my $interface = $defs{$master};
    $hash->{"INTERFACE"} = $interface;
    if ( !defined($interface) || $interface->{TYPE} ne "IOhomecontrol" ) {
        return "No such IOhomecontrol interface:  $master";
    }
    else { return; }
}

sub IOhomecontrolDevice_getSetCmds($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $attr = AttrVal( $name, "setCmds", "" );
    my ( undef, $setCmds ) = parseParams( $attr, "," );
    return $setCmds;
}

sub IOhomecontrolDevice_runSceneByIdCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name      = $hash->{NAME};
    my $interface = $hash->{INTERFACE};
    my $id        = $httpParams->{params}{id};
    my $sn        = $interface->{fhem}{".scenes"}->{$id};
    if ( defined($err) ) {
        Log3 $hash, 2,
"IOhomecontrolDevice $name: running scene id $id, name $sn, failed ($err)";
    }
    else {
        Log3 $hash, 5,
"IOhomecontrolDevice $name: running scene id $id, name $sn, completed";
        readingsSingleUpdate( $hash, "state", $sn, 1 );
    }
}

sub IOhomecontrolDevice_Set($$$) {
    my ( $hash, $argsref, undef ) = @_;

    my @a = @{$argsref};
    return "set needs at least one parameter" if ( @a < 2 );

    my $name = shift @a;
    my $cmd  = shift @a;

    my $setCmds = IOhomecontrolDevice_getSetCmds($hash);
    my $usage   = "Unknown argument $cmd, choose one of scene"
      . join( " ", ( keys %{$setCmds} ) );
    if ( exists( $setCmds->{$cmd} ) ) {
        readingsSingleUpdate( $hash, "state", $cmd, 1 );
        my $subst = $setCmds->{$cmd};
        Log3 $hash, 5,
          "IOhomecontrolDevice $name: substitute set command $cmd by $subst";
        ( $argsref, undef ) = parseParams($subst);
        @a   = @{$argsref};
        $cmd = shift @a;
    }

    if ( $cmd eq "scene" ) {
        if ($#a) {
            return "Command scene needs exactly one argument.";
        }
        else {
            my $id        = $a[0];
            my $interface = $hash->{INTERFACE};
            return IOhomecontrol_setScene( $interface, $id,
                \&IOhomecontrolDevice_runSceneByIdCallback );
        }
    }
    else {
        return $usage;
    }

    return undef;

}

#####################################

1;

=pod
=item device
=item summary control IOhomecontrol devices via IOhomecontrol interface
=item summary_DE IOhomecontrol-Ger&auml;te mittels IOhomecontrol-Interface steuern
=begin html

<a name="IOhomecontrolDevice"></a>
<h3>IOhomecontrolDevice</h3>
<ul>

  <a name="IOhomecontrolDevicedefine"></a>
  <b>Define</b><br><br>
  <ul>
    <code>define &lt;name&gt; IOhomecontrolDevice &lt;interface&gt; </code><br><br>

    Defines an IOhomecontrol device. <code>&lt;interface&gt;</code> is the
    name of the IOhomecontrol interface device (gateway) that is used to
    communicate with the IOhomecontrol devices.
    <br><br>

    Example:
    <ul>
      <code>define shutter1 IOhomecontrolDevice myKLF200</code><br>
    </ul>
    <br><br>
  </ul>

  <a name="IOhomecontrolDeviceset"></a>
  <b>Set</b><br><br>
  <ul>
    <code>set &lt;name&gt; scene &lt;id&gt;</code>
    <br><br>
    Runs the scene identified by <code>&lt;id&gt;</code> which can be either
    the numeric id of the scene or the scene's name.
    <br><br>
    Examples:
    <ul>
      <code>set shutter1 scene 1</code><br>
      <code>set shutter1 scene "3.dz.roll2 100%"</code><br>
    </ul>
    <br>
    Scene names with blanks must be enclosed in double quotes.
    <br><br>
  </ul>

  <a name="IOhomecontrolDeviceattr"></a>
  <b>Attributes</b>
  <br>
  <br>
  <ul>
    <li>setCmds: a comma-separated list of set command definitions.
    Every definition is of the form <code>&lt;shorthand&gt;=&lt;command&gt;</code>. This defines a new single-word command <code>&lt;shorthand&gt</code> as a substitute for <code>&lt;command&gt;</code>.<br>
    Example: <code>attr shutter1 setCmds up=scene "3.dz.roll2 100%",down=scene "3.dz.roll2 0%"</code><br>
    Substituted commands (and only these) are shown in the state reading.
    This is useful in conjunction with the <code>devStateIcon</code> attribute,
    e.g. <code>attr shutter1 devStateIcon down:shutter_closed up:shutter_open</code>.</li>
    <br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  <b>Full example</b>
  <ul><code>
  define myKLF200 IOhomecontrol KLF200 velux.local /opt/fhem/etc/veluxpw.txt<br>
  attr myKLF200 verbose 5<br>
  attr myKLF200 logTraffic 1<br>
  <br>
  define shutter1 IOhomecontrolDevice myKLF200<br>
  attr shutter1 setCmds up=scene "3.dz.roll2 0%",down=scene "3.dz.roll2 100%"<br>
  attr shutter1 webCmd up:down<br>
  attr shutter1 devStateIcon down:shutter_closed up:shutter_open<br>
  </code></ul>
  <br><br>

</ul>

=end html
=cut
