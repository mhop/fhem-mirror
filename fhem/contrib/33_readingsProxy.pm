# $Id: 33_readingsProxy.pm 16299 2018-03-01 08:06:55Z justme1968 $
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

use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
use vars qw($init_done);
use Data::Dumper;
sub Log($$);
sub Log3($$$);

sub readingsProxy_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsProxy_Define";
  $hash->{NotifyFn} = "readingsProxy_Notify";
  $hash->{UndefFn}  = "readingsProxy_Undefine";
  $hash->{SetFn}    = "readingsProxy_Set";
  $hash->{GetFn}    = "readingsProxy_Get";
  $hash->{AttrFn}   = "readingsProxy_Attr";
  $hash->{AttrList} = "disable:1 "
                      ."getList "
                      ."setList "
                      ."getFn:textField-long setFn:textField-long valueFn:textField-long "
                      .$readingFnAttributes;
}

sub
readingsProxy_setNotifyDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $regexp= join("|", (keys %{$hash->{PROXIES}})) // "";
  #main::Debug "readingsProxy_setNotifyDev $name $regexp";
  if( $regexp ne "" ) {
    notifyRegexpChanged($hash,"(global|$regexp)");
  } else {
    notifyRegexpChanged($hash,'');
  }
}

sub
readingsProxy_splitProxyDef($)
{
  my ($proxydef) = @_;

  my ($device, $reading, $proxy) = split(":", $proxydef);
  $reading //= "state";
  $proxy //= $device . "_" . $reading;
  return ($device, $reading, $proxy);
}

sub
readingsProxy_updateDevices($)
{
  my ($hash) = @_;

  my %proxies;
  my @proxydefs = split(" ", $hash->{DEF});
  foreach my $proxydef (@proxydefs) {
    my ($device, $reading, $proxy) = readingsProxy_splitProxyDef($proxydef);
    if( defined($defs{$device}) ) {
      $proxies{$device}{$reading} = $proxy;
      $hash->{primaryProxy} //= $proxydef; # the first proxy is for state, set, get and value
    }
  }
  InternalTimer(gettimeofday(), "readingsProxy_setNotifyDev", $hash);
  $hash->{PROXIES} = \%proxies;
  readingsProxy_updateAll($hash);
}

sub readingsProxy_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsProxy <device>:<reading>[:<proxy>] ..."  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

  $hash->{STATE} = 'Initialized';

  delete $hash->{primaryProxy};
  readingsProxy_updateDevices($hash) if( $init_done );

  return undef;
}

sub readingsProxy_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub
readingsProxy_readingsSingleUpdate($$$) {
  my ($hash, $reading, $value) = @_;
  my $name = $hash->{NAME};
  readingsSingleUpdate($hash, $reading, $value, 1);
}

sub
readingsProxy_update($$$$)
{
  my ($hash, $devname, $reading, $value) = @_;
  my $name = $hash->{NAME};

  my $proxy = $hash->{PROXIES}{$devname}{$reading};
  #main::Debug "readingsProxy_update $name:$proxy from $devname:$reading";
  my ($primaryDevname,$primaryReading) = readingsProxy_splitProxyDef($hash->{primaryProxy});

  $value //= ReadingsVal($devname,$reading,undef);
  
  if( $devname eq $primaryDevname && $reading eq $primaryReading) {
    my $value_fn = AttrVal( $name, "valueFn", "" );
    if( $value_fn =~ m/^{.*}$/s ) {
      my $VALUE = $value;
      my $LASTCMD = ReadingsVal($name,"lastCmd",undef);

      my $value_fn = eval $value_fn;
      Log3 $name, 3, $name .": valueFn: ". $@ if($@);
      return undef if( !defined($value_fn) );
      $value = $value_fn if( $value_fn ne '' );
    }
    readingsProxy_readingsSingleUpdate($hash, "state", $value);
  }
  readingsProxy_readingsSingleUpdate($hash, $proxy, $value);
}

sub
readingsProxy_updateAll($) 
{
  my ($hash) = @_;
  foreach my $devname (keys %{$hash->{PROXIES}})  {
    foreach my $reading (keys %{$hash->{PROXIES}{$devname}}) {
      readingsProxy_update($hash, $devname, $reading, undef);
    }
  }
}

sub
readingsProxy_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  my $events = deviceEvents($dev,1);
  return if( !$events );

  if( grep(m/^INITIALIZED$/, @{$events}) ) {
    readingsProxy_updateDevices($hash);
    return undef;
  } elsif( grep(m/^REREADCFG$/, @{$events}) ) {
    readingsProxy_updateDevices($hash);
    return undef;
  }
  return if( !$init_done );

  return if( AttrVal($name,"disable", 0) > 0 );

  my $devname = $dev->{NAME}; # name of device for which event occured

  return if($devname eq $name);

  my $max = int(@{$events});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));

    if( $devname eq "global") {
      #
      # events for the device global
      #
      if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
        # RENAMED
        my ($old, $new) = ($1, $2);
        if( defined($hash->{PROXIES}{$old}) ) {

          $hash->{DEF} =~ s/(^|\s+)$old((:\S+)?\s*)/$1$new$2/g;

          readingsProxy_updateDevices($hash);
        }
      } elsif($s =~ m/^DELETED ([^ ]*)$/) {
        # DELETED
        my ($delname) = ($1);

        if( defined($hash->{PROXIES}{$delname}) ) {
          readingsProxy_updateDevices($hash);
        }

      } elsif($s =~ m/^DEFINED ([^ ]*)$/) {
        # DEFINED
        my ($defname) = ($1);
        readingsProxy_updateDevices($hash) if( !$hash->{PROXIES}{$defname} );
      }

    } else {
      # events for one of the proxied devices
      next if( !$hash->{PROXIES}{$devname} );

      my @parts = split(/: /,$s);
      my $reading = shift @parts;
      my $value   = join(": ", @parts);

      $reading //= "";
      $value //= "";
      if( $value eq "" ) {
        $reading = "state";
        $value = $s;
      }
      next if( !$hash->{PROXIES}{$devname}{$reading} );
      #main::Debug "readingsProxy_Notify $name for $devname:$reading $value";

      readingsProxy_update($hash, $devname, $reading, $value);
    }
  }

  return undef;
}

sub
readingsProxy_Set($@)
{
  my ($hash, $name, @a) = @_;

  return "no set value specified" if(int(@a) < 1);
  
  my ($primaryDevname,$primaryReading) = readingsProxy_splitProxyDef($hash->{primaryProxy});
  return "no such device: $primaryDevname" unless($defs{$primaryDevname});

  my $setList = AttrVal($name, "setList", "");
  $setList = getAllSets($primaryDevname) if( $setList eq "%PARENT%" );
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

  SetExtensionsCancel($hash);

  my $v = join(" ", @a);
  my $set_fn = AttrVal( $hash->{NAME}, "setFn", "" );
  if( $set_fn =~ m/^{.*}$/s ) {
    my $CMD = $a[0];
    my $DEVICE = $primaryDevname;
    my $READING = $primaryReading;
    my $ARGS = join(" ", @a[1..$#a]);

    my $set_fn = eval $set_fn;
    Log3 $name, 3, $name .": setFn: ". $@ if($@);

    readingsSingleUpdate($hash, "lastCmd", $a[0], 0);

    return undef if( !defined($set_fn) );
    $v = $set_fn if( $set_fn ne '' );
  } else {
    readingsSingleUpdate($hash, "lastCmd", $a[0], 0);
  }

  if( $hash->{INSET} ) {
    Log3 $name, 2, "$name: ERROR: endless loop detected";
    return "ERROR: endless loop detected for $hash->{NAME}";
  }

  Log3 $name, 4, "$name: set $primaryDevname $v";
  $hash->{INSET} = 1;
  my $ret = CommandSet(undef,"$primaryDevname $v");
  delete($hash->{INSET});
  return $ret;
}

sub
readingsProxy_Get($@)
{
  my ($hash, $name, @a) = @_;

  return "no get value specified" if(int(@a) < 1);

  my ($primaryDevname,$primaryReading) = readingsProxy_splitProxyDef($hash->{primaryProxy});
  return "no such device: $primaryDevname" unless($defs{$primaryDevname});

  my $getList = AttrVal($name, "getList", "");
  $getList = getAllGets($primaryDevname) if( $getList eq "%PARENT%" );
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
  if( $get_fn =~ m/^{.*}$/s ) {
    my $CMD = $a[0];
    my $DEVICE = $primaryDevname;
    my $READING = $primaryReading;
    my $ARGS = join(" ", @a[1..$#a]);

    my ($get_fn,$direct_return) = eval $get_fn;
    Log3 $name, 3, $name .": getFn: ". $@ if($@);
    return $get_fn if($direct_return);
    return undef if( !defined($get_fn) );
    $v = $get_fn if( $get_fn ne '' );
  }

  if( $hash->{INGET} ) {
    Log3 $name, 2, "$name: ERROR: endless loop detected";
    return "ERROR: endless loop detected for $hash->{NAME}";
  }

  Log3 $name, 4, "$name: get $primaryDevname $v";
  $hash->{INSET} = 1;
  my$ret = CommandGet(undef,"$primaryDevname $v");
  delete($hash->{INSET});
  return $ret;
}

sub
readingsProxy_Attr($$$;$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $cmd eq "set" ) {
    if( $attrName eq 'getFn' || $attrName eq 'setFn' || $attrName eq 'valueFn' ) {
      my %specials= (
        "%CMD" => $name,
        "%DEVICE" => $name,
        "%READING" => $name,
        "%ARGS" => $name,
        "%VALUE" => $name,
        "%LASTCMD" => $name,
      );

      my $err = perlSyntaxCheck($attrVal, %specials);
      return $err if($err);
    }
  }

}



1;

=pod
=item helper
=item summary    make readings of other devices available as readings of a new device
=item summary_DE Readings anderer Ger&auml;te als Readings eines neuen Ger&auml;ts zur Verf&uuml;gung stellen
=begin html

<a name="readingsProxy"></a>
<h3>readingsProxy</h3>
<ul>
  This is the April 2026 enhanced downward-compatible version of readingsProxy<br><br>
  
  Create a device as aggregation of one or more readings of other devices. Can be used to create a new
  device with get and set functionality from one reading of another device (device extraction) or to 
  create a new device as a collection of readings from one or several devices (readings aggregation).<br>
  This can be used to map channels from 1-Wire, EnOcean or SWAP devices to independent devices that
  can have state, icons and webCmd different from the parent device and can be used in a floorplan. 
  Another use case would be a device to serve as single point of data for display of readings.
  <br><br>
  <a name="readingsProxy_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsProxy &lt;proxydef&gt; ...</code><br>
    <br>
    The definition of <code>readingsProxy</code> consists of one or more proxy definitions separated by
    whitespace. A proxy definition is a triplet <code>&lt;proxydef&gt; :=
    &lt;device&gt;:&lt;reading&gt;[:&lt;proxy&gt;]</code>. For each proxy definition the reading
    &lt;reading&gt; of device &lt;device&gt; is copied as a reading named &lt;proxy&gt; to the
    <code>readingsProxy</code> device. If the third part is omitted, the proxy is named
    as &lt;proxy&gt;_&lt;reading&gt;. If the second part is omitted, the <code>state</code> reading is used.<br><br>
    Examples:
    <ul>
      <code>define myProxy readingsProxy myDS2406:latch.A</code><br>
      <code>define myProxy readingsProxy myDS2406:latch.A:latchA</code><br>
      <code>define myProxy readingsProxy myDS2406_1:latch.A:latch1 myDS2406_2:ltach.A:latch2</code><br>
      <code>define proxy readingsProxy smaem:SMAEM1234567890_Bezug_Wirkleistung:Netzbezug smaem:SMAEM9876543210_GridFreq:Netzfrequenz smainverter:ChargeStatus:Battery</code>
    </ul>
    <br>
    Make sure to choose different names for the different proxies of the same <code>readingsProxy</code> device. Non-existent devices will be ignored.

    The first proxy referring to an existing device is called primary proxy. For the primary proxy, additional functionality can be made available 
    to the user in the form of individually defined get, set and value functionality (see 
    <a href="#readingsProxy_Attr">Attributes</a>). The <code>state</code> reading is taken from the primary proxy.<br><br>

    Renaming a proxied device will automatically rename the device in the <code>readingsProxy</code> device by changing its definition. 
    Deleting a proxied device will not change the definition and not change the primary proxy. If the device of the primary proxy is deleted, it
    will just work as if it were not there at all.
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
        Setting this attribute to 1 disables notify processing. Notice: this also disables rename and delete handling.</li>
      <li>getList<br>
        Space separated list of commands, which will be returned upon "get name ?",
        so the FHEMWEB frontend can construct a dropdown.
        %PARENT% will result in the complete list of commands from the parent device.
        get commands not in this list will be rejected.</li>
      <li>setList<br>
        Space separated list of commands, which will be returned upon "set name ?",
        so the FHEMWEB frontend can construct a dropdown and offer on/off switches.
        %PARENT% will result in the complete list of commands from the parent device.
        set commands not in this list will be rejected.<br>
        Example: <code>attr proxyName setList on off</code>
        </li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li>getFn<br>
        Perl expresion that will return the get command forwarded to the parent device.
        Has access to $DEVICE, $READING, $CMD and $ARGS.<br>
        <code>undef</code>: do nothing<br>
        <code>""</code>: pass through<br>
        <code>(&lt;value&gt;,1)</code>: directly return &lt;value&gt;, don't call parent getFn<br>
        everything else: use the provided function
        </li>
      <li>setFn<br>
        Perl expresion that will return the set command forwarded to the parent device.
        Has access to $CMD, $DEVICE, $READING and $ARGS.<br>
        <code>undef</code>: do nothing<br>
        <code>""</code>: pass through<br>
        everything else: use the provided function<br>
        Example: <code>attr myProxy setFn {($CMD eq "on")?"off":"on"}</code>
        </li>
      <li>valueFn<br>
        Perl expresion that will return the value that should be used for the reading.
        Has access to $LASTCMD, $DEVICE, $READING and $VALUE.<br>
        <code>undef</code>: do nothing<br>
        <code>""</code>: pass through<br>
        <code>(&lt;value&gt;,1)</code>: directly return &lt;value&gt;, don't call parent getFn<br>
        everything else: use the provided function<br>
        Examples: <code>attr myProxy valueFn { ($VALUE == 0) ? "off" : "on" }</code>
      </li>
      <br><li><a href="#perlSyntaxCheck">perlSyntaxCheck</a></li>
    </ul><br>
</ul>

=end html
=cut
