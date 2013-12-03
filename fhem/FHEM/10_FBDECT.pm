##############################################
# $Id: 10_FBDECT.pm 2779 2013-02-21 08:52:27Z rudolfkoenig $
package main;

# TODO: test multi-dev, test on the FB

use strict;
use warnings;
use SetExtensions;

sub FBDECT_Parse($$@);
sub FBDECT_Set($@);
sub FBDECT_Get($@);
sub FBDECT_Cmd($$@);

my @fbdect_models = qw(Powerline546E Dect200);

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
  23 => { n=>"temperature", fmt=>'sprintf("%0.1f C", hex($pyld)/10)' },
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

  my $u = "wrong syntax for $name: define <name> FBDECT id props";
  return $u if(int(@a) != 2);

  my $id = shift @a;
  return "define $name: wrong id ($id): need a number"
                   if( $id !~ m/^\d+$/i );
  $hash->{id} = $id;
  $hash->{props} = shift @a;

  $modules{FBDECT}{defptr}{$id} = $hash;
  AssignIoPort($hash);
  return undef;
}
 
###################################
my %sets = ("on"=>1, "off"=>1, "msgInterval"=>1);
sub
FBDECT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $cmd = $a[1];

  if(!$sets{$cmd}) {
    my $usage =  join(" ", sort keys %sets);
    return SetExtensions($hash, $usage, @a);
  }

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

my %gets = ("devInfo"=>1);
sub
FBDECT_Get($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $cmd = ($a[1] ? $a[1] : "");

  if(!$gets{$cmd}) {
    return "Unknown argument $cmd, choose one of ".join(" ", sort keys %gets);
  }

  if($cmd eq "devInfo") {
    my @answ = FBAHA_getDevList($hash->{IODev}, $hash->{id});
    return $answ[0] if(@answ == 1);
    my $d = pop @answ;
    my $state = "inactive" if($answ[0] =~ m/ inactive,/);
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
      if($ptyp eq "state" && 
         ReadingsVal($hash->{NAME}, $ptyp, "") ne $pyld) {
        readingsSingleUpdate($hash, $ptyp, ($state ? $state : $pyld), 1);
      }
      push @answ, "  $ptyp: $pyld";
      $d = substr($d, 16+$plen*2);
    }
    return join("\n", @answ);
  }
  return undef;
}

###################################
sub
FBDECT_Parse($$@)
{
  my ($iodev, $msg, $local) = @_;
  my $ioName = $iodev->{NAME};

  my $mt = substr($msg, 0, 2);
  if($mt ne "07" && $mt ne "04") {
    Log3 $ioName, 1, "FBDECT: unknown message type $mt";
    return "";  # Nobody else is able to handle this
  }

  my $id = hex(substr($msg, 16, 4));
  my $hash = $modules{FBDECT}{defptr}{$id};
  if(!$hash) {
    my $ret = "UNDEFINED FBDECT_$id FBDECT $id switch";
    Log3 $ioName, 3, "$ret, please define it";
    DoTrigger("global", $ret);
    return "";
  }

  readingsBeginUpdate($hash);

  if($mt eq "07") {
    my $d = substr($msg, 32);
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
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
        my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
        last if(!$plen);
        push @answ, "  $ptyp: $pyld";
        $d = substr($d, 16+$plen*2);
      }
      # Ignore the rest, is too confusing.
      @answ = grep /state:/, @answ;
      (undef, $state) = split(": ", $answ[0], 2);
    }
    readingsBulkUpdate($hash, "state", $state);
  }

  readingsEndUpdate($hash, 1);

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
FBDECT_decodePayload($)
{
  my ($d) = @_;
  my $ptyp = hex(substr($d, 0, 8));
  my $plen = hex(substr($d, 8, 4));
  my $pyld = substr($d, 16, $plen*2);
  if($fbdect_payload{$ptyp}) {
    $pyld = eval $fbdect_payload{$ptyp}{fmt} if($fbdect_payload{$ptyp}{fmt});
    $ptyp = $fbdect_payload{$ptyp}{n};
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
=begin html

<a name="FBDECT"></a>
<h3>FBDECT</h3>
<ul>
  This module is used to control AVM FRITZ!DECT devices via FHEM, see also the
  <a href="#FBAHA">FBAHA</a> module for the base.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT &lt;homeId&gt; &lt;id&gt; [classes]</code>
  <br>
  <br>
  &lt;id&gt; is the id of the device, the classes argument ist ignored for now.
  <br>
  Example:
  <ul>
    <code>define lamp FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Note:</b>Usually the device is created via
  <a href="#autocreate">autocreate</a>
  </ul>
  <br>
  <br>

  <a name="FBDECTset"></a>
  <b>Set</b>
  <ul>
  <li>on/off<br>
  set the device on or off.</li>
  <li>
   <a href="#setExtensions">set extensions</a> are supported.</li>
  <li>msgInterval &lt;sec&gt;<br>
    Number of seconds between the sensor messages.
    </li>
  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
  report device information</li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
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
    <li>temperature: $v C</li>
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
  steuern, siehe auch das <a href="#FBAHA">FBAHA</a> Modul f&uumlr die
  Anbindung an das FRITZ!Box.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT &lt;homeId&gt; &lt;id&gt; [classes]</code>
  <br>
  <br>
  &lt;id&gt; ist das Ger&auml;te-ID, das Argument wird z.Zt ignoriert.
  <br>
  Beispiel:
  <ul>
    <code>define lampe FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Achtung:</b>FBDECT Eintr&auml;ge werden noralerweise per 
  <a href="#autocreate">autocreate</a> angelegt.
  </ul>
  <br>
  <br

  <a name="FBDECTset"></a>
  <b>Set</b>
  <ul>
  <li>on/off<br>
    Ger&auml;t einschalten bzw. ausschalten.</li>
  <li>
    Die <a href="#setExtensions">set extensions</a> werden
    unterst&uuml;tzt.</li>
  <li>msgInterval &lt;sec&gt;<br>
    Anzahl der Sekunden zwischen den Sensornachrichten.
    </li>
  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
  meldet Ger&auml;te-Informationen.</li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
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
    <li>temperature: $v C</li>
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
