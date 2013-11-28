################################################################
#
#  Copyright notice
#
#  (c) 2009 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
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
################################################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use OW;

my %gets = (
  "address"     => "",
  "alias"       => "",
  "crc8"        => "",
  "family"      => "10",
  "id"          => "",
  "locator"     => "",
  "power"       => "",
  "present"     => "",
#  "r_address"   => "",
#  "r_id"        => "",
#  "r_locator"   => "",
  "temperature" => "",
  "temphigh"    => "",
  "templow"     => "",
  "type"        => "",
);

my %sets = (
  "alias"         => "",
  "temphigh"      => "",
  "templow"       => "",
  "interval"      => "",
  "alarminterval" => "",
);

my %updates = (
  "present"     => "",
  "temperature" => "",
  "templow"     => "",
  "temphigh"    => "",
);

my %dummy = (
  "crc8"         => "4D",
  "alias"        => "dummy",
  "locator"      => "FFFFFFFFFFFFFFFF",
  "power"        => "0",
  "present"      => "1",
  "temphigh"     => "75",
  "templow"      => "10",
  "type"         => "DS18S20",
  "warnings"     => "none",
);

#####################################
sub
OWTEMP_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "OWTEMP_Define";
  $hash->{UndefFn} = "OWTEMP_Undef";
  $hash->{GetFn}   = "OWTEMP_Get";
  $hash->{SetFn}   = "OWTEMP_Set";
  $hash->{AttrList}= "IODev do_not_notify:0,1 showtime:0,1 model:DS18S20 loglevel:0,1,2,3,4,5";
}

#####################################
sub
OWTEMP_UpdateReading($$$$)
{
  my ($hash,$reading,$now,$value) = @_;

  # define vars
  my $temp;

  # exit if empty value
  return 0
    if(!defined($value) || $value eq "");

  # trim value
  $value =~ s/\s//g
    if($reading ne "warnings");
  if($reading eq "temperature") {
    $value  = sprintf("%.4f",$value);
    $temp   = $value;
    $value  = $value . " (".$hash->{OW_SCALE}.")";
  }

  # update readings
  $hash->{READINGS}{$reading}{TIME} = $now;
  $hash->{READINGS}{$reading}{VAL}  = $value;
  Log 4, "OWTEMP $hash->{NAME} $reading: $value";

  return $value;
}

#####################################
sub
OWTEMP_GetUpdate($$)
{
  my ($hash, $a) = @_;

  # define vars
  my $name    = $hash->{NAME};
  my $now     = TimeNow();
  my $value   = "";
  my $temp    = "";
  my $ret     = "";
  my $count   = 0;

  # define warnings
  my $warn        = "none";
  $hash->{ALARM}  = "0";

  # check for real sensor
  if($hash->{OW_ID} ne "none") {
    # real sensor

    if(!$hash->{LOCAL} || $a eq "") {
      foreach my $r (sort keys %updates) {
        $ret = "";
        $ret = OW::get("/uncached/".$hash->{OW_PATH}."/".$r);
        if(!defined($ret)) {
          # 
          $hash->{PRESENT} = "0";
          $r = "present";
          $value = "0";
          $ret = OWTEMP_UpdateReading($hash,$r,$now,$value);
          $hash->{CHANGED}[$count] = "present: ".$value
        } else {
          $hash->{PRESENT} = "1";
          $value = $ret;
          if($r eq "temperature") {
            $temp = sprintf("%.4f",$value);
            $temp =~ s/\s//g;
          }
          $ret = OWTEMP_UpdateReading($hash,$r,$now,$value);
        }
        last if($hash->{PRESENT} eq "0");
      }
    } else {
      $ret = "";
      $ret = OW::get("/uncached/".$hash->{OW_PATH}."/".$a);
      if(!defined($ret)) {
        $hash->{PRESENT} = "0";
        $a = "present";
        $value = "0";
        $ret = OWTEMP_UpdateReading($hash,$a,$now,$value);
      } else {
        $hash->{PRESENT} = "1";
        $value = $ret;
        if($a eq "temperature") {
          $temp = sprintf("%.4f",$value);
          $temp =~ s/\s//g;
          $value = $temp;
        }
        $ret = OWTEMP_UpdateReading($hash,$a,$now,$value);
      }
    }
  } else {
    # dummy sensor
    $temp = sprintf("%.4f",rand(85));
    $dummy{temperature} = $temp;
    $dummy{present}     = "1";
    $hash->{PRESENT}    = $dummy{present};
    
    if(!$hash->{LOCAL} || $a eq "") {
      foreach my $r (sort keys %updates) {
        $ret = OWTEMP_UpdateReading($hash,$r,$now,$dummy{$r});
      }
    } else {
      $ret = "";
      $ret = $dummy{$a};
      if($ret ne "") {
        $value = $ret;
        if($a eq "temperature") {
          $temp = sprintf("%.4f",$value);
          $temp =~ s/\s//g;
        }
        $ret = OWTEMP_UpdateReading($hash,$a,$now,$value);
      }
    }
  }

  return 1
    if($hash->{LOCAL} && $a eq "" && $hash->{PRESENT} eq "0"); 

  # check for warnings
  my $templow   = $hash->{READINGS}{templow}{VAL};
  my $temphigh  = $hash->{READINGS}{temphigh}{VAL};

  if($hash->{PRESENT} eq "1") {
    if($temp <= $templow) {
      # low temperature
      $hash->{ALARM} = "1";
      $warn = "templow";
    } elsif($temp >= $temphigh) {
      # high temperature
      $hash->{ALARM} = "1";
      $warn = "temphigh";
    }
  } else {
    # set old state
    $temp = $hash->{READINGS}{temperature}{VAL};
    ($temp,undef) = split(" ",$temp);
    # sensor is missing
    $hash->{ALARM} = "1";
    $warn = "not present";
  }

  if(!$hash->{LOCAL} || $a eq "") {
    $ret = OWTEMP_UpdateReading($hash,"warnings",$now,$warn);
  }

  $hash->{STATE} =  "T: ".$temp."  ".
                    "L: ".$templow."  ".
                    "H: ".$temphigh."  ".
                    "P: ".$hash->{PRESENT}."  ".
                    "A: ".$hash->{ALARM}."  ".
                    "W: ".$warn;

  # inform changes
  # state
  $hash->{CHANGED}[$count++] = $hash->{STATE};
  # present
  $hash->{CHANGED}[$count++] = "present: ".$hash->{PRESENT}
    if(defined($hash->{PRESENT}) && $hash->{PRESENT} ne "");
  # temperature
  $hash->{CHANGED}[$count++] = "temperature: ".$temp." (".$hash->{OW_SCALE}.")"
    if(defined($temp) && $temp ne "");
  # temperature raw
  $hash->{CHANGED}[$count++] = "tempraw: ".$temp
    if(defined($temp) && $temp ne "");
  # low temperature
  $hash->{CHANGED}[$count++] = "templow: ".$templow
    if(defined($templow) && $templow ne "");
  # high temperature
  $hash->{CHANGED}[$count++] = "temphigh: ".$temphigh
    if(defined($temphigh) && $temphigh ne "");
  # warnings
  $hash->{CHANGED}[$count++] = "warnings: ".$warn
    if(defined($warn) && $warn ne "");


  if(!$hash->{LOCAL}) {
    # update timer
    RemoveInternalTimer($hash);
    # check alarm
    if($hash->{ALARM} eq "0") {
      $hash->{INTERVAL} = $hash->{INTV_CHECK};
    } else {
      $hash->{INTERVAL} = $hash->{INTV_ALARM};
    }
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 1);
  } else {
    return $value;
  }

  if(!$hash->{LOCAL}) {
    DoTrigger($name, undef) if($init_done);
  }

  return $hash->{STATE};
}

#####################################
sub
OWTEMP_Get($@)
{
  my ($hash, @a) = @_;
  
  # check syntax
  return "argument is missing @a"
    if(int(@a) != 2);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));

  # define vars
  my $value;

  # get value
  $hash->{LOCAL} = 1;
  $value = OWTEMP_GetUpdate($hash,$a[1]);
  delete $hash->{LOCAL};

  my $reading = $a[1];

  if(defined($hash->{READINGS}{$reading})) {
    $value = $hash->{READINGS}{$reading}{VAL};
  }

  return "$a[0] $reading => $value";
}

#####################################
sub
OWTEMP_Set($@)
{
  my ($hash, @a) = @_;

  # check syntax
  return "set needs one parameter"
    if(int(@a) != 3);
  # check arguments
  return "Unknown argument $a[1], choose one of ".join(",", sort keys %sets)
    if(!defined($sets{$a[1]}));

  # define vars
  my $key   = $a[1];
  my $value = $a[2];
  my $ret;

  # set new timer
  if($key eq "interval" || $key eq "alarminterval") {
    $key = "INTV_CHECK"
      if($key eq "interval");
    $key = "INTV_ALARM"
      if($key eq "alarminterval");
    # update timer
    $hash->{$key} = $value;
    RemoveInternalTimer($hash);
    # check alarm
    if($hash->{ALARM} eq "0") {
      $hash->{INTERVAL} = $hash->{INTV_CHECK};
    } else {
      $hash->{INTERVAL} = $hash->{INTV_ALARM};
    }
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 1);
  }

  # set warnings
  if($key eq "templow" || $key eq "temphigh") {
    # check range
    return "wrong value: range -55°C - 125°C"
      if(int($value) < -55 || int($value) > 125);
  }

  # set value
  Log 4, "OWTEMP set $hash->{NAME} $key $value";

  # check for real sensor
  if($hash->{OW_ID} ne "none") {
    # real senson
    $ret = OW::put($hash->{OW_PATH}."/$key",$value);
  } else {
    # dummy sensor
    $dummy{$key} = $value;
  }

  # update readings
  if($key ne "interval" || $key ne "alarminterval") {
    $hash->{LOCAL} = 1;
    $ret = OWTEMP_GetUpdate($hash,$key);
    delete $hash->{LOCAL};
  }
  
  return undef;
}

#####################################
sub
OWTEMP_Define($$)
{
  my ($hash, $def) = @_;

  # define <name> OWTEMP <id> [interval] [alarminterval]
  # e.g.: define flow OWTEMP 332670010800 300

  my @a = split("[ \t][ \t]*", $def);

  # check syntax
  return "wrong syntax: define <name> OWTEMP <id> [interval] [alarminterval]"
    if(int(@a) < 2 && int(@a) > 5);
  # check ID format
  return "Define $a[0]: missing ID or wrong ID format: specify a 12 digit value or set it to none for demo mode"
    if(lc($a[2]) ne "none" && lc($a[2]) !~ m/^[0-9|a-f]{12}$/);

  # define vars
  my $name          = $a[0];
  my $id            = $a[2];
  my $interval      = 300;
  my $alarminterval = 300;
  my $scale         = "";
  my $ret           = "";

  # overwrite default intervals if set by define
  if(int(@a)==4) { $interval = $a[3]; }
  if(int(@a)==5) { $interval = $a[3]; $alarminterval = $a[4] }

  # define device internals
  $hash->{ALARM}      = 0;
  $hash->{INTERVAL}   = $interval;
  $hash->{INTV_CHECK} = $interval;
  $hash->{INTV_ALARM} = $alarminterval;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $gets{family};
  $hash->{OW_PATH}    = $hash->{OW_FAMILY}.".".$hash->{OW_ID};
  $hash->{PRESENT}    = 0;

  $modules{OWTEMP}{defptr}{$a[2]} = $hash;

  # assign IO port
  AssignIoPort($hash);
  return "No I/O device found. Please define a OWFS device first."
    if(!defined($hash->{IODev}->{NAME}));

  # get scale from I/O device
  $scale = $attr{$hash->{IODev}->{NAME}}{"temp-scale"};
  # define scale for temperature values
  $scale = "Celsius"    if ($scale eq "C");
  $scale = "Fahrenheit" if ($scale eq "F");
  $scale = "Kelvin"     if ($scale eq "K");
  $scale = "Rankine"    if ($scale eq "R");
  $hash->{OW_SCALE} = $scale;

  $hash->{STATE} = "Defined";

  # define dummy values for testing
  if($hash->{OW_ID} eq "none") {
    my $now   = TimeNow();
    $dummy{address}     = $hash->{OW_FAMILY}.$hash->{OW_ID}.$dummy{crc8};
    $dummy{family}      = $hash->{OW_FAMILY};
    $dummy{id}          = $hash->{OW_ID};
    $dummy{temperature} = "80.0000 (".$hash->{OW_SCALE}.")";
    foreach my $r (sort keys %gets) {
      $hash->{READINGS}{$r}{TIME} = $now;
      $hash->{READINGS}{$r}{VAL}  = $dummy{$r};
      Log 4, "OWTEMP $hash->{NAME} $r: ".$dummy{$r};
    }
  }

  $hash->{STATE} = "Initialized";

  # initalize
  $hash->{LOCAL} = 1;
  $ret = OWTEMP_GetUpdate($hash,"");
  delete $hash->{LOCAL};

  # exit if sensor is not present
  return "Define $hash->{NAME}: Sensor is not reachable. Check first your 1-wire connection."
    if(defined($ret) && $ret eq 1);

  if(!$hash->{LOCAL}) {
    if($hash->{ALARM} eq "0") {
      $hash->{INTERVAL} = $hash->{INTV_CHECK};
    } else {
      $hash->{INTERVAL} = $hash->{INTV_ALARM};
    }
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 0);
  }

  return undef;
}

#####################################
sub
OWTEMP_Undef($$)
{
  my ($hash, $name) = @_;

  delete($modules{OWTEMP}{defptr}{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

1;

=pod
=begin html

<a name="OWTEMP"></a>
<h3>OWTEMP</h3>
<ul>
  High-Precision 1-Wire Digital Thermometer.
  <br><br>

  Note:<br>
  Please define an <a href="#OWFS">OWFS</a> device first.
  <br><br>

  <a name="OWTEMPdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWTEMP &lt;id&gt; [&lt;interval&gt;] [&lt;alarminterval&gt;]</code>
    <br><br>

    Define a 1-wire Digital Thermometer device.<br><br>

    <code>&lt;id&gt;</code>
    <ul>
      Corresponding to the <a href="#owfs_id">id</a> of the input device.<br>
      Set &lt;id&gt; to <code>none</code>for demo mode.
    </ul>
    <code>&lt;interval&gt;</code>
    <ul>
      Sets the status polling intervall in seconds to the given value. The default is 300 seconds.
    </ul>
    <code>&lt;alarminterval&gt;</code>
    <ul>
      Sets the alarm polling intervall in seconds to the given value. The default is 300 seconds.
      <br><br>
    </ul>

    Note:<br>
    Currently supported <a href="#owfs_type">type</a>: <code>DS18S20</code>.<br><br>

    Example:
    <ul>
      <code>define KG.hz.TF.01 OWTEMP 14B598010800 300 60</code><br>
    </ul>
    <br>
  </ul>

  <a name="OWTEMPset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul>
      <li><a name="owtemp_templow"></a>
        <code>templow</code> (read-write)<br>
        The upper limit for the low temperature alarm state.
      </li>
      <li><a name="owtemp_temphigh"></a>
        <code>temphigh</code> (read-write)<br>
        The lower limit for the high temperature alarm state.
      </li>
      <li><a name="owtemp_ALARMINT"></a>
        <code>ALARMINT</code> (write-only)<br>
        Sets the alarm polling intervall in seconds to the given value.
      </li>
      <li><a name="owtemp_INTERVAL"></a>
        <code>INTERVAL</code> (write-only)<br>
        Sets the status polling intervall in seconds to the given value.
      </li>
    </ul>
  </ul><br>

  <a name="OWTEMPget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul>
      <li><a href="#owfs_address">address</a> (read-only)</li>
      <li><a href="#owfs_crc8">crc8</a> (read-only)</li>
      <li><a href="#owfs_family">family</a> (read-only)</li>
      <li><a href="#owfs_id">id</a> (read-only)</li>
      <li><a href="#owfs_locator">locator</a> (read-only)</li>
      <li><a href="#owfs_present">present</a> (read-only)</li>
      <li><a name="owtemp_temperature"></a>
        <code>temperature</code> (read-only)<br>
        Read by the chip at high resolution (~12 bits). Units are selected from
        the defined OWFS Device. See <a href="#owfs_temp-scale">temp-scale</a> for choices.
      </li>
      <li><a href="#owtemp_templow">templow</a> (read-write)</li>
      <li><a href="#owtemp_temphigh">temphigh</a> (read-write)</li>
      <li><a href="#owfs_type">type</a> (read-only)</li>
      <br>
    </ul>
    Examples:
    <ul>
      <code>get KG.hz.TF.01 type</code><br>
      <code>KG.hz.TF.01 type => DS18S20</code><br><br>
      <code>get KG.hz.TF.01 temperature</code><br>
      <code>KG.hz.TF.01 temperature => 38.2500 (Celsius)</code>
    </ul>
    <br>
  </ul>

  <a name="OWTEMPattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#IODev">IODev</a></li>
  </ul>
  <br>

</ul>
  
=end html
=cut
