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
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use OW;

my %defptr;

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
  "alias"       => "",
  "temphigh"    => "",
  "templow"     => "",
  "INTERVAL"    => "",
  "ALARMINT"    => "",
);

my %updates = (
  "present"     => "",
  "temperature" => "",
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
OWTEMP_UpdateReading($$$$$)
{
  my ($hash,$reading,$now,$scale,$value) = @_;
  return 0 if (!defined($value) || $value eq "");

  # trim spaces
  $value =~ s/\s//g;

  $value = sprintf("%.4f",$value) if($reading eq "temperature");
  $value = $value . " ($scale)" if($reading eq "temperature" && $scale ne "");
  $hash->{READINGS}{$reading}{TIME} = $now;
  $hash->{READINGS}{$reading}{VAL}  = $value;
  Log 4, "OWTEMP $hash->{NAME} $reading: $value";

  return $value;
}

#####################################
sub
OWTEMP_GetUpdate($$)
{
  my ($hash,$a) = @_;

  if (!$hash->{LOCAL}) {
    if ($hash->{ALARM} == 0) {
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 1);
    } else {
      InternalTimer(gettimeofday()+$hash->{ALARMINT}, "OWTEMP_GetUpdate", $hash, 1);
    }
  }

  my $name = $hash->{NAME};

  # get OWTEMP information
  my $path  = $hash->{OW_PATH};
  my $now   = TimeNow();
  my $scale = $attr{$hash->{IODev}->{NAME}}{"temp-scale"};
  my $value = "";
  my $ret   = "";
  my $count = 0;

  $scale = "Celsius"    if ($scale eq "C");
  $scale = "Fahrenheit" if ($scale eq "F");
  $scale = "Kelvin"     if ($scale eq "K");
  $scale = "Rankine"    if ($scale eq "R");

  my $temp = "";

  if (!$hash->{LOCAL} || $hash->{LOCAL} == 2) {
    if (defined($hash->{LOCAL}) && $hash->{LOCAL} == 2) {
      foreach my $r (sort keys %gets) {
        $value = OW::get("/uncached/$path/".$r);
        $temp = $value if ($r eq "temperature");
        $ret = OWTEMP_UpdateReading($hash,$r,$now,$scale,$value);
	$hash->{CHANGED}[$count] = "$r: $ret";
	$count++;
      }
    } else {
      foreach my $r (sort keys %updates) {
        $value = OW::get("/uncached/$path/".$r);
        $temp = $value if ($r eq "temperature");
        $ret = OWTEMP_UpdateReading($hash,$r,$now,$scale,$value);
	$hash->{CHANGED}[$count] = "$r: $ret";
	$count++;
      }
    }

    # trim spaces
    $temp =~ s/\s//g;
    # set default warning to none
    my $warn  = "none";
    my $alarm = "";
    $hash->{ALARM} = "0";

    if ($temp <= $hash->{READINGS}{templow}{VAL}) {
      $warn = "templow";
      $hash->{ALARM} = "1";
      $ret = OWTEMP_UpdateReading($hash,"warnings",$now,"",$warn);
      $alarm = "A: ".$hash->{ALARM};
    } elsif ($temp >= $hash->{READINGS}{temphigh}{VAL}) {
      $warn = "temphigh";
      $hash->{ALARM} = "1";
      $ret = OWTEMP_UpdateReading($hash,"warnings",$now,"",$warn);
      $alarm = "A: ".$hash->{ALARM};
    } else {
      $ret = OWTEMP_UpdateReading($hash,"warnings",$now,"",$warn);
      $alarm = "A: ".$hash->{ALARM};
    }
    $hash->{CHANGED}[$count] = "warnings: $warn";
    $hash->{CHANGED}[$count+1] = "T: " . $temp . $alarm;
  
    $hash->{STATE} = "T: " . $temp . "  " .
                     "L: " . $hash->{READINGS}{templow}{VAL} . "  " .
                     "H: " . $hash->{READINGS}{temphigh}{VAL} . "  " .
                     $alarm;
  } else {
    $value = OW::get("/uncached/$path/".$a);
    foreach my $r (sort keys %gets) {
      $ret = OWTEMP_UpdateReading($hash,$r,$now,$scale,$value) if($r eq $a);
    }
    return $value;
  }

  if(!$hash->{LOCAL} || $hash->{LOCAL} == 2) {
    DoTrigger($name, undef) if($init_done);
  }

  return 1;
}

###################################
sub
OWTEMP_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing @a" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %gets)
        if(!defined($gets{$a[1]}));

  my $value;
  $hash->{LOCAL} = 1;
  $value = OWTEMP_GetUpdate($hash,$a[1]);
  delete $hash->{LOCAL};

  my $reading = $a[1];

  if(defined($hash->{READINGS}{$reading})) {
    $value = $hash->{READINGS}{$reading}{VAL};
  }

  return "$a[0] $reading => $value";
}

###################################
sub
OWTEMP_Set($@)
{
  my ($hash, @a) = @_;
  return "set needs one parameter" if(int(@a) != 3);
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %sets)
        if(!defined($sets{$a[1]}));

  my $key   = $a[1];
  my $value = $a[2];
  my $path  = $hash->{OW_PATH};
  my $ret;

  if ($key eq "INTERVAL" || $key eq "ALARMINT") {
    $hash->{$key} = $value;
    #RemoveInternalTimer($hash);
    if ($hash->{ALARM} == 0) {
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 0);
    } else {
      InternalTimer(gettimeofday()+$hash->{ALARMINT}, "OWTEMP_GetUpdate", $hash, 0);
    }
    Log 4, "OWTEMP $hash->{NAME} $key $value";
  } elsif ($key eq "templow" || $key eq "temphigh") {
    return "wrong value: range -55°C - 125°C" if (int($value) < -55 || int($value) > 125);
    $ret = OW::put("$path/".$key,$value);
    Log 4, "OWTEMP $hash->{NAME} $key $value";
    $hash->{LOCAL} = 1;
    OWTEMP_GetUpdate($hash,$key);
    delete $hash->{LOCAL};
  } else {
    $ret = OW::put("$path/".$key,$value);
    $hash->{LOCAL} = 1;
    $value = OWTEMP_GetUpdate($hash,$key);
    delete $hash->{LOCAL};
    Log 4, "OWTEMP $hash->{NAME} $key $value";
  }
  return undef;
}

###################################
sub
OWTEMP_Define($$)
{
  my ($hash, $def) = @_;

  # define <name> OWTEMP <id> [interval] [alarminterval]
  # define flow OWTEMP 332670010800 300

  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> OWTEMP <id> [interval] [alarminterval]"
    if(int(@a) < 2 && int(@a) > 5);
  return "Define $a[0]: wrong ID format: specify a 12 digit value"
    if(lc($a[2]) !~ m/^[0-9|a-f]{12}$/);

  $hash->{STATE} = "Initialized";

  my $name     = $a[0];
  my $id       = $a[2];
  my $interval = 300;
  my $alarmint = 300;
  if(int(@a)==4) { $interval = $a[3]; }
  if(int(@a)==5) { $interval = $a[3]; $alarmint = $a[4] }

  $hash->{OW_ID}     = $id;
  $hash->{OW_FAMILY} = $gets{family};
  $hash->{OW_PATH}   = $gets{family}.".".$hash->{OW_ID};
  $hash->{INTERVAL}  = $interval;
  $hash->{ALARMINT}  = $alarmint;
  $hash->{ALARM}     = 0;

  $defptr{$a[2]} = $hash;
  AssignIoPort($hash);

  return "No I/O device found. Please define a OWFS device first."
    if(!defined($hash->{IODev}->{NAME}));
  $hash->{LOCAL} = 2;
  OWTEMP_GetUpdate($hash,"");
  delete $hash->{LOCAL};

  if ($hash->{ALARM} == "0") {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 0);
  } else {
    InternalTimer(gettimeofday()+$hash->{ALARMINT}, "OWTEMP_GetUpdate", $hash, 0);
  }

  return undef;
}

#####################################
sub
OWTEMP_Undef($$)
{
  my ($hash, $name) = @_;

  delete($defptr{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

1;
