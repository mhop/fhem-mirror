# $Id$

package main;

use strict;
use warnings;

use Color;

use POSIX;
use JSON;
use SetExtensions;

use vars qw(%FW_webArgs); # all arguments specified in the GET

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


my $Aurora_hasDataDumper = 1;

sub
Aurora_Initialize($)
{
  my ($hash) = @_;

  # Provide

  #Consumer
  $hash->{DefFn}    = "Aurora_Define";
  $hash->{NotifyFn} = "Aurora_Notify";
  $hash->{UndefFn}  = "Aurora_Undefine";
  $hash->{SetFn}    = "Aurora_Set";
  $hash->{GetFn}    = "Aurora_Get";
  $hash->{AttrFn}   = "Aurora_Attr";
  $hash->{AttrList} = "delayedUpdate:1 ".
                      "realtimePicker:1,0 ".
                      "color-icons:1,2 ".
                      "transitiontime ".
                      "token ".
                      "disable:1,0 disabledForIntervals ".
                      $readingFnAttributes;

  #$hash->{FW_summaryFn} = "Aurora_summaryFn";

  FHEM_colorpickerInit();

  eval "use Data::Dumper";
  $Aurora_hasDataDumper = 0 if($@);
}

sub
Aurora_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  my $name = $hash->{NAME};

  return ".*:off:toggle" if( ReadingsVal($name,"state","off") eq "off" );
  return ".*:on:toggle" if( ReadingsVal($name,"effect","*Solid*") ne "*Solid*" );

  my $pct = ReadingsVal($name,"pct","100");
  my $s = $dim_values{int($pct/7)};
  $s="on" if( $pct eq "100" );

  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB001" );
  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB003" );
  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB004" );


  return ".*:$s@#".CommandGet("","$name RGB").":toggle" if( $pct < 100 && AttrVal($name, "color-icons", 0) == 2 );
  return ".*:on@#".CommandGet("","$name rgb").":toggle" if( AttrVal($name, "color-icons", 0) != 0 );

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
}
sub
Aurora_summaryFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};

  return Aurora_devStateIcon($hash);
}

sub
Aurora_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> Aurora <ip> [interval]"  if(@args < 3);

  my ($name, $type, $ip, $interval) = @args;

  $hash->{STATE} = 'Initialized';

  #pair & get mac
  $hash->{IP} = $ip;

  my $code = $hash->{IP};
  my $d = $modules{Aurora}{defptr}{$code};
  return "Aurora device $hash->{ID} already defined as $d->{NAME}."
         if( defined($d) && $d->{NAME} ne $name );

  $modules{Aurora}{defptr}{$code} = $hash;

  $args[3] = "" if( !defined( $args[3] ) );
  $interval = 60 if( defined($interval) && $interval < 10 );
  $hash->{INTERVAL} = $interval;

  $hash->{helper}{last_config_timestamp} = 0;

  $hash->{helper}{on} = -1;
  $hash->{helper}{colormode} = '';
  $hash->{helper}{ct} = -1;
  $hash->{helper}{hue} = -1;
  $hash->{helper}{sat} = -1;
  $hash->{helper}{xy} = '';
  $hash->{helper}{effect} = '';

  $hash->{helper}{pct} = -1;
  $hash->{helper}{rgb} = "";

  $attr{$name}{devStateIcon} = '{(Aurora_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

  my $icon_path = AttrVal("WEB", "iconPath", "default:fhemSVG:openautomation" );
  $attr{$name}{'color-icons'} = 2 if( !defined( $attr{$name}{'color-icons'} ) && $icon_path =~ m/openautomation/ );

  $hash->{NOTIFYDEV} = "global";

  RemoveInternalTimer($hash);
  if( $init_done ) {
    Aurora_OpenDev($hash) if( !IsDisabled($name) );
  }

  return undef;
}

sub
Aurora_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if( IsDisabled($name) > 0 ) {
    readingsSingleUpdate($hash, 'state', 'inactive', 1 ) if( ReadingsVal($name,'inactive','' ) ne 'disabled' );
    return undef;
  }

  Aurora_OpenDev($hash);

  return undef;
}


sub
Aurora_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);

  my $code = $hash->{IP};
  delete($modules{Aurora}{defptr}{$code});

  return undef;
}


sub
Aurora_OpenDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( !AttrVal($name, 'token', undef) ) {
    Aurora_Pair($hash);
  } else {
    RemoveInternalTimer($hash);
    Aurora_GetUpdate($hash);
  }
  return undef;

  Aurora_Detect($hash) if( defined($hash->{NUPNP}) );

  my $result = Aurora_Call($hash, undef, 'config', undef);
  if( !defined($result) ) {
    Log3 $name, 2, "Aurora_OpenDev: got empty config";
    return undef;
  }
  Log3 $name, 5, "Aurora_OpenDev: got config " . Dumper $result if($Aurora_hasDataDumper);

  if( !defined($result->{'linkbutton'}) || !AttrVal($name, 'key', undef) )
    {
      Aurora_fillBridgeInfo($hash, $result);

      Aurora_Pair($hash);
      return;
    }

  $hash->{mac} = $result->{'mac'};

  readingsSingleUpdate($hash, 'state', 'connected', 1 );
  Aurora_GetUpdate($hash);

  Aurora_Autocreate($hash);

  return undef;
}

sub
Aurora_Pair($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  readingsSingleUpdate($hash, 'state', 'pairing', 1 );

  my($err,$data) = HttpUtils_NonblockingGet({
    url => "http://$hash->{IP}:16021/api/v1/new",
    timeout => 2,
    method => 'POST',
    noshutdown => $hash->{noshutdown},
    hash => $hash,
    type => 'pair',
    callback => \&Aurora_dispatch,
  });

  return undef;


  my $result = Aurora_Register($hash);
  if( $result->{'error'} )
    {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5, "Aurora_Pair", $hash, 0);

      return undef;
    }

  $attr{$name}{token} = $result->{success}{username} if( $result->{success}{username} );

  readingsSingleUpdate($hash, 'state', 'paired', 1 );

  Aurora_OpenDev($hash);

  return undef;
}

sub
Aurora_dispatch($$$;$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  my $json;
  $json = eval { decode_json($data) } if( $data );
  Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );

#Log 1, "  $err";
#Log 1, "  $data";
#Log 1, "  $json";

  if( $param->{type} eq 'pair' ) {
    if( !$json ) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5, "Aurora_Pair", $hash, 0);

      return undef;
    } else {
      $attr{$name}{token} = $json->{auth_token} if( $json->{auth_token} );
      Aurora_GetUpdate($hash);
    }
  }
  #return undef if( !$json );

  if( $param->{type} eq 'state' ) {
    if( $param->{method} eq 'GET' ) {
      Aurora_Parse($hash, $json) if( $json );
    } else {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+1, "Aurora_GetUpdate", $hash, 0);
    }
  }
}




sub
Aurora_SetParam($$@)
{
  my ($name, $obj, $cmd, $value, $value2, @a) = @_;

  if( $cmd eq "color" ) {
    $value = int(1000000/$value);
    $cmd = 'ct';
  } elsif( $name && $cmd eq "toggle" ) {
    $cmd = ReadingsVal($name,"onoff",1) ? "off" :"on";
  } elsif( $cmd =~ m/^dim(\d+)/ ) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value <   0 );
    $value = 100 if( $value > 100 );
    $cmd = 'pct';
  } elsif( !defined($value) && $cmd =~ m/^(\d+)/) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value < 0 );
    $value = 100 if( $value > 100 );
    $cmd = 'pct';
  }

  $cmd = "off" if($cmd eq "pct" && $value == 0 );

  if($cmd eq 'on') {
    $obj->{'on'}  = JSON::true;
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq 'off') {
    $obj->{'on'}  = JSON::false;
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq "pct") {
    $value = 0 if( $value < 0 );
    $value = 100 if( $value > 100 );
    $obj->{'on'}  = JSON::true;
    $obj->{'brightness'}  = int($value);
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );

  } elsif($name && $cmd eq "dimUp") {
    my $pct = ReadingsVal($name,"pct","0");
    $pct += 10;
    $pct = 100 if( $pct > 100 );
    $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
    $obj->{'brightness'}  = 0+$pct;
    $obj->{'transitiontime'} = 1;
    #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
    $defs{$name}->{helper}->{update_timeout} = 0;

  } elsif($name && $cmd eq "dimDown") {
    my $pct = ReadingsVal($name,"pct","0");
    $pct -= 10;
    $pct = 0 if( $pct < 0 );
    $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
    $obj->{'brightness'}  = 0+$pct;
    $obj->{'transitiontime'} = 1;
    #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
    $defs{$name}->{helper}->{update_timeout} = 0;

  } elsif($cmd eq "satUp") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'sat_inc'}  = 10;
      $obj->{'sat_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "satDown") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'sat_inc'}  = -10;
      $obj->{'sat_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "hueUp") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'hue_inc'}  = 30;
      $obj->{'hue_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "hueDown") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'hue_inc'}  = -30;
      $obj->{'hue_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "ctUp") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'ct_inc'}  = 16;
      $obj->{'ct_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "ctDown") {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'ct_inc'}  = -16;
      $obj->{'ct_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "ct") {
    $obj->{'on'}  = JSON::true;
    $value = int(1000000/$value) if( $value < 1000 );
    $obj->{'ct'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "hue") {
    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "sat") {
    $obj->{'on'}  = JSON::true;
    $obj->{'sat'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif( $cmd eq "rgb" && $value =~ m/^(..)(..)(..)/) {
    my( $r, $g, $b ) = (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);

      my( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

      $obj->{'on'}  = JSON::true;
      $obj->{'hue'} = int( $h * 359 );
      $obj->{'sat'} = int( $s * 100 );
      $obj->{'brightness'} = int( $v * 100 );
  } elsif( $cmd eq "hsv" && $value =~ m/^(..)(..)(..)/) {
    my( $h, $s, $v ) = (hex($1), hex($2), hex($3));

    $s = 100 if( $s > 100 );
    $v = 100 if( $v > 100 );

    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = int($h*100);
    $obj->{'sat'}  = 0+$s;
    $obj->{'brightness'}  = 0+$v;
  } elsif( $cmd eq "effect" ) {
    $obj->{'select'} = "$value";
    $obj->{'select'} .= " $value2" if( $value2 );
    $obj->{'select'} .= " ". join(" ", @a) if( @a );
  } elsif( $cmd eq "transitiontime" ) {
    $obj->{'transitiontime'} = 0+$value;
  } elsif( $name &&  $cmd eq "delayedUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 1;
  } elsif( $name &&  $cmd eq "immediateUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 0;
  } elsif( $name &&  $cmd eq "noUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = -1;
  } else {
    return 0;
  }

  return 1;
}
sub
Aurora_Set($@)
{
  my ($hash, $name, @aa) = @_;
  my ($cmd, @args) = @aa;

  my %obj;

  $hash->{helper}->{update_timeout} =  AttrVal($name, "delayedUpdate", 1);

  if( (my $joined = join(" ", @aa)) =~ /:/ ) {
    my @cmds = split(":", $joined);
    for( my $i = 0; $i <= $#cmds; ++$i ) {
      Aurora_SetParam($name, \%obj, split(" ", $cmds[$i]) );
    }
  } else {
    my ($cmd, $value, $value2, @a) = @aa;

    if( $cmd eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      Aurora_GetUpdate($hash);
      return undef;
    }

    Aurora_SetParam($name, \%obj, $cmd, $value, $value2, @a);
  }
#Log 1, Dumper \%obj;

  if( %obj ) {
    if( defined($obj{on}) ) {
      $hash->{desired} = $obj{on}?1:0;
    }

    if( !defined($obj{transitiontime}) ) {
      my $transitiontime = AttrVal($name, "transitiontime", undef);

      $obj{transitiontime} = 0 + $transitiontime if( defined( $transitiontime ) );
    }
  }

  if( scalar keys %obj ) {
    my($err,$data) = HttpUtils_NonblockingGet({
      url => "http://$hash->{IP}:16021/api/v1/$attr{$name}{token}/".($obj{select}?"effects":"state"),
      timeout => 2,
      method => 'PUT',
      noshutdown => $hash->{noshutdown},
      hash => $hash,
      type => 'state',
      data => encode_json(\%obj),
      callback => \&Aurora_dispatch,
    });

    SetExtensionsCancel($hash);

    $hash->{".triggerUsed"} = 1;

    return undef;
  }

  my $list = "off:noArg on:noArg toggle:noArg statusRequest:noArg";
  $list .= " pct:colorpicker,BRI,0,1,100";
  $list .= " rgb:colorpicker,RGB";
  $list .= " color:colorpicker,CT,1200,10,6500";
  $list .= " hue:colorpicker,HUE,0,1,359 sat:slider,0,1,100";

  $list .= " dimUp:noArg dimDown:noArg";

  #$list .= " alert:none,select,lselect";

  #$list .= " dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%";

  if( $hash->{helper}{effects} ) {
    my $effects = join(',',@{$hash->{helper}{effects}});
    $effects =~ s/\s/#/g;
    $list .= " effect:,$effects";
  }

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
Aurora_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "rgb") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+)/ ) {
        ($r,$g,$b) = cttorgb(1000000/$1);
      }
    } else {
      my $h = ReadingsVal($name,"hue",0) / 359.0;
      my $s = ReadingsVal($name,"sat",0) / 100.0;
      my $v = ReadingsVal($name,"pct",0) / 100.0;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif($cmd eq "RGB") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = cttorgb($1);
      }
    } else {
      my $h = ReadingsVal($name,"hue",0) / 359.0;
      my $s = ReadingsVal($name,"sat",0) / 100.0;
      my $v = 1;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif ( $cmd eq "devStateIcon" ) {
    return Aurora_devStateIcon($hash);
  }

  return "Unknown argument $cmd, choose one of rgb:noArg RGB:noArg devStateIcon:noArg";
}


###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
Aurora_ReadFromServer($@)
{
  my ($hash,@a) = @_;

  my $name = $hash->{NAME};
  no strict "refs";
  my $ret;
  unshift(@a,$name);
  #$ret = IOWrite($hash, @a);
  $ret = IOWrite($hash,$hash,@a);
  use strict "refs";
  return $ret;
  return if(IsDummy($name) || IsIgnored($name));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log3 $name, 5, "No I/O device or ReadFn found for $name";
    return;
  }

  no strict "refs";
  #my $ret;
  unshift(@a,$name);
  $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

sub
Aurora_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Aurora_GetUpdate", $hash, 0) if( $hash->{INTERVAL} );
  }

  return undef if(IsDisabled($name));

  my ($now) = gettimeofday();
  if( $hash->{LOCAL} || $now - $hash->{helper}{last_config_timestamp} > 300 ) {
    my($err,$data) = HttpUtils_NonblockingGet({
      url => "http://$hash->{IP}:16021/api/v1/$attr{$name}{token}",
      timeout => 2,
      method => 'GET',
      noshutdown => $hash->{noshutdown},
      hash => $hash,
      type => 'state',
      callback => \&Aurora_dispatch,
    });

    $hash->{helper}{last_config_timestamp} = $now;

  } else {
    my($err,$data) = HttpUtils_NonblockingGet({
      url => "http://$hash->{IP}:16021/api/v1/$attr{$name}{token}/state",
      timeout => 2,
      method => 'GET',
      noshutdown => $hash->{noshutdown},
      hash => $hash,
      type => 'state',
      callback => \&Aurora_dispatch,
    });

  }

  return undef;
}

sub
AuroraSetIcon($;$)
{
  my ($hash,$force) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  my $name = $hash->{NAME};

  return if( defined($attr{$name}{icon}) && !$force );
}
sub
Aurora_Parse($$)
{
  my($hash,$result) = @_;
  my $name = $hash->{NAME};

  if( ref($result) ne "HASH" ) {
    if( ref($result) && $Aurora_hasDataDumper) {
      Log3 $name, 2, "$name: got wrong status message for $name: ". Dumper $result;
    } else {
      Log3 $name, 2, "$name: got wrong status message for $name: $result";
    }
    return undef;
  }

  Log3 $name, 4, "parse status message for $name";
  Log3 $name, 5, Dumper $result if($Aurora_hasDataDumper);

  $hash->{name} = $result->{name} if( defined($result->{name}) );
  $hash->{serialNo} = $result->{serialNo} if( defined($result->{serialNo}) );
  $hash->{manufacturer} = $result->{manufacturer} if( defined($result->{manufacturer}) );
  $hash->{model} = $result->{model} if( defined($result->{model}) );
  $hash->{firmwareVersion} = $result->{firmwareVersion} if( defined($result->{firmwareVersion}) );

  if( my $effects = $result->{effects} ) {
    $hash->{helper}{effects} = $effects->{effectsList} if( defined($effects->{effectsList}) );

    if( my $effect = $effects->{select} ) {
      if( $effect ne $hash->{helper}{effect} ) { readingsSingleUpdate($hash, 'effect', $effect, 1 ) };
      $hash->{helper}{effect} = $effect;
    }
  }

  $attr{$name}{devStateIcon} = '{(Aurora_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

  if( !defined($attr{$name}{webCmd}) ) {
    $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:ct 490:ct 380:ct 270:ct 160:effect:on:off';
    #$attr{$name}{webCmd} = 'hue:rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:toggle:on:off';
    #$attr{$name}{webCmd} = 'ct:ct 490:ct 380:ct 270:ct 160:toggle:on:off';
    #$attr{$name}{webCmd} = 'pct:toggle:on:off';
    #$attr{$name}{webCmd} = 'toggle:on:off';
  }

  readingsBeginUpdate($hash);

  my $state = $result;
  $state = $state->{'state'} if( defined($state->{'state'}) );

  my $on        = $state->{on}{value};
     $on = $hash->{helper}{on} if( !defined($on) );
  my $colormode = $state->{'colorMode'};
  my $pct       = $state->{'brightness'}{value};
     $pct = $hash->{helper}{pct} if( !defined($pct) );
  my $ct        = $state->{'ct'}{value};
  my $hue       = $state->{'hue'}{value};
  my $sat       = $state->{'sat'}{value};
  my $alert = $state->{alert};
  my $effect = $state->{effect};

  if( defined($colormode) && $colormode ne $hash->{helper}{colormode} ) {readingsBulkUpdate($hash,"colormode",$colormode);}
  if( defined($ct) && $ct != $hash->{helper}{ct} ) {
    if( $ct == 0 ) {
      readingsBulkUpdate($hash,"ct",$ct);
    }
    else {
      readingsBulkUpdate($hash,"ct",$ct);
    }
  }
  if( defined($hue) && $hue != $hash->{helper}{hue} ) {readingsBulkUpdate($hash,"hue",$hue);}
  if( defined($sat) && $sat != $hash->{helper}{sat} ) {readingsBulkUpdate($hash,"sat",$sat);}
  if( defined($alert) && $alert ne $hash->{helper}{alert} ) {readingsBulkUpdate($hash,"alert",$alert);}
  if( defined($effect) && $effect ne $hash->{helper}{effect} ) {readingsBulkUpdate($hash,"effect",$effect);}

  my $s = '';
  if( $on )
    {
      $s = 'on';
      if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",1);}

      $s = 'off' if( $pct == 0 );

    }
  else
    {
      $on = 0;
      $s = 'off';
      $pct = 0;
      if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",0);}
    }

  if( $pct != $hash->{helper}{pct} ) {readingsBulkUpdate($hash,"pct", $pct);}
  #if( $pct != $hash->{helper}{pct} ) {readingsBulkUpdate($hash,"level", $pct . ' %');}

  $hash->{helper}{on} = $on if( defined($on) );
  $hash->{helper}{colormode} = $colormode if( defined($colormode) );
  $hash->{helper}{ct} = $ct if( defined($ct) );
  $hash->{helper}{hue} = $hue if( defined($hue) );
  $hash->{helper}{sat} = $sat if( defined($sat) );
  $hash->{helper}{alert} = $alert if( defined($alert) );
  $hash->{helper}{effect} = $effect if( defined($effect) );

  $hash->{helper}{pct} = $pct;

  my $changed = $hash->{CHANGED}?1:0;

  if( $s ne $hash->{STATE} ) {readingsBulkUpdate($hash,"state",$s);}

  readingsEndUpdate($hash,1);

  if( defined($colormode) ) {
    my $rgb = CommandGet("","$name rgb");
    if( $rgb ne $hash->{helper}{rgb} ) { readingsSingleUpdate($hash,"rgb", $rgb,1); };
    $hash->{helper}{rgb} = $rgb;
  }

  $hash->{helper}->{update_timeout} = -1;
  #RemoveInternalTimer($hash);

  return $changed;
}

sub
Aurora_Attr($$$;$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return;
}

1;

=pod
=item summary    nanoleaf aurora
=item summary_DE nanoleaf aurora
=begin html

<a name="Aurora"></a>
<h3>Aurora</h3>
<ul>
  <br>
  <a name="Aurora_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Aurora &lt;ip&gt; [&lt;interval&gt;]</code><br>
    <br>

    Defines a device connected to a <a href="#Aurora">Aurora</a>.<br><br>

    The device status will be updated every &lt;interval&gt; seconds. 0 means no updates.
    Groups are updated only on definition and statusRequest<br><br>

    Examples:
    <ul>
      <code>define aurora Aurora 10.0.1.xxx 10</code><br>
    </ul>
  </ul><br>

  <a name="Aurora_Readings"></a>
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
    <li>pct<br>
    the current brightness in percent</li>
    <li>onoff<br>
    the current on/off state as 0 or 1</li>
    <li>sat<br>
    the current saturation</li>
    <li>state<br>
    the current state</li>
    <br>
    Notes:
      <ul>
      <li>with current bridge firware versions groups have <code>all_on</code> and <code>any_on</code> readings,
          with older firmware versions groups have no readings.</li>
      <li>not all readings show the actual device state. all readings not related to the current colormode have to be ignored.</li>
      <li>the actual state of a device controlled by a living colors or living whites remote can be different and will
          be updated after some time.</li>
      </ul><br>
  </ul><br>

  <a name="Aurora_Set"></a>
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
      <li>bri &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set brighness to &lt;value&gt;; range is 0-254.</li>
      <li>dimUp [delta]</li>
      <li>dimDown [delta]</li>
      <li>ct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set colortemperature to &lt;value&gt; in mireds (range is 154-500) or kelvin (rankge is 2000-6493).</li>
      <li>ctUp [delta]</li>
      <li>ctDown [delta]</li>
      <li>hue &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set hue to &lt;value&gt;; range is 0-65535.</li>
      <li>humUp [delta]</li>
      <li>humDown [delta]</li>
      <li>sat &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set saturation to &lt;value&gt;; range is 0-254.</li>
      <li>satUp [delta]</li>
      <li>satDown [delta]</li>
      <li>effect &lt;name&gt;</li>
      <li>rgb &lt;rrggbb&gt;<br>
        set the color to (the nearest equivalent of) &lt;rrggbb&gt;</li>
      <br>
      <li><a href="#setExtensions"> set extensions</a> are supported.</li>
      <br>
      Note:
        <ul>
        <li>&lt;ramp-time&gt; is given in seconds</li>
        <li>multiple paramters can be set at once separated by <code>:</code><br>
          Examples:<br>
            <code>set LC on : transitiontime 100</code><br>
            <code>set bulb on : bri 100 : color 4000</code><br></li>
        </ul>
    </ul><br>

  <a name="Aurora_Get"></a>
    <b>Get</b>
    <ul>
      <li>rgb</li>
      <li>RGB</li>
      <li>devStateIcon<br>
      returns html code that can be used to create an icon that represents the device color in the room overview.</li>
    </ul><br>

  <a name="Aurora_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>color-icon<br>
      1 -> use lamp color as icon color and 100% shape as icon shape<br>
      2 -> use lamp color scaled to full brightness as icon color and dim state as icon shape</li>
    <li>transitiontime<br>
      default transitiontime for all set commands if not specified directly in the set.</li>
    <li>delayedUpdate<br>
      1 -> the update of the device status after a set command will be delayed for 1 second. usefull if multiple devices will be switched.
</li>
    <li>devStateIcon<br>
      will be initialized to <code>{(Aurora_devStateIcon($name),"toggle")}</code> to show device color as default in room overview.</li>
    <li>webCmd<br>
      will be initialized to a device specific value</li>
  </ul>

</ul><br>

=end html
=cut
