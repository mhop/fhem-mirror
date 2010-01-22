# 82_LGTV.pm; an FHEM high level module for interfacing
# with LG's Scarlet Series of LCDs (e. g. LG 47LG7000)
# Trying to implement a generic command set so that is
# is re-usable with other low-level drivers besides my
# 80_xxLG7000.pm for a serial connection.
#
# Written by Kai 'wusel' Siering <wusel+fhem@uu.org> around 2010-01-20
# $Id: 82_LGTV.pm,v 1.2 2010-01-22 09:51:56 painseeker Exp $
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
    "input DVB-T",
    "input PAL",
    "audio mute",
    "audio normal",
    "selected input",
    "audio state"
);


###################################
sub
LGTV_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "LGTV_Get";
  $hash->{SetFn}     = "LGTV_Set";
  $hash->{DefFn}     = "LGTV_Define";

  $hash->{AttrList}  = "dummy:1,0 model:LGTV loglevel:0,1,2,3,4,5 TIMER:30";
}

###################################
sub
LGTV_GetStatus($)
{
    my ($hash) = @_;
    my $numchanged=0;
    my $name = $hash->{NAME};
    my @cmdlist;
    my $retval;

    @cmdlist=("get", "power", "state");
    
    $retval=LGTV_Set($hash, @cmdlist);

    my ($value, $state)=split(" ", $retval);
    if($value eq "power" && $state eq "on") {
	@cmdlist=("get", "selected", "input");
    
	$retval=LGTV_Set($hash, @cmdlist);
    }

    InternalTimer(gettimeofday()+$attr{$name}{TIMER}, "LGTV_GetStatus", $hash, 1);
    
    return;

    my $d = IOWrite($hash, "power state");
    if(!defined($d)) {
	my $msg = "LGTV $name read error";
	Log GetLogLevel($name,2), $msg;
	return $msg;
    }
    my $tn = TimeNow();
    
#    my ($value, $state)=split(" ", $d);

    if($value eq "power") {
	if($hash->{READINGS}{$value}{VAL} ne $state) {
	    $hash->{READINGS}{$value}{TIME} = $tn;
	    $hash->{READINGS}{$value}{VAL} = $state;
	    $hash->{CHANGED}[$numchanged++]= "$value: $state";
	    $hash->{STATE} = $hash->{READINGS}{$value}{VAL};
	}
	$hash->{STATE} = $hash->{READINGS}{$value}{VAL};
    }

    if($state eq "on") {
	$d = IOWrite($hash, "selected input");
	if(!defined($d)) {
	    my $msg = "LGTV $name read error";
	    Log GetLogLevel($name,2), $msg;
	    return $msg;
	}

	if($value eq "input") { # ... and not e. g. "error" ;)
	    if($hash->{READINGS}{$value}{VAL} ne $state) {
		$tn = TimeNow();
		($value, $state)=split(" ", $d);
		
		$hash->{READINGS}{$value}{TIME} = $tn;
		$hash->{READINGS}{$value}{VAL} = $state;
		$hash->{CHANGED}[$numchanged++]= "$value: $state";
	    }
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
    my $msg;

    return "argument is missing" if(int(@a) != 2);

    if($a[1] eq "power") {
	$msg="get power state";
    } elsif($a[1] eq "input") {
	$msg="get selected input";
    } elsif($a[1] eq "audio") {
	$msg="get audio state";
    } else {
	return "unknown get value, valid is power, input, audio";
    }
    my @msgarray=split(" ", $msg);
    my $v = LGTV_Set($hash, @msgarray);
    return "$a[0] $v";
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
    my $name = $hash->{NAME};

    $what=$a[1];
    if($na>1) {
	for($i=2; $i<$na; $i++) {
	    $what=$what . " " . lc($a[$i]);
	}
    }

    for($i=0; $i<$ncmds; $i++) {
	if(lc($commandlist[$i]) eq $what) {
	    $what=$commandlist[$i];
	    $known_cmd+=1;
	}
    }

    if($known_cmd==0) {
	return "Unknown argument $what, choose one of power input audio";
    }

    $ret=IOWrite($hash, $what, "");
    if(!defined($ret)) {
	my $msg = "LGTV $name read error";
	Log GetLogLevel($name,2), $msg;
    } else {
	my $tn = TimeNow();
	my ($value, $state)=split(" ", $ret);
	# Logic of the following: if no error:
	#                           if unset READINGS or difference:
	#                             store READINGS
	#                             if power-status: update STATE
	#                             if input-status: update STATE
	if($value ne "error") {
	    if(!defined($hash->{READINGS}{$value}{VAL}) || $state ne $hash->{READINGS}{$value}{VAL}) {
		$hash->{READINGS}{$value}{TIME} = $tn;
		$hash->{READINGS}{$value}{VAL} = $state;
		$hash->{CHANGED}[0]= "$value: $state";
	    }
	    if($value eq "power") {
		$hash->{STATE}=$state;		    
	    }
	    if($value eq "input") { # implies power being on, usually ...
		$hash->{STATE}=$hash->{READINGS}{"power"}{VAL} . ", " . $state;
	    }
	}
    }
    
    DoTrigger($name, undef);

    return $ret;
}


#############################
sub
LGTV_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  AssignIoPort($hash);

  $attr{$name}{TIMER}=30;

  InternalTimer(gettimeofday()+$attr{$name}{TIMER}, "LGTV_GetStatus", $hash, 0);

  # Preset if undefined
  if(!defined($hash->{READINGS}{"power"}{VAL})) {
      my $tn = TimeNow();
      $hash->{READINGS}{"power"}{VAL}="unknown"; 
      $hash->{READINGS}{"power"}{TIME}=$tn; 
  }
  return undef;
}

1;
