################################################################
#
#  $Id$
#
#  (c) 2019 Copyright: Wzut
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/topic,80703.msg891666.html#msg891666
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

# based on Broadlink Python script at https://github.com/ralphm2004/broadlink-thermostat
# Broadlink protocol parts are stolen from 38_Broadlink.pm :) , THX to daniel2311

package FHEM::BEOK;  ## no critic 'package'
# das no critic könnte weg wenn die Module nicht mehr zwingend mit NN_ beginnnen müssen

use strict;
use warnings;
use utf8;
use GPUtils qw(GP_Import GP_Export); # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::Local;
use IO::Socket::INET;
use IO::Select;
use MIME::Base64;
use SetExtensions;
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call

BEGIN
{
    # Import from main::
    GP_Import(
	qw(
	attr
	AttrVal
	AttrNum
	BlockingCall
	defs
	CommandAttr
	CommandGet
	CommandSet
	init_done
	InternalTimer
	RemoveInternalTimer
	IsDisabled
	Log3
	readingsSingleUpdate
	readingsBulkUpdate
	readingsBeginUpdate
	readingsEndUpdate
	ReadingsNum
	ReadingsVal
	readingFnAttributes
	SetExtensions
	gettimeofday
	FW_CSRF
	FW_dev2image
	FW_makeImage
	)
    );

    # Export to main
    GP_Export( qw(Initialize) );
}

my $hasmeta = 0;
# ältere Installationen haben noch kein Meta.pm
if (-e $attr{global}{modpath}.'/FHEM/Meta.pm') {
    $hasmeta = 1;
    require FHEM::Meta;
}

sub Initialize
{
    my $hash = shift;

    $hash->{DefFn}        = \&FHEM::BEOK::Define;
    $hash->{UndefFn}      = \&FHEM::BEOK::Undef;
    $hash->{ShutdownFn}   = \&FHEM::BEOK::Undef;
    $hash->{SetFn}        = \&FHEM::BEOK::Set;
    $hash->{GetFn}        = \&FHEM::BEOK::Get;
    $hash->{AttrFn}       = \&FHEM::BEOK::Attr;
    $hash->{FW_summaryFn} = \&FHEM::BEOK::summaryFn;
    $hash->{AttrList}     = 'interval timeout disable:0,1 timesync:0,1 language display:auto,always_on keepAuto:0,1 '
                            .'skipTimeouts:0,9 maxErrorLog model:BEOK,Floureon,Hysen,KETOTEK,Chunyang,unknown weekprofile '
                            .$readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash ) if ($hasmeta);
    return;
}

sub Define {
    my $hash = shift;
    my $def  = shift;
    my ($name, undef, $ip , $mac) = split(m{ \s+ }xms, $def, 4);

    return "wrong syntax: define <name> BEOK <ip> [<mac>]" if (!$ip);

    $mac //= 'de:ad:be:ef:08:15';

    eval {
	require Crypt::CBC;
	1;
    }
    or do {
	return 'please install Crypt::CBC first';
    };

    eval {
	require Crypt::OpenSSL::AES;
	1;
    }
    or do {
	return 'please install Crypt::OpenSSL::AES first';
    };

    $hash->{'.ip'} = $ip;
    $hash->{'MAC'} = $mac; # immer noch unklar ob die echte MAC nötig ist oder nicht

    $hash->{'.key'} = pack('C*', 0x09, 0x76, 0x28, 0x34, 0x3f, 0xe9, 0x9e, 0x23, 0x76, 0x5c, 0x15, 0x13, 0xac, 0xcf, 0x8b, 0x02);
    $hash->{'.iv'}  = pack('C*', 0x56, 0x2e, 0x17, 0x99, 0x6d, 0x09, 0x3d, 0x28, 0xdd, 0xb3, 0xba, 0x69, 0x5a, 0x2e, 0x6f, 0x58);
    $hash->{'.id'}  = pack('C*', 0, 0, 0, 0);

    $hash->{'counter'}   = 1;
    $hash->{'isAuth'}    = 0;
    $hash->{'lastCMD'}   = '';
    $hash->{TIME}        = time();
    $hash->{ERRORCOUNT}  = 0;
    $hash->{weekprofile} = 'none';
    $hash->{'skipError'} = 0;
    $hash->{SVN}         = (qw($Id$))[2];

    # wird mit dem ersten Full Status überschrieben
    $hash->{helper}{temp_manual} = 0;
    $hash->{helper}{power}       = 0;
    $hash->{helper}{remote_lock} = 0;
    $hash->{helper}{loop_mode}   = 1;
    $hash->{helper}{SEN}         = 0;
    $hash->{helper}{OSV}         = 0;
    $hash->{helper}{dIF}         = 0;
    $hash->{helper}{SVH}         = 0;
    $hash->{helper}{SVL}         = 0;
    $hash->{helper}{AdJ}         = 0;
    $hash->{helper}{FrE}         = 0;
    $hash->{helper}{PoM}         = 0;
    $hash->{helper}{0}{temp}     = 10;
    $hash->{helper}{0}{time}     = '05:00';
    $hash->{helper}{1}{temp}     = 15;
    $hash->{helper}{1}{time}     = '08:00';
    $hash->{helper}{2}{temp}     = 20;
    $hash->{helper}{2}{time}     = '11:00';
    $hash->{helper}{3}{temp}     = 25;
    $hash->{helper}{3}{time}     = '12:00';
    $hash->{helper}{4}{temp}     = 30;
    $hash->{helper}{4}{time}     = '17:00';
    $hash->{helper}{5}{temp}     = 35;
    $hash->{helper}{5}{time}     = '22:00';
    $hash->{helper}{6}{temp}     = 40;
    $hash->{helper}{6}{time}     = '08:00';
    $hash->{helper}{7}{temp}     = 45;
    $hash->{helper}{7}{time}     = '23:00';

    CommandAttr(undef, $name.' devStateIcon on:on off:off close:secur_locked open:secur_open hon:on hoff:off') if (!exists($attr{$name}{devStateIcon}));
    CommandAttr(undef, $name.' interval 60')   if (!exists($attr{$name}{interval}));
    CommandAttr(undef, $name.' timeout 5')     if (!exists($attr{$name}{timeout}));
    CommandAttr(undef, $name.' timesync 1')    if (!exists($attr{$name}{timesync}));
    CommandAttr(undef, $name.' model unknown') if (!exists($attr{$name}{model}));

    readingsSingleUpdate($hash, 'state',' defined', 1);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, 'FHEM::BEOK::OnTimer', $hash, 0);

    return $@ if ($hasmeta && !FHEM::Meta::SetInternals($hash));
    return;
}

sub Undef {
    my $hash = shift;
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
    return;
}

sub OnTimer {
    my $hash = shift;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);

    my $interval      = AttrNum($name, 'interval', 60);
    my $wp            = AttrVal($name, 'weekprofile', '');
    $hash->{INTERVAL} = $interval;
    $hash->{MODEL}    = AttrVal($name, 'model', 'unknown');

    return if (!$interval);

    InternalTimer(gettimeofday()+int($interval), 'FHEM::BEOK::OnTimer', $hash, 0);

    return if (!$init_done || IsDisabled($name));

    readingsSingleUpdate($hash, 'alive', 'no',1) if ((time()-($interval*5)) > $hash->{TIME});

    if (!$hash->{isAuth}) {
	CommandGet(undef, "$name auth");
	return;
    }

    if (!$wp) {
        if ((AttrVal($name, 'display', 'auto') eq 'auto') && ($hash->{isAuth})) {
		CommandGet(undef, "$name status");
		return;
        }
        CommandSet(undef, "$name on") if  ($hash->{isAuth}); # Display immer an
        return;
    }

    my $now_day  = (localtime(time()))[6];  # jetzt
    my $last_day = (localtime($hash->{TIME}))[6]; # letzter Lauf
    my $next_day = (localtime(time()+$interval))[6]; # nächster Lauf

    # letzter Lauf für heute ?
    if ($now_day != $next_day && AttrNum($name, 'keepAuto', 0) && !$hash->{helper}{auto_mode}) {
	$hash->{'.lastdayrun'} = 0;
	my $error = CommandSet(undef, "$name mode auto");
	if ($error) {
	    Log3($name, 3, "$name, $error");
	    $hash->{TIME} = time();
	}
	return;
    }
    #neuer Tag ?
    elsif ($now_day != $last_day) {
	Log3($name, 4, "$name, firstday run");
	$hash->{'.firstdayrun'} = 1;
	my $error = CommandSet(undef, "name weekprofile $wp");
	if ($error) {
	    Log3($name, 3, "$name, $error");
	    $hash->{TIME} = time(); # sonst Endlos Schleife wenn weekprofile nicht gesetzt werden kann !
	}
	return; # neuer status kommt via set weekprofile
    }
    else { 
	$hash->{'.firstdayrun'} = 0;
	$hash->{'.lastdayrun'}  = 0;
	if ((AttrVal($name, 'display', 'auto') eq 'auto') && ($hash->{isAuth})) {
	    CommandGet(undef, "$name status");
	    return;
	}
	CommandSet(undef, "$name on") if  ($hash->{isAuth}); # Display immer an
    }
    return;
}


sub Get {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "get $name needs at least one argument !";
    my $gets = 'status:noArg  auth:noArg temperature:noArg';

    return "unknown command, choose one of $gets" if ($cmd eq '?');

    if ($cmd eq 'auth') {
	return 'device auth key already stored' if ($hash->{isAuth});

	my @payload = ((0x00) x 80);
	$payload[0x04] = 0x31;
	$payload[0x05] = 0x31;
	$payload[0x06] = 0x31;
	$payload[0x07] = 0x31;
	$payload[0x08] = 0x31;
	$payload[0x09] = 0x31;
	$payload[0x0a] = 0x31;
	$payload[0x0b] = 0x31;
	$payload[0x0c] = 0x31;
	$payload[0x0d] = 0x31;
	$payload[0x0e] = 0x31;
	$payload[0x0f] = 0x31;
	$payload[0x10] = 0x31;
	$payload[0x11] = 0x31;
	$payload[0x12] = 0x31;
	$payload[0x1e] = 0x01;
	$payload[0x2d] = 0x01;
	$payload[0x30] = ord('T');
	$payload[0x31] = ord('e');
	$payload[0x32] = ord('s');
	$payload[0x33] = ord('t');
	$payload[0x34] = ord(' ');
	$payload[0x35] = ord(' ');
	$payload[0x36] = ord('1');

	$hash->{lastCMD} = 'get auth';
 
	return send_packet($hash, 0x65, @payload);
    }

    return "you must run get $name auth first !" if (!$hash->{isAuth});

    if ($cmd eq 'status') {
	my @payload = (1,3,0,0,0,22);

	$hash->{lastCMD} = 'get status';
	return send_packet($hash, 0x6a, @payload);
    }

    if ($cmd eq 'temperature') {
	# Get current external temperature in degrees celsius
	# [0x01,0x03,0x00,0x00,0x00,0x08]
	# return payload[5] / 2.0
	# return payload[18] / 2.0
	my @payload = (1,3,0,0,0,8);
	$hash->{lastCMD} = 'get temperature';
	return send_packet($hash, 0x6a, @payload);
    }

    return "unknown command $cmd , choose one of $gets";
}

sub Set {

    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument !";
    my $subcmd = shift // '';
    my $ret;
    my @payload;
    my $len;

    Log3($name, 4, "$name, set $cmd $subcmd") if (($cmd ne '?') && $subcmd);


    my $cmdList  = 'desired-temp on:noArg off:noArg mode:auto,manual loop:12345.67,123456.7,1234567 '
		  .'sensor:external,internal,both time:noArg active:noArg inactive:noArg lock:on,off '
		  .'power-on-memory:on,off fre:open,close room-temp-adj:'
		  .'-5,-4.5,-4,-3.5,-3,-2.5,-2,-1.5,-1,-0.5,0,0.5,1,1.5,2,2.5,3,3.5,4,4.5,5 '
		  .'osv svh svl dif:1,2,3,4,5,6,7,8,9 weekprofile';

    for (my $i=1; $i<7; $i++) { $cmdList .= ' day-profile'.$i.'-temp day-profile'.$i.'-time'; }
    for (my $i=7; $i<9; $i++) { $cmdList .=  ' we-profile'.$i.'-temp  we-profile'.$i.'-time'; }


    #if (($cmd eq '?') || ($cmd =~ /^(on-|off-|toggle|intervals)/)) {
   if (($cmd eq '?') || ($cmd =~ m{ /^(on-|off-|toggle|intervals)/ }x)) {
        return SetExtensions($hash, $cmdList, $name, $cmd, $subcmd);
    }

    ($subcmd) ? Log3($name, 5, "$name, set $cmd $subcmd") : Log3($name, 5, "$name, set $cmd");

    return 'no set commands allowed, auth key and device id are missing ! ( need run get auth first )' if (!$hash->{isAuth});


    if (($cmd eq 'inactive') && !IsDisabled($name)) {
	readingsSingleUpdate($hash, 'state', 'inactive', 1); 
	Undef($hash);
	return;
    }

    if (($cmd eq 'active') && IsDisabled($name)) {
	readingsSingleUpdate($hash, 'state', 'active', 1);
	update($hash);
	return;
    }

    if (($cmd eq 'on') || ($cmd eq 'off') || ($cmd eq 'lock')) {
	# Set device on(1) or off(0), does not deactivate Wifi connectivity
	#[0x01,0x06,0x00,0x00,remote_lock,power]

	$hash->{helper}{power}       = 1 if ($cmd  eq 'on');
	$hash->{helper}{power}       = 0 if ($cmd  eq 'off');
	$hash->{helper}{remote_lock} = 1 if (($cmd eq 'lock') && ($subcmd eq 'on' ));
	$hash->{helper}{remote_lock} = 0 if (($cmd eq 'lock') && ($subcmd eq 'off'));

	@payload = (1,6,0,0, $hash->{helper}{remote_lock}, $hash->{helper}{power});

	readingsSingleUpdate($hash, 'state', 'set_'.$cmd, 0)   if ($cmd ne 'lock');
	readingsSingleUpdate($hash, 'lock', 'set_'.$subcmd, 0) if ($cmd eq 'lock');

	$hash->{lastCMD} = "set $cmd";
	return send_packet($hash, 0x6a, @payload);
    }

    if (($cmd eq 'mode') || ($cmd eq 'sensor') || ($cmd eq 'loop')) {
	# mode_byte = ( (loop_mode + 1) << 4) + auto_mode
	# [0x01,0x06,0x00,0x02,mode_byte,sensor

	$hash->{helper}{'auto_mode'} = ($subcmd eq 'auto') ? 1 : 0 if ($cmd eq 'mode');

	# Sensor control option | 0:internal sensor 1:external sensor 2:internal control temperature, external limit temperature

	if ($cmd eq 'sensor') {
	    $hash->{helper}{SEN} = 2 if ($subcmd eq 'both');
	    $hash->{helper}{SEN} = 0 if ($subcmd eq 'internal');
	    $hash->{helper}{SEN} = 1 if ($subcmd eq 'external');
	}

	# E.g. loop_mode = 1 ("12345,67") means Saturday and Sunday follow the "weekend" schedule
	# loop_mode = 3 ("1234567") means every day (including Saturday and Sunday) follows the "weekday" schedule
 
	if ($cmd eq 'loop') {
	    $hash->{helper}{'loop_mode'} = 3 if ($subcmd eq '1234567');
	    $hash->{helper}{'loop_mode'} = 2 if ($subcmd eq '123456.7');
	    $hash->{helper}{'loop_mode'} = 1 if ($subcmd eq '12345.67');
	}

	@payload = (1,6,0,2);
	push @payload , (($hash->{helper}{'loop_mode'} << 4) + $hash->{helper}{'auto_mode'});
	push @payload , $hash->{helper}{'SEN'};

	readingsSingleUpdate($hash, $cmd, 'set_'.$subcmd, 0);

	$hash->{lastCMD} = "set $cmd $subcmd";
	return send_packet($hash, 0x6a, @payload);
    }

    if (($cmd eq 'power-on-memory')
     || ($cmd eq 'fre')
     || ($cmd eq 'room-temp-adj')
     || ($cmd eq 'osv')
     || ($cmd eq 'svh')
     || ($cmd eq 'svl')
     || ($cmd eq 'dif')) {

	# 1 | SEN | Sensor control option | 0:internal sensor 1:external sensor 2:internal control temperature, external limit temperature 
	# 2 | OSV | Limit temperature value of external sensor | 5-99C 
	# 3 | dIF | Return difference of limit temperature value of external sensor | 1-9C 
	# 4 | SVH | Set upper limit temperature value | 5-99C 
	# 5 | SVL | Set lower limit temperature value | 5-99C 
	# 6 | AdJ | Measure temperature | Measure temperature,check and calibration | 0.1C precision Calibration (actual temperature)
	# 7 | FrE | Anti-freezing function | 0:anti-freezing function shut down 1:anti-freezing function open
	# 8 | PoM | Power on memory | 0:Power on no need memory 1:Power on need memory
	#  set_advanced(loop_mode, sensor, osv, dif, svh, svl, adj, fre, poweron):
	#  input_payload = bytearray([0x01,0x10,0x00,0x02,0x00,0x05,0x0a, 
	#                             loop_mode, sensor, osv, dif, 
	#                             svh, svl, (int(adj*2)>>8 & 0xff), (int(adj*2) & 0xff), 
	#                             fre, poweron])

	$hash->{helper}{PoM} = 1 if ( ($cmd eq 'power-on-memory') && ($subcmd eq 'off') );
	$hash->{helper}{PoM} = 0 if ( ($cmd eq 'power-on-memory') && ($subcmd eq 'on') );
	$hash->{helper}{FrE} = 1 if ( ($cmd eq 'fre')             && ($subcmd eq 'open') );
	$hash->{helper}{FrE} = 0 if ( ($cmd eq 'fre')             && ($subcmd eq 'close') );

        $subcmd = int($subcmd);

	$hash->{helper}{SVH} = $subcmd if ( ($cmd eq 'svh') && ($subcmd > 4) && ($subcmd < 100));
	$hash->{helper}{SVL} = $subcmd if ( ($cmd eq 'svl') && ($subcmd > 4) && ($subcmd < 100));
	$hash->{helper}{OSV} = $subcmd if ( ($cmd eq 'osv') && ($subcmd > 4) && ($subcmd < 100));
	$hash->{helper}{dIF} = $subcmd if ( ($cmd eq 'dif') && ($subcmd > 0) && ($subcmd < 10));

	if ($cmd eq 'room-temp-adj') {
	    my $temp = ($subcmd * 2);
	    return "invalid offset $subcmd for room-temp-adj" if (($temp > 10) || ($temp < -10));
	    if  ($temp   >=  0 ) {
		$hash->{helper}{AdJ} = $temp;
	    }
	    else {
		$hash->{helper}{AdJ} = 0x10000 + $temp; 
	    }
	}

	# WICHTIG : Loop Mode und Auto Mode werden sonst mit geändert !
	$hash->{helper}{'loop_mode'} = (($hash->{helper}{'loop_mode'} << 4) + $hash->{helper}{'auto_mode'});

	@payload  = (0x01,0x10,0x00,0x02,0x00,0x05,0x0a,
		    $hash->{helper}{loop_mode},
		    $hash->{helper}{SEN},
		    $hash->{helper}{OSV},
		    $hash->{helper}{dIF},
		    $hash->{helper}{SVH},
		    $hash->{helper}{SVL},
		    $hash->{helper}{AdJ}>>8 & 0xff,
		    $hash->{helper}{AdJ} & 0xff,
		    $hash->{helper}{FrE},
		    $hash->{helper}{PoM}
		    );

	readingsSingleUpdate($hash, $cmd, 'set_'.$subcmd, 0);

	$hash->{lastCMD} = "set $cmd $subcmd";
	return send_packet($hash, 0x6a, @payload);
    }

    if ($cmd eq "time") {

	my ($sec,$min,$hour,undef,undef,undef,$wday,undef,undef) = localtime(gettimeofday());
	$wday = 7 if (!$wday); # Local 0..6 Sun-Sat, Thermo 1..7 Mon-Sun

	@payload = (1,16,0,8,0,2,4, $hour, $min, $sec, $wday);
	Log3($name, 4, "$name, set time $hour:$min:$sec, $wday");
 
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'time', "set_$hour:$min:$sec", 0);
	readingsBulkUpdate($hash, 'dayofweek', 'set_'.$wday, 0);
	readingsEndUpdate($hash,0);

	$hash->{lastCMD} = "set $cmd";
	return send_packet($hash, 0x6a, @payload);
    }
 
    if ($cmd eq 'desired-temp') {
	return  'Missing Temperature' if (!$subcmd);

	my $temp = int($subcmd*2);
	return 'Temperature must be between 5 and 99' if (($temp < 10) || ($temp > 198));

	@payload             =  (1,6,0,1,0,$temp);  # setzt angeblich auch mode manu
	$hash->{lastCMD}     = "set $cmd $subcmd";
	return send_packet($hash, 0x6a, @payload);
    }

    if ( $cmd =~ m{ /^(day|we)-profile[1-8]-time$/ }x ) {
	return "Time must be between 0:00 and 23:59" if ($subcmd !~ m{/(?:[01]\d|2[0123]):(?:[012345]\d)/gm}x);
	my $day = $cmd;
	$day =~ s/(day|we)-profile//;
	$day =~ s/-time//;
	$day--;  # 0 - 7
	$hash->{helper}{$day}{time} = $subcmd;

	@payload = set_timer_schedule($hash);

	$hash->{lastCMD} = "set $cmd $subcmd";
	$hash->{weekprofile} = '???';
	return send_packet($hash, 0x6a, @payload);
    }

    if ( $cmd =~ m{ /^(day|we)-profile[1-8]-temp$/ }x ) {
	my $temp = int($subcmd*2);
	return "Temperature must be between 5 and 99" if (($temp < 10) || ($temp > 198));

	my $day = $cmd;
	$day =~ s/(day|we)-profile//;
	$day =~ s/-temp//;
	$day--;
	$hash->{helper}{$day}{temp} = $temp;
	@payload = set_timer_schedule($hash);

	readingsSingleUpdate($hash, $cmd, $subcmd, 0);

	$hash->{lastCMD} = "set $cmd $subcmd";
	$hash->{weekprofile} = '???';
	return send_packet($hash, 0x6a, @payload);
    }

    if ($cmd eq 'weekprofile') {
	my ($wpd,$wpp,$wpday) = split(':', $subcmd);
	return "use set $name weekprofile <weekday_device_name:profile_name[:day]>" if ((!$wpd) || (!$wpp));
	$wpday= ' ' if (!$wpday);

	my $topic;
	$topic = ReadingsVal($wpd, 'active_topic', '') if (AttrNum($wpd, 'useTopics', 0));
	$wpp = ($topic) ? $topic.':'.$wpp : $wpp;

	eval { require JSON; 1; } or do { return 'please install JSON first'; };

	my $json = CommandGet(undef, "$wpd profile_data $wpp");

	if (substr($json,0,2) ne "{\"") #} kein JSON = Fehlermeldung FHEM Device nicht vorhanden oder Fehler von weekprofile
	{
	    Log3($name, 2, "$name, $json");
	    readingsSingleUpdate($hash, 'error', $json, 1);
	    return $json;
	}

	my @days = ('Mon','Tue','Wed','Thu','Fri','Sat','Sun');

	my $today = ($wpday eq ' ') ? $days[ (localtime(time))[6] -1 ] : $wpday;
	return "$today is not a valid weekprofile day, please use on of ".join(",",@days) if  !grep {/$today/} @days;

	my $j;

	eval { 
	    $j = decode_json($json);
	    1;
	} 
	or do {
	    $ret = $@;
	    Log3($name, 2, "$name, $ret");
	    readingsSingleUpdate($hash, 'error', $ret, 1);
	    return $ret;
	};

	for (my $i=0; $i<6; $i++) {
	    if (!defined($j->{$today}{time}[$i])) {
		$ret = "Day $today time #".($i+1)." is missing in weekprofile $wpd profile_data $wpp";
		Log3($name, 2, "$name, $ret");
		readingsSingleUpdate($hash, 'error', $ret, 1);
		return $ret;
	    }
	    else {
		if (int(substr($j->{$today}{time}[$i],0,2)) > 23) {
		    $ret = "Day $today time #".($i+1)." hour ".substr($j->{$today}{time}[$i],0,2)." is invalid";
		    Log3($name, 2, "$name, $ret");
		    readingsSingleUpdate($hash, 'error', $ret, 1);
		    return $ret;
		}
	    }

	    if (!defined($j->{$today}{temp}[$i])) { # eigentlich überflüssig ?
		$ret = "Day $today temperature #".($i+1)." is missing in weekprofile $wpd profile_data $wpp";
		Log3($name, 2, "$name, $ret");
		readingsSingleUpdate($hash, 'error', $ret, 1);
		return $ret;
	    }
	}

	for (my $i=0; $i<6; $i++) {
	    $hash->{helper}{$i}{time} = $j->{$today}{time}[$i];
	    $hash->{helper}{$i}{temp} = int($j->{$today}{temp}[$i]*2);
	}

	@payload = set_timer_schedule($hash);
	$hash->{lastCMD}     = "set $cmd $subcmd";
	$hash->{weekprofile} = "$wpd:$wpp:$today";
	return send_packet($hash, 0x6a, @payload);
    }

    $cmdList .= ' on-for-timer off-for-timer on-till off-till on-till-overnight off-till-overnight toggle intervals';
    return "$name, set with unknown argument $cmd, choose one of $cmdList"; 
}

sub NBStart {

    my $arg = shift // return;

    my ($name,$cmd) = split("\\|",$arg);
    my $hash     = $defs{$name};
    my $logname  = $name.'['.$$.']';
    my $timeout  = AttrVal($name, 'timeout', 3);
    my $data;

    Log3($name, 5, "$logname, NBStart $cmd");

    my $sock = IO::Socket::INET->new(
            PeerAddr  => $hash->{'.ip'},
            PeerPort  => '80',
            Proto     => 'udp',
            ReuseAddr => 1,
            Timeout   => $timeout
	    );

    if (!$sock) {
	Log3($name, 2, $logname.', '.$!);
	return $name.'|1|NBStart: '.$!;
    }

    my $select = IO::Select->new($sock);

    $cmd = decode_base64($cmd);
    $sock->send($cmd);
    $sock->recv($data, 1024) if ($select->can_read($timeout));
    $sock->close();

    return $name.'|1|no data from device' if (!$data);
    return $name.'|0|'.encode_base64($data,'');
}

sub NBAbort {

    my $hash = shift;
    my $name   = $hash->{NAME};
    my $error  = 'BlockingCall Timeout';
    $hash->{ERRORCOUNT}++;
    $error .= ' ['.$hash->{ERRORCOUNT}.'], abort for cmd : '.$hash->{lastCMD};
    Log3($name, 3, "$name, $error") if ($hash->{ERRORCOUNT} < AttrNum($name, 'maxErrorLog', 10));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'error', $error);
    readingsBulkUpdate($hash,'state', 'error');
    readingsBulkUpdate($hash,'alive', 'no');
    readingsEndUpdate($hash,1);
    delete($hash->{helper}{RUNNING_PID});
    return $error;
}

sub NBDone {

    my ($string) = @_;
    return unless(defined($string));

    my @r = split("\\|",$string);
    my $name     = $r[0];
    my $hash     = $defs{$name};
    my $error    = (defined($r[1])) ? int($r[1]) : 1;
    my $data     = (defined($r[2])) ? $r[2] : "";

    Log3($name, 5, "$name, NBDone : $string");

    delete($hash->{helper}{RUNNING_PID});

    if ($error) {
	if ($hash->{'skipError'} < AttrNum($name, 'skipTimeouts', 1)) {
	    $hash->{'skipError'}++;
	    Log3($name, 4, "$name, NBDone Timeout skip $hash->{'skipError'} , max : ".AttrVal($name,'skipTimeouts','1'));
	    return;
	}

	$hash->{'skipError'} = 0;
	$hash->{ERRORCOUNT}++;
	$data .= ' ['.$hash->{ERRORCOUNT}.'], for cmd : '.$hash->{lastCMD};
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'error', $data);
	readingsBulkUpdate($hash, 'state', 'error');
	readingsBulkUpdate($hash, 'alive', 'no');
	readingsEndUpdate($hash,1);
	Log3($name, 3, "$name, NBDone Data : $data") if ($hash->{ERRORCOUNT} < AttrNum($name, 'maxErrorLog', 10));
	return $data;
    }

   $data = decode_base64($data);

   if ((length($data) > 0x38) && ($hash->{lastCMD} eq 'get auth')) {
	my $cipher = getCipher($hash);
	my $dData  = $cipher->decrypt(substr($data, 0x38));

	if (length($dData) < 32) {
	    $error = 'auth -> decrypt data to short : '.length($dData);
	    Log3($name, 3, "$name, $error");
	    readingsBeginUpdate($hash);
	    readingsBulkUpdate($hash, 'error', $error);
	    readingsBulkUpdate($hash, 'alive', 'yes');
	    readingsEndUpdate($hash,1);
	    return;
	}

	$hash->{'.key'} = substr($dData, 4, 16);
	$hash->{'.id'}  = substr($dData, 0,  4);

	$hash->{isAuth} = 1;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', 'auth');
	readingsBulkUpdate($hash, 'alive', 'yes');
	readingsEndUpdate($hash, 1);
	return CommandGet(undef, "name status"); # gleich die aktuellen Werte holen
    }

    if ((length($data) < 0x39) || unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8)) {
	$error = 'wrong data, '.unpack("C*", substr($data, 0x22, 1)).' | '.(unpack("C*", substr($data, 0x23, 1)) << 8);
	$error = 'to short data, length '.length($data) if (length($data) < 0x39);
    }
   else {
	my $cipher = getCipher($hash);
        my $dData  = $cipher->decrypt(substr($data, 0x38));

        my $payload_len = unpack("C*", substr($dData, 0, 1));

        my @payload;
        if (length($dData) > $payload_len) {
	    for my $i (2..$payload_len+1) { # Payload ohne Header aber mit CRC
		push @payload, unpack("C*",substr($dData, $i,1));
	    }
	    my $crc1 = int(((pop @payload) <<8) + pop @payload); # CRC entfernen und merken
	    my $crc2 = CRC16(@payload); # CRC selbst berechnen

	    if ($crc1 != $crc2) {
		$error = "CRC Error $crc1 / $crc2";
	    }
	}
        else { 
	    $error = "response to short $payload_len / ".length($dData);
	}

        if ($error) {
	    $hash->{ERRORCOUNT}++;
	    $error .= ' ['.$hash->{ERRORCOUNT}.']';
	    readingsBeginUpdate($hash);
	    readingsBulkUpdate($hash, 'error', $error);
	    readingsBulkUpdate($hash, 'state', 'error');
	    readingsBulkUpdate($hash, 'alive', 'yes');
	    readingsEndUpdate($hash,1);
	    Log3($name, 2, "$name, $error") if ($hash->{ERRORCOUNT} < AttrNum($name, 'maxErrorLog', 10));
	    return $error;
	}

	$hash->{ERRORCOUNT} = 0;
	$hash->{TIME}       = time();

	return UpdateTemp($hash,@payload) if ($hash->{lastCMD} eq 'get temperature'); 
	return CommandGet(undef, "$name status") if ($hash->{lastCMD} ne 'get status');
	UpdateStatus($hash,@payload) if ($hash->{lastCMD} eq 'get status');
    }
    return;
}

sub UpdateTemp {

    my ($hash, @data) = @_;
    my $name = $hash->{NAME};

    Log3($name, 5, "$name, UpdateTemp");
    Log3($name, 4, "$name, Room : ".sprintf('%.1f',  $data[5] / 2).' Floor : '.sprintf('%.1f', $data[18] / 2));

    if (@data < 19) {
	# Bug ?
	Log3($name, 3, "$name, UpdateTemp data to short ".int(@data));
	return;
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, 'alive', 'yes');
    readingsBulkUpdate ($hash, 'room-temp',  sprintf('%.1f',  $data[5] / 2));
    readingsBulkUpdate ($hash, 'floor-temp', sprintf('%.1f', $data[18] / 2));
    readingsEndUpdate($hash,1);

    return;
}

sub UpdateStatus {

    my ($hash,@data) = @_;
    my $name = $hash->{NAME};

    my $t;
    my $val;

    Log3($name, 5, "$name, UpdateStatus");

    if (@data < 47) {
	# Bug ?
	Log3($name, 3, "$name, UpdateStatus data to short ".int(@data));
	return;
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, 'alive', 'yes');

    $val = $data[3] & 1;
    $hash->{helper}{'remote_lock'} = $val;
    readingsBulkUpdate ($hash, 'remote-lock', $val);

    $val = $data[4] & 1;
    $hash->{helper}{power} = $val;
    readingsBulkUpdate ($hash, 'power', $val);

    readingsBulkUpdate ($hash, 'relay', ($data[4] >> 4) & 1);
    $t = ($data[4] >> 6) & 1;
    $hash->{helper}{temp_manual} = $t*2;
    readingsBulkUpdate ($hash, 'temp-manual',  $t); # 2 = manuelle Temp im Automodus
    readingsBulkUpdate ($hash, 'room-temp',     sprintf('%.1f', $data[5] / 2));
    readingsBulkUpdate ($hash, 'desired-temp',  sprintf('%.1f', $data[6] / 2));
    Log3($name, 4, "$name, temp-manual : $t , room-temp : ".sprintf('%.1f', $data[5] / 2).' desired-temp : '.sprintf('%.1f', $data[6] / 2));

    $val = $data[7]  & 15;
    $hash->{helper}{auto_mode} = $val;
    readingsBulkUpdate ($hash, 'mode', ($val) ? 'auto' : 'manual');

    $val = int(($data[7] >> 4) & 15);
    $hash->{helper}{loop_mode} = $val;

    $t = ($val == 1) ? '12345.67' : ($val == 2) ? '123456.7' : ($val == 3) ? '1234567' : '???';
    readingsBulkUpdate ($hash, 'loop', $t);

    $val = int($data[8]);
    $hash->{helper}{SEN} = $val;

    $t = ($val == 0) ? 'internal' : ($val == 1) ? 'external' : ($val == 2) ? 'both' : '???';
    readingsBulkUpdate ($hash, 'sensor', $t);

    $val = sprintf('%.1f', $data[9]);
    $hash->{helper}{OSV} = $data[9];  # 6 - 99 Bodentemp
    readingsBulkUpdate ($hash, 'osv', $val);

    $val = sprintf('%.1f', $data[10]);
    $hash->{helper}{dIF} = $data[10]; # 1 - 9 Bodentemp diff
    readingsBulkUpdate ($hash, 'dif', $val);

    $val = sprintf('%.1f', $data[11]);
    $hash->{helper}{SVH} = $data[11]; # Raumtemp max. 5 - 99
    readingsBulkUpdate ($hash, 'svh', $val);

    $val = sprintf('%.1f', $data[12]);
    $hash->{helper}{SVL} = $data[12]; # Raumtemp min 5 - 99
    readingsBulkUpdate ($hash, 'svl', $val);

    $val = ($data[13] << 8) + $data[14];
    $hash->{helper}{AdJ} = $val; #  Raumtemp adj -5 - 0 - +5

    my $adj = ($val >=  0) ? sprintf('%.1f', $val / 2) : sprintf('%.1f', (0x10000 - $val) / -2);

    readingsBulkUpdate ($hash, 'room-temp-adj', $adj);

    $hash->{helper}{FrE} = $data[15];
    readingsBulkUpdate ($hash, 'fre', ($data[15]) ? 'open' : 'close');

    $hash->{helper}{PoM} = $data[16];
    readingsBulkUpdate ($hash, 'power-on-mem',  ($data[16]) ? 'off' : 'on');

    readingsBulkUpdate ($hash, 'unknown',    $data[17]); # ???
    readingsBulkUpdate ($hash, 'floor-temp', sprintf('%0.1f', $data[18] / 2));
    Log3($name, 4, "$name,  floor-temp : ".sprintf('%.1f', $data[18] / 2));

    readingsBulkUpdate ($hash, 'time',       sprintf('%02d:%02d:%02d', $data[19],$data[20],$data[21]));
    readingsBulkUpdate ($hash, 'dayofweek',  $data[22]);

    for (my $i=0; $i<6; $i++) {
	$hash->{helper}{$i}{time} = sprintf('%02d:%02d' , $data[2*$i+23], $data[2*$i+24]);
	readingsBulkUpdate ($hash, 'day-profile'.($i+1).'-time', $hash->{helper}{$i}{time});
	$hash->{helper}{$i}{temp} = $data[$i+39];
	readingsBulkUpdate ($hash, 'day-profile'.($i+1).'-temp', sprintf('%.1f', $hash->{helper}{$i}{temp} / 2));
     }

     for (my $i=6; $i<8; $i++) {
	$hash->{helper}{$i}{time} = sprintf('%02d:%02d' , $data[2*$i+23] , $data[2*$i+24]);
	readingsBulkUpdate ($hash, 'we-profile'.($i+1).'-time', $hash->{helper}{$i}{time});
	$hash->{helper}{$i}{temp} = $data[$i+39];
	readingsBulkUpdate ($hash, 'we-profile'.($i+1).'-temp', sprintf('%.1f', $hash->{helper}{$i}{temp} / 2));
     }

    readingsBulkUpdate ($hash, 'mode_state', $hash->{helper}{temp_manual} + $hash->{helper}{auto_mode});
    readingsBulkUpdate ($hash, 'state', ($hash->{helper}{power}) ? 'on' : 'off');
    readingsEndUpdate($hash,1);

    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
    my $time1 = timelocal( $sec, $min, $hour,$mday,$month,$year);
    my $time2 = timelocal($data[21],$data[20],$data[19],$mday,$month,$year);
    $data[22] = 0 if ($data[22] == 7);

    # falscher Wochentag oder Zeit Diff mehr als eine Minute ?

    if (($wday != $data[22]) || (($time1-$time2) > 60) || (($time1-$time2) < -60)) {
	my @days =('Sun','Mon','Tue','Wed','Thu','Fri','Sat','Sun');
	my $time1_s = sprintf('%02d:%02d:%02d , %3s' , $hour,$min,$sec,$days[$wday]);
	my $time2_s = sprintf('%02d:%02d:%02d , %3s' , $data[19],$data[20],$data[21],$days[$data[22]]);

	if (!AttrNum($name, 'timesync', 0)) {
	    Log3($name, 3, "$name, time on device is wrong. FHEM : $time1_s / $name : $time2_s - run set $name time");
	}
	else {
	    Log3($name, 4, "$name, time autosync : $time1_s / $time2_s");
	    CommandSet(undef, "$name time");
	}
    }
    return;
}

sub getCipher {

  my $hash = shift;

  return Crypt::CBC->new(
			-key         => $hash->{'.key'},
			-cipher      => 'Crypt::OpenSSL::AES',
			-header      => 'none',
			-iv          => $hash->{'.iv'},
			-literal_key => 1,
			-keysize     => 16,
			-padding     => 'space'
			);
}

sub send_packet {

    my ($hash,$command,@payload) = @_;
    my $name = $hash->{NAME};
    my $len;
    Log3($name, 5, "$name, send_packet ". join(' ', @payload));

    if ($command != 0x65) { # auth payload ist bereits fertig
	$len = int(@payload)+2; 
	my $crc  = CRC16(@payload);
        push @payload, $crc & 0xFF; 
        push @payload, $crc >>8;

	unshift @payload, 0;
	unshift @payload, $len;

	$len +=2; # neue Länge und dann mit Nullen auffüllen bis Länge ohne Rest durch 16 teilbar ist

	for (my $i=16; $i<96; $i+=16) {
	    if (( $len > ($i-16) ) && ( $len < $i ))  { while (int(@payload) < $i) { push @payload, 0; } }
	}

    }

    $hash->{'counter'} = ($hash->{'counter'} + 1) & 0xffff;

    my @id  = split(//, $hash->{'.id'});
    my @mac = split(':', $hash->{MAC});

    my @packet = (0) x 56;

    $packet[0x00] = 0x5a;
    $packet[0x01] = 0xa5;
    $packet[0x02] = 0xaa;
    $packet[0x03] = 0x55;
    $packet[0x04] = 0x5a;
    $packet[0x05] = 0xa5;
    $packet[0x06] = 0xaa;
    $packet[0x07] = 0x55;
    $packet[0x24] = 0x2a;
    $packet[0x25] = 0x27;
    $packet[0x26] = $command;
    $packet[0x28] = $hash->{'counter'} & 0xff;
    $packet[0x29] = $hash->{'counter'} >> 8;
    $packet[0x2a] = hex ($mac[5]);
    $packet[0x2b] = hex ($mac[4]);
    $packet[0x2c] = hex ($mac[3]);
    $packet[0x2d] = hex ($mac[2]);
    $packet[0x2e] = hex ($mac[1]);
    $packet[0x2f] = hex ($mac[0]);
    $packet[0x30] = unpack('C', $id[0]);
    $packet[0x31] = unpack('C', $id[1]);
    $packet[0x32] = unpack('C', $id[2]);
    $packet[0x33] = unpack('C', $id[3]);

    #calculate payload checksum of original data
    my $checksum = 0xbeaf;
    $len = int(@payload);
    for(my $i = 0; $i < $len; $i++) {
	$checksum += $payload[$i];
	$checksum  = $checksum & 0xffff;
    }

    $packet[0x34] = $checksum & 0xff;
    $packet[0x35] = $checksum >> 8;

    #crypt payload
    my $cipher       = getCipher($hash);
    my $payloadCrypt = $cipher->encrypt(pack('C*', @payload));

    #add the crypted data to packet
    my @values = split(//,$payloadCrypt);

    foreach  (@values) { push @packet, unpack('C*', $_); }

    #create checksum of whole packet
    $checksum = 0xbeaf;
    $len      = int(@packet);

    for(my $i = 0; $i < $len; $i++) {
	$checksum += $packet[$i];
	$checksum  = $checksum & 0xffff;
    }

    $packet[0x20] = $checksum & 0xff;
    $packet[0x21] = $checksum >> 8;

    my $timeout = AttrVal($name, 'timeout', 3)*2;

    Log3($name, 5, "$name, send_packet ". join(' ', @packet));
    my $arg = encode_base64(pack('C*',@packet));

    $arg = $name.'|'.$arg;

    if (defined($hash->{helper}{RUNNING_PID})) {
	Log3($name, 3, "$name, last BlockingCall $hash->{helper}{RUNNING_PID}{pid} has not ended yet !");
    }
    $hash->{helper}{RUNNING_PID} = BlockingCall('FHEM::BEOK::NBStart',$arg, 'FHEM::BEOK::NBDone',$timeout,'FHEM::BEOK::NBAbort',$hash); 

    if (!$hash->{helper}{RUNNING_PID}) {
	$hash->{ERRORCOUNT}++;
	my $error = "can`t start BlockingCall [$hash->{ERRORCOUNT}]";
	Log3($name, 3, "$name, $error") if ($hash->{ERRORCOUNT} < 20);
	readingsBeginUpdate($hash);
	readingsBulkUpdate ($hash, 'error', $error);
	readingsBulkUpdate ($hash, 'state', 'error');
	readingsEndUpdate($hash,1);
	return $error;
    }
    return;
}

sub CRC16 {
    my (@ar) = @_;
    my $crc = 0xFFFF;

    foreach my $val (@ar) {
	$crc ^= 0xFF & $val;
	for (1..8) {
	    if ($crc & 0x0001) {
		$crc = (($crc >> 1) & 0xFFFF) ^ 0xA001;
	    }
	    else {
		$crc =  ($crc >> 1) & 0xFFFF;
	    }
	}
    }
    return $crc;
}

sub set_timer_schedule {

    my $hash = shift;

    # Set timer schedule
    # Format is the same as you get from get_full_status.
    # weekday is a list (ordered) of 6 dicts like:
    # {'start_hour':17, 'start_minute':30, 'temp': 22 }
    # Each one specifies the thermostat temp that will become effective at start_hour:start_minute
    # weekend is similar but only has 2 (e.g. switch on in morning and off in afternoon)

    # Begin with some magic values ...
    my @payload = (1,16,0,10,0,0x0c,0x18);

    # Now simply append times/temps

    for (my $i=0; $i<8; $i++) {
	my ($h,$m) = split(':', $hash->{helper}{$i}{time});
	push @payload,int($h); push @payload,int($m);
    }

    for (my $i=0; $i<8; $i++) {
	push @payload, $hash->{helper}{$i}{temp}; # temperatures
    }

    return @payload;
}

sub Attr {

    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash  = $defs{$name};

    if ($attrName eq 'interval') {
	OnTimer($hash)  if ($cmd eq 'set');  # Polling Start
	RemoveInternalTimer($hash) if ($cmd eq 'del');
    }
    return;
}

sub summaryFn {

    my ($FW_wname, $name, $room, $pageHash) = @_;
    return if (AttrVal($name, 'stateFormat', ''));

    my $hash         = $defs{$name};
    my $state        = ReadingsVal($name,'state', '');
    my $power        = ($hash->{helper}{power}) ? 'on' : 'off';
    my $relay        = (ReadingsNum($name,'relay',1)) ? 'hon' : 'hoff';
    my $sensor       = $hash->{helper}{SEN};
    my $locked       = ($hash->{helper}{remote_lock}) ? 'closed' : 'open';
    my $mode         = ($hash->{helper}{auto_mode}) ? 'auto' : 'manual';
    my $csrf         = ($FW_CSRF ? "&fwcsrf=$defs{$FW_wname}{CSRFTOKEN}" : '');
    my $sel          = '';
    my $html         = '';
    my $link         = '';
    my $icon;
    my @names        = ('Room ','Floor ','desired-temp','Mode');

    return $state if (($state ne 'on' ) && ($state ne 'off'));

    if (AttrVal($name, 'language', '') eq 'DE') {
	@names = ('Raum ','Boden ','Soll','Modus');
    }

    if (($state eq 'on') || ($state eq 'off')) {
	($icon, undef, undef) = FW_dev2image($name,$power);
	$power  = FW_makeImage($icon, $power) if ($icon);
	$link   = "cmd.$name=set%20$name%20";
	$link  .= ($state eq 'on') ? 'off' : 'on';
	$power  = "<a onClick=\"FW_cmd('/fhem?XHR=1&$link&room=$room$csrf')\">$power</a>" if ($power);
	$html  .= '<table border="0" class="header"><tr><td>'.$power.'</td>';
    }

    if ($state eq 'off') {
	$html .='</tr></table>';
	return $html;
    }

    if ($state eq 'on') {
	($icon, undef, undef) = FW_dev2image($name,$relay);
	$relay = FW_makeImage($icon, $relay) if ($icon);

	($icon, undef, undef) = FW_dev2image($name,$locked);
	$locked = FW_makeImage($icon, $locked) if ($icon);

	$link    = "cmd.$name=set%20$name%20lock%20";
	$link   .= (int($hash->{helper}{remote_lock})) ? 'off' : 'on';
	$locked  = "<a onClick=\"FW_cmd('/fhem?XHR=1&$link&room=$room$csrf')\">$locked</a>" if ($locked);
	$html   .= '<td>'.$relay.'</td><td>'.$locked.'</td>';

	$html .= '<td align="right">'.$names[0].ReadingsNum($name,'room-temp',0).' &deg;C<br>'.$names[1].ReadingsNum($name,'floor-temp',0).' &deg;C</td>';

	$html .= "<td align=\"center\">".$names[2]."<br><select  id=\"".$name."_tempList\" name=\"".$name."_tempList\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1$csrf&cmd.$name=set $name desired-temp ' + this.options[this.selectedIndex].value)\">";

	for (my $i=10; $i<199; $i++) {
    	    my $s = (($i/2) == ReadingsNum($name,'desired-temp',5)) ? ' selected' : '';
    	    $html .= "<option".$s." value=\"".sprintf('%.1f', $i / 2)."\">".sprintf('%.1f', $i / 2)."</option>";
	}

	$html .= '</select></td>';

	$html .= "<td align=\"center\">".$names[3]."<br><select  id=\"".$name."_modeList\" name=\"".$name."_modeList\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1$csrf&cmd.$name=set $name mode ' + this.options[this.selectedIndex].value)\">";
	$sel   = ($mode eq 'auto') ? ' selected' : '';
	$html .= "<option".$sel." value=\"auto\">auto</option>";
	$sel   = ($mode eq 'manual') ? ' selected' : '';
	$html .= "<option".$sel." value=\"manual\">manual</option>";
	$html .= '</select></td>';
	$html .='</tr></table>';
	return $html;
    }
    return;
}

1;

=pod
=encoding utf8

=item device
=item summary implements a connection to BEOK / Floureon / Hysen WiFi room thermostat
=item summary_DE implementiert die Verbindung zu BEOK / Floureon / Hysen WiFi Raumthermostaten
=begin html

<a name="BEOK"></a>
<h3>BEOK</h3>
<ul>
    BEOK implements a connection to BEOK / Floureon / Hysen WiFi room thermostat
    <br>
	AES Encyrption is needed. Maybe you must first install extra Perl modules.<br>
        E.g. for Debian/Raspian :<br>
	<code>
        sudo apt-get install libcrypt-cbc-perl<br>
	sudo apt-get install libcrypt-rijndael-perl<br>
        sudo apt-get install libssl-dev<br>
	sudo cpan Crypt/OpenSSL/AES.pm</code>
    <br>
    <br>
    <a name="BEOKdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; BEOK &lt;ip&gt; [mac]</code>
        <br>
        <br>
        Example: <code>define Thermo BEOK 192.168.1.100</code>
    </ul>
    <br>
    <a name="BEOKset"></a>
    <b>Set</b>
    <br>
    <ul>
    <li><code>desired-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>mode &lt;auto manual&gt;</code>
    </li><br>
    <li><code>loop &lt;12345.67 123456.7 1234567&gt;</code><br>
    12345.67 means Saturday and Sunday follow the "weekend" schedule<br>
    1234567 means every day (including Saturday and Sunday) follows the "weekday" schedule
    </li><br>
    <li><code>sensor &lt;external internal both&gt;</code><br>
    both = internal control temperature, external limit temperature
    </li><br>
    <li><code>time</code><br>
    sets time and day of week on device to FHEM time & day
    </li><br>
    <li><code>lock &lt;on off&gt;</code>
    </li><br>
    <li><code>power-on-memory &lt;on off&gt;</code>
    </li><br> 
    <li><code>fre &lt;open close&gt;</code> 
     Anti-freezing function
    </li><br>
    <li><code>room-temp-adj  &lt;-5 +5&gt;</code>
    </li><br>
    <li><code>osv &lt;5 - 99&gt;</code><br>
    Limit temperature value of external sensor
    </li><br>
    <li><code>svh &lt;5 - 99&gt;</code><br>
    Set upper limit temperature value
    </li><br>
    <li><code>svl &lt;5 - 99&gt;</code><br>
    Set lower limit temperature value
    </li><br>
    <li><code>dif &lt;1 - 9&gt;</code><br>
    difference of limit temperature value of external sensor
    </li><br>
    <li><code>day-profil[1-6]-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>day-profil[1-6]-time &lt;00:00 - 23:59&gt;</code>
    </li><br>
    <li><code>we-profile[7-8]-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>we-profile[7-8]-time &lt;00:00 - 23:59&gt;</code>
    </li><br>
    <li><code>weekprofile</code><br>
    Set all weekday setpoints and temperatures with values from a weekprofile day.<br>
    Syntax : set <name> weekprofile  &lt;weekprofile_device:profil_name[:weekday]&gt;<br>
    see also <a href='https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303'>https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303</a>
    </li><br>

    </ul>
    <a name="BEOKattr"></a>
    <b>Attributes</b>
    <br>
    <ul><a name="timeout"></a>
        <li><code>timeout</code>
        <br>
        timeout for network device communication, default 5
        </li>
    </ul>
    <br>
    <ul><a name="interval"></a>
        <li><code>interval</code>
        <br>
        poll time interval in seconds, set to 0 for no polling , default 60
        </li>
    </ul>
    <br>
    <ul><a name="timesync"></a>
        <li><code>timesync</code>
        <br>
	 set device time and day of week automatic to FHEM time, default 1 (on)
        </li>
    </ul>
    <br>
    <ul><a name="language"></a>
        <li><code>language</code>
        <br>
	 set to DE for german names of Room, Floor , etc.
        </li>
    </ul>
    <br>
    <ul><a name="model"></a>
        <li><code>model</code>
        <br>
	  only for FHEM modul statistics at <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a>
        </li>
    </ul>

</ul>

=end html
=begin html_DE

<a name="BEOK"></a>
<h3>BEOK</h3>
<ul>
    BEOK implementiert die Verbindung zu einem BEOK / Floureon / Hysen WiFi Raum Thermostaten
	<br>
        Wiki : <a href='https://wiki.fhem.de/wiki/BEOK'>https://wiki.fhem.de/wiki/BEOK</a><br><br>
	Da das Modul AES-Verschl&uuml;sselung ben&ouml;tigt m&uuml;ssen ggf. noch zus&auml;tzliche Perl Module installiert werden.<br>
        Bsp. f&uuml;r Debian/Raspian :<br>
	<code>
        sudo apt-get install libcrypt-cbc-perl<br>
	sudo apt-get install libcrypt-rijndael-perl<br>
        sudo apt-get install libssl-dev<br>
	sudo cpan Crypt/OpenSSL/AES.pm</code><br>
    <br><br>
    <a name="BEOKdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; BEOK &lt;ip&gt; [mac]</code>
        <br>
        <br>
        Beispiel: <code>define WT BEOK 192.178.1.100</code><br>
        <code>define WT BEOK 192.178.1.100 01:02:03:04:05:06</code><br>
        Es wird empfohlen die MAC Adresse mit anzugeben. Z.z ist noch nicht gekl&auml;rt ob sonst eventuell vermehrte Timeouts die Folge sind.
    </ul>
    <br>
    <br>
    <a name="BEOKset"></a>
    <b>Set</b><br>
    <ul><a name="desired-temp"></a><li><desired-temp &lt;5 - 99&gt;</li><br>
    <a name="mode"></a><li>mode &lt;auto manual&gt;</li><br>
    <a name="loop"></a><li>loop &lt;12345.67 123456.7 1234567&gt;<br>
    12345.67 Montag - Freitag Werktag, Samstag & Sonntag sind Wochenende<br>
    123456.7 Montag - Samstag Werktag, nur Sonntag ist Wochendende<br>
    1234567 jeder Tag (inklusive Samstag & Sonntag) ist ein Werktag, kein Wochenende
    </li><br>
    <a name="sensor"></a><li>sensor &lt;external internal both&gt;<br>
    both = internal control temperature, external limit temperature
    </li><br>
    <a name="time"></a><li>time<br>
    setzt Uhrzeit und Wochentag
    </li><br>
    <li><code>lock &lt;on off&gt;</code>
    </li><br>
    <li><code>power-on-memory &lt;on off&gt;</code>
    </li><br> 
    <li><code>fre &lt;open close&gt;</code><br>
     Frostschutz Funktion
    </li><br>
    <li><code>room-temp-adj  &lt;-5 - +5&gt;</code><br>
    Korrekturwert (Offset) Raumtemperatur
    </li><br>
    <li><code>osv &lt;5 - 99&gt;</code><br>
    Maximum Temperatur f&uuml;r externen Sensor
    </li><br>
    <li><code>svh &lt;5 - 99&gt;</code><br>
    Raumtemperatur Maximum
    </li><br>
    <li><code>svl &lt;5 - 99&gt;</code><br>
    Raumtemperatur Minimum
    </li><br>
    <li><code>dif &lt;1 - 9&gt;</code><br>
    difference of limit temperature value of external sensor
    </li><br>
    <li><code>day-profil[1-6]-temp &lt;5 - 99&gt;</code><br>
    Werktagprofil Temperatur
    </li><br>
    <li><code>day-profil[1-6]-time &lt;00:00 - 23:59&gt;</code><br>
    Werktagprofil Zeit
    </li><br>
    <li><code>we-profile[7-8]-temp &lt;5 - 99&gt;</code><br>
    Wochenendprofil Temperatur
    </li><br>
    <li><code>we-profile[7-8]-time &lt;00:00 - 23:59&gt;</code><br>
    Wochenendprofil Zeit
    </li><br>
    <li><code>weekprofile</code><br>
    Setzt alle Wochentag Schaltzeiten und Temperaturen mit Werten aus einem Profil des Moduls weekprofile.<br>
    Syntax : set <name> weekprofile &lt;weekprofile_device:profil_name[:Wochentag]&gt;<br>
    siehe auch Erkl&auml;rung im <a href='https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303'>Forum</a>
    bzw. im <a href='https://wiki.fhem.de/wiki/BEOK'>Wiki</a>.
    </li><br>
  </ul>
    <a name="BEOKattr"></a>
    <b>Attribute</b>
    <br>
    <ul><a name="display"></a>
        <li>display
        <br>
         auto | always_on , default auto<br>
         Displaybeleuchtung bei jeder Statusabfrage einschalten (always_on). Wird ausserdem das Attribut interval auf eine Zeit kleiner 9 Sekunden gesetzt,
         so leuchtet das Display dauerhaft.<br><b>ACHTUNG</b> dies hat eine wesentlich h&ouml;here Funklast zur Folge !<br>
         D.h. die Wahrscheinlichkeit von gelegentlichen Timeouts wird stark zunehmen, siehe auch Attribut skipTimeouts.
        </li>
    </ul>
    <br>
    <ul><a name="interval"></a>
        <li>interval
        <br>
	  Poll Intevall in Sekunden, 0 = kein Polling , default 60
        </li>
    </ul>
    <br>
    <ul><a name="keepAuto"></a>
        <li>keepAuto
        <br>
	  0 | 1 , default 0 (aus)<br>
          Schaltet das Thermostat kurz vor Ende eines Tages in den Mode auto sollte es sich zu diesem Zeitpunkt
          im Mode manu befinden.
        </li>
    </ul>
    <br>
    <ul><a name="language"></a>
        <li>language
        <br>
	  DE f&uuml;r deutsche Bezeichnungen in der &Uuml;bersicht, z.B. Raum statt Room , usw.
        </li>
    </ul>
    <br>
    <ul><a name="maxErrorLog"></a>
        <li>maxErrorLog
        <br>
	  Default : 10<br>maximale Anzahl wie oft die gleiche Fehlermeldung in die Log Datei geschrieben wird.
        </li>
    </ul>
    <br>
    <ul><a name="model"></a>
        <li>model
        <br>
	  nur f&uuml;r die FHEM Modul Statistik unter <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a>
        </li>
    </ul>
    <br>
    <ul><a name="skipTimeouts"></a>
        <li>skipTimeouts
        <br>
        0 - 9 , default 1<br>
        Anzahl der max. zul&auml;ssigen Timeouts in Folge ohne das ein Logeintrag bzw. eine Fehlermeldung erfolgt (default 1)
        </li>
    </ul>
    <br>
    <ul><a name="timeout"></a>
        <li><code>timeout</code>
        <br>
	  Timeout in Sekunden für die Wlan Kommunikation, default 5<br>
          <b>ACHTUNG</b> in Verbindung mit dem Attribut display = alaways_on darf diese Wert niemals gr&ouml;sser als als das Attribut interval sein ! 
        </li>
    </ul>
    <br>
    <ul><a name="timesync"></a>
        <li><code>timesync</code>
        <br>
	 Uhrzeit und Wochentag automatisch mit FHEM synchronisieren, default 1 (an)<br>
         Setzt automatisch FHEM Zeit und Wochentag im Thermostsat.
        </li>
    </ul>
</ul>

=for :application/json;q=META.json 98_readingsWatcher.pm

{
  "abstract": "connection to BEOK / Floureon / Hysen WiFi room thermostat",
  "x_lang": {
    "de": {
      "abstract": "Verbindung zu BEOK / Floureon / Hysen WiFi Raum Thermostat"
    }
  },
  "keywords": [
    "BEOK",
    "Hysen",
    "Floureon",
    "Thermostat"
  ],
  "version": "2.0.0",
  "release_status": "stable",
  "author": [
    "Wzut"
  ],
  "x_fhem_maintainer": [
    "Wzut"
  ],
  "x_fhem_maintainer_github": [
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "GPUtils": 0,
        "Time::HiRes": 0,
        "IO::Socket": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=end html_DE
=cut