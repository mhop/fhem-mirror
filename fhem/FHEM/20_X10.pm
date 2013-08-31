################################################################
#
#  Copyright notice
#
#  (c) 2008 Dr. Boris Neubert (omega@online.de)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
# $Id$


#
# Internals introduced in this module:
#	MODEL	distinguish between different X10 device types
#	BRIGHT	brightness level of dimmer devices in units of microdims (0..210)
#
# Readings introduced in this module:
#	state	function and argument of last command
#	onoff	inherited from switch interface (0= on, 1= off)
#	dimmer	inherited from dimmer interface (0= dark, 100= bright)
#
# Setters introduced in this module:
#	on	inherited from switch interface
#	off	inherited from switch interface
#	dimmer  inherited from dimmer interface (0= dark, 100= bright)
#	dimdown	inherited from dimmer interface
#	dimup	inherited from dimmer interface
#

package main;

use strict;
use warnings;

my %functions  = (  ALL_UNITS_OFF           => "all_units_off",
                    ALL_LIGHTS_ON           => "all_lights_on",
                    ON                      => "on",
                    OFF                     => "off",
                    DIM                     => "dimdown",
                    BRIGHT                  => "dimup",
                    ALL_LIGHTS_OFF          => "all_lights_off",
                    EXTENDED_CODE           => "",
                    HAIL_REQUEST            => "",
                    HAIL_ACK                => "",
                    PRESET_DIM1             => "",
                    PRESET_DIM2             => "",
                    EXTENDED_DATA_TRANSFER  => "",
                    STATUS_ON               => "",
                    STATUS_OFF              => "",
                    STATUS_REQUEST          => "",
                );

my %snoitcnuf;  # the reverse of the above

my %functions_rewrite = ( "all_units_off"  => "off",
                          "all_lights_on"  => "on",
                          "all_lights_off" => "off",
                        );

my %functions_snd = qw(  ON  0010
                         OFF 0011
                         DIM 0100
                         BRIGHT 0101 );

my %housecodes_snd = qw(A 0110  B 1110  C 0010  D 1010
                        E 0001  F 1001  G 0101  H 1101
                        I 0111  J 1111  K 0011  K 1011
                        M 0000  N 1000  O 0100  P 1100);

my %unitcodes_snd  = qw( 1 0110   2 1110   3 0010   4 1010
                         5 0001   6 1001   7 0101   8 1101
                         9 0111  10 1111  11 0011  12 1011
                        13 0000  14 1000  15 0100  16 1100);


my %functions_set = ( "on"      => 0,
                      "off"     => 0,
                      "dimup"   => 1,
                      "dimdown" => 1,
		      "dimto"   => 1,
                      "on-till" => 1,
		      "on-for-timer" => 1,
                    );


my %models = (
    lm12	=> 'dimmer',
    lm15        => 'switch',
    am12        => 'switch',
    tm13        => 'switch',
);

my %interfaces = (
    lm12        => 'dimmer',
    lm15        => 'switch_passive',
    am12        => 'switch_passive',
    tm13        => 'switch_passive',
);

my @lampmodules = ('lm12','lm15'); # lamp modules


sub
X10_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %functions) {
    $snoitcnuf{$functions{$k}}= $k;
  }

  $hash->{Match}     = "^X10:[A-P];";
  $hash->{SetFn}     = "X10_Set";
  $hash->{StateFn}   = "X10_SetState";
  $hash->{DefFn}     = "X10_Define";
  $hash->{UndefFn}   = "X10_Undef";
  $hash->{ParseFn}   = "X10_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 " .
                       "dummy:1,0 showtime:1,0 model:lm12,lm15,am12,tm13";

}

#####################################
sub
X10_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#############################
sub
X10_StateMachine($$$$)
{
  my($hash, $time, $function, $argument)= @_;

  # the following changes between (onoff,bright) states were
  # experimentally observed for a Busch Timac Ferndimmer 2265
  # bright and argument are measured in brightness steps
  # from 0 (0%) to 210 (100%).
  # for convenience, we connect the off state with a 210 bright state
  #
  #	initial		on		off		dimup d 	dimdown d
  #	-------------------------------------------------------------------------
  #	(on,x)	  ->	(on,x)		(off,210)	(on,x+d)	(on,x-d)
  #	(off,210) ->	(on,210)	(off,210)	(on,210)	(on,210-d)

  my $onoff;
  my $bright;


  if(defined($hash->{ONOFF})) {
    $onoff= $hash->{ONOFF};
  } else {
    $onoff= 0; }
  if(defined($hash->{BRIGHT})) {
    $bright= $hash->{BRIGHT};
  } else {
    $bright= 0; }
  #Log3 $hash, 1, $hash->{NAME} . " initial state ($onoff,$bright)";

  if($onoff) {
    # initial state (on,bright)
    if($function eq "on") {
    } elsif($function eq "off") {
      $onoff= 0; $bright= 210;
    } elsif($function eq "dimup") {
      $bright+= $argument;
      if($bright> 210) { $bright= 210 };
    } elsif($function eq "dimdown") {
      $bright-= $argument;
      if($bright< 0) { $bright= 0 };
    }
  } else {
    # initial state (off,bright)
    if($function eq "on") {
      $onoff= 1; $bright= 210;
    } elsif($function eq "off") {
      $onoff= 0; $bright= 210;
    } elsif($function eq "dimup") {
      $onoff= 1; $bright= 210;
    } elsif($function eq "dimdown") {
      $onoff= 1;
      $bright= 210-$argument;
      if($bright< 0) { $bright= 0 };
    }
  }
  #Log3 $hash,  1, $hash->{NAME} . " final state ($onoff,$bright)";

  $hash->{ONOFF}= $onoff;
  $hash->{BRIGHT}= $bright;
  $hash->{READINGS}{onoff}{TIME}= $time;
  $hash->{READINGS}{onoff}{VAL}= $onoff;
  $hash->{READINGS}{dimmer}{TIME}= $time;
  $hash->{READINGS}{dimmer}{VAL}= int(1000.0*$bright/210.0+0.5)/10.0;
}

#############################
sub
X10_LevelToDims($)
{
  # 22= 100%
  my ($level)= @_;
  my $dim= int(22*$level/100.0+0.5);
  return $dim;
}


#############################
sub
X10_Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log3 $hash, 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  if($modules{X10}{ldata}{$a[0]}) {
    CommandDelete(undef, $a[0] . "_timer");
    delete $modules{FS20}{ldata}{$a[0]};
  }
  $modules{X10}{ldata}{$a[0]} = "$hms_till";

  my @b = ($a[0], "on");
  X10_Set($hash, @b);
  CommandDefine(undef, $hash->{NAME} . "_timer at $hms_till set $a[0] off");

}
#############################
sub
X10_Do_On_For_Timer($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-for-timer command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my $hms_for_timer = sprintf("+%02d:%02d:%02d", $hr, $min, $sec);

  if($modules{X10}{ldata}{$a[0]}) {
    CommandDelete(undef, $a[0] . "_timer");
    delete $modules{FS20}{ldata}{$a[0]};
  }
  $modules{X10}{ldata}{$a[0]} = "$hms_for_timer";

  my @b = ($a[0], "on");
  X10_Set($hash, @b);
  CommandDefine(undef, $hash->{NAME} . "_timer at $hms_for_timer set $a[0] off");

}

###################################

sub
X11_Write($$$)
{
  my ($hash, $function, $dim)= @_;
  my $name     = $hash->{NAME};
  my $housecode= $hash->{HOUSE};
  my $unitcode = $hash->{UNIT};
  my $x10func  = $snoitcnuf{$function};
  undef $function; # do not use after this point
  my $prefix= "X10 device $name:";

  Log3 $name, 5, "$prefix sending X10:$housecode;$unitcode;$x10func $dim";

  my ($hc_b, $hu_b, $hf_b);
  my ($hc, $hu, $hf);

  # Header:Code, Address
  $hc_b  = "00000100"; # 0x04
  $hc    = pack("B8", $hc_b);
  $hu_b  = $housecodes_snd{$housecode} . $unitcodes_snd{$unitcode};
  $hu    = pack("B8", $hu_b);
  IOWrite($hash, $hc, $hu);

  # Header:Code, Function
  $hc_b   = substr(unpack('B8', pack('C', $dim)), 3) . # dim, 0..22
            "110";                                     # always 110
  $hc     = pack("B8", $hc_b);
  $hf_b   = $housecodes_snd{$housecode} . $functions_snd{$x10func};
  $hf     = pack("B8", $hf_b);
  IOWrite($hash, $hc, $hf);
}

###################################
sub
X10_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  # initialization and sanity checks
  return "no set value specified" if($na < 2);

  my $name= $hash->{NAME};
  my $function= $a[1];
  my $nrparams= $functions_set{$function};
  return "Unknown argument $function, choose one of " .
          join(" ", sort keys %functions_set) if(!defined($nrparams));
  return "Wrong number of parameters"  if($na != 2+$nrparams);

  # special for on-till
  return X10_Do_On_Till($hash, @a) if($function eq "on-till");

  # special for on-for-timer
  return X10_Do_On_For_Timer($hash, @a) if($function eq "on-for-timer");



  # argument evaluation
  my $model= $hash->{MODEL};

  my $dim= 0;
  if($function =~ m/^dim/) {
    return "Cannot dim $name (model $model)" if($models{$model} ne "dimmer");
    my $arg= $a[2];
    return "Wrong argument $arg, use 0..100" if($arg !~ m/^[0-9]{1,3}$/);
    return "Wrong argument $arg, use 0..100" if($arg>100);
    if($function eq "dimto") {
      # translate dimmer command to dimup/dimdown command
      my $bright= 210;
      if(defined($hash->{BRIGHT})) { $bright= $hash->{BRIGHT} };
      $arg= $arg-100.0*$bright/210.0;
      if($arg> 0) {
	$function= "dimup";
	$dim= X10_LevelToDims($arg);
      } else {
	$function= "dimdown";
	$dim= X10_LevelToDims(-$arg);
      }
    } else {
      $dim= X10_LevelToDims($arg);
    }

    # the meaning of $dim= 0, 1 is unclear
    # if we encounter the need for dimming by such a small amount, we
    # ignore it
    if($dim< 2) { return "Dim amount too small" };
  };

  # send command to CM11
  X11_Write($hash, $function, $dim) if(!IsDummy($a[0]));

  my $v = join(" ", @a);
  Log3 $a[0], 2, "X10 set $v";
  (undef, $v) = split(" ", $v, 2);      # Not interested in the name...

  my $tn = TimeNow();

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = $tn;
  $hash->{READINGS}{state}{VAL} = $v;
  X10_StateMachine($hash, $tn, $function, int(210.0*$dim/22.0+0.5));

  return undef;
}

#############################
sub
X10_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> X10 model housecode unitcode"
                if(int(@a)!= 5);

  my $model= $a[2];
  return "Define $a[0]: wrong model: specify one of " .
            join ",", sort keys %models
                if(!grep { $_ eq $model} keys %models);

  my $housecode = $a[3];
  return "Define $a[0]: wrong housecode format: specify a value ".
         "from A to P"
  		if($housecode !~ m/^[A-P]$/i);

  my $unitcode = $a[4];
  return "Define $a[0]: wrong unitcode format: specify a value " .
         "from 1 to 16"
  		if( ($unitcode<1) || ($unitcode>16) );


  $hash->{MODEL}  = $model;
  $hash->{HOUSE}  = $housecode;
  $hash->{UNIT}   = $unitcode;

  $hash->{internals}{interfaces}= $interfaces{$model};

  if(defined($modules{X10}{defptr}{$housecode}{$unitcode})) {
    return "Error: duplicate X10 device $housecode $unitcode definition " .
           $hash->{NAME} . " (previous: " .
           $modules{X10}{defptr}{$housecode}{$unitcode}->{NAME} .")";
  }

  $modules{X10}{defptr}{$housecode}{$unitcode}= $hash;

  AssignIoPort($hash);
}

#############################
sub
X10_Undef($$)
{
  my ($hash, $name) = @_;
  if( defined($hash->{HOUSE}) && defined($hash->{UNIT}) ) {
    delete($modules{X10}{defptr}{$hash->{HOUSE}}{$hash->{UNIT}});
  }
  return undef;
}

#############################
sub
X10_Parse($$)
{
  my ($hash, $msg) = @_;

  # message example: X10:N;1 12;OFF
  (undef, $msg)= split /:/, $msg, 2; # strip off "X10"
  my ($housecode,$unitcodes,$command)= split /;/, $msg, 4;

  my @list;   # list of selected devices

  #
  # command evaluation
  #
  my ($x10func,$arg)= split / /, $command, 2;
  my $function= $functions{$x10func}; # translate, eg BRIGHT -> dimup
  undef $x10func; # do not use after this point

  # the following code sequence converts an all on/off command into
  # a sequence of simple on/off commands for all defined devices
  my $all_lights= ($function=~ m/^all_lights_/);
  my $all_units= ($function=~ m/^all_units_/);
  if($all_lights || $all_units) {
    $function= $functions_rewrite{$function}; # translate, all_lights_on -> on
    $unitcodes= "";
    foreach my $unitcode (keys %{ $modules{X10}{defptr}{$housecode} } ) {
      my $h= $modules{X10}{defptr}{$housecode}{$unitcode};
      my $islampmodule= grep { $_ eq $h->{MODEL} } @lampmodules;
      if($all_units || $islampmodule ) {
        $unitcodes.= " " if($unitcodes ne "");
        $unitcodes.= $h->{UNIT};
      }
    }
    # no units for that housecode
    if($unitcodes eq "") {
      Log3 $hash, 3, "X10 No units with housecode $housecode, command $command, " .
             "please define one";
      push(@list,
             "UNDEFINED X10_$housecode X10 lm15 $housecode ?");
      return @list;
    }
  }

  # apply to each unit in turn
  my @unitcodes= split / /, $unitcodes;

  if(!int(@unitcodes)) {
    # command without unitcodes, this happens when a single on/off is sent
    # but no unit was previously selected
    Log3 $hash, 3, "X10 No unit selected for housecode $housecode, command $command";
    push(@list,
             "UNDEFINED X10_$housecode X10 lm15 $housecode ?");
    return @list;
  }

  # function rewriting
  my $value= $function;
  return @list if($value eq "");  # function not evaluated

  # function determined, add argument
  if( defined($arg) ) {
    # received dims from 0..210
    my $dim= $arg;
    $value = "$value $dim" ;
  }

  my $unknown_unitcodes= '';
  my $tn= TimeNow();
  foreach my $unitcode (@unitcodes) {
    my $h= $modules{X10}{defptr}{$housecode}{$unitcode};
    if($h) {
        my $name= $h->{NAME};
        $h->{CHANGED}[0] = $value;
        $h->{STATE} = $value;
        $h->{READINGS}{state}{TIME} = $tn;
        $h->{READINGS}{state}{VAL} = $value;
	X10_StateMachine($h, $tn, $function, $arg);
        Log3 $hash, 2, "X10 $name $value";
        push(@list, $name);
    } else {
        Log3 $hash, 3, "X10 Unknown device $housecode $unitcode, command $command, " .
               "please define it";
        push(@list,
             "UNDEFINED X10_$housecode X10 lm15 $housecode $unitcode");
    }
  }
  return @list;

}


1;

=pod
=begin html

<a name="X10"></a>
<h3>X10</h3>
<ul>
  <a name="X10define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; X10 &lt;model&gt; &lt;housecode&gt;
          &lt;unitcode&gt;</code>
    <br><br>

   Defines an X10 device via its model, housecode and unitcode.<br><br>

   Notes:
   <ul>
   <li><code>&lt;model&gt;</code> is one of
      <ul>
        <li><code>lm12</code>: lamp module, dimmable</li>
        <li><code>lm15</code>: lamp module, not dimmable</li>
        <li><code>am12</code>: appliance module, not dimmable</li>
        <li><code>tm12</code>: tranceiver module, not dimmable. Its
            unitcode is 1.</li>
      </ul>
      Model determines whether a dim command is reasonable to be sent
      or not.</li>
   <li><code>&lt;housecode&gt;</code> ranges from A to P.</li>
   <li><code>&lt;unitcode&gt;</code> ranges from 1 to 16.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define lamp1 X10 lm12 N 10</code><br>
      <code>define pump X10 am12 B 7</code><br>
      <code>define lamp2 X10 lm15 N 11</code><br>
    </ul>
  </ul>
  <br>

  <a name="X10set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;argument&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    dimdown           # requires argument, see the note
    dimup             # requires argument, see the note
    off
    on
    on-till           # Special, see the note
    on-for-timer      # Special, see the note
    </pre>
    Examples:
    <ul>
      <code>set lamp1 dimup 10</code><br>
      <code>set lamp1,lamp2 off</code><br>
      <code>set pump off</code><br>
      <code>set lamp2 on-till 19:59</code><br>
      <code>set lamp2 on-for-timer 00:02:30</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>Only switching and dimming are supported by now.</li>
      <li>Dimming is valid only for a dimmable device as specified by
          the <code>model</code> argument in its <code>define</code>
          statement.</li>
      <li>An X10 device has 210 discrete brightness levels. If you use a
          X10 sender, e.g. a remote control or a wall switch to dim, a
          brightness step is 100%/210.</li>
      <li><code>dimdown</code> and <code>dimup</code> take a number in the
          range from 0 to 22 as argument. It is assumed that argument 1 is
          a 1% brightness change (microdim) and arguments 2 to 22 are
          10%..100% brightness changes. The meaning of argument 0 is
          unclear.</li>
      <li>This currently leads to some confusion in the logs as the
          <code>dimdown</code> and <code>dimup</code> codes are logged with
          different meaning of the arguments depending on whether the commands
          were sent from the PC or from a remote control or a wall switch.</li>
      <li><code>dimdown</code> and <code>dimup</code> from on and off states may
          have unexpected results. This seems to be a feature of the X10
          devices.</li>
      <li><code>on-till</code> requires an absolute time in the "at" format
          (HH:MM:SS, HH:MM) or { &lt;perl code&gt; }, where the perl code
          returns a time specification).
          If the current time is greater than the specified time, then the
          command is ignored, else an "on" command is generated, and for the
          given "till-time" an off command is scheduleld via the at command.
          </li>
      <li><code>on-for-timer</code> requires a relative time in the "at" format
          (HH:MM:SS, HH:MM) or { &lt;perl code&gt; }, where the perl code
          returns a time specification).
          </li>
    </ul>
  </ul>
  <br>

  <a name="X10get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="X10attr"></a>
  <b>Attributes</b>
  <ul>
  <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (lm12,lm15,am12,tm13)</li>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
  </ul>
  <br>
</ul>

=end html
=cut
