# $Id$
##############################################################################
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

use SetExtensions;

sub readingsProxy_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsProxy_Define";
  $hash->{NotifyFn} = "readingsProxy_Notify";
  $hash->{UndefFn}  = "readingsProxy_Undefine";
  $hash->{SetFn}    = "readingsProxy_Set";
  $hash->{GetFn}    = "readingsProxy_Get";
  $hash->{AttrList} = "disable:1 "
                      ."getList "
                      ."setList "
                      ."getFn setFn valueFn "
                      .$readingFnAttributes;
}

sub
readingsProxy_updateDevices($)
{
  my ($hash) = @_;

  my %list;

  delete $hash->{DEVICE};
  delete  $hash->{READING};

  my @params = split(" ", $hash->{DEF});
  if( defined($defs{$params[0]}) ) {
    $list{$params[0]} = 1;
    $hash->{DEVICE} = $params[0];
    $hash->{READING} = $params[1];
  }

  $hash->{CONTENT} = \%list;

  readingsProxy_update($hash, undef);
}

sub readingsProxy_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsProxy <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

  $hash->{STATE} = 'Initialized';

  readingsProxy_updateDevices($hash);

  return undef;
}

sub readingsProxy_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub
readingsProxy_update($$)
{
  my ($hash,$value) = @_;
  my $name = $hash->{NAME};

  my $DEVICE = $hash->{DEVICE};
  my $READING = $hash->{READING};

  $value = ReadingsVal($DEVICE,$READING,undef) if( !defined($value) );

  my $value_fn = AttrVal( $name, "valueFn", "" );
  if( $value_fn =~ m/^{.*}$/ ) {
    my $VALUE = $value;

    my $value_fn = eval $value_fn;
    Log3 $name, 3, $name .": valueFn: ". $@ if($@);
    return undef if( !defined($value_fn) );
    $value = $value_fn if( $value_fn );
  }

  readingsSingleUpdate($hash, "state", $value, 1)
}

sub
readingsProxy_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
    readingsProxy_updateDevices($hash);
    return undef;
  }
  elsif( grep(m/^REREADCFG$/, @{$dev->{CHANGED}}) ) {
    readingsProxy_updateDevices($hash);
    return undef;
  }

  return if( AttrVal($name,"disable", 0) > 0 );

  return if($dev->{NAME} eq $name);

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if( $dev->{NAME} eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);
      if( defined($hash->{CONTENT}{$old}) ) {

        $hash->{DEF} =~ s/(\s*)$old((:\S+)?\s*)/$1$new$2/g;
      }
      readingsProxy_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name((:\S+)?\s*)/ /g;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;
      }
      readingsProxy_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      readingsProxy_updateDevices($hash);
    } else {
      next if( $dev->{NAME} ne $hash->{DEVICE} );

      my @parts = split(/: /,$s);
      my $reading = shift @parts;
      my $value   = join(": ", @parts);

      $reading = "" if( !defined($reading) );
      $value = "" if( !defined($value) );
      if( $value eq "" ) {
        $reading = "state";
        $value = $s;
      }
      next if( $reading ne $hash->{READING} );

      readingsProxy_update($hash, $value);
    }
  }

  return undef;
}

sub
readingsProxy_Set($@)
{
  my ($hash, $name, @a) = @_;

  return "no set value specified" if(int(@a) < 1);
  my $setList = AttrVal($name, "setList", "");
  $setList = getAllSets($hash->{DEVICE}) if( $setList eq "%PARENT%" );
  return SetExtensions($hash,$setList,$name,@a) if(!$setList || $a[0] eq "?");

  my $found = 0;
  foreach my $set (split(" ", $setList)) {
    if( "$set " =~ m/^${a[0]}[ :]/ ) {
      $found = 1;
      last;
    } elsif( "$set " =~ m/^state[ :]/ ) {
      $found = 1;
      last;
    }
  }
  return SetExtensions($hash,$setList,$name,@a) if( !$found );

  my $v = join(" ", @a);
  my $set_fn = AttrVal( $hash->{NAME}, "setFn", "" );
  if( $set_fn =~ m/^{.*}$/ ) {
    my $DEVICE = $hash->{DEVICE};
    my $READING = $hash->{READING};
    my $CMD = $a[0];
    my $ARGS = join(" ", @a[1..$#a]);

    my $set_fn = eval $set_fn;
    Log3 $name, 3, $name .": setFn: ". $@ if($@);
    return undef if( !defined($set_fn) );
    $v = $set_fn if( $set_fn );
  }

  Log3 $name, 4, "$name: set hash->{DEVICE} $v";
  return CommandSet(undef,"$hash->{DEVICE} ".$v);

  return undef;
}

sub
readingsProxy_Get($@)
{
  my ($hash, $name, @a) = @_;

  return "no get value specified" if(int(@a) < 1);
  my $getList = AttrVal($name, "getList", "");
  $getList = getAllGets($hash->{DEVICE}) if( $getList eq "%PARENT%" );
  return "Unknown argument ?, choose one of $getList" if(!$getList || $a[0] eq "?");

  my $found = 0;
  foreach my $get (split(" ", $getList)) {
    if( "$get " =~ m/^${a[0]}[ :]/ ) {
      $found = 1;
      last;
    }
  }
  return "Unknown argument $a[0], choose one of $getList" if(!$found);

  my $v = join(" ", @a);
  my $get_fn = AttrVal( $hash->{NAME}, "getFn", "" );
  if( $get_fn =~ m/^{.*}$/ ) {
    my $DEVICE = $hash->{DEVICE};
    my $READING = $hash->{READING};
    my $CMD = $a[0];
    my $ARGS = join(" ", @a[1..$#a]);

    my ($get_fn,$direct_return) = eval $get_fn;
    Log3 $name, 3, $name .": getFn: ". $@ if($@);
    return $get_fn if($direct_return);
    return undef if( !defined($get_fn) );
    $v = $get_fn if( $get_fn );
  }

  Log3 $name, 4, "$name: get hash->{DEVICE} $v";
  return CommandGet(undef,"$hash->{DEVICE} ".$v);

  return undef;
}

1;

=pod
=begin html

<a name="readingsProxy"></a>
<h3>readingsProxy</h3>
<ul>
  Makes (a subset of) a reading from one device available as a new device.<br>
  This can be used to map channels from 1-Wire, EnOcean or SWAP devices to independend devices that
  can have state,icons and webCmd different from the parent device and can be used in a floorplan.
  <br><br>
  <a name="readingsProxy_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsProxy &lt;device&gt;:&lt;reading&gt;</code><br>
    <br>

    Examples:
    <ul>
      <code>define myProxy readingsProxy myDS2406:latch.A</code><br>
    </ul>
  </ul><br>

  <a name="readingsProxy_Set"></a>
    <b>Set</b>
    <ul>
    </ul><br>

  <a name="readingsProxy_Get"></a>
    <b>Get</b>
    <ul>
    </ul><br>

  <a name="readingsProxy_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>disable<br>
        1 -> disable notify processing. Notice: this also disables rename and delete handling.</li>
      <li>getList<br>
        Space separated list of commands, which will be returned upon "get name ?",
        so the FHEMWEB frontend can construct a dropdown.
        %PARENT% will result in the complete list of commands from the parent device.
        get commands not in this list will be rejected.</li>
      <li>setList<br>
        Space separated list of commands, which will be returned upon "set name ?",
        so the FHEMWEB frontend can construct a dropdown and offer on/off switches.
        %PARENT% will result in the complete list of commands from the parent device.
        set commands not in this list will be rejected.
        Example: attr proxyName setList on off</li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li>getFn<br>
        perl expresion that will return the get command forwarded to the parent device.
        has access to $DEVICE, $READING, $CMD and $ARGS.<br>
        undef -> do nothing<br>
        ""    -> pass-through<br>
        (<value>,1) -> directly return <value>, don't call parent getFn<br>
        everything else -> use this instead</li>
      <li>setFn<br>
        perl expresion that will return the set command forwarded to the parent device.
        has access to $DEVICE, $READING, $CMD and $ARGS.<br>
        undef -> do nothing<br>
        ""    -> pass-through<br>
        everything else -> use this instead<br>
        Examples:<br>
          <code>attr myProxy setFn {($CMD eq "on")?"off":"on"}</code>
        </li>
      <li>valueFn<br>
        perl expresion that will return the value that sould be used as state.
        has access to $DEVICE, $READING, $CMD and $VALUE.<br>
        undef -> do nothing<br>
        ""    -> pass-through<br>
        everything else -> use this instead<br>
        Examples:<br>
          <code>attr myProxy valueFn {($VALUE == 0)?"off":"on"}</code>
      </li>
    </ul><br>
</ul>

=end html
=cut
