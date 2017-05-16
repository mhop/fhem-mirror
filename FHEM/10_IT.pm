######################################################
# InterTechno Switch Manager as FHM-Module
#
# (c) Olaf Droegehorn / DHS-Computertechnik GmbH
# 
# Published under GNU GPL License
######################################################package main;

use strict;
use warnings;


my %codes = (
  "XMIToff" 		=> "off",
  "XMITon" 			=> "on",		
  "XMITdimup" 	=> "dimup",
  "XMITdimdown" => "dimdown",
  "99" => "on-till",
 
);

my %it_c2b;

my $it_defrepetition = 6;   ## Default number of InterTechno Repetitions

my $it_simple ="off on";
my %models = (
    itremote    => 'sender',
    itswitch    => 'simple',
    itdimmer    => 'dimmer',
);

sub
IT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $it_c2b{$codes{$k}} = $k;
  }

#  $hash->{Match}     = "";
  $hash->{SetFn}     = "IT_Set";
  $hash->{StateFn}   = "IT_SetState";
  $hash->{DefFn}     = "IT_Define";
  $hash->{UndefFn}   = "IT_Undef";
#  $hash->{ParseFn}   = "IT_Parse";
  $hash->{AttrList}  = "IODev ITfrequency ITrepetition switch_rfmode:1,0 do_not_notify:1,0 ignore:0,1 dummy:1,0 model:itremote,itswitch,itdimmer loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
IT_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}

#############################
sub
IT_Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my @b = ($a[0], "on");
  IT_Set($hash, @b);
  my $tname = $hash->{NAME} . "_till";
  CommandDelete(undef, $tname) if($defs{$tname});
  CommandDefine(undef, "$tname at $hms_till set $a[0] off");

}

###################################
sub
IT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);
  my $message;

  return "no set value specified" if($na < 2 || $na > 3);

  my $c = $it_c2b{$a[1]};
  if(!defined($c)) {

    # Model specific set arguments
    if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"model"})) {
      my $mt = $models{$attr{$a[0]}{"model"}};
      return "Unknown argument $a[1], choose one of "
                                               if($mt && $mt eq "sender");
      return "Unknown argument $a[1], choose one of $it_simple"
                                               if($mt && $mt eq "simple");
    }
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %it_c2b);
  }

  return IT_Do_On_Till($hash, @a) if($a[1] eq "on-till");
  return "Bad time spec" if($na == 3 && $a[2] !~ m/^\d*\.?\d+$/);

  my $io = $hash->{IODev};

	## Do we need to change RFMode to SlowRF??
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"switch_rfmode"})) {
  	if ($attr{$a[0]}{"switch_rfmode"} eq "1") {			# do we need to change RFMode of IODev
  		  my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "SlowRF"));
 	 	}	
	}

  ## Do we need to change ITrepetition ??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITrepetition"})) {
  	$message = "isr".$attr{$a[0]}{"ITrepetition"};
		CUL_SimpleWrite($io, $message);
		Log GetLogLevel($a[0],4), "IT set ITrepetition: $message for $io->{NAME}";
	}

  ## Do we need to change ITfrequency ??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITfrequency"})) {
    my $f = $attr{$a[0]}{"ITfrequency"}/26*65536;
    my $f2 = sprintf("%02x", $f / 65536);
    my $f1 = sprintf("%02x", int($f % 65536) / 256);
    my $f0 = sprintf("%02x", $f % 256);
    
    my $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
    Log GetLogLevel($a[0],4), "Setting ITfrequency (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
    CUL_SimpleWrite($hash, "if$f2$f1$f0");
	}
	
  my $v = join(" ", @a);
  $message = "is".uc($hash->{XMIT}.$hash->{$c});
	
	## Log that we are going to switch InterTechno
  Log GetLogLevel($a[0],2), "IT set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

	## Send Message to IODev and wait for correct answer
  my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
  if ($msg =~ m/raw => $message/) {
        Log 4, "Answer from $io->{NAME}: $msg";
  } else {
        Log 2, "IT IODev device didn't answer is command correctly: $msg";
  }

  ## Do we need to change ITrepetition back??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITrepetition"})) {
  	$message = "isr".$it_defrepetition;
		CUL_SimpleWrite($io, $message);
		Log GetLogLevel($a[0],4), "IT set ITrepetition back: $message for $io->{NAME}";
	}

  ## Do we need to change ITfrequency back??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITfrequency"})) {
    Log GetLogLevel($a[0],4), "Setting ITfrequency back to 433.92 MHz";
    CUL_SimpleWrite($hash, "if0");
	}

	## Do we need to change RFMode back to HomeMatic??
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"switch_rfmode"})) {
  	if ($attr{$a[0]}{"switch_rfmode"} eq "1") {			# do we need to change RFMode of IODev
  		  my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "HomeMatic"));
 	 	}	
	}


  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT}";
  my $tn = TimeNow();
  foreach my $n (keys %{ $modules{IT}{defptr}{$code} }) {

    my $lh = $modules{IT}{defptr}{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
  }
  return $ret;
}

#############################
sub
IT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  # calculate transmit code from IT A-P rotary switches
  if($a[2] =~ /^([A-O])(([0]{0,1}[1-9])|(1[0-6]))$/i) {
      my %it_1st = (
          "A","0000","B","F000","C","0F00","D","FF00","E","00F0","F","F0F0",
          "G","0FF0","H","FFF0","I","000F","J","F00F","K","0F0F","L","FF0F",
          "M","00FF","N","F0FF","O","0FFF","P","FFFF"
          );
      my %it_2nd = (
          1 ,"0000",2 ,"F000",3 ,"0F00",4 ,"FF00",5 ,"00F0",6 ,"F0F0",
          7 ,"0FF0",8 ,"FFF0",9 ,"000F",10,"F00F",11,"0F0F",12,"FF0F",
          13,"00FF",14,"F0FF",15,"0FFF",16,"FFFF"
          );
      
      $a[2] = $it_1st{$1}.$it_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }
  # calculate transmit code from FLS 100 I,II,III,IV rotary switches
  if($a[2] =~ /^(I|II|III|IV)([1-4])$/i) {
      my %fls_1st = ("I","0FFF","II","F0FF","III","FF0F","IV","FFF0" );
      my %fls_2nd = (1 ,"0FFF",2 ,"F0FF",3 ,"FF0F",4 ,"FFF0");
      
      $a[2] = $fls_1st{$1}.$fls_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }

  my $u = "wrong syntax: define <name> IT 10-bit-housecode " .
                        "off-code on-code [dimup-code] [dimdown-code]";

  return $u if(int(@a) < 5);
  return "Define $a[0]: wrong IT-Code format: specify a 10 digits 0/1/f "
  		if( ($a[2] !~ m/^[f0-1]{10}$/i) );

  return "Define $a[0]: wrong ON format: specify a 2 digits 0/1/f "
    	if( ($a[3] !~ m/^[f0-1]{2}$/i) );

  return "Define $a[0]: wrong OFF format: specify a 2 digits 0/1/f "
    	if( ($a[4] !~ m/^[f0-1]{2}$/i) );

  my $housecode = $a[2];
  my $oncode = $a[3];
  my $offcode = $a[4];

  $hash->{XMIT} = lc($housecode);
  $hash->{$it_c2b{"on"}}  = lc($oncode);
  $hash->{$it_c2b{"off"}}  = lc($offcode);
  
  if (int(@a) > 5) {
  	return "Define $a[0]: wrong dimup-code format: specify a 2 digits 0/1/f "
    	if( ($a[5] !~ m/^[f0-1]{2}$/i) );
		$hash->{$it_c2b{"dimup"}}  = lc($a[5]);
   
	  if (int(@a) == 7) {
  		return "Define $a[0]: wrong dimdown-code format: specify a 2 digits 0/1/f "
	    	if( ($a[6] !~ m/^[f0-1]{2}$/i) );
    	$hash->{$it_c2b{"dimdown"}}  = lc($a[6]);
  	}
  } else {
		$hash->{$it_c2b{"dimup"}}  = "00";
   	$hash->{$it_c2b{"dimdown"}}  = "00";
  }
  
  my $code = lc($housecode);
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  $modules{IT}{defptr}{$code}{$name}   = $hash;

  AssignIoPort($hash);
}

#############################
sub
IT_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{IT}{defptr}{$c} }) {
      delete($modules{IT}{defptr}{$c}{$dname})
        if($modules{IT}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
IT_Parse($$)
{

}

1;

=pod
=begin html

<a name="IT"></a>
<h3>IT - InterTechno</h3>
<ul>
  The InterTechno 433MHZ protocol is used by a wide range of devices, which are either of
  the sender/sensor category or the receiver/actuator category. As we right now are only
  able to SEND InterTechno commands, but CAN'T receive them, this module at the moment
  supports just  devices like switches, dimmers, etc. through an <a href="#CUL">CUL</a> device, so this must be defined first.

  <br><br>

  <a name="ITdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; IT &lt;housecode&gt; &lt;on-code&gt; &lt;off-code&gt;
    [&lt;dimup-code&gt;] [&lt;dimdown-code&gt;] </code>
    <br>or<br>
    <code>define &lt;name&gt; IT &lt;ITRotarySwitches|FLS100RotarySwitches&gt; </code>
    <br><br>

   The value of housecode is a 10-digit InterTechno Code, consisting of 0/1/F as it is
   defined as a tri-state protocol. These digits depend on your device you are using.
   <br>
   Bit 11/12 are used for switching/dimming. As different manufacturers are using
   different bit-codes you can specifiy here the 2-digit code for off/on/dimup/dimdown
   in the same form: 0/1/F.
	<br>
   The value of ITRotarySwitches consist of the value of the alpha switch A-P and
   the numeric switch 1-16 as set on the intertechno device. E.g. A1 or G12.
<br>
   The value of FLS100RotarySwitches consist of the value of the I,II,II,IV switch
   and the numeric 1,2,3,4 swicht. E.g. I2 or IV4.
<br>
   The value of ITRotarySwitches and FLS100RotarySwitches is internaly translated
   into a houscode value.
<br>
   <ul>
   <li><code>&lt;housecode&gt;</code> is a 10 digit tri-state number (0/1/F) depending on
	 your device setting (see list below).</li>
   <li><code>&lt;on-code&gt;</code> is a 2 digit tri-state number for switching your device on;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li><code>&lt;off-code&gt;</code> is a 2 digit tri-state number for switching your device off;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li>The optional <code>&lt;dimup-code&gt;</code> is a 2 digit tri-state number for dimming your device up;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li>The optional <code>&lt;dimdown-code&gt;</code> is a 2 digit tri-state number for dimming your device down;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define lamp IT 01FF010101 11 00 01 10</code><br>
      <code>define roll1 IT 111111111F 11 00 01 10</code><br>
      <code>define otherlamp IT 000000000F 11 10 00 00</code><br>
      <code>define otherroll1 IT FFFFFFF00F 11 10</code><br>
      <code>define itswitch1 IT A1</code><br>
      <code>define lamp IT J10</code><br>
      <code>define flsswitch1 IT IV1</code><br>
      <code>define lamp IT II2</code>
    </ul>
  </ul>
  <br>

  <a name="ITset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    dimdown
    dimup
    off
    on
    on-till           # Special, see the note
</pre>
    Examples:
    <ul>
      <code>set lamp on</code><br>
      <code>set lamp1,lamp2,lamp3 on</code><br>
      <code>set lamp1-lamp3 on</code><br>
      <code>set lamp off</code><br>
    </ul>
    <br>
    Notes:
    <ul>
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

  <a name="ITattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is a CUL.
		Note: Upon startup fhem DOES NOT assigns an InterTechno device an
		IODevice! The attribute IODev needs to be used AT ANY TIME!</li><br>

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

    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <a name="attrdummy"></a>
    <li>dummy<br>
    Set the device attribute dummy to define devices which should not
    output any radio signals. Associated notifys will be executed if
    the signal is received. Used e.g. to react to a code from a sender, but
    it will not emit radio signal if triggered in the web frontend.
    </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands
        (e.g. "on" or "off" to a switch, "dim..%" to dimmers etc.).
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited. Here is a list of "official"
        devices:<br>
          <b>Sender/Sensor</b>: itremote<br>

          <b>Dimmer</b>: itdimmer<br>

          <b>Receiver/Actor</b>: itswitch
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

  </ul>
  <br>

  <a name="ITevents"></a>
  <b>Generated events:</b>
  <ul>
     From an IT device you can receive one of the following events.
     <li>on
     <li>off
     <li>dimdown
     <li>dimup<br>
      Which event is sent is device dependent and can sometimes configured on
     the device.
  </ul>
</ul>



=end html
=cut
