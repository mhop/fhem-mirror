##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

my %codes = (
  "00" => "off",
  "01" => "dim06%",
  "02" => "dim12%",
  "03" => "dim18%",
  "04" => "dim25%",
  "05" => "dim31%",
  "06" => "dim37%",
  "07" => "dim43%",
  "08" => "dim50%",
  "09" => "dim56%",
  "0a" => "dim62%",
  "0b" => "dim68%",
  "0c" => "dim75%",
  "0d" => "dim81%",
  "0e" => "dim87%",
  "0f" => "dim93%",
  "10" => "dim100%",
  "11" => "on",		# Set to previous dim value (before switching it off)
  "12" => "toggle",	# between off and previous dim val
  "13" => "dimup",
  "14" => "dimdown",
  "15" => "dimupdown",
  "16" => "timer",
  "17" => "sendstate",
  "18" => "off-for-timer",
  "19" => "on-for-timer",
  "1a" => "on-old-for-timer",
  "1b" => "reset",
  "1c" => "ramp-on-time",      #time to reach the desired dim value on dimmers
  "1d" => "ramp-off-time",     #time to reach the off state on dimmers
  "1e" => "on-old-for-timer-prev", # old val for timer, then go to prev. state
  "1f" => "on-100-for-timer-prev", # 100% for timer, then go to previous state

);

my %readonly = (
  "thermo-on" => 1,
  "thermo-off" => 1,
);

use vars qw(%fs20_c2b);		# Peter would like to access it from outside

my $fs20_simple ="off off-for-timer on on-for-timer on-till reset timer toggle";
my %models = (
    fs20fms     => 'sender',
    fs20hgs     => 'sender',
    fs20irl     => 'sender',
    fs20kse     => 'sender',
    fs20ls      => 'sender',
    fs20pira    => 'sender',
    fs20piri    => 'sender',
    fs20piru    => 'sender',
    fs20s16     => 'sender',
    fs20s20     => 'sender',
    fs20s4      => 'sender',
    fs20s4a     => 'sender',
    fs20s4m     => 'sender',
    fs20s4u     => 'sender',
    fs20s4ub    => 'sender',
    fs20s8      => 'sender',
    fs20s8m     => 'sender',
    fs20sd      => 'sender',    # Sensor: Daemmerung
    fs20sn      => 'sender',    # Sensor: Naeherung
    fs20sr      => 'sender',    # Sensor: Regen
    fs20ss      => 'sender',    # Sensor: Sprache
    fs20str     => 'sender',    # Sensor: Thermostat+Regelung
    fs20tc1     => 'sender',
    fs20tc6     => 'sender',    # TouchControl x 6
    fs20tfk     => 'sender',    # TuerFensterKontakt
    fs20tk      => 'sender',    # TuerKlingel
    fs20uts     => 'sender',    # Universal Thermostat Sender
    fs20ze      => 'sender',    # FunkTimer (ZeitEinheit?)
    fs20bf      => 'sender',    # BodenFeuchte
    fs20bs      => 'sender',    # Beschattung
    dummySender => 'sender',

    fs20di      => 'dimmer',
    fs20di10    => 'dimmer',
    fs20du      => 'dimmer',
    dummyDimmer => 'dimmer',

    fs20as1     => 'simple',
    fs20as4     => 'simple',
    fs20ms2     => 'simple',
    fs20rgbsa   => 'simple',
    fs20rst     => 'simple',
    fs20rsu     => 'simple',
    fs20sa      => 'simple',
    fs20sig     => 'simple',
    fs20sm4     => 'simple',
    fs20sm8     => 'simple',
    fs20st      => 'simple',
    fs20st2     => 'simple',
    fs20su      => 'simple',
    fs20sv      => 'simple',
    fs20ue1     => 'simple',
    fs20usr     => 'simple',
    fs20ws1     => 'simple',
    dummySimple => 'simple',

);

sub hex2four($);
sub four2hex($$);

sub
FS20_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $fs20_c2b{$codes{$k}} = $k;
  }
  $fs20_c2b{"on-till"} = 99;

  $hash->{Match}     = "^81..(04|0c)..0101a001";
  $hash->{SetFn}     = "FS20_Set";
  $hash->{DefFn}     = "FS20_Define";
  $hash->{UndefFn}   = "FS20_Undef";
  $hash->{ParseFn}   = "FS20_Parse";
  $hash->{AttrList}  = "IODev follow-on-for-timer:1,0 follow-on-timer ".
                       "do_not_notify:1,0 ignore:1,0 dummy:1,0 showtime:1,0 ".
                       "loglevel:0,1,2,3,4,5,6 $readingFnAttributes " .
                       "model:".join(",", sort keys %models);
}

#############################
sub
Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log3 $hash->{NAME}, 4,
        "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my @b = ($a[0], "on");
  FS20_Set($hash, @b);
  my $tname = $hash->{NAME} . "_till";
  CommandDelete(undef, $tname) if($defs{$tname});
  CommandDefine(undef, "$tname at $hms_till set $a[0] off");

}


###################################
sub
FS20_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));

  if($na > 2 && $a[1] eq "dim") {
    $a[1] = ($a[2] eq "0" ? "off" : sprintf("dim%02d%%",$a[2]) );
    splice @a, 2, 1;
    $na = int(@a);
  }

  my $c = $fs20_c2b{$a[1]};
  my $name = $a[0];
  if(!defined($c)) {

    # Model specific set arguments
    my $list;
    if(defined($attr{$name}) && defined($attr{$name}{"model"})) {
      my $mt = $models{$attr{$name}{"model"}};
      $list = "" if($mt && $mt eq "sender");
      $list = $fs20_simple if($mt && $mt eq "simple");
    }
    $list = (join(" ", sort keys %fs20_c2b) . " dim:slider,0,6.25,100")
        if(!defined($list));
    return SetExtensions($hash, $list, @a);

  }

  return Do_On_Till($hash, @a) if($a[1] eq "on-till");

  return "Bad time spec" if($na == 3 && $a[2] !~ m/^\d*\.?\d+$/);

  my $v = join(" ", @a);
  Log3 $name, 3, "FS20 set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  my $val;

  if($na == 3) {                                # Timed command.
    $c = sprintf("%02X", (hex($c) | 0x20)); # Set the extension bit

    ########################
    # Calculating the time.
    LOOP: for(my $i = 0; $i <= 12; $i++) {
      for(my $j = 0; $j <= 15; $j++) {
        $val = (2**$i)*$j*0.25;
        if($val >= $a[2]) {
          if($val != $a[2]) {
            Log3 $name, 2, "$name: changing timeout to $val from $a[2]";
          }
          $c .= sprintf("%x%x", $i, $j);
          last LOOP;
        }
      }
    }
    return "Specified timeout too large, max is 15360" if(length($c) == 2);
  }

  IOWrite($hash, "04", "010101" . $hash->{XMIT} . $hash->{BTN} . $c);

  ###########################################
  # Set the state of a device to off if on-for-timer is called
  if($modules{FS20}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{FS20}{ldata}{$name};
  }

  my $newState="";
  my $onTime = AttrVal($name, "follow-on-timer", undef);

  ####################################
  # following timers
  if($a[1] eq "on" && $na == 2 && $onTime) {
    $newState = "off";
    $val = $onTime;

  } elsif($a[1] =~ m/(on|off).*-for-timer/ && $na == 3 &&
     AttrVal($name, "follow-on-for-timer", undef)) {
    $newState = ($1 eq "on" ? "off" : "on");

  }

  if($newState) {
    my $to = sprintf("%02d:%02d:%02d", $val/3600, ($val%3600)/60, $val%60);
    $modules{FS20}{ldata}{$name} = $to;
    Log3 $name, 4, "Follow: +$to setstate $name $newState";
    CommandDefine(undef, $name."_timer at +$to ".
        "setstate $name $newState; trigger $name $newState");
  }

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT} $hash->{BTN}";
  my $tn = TimeNow();
  my $defptr = $modules{FS20}{defptr}{$code};
  foreach my $n (keys %{ $defptr }) {
    readingsSingleUpdate($defptr->{$n}, "state", $v, 1);
  }
  return $ret;
}

#############################
sub
FS20_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> FS20 housecode " .
                        "addr [fg addr] [lm addr] [gm FF]";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong housecode format: specify a 4 digit hex value ".
         "or an 8 digit quad value"
  		if( ($a[2] !~ m/^[a-f0-9]{4}$/i) && ($a[2] !~ m/^[1-4]{8}$/i) );

  return "Define $a[0]: wrong btn format: specify a 2 digit hex value " .
         "or a 4 digit quad value"
  		if( ($a[3] !~ m/^[a-f0-9]{2}$/i) && ($a[3] !~ m/^[1-4]{4}$/i) );

  my $housecode = $a[2];
  $housecode = four2hex($housecode,4) if (length($housecode) == 8);

  my $btncode = $a[3];
  $btncode = four2hex($btncode,2) if (length($btncode) == 4);

  $hash->{XMIT} = lc($housecode);
  $hash->{BTN}  = lc($btncode);

  my $code = lc("$housecode $btncode");
  my $ncode = 1;
  my $name = $a[0];
  $hash->{CODE}{$ncode++} = $code;
  $modules{FS20}{defptr}{$code}{$name}   = $hash;

  for(my $i = 4; $i < int(@a); $i += 2) {

    return "No address specified for $a[$i]" if($i == int(@a)-1);

    $a[$i] = lc($a[$i]);
    if($a[$i] eq "fg") {
      return "Bad fg address for $name, see the doc"
        if( ($a[$i+1] !~ m/^f[a-f0-9]$/) && ($a[$i+1] !~ m/^44[1-4][1-4]$/));
    } elsif($a[$i] eq "lm") {
      return "Bad lm address for $name, see the doc"
        if( ($a[$i+1] !~ m/^[a-f0-9]f$/) && ($a[$i+1] !~ m/^[1-4][1-4]44$/));
    } elsif($a[$i] eq "gm") {
      return "Bad gm address for $name, must be ff"
        if( ($a[$i+1] ne "ff") && ($a[$i+1] ne "4444"));
    } else {
      return $u;
    }

    my $grpcode = $a[$i+1];
    if (length($grpcode) == 4) {
       $grpcode = four2hex($grpcode,2);
    }

    $code = "$housecode $grpcode";
    $hash->{CODE}{$ncode++} = $code;
    $modules{FS20}{defptr}{$code}{$name}   = $hash;
  }
  AssignIoPort($hash);
}

#############################
sub
FS20_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{FS20}{defptr}{$c} }) {
      delete($modules{FS20}{defptr}{$c}{$dname})
        if($modules{FS20}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
FS20_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: 
  # 81 0b 04 f7 0101 a001 HHHH 01 00 11

  my $dev = substr($msg, 16, 4);
  my $btn = substr($msg, 20, 2);
  my $cde = substr($msg, 24, 2);


  my $dur = 0;
  my $cx = hex($cde);
  if($cx & 0x20) {      # Timed command
    $dur = hex(substr($msg, 26, 2));
    my $i = ($dur & 0xf0) / 16;
    my $j = ($dur & 0xf);
    $dur = (2**$i)*$j*0.25;
    $cde = sprintf("%02x", $cx & ~0x20);
  }

  my $v = $codes{$cde};
  $v = "unknown_$cde" if(!defined($v));
  $v .= " $dur" if($dur);


  my $def = $modules{FS20}{defptr}{"$dev $btn"};
  if($def) {
    my @list;
    foreach my $n (keys %{ $def }) {
      my $lh = $def->{$n};
      $n = $lh->{NAME};        # It may be renamed

      return "" if(IsIgnored($n));   # Little strange.

      readingsSingleUpdate($lh, "state", $v, 1);
      Log3 $n, 4, "FS20 $n $v";

      if($modules{FS20}{ldata}{$n}) {
        CommandDelete(undef, $n . "_timer");
        delete $modules{FS20}{ldata}{$n};
      }

      my $newState = "";
      if($v =~ m/(on|off).*-for-timer/ && $dur &&
        AttrVal($n, "follow-on-for-timer", undef)) {
        $newState = ($1 eq "on" ? "off" : "on");

      } elsif($v eq "on" && (my $d = AttrVal($n, "follow-on-timer", undef))) {
        $dur = $d;
        $newState = "off";

      }
      if($newState) {
        my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
        Log3 $n, 4, "Follow: +$to setstate $n $newState";
        CommandDefine(undef, $n."_timer at +$to ".
            "setstate $n $newState; trigger $n $newState");
        $modules{FS20}{ldata}{$n} = $to;
      }

      push(@list, $n);
    }
    return @list;

  } else {
    # Special FHZ initialization parameter. In Multi-FHZ-Mode we receive
    # it by the second FHZ
    return "" if($dev eq "0001" && $btn eq "00" && $cde eq "00");

    my $dev_four = hex2four($dev);
    my $btn_four = hex2four($btn);
    Log 3, "FS20 Unknown device $dev ($dev_four), " .
                "Button $btn ($btn_four) Code $cde ($v), please define it";
    return "UNDEFINED FS20_$dev$btn FS20 $dev $btn";
  }

}

#############################
sub
hex2four($)
{
  my $v = shift;
  my $r = "";
  foreach my $x (split("", $v)) {
    $r .= sprintf("%d%d", (hex($x)/4)+1, (hex($x)%4)+1);
  }
  return $r;
}

#############################
sub
four2hex($$)
{
  my ($v,$len) = @_;
  my $r = 0;
  foreach my $x (split("", $v)) {
    $r = $r*4+($x-1);
  }
  return sprintf("%0*x", $len,$r);
}


1;

=pod
=begin html

<a name="FS20"></a>
<h3>FS20</h3>
<ul>
  The FS20 protocol is used by a wide range of devices, which are either of
  the sender/sensor category or the receiver/actuator category.  The radio
  (868.35 MHz) messages are either received through an <a href="#FHZ">FHZ</a>
  or an <a href="#CUL">CUL</a> device, so this must be defined first.

  <br><br>

  <a name="FS20define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FS20 &lt;housecode&gt; &lt;button&gt;
    [fg &lt;fgaddr&gt;] [lm &lt;lmaddr&gt;] [gm FF] </code>
    <br><br>

   The values of housecode, button, fg, lm, and gm can be either defined as
   hexadecimal value or as ELV-like "quad-decimal" value with digits 1-4. We
   will reference this ELV-like notation as ELV4 later in this document. You
   may even mix both hexadecimal and ELV4 notations, because FHEM can detect
   the used notation automatically by counting the digits.<br>

   <ul>
   <li><code>&lt;housecode&gt;</code> is a 4 digit hex or 8 digit ELV4 number,
     corresponding to the housecode address.</li>
   <li><code>&lt;button&gt;</code> is a 2 digit hex or 4 digit ELV4 number,
     corresponding to a button of the transmitter.</li>
   <li>The optional <code>&lt;fgaddr&gt;</code> specifies the function group.
     It is a 2 digit hex or 4 digit ELV address. The first digit of the hex
     address must be F or the first 2 digits of the ELV4 address must be
     44.</li>
   <li>The optional <code>&lt;lmaddr&gt;</code> specifies the local
     master. It is a 2 digit hex or 4 digit ELV address.  The last digit of the
     hex address must be F or the last 2 digits of the ELV4 address must be
     44.</li>
   <li>The optional gm specifies the global master, the address must be FF if
     defined as hex value or 4444 if defined as ELV4 value.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define lamp FS20 7777 00 fg F1 gm F</code><br>
      <code>define roll1 FS20 7777 01</code><br>
      <code>define otherlamp FS20 24242424 1111 fg 4412 gm 4444</code><br>
      <code>define otherroll1 FS20 24242424 1114</code>
    </ul>
  </ul>
  <br>

  <a name="FS20set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><code>
      dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50%<br>
      dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%<br>
      dimdown<br>
      dimup<br>
      dimupdown<br>
      off<br>
      off-for-timer<br>
      on                # dimmer: set to value before switching it off<br>
      on-for-timer      # see the note<br>
      on-old-for-timer  # set to previous (before switching it on)<br>
      ramp-on-time      # time to reach the desired dim value on dimmers<br>
      ramp-off-time     # time to reach the off state on dimmers<br>
      reset<br>
      sendstate<br>
      timer<br>
      toggle            # between off and previous dim val<br>
      on-till           # Special, see the note<br>
    </code></ul>
    The <a href="#setExtensions"> set extensions</a> are also supported.<br>
    <br>
    Examples:
    <ul>
      <code>set lamp on</code><br>
      <code>set lamp1,lamp2,lamp3 on</code><br>
      <code>set lamp1-lamp3 on</code><br>
      <code>set lamp on-for-timer 12</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>Use reset with care: the device forgets even the housecode.
      </li>
      <li>As the FS20 protocol needs about 0.22 seconds to transmit a
      sequence, a pause of 0.22 seconds is inserted after each command.
      </li>
      <li>The FS20ST switches on for dim*%, dimup. It does not respond to
          sendstate.</li>
      <li>If the timer is set (i.e. it is not 0) then on, dim*,
          and *-for-timer will take it into account (at least by the FS20ST).
      </li>
      <li>The <code>time</code> argument ranges from 0.25sec to 4 hours and 16
          minutes.  As the time is encoded in one byte there are only 112
          distinct values, the resolution gets coarse with larger values. The
          program will report the used timeout if the specified one cannot be
          set exactly.  The resolution is 0.25 sec from 0 to 4 sec, 0.5 sec
          from 4 to 8 sec, 1 sec from 8 to 16 sec and so on. If you need better
          precision for large values, use <a href="#at">at</a> which has a 1
          sec resolution.</li>
      <li>on-till requires an absolute time in the "at" format (HH:MM:SS, HH:MM
      or { &lt;perl code&gt; }, where the perl-code returns a time
          specification).
      If the current time is greater than the specified time, then the
      command is ignored, else an "on" command is generated, and for the
      given "till-time" an off command is scheduleld via the at command.
      </li>
    </ul>
  </ul>
  <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="FS20attr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is an FHZ
        or a CUL. Note: Upon startup fhem assigns each logical device
        (FS20/HMS/KS300/etc) the last physical device which can receive data
        for this type of device. The attribute IODev needs to be used only if
        you attached more than one physical device capable of receiving signals
        for this logical device.</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or komma(,)
        then split not by space but by this character, enabling to embed spaces.
        Examples:<ul><code>
        attr store eventMap on:open off:closed<br>
        attr store eventMap /on-for-timer 10:open/off:closed/<br>
        set store open
        </code></ul>
        </li><br>

    <a name="attrdummy"></a>
    <li>dummy<br>
    Set the device attribute dummy to define devices which should not
    output any radio signals. Associated notifys will be executed if
    the signal is received. Used e.g. to react to a code from a sender, but
    it will not emit radio signal if triggered in the web frontend.
    </li><br>

    <a name="follow-on-for-timer"></a>
    <li>follow-on-for-timer<br>
    schedule a "setstate off;trigger off" for the time specified as argument to
    the on-for-timer command. Or the same with on, if the command is
    off-for-timer.
    </li><br>

    <a name="follow-on-timer"></a>
    <li>follow-on-timer<br>
    Like with follow-on-for-timer schedule a "setstate off;trigger off", but
    this time for the time specified as argument in seconds to this attribute.
    This is used to follow the pre-programmed timer, which was set previously
    with the timer command or manually by pressing the button on the device,
    see your manual for details.
    </li><br>


    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands
        (e.g. "on" or "off" to a fs20st, "dim..%" to fs20du etc.).
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited. Here is a list of "official"
        devices:<br><br>
          <b>Sender/Sensor</b>: fs20fms fs20hgs fs20irl fs20kse fs20ls
          fs20pira fs20piri fs20piru fs20s16 fs20s20 fs20s4  fs20s4a fs20s4m
          fs20s4u fs20s4ub fs20s8 fs20s8m fs20sd  fs20sn  fs20sr fs20ss
          fs20str fs20tc1 fs20tc6 fs20tfk fs20tk  fs20uts fs20ze fs20bf<br><br>

          <b>Dimmer</b>: fs20di  fs20di10 fs20du<br><br>

          <b>Receiver/Actor</b>: fs20as1 fs20as4 fs20ms2 fs20rgbsa fs20rst
          fs20rsu fs20sa fs20sig fs20sm4 fs20sm8 fs20st fs20su fs20sv fs20ue1
          fs20usr fs20ws1
    </li><br>


    <a name="ignore"></a>
    <li>ignore<br>
        Ignore this device, e.g. if it belongs to your neighbour. The device
        won't trigger any FileLogs/notifys, issued commands will silently
        ignored (no RF signal will be sent out, just like for the <a
        href="#attrdummy">dummy</a> attribute). The device won't appear in the
        list command (only if it is explicitely asked for it), nor will it
        appear in commands which use some wildcard/attribute as name specifiers
        (see <a href="#devspec">devspec</a>). You still get them with the
        "ignored=1" special devspec.
        </li><br>

    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>

  </ul>
  <br>

  <a name="FS20events"></a>
  <b>Generated events:</b>
  <ul>
     From an FS20 device you can receive one of the following events.
     <li>on</li>
     <li>off</li>
     <li>toggle</li>
     <li>dimdown</li>
     <li>dimup</li>
     <li>dimupdown</li>
     <li>on-for-timer</li>
     Which event is sent is device dependent and can sometimes configured on
     the device.
  </ul>
</ul>

=end html
=cut
