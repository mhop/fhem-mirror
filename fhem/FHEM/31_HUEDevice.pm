
package main;

use strict;
use warnings;
use POSIX;
use JSON;
use SetExtensions;

my %models = (
  LCT001 => 'HUE Bulb',
  LLC001 => 'LivingColors G2',
  LLC006 => 'LivingColors Iris',
  LLC007 => 'LivingColors Bloom',
  LWB001 => 'LivingWhites Bulb',
  LWL001 => 'LivingWhites Outlet',
);

sub HUEDevice_Initialize($)
{
  my ($hash) = @_;

  # Provide

  #Consumer
  $hash->{DefFn}    = "HUEDevice_Define";
  $hash->{UndefFn}  = "HUEDevice_Undefine";
  $hash->{SetFn}    = "HUEDevice_Set";
  $hash->{GetFn}    = "HUEDevice_Get";
  $hash->{AttrList} = "IODev ".
                      "$readingFnAttributes ".
                      "model:".join(",", sort keys %models)." ".
                      "subType:dimmer,switch";
}

sub HUEDevice_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> HUEDevice <id> [interval]"  if(@args < 3);

  my ($name, $type, $id, $interval) = @args;

  $interval= 60 unless defined($interval);
  if( $interval < 10 ) { $interval = 60; }


  $hash->{STATE} = 'Initialized';
  $hash->{fhem}{interfaces}= "dimmer";

  $hash->{fhem}{id} = $id;
  $hash->{INTERVAL} = $interval;

  $hash->{fhem}{on} = -1;
  $hash->{fhem}{colormode} = '';
  $hash->{fhem}{bri} = -1;
  $hash->{fhem}{ct} = -1;
  $hash->{fhem}{hue} = -1;
  $hash->{fhem}{sat} = -1;
  $hash->{fhem}{xy} = '';


  CommandAttr(undef,$name.' webCmd rgb:toggle:on:off') if( !defined( AttrVal($hash->{NAME}, "webCmd", undef) ) );
  CommandAttr(undef,$name.' devStateIcon {CommandGet("","'.$name.' devStateIcon")}') if( !defined( AttrVal($hash->{NAME}, "devStateIcon", undef) ) );

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log 1, "$name: no I/O device";
  }

  #HUEDevice_GetUpdate($hash);
  InternalTimer(gettimeofday()+10, "HUEDevice_GetUpdate", $hash, 0);

  return undef;
}

sub HUEDevice_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);

  delete($hash->{fhem}{id});

  return undef;
}

sub
HUEDevice_Set($@)
{
  my ($hash, $name, $cmd, $value, $value2, @a) = @_;

  if( $cmd eq "color" ) {
    $value = int(100000/$value);
    $cmd = 'ct';
  } elsif( $cmd eq "toggle" ) {
    $cmd = ReadingsVal($name,"state","on") eq "off" ? "on" :"off";
  } elsif( $cmd =~ m/^dim(\d+)/ ) {
    $value = $1 unless defined($value);
    if( $value <   0 ) { $value =   0; }
    if( $value > 100 ) { $value = 100; }
    $cmd = 'pct';
  } elsif( !defined($value) && $cmd =~ m/^(\d+)/) {
    $value = $1;
    $value = 254 if( $value > 254 );
    $cmd = 'bri';
  }

  # usage check
  if($cmd eq 'statusRequest') {
    RemoveInternalTimer($hash);
    HUEDevice_GetUpdate($hash);
    return undef;
  } elsif($cmd eq 'on') {

    my $obj = {
      'on'  => JSON::true,
    };
   $obj->{bri} =254 if( ReadingsVal($name,"bri","0") eq 0 );
   if( defined($value) ) {
     $obj->{transitiontime} = $value / 10;
   }

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq 'off') {

    my $obj = {
      'on'  => JSON::false,
    };
   if( defined($value) ) {
     $obj->{transitiontime} = $value / 10;
   }

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "pct") {
    my $obj = {
      'bri'  => int(2.54 * $value),
      'on'  => JSON::true,
    };
   if( defined($value2) ) {
     $obj->{transitiontime} = $value2 / 10;
   }

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "bri") {
    my $obj = {
      'bri'  => 0+$value,
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "ct") {
    my $obj = {
      'ct'  => 0+$value,
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "hue") {
    my $obj = {
      'hue'  => 0+$value,
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "sat") {
    my $obj = {
      'sat'  => 0+$value,
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } elsif($cmd eq "xy" && $value =~ m/^(.+),(.+)/) {
    my ($x,$y) = ($1, $2);

    my $obj = {
      'xy'  => [0+$x, 0+$y],
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
    }
  } elsif( $cmd eq "rgb" && $value =~ m/^(..)(..)(..)/) {
    my( $r, $g, $b ) = (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

    my $X =  1.076450 * $r - 0.237662 * $g + 0.161212 * $b;
    my $Y =  0.410964 * $r + 0.554342 * $g + 0.034694 * $b;
    my $Z = -0.010954 * $r - 0.013389 * $g + 1.024343 * $b;
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

    if( $X != 0
        || $Y != 0
        || $Z != 0 ) {
      my $x = $X / ($X + $Y + $Z);
      my $y = $Y / ($X + $Y + $Z);
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

      #$x = 0 if( $x < 0 );
      #$x = 1 if( $x > 1 );
      #$y = 0 if( $y < 0 );
      #$y = 1 if( $y > 1 );
      $Y = 1 if( $Y > 1 );

      my $bri  = max($r,max($g,$b));
      #my $bri  = $Y;
      my $obj = {
        'xy'  => [0+$x, 0+$y],
        'bri'  => int(254*$bri),
        'on'  => JSON::true,
      };

      my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
      if( $result->{'error'} ) {
          $hash->{STATE} = $result->{'error'}->{'description'};
          return undef;
        }
      }
  } elsif( $cmd eq "hsv" && $value =~ m/^(..)(..)(..)/) {
    my( $h, $s, $v ) = (hex($1), hex($2), hex($3));

    $s = 254 if( $s > 254 );
    $v = 254 if( $v > 254 );

    my $obj = {
      'hue'  => int($h*256),
      'sat'  => 0+$s,
      'bri'  => 0+$v,
      'on'  => JSON::true,
    };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id}."/state",$obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }
  } else {
    my $list = "off on toggle statusRequest";
    $list .= " rgb:colorpicker,RGB pct:slider,0,1,100 color:slider,2000,1,6500 bri:slider,0,1,254 ct:slider,154,1,500 hue:slider,0,1,65535 sat:slider,0,1,254 xv" if( AttrVal($hash->{NAME}, "subType", "dimmer") eq "dimmer" );
    #$list .= " dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%" if( AttrVal($hash->{NAME}, "subType", "dimmer") eq "dimmer" );
    return SetExtensions($hash, $list, $name, $cmd, $value, @a);
  }

  $hash->{LOCAL} = 1;
  HUEDevice_GetUpdate($hash);
  delete $hash->{LOCAL};

  return undef;
}

sub
HUEDevice_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "rgb") {
    my $ret = "000000";

    if( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ )
      {
        my ($x,$y) = ($1, $2);
        my $Y = ReadingsVal($name,"bri","") / 254.0;
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

        if( $y > 0 ) {
          my $X = $x * $Y / $y;
          my $Z = (1 - $x - $y)*$Y / $y;

          if( $X > 1
              || $Y > 1
              || $Z > 1 ) {
            my $f = max($X,max($Y,$Z));
            $X /= $f;
            $Y /= $f;
            $Z /= $f;
          }
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

          my $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
          my $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
          my $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

          if( $r > 1
              || $g > 1
              || $b > 1 ) {
            my $f = max($r,max($g,$b));
            $r /= $f;
            $g /= $f;
            $b /= $f;
          }
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

          $r *= 255;
          $g *= 255;
          $b *= 255;

          $ret = sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
        }
      }
    return $ret;
  } elsif ( $cmd eq "devStateIcon" ) {
    return '<div id="'.$name.'" align="center" class="col2">'.
           '<img src="/fhem/icons/off" alt="off" title="off">'.
           '</div>' if( ReadingsVal($name,"state","off") eq "off" | ReadingsVal($name,"bri","0") eq 0 );

    return '<div id="'.$name.'" align="center" class="col2">'.
           '<img src="/fhem/icons/'.$hash->{STATE}.'" alt="'.$hash->{STATE}.'" title="'.$hash->{STATE}.'">'.
           '</div>' if( AttrVal($hash->{NAME}, "model", "") eq "LWL001" );

    return '<div id="'.$name.'" class="block" style="width:32px;height:19px;'.
           'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
  }

  return "Unknown argument $cmd, choose one of rgb devStateIcon";
}


###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
HUEDevice_ReadFromServer($@)
{
  my ($hash,@a) = @_;

  my $dev = $hash->{NAME};
  no strict "refs";
  my $ret;
  unshift(@a,$dev);
  $ret = IOWrite($hash, @a);
  use strict "refs";
  return $ret;
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log 5, "No I/O device or ReadFn found for $dev";
    return;
  }

  no strict "refs";
  #my $ret;
  unshift(@a,$dev);
  $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);


sub
HUEDevice_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEDevice_GetUpdate", $hash, 1);
  }

  my $result = HUEDevice_ReadFromServer($hash,$hash->{fhem}{id});
  if( !defined($result) ) {
    $hash->{STATE} = "unknown";
    return;
  } elsif( $result->{'error'} ) {
    $hash->{STATE} = $result->{'error'}->{'description'};
    return;
  }

  $hash->{modelid} = $result->{'modelid'};
  $hash->{name} = $result->{'name'};
  $hash->{type} = $result->{'type'};
  $hash->{swversion} = $result->{'swversion'};

  $attr{$name}{model} = $result->{'modelid'} unless (defined($attr{$name}{model}) || $result->{'modelid'} eq '' );

  readingsBeginUpdate($hash);

  my $state = $result->{'state'};

  my $on        = $state->{on};
  my $colormode = $state->{'colormode'};
  my $bri       = $state->{'bri'};
  my $ct        = $state->{'ct'};
  my $hue       = $state->{'hue'};
  my $sat       = $state->{'sat'};
  my $xy        = $state->{'xy'}->[0] .",". $state->{'xy'}->[1];

  if( defined($colormode) && $colormode ne $hash->{fhem}{colormode} ) {readingsBulkUpdate($hash,"colormode",$colormode);}
  if( defined($bri) && $bri != $hash->{fhem}{bri} ) {readingsBulkUpdate($hash,"bri",$bri);}
  if( defined($ct) && $ct != $hash->{fhem}{ct} ) {
    if( $ct == 0 ) {
      readingsBulkUpdate($hash,"ct",$ct);
    }
    else {
      readingsBulkUpdate($hash,"ct",$ct . " (".int(1000000/$ct)."K)");
    }
  }
  if( defined($hue) && $hue != $hash->{fhem}{hue} ) {readingsBulkUpdate($hash,"hue",$hue);}
  if( defined($sat) && $sat != $hash->{fhem}{sat} ) {readingsBulkUpdate($hash,"sat",$sat);}
  if( $xy eq "," ) {readingsBulkUpdate($hash,"xy","");}
  elsif( $xy != $hash->{fhem}{xy} ) {readingsBulkUpdate($hash,"xy",$xy);}

  my $s = '';
  if( $on )
    {
      $s = 'on';
      if( $on != $hash->{fhem}{on} ) {readingsBulkUpdate($hash,"onoff",1);}

      my $percent = int( $state->{'bri'} * 100 / 254 );
      if( $bri != $hash->{fhem}{bri} ) {readingsBulkUpdate($hash,"level", $percent . ' %');}
      if( $bri != $hash->{fhem}{bri} ) {readingsBulkUpdate($hash,"pct", $percent);}
      if( $percent > 0
          && $percent < 100  ) {
        $s = $dim_values{int($percent/7)};
      }
    }
  else
    {
      $s = 'off';
      if( $on != $hash->{fhem}{on} ) {readingsBulkUpdate($hash,"onoff",0);}
    }

  if( $s ne $hash->{STATE} ) {readingsBulkUpdate($hash,"state",$s);}
  readingsEndUpdate($hash,defined($hash->{LOCAL} ? 0 : 1));

  $hash->{fhem}{on} = $on;
  $hash->{fhem}{colormode} = $colormode;
  $hash->{fhem}{bri} = $bri;
  $hash->{fhem}{ct} = $ct;
  $hash->{fhem}{hue} = $hue;
  $hash->{fhem}{sat} = $sat;
  $hash->{fhem}{xy} = $xy;
}

1;

=pod
=begin html

<a name="HUEDevice"></a>
<h3>HUEDevice</h3>
<ul>
  <br>
  <a name="HUEDevice_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HUEDevice &lt;id&gt; [&lt;interval&gt;]</code><br>
    <br>

    Defines a device connected to a <a href="#HUEBridge">HUEBridge</a>.<br><br>

    This can be a hue bulb, a living color light or a living whites bulb or dimmer plug.<br><br>

    The device status will be updated every &lt;interval&gt; seconds. The default and minimum is 60.<br><br>

    Examples:
    <ul>
      <code>define bulb HUEDevice 1</code><br>
      <code>define LC HUEDevice 2</code><br>
    </ul>
  </ul><br>

  <a name="SYSSTAT_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>bri<br>
    the brightness reported from the device. the value can be betwen 1 and 254</li>
    <li>colormode<br>
    the current colormode</li>
    <li>ct<br>
    the colortemperature in mireds and kelvin</li>
    <li>hue<br>
    the current hue</li>
    <li>level<br>
    the current brightness in percent</li>
    <li>onoff<br>
    the current on/off state as 0 or 1</li>
    <li>sat<br>
    the current saturation</li>
    <li>xy<br>
    the current xy color coordinates</li>
    <li>state<br>
    the current state</li>
    <br>
    Notes:
      <ul>
      <li>not all readings show the actual device state. all readings not related to the current colormode have to be ignored.</li>
      <li>the actual state of a device controlled by a living colors or living whites remote can be different and will
          be updated after some time.</li>
      </ul><br>
  </ul><br>

  <a name="HUEDevice_Set"></a>
    <b>Set</b>
    <ul>
      <li>on [&lt;ramp-time&gt;]</li>
      <li>off [&lt;ramp-time&gt;]</li>
      <li>toggle [&lt;ramp-time&gt;]</li>
      <li>statusRequest<br>
      Request device status update.</li>
      <li>pct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        dim to &lt;value&gt;</li>
      Notes:
        <ul>
        <li>the FS20 compatible dimXX% commands are also accepted.</li>
        </ul><br>
      <li>color &lt;value&gt;<br>
        set colortemperature to &lt;value&gt; kelvin.</li>
      <li>bri &lt;value&gt;<br>
        set brighness to &lt;value&gt;; range is 1-254.</li>
      <li>ct &lt;value&gt;<br>
        set colortemperature to &lt;value&gt; mireds; range is 154-500.</li>
      <li>hue &lt;value&gt;<br>
        set hue to &lt;value&gt;; range is 0-65535.</li>
      <li>sat &lt;value&gt;<br>
        set saturation to &lt;value&gt;; range is 0-254.</li>
      <li>x &lt;x&gt;,&lt;y&gt;<br>
        set the xv color coordinates to &lt;x&gt;,&lt;y&gt;;</li>
      <li>rgb &lt;rrggbb&gt;</li>
    </ul><br>

  <a name="HUEDevice_Get"></a>
    <b>Get</b>
    <ul>
      <li>rgb</li>
      <li>devStateIcon<br>
      returns html code that can be used to create an icon that represents the device color in the room overview.</li>
    </ul><br>

  <a name="HUEDevice_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>subType<br>
      dimmer or switch, default is dimmer.</li>
      <li>devStateIcon<br>
      will be initialized to <code>{CommandGet("","&lt;name&gt; devStateIcon")}</code> as default to show device color in room overview.</li>
  </ul>

</ul><br>

=end html
=cut
