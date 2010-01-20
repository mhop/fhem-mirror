# 82_LGTV.pm; an FHEM high level module for interfacing
# with LG's Scarlet Series of LCDs (e. g. LG 47LG7000)
# Trying to implement a generic command set so that is
# is re-usable with other low-level drivers besides my
# 80_xxLG7000.pm for a serial connection.
#
# Written by Kai 'wusel' Siering <wusel+fhem@uu.org> around 2010-01-20
#
# re-using code of 82_M232Voltage.pm
# written by Dr. Boris Neubert 2007-12-24
# e-mail: omega at online dot de
#
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub LGTV_Get($@);
sub LGTV_Define($$);
sub LGTV_GetStatus($);

my @commandlist = (
    "power state",
    "power on",
    "power off",
    "input AV1",
    "input AV2",
    "input AV3",
    "input AV3",
    "input Component",
    "input RGB",
    "input HDMI1",
    "input HDMI2",
    "input HDMI3",
    "input HDMI4",
    "input DVBT",
    "input PAL",
    "audio mute",
    "audio normal",
    "selected input"
);


###################################
sub
LGTV_Initialize($)
{
  my ($hash) = @_;

#  $hash->{GetFn}     = "LGTV_Get";
  $hash->{SetFn}     = "LGTV_Set";
  $hash->{DefFn}     = "LGTV_Define";

  $hash->{AttrList}  = "dummy:1,0 model:LGTV loglevel:0,1,2,3,4,5";
}

###################################
sub
LGTV_GetStatus($)
{
    my ($hash) = @_;
    
    if(!$hash->{LOCAL}) {
	InternalTimer(gettimeofday()+60, "LGTV_GetStatus", $hash, 1);
    }
    
    my $name = $hash->{NAME};
    
    my $d = IOWrite($hash, "power state");
    if(!defined($d)) {
	my $msg = "LGTV $name read error";
	Log GetLogLevel($name,2), $msg;
	return $msg;
    }
    my $tn = TimeNow();
    
    my ($value, $state)=split(" ", $d);
    
    if($value eq "power") {
	$hash->{READINGS}{$value}{TIME} = $tn;
	$hash->{READINGS}{$value}{VAL} = $state;
	$hash->{CHANGED}[0]= "$value: $state";
	$hash->{STATE} = $state;

	if($state eq "on") {
	    $d = IOWrite($hash, "selected input");
	    if(!defined($d)) {
		my $msg = "LGTV $name read error";
		Log GetLogLevel($name,2), $msg;
		return $msg;
	    }
	    $tn = TimeNow();
	    ($value, $state)=split(" ", $d);
	    
	    $hash->{READINGS}{$value}{TIME} = $tn;
	    $hash->{READINGS}{$value}{VAL} = $state;
	    $hash->{CHANGED}[1]= "$value: $state";
	    $hash->{STATE} = $hash->{STATE} . ", " . $state;
	}
    }
    
    DoTrigger($name, undef);
    
    Log GetLogLevel($name,4), "LGTV $name: $hash->{STATE}";
    
    return $hash->{STATE};
}

###################################
sub
LGTV_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = LGTV_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}


###################################
sub
LGTV_Set($@)
{
    my ($hash, @a) = @_;
    my $ret = undef;
    my $na = int(@a);
    my $ncmds=int(@commandlist);
    my $i;
    my $known_cmd=0;
    my $what = "";

    $what=$a[1];
    if($na>1) {
	for($i=2; $i<$na; $i++) {
	    $what=$what . " " . $a[$i];
	}
    }

    for($i=0; $i<$ncmds; $i++ && $known_cmd==0) {
	if($commandlist[$i] eq $what) {
	    $known_cmd+=1;
	}
    }

    if($known_cmd==0) {
	return "Unknown argument $what, choose one of power input audio";
    }

    $ret=IOWrite($hash, $what, "");

    return $ret;
}

#############################
sub
LGTV_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

#  return "syntax: define <name> LGTV an0..an5 [unit [factor]]"
#    if(int(@a) < 3 && int(@a) > 5);
#
#  my $reading= $a[2];
#  return "$reading is not an analog input, valid: an0..an5"
#    if($reading !~  /^an[0-5]$/) ;
#
#  my $unit= ((int(@a) > 3) ? $a[3] : "volts");
#  my $factor= ((int(@a) > 4) ? $a[4] : 1.0);
# 
#  $hash->{INPUT}= substr($reading,2);
#  $hash->{UNIT}= $unit;
#  $hash->{FACTOR}= $factor;

  AssignIoPort($hash);

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "LGTV_GetStatus", $hash, 0);
  }
  return undef;
}

1;
