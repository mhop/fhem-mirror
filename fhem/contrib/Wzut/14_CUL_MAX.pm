############### ###############################
# $Id: 14_CUL_MAX.pm 21921 2020-05-12 15:44:06Z Wzut $
# 
#  (c) 2012 Copyright: Matthias Gehre, M.Gehre@gmx.de
#  (c) 2019 Copyright: Wzut
#
#  All rights reserved
#
#  FHEM Forum : http://forum.fhem.de/
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

package FHEM::CUL_MAX;  ## no critic 'package'
# das no critic könnte weg wenn die Module nicht mehr zwingend mit NN_ beginnnen müssen


use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Time::Local;
require Data::Dumper;
use POSIX qw(ceil);
use GPUtils qw(GP_Import GP_Export); # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

BEGIN
{
    # Import from main::
    GP_Import(
	qw(
	attr
	AttrVal
	AttrNum
	AssignIoPort
	CommandGet
	defs
	devspec2array
	Dispatch
	FmtDateTime
	init_done
	InternalTimer
	InternalVal
	IOWrite
	IsDisabled
	IsIgnored
	IsDummy
	Log3
	modules
	readingsSingleUpdate
	readingsBulkUpdate
	readingsBeginUpdate
	readingsEndUpdate
	ReadingsNum
	ReadingsVal
	readingFnAttributes
	RemoveInternalTimer
	TimeNow
	)
    );

    # Export to main
    GP_Export( qw(Initialize) );
}

my $hasmeta = 0;
# ältere Installationen haben noch kein Meta.pm
if (-e $attr{global}{modpath}.'/FHEM/Meta.pm') {
    eval {
	require FHEM::Meta;
    };
    $hasmeta = 1 if (!$@);
}

my %device_types = (
  0 => 'Cube',
  1 => 'HeatingThermostat',
  2 => 'HeatingThermostatPlus',
  3 => 'WallMountedThermostat',
  4 => 'ShutterContact',
  5 => 'PushButton',
  6 => 'virtualShutterContact',
  7 => 'virtualThermostat',
  8 => 'PlugAdapter',
  9 => 'new'
);

my %msgId2Cmd = (
                 '00' => 'PairPing',
                 '01' => 'PairPong',
                 '02' => 'Ack',
                 '03' => 'TimeInformation',
                 '10' => 'ConfigWeekProfile',
                 '11' => 'ConfigTemperatures', #like eco/comfort etc
                 '12' => 'ConfigValve',
                 '20' => 'AddLinkPartner',
                 '21' => 'RemoveLinkPartner',
                 '22' => 'SetGroupId',
                 '23' => 'RemoveGroupId',
                 '30' => 'ShutterContactState',
                 '40' => 'SetTemperature', # to thermostat
                 '42' => 'WallThermostatControl', # by WallMountedThermostat
                 # Sending this without payload to thermostat sets desiredTempeerature to the comfort/eco temperature
                 # We don't use it, we just do SetTemperature
                 '43' => 'SetComfortTemperature',
                 '44' => 'SetEcoTemperature',
                 '50' => 'PushButtonState',
                 '60' => 'ThermostatState', # by HeatingThermostat
                 '70' => 'WallThermostatState',
                 '82' => 'SetDisplayActualTemperature',
                 'F1' => 'WakeUp',
                 'F0' => 'Reset',
               );

my %msgCmd2Id = reverse %msgId2Cmd;

my $defaultWeekProfile = '444855084520452045204520452045204520452045204520452044485508452045204520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc5514452045204520452045204520452045204520';
sub ParseTemperature  { my $v = shift; return $v eq 'on' ? 30.5 : ($v eq 'off' ? 4.5 :$v); }
sub validTemperature  { my $v = shift; return $v eq 'on' || $v eq 'off' || ($v =~ /^\d+(\.[05])?$/x && $v >= 4.5 && $v <= 30.5); }

my $ackTimeout      = 3; # seconds
my $maxRetryCnt     = 3;

sub Initialize {

    my $hash = shift;

    $hash->{Match}     = '^Z';
    $hash->{DefFn}     = \&Define;
    $hash->{Clients}   = ':MAX:';
    $hash->{MatchList} = {'1:MAX' => 'MAX'};
    $hash->{UndefFn}   = \&Undef;
    $hash->{ParseFn}   = \&Parse;
    $hash->{RenameFn}  = \&RenameFn;
    $hash->{SetFn}     = \&Set;
    $hash->{GetFn}     = \&Get;
    $hash->{AttrFn}    = \&Attr;
    $hash->{AttrList}  = 'IODev IOgrp do_not_notify:1,0 ignore:0,1 debug:0,1 showtime:1,0 '.
		       'fakeSCaddr fakeWTaddr broadcastTimeDiff blacklist whitelist '.
			$readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash ) if ($hasmeta);
    return;
}

sub updateConfig {

    # this routine is called 5 sec after the last define of a restart
    # this gives FHEM sufficient time to fill in attributes

    my $hash = shift;
    my $name = $hash->{NAME};

    if (!$init_done) {
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday()+5, 'FHEM::CUL_MAX::updateConfig', $hash, 0);
	return;
    }

    $attr{$name}{fakeSCaddr}  = '222222' unless (exists($attr{$name}{fakeSCaddr}));
    $attr{$name}{fakeWTaddr}  = '111111' unless (exists($attr{$name}{fakeWTaddr}));

    my $iogrp = AttrVal($name, 'IOgrp', '');
    my @ios;
    my $version;

    if ($iogrp && ($iogrp =~ m{ \s }xms)) {
	Log3($name, 2, "$name, not allowed whitespace found in attribute IOgrp, removing it !");
	$iogrp =~ s/\s//xg;
	$attr{$name}{'IOgrp'} = $iogrp;
    }

    if ($iogrp ) {
	@ios = split(',',$iogrp);
	$hash->{IOgrp} = '';
	Log3($name, 1 , "$name, attribute IOgrp has only a single CUL device, please delete attribute IOgrp !") if (int(@ios) < 2);
	$hash->{'.culids'} = '';

	foreach my $io (@ios) {
	    AssignIoPort($hash, $io); # mit proposed $_
	    if (defined($hash->{IODev})) {

		$version = Check($hash);
		$hash->{$io.'_VERSION'} = $version;
		$hash->{'.VERSION'}     = $version;

		Log3($name, 1, "$name, detected very old firmware version $version of the CUL-compatible IODev $io") if ($version < 152);

		if ($version >= 152) {
		    # Doing this on older firmware disables MAX mode
		    # Append to initString, so this is resend if cul disappears and then reappears
		    if (!defined($hash->{IODev}{'.maxid'})) {
			IOWrite($hash, '', 'Za'. $hash->{addr});
			$hash->{IODev}{initString} .= "\nZa". $hash->{addr}; 
		    }
		    else { 
			IOWrite($hash, '', 'Za'. $hash->{IODev}{'.maxid'});
			$hash->{IODev}{initString} .= "\nZa".$hash->{IODev}{'.maxid'}; 
		    }
		}

		if ($version >= 153) {
		    # Doing this on older firmware disables MAX mode
		    my $cmd = 'Zw'. AttrVal($name, 'fakeWTaddr', '111111');
		    IOWrite($hash, '',  $cmd);
		    $hash->{IODev}{initString} .= "\n".$cmd;
		}

		$hash->{IOgrp} .= ($hash->{IOgrp}) ? ','.$io : $io ;
	    }# iodev
	}
    } # iogrp
    else { # no IOgrp , use IOdev
	AssignIoPort($hash);

	if (defined($hash->{IODev})) {
	    $version = Check($hash);
	    $hash->{'.VERSION'} = $version;
	    Log3($name, 1, "$name, detected very old firmware version $version of the CUL-compatible IODev $hash->{IODev}") if ($version < 152);

	    if ($version >= 152) {
		#Doing this on older firmware disables MAX mode
		IOWrite($hash, '', 'Za'. $hash->{addr});
		#Append to initString, so this is resend if cul disappears and then reappears
		$hash->{IODev}{initString} .= "\nZa". $hash->{addr}; 
	    }
	    if ($version >= 153) {
		#Doing this on older firmware disables MAX mode
		my $cmd = 'Zw'. AttrVal($name, 'fakeWTaddr', '111111');
		IOWrite($hash, '', $cmd);
		$hash->{IODev}{initString} .= "\n".$cmd;
	    }
	}
    }# use IOdev

    if (!defined($hash->{IODev})) {
        Log3($name, 1, "$name, did not find suitable IODev (CUL etc. in rfmode MAX)! You may want to execute 'attr $name IODev SomeCUL'");
        return;
    }

    #This interface is shared with 00_MAXLAN.pm
    #$hash->{Send} = \&CUL_MAX_Send; -> verschoben nach Define

    #Start broadcasting time after 30 seconds, so there is enough time to parse the config
    InternalTimer(gettimeofday() +  30, 'FHEM::CUL_MAX::BroadcastTime', $hash, 0);
    InternalTimer(gettimeofday() + 300, 'FHEM::CUL_MAX::Alive', $hash, 0);
    return;
}

sub Define {

    my $hash = shift;
    my $def  = shift;

    my ($name, undef, $addr) = split(m{ \s+ }xms, $def, 3);

    return "wrong syntax: define $name CUL_MAX <MAXID>" if (!$addr);

    my $ret;
    $addr = lc($addr);

    if ((length($addr) != 6) || ($addr !~ m{\A[a-f0-9]{6}\z}xms)) {
	$ret = "$name, the MAXID must be 6 hexadecimal digits";
	Log3($name, 1, $ret);
	return $ret;
    }

    if (exists($modules{CUL_MAX}{defptr}) && ($modules{CUL_MAX}{defptr}->{NAME} ne $name)) {
        $ret = "a CUL_MAX device with MAXID $addr is already defined !";
        Log3($name, 1, $ret);
        return $ret;
    }

    $hash->{addr}         = $addr;
    $hash->{STATE}        = 'Defined';
    $hash->{cnt}          = 0;
    $hash->{pairmode}     = 0;
    $hash->{retryCount}   = 0;
    $hash->{sendQueue}    = [];
    $hash->{sq}           = 0;
    $hash->{LASTInputDev} = '';
    $hash->{'.culids'}    = '';
    $hash->{SVN}          = (qw($Id: 14_CUL_MAX.pm 21921 2020-05-12 15:44:06Z Wzut $))[2];
    $hash->{Send}         = \&Send;

    $modules{CUL_MAX}{defptr} = $hash;

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + 5, 'FHEM::CUL_MAX::updateConfig', $hash, 0);

    if ($hasmeta) {
	return $@ unless ( FHEM::Meta::SetInternals($hash) )
    }

    return;
}

#####################################

sub Undef
{
  my $hash = shift;
  RemoveInternalTimer($hash);
  delete $modules{CUL_MAX}{defptr};
  return;
}

sub DisablePairmode
{
  my $hash = shift;
  $hash->{pairmode} = 0;
  return;
}

sub Check
{
    my $hash    = shift;
    my $nocheck = shift;
    $nocheck //= 0;
    my $name = $hash->{NAME};

    if (!defined($hash->{IODev})) {
	Log3($name, 1, "$name, no IODev found");
	return 0;
    }

    if (!defined($hash->{IODev}{VERSION})) {
	Log3($name, 1, "$name, IODev has no VERSION");
	return 0;
    }

    my $cul = $hash->{IODev}{NAME};
    my $maxid = lc(AttrVal($cul,'maxid',''));
 
    if ($maxid && $maxid !~ m{\A[a-f0-9]{6}\z}xms) {
	$maxid = '';
	Log3($name, 1, "$name, wrong value for attribute maxid on $cul - ignoring !");
    }

    if (!$maxid) {
	Log3($name, 1, "$name, please set attribute maxid on $cul !") if (AttrVal($name,'IOgrp',''));
    }
    else { 
	$hash->{$cul.'_MAXID'} = $maxid;
	$hash->{'.culids'} .= $maxid.' ' if (index($hash->{'.culids'}, $maxid) == -1);
	$hash->{IODev}{'.maxid'} = $maxid;
	$hash->{addr} = $maxid;
    }

    # a-culfw is compatibel to culfw 154
    return 154  if (index($hash->{IODev}{VERSION}, 'a-culfw') != -1);

    my $version = $hash->{IODev}{VERSION};

    # Looks like 'V 1.49 CUL868'
    if ($version =~ m{\AV\s
		    (?<major> (?:[0-9]{1,2}))\.
		    (?<minor> (?:[0-9]{1,2}))\s
		    }xms) {

	$version = 100*$+{major} + $+{minor};
	Log3($name, 2, "$name, You are using an old version of the CUL firmware, which has known bugs with respect to MAX! support. Please update.") if ($version < 154);
	return $version;
    }

    Log3($name, 1, "$name, could not correctly parse IODev->{VERSION} = $version");
    return 0;
}

sub Attr {

    my ($cmd, $name, $attrName, $attrVal) = @_;
    return if ($cmd ne 'set');

    if ((($attrName eq 'fakeWTaddr')
	|| ($attrName eq 'fakeSCaddr'))
	&& ($attrVal !~ m{\A[0-9a-fA-F]{6}\z}xms)) { 
	return "$name, invalid value $attrVal for attr $attrName"; 
    }

    return;
}


sub Get {

    my ($hash, $name, $cmd, @args) = @_;
    return "$name, get needs at least one parameter" if (!$cmd);

    if ($cmd eq 'deviceinfo') {

	return 'missing address' if (!@args);
        my $addr = lc($args[0]);

        return 'wrong format , need 6 digts hex' if ($addr !~ m{\A[a-f0-9]{6}\z}xms);
	return "no MAX device with address $addr found !" if (!exists($modules{MAX}{defptr}{$addr}));
	my $list = eval { 
	    #use Data::Dumper; 
	    return Dumper($modules{MAX}{defptr}{$addr}); 
	};
	return $@ if ($@);
	return $list;
    }
 
    if ($cmd eq 'showSendQueue') {
	return 'Send Queue is empty !' if (!$hash->{sq});

	my ($i,$dst,$cm,$time,$cul,$s,@lines);
	my $dw = 11;
	my $cw =  7;
	my $lw =  3;

	for ($i = 0; $i < @{$hash->{sendQueue}}; $i++) {
	    $dst  = $hash->{sendQueue}[$i]->{dst_name};
	    $cm   = $hash->{sendQueue}[$i]->{cmd};
	    $time = FmtDateTime($hash->{sendQueue}[$i]->{time});
	    $cul  = (defined($hash->{sendQueue}[$i]->{CUL})) ? $hash->{sendQueue}[$i]->{CUL} : '-';

	    $dw   = length($dst) if (length($dst) > $dw);
	    $cw   = length($cm)  if (length($cm)  > $cw);
	    $lw   = length($cul) if (length($cul) > $lw);

	    push @lines, "$time,$dst,$cm,$cul";
	}

	$s = '        Time        | Destination'.(' 'x($dw-11)).' | Command'.(' 'x($cw-7));
	$s.= (AttrVal($name,'IOgrp','')) ? ' | CUL'.(' 'x($lw-3)) : '';

	my $line = ('-' x length($s));
	while ( $s =~ m/\|/gx ) { substr $line, (pos($s)-1), 1, '+'; }

	$s .= "\n".$line."\n";

	foreach my $l (@lines) {
    	    my @ar = split(',',$l);
    	    $ar[1] .= (' 'x($dw-length($ar[1]))) if ($dw-length($ar[1]));
    	    $ar[2] .= (' 'x($cw-length($ar[2]))) if ($cw-length($ar[2]));
    	    $s.= "$ar[0] | $ar[1] | $ar[2]";
    	    $s.= (AttrVal($name,'IOgrp','')) ? " | $ar[3]\n" : "\n";
	}
	return $s.$line;
    }

   return "unknown command $cmd, choose one of deviceinfo showSendQueue:noArg";
}


sub Set {

    my ( $hash, $name, $cmd, @args ) = @_;
    $cmd // return "set $name needs at least one parameter";

    if ($cmd eq 'sendTime') {
	$args[0] //= '';
	return "invalid destination addr $args[0]" if ($args[0] !~ m{\A[a-f0-9]{6}\z}xms);
	return "unkown MAX device $args[0]" if (!exists($modules{MAX}{defptr}{$args[0]}));
	SendTimeInformation($hash, $args[0]);
	return;
    }

    if ($cmd eq 'deleteSendQueue') {
	$hash->{sendQueue} = [];
	$hash->{sq} = 0;
	return;
    }

    if ($cmd eq 'pairmode') {
	$hash->{pairmode} = 1;
	my $pairmodeDuration = (int($args[0]) > 60) ? int($args[0]) : 60;
	InternalTimer(gettimeofday()+$pairmodeDuration, 'FHEM::CUL_MAX::DisablePairmode', $hash, 0);
	return;
    }

    if ($cmd eq 'broadcastTime') {
	BroadcastTime($hash, 1);
	return;
    }

    if (($cmd eq 'fakeSC') || ($cmd eq 'fakeWT')) {
	return "$name invalid number of arguments for $cmd" if (!@args);
	my $dest = $args[0];
	my $destname;
	# $dest may be either a name or an address
	if (exists($defs{$dest})) {
	    return 'Destination is not a MAX device' if ($defs{$dest}{TYPE} ne 'MAX');
	    $destname = $dest;
	    $dest = $defs{$dest}{addr};
	}
	else {
	    $dest = lc($dest); #address to lower-case
	    return "No MAX device with address $dest found !" if (!exists($modules{MAX}{defptr}{$dest}));
	    $destname = $modules{MAX}{defptr}{$dest}{NAME};
	}

	my $groupid = ReadingsNum($destname, 'groupid', 0);

	if ($cmd eq 'fakeSC') {
	    return "$name, invalid number of arguments for $cmd" if (@args != 2);
	    return "$name, invalid fakeSCaddr attribute set (must not be 000000)" if (AttrVal($name,'fakeSCaddr','') eq '000000');

	    #my $state = $args[1] ? '12' : '10';
	    
	    return Send($hash, 
				'ShutterContactState',
				$dest,
				($args[1]) ? '12' : '10',
				groupId => sprintf('%02x', $groupid),
            			flags   => ( $groupid ? '04' : '06' ),
				src     => AttrVal($name, 'fakeSCaddr', '222222')
				);
	}
     
	if ($cmd eq 'fakeWT') {
	    return "$name, invalid number of arguments for $cmd" if (@args != 3);
	    return "$name, desiredTemperature is invalid" if (!validTemperature($args[1]));
	    return "$name, invalid fakeWTaddr attribute set (must not be 000000)" if (AttrVal($name,'fakeWTaddr','') eq '000000');

	    #Valid range for measured temperature is 0 - 51.1 degree
	    $args[2] = 0 if ($args[2] < 0); #Clamp temperature to minimum of 0 degree

	    # Encode into binary form
	    my $arg2 = int(10*$args[2]);
	    # First bit is 9th bit of temperature, rest is desiredTemperature
	    my $arg1 = (($arg2&0x100)>>1) | (int(2*ParseTemperature($args[1]))&0x7F);
	    $arg2 &= 0xFF; #only take the lower 8 bits

	    return Send($hash,
				'WallThermostatControl',
				$dest,
				sprintf('%02x%02x', $arg1, $arg2),
				groupId => sprintf('%02x', $groupid),
            			flags   => ( $groupid ? '04' : '00' ),
				src     => AttrVal($name, 'fakeWTaddr', '111111')
				);
	}
    }

   return "unknown argument $cmd, choose one of pairmode:60,300,600 broadcastTime:noArg deleteSendQueue:noArg fakeSC fakeWT sendTime";
}

sub Parse {

    # Attention: there is a limit in the culfw firmware: It only receives messages shorter than 30 bytes (see rf_moritz.h)
    # $hash is for the CUL instance
    my $hash = shift;
    my $rmsg = shift;
    my $name = $hash->{NAME};
 
    #return $name if (!$init_done); # brauchen wir das noch wenn alle Prototypen weg sind ?

    my $shash; #for the CUL_MAX instance

    # Find a CUL_MAX that has the CUL $hash as its IODev;
    # if no matching is found, just use the last encountered CUL_MAX.
    # change -> Implementierung des Highlander-Prinzips: Es kann nur Einen geben! D.h. Schaffung eindeutiger Zuständigkeiten

    foreach my $d (keys %defs) {
	if ($defs{$d}{TYPE} eq 'CUL_MAX') {
	    $shash = $defs{$d};
	    last; #if ($defs{$d}{IODev} == $hash);
	}
    }

    if (!defined($shash)) {
	Log3($name, 2, 'CM_Parse, no matching CUL_MAX device found');
	return $name; # if (!$ac);
    }

    my $sname = $shash->{NAME};
    my $debug = AttrNum($sname,'debug',0);

    if (length($rmsg) < 21) {
	Log3($sname, 4, "$sname, message $rmsg is to short !");
	readingsSingleUpdate($shash, 'short_message', $rmsg, 1) if ($debug);
	return $name;
    }

    my $len = hex(substr($rmsg,1,2));

    if (2*$len+3 != length($rmsg)) { #+3 = +1 for 'Z' and +2 for len field in hex
	Log3($sname, 4, "$sname, message $rmsg len mismatch ".length($rmsg).' vs '.(2*$len+3));
        readingsSingleUpdate($shash, 'mismatch_message', $rmsg, 1) if ($debug);
	return $name;
    }

    if ( $rmsg !~ m{\AZ[0-9A-F]{2,48}\z}xms ) { # repeptition safe margin, but not "infinite"
	Log3($sname, 4, "$sname, unknown message : $rmsg");
	if ($debug) {
	    readingsSingleUpdate($shash, 'unknown_message', $rmsg, 1);
	    my ($msgcnt, $flag, $msgTypeRaw, $src, $dst, $groupid, $payload) = unpack("(A2)3(A6)2A2A26", substr($rmsg,3));
	    $msgcnt     //= '??';
	    $flag       //= '??';
	    $msgTypeRaw //= '??';
	    $src        //= '??????';
	    $dst        //= '??????';
	    $groupid    //= '??';
	    $payload    //= '?';

	    Log3($sname, 4, "$sname, $flag $msgcnt $msgTypeRaw $src $dst $groupid $payload");
	}

        return $name;
    }

    my ($msgcnt, undef, $msgTypeRaw, $src, $dst, $groupid, $payload) = unpack("(A2)3(A6)2A2A26", substr($rmsg,3));

    $groupid = hex($groupid);

    readingsSingleUpdate($shash, 'state', get_CUL_States($shash), 1);

    #convert adresses to lower case
    $src     = lc($src);
    $dst     = lc($dst);

    my $src_name = 'MAX_'.$src;
    my $dst_name = 'MAX_'.$dst;
    my $src_type = 'UNKNOWN';
    my $dst_type = 'UNKNOWN';

    if (exists($modules{MAX}{defptr}{$src})) {
	if (!exists($modules{MAX}{defptr}{$src}->{NAME})) {
	    Log3($sname, 3, "$sname, source device $src has no name !") if (($src ne $shash->{addr}) && ($src ne '000000'));
	}
	else {
            Log3($sname, 3, "$sname, source device $src has a empty name !") if (!$modules{MAX}{defptr}{$src}->{NAME});
	    $src_name = $modules{MAX}{defptr}{$src}->{NAME} if ($modules{MAX}{defptr}{$src}->{NAME});
	}
	if (IsIgnored($src_name)) {
	    Log3($sname ,5 , "$sname, src $src_name has attribute ignore 1");
	    return $name;
	}
	$src_type = $modules{MAX}{defptr}{$src}{type} if ($modules{MAX}{defptr}{$src}{type});
    }

    if (exists($modules{MAX}{defptr}{$dst})) { 
	if (!exists($modules{MAX}{defptr}{$dst}->{NAME})) {
	    Log3($sname ,3, "$sname, target device $dst has no name !") if (($dst ne $shash->{addr}) && ($dst ne '000000'));
	}
	else {
	    Log3($sname, 3, "$sname, target device $dst has a empty name !") if (!$modules{MAX}{defptr}{$dst}->{NAME});
	    $dst_name = $modules{MAX}{defptr}{$dst}->{NAME} if ($modules{MAX}{defptr}{$dst}->{NAME});
	}
	$dst_name = 'Broadcast' if ($dst_name eq 'MAX_000000');
	$dst_type = $modules{MAX}{defptr}{$dst}{type} if ($modules{MAX}{defptr}{$dst}{type}); 
    }

    my $msgType = $msgId2Cmd{$msgTypeRaw};

    if (!$msgType) {
	Log3($sname, 2, "$sname, unhandled message type $msgTypeRaw from $src_name to $dst_name - ignoring !");
	return $name;
    }

    my @whitelist = split(',', lc(AttrVal($sname, 'whitelist', '')));
    my @blacklist = split(',', lc(AttrVal($sname, 'blacklist', '')));

    my $ignore_bl = 0; # erst alles erlauben
    my $ignore_wl = (@whitelist) ? 1 : 0;

    #if (@whitelist) {
	#if (@blacklist) {
	#    Log3($sname, 2, "$sname, whitelist and blacklist found. Blacklist ignoring !");
	#    @blacklist = ();
	#}
	foreach my $white_addr (@whitelist) {
	    $white_addr =~ s/ //g; 
	    $ignore_wl = 0 if (($white_addr eq $src) || ($white_addr eq $dst)); # das ist ein Guter
	    last if (!$ignore_wl);
	}
    #}

    #if (@blacklist) {
	foreach my $black_addr (@blacklist) {
	    $black_addr =~ s/ //g; 
	    $ignore_bl = 1 if (($black_addr eq $src) || ($black_addr eq $dst));
	    last if ($ignore_bl);
	}
    #}

    if ($ignore_wl || $ignore_bl) {
	my $txt = ($ignore_wl) ? 'not found on whitelist' : 'found on blacklist';
	Log3($sname, 3, "$sname, soure $src_type $src or destination $dst_type $dst $txt - ignoring !");
	return $name;
    }


    my $rssi = exists($hash->{RSSI}) ? $hash->{RSSI} : 0;

    Log3($sname, 5, "$sname, IODev $name, msgcnt $msgcnt, msgType $msgType, src $src $src_type, dst $dst $dst_type, group $groupid, payload $payload, rssi $rssi");
 
    my $isToMe;
    my $isMe;

    if (!$shash->{'.culids'}) { # keine verschieden IDs ! 
	$isToMe = ($dst eq $shash->{addr}) ? 1 : 0; # $isToMe is true if that packet was directed at us
	$dst_name = 'ToMe' if ($isToMe);
	$isMe   = ($src eq $shash->{addr}) ? 1 : 0;
    }
    else {
	$isToMe = (index($shash->{'.culids'}, $dst) != -1)  ? 1 : 0;
	$isMe   = (index($shash->{'.culids'}, $src) != -1)  ? 1 : 0;
	$dst_name = 'ToMe' if ($isToMe);
    }

    if ($isMe) { # is true if we received a packet from our second CUL
	Log3($sname, 4, "$sname, packet from ourselves ->  $src - ignoring !");
	return $name;
    }

    my $dummy  = AttrNum($src_name,'dummy',0);
    $isToMe    = 0 if ($dummy); # wir werten es aus, reagieren aber nicht darauf

    # Set RSSI , msgcount and destination on MAX device
    if (exists($modules{MAX}{defptr}{$src})) {
	$modules{MAX}{defptr}{$src}{'.rssi'}       = (exists($hash->{RSSI})) ? $hash->{RSSI} : 0 ;
	$modules{MAX}{defptr}{$src}{'.count'}      = hex($msgcnt)  if (abs($modules{MAX}{defptr}{$src}{'.count'}) != hex($msgcnt));
	$modules{MAX}{defptr}{$src}{'.sendToName'} = ($dst_name ne 'ToMe') ? $dst_name : '';
	$modules{MAX}{defptr}{$src}{'.sendToAddr'} = ($dst_name ne 'ToMe') ? $dst : '-1';
    }


    if ($msgType eq "Ack") {
	#Ignore packets generated by culfw's auto-Ack
	if ($isMe 
	   || ($src eq AttrVal($name, 'fakeWTaddr', '111111')) 
	   || ($src eq AttrVal($name, 'fakeSCaddr', '222222'))) {
		Log3($sname, 5, "$sname, auto ACK from $src - ignoring !");
		return $name;
        }

	Log3($sname, 1, "$sname, payload 00 from $src_type ($src_name) for $dst_type ($dst_name)") if ($isToMe && ($payload eq '00'));
	    
	    #else
    	    #{
    		##Dispatch($shash, "MAX,$isToMe,Ack,$src,$payload", {});
    	    #}

	if (!@{$shash->{sendQueue}}) {
	    if (!$dummy) {
		Log3($sname, 5, "$sname, ACK from $src_type $src_name but Send Queue is empty") if  ($isToMe);
		Log3($sname, 4, "$sname, ACK from $src_type $src_name to $dst_type $dst_name")  if (!$isToMe);
	    }
	    else {
		Log3($sname, 5, "$sname, ACK from dummy $src_type $src_name to $dst_type $dst_name");
	    }

	    Dispatch($shash, "MAX,$isToMe,Ack,$src,$payload", {});
	    return $name;
	}

	###################  check Send Queue ###############################
	my $quickremove = -1;
	for my $i (0 .. $#{$shash->{sendQueue}}) {
	    my $packet = $shash->{sendQueue}[$i];
	    if (($packet->{src} eq $dst) && ($packet->{dst} eq $src) && ($packet->{cnt} == hex($msgcnt))) {
		my $isnak = unpack("C",pack("H*",$payload)) & 0x80;
		$packet->{sent}  = $isnak ? 3 : 2;
		$packet->{iodev} = $hash->{NAME}; # ToDo : warum wird hier das iodev nachgezogen ?
		if (!$isnak) {
		    $quickremove = $i if ($packet->{cmd} eq 'PairPong'); # das muss nicht später noch durch MAX_Parse
		    Log3($sname, 5, "$sname, ACK from $src_type $src_name for cmd $packet->{cmd} , packet will be removed soon");
		}
		else {
		    Log3($sname, 4, "$sname, NACK from $src_type $src_name for cmd $packet->{cmd} !");
		}
	    }
	}

	if ($quickremove != -1) {
	    splice @{$shash->{sendQueue}}, $quickremove, 1; # Remove from Queue, hat kein callBack und muss nicht durch MAX !
	    Log3($sname, 5, "$sname, delete packet Index $quickremove in SendQueue direct !");
	}
	# Handle outgoing messages to that ShutterContact. It is only awake shortly
	# after sending an Ack to a PairPong
	# ToDo : das kann nicht sein, mit ELV Firmware schickt der Cube das AddLinkPartner
	# an den FK nachdem dieser sein letztes Status Telegramm an seine Peers geschickt hat !

	if ($src_type eq 'ShutterContact') {
	    Log3($sname, 3, "$sname, got ACK from ShutterContact $src_name , checking SendQueue now !");
	    SQH($shash, $src);
	}

	Dispatch($shash, "MAX,$isToMe,Ack,$src,$payload", {});
	return $name;
    } #$msgType eq "Ack"

    if ($msgType eq 'TimeInformation') {
	if ($isToMe) {
	    # This is a request for TimeInformation send to us
	    # Log3 $hash, 4, "CMA_Parse, got request for TimeInformation from $src_name";
	    # CUL_MAX_SendTimeInformation($shash, $src);

	    if (length($payload) > 0) {
		my ($f1,$f2,$f3,$f4,$f5) = unpack("CCCCC",pack("H*",$payload));
		# For all fields but the month I'm quite sure
		my $year = $f1 + 2000;
		my $day  = $f2;
		my $hour = ($f3 & 0x1F);
		my $min = $f4 & 0x3F;
		my $sec = $f5 & 0x3F;
		my $month = (($f4 >> 6) << 2) | ($f5 >> 6); # this is just guessed

		my $timestamp = timelocal($sec, $min, $hour, $day, $month - 1, $year - 1900);

		my $timeDiff = int(time()-$timestamp);
		if ($timeDiff > AttrNum($sname, 'broadcastTimeDiff', 5)) {
		    Log3($sname, 4, "$sname, TimeInformation from $src_type $src_name $timeDiff seconds out of sync. Sending correct Information! Received Timestamp (in GMT): $hour:$min:$sec $day.$month.$year");
		    SendTimeInformation($shash, $src);
		    #readingsSingleUpdate($defs{$src_name}, 'lastTimeSync', TimeNow(), 1);
                    $defs{$src_name}->{'lastTimeSync'} =  TimeNow();
		    readingsSingleUpdate($shash, 'lastTimeSync', $src_name, 1) if ($debug);
		    return;
		} 
		else {
		    Log3($sname, 4, "$sname, TimeInformation from $src_type $src_name to now is only $timeDiff seconds. - ignoring !");
		    return $name;
		}
	    } 
	    else {
		Log3($sname, 4, "$sname, TimeInformation-Request from $src_type $src_name without timestamp in payload. Sending back correct Timestamp");
		SendTimeInformation($shash, $src);
		#readingsSingleUpdate($defs{$src_name}, 'lastTimeSync', TimeNow(), 1);
                $defs{$src_name}->{'lastTimeSync'} =  TimeNow();
		readingsSingleUpdate($shash, 'lastTimeSync', $src_name, 1) if ($debug);
		return $name;
	    }
	} 
	elsif (length($payload) > 0) { # nicht direkt an uns, aber mit payload

	    my ($f1,$f2,$f3,$f4,$f5) = unpack("CCCCC",pack("H*",$payload));
	    # For all fields but the month I'm quite sure
	    my $year  = sprintf("%4d",$f1 + 2000);
	    my $day   = sprintf("%02d",$f2);
	    my $hour  = sprintf("%02d",($f3 & 0x1F));
	    my $min   = sprintf("%02d",$f4 & 0x3F);
	    my $sec   = sprintf("%02d",$f5 & 0x3F);
	    my $month = sprintf("%02d",(($f4 >> 6) << 2) | ($f5 >> 6)); #this is just guessed

	    my $u1 = ($f3 >> 5) * 100;
	    my $u2 = ($f4 >> 6) * 10;
	    my $u3 = $f5 >> 6;
	    # I guess the unk1,2,3 encode if we are in DST?
	    
	    Log3($sname, 4, "$sname, TimeInformation from $src_type $src_name to $dst_type $dst_name : $hour:$min:$sec $day.$month.$year , unknown:".($u1+$u2+$u3));
	    return $name;
	}
    } #$msgType eq "TimeInformation 

    if ($msgType eq 'PairPing') {
	my ($firmware,$type,$testresult,$serial) = unpack("CCCa*",pack("H*",$payload));
	# What does testresult mean?
	# ToDo : eine der Variablen kann undef sein bei zerstörten Telegrammen.

	$firmware //= '?';
	$type //= 99;
	$device_types{$type} //= 'strange';
	$testresult //= '';
	$serial //= '?';

	Log3($sname, 4, "$sname, PairPing (dst $dst, pairmode $shash->{pairmode}), firmware $firmware, type $device_types{$type}, testresult $testresult, serial $serial");

	# There are two variants of PairPing:
	# 1. It has a destination address of "000000" and can be paired to any device.
	#
	# 2. It is sent after changing batteries or repressing the pair button (without factory reset) and has a destination address of the last paired device. 
	# We can answer it with PairPong and even get an Ack, but it will still not be paired to us.
	# A factory reset (originating from the last paired device) is needed first.

	my $dhash = (exists($modules{MAX}{defptr}{$src})) ? $modules{MAX}{defptr}{$src} : '';

	# OK , das Gerät kennen wir schon. Reden wir überhaupt mit ihm ?
	if ($dhash && IsDummy($src_name)) {
	    Log3($name, 3 , "$sname, device $src_type $src_name want a ".($isToMe ? 'repairing' : 'pairing').' but it is already set to an dummy device - ignoring !');
	    return $name;
	}
	

	if (($dst ne '000000') && !$isToMe) {
	    readingsSingleUpdate($dhash, 'PairedTo', $dst, 1) if ($dhash);
	    Log3($sname, 3 , "$sname, device $src_type $src_name want to be re-paired to $dst_type $dst_name, not to us [ $shash->{addr} ] - ignoring !");
	    return $name;
	}

	# If $isToMe is true, this device is already paired and just wants to be reacknowledged
	# If we already have the device created but it was reseted (batteries changed?), we directly re-pair (without pairmode)

	if ($shash->{pairmode} || $isToMe || $dhash) {
	    Log3($sname, 3, "$sname, ".($isToMe ? 'Re-Pairing' : 'Pairing') . " device $src_name of type $device_types{$type} with serial $serial");
	    # save the groupid if the device has one
	    my $gid = ($dhash) ? ReadingsNum($src_name, 'groupid' ,0) :  0;
	    Dispatch($shash, "MAX,$isToMe,define,$src,$device_types{$type},$serial,$gid", {});
	    # Set firmware and testresult on device and if it is a new device we now have a valid dhash

	    $dhash = (exists($modules{MAX}{defptr}{$src})) ? $modules{MAX}{defptr}{$src} : '';

	    if ($dhash) {
		readingsBeginUpdate($dhash);
		readingsBulkUpdate($dhash, 'firmware',   sprintf('%u.%u',int($firmware/16),$firmware%16));
		readingsBulkUpdate($dhash, 'testresult', $testresult);
		readingsBulkUpdate($dhash, 'PairedTo',   $shash->{addr});
		readingsEndUpdate($dhash, 1);
	    }

	    # Send after dispatch the define, otherwise Send will create an invalid device
	    # ToDo : was ist hier genau gemeint ?
	    Send($shash, 'PairPong', $src, '00');

	    return $name if ($isToMe); # if just re-pairing, default values are not restored (I checked)

	    # This are the default values that a device has after factory reset or pairing
	    if ($device_types{$type} =~ m{\AHeatingThermostat}xms) {
	        Dispatch($shash, "MAX,$isToMe,HeatingThermostatConfig,$src,17,21,30.5,4.5,$defaultWeekProfile,80,5,0,12,15,100,0,0,12", {});
	    }

	    if ($device_types{$type} eq 'WallMountedThermostat') {
	        Dispatch($shash, "MAX,$isToMe,WallThermostatConfig,$src,17,21,30.5,4.5,$defaultWeekProfile,80,5,0,12", {});
	    }

	    return $name;
	} # pairmode , isToMe, exists
	
	Log3($sname, 2, "$sname, could not handle message Pair-Ping from device $src_name , please check Pairmode !");
	return $name;
    } # pair-ping

    if (   ($msgType eq 'ShutterContactState')
        || ($msgType eq 'WallThermostatState')
        || ($msgType eq 'WallThermostatControl')
        || ($msgType eq 'ThermostatState')
        || ($msgType eq 'PushButtonState')
        || ($msgType eq 'SetTemperature')) {
	    Dispatch($shash, "MAX,$isToMe,$msgType,$src,$payload", {}); # istome ?

	    # if (($msgType eq "ShutterContactState") && int($shash->{sq}) )# ToDo Test FK
	    #{
	    # noch prüfen : macht es einen Unterschied ob dispatch davor oder danach steht ?
	    #Log3 $shash, 3, $name.', '.$src_name.' is a ShutterContact, checking packet in SendQueue';
	    #CUL_MAX_SQH($shash, $src);
	    #}
	    #Dispatch($shash, "MAX,$isToMe,$msgType,$src,$payload", {}); # istome ?
	    return $name;
	} 

    Log3($sname, 3, "$sname, could not handle message $msgType from device $src_name to $dst_name - ignoring !");
    return $name;
}

#All inputs are hex strings, $cmd is one from %msgCmd2Id
sub Send {

    my ($hash, $cmd, $dst, $payload, %opts) = @_;
    my $name = $hash->{NAME};
    
    my $flags    = (exists($opts{flags}))    ? $opts{flags}    : '00';
    my $groupId  = (exists($opts{groupId}))  ? $opts{groupId}  : '00';
    my $src      = (exists($opts{src}))      ? $opts{src}      : $hash->{addr};

    my $src_name = (exists($modules{MAX}{defptr}{$src}) && exists($modules{MAX}{defptr}{$src}->{NAME})) ? $modules{MAX}{defptr}{$src}->{NAME} : 'MAX_'.$src;
    my $dst_name = (exists($modules{MAX}{defptr}{$dst}) && exists($modules{MAX}{defptr}{$dst}->{NAME})) ? $modules{MAX}{defptr}{$dst}->{NAME} : 'MAX_'.$dst;
    my $type     = (exists($modules{MAX}{defptr}{$dst}) && exists($modules{MAX}{defptr}{$dst}->{type})) ? $modules{MAX}{defptr}{$dst}->{type} : 'unknown';

    my $dhash;

    # Bei Brodcast Zielen ist es etwas anders
    if ($dst eq '000000') {
	$dst_name = 'Broadcast';
	$dhash    = (exists($modules{MAX}{defptr}{$src})) ? $modules{MAX}{defptr}{$src} : '';
    }
    else {
	$dhash = (exists($modules{MAX}{defptr}{$dst})) ? $modules{MAX}{defptr}{$dst} : '';
    }

    if (!$dhash) {
	Log3($name, 1 , "$name, could not find valid hash for src $src_name -> dst $dst_name, nothing will be send !");
	return;
    }

    # Fix : Use of uninitialized value $payload in concatenation (.) or string nach Device Factory Reset
    $payload //= '';
    $dhash->{READINGS}{msgcnt}{VAL} ++;
    $dhash->{READINGS}{msgcnt}{VAL} &= 0xFF;
    $dhash->{READINGS}{msgcnt}{TIME} = TimeNow();

    my $msgcnt = sprintf('%02x', $dhash->{READINGS}{msgcnt}{VAL});

    my $cul = AttrVal($dst_name, 'CULdev', 'none');

    my $packet = $msgcnt . $flags . $msgCmd2Id{$cmd} . $src . $dst . $groupId . $payload;

    Log3($name, 4, "$name, send -> cmd:$cmd, msgcnt:$msgcnt, flags:$flags, Cmd2id:$msgCmd2Id{$cmd}, src:$src_name , dst:$dst_name , gid:$groupId , payload:$payload , cul:$cul");

    # prefix length in bytes
    $packet = sprintf('%02x',length($packet)/2) . $packet;

    Log3($name, 5, "$name, send packet: $packet");
    my $timeout = gettimeofday()+$ackTimeout;

    my $l = '0';
    my $win = '-1';
    my @io = split(',', AttrVal($name, 'IOgrp', ''));

    #if ((@io > 1) && !$cul)
    #{
    #if ( exists($dhash->{$io[0]}) && exists($dhash->{$io[1]}))
    #{

	#if (  ($dhash->{$io[0].'_RAWMSG'} eq $dhash->{$io[1].'_RAWMSG'})
        #  && ($dhash->{$io[0].'_TIME'}   eq $dhash->{$io[1].'_TIME'}))
        #{
        # $l = '2' if ($dhash->{$io[0].'_RSSI'} < $dhash->{$io[1].'_RSSI'});
        #$l = '1' if ($dhash->{$io[0].'_RSSI'} > $dhash->{$io[1].'_RSSI'});
        #}

        #$win = $io[1] if $l == 2;
        #$win = $io[0] if $l == 1;

	#Log3 $hash, 4, "$name, last input win $l - $win";
	#Log3 $hash, 5, "$name, $dhash->{$io[0].'_RAWMSG'} |  $dhash->{$io[1].'_RAWMSG'}";
    #	}
    #	}
    my $aref = $hash->{sendQueue};
    push(@{$aref},{       'packet' => $packet,
                            'src' => $src,
                            'dst' => $dst,
                            'cnt' => hex($msgcnt),
                           'time' => $timeout,
                           'sent' => '0',
                            'cmd' => $cmd,
                            'win' => $win,
                            'CUL' => $cul,
                       'src_name' => $src_name,
                       'dst_name' => $dst_name,
                  'callbackParam' => (exists($opts{callbackParam}) ? $opts{callbackParam} : ''),
                          'type'  => $type,
                  });

    # Call CUL_MAX_SendQueueHandler if we just enqueued the only packet
    # otherwise it is already in the InternalTimer list

    $hash->{sq} = int(@{$hash->{sendQueue}});
    SQH($hash) if (int(@{$hash->{sendQueue}}) == 1);
    return;
}


sub SendTimeInformation {

    my $hash    = shift;
    my $addr    = shift;
    my $payload = shift // GetTimeInformationPayload();

    Log3($hash, 5, "$hash->{NAME}, Broadcast time to $addr");
    Send($hash, 'TimeInformation', $addr, $payload, flags => '04');
    return;
}

sub BroadcastTime {

    my $hash       = shift;
    my $manual     = shift // 0;
    #   $manual     //= 0;
    my $name       = $hash->{NAME};
    my $payload    = GetTimeInformationPayload();
    my @used_slots = ( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 );
    my @devs;

    Log3($name, 5, "$name, BroadcastTime payload : $payload");

    # First, lookup all thermstats for their current TimeInformationHour timeslot (0-11)
    # Check that
    # 1. the MAX device dhash uses this MAX_CUL as IODev
    # 2. the MAX device is a Wall/HeatingThermostat
    # 3. not ignored or a dummy

    foreach my $addr (keys %{$modules{MAX}{defptr}}) {
	my $dhash = $modules{MAX}{defptr}{$addr};
	next if (!exists($dhash->{IODev}{NAME}));
	next if ($dhash->{IODev}{NAME} ne $name);
	if (exists($dhash->{IODev})
	   && defined($dhash->{IODev}) 
	   && ($dhash->{IODev} == $hash)
	   && ($dhash->{type} =~ m{Thermostat}xms)
	   && ($dhash->{devtype} != 7)
	   && !IsIgnored($dhash->{NAME})
	   && !IsDummy($dhash->{NAME})) {

	    my $h = InternalVal($dhash->{NAME}, 'TimeSlot', '-1');
	    $used_slots[$h]++ if (( $h < 12 ) && ( $h > -1));
	    push @devs , $dhash;
	}
    }

    foreach my $dhash (@devs) {
	# Check that
	# 1. the MAX device dhash uses this MAX_CUL as IODev
	# 2. the MAX device is a Wall/HeatingThermostat
	# 3. not ignored or a dummy

	my $h = InternalVal($dhash->{NAME}, 'TimeSlot', '-1');
	if (( $h < 0 ) || ( $h > 11)) {
	    # Find the used_slot with the smallest number of entries
	    $h = (sort { $used_slots[$a] cmp $used_slots[$b] } 0 .. 11)[0];
	    $dhash->{TimeSlot} = $h;
	    Log3($name, 4, "$name, new timeslot $h for device $dhash->{NAME}");
	    $used_slots[$h]++;
	}

	if ( [gmtime()]->[2] % 12 == $h ) {
	    SendTimeInformation($hash, $dhash->{addr}, $payload);
	    #readingsSingleUpdate($dhash, 'lastTimeSync', TimeNow(), 1);
            $dhash->{'lastTimeSync'} =  TimeNow();
	    readingsSingleUpdate($hash, 'lastTimeSync', $dhash->{NAME}, 1) if (AttrNum($name,'debug',0));
	    Log3($name, 4, "$name, periodical TimeInformation sent to $dhash->{NAME}");
	}
    }

    # Check again in 1 hour if some thermostats with the right TimeInformationHour need updating
    InternalTimer(gettimeofday() + 3600, 'FHEM::CUL_MAX::BroadcastTime', $hash, 0) if (!$manual);
    return;
}

sub Alive {

    my $hash = shift;

    foreach my $device (keys %{$modules{MAX}{defptr}}) {
	my $dhash = $modules{MAX}{defptr}{$device};

	if (exists($dhash->{IODev}) && ($dhash->{IODev} == $hash) && exists($dhash->{'.actCycle'})) {
    	    my $ac   = InternalVal($dhash->{NAME}, '.actCycle', '0');
    	    my $diff = int(time() - ReadingsNum($dhash->{NAME}, '.lastact', 0));

    	    if ($ac && ($diff > $ac)) {
    	        readingsSingleUpdate($dhash,'Activity', ($diff > ($ac*3)) ? 'dead' : 'timeout',1);
    	    }
	}
    }

    InternalTimer(gettimeofday() + 300, 'FHEM::CUL_MAX::Alive',$hash,0);
    return;
}

sub GetTimeInformationPayload {

    my ($sec,$min,$hour,$day,$mon,$year,$wday,$yday,$isdst) = localtime(time());
    $mon += 1; #make month 1-based
    #month encoding is just guessed
    #perls localtime gives years since 1900, and we need years since 2000
    return unpack("H*",pack("CCCCC", $year - 100, $day, $hour, $min | (($mon & 0x0C) << 4), $sec | (($mon & 0x03) << 6)));
}

# This can be called for two reasons:
# 1. @sendQueue was empty, CUL_MAX_Send added a packet and then called us
# 2. We sent a packet from @sendQueue and now the ackTimeout is over.
#   The packet my still be in @sendQueue (timed out) or removed when the Ack was received.
# Arguments are hash and responseToShutterContact.
# If SendQueueHandler was called after receiving a message from a shutter contact, responseToShutterContact
# holds the address of the respective shutter contact. Otherwise, it is empty.

sub SQH {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $responseToShutterContact = shift // 0;

    $hash->{sq} = int(@{$hash->{sendQueue}});

    my $txt = "$name, Send Queue : $hash->{sq} ". (($hash->{sq} == 1) ? 'packet' : 'packets') .' are in the queue';
    $txt .= " , rTSC : $responseToShutterContact" if ($responseToShutterContact);

    Log3($name, 5, $txt);

    return if (!$hash->{sq}); # nothing to do

    my $timeout = gettimeofday(); # reschedule immediatly

    # Check if we have an IODev
    if (!defined($hash->{IODev})) {
	Log3($name, 1, "$name, did not find suitable IODev (CUL etc. in rfmode MAX), cannot send! You may want to execute 'attr $hash->{NAME} IODev SomeCUL'");
	# Maybe some CUL will appear magically in some seconds
	# At least we cannot quit here with an non-empty queue, so we have two alternatives:
	# 1. Delete the packet from queue and quit -> packet is lost
	# 2. Wait, recheck, wait, recheck ... -> a lot of logs

	#InternalTimer($timeout+60, "CUL_MAX_SendQueueHandler", $hash, 0);
	$hash->{sendQueue} = [];
	$hash->{sq} = 0;
	return;
    }
 
    my $debug = AttrNum($name,'debug',0);

    my ($packet, $pktIdx, $dst);

    for ($pktIdx = 0; $pktIdx < @{$hash->{sendQueue}}; $pktIdx ++) {
	$packet = $hash->{sendQueue}[$pktIdx];

	if ($responseToShutterContact) {
    	    # Find a packet to the ShutterContact in $responseToShutterContact
    	    # Aufruf Sonderfall
    	    last if ($packet->{dst} eq $responseToShutterContact);
	} 
	else {
	    #We cannot sent packets to a ShutterContact directly, everything else is possible
	    last if (($packet->{cmd} eq 'PairPong')
		    || ($packet->{sent} != 0)
		    || ($packet->{type} ne 'ShutterContact'));
    	    #$packetForShutterContactInQueue = $modules{MAX}{defptr}{$packet->{dst_name}};
	}
    }

    if ($pktIdx == @{$hash->{sendQueue}} && !$responseToShutterContact) {
	Log3($name, 4, "$name, Send Queue packet for ShutterContact $packet->{dst_name} exists");
	#. Please trigger a window action (open or close the window) to wake up the respective ShutterContact and let it receive the packet.";
	$timeout += 3;
	InternalTimer($timeout, 'FHEM::CUL_MAX::SQH', $hash, 0);
	#Log3 $hash, 5, $name.', Send Queue in not empty yet, next run in '.sprintf("%.1f",($timeout-gettimeofday())).' seconds';
	# ToDo : checken wir hier immer nur auf das letzte Packet in der Queue ?
	return;
    }

    if ( $packet->{sent} == 0 ) {
	my $io_name = $hash->{IODev}{NAME};

	if (($packet->{CUL} ne 'none') && ($packet->{CUL} ne $io_name) && AttrVal($name, 'IOgrp', '')) {
    	    Log3($name, 4, "$name, Send Queue packet to $packet->{dst_name} needs $packet->{CUL} but current IODev is $io_name");
    	    AssignIoPort($hash, $packet->{CUL}); # falls das schief geht nehmen wir halt das attr IODev
    	    if ($io_name ne $hash->{IODev}{NAME}) {
    		$io_name = $hash->{IODev}{NAME};
    		$hash->{'.VERSION'} = Check($hash);
    		Log3($name, 4, "$name, Send Queue IODev switched to $io_name with version $hash->{'.VERSION'}");
    	    }
    	    else { 
		Log3($name, 3, "$name, Send Queue unable to change IODev !");
	    }
	}


	# Need to send it first
	# We can use fast sending without preamble on culfw 1.53 and higher when the devices has been woken up
	my $needPreamble = (($hash->{'.VERSION'} < 153)
    			    || (!$responseToShutterContact
			    && (!defined($modules{MAX}{defptr}{$packet->{dst}}{wakeUpUntil})
        		    || $modules{MAX}{defptr}{$packet->{dst}}{wakeUpUntil} < gettimeofday()))) ? 1 : 0;

	#my $needPreamble = ($hash->{'.VERSION'} < 153) ? 1 : 0;

	$needPreamble = 1;
	# Send to CULs

	my $last_h  = (exists($hash->{IODev}{NR_CMD_LAST_H})) ? $hash->{IODev}{NR_CMD_LAST_H} : 0;
	readingsSingleUpdate($hash,$io_name.'_cmd_last_h',int($last_h),1) if ($debug);

	#my ($credit10ms) = (CommandGet('',$io_name.' credit10ms') =~ /[^ ]* [^ ]* => (.*)/);
	my ($answer,$val) = split(' => ', CommandGet(undef, "$io_name credit10ms"));

	if (!defined($val) || ($answer eq 'No answer')) {
    	    Log3($hash, 1, "$name, Send Queue error CUL $io_name did not answer request for current credits. Waiting 5 seconds");
    	    $timeout += 5;
	    $val = 0;
	} 
	else {
	    $val = int($val);
	    readingsSingleUpdate($hash, $io_name.'_credit10ms', $val, 1) if ($debug);
	    # We need 1000ms for preamble + len in bits (=hex len * 4) ms for payload. Divide by 10 to get credit10ms units
	    # keep this in sync with culfw's code in clib/rf_moritz.c!
	    my $necessaryCredit = ceil(100*$needPreamble + (length($packet->{packet})*4)/10);
	    Log3($name, 5, "$name, Send Queue $io_name -> needPreamble: $needPreamble, necessaryCredit: $necessaryCredit, credit10ms: $io_name = $val, CMD_LAST_H: $last_h");

	    if ($val < $necessaryCredit) {
		my $waitTime = $necessaryCredit-$val; # we get one credit10ms every second
		$timeout += $waitTime + 1;
		Log3($name, 2, "$name, $io_name not enough credit! credit10ms is $val, but we need $necessaryCredit. Waiting $waitTime seconds. Currently ".@{$hash->{sendQueue}}.' messages are waiting to be sent');
	    } 
	    else {
		# Update TimeInformation payload. It should reflect the current time when sending,
		# not the time when it was enqueued. A low credit10ms can defer such a packet for multiple minutes
		if ( $msgId2Cmd{substr($packet->{packet}, 6, 2)} eq 'TimeInformation' ) {
		    Log3($name, 5, "$name, Send Queue updating packet TimeInformation payload");
		    substr($packet->{packet},22) = GetTimeInformationPayload();
		    #substr($packet->{packet}, 22, 10, GetTimeInformationPayload());
		}

		IOWrite($hash, '', ($needPreamble ? 'Zs' : 'Zf') . $packet->{packet});
		Log3($name, 4, "$name, Send Queue packet send : ".($needPreamble ? 'Zs' : 'Zf')."$packet->{packet} to $packet->{dst_name} with $io_name");

		readingsSingleUpdate($hash, 'state', get_CUL_States($hash), 1);

		# Broadcast Nachricht sofort wieder löschen, wir bekommen nie ein ACK
		splice @{$hash->{sendQueue}}, $pktIdx, 1 if ($packet->{dst} eq '000000'); # Remove from Queue

		if ($packet->{dst} ne '000000') {
		    $packet->{sent} = 1;
		    $packet->{sentTime} = gettimeofday();
		    $packet->{retryCnt} = $maxRetryCnt if (!defined($packet->{retryCnt}));
		    $timeout += 0.5; # recheck for Ack in 0.5 seconds
		}
	    }
	} # $credit10ms ne "No answer"
    } # paket send == 0 

    if ( $packet->{sent} == 1 ) { # Already sent it, got no Ack
	if ( $packet->{sentTime} + $ackTimeout < gettimeofday() ) {
	    # ackTimeout exceeded
	    if ( $packet->{retryCnt} > 0 ) {
		Log3($name, 4, "$name, Send Queue retry $packet->{dst_name} for $packet->{cmd} count: $packet->{retryCnt}");
		$packet->{sent} = 0;
		$packet->{retryCnt}--;
		$timeout += 3;
		if ($debug) {
		    readingsSingleUpdate($hash, $packet->{CUL}.'_retry', (ReadingsNum($name, $packet->{CUL}.'_retry', '0') + 1),1);
		    readingsSingleUpdate($defs{$packet->{dst_name}}, $packet->{CUL}.'_retry', (ReadingsNum($packet->{dst_name}, $packet->{CUL}.'_retry', '0') + 1),1);
		}
	    }
	    else {
		Log3($name, 3, "$name, Send Queue missing ack from $packet->{dst_name} for $packet->{cmd}, removing from queue");
		splice @{$hash->{sendQueue}}, $pktIdx, 1; # Remove from Queue
		if ($debug) {
		    readingsSingleUpdate($hash, $packet->{CUL}.'_lost', (ReadingsNum($name, $packet->{CUL}.'_lost', '0') + 1),1);
		    readingsSingleUpdate($defs{$packet->{dst_name}}, $packet->{CUL}.'_lost', (ReadingsNum($packet->{dst_name}, $packet->{CUL}.'_lost', '0') + 1),1);
		}
	    }
	}
	else {
	    # Recheck for Ack
	    $timeout += 0.5;
	}
    }

    if ( $packet->{sent} == 2 ) { # Got ack
	Log3($name, 4, "$name, Send Queue ACK from $packet->{dst_name} for $packet->{cmd}, removing from queue");
	splice @{$hash->{sendQueue}}, $pktIdx, 1; # Remove from Queue

	if ($packet->{callbackParam}) {
	    my $para = "Ack$packet->{cmd},$packet->{dst},$packet->{callbackParam}";
	    Log3($name , 4 ,"$name, Send Queue packet has callback, call dispatch : $para");
	    Dispatch($hash, "MAX,1,$para", {});
	}
    }

    if ( $packet->{sent} == 3 ) { # Got nack
	Log3($name, 4, "$name, Send Queue NACK from $packet->{dst_name} for $packet->{cmd}, removing from queue");
	splice @{$hash->{sendQueue}}, $pktIdx, 1; # Remove from Queue
	readingsSingleUpdate($hash, $packet->{CUL}.'_nack', (ReadingsNum($name, $packet->{CUL}.'_nack', '0') + 1),1) if ($debug);
	readingsSingleUpdate($defs{$packet->{dst_name}}, $packet->{CUL}.'_nack', (ReadingsNum($packet->{dst_name}, $packet->{CUL}.'_nack', '0') + 1),1) if ($debug);
    }

    $hash->{sq} = int(@{$hash->{sendQueue}});

    if (!$hash->{sq}) {
	Log3($name, 5, "$name, Send Queue is now empty");
	return; # everything done , empty sendQueue 
    }

    InternalTimer($timeout, 'FHEM::CUL_MAX::SQH', $hash, 0) if (!$responseToShutterContact); # this was not called from InternalTimer;
    return;
}

sub get_CUL_States {

    my $hash = shift;
    my $ret  = '';
    my $iodev;
    my $state = sub {return (ReadingsVal(shift, 'state', '???') eq 'Initialized') ? 'ok' : 'UAS'};

    $iodev = $hash->{IODev}{NAME} if(exists($hash->{IODev}{NAME}));
    $ret = $iodev.':'.&$state($iodev) if ($iodev);

    if (exists($hash->{IOgrp})) {
	foreach my $cul (split(',' , $hash->{IOgrp})) {
	    next if (!$cul || ($cul eq $iodev));
	    $ret .= ',' if ($ret);
	    $ret .= "$cul:".&$state($cul);
	}
	$ret .= " Last:$hash->{LASTInputDev}" if (exists($hash->{LASTInputDev}) && $hash->{LASTInputDev});
    }

    return ($ret) ? $ret : '???';
}

sub RenameFn {

    my $new = shift;
    my $old = shift;
    for my $d (devspec2array('TYPE=MAX')) {
	my $hash = $defs{$d};
	next if (!$hash);
	#$hash->{DEF} =~ s/^$old:/$new:/;
	$attr{$d}{IODev} = $new if (AttrVal($d, 'IODev', '') eq $old);
    }
    #MAX_renameIoDev($new, $old);
    return;
}

1;

__END__

=pod

=encoding utf8

=begin html

<a name="CUL_MAX"></a>
<h3>CUL_MAX</h3>
<ul>
  The CUL_MAX module interprets MAX! messages received by the CUL. It will be automatically created by autocreate, just make sure
  that you set the right rfmode like <code>attr CUL0 rfmode MAX</code>.<br>
  <br><br>

  <a name="CUL_MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_MAX &lt;addr&gt;</code>
      <br><br>

      Defines an CUL_MAX device of type &lt;type&gt; and rf address &lt;addr&gt. The rf address
      must not be in use by any other MAX device.
  </ul>
  <br>

  <a name="CUL_MAXset"></a>
  <b>Set</b>
  <ul>
      <li>pairmode<br>
      Sets the CUL_MAX into pairing mode for 60 seconds where it can be paired with 
      other devices (Thermostats, Buttons, etc.). You also have to set the other device 
      into pairing mode manually. (For Thermostats, this is pressing the "Boost" button 
      for 3 seconds, for example).</li>
      <li>fakeSC &lt;device&gt; &lt;open&gt;<br>
      Sends a fake ShutterContactState message &lt;open&gt; must be 0 or 1 for 
      "window closed" or "window opened". If the &lt;device&gt; has a non-zero groupId, 
      the fake ShutterContactState message affects all devices with that groupId. 
      Make sure you associate the target device(s) with fakeShutterContact beforehand.</li>
      <li>fakeWT &lt;device&gt; &lt;desiredTemperature&gt; &lt;measuredTemperature&gt;<br>
      Sends a fake WallThermostatControl message (parameters both may have one digit 
      after the decimal point, for desiredTemperature it may only by 0 or 5). 
      If the &lt;device&gt; has a non-zero groupId, the fake WallThermostatControl 
      message affects all devices with that groupId. Make sure you associate the target 
      device with fakeWallThermostat beforehand.</li>
  </ul>
  <br>

  <a name="CUL_MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li><br>
    <li><a href="#debug">debug</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="CUL_MAXevents"></a>
  <b>Generated events:</b>
  <ul>N/A</ul>
  <br>

</ul>
=end html
=device
=item summary Uses a CUL (or compatible) to control MAX! devices.
=item summary_DE Benutzt einen CUL (oder kompatibles Gerät) um MAX! Geräte zu steuern.
=begin html_DE

<a name="CUL_MAX"></a>
<h3>CUL_MAX</h3>
<ul>
  Das Modul CUL_MAX wertet von einem CUL empfangene MAX! Botschaften aus.
  Es wird mit Hilfe von autocreate automatisch generiert, es muss nur sichergestellt 
  werden, dass der richtige rfmode gesetzt wird, z.B. <code>attr CUL0 rfmode MAX</code>.<br>
  <br>

  <a name="CUL_MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_MAX &lt;addr&gt;</code>
      <br><br>

      Definiert ein CUL_MAX Ger&auml;t des Typs &lt;type&gt; und der Adresse &lt;addr&gt.
      Die Adresse darf nicht schon von einem anderen MAX! Ger&auml;t verwendet werden.
  </ul>
  <br>

  <a name="CUL_MAXset"></a>
  <b>Set</b>
  <ul>
      <li>pairmode<br>
      Versetzt den CUL_MAX f&uuml;r 60 Sekunden in den Pairing Modus, w&auml;hrend dieser Zeit
      kann das Ger&auml;t mit anderen Ger&auml;ten gepaart werden (Heizk&ouml;rperthermostate, 
      Eco-Taster, etc.). Auch das zu paarende Ger&auml;t muss manuell in den Pairing Modus 
      versetzt werden (z.B. beim Heizk&ouml;rperthermostat durch Dr&uuml;cken der "Boost" 
      Taste f&uuml;r 3 Sekunden).</li>
      <li>fakeSC &lt;device&gt; &lt;open&gt;<br>
      Sendet eine fingierte <i>ShutterContactState</i> Meldung &lt;open&gt;, dies muss 0 bzw. 1 f&uuml;r
      "Fenster geschlossen" bzw. "Fenster offen" sein. Wenn das &lt;device&gt; eine Gruppen-ID
      ungleich Null hat, beeinflusst diese fingierte <i>ShutterContactState</i> Meldung alle Ger&auml;te
      mit dieser Gruppen-ID. Es muss sichergestellt werden, dass vorher alle Zielger&auml;te 
      mit <i>fakeShutterContact</i> verbunden werden.</li>
      <li>fakeWT &lt;device&gt; &lt;desiredTemperature&gt; &lt;measuredTemperature&gt;<br>
      Sendet eine fingierte <i>WallThermostatControl</i> Meldung (beide Parameter k&ouml;nnen
      eine Nachkommastelle haben, f&uuml;r <i>desiredTemperature</i> darf die Nachkommastelle nur 0 bzw. 5 sein).
      Wenn das &lt;device&gt; eine Gruppen-ID ungleich Null hat, beeinflusst diese fingierte 
      <i>WallThermostatControl</i> Meldung alle Ger&auml;te mit dieser Gruppen-ID.
      Es muss sichergestellt werden, dass vorher alle Zielger&auml;te 
      mit <i>fakeWallThermostat</i> verbunden werden.</li>
  </ul>
  <br>

  <a name="CUL_MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li><br>
    <li><a href="#debug">debug</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
  <a name="CUL_MAXevents"></a>
  <b>Events</b>
  <ul>N/A</ul>
  <br>

</ul>

=end html_DE

=for :application/json;q=META.json 14_CUL_MAX.pm

{
  "abstract": "controls a MAX! device",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Steuerung von MAX! Geraeten"
    }
  },
  "keywords": [ "MAX","CUL" ],
  "version": "0",
  "release_status": "stable",
  "author": [ "Wzut" ],
  "x_fhem_maintainer": [ "Wzut" ],
  "x_fhem_maintainer_github": [ ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "GPUtils": 0,
        "Time::HiRes": 0,
        "Time::Local": 0
     },
      "recommends": { "FHEM::Meta": 0, "Data::Dumper": 0 }
    }
  }
}
=end :application/json;q=META.json

=cut
