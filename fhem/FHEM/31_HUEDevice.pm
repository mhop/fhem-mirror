
# $Id$

# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;

use Color;

use POSIX;
use JSON;
use SetExtensions;

my %hueModels = (
  LCT001 => {name => 'HUE Bulb'             ,type => 'Extended color light'   ,subType => 'colordimmer',},
  LLC001 => {name => 'LivingColors G2'      ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC005 => {name => 'LivingColors Bloom'   ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC006 => {name => 'LivingColors Iris'    ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC007 => {name => 'LivingColors Bloom'   ,type => 'Color Light'            ,subType => 'colordimmer',},
  LWB001 => {name => 'LivingWhites Bulb'    ,type => 'Dimmable light'         ,subType => 'dimmer',},
  LWL001 => {name => 'LivingWhites Outlet'  ,type => 'Dimmable plug-in unit'  ,subType => 'dimmer',},
);

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
                      "color-icons:1,2 ".
                      "model:".join(",", sort keys %hueModels)." ".
                      "subType:colordimmer,dimmer,switch ".
                      $readingFnAttributes;

  #$hash->{FW_summaryFn} = "HUEDevice_summaryFn";

  $data{webCmdFn}{colorpicker} = "FHEM_colorpickerFn";
  $data{FWEXT}{"/"}{SCRIPT} = "/jscolor/jscolor.js";
}

sub
HUEDevice_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $name = $hash->{NAME};

  return ".*:light_question" if( !$hash->{fhem}{reachable} && AttrVal($name, "color-icons", 0) != 0 );

  return undef
         if( ReadingsVal($name,"state","off") eq "off" || ReadingsVal($name,"bri","0") eq 0 );

  return undef
         if( AttrVal($name, "model", "") eq "LWB001" );

  return undef
         if( AttrVal($name, "model", "") eq "LWL001" );

  #return '<div style="height:19px;'.
  #       'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';">'.
  #       '<img src="/fhem/icons/'.$hash->{STATE}.'" alt="'.$hash->{STATE}.'" title="'.$hash->{STATE}.'">'.
  #       '</div>' if( ReadingsVal($name,"colormode","") eq "ct" );

  my $percent = ReadingsVal($name,"pct","100");
  my $s = $dim_values{int($percent/7)};

  return ".*:$s@#".CommandGet("","$name RGB").":toggle" if( $percent < 100 && AttrVal($name, "color-icons", 0) == 2 );
  return ".*:on@#".CommandGet("","$name rgb").":toggle" if( AttrVal($name, "color-icons", 0) != 0 );

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
}
sub
HUEDevice_summaryFn($$$$)
{
Log 3, "HUEDevice_summaryFn";
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};

  return HUEDevice_devStateIcon($hash);
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

  $hash->{ID} = $id;
  $hash->{fhem}{id} = $id;

  $hash->{INTERVAL} = $interval;

  $hash->{fhem}{on} = -1;
  $hash->{fhem}{reachable} = '';
  $hash->{fhem}{colormode} = '';
  $hash->{fhem}{bri} = -1;
  $hash->{fhem}{ct} = -1;
  $hash->{fhem}{hue} = -1;
  $hash->{fhem}{sat} = -1;
  $hash->{fhem}{xy} = '';

  $hash->{fhem}{percent} = -1;


  $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

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
HUEDevice_SetParam($$@)
{
  my ($name, $obj, $cmd, $value, $value2) = @_;

  if( $cmd eq "color" ) {
    $value = int(1000000/$value);
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

  if($cmd eq 'on') {
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'} = 254 if( ReadingsVal($name,"bri","0") eq 0 );
    $obj->{'transitiontime'} = $value / 10 if( defined($value) );
  } elsif($cmd eq 'off') {
    $obj->{'on'}  = JSON::false;
    $obj->{'transitiontime'} = $value / 10 if( defined($value) );
  } elsif($cmd eq "pct") {
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = int(2.54 * $value);
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif($cmd eq "bri") {
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif($cmd eq "ct") {
    $obj->{'on'}  = JSON::true;
    $obj->{'ct'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif($cmd eq "hue") {
    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif($cmd eq "sat") {
    $obj->{'on'}  = JSON::true;
    $obj->{'sat'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif($cmd eq "xy" && $value =~ m/^(.+),(.+)/) {
    my ($x,$y) = ($1, $2);
    $obj->{'on'}  = JSON::true;
    $obj->{'xy'}  = [0+$x, 0+$y];
    $obj->{'transitiontime'} = $value2 / 10 if( defined($value2) );
  } elsif( $cmd eq "rgb" && $value =~ m/^(..)(..)(..)/) {
    # calculation from http://www.everyhue.com/vanilla/discussion/94/rgb-to-xy-or-hue-sat-values/p1
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

      my $bri  = maxNum($r,$g,$b);
      #my $bri  = $Y;

    $obj->{'on'}  = JSON::true;
    $obj->{'xy'}  = [0+$x, 0+$y];
    $obj->{'bri'}  = int(254*$bri);
        }
  } elsif( $cmd eq "hsv" && $value =~ m/^(..)(..)(..)/) {
    my( $h, $s, $v ) = (hex($1), hex($2), hex($3));

    $s = 254 if( $s > 254 );
    $v = 254 if( $v > 254 );

    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = int($h*256);
    $obj->{'sat'}  = 0+$s;
    $obj->{'bri'}  = 0+$v;
  } elsif( $cmd eq "effect" ) {
    $obj->{'effect'}  = $value;
  } elsif( $cmd eq "transitiontime" ) {
    $obj->{'transitiontime'} = 0+$value;
  } else {
    return 0;
  }

  return 1;
}
sub HUEDevice_Set($@);
sub
HUEDevice_Set($@)
{
  my ($hash, $name, @aa) = @_;

  my %obj;

  if( (my $joined = join(" ", @aa)) =~ /:/ ) {
    my @cmds = split(":", $joined);
    for( my $i = 0; $i <= $#cmds; ++$i ) {
      HUEDevice_SetParam($name, \%obj, split(" ", $cmds[$i]) );
    }
  } else {
    my ($cmd, $value, $value2, @a) = @aa;

    if( $cmd eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;
    }

    HUEDevice_SetParam($name, \%obj, $cmd, $value, $value2);
  }


  if( scalar keys %obj ) {
    my $result = HUEDevice_ReadFromServer($hash,$hash->{ID}."/state",\%obj);
    if( $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }

    $hash->{LOCAL} = 1;
    HUEDevice_GetUpdate($hash);
    delete $hash->{LOCAL};

    return undef;
  }

  my $list = "off:noArg on:noArg toggle:noArg statusRequest:noArg";
  $list .= " pct:slider,0,1,100 bri:slider,0,1,254" if( AttrVal($name, "subType", "colordimmer") =~ m/dimmer/ );
  #$list .= " dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%" if( AttrVal($hash->{NAME}, "subType", "colordimmer") =~ m/dimmer/ );
  $list .= " rgb:colorpicker,RGB color:slider,2000,1,6500 ct:slider,154,1,500 hue:slider,0,1,65535 sat:slider,0,1,254 xy effect:none,colorloop" if( AttrVal($hash->{NAME}, "subType", "colordimmer") =~ m/color/ );
  return SetExtensions($hash, $list, $name, @aa);
}

sub
cttorgb($)
{
  my ($ct) = @_;

  # calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code
  # adjusted by 1000K
  my $temp = (1000000/$ct)/100 + 10;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  $r = 255;
  $r = 329.698727446 * ($temp - 60) ** -0.1332047592 if( $temp > 66 );
  $r = 0 if( $r < 0 );
  $r = 255 if( $r > 255 );

  if( $temp <= 66 ) {
    $g = 99.4708025861 * log($temp) - 161.1195681661;
  } else {
    $g = 288.1221695283 * ($temp - 60) ** -0.0755148492;
  }
  $g = 0 if( $g < 0 );
  $g = 255 if( $g > 255 );

  $b = 255;
  $b = 0 if( $temp <= 19 );
  if( $temp < 66 ) {
    $b = 138.5177312231 * log($temp-10) - 305.0447927307;
  }
  $b = 0 if( $b < 0 );
  $b = 255 if( $b > 255 );

  return( $r, $g, $b );
}

sub
xyYtorgb($$$)
{
  # calculation from http://www.brucelindbloom.com/index.html
  my ($x,$y,$Y) = @_;
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  if( $y > 0 ) {
    my $X = $x * $Y / $y;
    my $Z = (1 - $x - $y)*$Y / $y;

    if( $X > 1
        || $Y > 1
        || $Z > 1 ) {
      my $f = maxNum($X,$Y,$Z);
      $X /= $f;
      $Y /= $f;
      $Z /= $f;
    }
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

    $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
    $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
    $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

    if( $r > 1
        || $g > 1
        || $b > 1 ) {
      my $f = maxNum($r,$g,$b);
      $r /= $f;
      $g /= $f;
      $b /= $f;
    }
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

    $r *= 255;
    $g *= 255;
    $b *= 255;
  }

  return( $r, $g, $b );
}

sub
HUEDevice_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "rgb") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    if( ReadingsVal($name,"colormode","") eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = cttorgb($1);
      }
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = ReadingsVal($name,"bri","") / 254.0;

      ($r,$g,$b) = xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif($cmd eq "RGB") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    if( ReadingsVal($name,"colormode","") eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = cttorgb($1);
      }
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = 1;

      ($r,$g,$b) = xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif ( $cmd eq "devStateIcon" ) {
    return HUEDevice_devStateIcon($hash);
  }

  return "Unknown argument $cmd, choose one of rgb:noArg RGB:noArg devStateIcon:noArg";
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

sub
HUEDevice_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEDevice_GetUpdate", $hash, 1);
  }

  my $result = HUEDevice_ReadFromServer($hash,$hash->{ID});
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

  $attr{$name}{model} = $result->{'modelid'} unless( defined($attr{$name}{model}) || $result->{'modelid'} eq '' );
  $attr{$name}{subType} = $hueModels{$attr{$name}{model}}{subType} unless( defined($attr{$name}{subType})
                                                                           || !defined($attr{$name}{model})
                                                                           || !defined($hueModels{$attr{$name}{model}}{subType}) );

  $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

  if( !defined( $attr{$name}{webCmd} ) ) {
    $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb 98FF23:rgb 0000ff:toggle:on:off' if( $attr{$name}{subType} eq "colordimmer" );
    $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb C8FF12:rgb 0000ff:toggle:on:off' if( AttrVal($name, "model", "") eq "LCT001" );
    $attr{$name}{webCmd} = 'pct:toggle:on:off' if( $attr{$name}{subType} eq "dimmer" );
    $attr{$name}{webCmd} = 'toggle:on:off' if( $attr{$name}{subType} eq "switch" );
  }

  readingsBeginUpdate($hash);

  my $state = $result->{'state'};

  my $on        = $state->{on};
  my $reachable = $state->{reachable};
  my $colormode = $state->{'colormode'};
  my $bri       = $state->{'bri'};
  my $ct        = $state->{'ct'};
  my $hue       = $state->{'hue'};
  my $sat       = $state->{'sat'};
  my $xy        = undef;
     $xy        = $state->{'xy'}->[0] .",". $state->{'xy'}->[1] if( defined($state->{'xy'}) );

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
  if( defined($xy) && $xy ne $hash->{fhem}{xy} ) {readingsBulkUpdate($hash,"xy",$xy);}
  if( defined($reachable) && $reachable ne $hash->{fhem}{reachable} ) {readingsBulkUpdate($hash,"reachable",$reachable);}

  my $s = '';
  my $percent;
  if( $on )
    {
      $s = 'on';
      if( $on != $hash->{fhem}{on} ) {readingsBulkUpdate($hash,"onoff",1);}

      $percent = int( $bri * 100 / 254 );
      if( $percent > 0
          && $percent < 100  ) {
        $s = $dim_values{int($percent/7)};
      }
      $s = 'off' if( $percent == 0 );
    }
  else
    {
      $s = 'off';
      $percent = 0;
      if( $on != $hash->{fhem}{on} ) {readingsBulkUpdate($hash,"onoff",0);}
    }

  if( $percent != $hash->{fhem}{percent} ) {readingsBulkUpdate($hash,"level", $percent . ' %');}
  if( $percent != $hash->{fhem}{percent} ) {readingsBulkUpdate($hash,"pct", $percent);}

  $s = 'off' if( !$reachable );

  if( $s ne $hash->{STATE} ) {readingsBulkUpdate($hash,"state",$s);}
  readingsEndUpdate($hash,defined($hash->{LOCAL} ? 0 : 1));

  CommandTrigger( "", "$name RGB: ".CommandGet("","$name rgb") ); 

  $hash->{fhem}{on} = $on;
  $hash->{fhem}{reachable} = $reachable;
  $hash->{fhem}{colormode} = $colormode;
  $hash->{fhem}{bri} = $bri;
  $hash->{fhem}{ct} = $ct;
  $hash->{fhem}{hue} = $hue;
  $hash->{fhem}{sat} = $sat;
  $hash->{fhem}{xy} = $xy;

  $hash->{fhem}{percent} = $percent;
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

    This can be a hue bulb, a living colors light or a living whites bulb or dimmer plug.<br><br>

    The device status will be updated every &lt;interval&gt; seconds. The default and minimum is 60.<br><br>

    Examples:
    <ul>
      <code>define bulb HUEDevice 1</code><br>
      <code>define LC HUEDevice 2</code><br>
    </ul>
  </ul><br>

  <a name="HUEDevice_Readings"></a>
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
        dim to &lt;value&gt;<br>
        Note: the FS20 compatible dimXX% commands are also accepted.</li>
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
      <li>xy &lt;x&gt;,&lt;y&gt;<br>
        set the xy color coordinates to &lt;x&gt;,&lt;y&gt;</li>
      <li>effect [none|colorloop]</li>
      <li>transitiontime &lt;time&gt;<br>
        set the transitiontime to &lt;time&gt; 1/10s</li>
      <li>rgb &lt;rrggbb&gt;</li>
      <li><a href="#setExtensions"> set extensions</a> are supported.</li>
      <br>
      Note:
        <ul>
        <li>multiple paramters can be set at once separated by <code>:</code><br>
          Examples:<br>
            <code>set LC on : transitiontime 100</code><br>
            <code>set bulb on : bri 100 : color 4000</code><br></li>
        </ul>
    </ul><br>

  <a name="HUEDevice_Get"></a>
    <b>Get</b>
    <ul>
      <li>rgb</li>
      <li>RGB</li>
      <li>devStateIcon<br>
      returns html code that can be used to create an icon that represents the device color in the room overview.</li>
    </ul><br>

  <a name="HUEDevice_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>color-icon<br>
      1 -> use lamp color as icon color and 100% shape as icon shape<br>
      2 -> use lamp color scaled to full brightness as icon color and dim state as icon shape</li>
    <li>subType<br>
      colordimmer, dimmer or switch, default is initialized according to device model.</li>
    <li>devStateIcon<br>
      will be initialized to <code>{(HUEDevice_devStateIcon($name),"toggle")}</code> to show device color as default in room overview.</li>
    <li>webCmd<br>
      will be initialized to <code>rgb:rgb FF0000:rgb C8FF12:rgb 0000FF:toggle:on:off</code> to show colorpicker and 3 color preset buttons in room overview.</li>
  </ul>

</ul><br>

=end html
=cut
