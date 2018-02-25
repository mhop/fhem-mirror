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
sub FBDECT_Cmd($$@);

sub FBDECT_decodePayload($$$);

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

  if($p =~ m/switch/) {
    $cmd{off} = $cmd{on} = $cmd{toggle} = "noArg";
  }
  if($p =~ m/actuator/) {
    $cmd{"desired-temp"} = "slider,8,0.5,28,1";
    $cmd{open} = $cmd{closed} = "noArg";
  }
  if(!$cmd{$a[1]}) {
    my $cmdList = join(" ", map { "$_:$cmd{$_}" } sort keys %cmd);
    return SetExtensions($hash, $cmdList, @a)
  }
  SetExtensionsCancel($hash);

  my $cmd = $a[1];
  my $name = $hash->{NAME};
  return "" if(IsDisabled($name));
  Log3 $name, 3, "FBDECT set $name $cmd";

  if($cmd =~ m/^(on|off|toggle)$/) {
    IOWrite($hash, ReadingsVal($name,"AIN",0), "setswitch$cmd");
    my $state = ($cmd eq "toggle" ? ($hash->{state} eq "on" ? "off":"on"):$cmd);
    readingsSingleUpdate($hash, "state", $state, 1);
    return undef;
  }

  if($cmd =~ m/^(open|closed|desired-temp)$/) {
    if($cmd eq "desired-temp") { 
      return "Usage: set $name desired-temp value" if(int(@a) != 3);
      return "desired-temp must be between 8 and 28"
        if($a[2] !~ m/^[\d.]+$/ || $a[2] < 8 || $a[2] > 28)
    }
    my $val = ($cmd eq "open" ? 254 : ($cmd eq "closed" ? 253: int(2*$a[2])));
    IOWrite($hash, ReadingsVal($name,"AIN",0),"sethkrtsoll&param=$val");
    return undef;
  }
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
   functionbitmask => '"FBPROP:$fbprop"',
   fwversion       => '"fwversion:$val"',
   id              => '"ID:$val"',
   identifier      => '"AIN:$val"',
   komfort         => 'sprintf("day-temp:%.1f C", $val/2)',
   lock            => '"locked:".($val ? "yes":"no")',
   mode            => '"mode:$val"',
   name            => '"FBNAME:$val"',
   offset          => 'sprintf("tempadjust:%.1f C", $val/10)', # ??
   power           => 'sprintf("power:%.2f W", $val/1000)',
   present         => '"present:".($val?"yes":"no")',
   productname     => '"FBTYPE:$val"',
   state           => '"state:".($val?"on":"off")',
#  tist => 'sprintf("temperature:%.1f C (measured)", $val/2)', # Forum #57644
   tsoll           => 'sprintf("desired-temp:%s", $val)',
   members         => '"members:$val"',
   devicelock      => '"devicelock:".($val ? "yes":"no")',
   errorcode       => '"errorcode:".($ecTxt{$val} ? $ecTxt{$val} : ">$val<")',
);

sub
FBDECT_ParseHttp($$$)
{
  my ($iodev, $msg, $type) = @_;
  my $ioName = $iodev->{NAME};
  my %h;

  $msg =~ s,<([^/>]+?)>([^<]+?)<,$h{$1}=$2,ge; # Quick & Dirty: Tags
  $msg =~ s, ([a-z]+?)="([^"]*)",$h{$1}=$2,ge; # Quick & Dirty: Attributes

  my $ain = $h{identifier};
  $ain =~ s/[-: ]/_/g;

  my %ll = (4=>"alarmSensor",
            6=>"actuator",
            7=>"powerMeter",
            8=>"tempSensor",
            9=>"switch",
           10=>"repeater");
  my %ecTxt = (0 => "noError (0)",
               1 => "notMounted (1)",
               2 => "valveShortOrBatteryEmpty (2)",
               3 => "valveStuck (3)",
               4 => "installationPreparation (4)",
               5 => "installationInProgress (5)",
               6 => "installationIsAdapting (6)");

  my $lsn = int($h{functionbitmask});
  my @fb;
  map { push @fb, $ll{$_} if((1<<$_) & $lsn) } sort keys %ll;
  my $fbprop = join(",", @fb);

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
  readingsBeginUpdate($hash);
  Log3 $hash, 5, $hash->{NAME};
  foreach my $n (keys %h) {
    Log3 $hash, 5, "   $n = $h{$n}";
    next if(!$fbhttp_readings{$n});
    my $val = $h{$n};
    $val = ($val==254 ? "on": ($val==253 ? "off" : sprintf("%0.1f C",$val/2)))
      if($n eq "tsoll");
    $val = $type if($n eq "productname" && $val eq "");
    my ($ptyp,$pyld) = split(":", eval $fbhttp_readings{$n}, 2);
    readingsBulkUpdate($hash, "state", "$ptyp: $pyld") if($n eq "tsoll");
    readingsBulkUpdate($hash, $ptyp, $pyld);
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
    Log3 $hash, 4, "FBDECT ignoring payload: data shorter than given length($plen)";
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
  <ul>
  <li>on/off<br>
    set the device on or off.
    </li>

  <li>desired-temp &lt;value&gt;<br>
    set the desired temp on a Comet DECT (FBAHAHTTP IOdev only)
    </li>

  <li><a href="#setExtensions">set extensions</a> are supported.
   </li>

  <li>msgInterval &lt;sec&gt;<br>
    Number of seconds between the sensor messages (FBAHA IODev only).
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
  href="#FBAHAHTTP">FBAHAHTTP</a> Modul f&uumlr die Anbindung an das FRITZ!Box.
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
  <li>desired-temp &lt;value&/gt;<br>
    Gew&uuml;nschte Temperatur beim Comet DECT setzen (nur mit FBAHAHTTP als
    IODev).
    </li>
  <li>
    Die <a href="#setExtensions">set extensions</a> werden
    unterst&uuml;tzt.
    </li>
  <li>msgInterval &lt;sec&gt;<br>
    Anzahl der Sekunden zwischen den Sensornachrichten (nur mit FBAHA als
    IODev).
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
