##############################################
# $Id$
package main;

# See also https://avm.de/fileadmin/user_upload/Global/Service/Schnittstellen/AHA-HTTP-Interface.pdf
use strict;
use warnings;
use SetExtensions;

sub FBDECT_Parse($$@);
sub FBDECT_Set($@);
sub FBDECT_Get($@);

sub FBDECT_decodePayload($$$);
sub FBDECT_adjustHueSat($$);
sub FBDECT_colName($);
sub FBDECT_colVal($$$);
sub FBDECT_getDiscreteSat($$);

my @fbdect_models = qw(Powerline546E Dect200 CometDECT HAN-FUN);

my %fbdect_payload = (
   7 => { n=>"connected" },
   8 => { n=>"disconnected" },
  10 => { n=>"configChanged" },
  15 => { n=>"state",       fmt=>'hex($pyld)?"on":"off"' },
  16 => { n=>"relayTimes",  fmt=>'FBDECT_decodeRelayTimes($pyld)' },
  18 => { n=>"current",     fmt=>'sprintf("%0.4f A", hex($pyld)/10000)' },
  19 => { n=>"voltage",     fmt=>'sprintf("%0.3f V", hex($pyld)/1000)' },
  20 => { n=>"power",       fmt=>'sprintf("%0.2f W", hex($pyld)/100)' },
  21 => { n=>"energy",      fmt=>'sprintf("%0.0f Wh",hex($pyld))' },
  22 => { n=>"powerFactor", fmt=>'sprintf("%0.3f", hex($pyld))' },
  23 => { n=>"temperature", fmt=>'FBDECT_decodeTemp($pyld, $hash, $addReading)' },
  35 => { n=>"options",     fmt=>'FBDECT_decodeOptions($pyld)' },
  37 => { n=>"control",     fmt=>'FBDECT_decodeControl($pyld)' },
);


sub
FBDECT_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = ".*";
  $hash->{SetFn}     = "FBDECT_Set";
  $hash->{GetFn}     = "FBDECT_Get";
  $hash->{DefFn}     = "FBDECT_Define";
  $hash->{UndefFn}   = "FBDECT_Undef";
  $hash->{ParseFn}   = "FBDECT_Parse";
  $hash->{AttrList}  = 
    "IODev do_not_notify:1,0 ignore:1,0 dummy:1,0 showtime:1,0 ".
    "disable:0,1 disabledForIntervals ".
    "$readingFnAttributes " .
    "model:".join(",", sort @fbdect_models);
  $hash->{AutoCreate}= 
        { "FBDECT.*" => { 
             GPLOT => "power4:Power,",
             FILTER => "%NAME:power\\x3a.*",
             ATTR => "event-min-interval:power:120" } };
}


#############################
sub
FBDECT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name   = shift @a;
  my $type = shift(@a); # always FBDECT

  my $u = "wrong syntax for $name: define <name> FBDECT [FBAHAname:]id props";
  return $u if(int(@a) != 2);

  my $ioNameAndId = shift @a;
  my ($ioName, $id) = (undef, $ioNameAndId);
  if($ioNameAndId =~ m/^([^:]*):(.*)$/) {
    $ioName = $1; $id = $2;
  }
  $hash->{id} = $id;
  $hash->{props} = shift @a;
  $hash->{webCmd} = "desired-temp" if($hash->{props} =~ m/actuator/);

  $modules{FBDECT}{defptr}{$ioNameAndId} = $hash;
  AssignIoPort($hash, $ioName);
  return undef;
}
 
###################################
sub
FBDECT_SetHttp($@)
{
  my ($hash, @a) = @_;
  my %cmd;
  my $p = $hash->{props};
  my $name = $hash->{NAME};
  my $unittype = ReadingsVal($name, "unittype", "");

  $cmd{raw} = "textField";

  if($p =~ m/switch/) {
    $cmd{off} = $cmd{on} = $cmd{toggle} = "noArg";
  }
  if($p =~ m/actuator/) {
    $cmd{"desired-temp"} = "slider,7.5,0.5,28.5,1";
    $cmd{open} = $cmd{closed} = "noArg";
    $cmd{windowopen} = $cmd{boost} = "textField";
  }
  if($p =~ m/dimmer/) {
    $cmd{"dim"} = "slider,0,1,100,1";
  }
  if($p =~ m/HANFUNUnit/ && $unittype eq "BLIND") {
    $cmd{open} = $cmd{closed} = $cmd{stop} = "noArg";
  }
  if($p =~ m/HANFUNUnit/ && $unittype eq "DIMMABLE_COLOR_BULB") {
    $cmd{"color"} = "select,red,orange,yellow,lawngreen,green,turquoise,".
                        "cyan,azure,blue,violet,magenta,pink";
    $cmd{"satindex"}         = "slider,1,1,3,1";
    $cmd{"colortemperature"} = "colorpicker,CT,2700,100,6500";
    $cmd{"hue"}              = "colorpicker,HUE,0,1,359";
    $cmd{"saturation"}       = "slider,0,1,255";
    $cmd{off} = $cmd{on} = $cmd{toggle} = "noArg";
  }

  if(!$cmd{$a[1]}) {
    my $cmdList = join(" ", map { "$_:$cmd{$_}" } sort keys %cmd);
    return SetExtensions($hash, $cmdList, @a)
  }
  SetExtensionsCancel($hash);

  my $cmd = $a[1];
  return "" if(IsDisabled($name));
  Log3 $name, 3, "FBDECT set $name $cmd";
  my $ain = ReadingsVal($name,"AIN",0);

  if($cmd =~ m/^(on|off|toggle)$/) {
    IOWrite($hash, $ain, "setswitch$cmd");
    my $state = ($cmd eq "toggle" ? ($hash->{STATE} eq "on" ? "off":"on"):$cmd);
    readingsSingleUpdate($hash, "state", $state, 1);
    return undef;
  }

  if($cmd =~ m/^(open|closed|desired-temp)$/ && $p =~ m/actuator/) {
    if($cmd eq "desired-temp") { 
      return "Usage: set $name desired-temp value" if(int(@a) != 3);
      return "desired-temp must be between 7.5 and 28.5"
        if($a[2] !~ m/^[\d.]+$/ || $a[2] < 7.5 || $a[2] > 28.5)
    }
    my $a2 = ($a[2] ? $a[2] : 0);
    my $val = ($cmd eq "open"  || $a2==28.5) ? 254 :
              ($cmd eq "closed"|| $a2== 7.5) ? 253: int(2*$a2);
    IOWrite($hash, $ain,"sethkrtsoll&param=$val");
    return undef;
  }

  if($cmd =~ m/^(boost|windowopen)$/ && $p =~ m/actuator/) {
    return "Usage: set $name $cmd duration" if(int(@a) != 3);
    return "duration must be between 0 (deactivate) and 86400 (+24h)"
      if($a[2] !~ m/^\d+$/ || $a[2] > 86400);
    my $endtimestamp = ($a[2] == 0 ? 0 : (time() + $a[2]));

    if($cmd eq "boost") {
      Log3 $name,5, "$name: raw sethkrboost&endtimestamp=$endtimestamp";
      IOWrite($hash, $ain, "sethkrboost&endtimestamp=$endtimestamp");

    } elsif ($cmd eq "windowopen") {
      Log3 $name,5, "$name: raw sethkrwindowopen&endtimestamp=$endtimestamp";
      IOWrite($hash, $ain, "sethkrwindowopen&endtimestamp=$endtimestamp");

    } 
    return undef;
  }

  if($cmd eq "dim") {
    return "Usage: set $name dim value"
        if(int(@a) != 3 || $a[2] !~ m/^\d+$/ || !($a[2]>=0 && $a[2]<=100));
    IOWrite($hash, $ain,"setlevelpercentage&level=$a[2]");
    return undef;
  }

  if($cmd =~ m/^(open|closed|stop)$/ &&
    $p =~ m/HANFUNUnit/ && $unittype eq "BLIND") {
    IOWrite($hash, $ain,"setblind&target=$cmd");
    return undef;
  }

  if($cmd eq "raw") {
    shift @a; shift @a;
    return "Usage set $name raw <arguments>" if(!@a);
    IOWrite($hash, $ain, join("&", @a));
    return undef;
  }

  if($cmd eq "color") {
    return "Usage: set $name color [colorname]"
        if(int(@a) != 2 && int(@a) != 3);
    my $color = defined($a[2]) ? $a[2] : FBDECT_colVal($hash,"color","yellow");
    my $satindex = FBDECT_colVal($hash, "satindex", 1);
    my ($hue, $saturation) = FBDECT_adjustHueSat($color, $satindex);
    $hash->{hue}        = $hue;
    $hash->{saturation} = $saturation;
    $hash->{color}      = $color;
    Log3 $name,5,
        "$name: raw setcolor&hue=$hue&saturation=$saturation&duration=0";
    IOWrite($hash, $ain, "setcolor&hue=$hue&saturation=$saturation&duration=0");
    return undef;
  }
  
  if($cmd eq "satindex") {
    return "Usage: set $name satindex [saturation-index]"
        if(int(@a) != 2 && int(@a) != 3);
    my $satindex = defined($a[2]) ? $a[2] : FBDECT_colVal($hash, "satindex", 1);
    my $color = FBDECT_colVal($hash, "color", "yellow");
    my ($hue, $saturation) = FBDECT_adjustHueSat($color,$satindex);
    $hash->{saturation} = $saturation;
    $hash->{satindex}   = $satindex;
    Log3 $name,5,
        "$name: raw setcolor&hue=$hue&saturation=$saturation&duration=0";
    IOWrite($hash, $ain, "setcolor&hue=$hue&saturation=$saturation&duration=0");
    return undef;
  }

  if($cmd eq "saturation") {
    return "Usage: set $name saturation value"
        if(int(@a) != 3 || $a[2] !~ m/^\d+$/ || !($a[2]>=0 && $a[2]<=255));
    my $color = FBDECT_colVal($hash, "color", "yellow");
    my $hue   = FBDECT_colVal($hash, "hue", 52);
    my $saturation = $a[2];
    my $satindex;
    ($satindex, $saturation) = FBDECT_getDiscreteSat($color, $saturation);
    $hash->{saturation} = $saturation;
    $hash->{satindex} = $satindex;
    Log3 $name,5,
        "$name: raw setcolor&hue=$hue&saturation=$saturation&duration=0";
    IOWrite($hash, $ain, "setcolor&hue=$hue&saturation=$saturation&duration=0");
    return undef;
  }
    
  if($cmd eq "colortemperature") {
    return "Usage: set $name colortemperature [temperature]"
        if(int(@a) != 2 && int(@a) != 3);
    my $initialTemperature = FBDECT_colVal($hash, "colortemperature", 4200);
    my $setTemperature = defined($a[2]) ? $a[2] : $initialTemperature;
    my $tempunit = "kelvin";
    my $colortemperature = $setTemperature;
    if($setTemperature < 2000) { # get temp in Kelvin if given in mireds
      $tempunit = "mired";
      $colortemperature = int(1000000 / $setTemperature + 0.5);
    }
    my @discreteTemp = (2700,3000,3400,3800,4200,4700,5300,5900,6500,99999);
    for(my $i = 0; $i < int(@discreteTemp)-1; $i++) {
      if($colortemperature <
         $discreteTemp[$i] + ($discreteTemp[$i+1]-$discreteTemp[$i])/2 ) {
           $colortemperature = $discreteTemp[$i];
           last;
      }
    }
    # sending setcolortemperature will switch the mode to white. Homebridge
    # sends ct (mireds) along with hue when in color mode => only
    # setcolortemperature if kelvin or if temp changed
    if($colortemperature != $initialTemperature || $tempunit eq "kelvin") {
      $hash->{colortemperature} = $colortemperature;
      Log3 $name,5, "$name: raw setcolortemperature&".
                        "temperature=$colortemperature&duration=0";
      IOWrite($hash, $ain,
                "setcolortemperature&temperature=$colortemperature&duration=0");
    }
    return undef;
  }

  if($cmd eq "hue") {
    return "Usage: set $name hue huevalue"
        if(int(@a) != 3 || $a[2] !~ m/^\d+$/ || !($a[2]>=0 && $a[2]<=359));
    my $satindex = FBDECT_colVal($hash, "satindex", 1);
    my $hue = $a[2];
    my $saturation;
    my @discreteHue = (35,52,92,120,160,195,212,225,266,296,335,358,9999);
    for(my $i = 0; $i < int(@discreteHue)-1; $i++) {
      if($hue < $discreteHue[$i] + ($discreteHue[$i+1]-$discreteHue[$i])/2 ) {
        $hue = $discreteHue[$i];
        last;
      }
    }
    my $color = FBDECT_colName($hue);
    ($hue, $saturation) = FBDECT_adjustHueSat($color,$satindex);
    $hash->{color} = $color;
    $hash->{hue} = $hue;
    $hash->{saturation} = $saturation;
    Log3 $name,5,
        "$name: raw setcolor&hue=$hue&saturation=$saturation&duration=0";
    IOWrite($hash, $ain, "setcolor&hue=$hue&saturation=$saturation&duration=0");
    return undef;
  }
  
  return "Internal Error, unknown command $cmd";
}

###################################
sub
FBDECT_Set($@)
{
  my ($hash, @a) = @_;
  my %sets = ("on"=>1, "off"=>1, "msgInterval"=>1);

  return FBDECT_SetHttp($hash, @a)
    if($hash->{IODev} && $hash->{IODev}{TYPE} eq "FBAHAHTTP");

  my $ret = undef;
  my $cmd = $a[1];
  if(!$sets{$cmd}) {
    my $usage =  join(" ", sort keys %sets);
    return SetExtensions($hash, $usage, @a);
  }
  SetExtensionsCancel($hash);

  my $name = $hash->{NAME};
  return "" if(IsDisabled($name));
  Log3 $name, 3, "FBDECT set $name $cmd";

  my $relay;
  if($cmd eq "on" || $cmd eq "off") {
    my $relay = sprintf("%08x%04x0000%08x", 15, 4, $cmd eq "on" ? 1 : 0);
    my $msg = sprintf("%04x0000%08x$relay", $hash->{id}, length($relay)/2);
    IOWrite($hash, "07", $msg);
    readingsSingleUpdate($hash, "state", "set_$cmd", 1);
  }
  if($cmd eq "msgInterval") {
    return "msgInterval needs seconds as parameter"
        if(!defined($a[2]) || $a[2] !~ m/^\d+$/);
    # Set timer for RELAY, CURRENT, VOLTAGE, POWER, ENERGY,
    # POWER_FACTOR, TEMP, RELAY_TIMES, 
    foreach my $i (24, 26, 27, 28, 29, 30, 31, 32) {
      my $txt = sprintf("%08x%04x0000%08x", $i, 4, $a[2]);
      my $msg = sprintf("%04x0000%08x$txt", $hash->{id}, length($txt)/2);
      IOWrite($hash, "07", $msg);
    }
  }
  return undef;
}

sub
FBDECT_Get($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $cmd = ($a[1] ? $a[1] : "");
  my %gets = ("devInfo"=>1);

  if($hash->{IODev} && $hash->{IODev}{TYPE} eq "FBAHA") {
    return "Unknown argument $cmd, choose one of ".join(" ",sort keys %gets)
        if(!$gets{$cmd});
  } else {
    return "Unknown argument $cmd, choose one of ";
  }

  if($cmd eq "devInfo") {
    my @answ = FBAHA_getDevList($hash->{IODev}, $hash->{id});
    return $answ[0] if(@answ == 1);
   
    readingsBeginUpdate($hash);

    if($answ[0] && 
       $answ[0] =~ m/NAME:(.*), ID:(.*), (.*), TYPE:(.*) PROP:(.*)/) {
      readingsBulkUpdate($hash, "FBNAME", $1, 1);
      readingsBulkUpdate($hash, "FBTYPE", $4, 1);
      readingsBulkUpdate($hash, "FBPROP", $5, 1);
    }

    my $d = pop @answ;
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d, $hash, 0);
      Log3 $hash, 4, "Payload: $d -> $ptyp: $pyld";
      last if($ptyp eq "");
      readingsBulkUpdate($hash, $ptyp, $pyld, 1);
      push @answ, "  $ptyp: $pyld";
      $d = substr($d, 16+$plen*2);
    }
    readingsEndUpdate($hash, 1);
    return join("\n", @answ);
  }

  return undef;
}

my %fbhttp_readings = (
   absenk          => 'sprintf("night-temp:%.1f C", $val/2)',
   batterylow      => '"batterylow:$val"',
   celsius         => 'sprintf("temperature:%.1f C (measured)", $val/10)',
   energy          => 'sprintf("energy:%d Wh", $val)',
   etsideviceid    => '"etsideviceid:$val"',
   functionbitmask => '"FBPROP:$fbprop"',
   fwversion       => '"fwversion:$val"',
   id              => '"ID:$val"',
   identifier      => '"AIN:$val"',
   komfort         => 'sprintf("day-temp:%.1f C", $val/2)',
   level           => '"level:$val"',
   levelpercentage => '"dim:$val"',
   lock            => '"locked:".($val ? "yes":"no")',
   mode            => '"mode:$val"',
   name            => '"FBNAME:$val"',
   offset          => 'sprintf("tempadjust:%.1f C", $val/10)', # ??
   power           => 'sprintf("power:%.2f W", $val/1000)',
   present         => '"present:".($val?"yes":"no")',
   productname     => '"FBTYPE:$val"',
   rel_humidity    => '"rel_humidity:$val %"',
   state           => '"state:".($val?"on":"off")',
   voltage         => 'sprintf("voltage:%.3f V", $val/1000)',
#  tist => 'sprintf("temperature:%.1f C (measured)", $val/2)', # Forum #57644
   tsoll           => 'sprintf("desired-temp:%s", $val)',
   members         => '"members:$val"',
   devicelock      => '"devicelock:".($val ? "yes":"no")',
   unittype        => '"unittype:".($unittype{$val} ? $unittype{$val} : $val)',
   errorcode       => '"errorcode:".($ecTxt{$val} ? $ecTxt{$val} : ">$val<")',
   windowopenactiv => '"windowopenactiv:".($val ? "yes":"no")',
   battery         => 'sprintf("battery:%s %%", $val)',
   endperiod       => 'sprintf("nextPeriodStart:%s", FmtDateTime($val))',
   tchange         => 'sprintf("nextPeriodTemp:%0.1f C", $val/2)',
   summeractive    => '"summeractive:".($val ? "yes":"no")',
   holidayactive   => '"holidayactive:".($val ? "yes":"no")',
   lastpressedtimestamp => '"lastpressedtimestamp:".($val=~m/^\d{10}$/ ? FmtDateTime($val) : "N/A")',
   lastpressedtimestamp_kurz => '"lastpressedtimestamp_kurz:$val"',
   lastpressedtimestamp_lang => '"lastpressedtimestamp_lang:$val"',
   lastpressedtimestamp_Oben_rechts =>'"lastpressedtimestamp_oben_rechts:$val"',
   lastpressedtimestamp_Unten_rechts=>'"lastpressedtimestamp_unten_rechts:$val"',
   lastpressedtimestamp_Oben_links =>'"lastpressedtimestamp_oben_links:$val"',
   lastpressedtimestamp_Unten_links=>'"lastpressedtimestamp_unten_links:$val"',
   hue             => '"hue:$val"',
   current_mode    => '"current_mode:$val"',
   saturation      => '"saturation:$val"',
   temperature     => '"colortemperature:$val"',
   windowopenactiveendtime => '"windowopenactiveendtime:".($val=~m/^\d{10}$/ ? FmtDateTime($val) : "N/A")',
   boostactive     => '"boostactive:".($val ? "yes":"no")',
   boostactiveendtime => '"boostactiveendtime:".($val=~m/^\d{10}$/ ? FmtDateTime($val) : "N/A")',
   masterdeviceid  => '"groupmasterid:$val"',
   lastalertchgtimestamp => '"lastalertchgtimestamp:".($val=~m/^\d{10}$/ ? FmtDateTime($val) : "N/A")',
);

sub
FBDECT_ParseHttp($$$)
{
  my ($iodev, $msg, $type) = @_;
  my $ioName = $iodev->{NAME};
  my %h;
  my $omsg;

  $omsg = $msg;
  $omsg =~ s,<([^/>]+?)>([^<]+?)<,$h{$1}=$2 if(!$h{$1}),ge; # Quick & Dirty:Tags
  $omsg = $msg;
  $omsg =~ s, ([a-z_]+?)="([^"]*)",$h{$1}=$2 if(!$h{$1}),ge; # Attributes

  if($h{lastpressedtimestamp}) { # Dect400/#94700, 440/#118303
    sub dp {
      my ($txt,$h,$ln) = (@_);
      $txt =~ s#<([^/\s>]+?)[^/]*?>(.*?)</\g1>#
        my ($n,$c) = ($1,$2);
        $ln = makeReadingName($1) if($n eq "name" && $c =~ m/:\s*(.*)$/);
        if($n eq "lastpressedtimestamp" && $ln) {
          $h->{"${n}_$ln"} = ($c =~ m/^\d{10}$/ ? FmtDateTime($c) : "N/A");
        }
        dp($c, $h) if($c && $c =~ m/^<.*>$/);
      #gex;
    }
    dp($msg, \%h);
  }

  my $ain = $h{identifier};
  $ain =~ s/[-: ]/_/g;

  my %ll = (
    0 => "HANFUN",
    2 => "lightSwitch",
    4 => "alarmSensor",
    5 => "avmButton",
    6 => "actuator",
    7 => "powerMeter",
    8 => "tempSensor",
    9 => "switch",
   10 => "repeater",
   11 => "microphone",
   13 => "HANFUNUnit",
   15 => "switch",
   16 => "dimmer",
   17 => "colorswitch",
  );
  my %ecTxt = (0 => "noError (0)",
               1 => "notMounted (1)",
               2 => "valveShortOrBatteryEmpty (2)",
               3 => "valveStuck (3)",
               4 => "installationPreparation (4)",
               5 => "installationInProgress (5)",
               6 => "installationIsAdapting (6)");
  my %unittype = (
    273 => "SIMPLE_BUTTONAHA-HTTP-API",
    256 => "SIMPLE_ON_OFF_SWITCHABLE",
    257 => "SIMPLE_ON_OFF_SWITCH",
    262 => "AC_OUTLET",
    263 => "AC_OUTLET_SIMPLE_POWER_METERING",
    264 => "SIMPLE_LIGHT",
    265 => "DIMMABLE_LIGHT",
    266 => "DIMMER_SWITCH",
    277 => "COLOR_BULB",
    278 => "DIMMABLE_COLOR_BULB",
    281 => "BLIND",
    282 => "LAMELLAR",
    512 => "SIMPLE_DETECTOR",
    513 => "DOOR_OPEN_CLOSE_DETECTOR",
    514 => "WINDOW_OPEN_CLOSE_DETECTOR",
    515 => "MOTION_DETECTOR",
    518 => "FLOOD_DETECTOR",
    519 => "GLAS_BREAK_DETECTOR",
    520 => "VIBRATION_DETECTOR",
    640 => "SIREN",
  );


  my $lsn = int($h{functionbitmask});
  my @fb;
  map { push @fb, $ll{$_} if((1<<$_) & $lsn) } sort keys %ll;
  my $fbprop = join(",", @fb);
  $fbprop = "none" if(!$fbprop); # 85930

  my $dp = $modules{FBDECT}{defptr};
  my $hash = $dp->{"$ioName:$ain"};
  $hash = $dp->{$ain}             if(!$hash);
  $hash = $dp->{"$ioName:$h{id}"} if(!$hash);
  $hash = $dp->{$h{id}}           if(!$hash);

  if(!$hash) {
    my $ret = "UNDEFINED FBDECT_${ioName}_$ain FBDECT $ioName:$ain $fbprop";
    Log3 $ioName, 3, "$ret, please define it";
    DoTrigger("global", $ret);
    return "";
  }

  $hash->{props} = $fbprop; # replace values from define
  $hash->{webCmd} = "desired-temp" if($hash->{props} =~ m/actuator/);
  readingsBeginUpdate($hash);
  Log3 $hash, 5, $hash->{NAME};
  foreach my $n (keys %h) {
    Log3 $hash, 5, "   $n = $h{$n}";
    next if(!$fbhttp_readings{$n});
    my $val = $h{$n};
    $val = ($val == 254 ? 28.5:
            $val == 253 ?  7.5 : sprintf("%0.1f C",$val/2))
      if($n eq "tsoll");
    $val = $type if($n eq "productname" && $val eq "");
    my ($ptyp,$pyld) = split(":", eval $fbhttp_readings{$n}, 2);
    readingsBulkUpdate($hash, "state", "$ptyp: $pyld") if($n eq "tsoll");
    readingsBulkUpdate($hash, $ptyp, $pyld);
    readingsBulkUpdate($hash, "batteryState", $pyld ? "low" : "ok")
        if($ptyp eq "batterylow");
    readingsBulkUpdate($hash, "batteryPercent", $val) # 87575/96302
        if($ptyp eq "battery");
    if($val && $ptyp eq "colortemperature") {
      readingsBulkUpdate($hash, "colortemperaturemireds",
                $val>0 ? int(1000000/$val+0.5) : "");
      readingsBulkUpdate($hash, $ptyp, $val);
      $hash->{$ptyp} = $val;
    }
    if($val && $ptyp eq "hue") {
      readingsBulkUpdate($hash, "color", FBDECT_colName($val));
      $hash->{color} = FBDECT_colName($val);
      $hash->{hue} = $val;
    }
    if ($val && $ptyp eq "saturation") {
      my $color = FBDECT_colVal($hash, "color", "yellow");
      my ($satindex, $sat) = FBDECT_getDiscreteSat($color, $val);
      readingsBulkUpdate($hash, "satindex", $satindex);
      $hash->{saturation} = $val;
      $hash->{satindex} = $satindex;
    }
    readingsBulkUpdate($hash, "colormode", $val eq "1" ? "color" : "white")
        if($ptyp eq "current_mode");

  }
  readingsEndUpdate($hash, 1);

  return $hash->{NAME};
}

sub
FBDECT_renameIoDev($$)  # Called from FBAHAHTTP
{
  my ($new, $old) = @_;
  my $dp = $modules{FBDECT}{defptr};
  for my $ok (keys %{$dp}) {
    my $nk = $ok;
    $nk =~ s/^$old:/$new:/;
    next if($nk eq $ok);
    $dp->{$nk} = $dp->{$ok};
    delete $dp->{$ok};
  }
}

###################################
sub
FBDECT_Parse($$@)
{
  my ($iodev, $msg, $local) = @_;

  return FBDECT_ParseHttp($iodev, $msg, $1) if($msg =~ m/^<(device|group) /);

  my $mt = substr($msg, 0, 2);
  my $ioName = $iodev->{NAME};
  if($mt ne "07" && $mt ne "04") {
    Log3 $ioName, 1, "FBDECT: unknown message type $mt";
    return "";  # Nobody else is able to handle this
  }

  my $id = hex(substr($msg, 16, 4));
  my $hash = $modules{FBDECT}{defptr}{"$ioName:$id"};
  $hash = $modules{FBDECT}{defptr}{$id} if(!$hash);
  if(!$hash) {
    my $ret = "UNDEFINED FBDECT_${ioName}_$id FBDECT $ioName:$id switch";
    Log3 $ioName, 3, "$ret, please define it";
    DoTrigger("global", $ret);
    return "";
  }

  readingsBeginUpdate($hash);

  if($mt eq "07") {
    my $d = substr($msg, 32);
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d, $hash, 1);
      Log3 $hash, 4, "Payload: $d -> $ptyp: $pyld";
      last if($ptyp eq "");
      readingsBulkUpdate($hash, $ptyp, $pyld);
      $d = substr($d, 16+$plen*2);
    }
  }
  if($mt eq "04") {
    my @answ = FBAHA_configInd(substr($msg,16), $id);
    my $state = "";
    if($answ[0] =~ m/ inactive,/) {
      $state = "inactive";

    } else {
      my $d = pop @answ;
      while($d) {
        if(length($d) <= 16) {
          push @answ, "FBDECT_DECODE_ERROR:short payload $d";
          last;
        }
        my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d, $hash, 1);
        last if($ptyp eq "");
        push @answ, "  $ptyp: $pyld";
        $d = substr($d, 16+$plen*2);
      }
      Log3 $iodev, 4, "FBDECT PARSED: ".join(" / ", @answ);
      # Ignore the rest, is too confusing.
      @answ = grep /state:/, @answ;
      (undef, $state) = split(": ", $answ[0], 2) if(@answ > 0);
    }
    readingsBulkUpdate($hash, "state", $state) if($state);
  }

  readingsEndUpdate($hash, 1);
  Log3 $iodev, 5, "FBDECT_Parse for device $hash->{NAME} done";
  return $hash->{NAME};
}

sub
FBDECT_decodeRelayTimes($)
{
  my ($p) = @_;
  return "unknown"  if(length($p) < 16);
  return "disabled" if(substr($p, 12, 4) eq "0000");
  return $p;
}

sub
FBDECT_decodeTemp($$$)
{
  my ($p, $hash, $addReading) = @_;

  my $v = hex(substr($p,0,8));
  $v = -(4294967296-$v) if($v > 2147483648);
  $v /= 10;
  if(hex(substr($p,8,8))+0) {
    readingsBulkUpdate($hash, "tempadjust", sprintf("%0.1f C", $v))
        if($addReading);
    return "";
  }
  return sprintf("%0.1f C (measured)", $v);
}

sub
FBDECT_decodeOptions($)
{
  my ($p) = @_;
  my @opts;

  return "uninitialized" if($p eq "0000ffff");
  if(length($p) >= 8) {
    my $o = hex(substr($p,0,8));
    push @opts, "powerOnState:".($o==0 ? "off" : ($o==1?"on" : "last"));
  }
  if(length($p) >= 16) {
    my $o = hex(substr($p,8,8));
    my @lo;
    push @lo, "none" if($o == 0);
    push @lo, "webUi"    if($o & 1);
    push @lo, "remoteFB" if($o & 2);
    push @lo, "button"   if($o & 4);
    push @opts, "lock:".join(",", @lo);
  }
  return join(",", @opts);
}

sub
FBDECT_decodeControl($)
{
  my ($p) = @_;
  my @ctrl;

  for(my $off=8; $off+28<=length($p)/2; $off+=28) {

    if(substr($p,($off+ 8)*2,24) eq "000000050000000000000000") {
      push @ctrl, "disabled";
      next;
    }

    my ($n, $s);
    $s = "on";

    $n = hex(substr($p,($off+ 4)*2,8));
    $s .= " ".($fbdect_payload{$n} ? $fbdect_payload{$n}{n} : "fn=$n");

    my %tbl = (3=>">", 4=>"=>", 5=>"<", 6=>"<=");
    $n = hex(substr($p,($off+ 8)*2,8));
    $s .= " ".($tbl{$n} ? $tbl{$n} : "rel=$n");

    $n = hex(substr($p,($off+12)*2,8));
    $s .= sprintf(" %0.2f", $n/100);

    $n = hex(substr($p,($off+16)*2,8));
    $s .= " delay:${n}sec";

    $n = hex(substr($p,($off+20)*2,8));
    $s .= " do:".($fbdect_payload{$n} ? $fbdect_payload{$n}{n} : "fn=$n");

    $n = hex(substr($p,($off+24)*2,8));
    $s .= " ".($n==0 ? "off" : "on");

    push @ctrl, $s;
  }

  return join(",", @ctrl);
}

sub
FBDECT_decodePayload($$$)
{
  my ($d, $hash, $addReading) = @_;
  if(length($d) < 12) {
    Log3 $hash, 4, "FBDECT ignoring payload: data too short";
    return ("", "", "");
  }

  my $ptyp = hex(substr($d, 0, 8));
  my $plen = hex(substr($d, 8, 4));
  if(length($d) < 16+$plen*2) {
    Log3 $hash, 4,
        "FBDECT ignoring payload: data shorter than given length($plen)";
    return ("", "", "");
  }
  my $pyld = substr($d, 16, $plen*2);

  if($fbdect_payload{$ptyp}) {
    $cmdFromAnalyze = $fbdect_payload{$ptyp}{fmt};
    $pyld = eval $cmdFromAnalyze if($cmdFromAnalyze);
    $cmdFromAnalyze = undef;

    $ptyp = ($pyld ? $fbdect_payload{$ptyp}{n} : "");
  }
  return ($ptyp, $plen, $pyld);
}

###################################
# Color helpers
my %colordefaults = (
  red       => { hue=>358, sat=>[180, 112, 54] },
  orange    => { hue=> 35, sat=>[214, 140, 72] },
  yellow    => { hue=> 52, sat=>[153, 102, 51] },
  lawngreen => { hue=> 92, sat=>[123,  79, 38] },
  green     => { hue=>120, sat=>[160,  82, 38] },
  turquoise => { hue=>160, sat=>[145,  84, 41] },
  cyan      => { hue=>195, sat=>[179, 118, 59] },
  azure     => { hue=>212, sat=>[169, 110, 56] },
  blue      => { hue=>225, sat=>[204, 135, 67] },
  violet    => { hue=>266, sat=>[169, 110, 54] },
  magenta   => { hue=>296, sat=>[140,  92, 46] },
  pink      => { hue=>335, sat=>[180, 107, 51] }
);

sub
FBDECT_adjustHueSat($$)
{
  my ($color, $satindex) = @_;
  return FBDECT_adjustHueSat("yellow", $satindex) if(!$colordefaults{$color});
  return FBDECT_adjustHueSat($color, 1) if($satindex < 1 || $satindex > 3);
  return ($colordefaults{$color}{hue},$colordefaults{$color}{sat}[$satindex-1]);
}

sub
FBDECT_colName($)
{
  my ($hue) = @_;
  foreach my $k (keys %colordefaults) {
    return $k if($hue eq $colordefaults{$k}{hue});
  }
  return "yellow";
}

sub
FBDECT_colVal($$$)
{
  my ($hash,$cname,$default) = @_;
  return $hash->{$cname} if($hash->{$cname});
  return ReadingsVal($hash->{NAME}, $cname, $default);
}


sub
FBDECT_getDiscreteSat($$)
{
  my ($color, $saturation) = @_;
  my $satindex = 3;
  $color = "yellow" if(!$colordefaults{$color});
  my @discreteSat = reverse (9999, @{$colordefaults{$color}{sat}});
  for(my $i=0; $i<3; $i++) {
    if($saturation <
       $discreteSat[$i] + ($discreteSat[$i+1]-$discreteSat[$i])/2 ) {
      $saturation = $discreteSat[$i];
      $satindex = 3 - $i;
      last;
    }
  }
  return ($satindex, $saturation);
}

#####################################
sub
FBDECT_Undef($$)
{
  my ($hash, $arg) = @_;
  my $homeId = $hash->{homeId};
  my $id = $hash->{id};
  delete $modules{FBDECT}{defptr}{$id};
  return undef;
}

1;

=pod
=item summary    DECT devices connected via the Fritz!OS AHA Server
=item summary_DE &uuml;ber den Fritz!OS AHA Server angebundene DECT Ger&auml;te
=begin html

<a name="FBDECT"></a>
<h3>FBDECT</h3>
<ul>
  This module is used to control AVM FRITZ!DECT devices via FHEM, see also the
  <a href="#FBAHA">FBAHA</a> or <a href="#FBAHAHTTP">FBAHAHTTP</a> module for
  the base.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT [&lt;FBAHAname&gt;:]&lt;id&gt; props</code>
  <br>
  <br>
  Example:
  <ul>
    <code>define lamp FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Note:</b>Usually the device is created via
  <a href="#autocreate">autocreate</a>. If you rename the corresponding FBAHA
  device, take care to modify the FBDECT definitions, as it is not done
  automatically.
  </ul>
  <br>
  <br>

  <a name="FBDECTset"></a>
  <b>Set</b>
  Note: not all commands are supported for all devices.
  <ul>
  <li>on/off<br>
    set the device on or off.
    </li>

  <li>dim &lt;value&gt;<br>
    dim the device (if it is supported), value is between 0 and 100 (in %)
    </li>

  <li>open/close/stop<br>
    set the blind correspondingly
    </li>

  <li>desired-temp &lt;value&gt;<br>
    set the desired temp on a Comet DECT (FBAHAHTTP IOdev only). The value 7.5
    corresponds to off, and 28.5 to on.
    </li>

  <li>boost &lt;duration&gt;<br>
    set the boost mode on a Comet/Fritz DECT 301 (FBAHAHTTP IOdev only) for 
    duration in seconds.
    The value 0 means deactivate previously set boost mode.
    </li>

  <li>windowopen &lt;duration&gt;<br>
    set the windowopen mode on a Comet/Fritz DECT (FBAHAHTTP IOdev only) for 
    duration in seconds.
    The value 0 means deactivate previously set windowopen mode.
    </li>

  <li><a href="#setExtensions">set extensions</a> are supported.
   </li>

  <li>msgInterval &lt;sec&gt;<br>
    Number of seconds between the sensor messages (FBAHA IODev only).
    </li>

  <li>color &lt;colorname&gt;<br>
    Color name for color bulbs: red, orange, yellow, lawngreen, green, 
    turquoise, cyan, azure, blue, violet, magenta, pink.
    If the bulb was in "white" mode, it will change to "color" mode.
    </li>

  <li>colortemperature &lt;temperature&gt;<br>
    Color temperature in Kelvin (&gt; 2000) otherwise micro-reciprocal degrees
    (mired).  If temperature is not given, it will only change from "color" to
    "white" mode.  As the Fritzbox only accepts pre-defined values, it will be
    set back to the nearest authorized value in Kelvin (run <i>set
    &lt;devicename&gt; raw getcolordefaults</i> to know the accepted values).
    If the bulb was in "color" mode, it will change to "white" mode, except if
    temperature given in mireds leads to no change of temperature in Kelvin.
    </li>

  <li>sat_index &lt;index&gt;<br>
    Index from 1 to 3 of accepted saturation levels. Sets the bulb to the 
    corresponding saturation for the set color.
    If the bulb was in "white" mode, it will change to "color" mode.
    </li>

  <li>hue &lt;huevalue&gt;<br>
    Hue value from 0 to 359. As the Fritzbox only accepts pre-defined values,
    it will be set back to the nearest authorized value.  (run <i>set
    &lt;devicename&gt; raw getcolordefaults</i> to know the accepted values).
    The saturation will change to the accepted saturation for the color and
    sat_index set.  If the bulb was in "white" mode, it will change to "color"
    mode.  </li>

  <li>saturation &lt;value&gt;<br>
    Color saturation from 0 to 255. As the Fritzbox only accepts pre-defined
    values, it will be set back to the nearest authorized value for the set
    color (run <i>set &lt;devicename&gt; raw getcolordefaults</i> to know the
    accepted values for each color).  If the bulb was in "white" mode, it will
    change to "color" mode.  </li>

  <li>raw ...<br>
    Used for debugging.<br>
    Sends switchcmd=..., further parameters are joined with &amp;.
    </li>

  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
    report device information (FBAHA IODev only)
    </li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="FBDECTevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>set_on</li>
    <li>set_off</li>
    <li>current: $v A</li>
    <li>voltage: $v V</li>
    <li>power: $v W</li>
    <li>energy: $v Wh</li>
    <li>powerFactor: $v"</li>
    <li>temperature: $v C (measured)</li>
    <li>tempadjust: $v C</li>
    <li>options: uninitialized</li>
    <li>options: powerOnState:[on|off|last],lock:[none,webUi,remoteFb,button]</li>
    <li>control: disabled</li>
    <li>control: on power < $v delay:$d sec do:state [on|off]</li>
    <li>relaytimes: disabled</li>
    <li>relaytimes: HEX</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="FBDECT"></a>
<h3>FBDECT</h3>
<ul>
  Dieses Modul wird verwendet, um AVM FRITZ!DECT Ger&auml;te via FHEM zu
  steuern, siehe auch das <a href="#FBAHA">FBAHA</a> oder <a
  href="#FBAHAHTTP">FBAHAHTTP</a> Modul f&uuml;r die Anbindung an das FRITZ!Box.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT [&lt;FBAHAname&gt;:]&lt;id&gt; props</code>
  <br>
  <br>
  Beispiel:
  <ul>
    <code>define lampe FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Achtung:</b>FBDECT Eintr&auml;ge werden normalerweise per 
  <a href="#autocreate">autocreate</a> angelegt. Falls sie die zugeordnete 
  FBAHA oder FBAHAHTTP Instanz umbenennen, dann muss die FBDECT Definition
  manuell angepasst werden.
  </ul>
  <br>
  <br

  <a name="FBDECTset"></a>
  <b>Set</b>
  <ul>
  <li>on/off<br>
    Ger&auml;t einschalten bzw. ausschalten.</li>
  <li>desired-temp &lt;value&gt;<br>
    Gew&uuml;nschte Temperatur beim Comet DECT setzen. 7.5 entspricht aus, 28.5
    bedeutet an.
    </li>

  <li>boost &lt;Dauer&gt;<br>
    Versetzt den Comet/Fritz DECT 301 in boost Modus f&uuml;r Dauer in Sekunden.
    0 deaktiviert den boost Modus.
    </li>

  <li>windowopen &lt;Dauer&gt;<br>
    Versetzt den Comet/Fritz DECT 301 in windowopen Modus f&uuml;r Dauer in
    Sekunden. 0 deaktiviert den windowopen Modus.
    </li>

  <li>dim &lt;value&gt;<br>
    Helligkeit oder Rolladenstand (zwischen 0 und 100, in Prozent) setzen.
    </li>

  <li>open/close/stop<br>
    Rollade &ouml;ffnen, schlie&szlig;en oder stoppen.
    </li>

  <li>
    Die <a href="#setExtensions">set extensions</a> werden
    unterst&uuml;tzt.
    </li>
  <li>msgInterval &lt;sec&gt;<br>
    Anzahl der Sekunden zwischen den Sensornachrichten (nur mit FBAHA als
    IODev).
    </li>
    
  <li>color &lt;colorname&gt;<br>
    Farbname f&uuml;r Farbbirnen: rot, orange, gelb, grassgr&uuml;n, gr&uuml;n,
    t&uuml;rkis, cyan, himmelblau, blau, violett, magenta, rosa .  Wenn die
    Gl&uuml;hbirne im "white" Modus war, wechselt sie in den Modus "color"
    </li>

  <li>colortemperature &lt;Temperatur&gt;<br>
    Farbtemperatur in Kelvin wenn &gt; 2000 sonst mireds. Da die Fritzbox nur
    vordefinierte Werte unterst&uuml;tzt, wird sie auf den n&auml;chstliegenden
    unterst&uuml;tzten Wert in Kelvin zur&uuml;ckgesetzt (um die
    unterst&uuml;tzte Werte zu kennen, <i>set &lt;devicename&gt; raw
    getcolordefaults</i> ausführen).  Wenn die Gl&uuml;hbirne im "color" Modus
    war, wechselt sie in den Modus "white", ausser wenn die in mireds
    eingegebene Temperatur zu keine Aenderung der Temperatur in Kelvin
    f&uuml;hrt.  </li>

  <li>sat_index &lt;index&gt;<br>
    Index von 1 bis 3 der akzeptierten S&auml;ttigungsstufen. Setzt die
    Gl&uuml;hbirne auf die entsprechende S&auml;ttigung f&uuml;r die
    eingestellte Farbe.  Wenn die Gl&uuml;hbirne im "white" Modus war, wechselt
    sie in den Modus "color" </li>

  <li>hue &lt;huevalue&gt;<br>
    Hue Wert von 0 bis 359. Da die Fritzbox nur vordefinierte Werte
    unterst&uuml;tzt, wird sie auf den n&auml;chstliegenden unterst&uuml;tzten
    Wert zur&uuml;ckgesetzt (um die unterst&uuml;tzte Werte zu kennen, <i>set
    &lt;devicename&gt; raw getcolordefaults</i> ausführen).  Die
    S&auml;ttigung wird auf die f&uuml;r die Farbe und sat_index akzeptierte
    S&auml;ttigung ge&auml;ndert.  Wenn die Gl&uuml;hbirne im "white" Modus
    war, wechselt sie in den Modus "color" </li>

  <li>saturation &lt;Wert&gt;<br>
    Farbs&auml;ttigung von 0 bis 255. Da die Fritzbox nur vordefinierte Werte
    unterst&uuml;tzt, wird sie auf den n&auml;chstliegenden unterst&uuml;tzten
    Wert zur&uuml;ckgesetzt (um die unterst&uuml;tzte Werte zu kennen, <i>set
    &lt;devicename&gt; raw getcolordefaults</i> ausf&uuml;hren).  Wenn die
    Gl&uuml;hbirne im "white" Modus war, wechselt sie in den Modus "color"
    </li>

  <li>raw ...<br>
    Dient zum debuggen.<br>
    Sendet switchcmd=..., weitere Parameter werden per &amp; zusammengeklebt.
    </li>
  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
  meldet Ger&auml;te-Informationen (nur mit FBAHA als IODev)</li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="FBDECTevents"></a>
  <b>Generierte events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>set_on</li>
    <li>set_off</li>
    <li>current: $v A</li>
    <li>voltage: $v V</li>
    <li>power: $v W</li>
    <li>energy: $v Wh</li>
    <li>powerFactor: $v"</li>
    <li>temperature: $v C ([measured|corrected])</li>
    <li>options: uninitialized</li>
    <li>options: powerOnState:[on|off|last],lock:[none,webUi,remoteFb,button]</li>
    <li>control: disabled</li>
    <li>control: on power < $v delay:$d sec do:state [on|off]</li>
    <li>relaytimes: disabled</li>
    <li>relaytimes: HEX</li>
  </ul>
</ul>
=end html_DE

=cut
