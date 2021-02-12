# $Id$
#
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/board,26.0.html
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
#
################################################################

package FHEM::OW2S0SMSGUARD;  ## no critic 'package'

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);
use DevIo;
use Scalar::Util qw(looks_like_number);
use GPUtils qw(GP_Import GP_Export); # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

BEGIN
{
    # Import from main::
    GP_Import(
	qw(
	attr
	AttrNum
	AttrVal
	CommandAttr
	CommandDelete
	CommandDeleteReading
	defs
	deviceEvents
	DevIo_CloseDev
	DevIo_OpenDev
	DevIo_SimpleRead
	Dispatch
	init_done
	IsDisabled
	InternalTimer
	Log3
	modules
	ReadingsVal
	ReadingsNum
	ReadingsTimestamp
	readingsSingleUpdate
	readingsBulkUpdate
	readingsBeginUpdate
	readingsEndUpdate
	readingFnAttributes
	RemoveInternalTimer
	setDevAttrList
	setReadingsVal
	TimeNow
	time_str2num
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

#####################################

sub Initialize {
    my $hash = shift;

    $hash->{Clients}    = ':OW2S0SMSGUARD:';
    $hash->{MatchList}  = { '1:OW2S0SMSGUARD' => '^OW.*' };
    $hash->{ReadFn}     = \&ReadFn;
    $hash->{DefFn}      = \&DefineFn;
    $hash->{UndefFn}    = \&UndefFn;
    $hash->{NotifyFn}   = \&NotifyFn;
    $hash->{GetFn}      = \&GetFn;
    $hash->{SetFn}      = \&SetFn;
    $hash->{AttrFn}     = \&AttrFn;
    $hash->{ParseFn}    = \&ParseFn;
    $hash->{AttrList}   = 'model:unknown,DS2401,DS1820,DS18B20,DS1822 '.$readingFnAttributes; # Slave Device
    $hash->{AutoCreate} = { '^OW.*' => {ATTR => 'event-on-change-reading:.* timestamp-on-change-reading:.*', FILTER => '%NAME', GPLOT => q{}} };

    return  FHEM::Meta::InitMod( __FILE__, $hash ) if ($hasmeta);

    return;
}

#####################################

sub DefineFn {

    my $msg = 'wrong syntax: define <name> OW2S0SMSGUARD IO Device or model OWID';
    my $hash = shift;
    my $def  = shift // return $msg;

    my ($name, undef, $dev, $interval, $model) = split(m{ \s+ }xms, $def, 5);

    $dev // return $msg;
    $model //= 'unknown';

    DevIo_CloseDev($hash);

    my $addr = ( $dev !~ m/\@/x && $dev !~ m/:/x && $dev !~ m/\./x) ? $dev : 'master';

    if ($addr eq 'master') {
	$hash->{DeviceName} = $dev;
	$interval //= 30;
	$hash->{INTERVAL}   = $interval;
	$hash->{OWDEVICES}  = 0;
	$hash->{OWVals}     = 0;
	$hash->{addr}       = 'master';
	$hash->{TIMEOUT}    = 0.5;
	setDevAttrList($name,'interval disable:0,1 DS2401_Timeout mapOWIDs useSubDevices:0,1 delay:0.01,0.05,0.1,0.5,1 model:master,unknown,DS2401,DS1820,DS18B20,DS1822 '.$readingFnAttributes);
	CommandAttr(undef, "$name model master")   if (!exists($attr{$name}{model}));
    }
    else {
	if (exists($modules{OW2S0SMSGUARD}{defptr}{$addr}) && $modules{OW2S0SMSGUARD}{defptr}{$addr}->{NAME} ne $name) {
	    return "$name, a OW2S0SMSGUARD device with address $addr is already defined as ".$modules{OW2S0SMSGUARD}{defptr}{$addr}->{NAME};
	}
	$hash->{addr} = $addr;
	CommandAttr(undef, "$name model $model")  if (!exists($attr{$name}{model}));
    }

    $hash->{STATE}      = 'defined';
    $hash->{NOTIFYDEV}  = 'global';
    $hash->{SVN}        = (qw($Id$))[2];

    $modules{OW2S0SMSGUARD}{defptr}{$addr} = $hash;

    return $@ if ($hasmeta && !FHEM::Meta::SetInternals($hash));

    return;
}

#####################################

sub UndefFn {
    my $hash = shift;
    delete $modules{OW2S0SMSGUARD}{defptr}{$hash->{addr}};
    DevIo_CloseDev($hash) if ($hash->{addr} eq 'master');
  return;
}

#####################################

sub NotifyFn {
    # $hash is my hash, $dhash is the hash of the changed device
    my $hash   = shift;
    my $dhash  = shift;
    my $name   = $hash->{NAME};
    my $events = deviceEvents($dhash, 0);
    my $ev_str = join('|', @{$events});

    if (($dhash->{NAME} eq 'global') && ((index($ev_str, 'INITIALIZED') > -1) || (index($ev_str, 'REREADCFG') > -1))) {

	return if ($hash->{addr} ne 'master');

	$attr{$name}{interval} = $hash->{INTERVAL} if (!exists($attr{$name}{interval}));
	$hash->{INTERVAL} = $attr{$name}{interval};

	if (index($ev_str, 'INITIALIZED') > -1) { # nur bei FHEM Neustart eventuelle DS2401 vorbesetzen
	    my @ds2401 = split(',', ReadingsVal($name, '.ds2401' ,''));

	    foreach my $dev (@ds2401) { 
		$hash->{helper}{OW}{100}{$dev}{name} = mapNames($hash, 100, $dev);
	    }
	    foreach my $dev (@ds2401) {
		setReadingsVal($hash, $hash->{helper}{OW}{100}{$dev}{name}, 'unkown', TimeNow());
		$hash->{helper}{OW}{100}{$dev}{time} = TimeNow();
		Log3($name, 5, "$name, restore hash for $dev");
	    }
	}

	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	DevIo_OpenDev($hash, 1, \&DoInit) if ($hash->{INTERVAL} && !IsDisabled($name));
	readingsSingleUpdate($hash, 'state', 'disabled', 1) if (!$hash->{INTERVAL} || !IsDisabled($name));
    }

    return;
}

#####################################

sub AttrFn {

    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    return if ($hash->{addr} ne 'master');

    if ($cmd eq 'del') {
	RemoveInternalTimer($hash);
	$hash->{INTERVAL} = 0 if ($attrName eq 'interval');
	InternalTimer(gettimeofday()+1, 'FHEM::OW2S0SMSGUARD::GetUpdate', $hash, 0) if ($attrName eq 'disable');
    }

    if ($cmd eq 'set') {
	if ($attrName eq 'interval') { 
	    return "invalid value" if (int($attrVal) < 0);
	    $hash->{INTERVAL} = int($attrVal);

	    InternalTimer(gettimeofday()+1, 'FHEM::OW2S0SMSGUARD::GetUpdate', $hash, 0) if ($hash->{INTERVAL});
	    readingsSingleUpdate($hash, 'state', 'disabled', 1) if (!$hash->{INTERVAL});
	}

	if ($attrName eq 'DS2401_Timeout') {
	    return "invalid value" if (((int($attrVal) < 0) || (int($attrVal) < $hash->{INTERVAL})) && $init_done);
	}

	if ($attrName eq 'disable') {
	    if (int($attrVal) == 1) {
		DevIo_CloseDev($hash);
		readingsSingleUpdate($hash, 'state', 'disabled', 1);
		$hash->{INTERVAL} = 0;
		RemoveInternalTimer($hash);
	    }
	    if (int($attrVal) == 0) {
		$hash->{INTERVAL} = AttrNum($name, 'interval', 30);
		InternalTimer(gettimeofday()+1, 'FHEM::OW2S0SMSGUARD::GetUpdate', $hash, 0) if ($hash->{INTERVAL});
		DevIo_CloseDev($hash);
		DevIo_OpenDev($hash, 1, \&DoInit) if ($hash->{INTERVAL}); #$hash, $reopen, $initfn, $callback
	    }
	}
    }
    return;
}

#####################################

sub DoInit {
    my $hash = shift;

    Log3($hash, 5, "$hash->{NAME}, DoInit");

    if ($hash->{INTERVAL}) {
	RemoveInternalTimer($hash);
	SimpleWrite($hash, "\$L+\n\$?");
	InternalTimer(gettimeofday()+1, 'FHEM::OW2S0SMSGUARD::GetUpdate', $hash, 0);
    }

    return;
}

#####################################

sub GetUpdate {

    my $hash = shift;
    my $name = $hash->{NAME};

    Log3($name, 5, "$name, GetUpdate");
    RemoveInternalTimer($hash);
    return if (IsDisabled($name) || !$hash->{INTERVAL} || ($hash->{addr} ne 'master'));

    my $c = ($hash->{STATE} ne 'disconnected') ? SimpleWrite($hash, '$?') : DevIo_OpenDev($hash, 1, \&DoInit);

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, 'FHEM::OW2S0SMSGUARD::GetUpdate', $hash, 0);

    return;
}

#####################################

sub read_OW {
    my $h = shift;
    my $hash = $h->{h};
    my $num  = $h->{n};

    SimpleWrite($hash, '$'.$num); # Antwort kommt via sub ReadFn
    Log3($hash, 5, "$hash->{NAME}, read_OW : $num");
    return;
}

#####################################

sub SetFn {

    my $hash  = shift // return;

    return if ($hash->{addr} ne 'master');

    my $name  = shift // return;
    my $cmd   = shift // '?';
    my $val   = shift // .5;
    my $dlist = ReadingsVal($name, '.ds2401' ,'');
    my $ds    = ($dlist) ? ' deleteDS2401:'.$dlist : '';


    if ($cmd eq 'reset') {
	DevIo_CloseDev($hash);
	return DevIo_OpenDev($hash, 1, \&DoInit);
    }

    return SimpleWrite($hash, '$rez') if ($cmd eq 'S0-reset');

    if (($cmd eq 'deleteDS2401') && $dlist && (IsValidHex($val,16)) && (substr($val, 0, 2) eq '01')) {

	my ($ret , $rr, $r);

	if (exists($hash->{helper}{OW}{100}{$val})) {
	    my $reading = (defined($hash->{helper}{OW}{100}{$val}->{name})) ? $hash->{helper}{OW}{100}{$val}->{name} : '';
	    $ret = CommandDeleteReading(undef, "$name $reading") if ($reading);
	    delete $hash->{helper}{OW}{100}{$val};
	}

	# Sub Device löschen ?
	my $dname = (exists($modules{OW2S0SMSGUARD}{defptr}{$val})) ? $modules{OW2S0SMSGUARD}{defptr}{$val}->{NAME} : '';
	$r = CommandDelete(undef, $dname) if ($dname && AttrVal($name, 'useSubDevices', ''));
	$ret .= ($ret && $r) ? ' '.$r : $r;

	$dlist =~ s/$val//x;
	$dlist =~ s/,,/,/x; # $val war in der Mitte des Strings
	$dlist =~ s/(^,|,$)//x; # einzelens Komma am Anfang oder Ende ?

	readingsSingleUpdate($hash, '.ds2401', $dlist, 0) if ($dlist); # noch etwas übrig vom reading ?

	if (!$dlist) {
	    $rr = CommandDeleteReading(undef, "$name .ds2401");
	    $ret .= ($ret && $rr) ? ' '.$rr : $rr;
	}
	Log3($name, 3, "$name, $ret") if ($ret);
	return $ret;
    }

    return 'Unknown argument '.$cmd.', choose one of reset:noArg S0-reset:noArg '.$ds;
}

#####################################

sub GetFn {

    my $hash   = shift // return;
    my $name   = shift // return;
    my $cmd    = shift // '?';

    return if ($hash->{addr} ne 'master');

    if (($cmd eq 'OWdevicelist') && (exists($hash->{helper}{OW}))) {
        my @devs;
	foreach my $dev ( sort keys %{$hash->{helper}{OW}} ) {
	    next if (int($dev) == 100);
	    push @devs, "$dev,$hash->{helper}{OW}{$dev}{typ},$hash->{helper}{OW}{$dev}{addr},$hash->{helper}{OW}{$dev}{name},$hash->{helper}{OW}{$dev}{time}";
	}
	return formatOWList(@devs);
    }

    return 'Unknown argument '.$cmd.', choose one of OWdevicelist:noArg';
}

sub formatOWList {

    my @devs = @_;

    # Type   | Address          | Name   | Time
    # -------+------------------+--------+--------------------
    # DS1820 | 10D64CBF02080077 | Keller | 2021-01-30 08:44:55
    # DS2401 | 018468411C0000BA | TestDS | 2021-01-30 08:44:55
    # -------+------------------+--------+--------------------

    return 'Sorry, no OW devices found !' if (!int(@devs));

    my ($ow,$yw,$dw,$nw,$tw) = (1,6,8,5,5); # Startbreiten, bzw. Mindestbreite durch Überschrift

    foreach my $dev (@devs) {

	my ($o,$y,$d,$n,$t)  = split(',', $dev);
	# die tatsächlichen Breiten aus den vorhandenen Werten ermitteln
	$ow = (length($o) > $ow) ? length($o) : $ow;
	$yw = (length($y) > $yw) ? length($y) : $yw;
	$dw = (length($d) > $dw) ? length($d) : $dw;
	$nw = (length($n) > $nw) ? length($n) : $nw;
	$tw = (length($t) > $tw) ? length($t) : $tw;
    }

    my $head  = '# | Type' .(' ' x ($yw-4))
              .' | Address'.(' ' x ($dw-7))
              .' | Name'   .(' ' x ($nw-4))
              .' | Time'   .(' ' x ($tw-4));

    my $separator = ('-' x length($head));

    while ( $head =~ m{\|}xg ) { # alle | Positionen durch + ersetzen
	substr $separator, (pos($head)-1), 1, '+';
    }

    $head .= "\n".$separator."\n";

    my $s;
    foreach my $dev (@devs) {
;
	my ($o,$y,$d,$n,$t)  = split(',', $dev);
	$s .= $o . (' ' x ($ow - length($o))).' | ';
	$s .= $y . (' ' x ($yw - length($y))).' | ';
	$s .= $d . (' ' x ($dw - length($d))).' | ';
	$s .= $n . (' ' x ($nw - length($n))).' | ';
	$s .= $t . (' ' x ($tw - length($t)));
	$s .= "\n";
    }

    return $head.$s.$separator;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data

sub ReadFn {

    my $hash = shift;
    my $name = $hash->{NAME};

    my $buf = DevIo_SimpleRead($hash);
    return '' if (!defined($buf));

    my $raw = $hash->{PARTIAL};
    $raw .= $buf;

    Log3($name, 5, "$name, ReadFn RAW: $raw / buf :$ buf");

    my $i = 0;

    while($raw =~ m/\n/x) {
	my $rmsg;
	($rmsg,$raw) = split("\n", $raw, 2);
	$rmsg =~ s/[\r\$]//xg; # alle Antwortenn beginnen mit einem $ , Bsp $0;o;31;00;4B;46;FF;FF;07;10;8D;64;

	if ($rmsg) {
	    $i++;
	    Log3($name, 4, "$name, read[$i] : $rmsg");
	    Parse($hash,  $rmsg);
	}
    }

    $hash->{PARTIAL} = $raw;
    Log3($name, 5, "$name, ReadFn RAW: $raw");
    return;
}

#####################################

sub Parse {

    my $hash = shift;
    my $rmsg = shift // return;
    my $name = $hash->{NAME};
    my $txt;

    $rmsg =~ s/ //g;

    my @data = split(';', $rmsg);

    return ErrorLog($hash, 'message is too short -> '.int(@data)) if (int(@data) < 3);

    return UpdateReadings($hash, $rmsg) if ($data[0] eq 'S0'); # Liste ist jetzt vollständig

    return ErrorLog($hash, "first byte $data[0] is not a number !") if (!looks_like_number($data[0]));

    my $num  = int($data[0]);

    return ErrorLog($hash, "invalid OW number $num") if (($num > 63) || ($num < 0));


    my $ok   = (defined($data[1]) && ($data[1] eq 'o')) ? 1 : 0;

    # Werte Telegramm eines DS18xx ?
    return decodeVal($hash, $name, $num, @data) if ($ok && defined($data[11]) && exists($hash->{helper}{OW}{$num}));

    # eine Zeile aus list :  0;o;1080974B020800BA;
    if (defined($data[2])) {
	return ErrorLog($hash, "invalid hex address for device $num") if (!IsValidHex($data[2], 16));
	decodeList($hash, $name, $num, $ok, @data);
    }

    return;
}

#####################################

sub decodeList {

    my ($hash, $name, $num, $ok, @data) = @_;

    delete $hash->{helper}{OW}{$num};

    $hash->{helper}{OW}{$num}{state} = $ok;
    $hash->{helper}{OW}{$num}{time}  = TimeNow();
    $hash->{helper}{OW}{$num}{addr}  = $data[2];
    $hash->{'OW-Dev'.$num}           = $hash->{helper}{OW}{$num}{addr}." => $ok";
    $hash->{OWDEVICES}               = ($num + 1);

    return ErrorLog($hash, "got NOK for OW device $num [".$data[2].']') if (!$ok); 

    my $model = int(substr($data[2],0,2));
    my $owid  = substr($data[2],0,14);
    my $owcrc = substr($data[2],14,2);
    my $crc   = 0;

    for my $i (0,2,4,6,8,10,12) { # die ersten 7 Byte
	my $byte = substr($owid, $i , 2);
	for (my $bit=1; $bit<256; $bit=$bit*2) {
	    my $cbit = ((hex($byte) & $bit) == $bit) ? 1 : 0;
	    $crc= (($crc & 1) != $cbit) ? ($crc >> 1)^0x8c : $crc >> 1;
	}
    }

    return ErrorLog($hash, "CRC error OW device $num [$data[2]] : $owcrc != ". sprintf('%02x', $crc)) if ($crc != hex($owcrc));

    if ($num == 0) {
        for my $i (1..63) {delete $hash->{'OW-Dev'.$i} if (exists($hash->{'OW-Dev'.$i})); }
	$hash->{OWVals} = 0;
    }

    $hash->{helper}{OW}{$num}{fam} = $model;
    $hash->{OWVals}++ if ($model > 1);

    # passen DELAY und Intervall zusammen ?
    $hash->{DELAY} = AttrNum($name, 'delay' ,0.5);

    if (((($hash->{OWVals} * $hash->{DELAY})+1) >= $hash->{INTERVAL}) && $hash->{INTERVAL}) {
	ErrorLog($hash, "intervall $hash->{INTERVAL} is very short to read all $hash->{OWVals} OW devices with a delay of $hash->{DELAY} seconds");
    }

    mapNames($hash, $num);

    $hash->{helper}{OW}{$num}{typ} = 'DS1822'  if ($model == 22);
    $hash->{helper}{OW}{$num}{typ} = 'DS18B20' if ($model == 28);
    $hash->{helper}{OW}{$num}{typ} = 'DS1820'  if ($model == 10);

    if ($model == 1) {
	$hash->{helper}{OW}{100}{$data[2]}{name}  = $hash->{helper}{OW}{$num}{name};
	$hash->{helper}{OW}{100}{$data[2]}{time}  = TimeNow();
	$hash->{helper}{OW}{100}{$data[2]}{busid} = $num;
	$hash->{helper}{OW}{$num}{typ} = 'DS2401';
	$hash->{DS2401} .= (!$hash->{DS2401}) ? $data[2] : ','.$data[2];
    }

    if (!defined($hash->{helper}{OW}{$num}{typ})) {
	$hash->{helper}{OW}{$num}{typ} = 'unknown';
	ErrorLog($hash, "unknown OW type, address $data[2]");
    }

    InternalTimer(gettimeofday()+1+($num * $hash->{DELAY}), 'FHEM::OW2S0SMSGUARD::read_OW', {h=>$hash, n=>$num}, 0) if ($ok && ($model > 1)); # nicht bei DS2401
    return;
}

sub decodeVal {

    my ($hash, $name, $num, @data)  = @_;

    my $crc = 0;

    # das 10.Byte ist eine Checksumme für die serielle Übertragung

    for my $i (2..10) { 
	$crc += (IsValidHex($data[$i],2)) ? hex($data[$i]) : 0;
    }
    $crc = $crc & 0xFF;
    $data[11] = (IsValidHex($data[11],2)) ? hex($data[11]) : -1; # das CRC Byte selbst ist ungültig

    return ErrorLog($hash, "CRC error OW device $num : $data[11] != $crc") if ($crc != $data[11]); 

    shift @data;
    shift @data;

    my $model = $hash->{helper}{OW}{$num}{typ};
    $hash->{helper}{OW}{$num}{raw} = join(' ' , @data);

    my $temp;

    if ($model ne 'unknown') {
	$temp = decodeTemperature($model, @data);
	return ErrorLog($hash,"unable to decode data $hash->{helper}{OW}{$num}{raw} for model $model") if ($temp eq '');
    }

    $temp //= $hash->{helper}{OW}{$num}{raw};

    $hash->{helper}{OW}{$num}{value} = $temp;

    if (!AttrNum($name, 'useSubDevices', 0)) {
	readingsSingleUpdate($hash, $hash->{helper}{OW}{$num}{name}, $temp, 1);
	return;
    }

    readingsSingleUpdate($hash, $hash->{helper}{OW}{$num}{name}, $temp, 0);
    Dispatch($hash, "OW,$hash->{helper}{OW}{$num}{addr},$model,$temp,$num");
    return;
}

sub decodeTemperature {

    my ($model, @data) = @_;
    my $temp = (( hex($data[1]) << 8) | hex($data[0]));

    if ($model eq 'DS1820')  {

	# heute eigentlich DS18S20 , echter alter DS1820 hat nur 0.5° Auflösung
	$temp = $temp * 0.5;
	#$temp = ($temp & 0xFFF0) +12 - hex($data[6]) if ($data[7] eq '10');
	# Alternative Berechnung :

	$temp = ($temp - 0.25) + ((hex($data[7]) - hex($data[6])) / hex($data[7])) if ($data[7] ne '00');
    }

    if (($model eq 'DS18B20') || ($model eq 'DS1822')) {

	my $cfg = (hex($data[4]) & 0x60);
	$temp  = $temp << 3 if ($cfg == 0);
	$temp  = $temp << 2 if ($cfg == 0x20);
	$temp  = $temp << 1 if ($cfg == 0x40);
	$temp  = $temp/16.0;
    }

    $temp -= 4096 if (hex($data[1]) > 127); # ToDo : testen !

    return sprintf('%.1f', $temp);
}

#####################################

sub ParseFn {

    my $shash = shift;
    my $msg   = shift // return;
    Log3($shash, 5, "ParseFn, $msg");

    my @arr   = split(',', $msg);
    return if (!defined($arr[1]) || (!IsValidHex($arr[1],16)));
    my $model = $arr[2] // return;
    my $val   = $arr[3] // return;


    if (!exists($modules{OW2S0SMSGUARD}{defptr}{$arr[1]})) {
	my $ac = (IsDisabled('autocreate')) ? 'disabled' : 'enabled' ; 
	Log3($shash, 3, "$shash->{NAME}, got message for undefined device [$arr[1]] type $arr[2] autocreate is $ac");
	return 'disable' if ($ac eq 'disabled');
	return "UNDEFINED OW_$arr[1] OW2S0SMSGUARD $arr[1] 0 $arr[2]";
    }

    my $dhash  = $modules{OW2S0SMSGUARD}{defptr}{$arr[1]};
    my $dname  = $dhash->{NAME} // return;

    Log3($dname, 4, "$dname, ParseFn $msg");

    $dhash->{busid} = $arr[4] //= -1;

    readingsBeginUpdate($dhash);

    if ($model =~ m{ ^DS18 }x) {

	readingsBulkUpdate($dhash, 'temperature', $val);

	readingsBulkUpdate($dhash, 'state',       "T: $val °C");
    }
    elsif ($model eq 'DS2401') {

	$dhash->{last_present} = TimeNow() if ($val eq 'present');
	$dhash->{last_absent}  = TimeNow() if ($val eq 'absent');
	$dhash->{last_absent}  //= '???';
	$dhash->{last_present} //= '???';

	if (ReadingsVal($dname, 'presence' ,'') ne $val) { # aber nicht bei timeout !
	    if ($val eq 'absent') {
		$dhash->{busid} = -1;
		readingsBulkUpdate($dhash, 'last_present', $dhash->{last_present});
	    }
	    readingsBulkUpdate($dhash, 'last_absent', $dhash->{last_absent}) if ($val eq 'present');
	}

	readingsBulkUpdate($dhash, 'state',    $val);
	readingsBulkUpdate($dhash, 'presence', $val);

    }
    else { readingsBulkUpdate($dhash, 'state', $val); } # bisher unbekanntes OW Device

    readingsEndUpdate($dhash,1);

    return $dname;
}

#####################################

sub UpdateReadings {

    my $hash = shift;
    my @data = split(';', shift);

    my @arr;

    my $S0A = (looks_like_number($data[1])) ? int($data[1]) : '';
    my $S0B = (looks_like_number($data[2])) ? int($data[2]) : '';
    

    Log3($hash, 5, "$hash->{NAME}, UpdateReadings data : ".join(' ',@data)); 

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'A',  $S0A) if ($S0A ne '');
    readingsBulkUpdate($hash, 'B',  $S0B) if ($S0B ne '');
    readingsBulkUpdate($hash, 'state',  "A: $S0A - B: $S0B") if (($S0A ne '') && ($S0B ne ''));
    readingsEndUpdate($hash, 1);

    #if ($hash->{DS2401}) {
    if (exists($hash->{helper}{OW}{100})) {
	$hash->{DS2401} //= '';
	readingsBeginUpdate($hash);

        foreach my $dev ( keys %{$hash->{helper}{OW}{100}} ) {
	    my $state = (index($hash->{DS2401}, $dev) != -1) ? 'present' : '';

	    if (!$state) {
		my $t = (defined($hash->{helper}{OW}{100}{$dev}{time})) ? int(gettimeofday() - time_str2num($hash->{helper}{OW}{100}{$dev}{time})) : 9999;
		my $to = AttrNum($hash->{NAME}, 'DS2401_Timeout', ($hash->{INTERVAL} * 1.5));

		ErrorLog($hash, "DS2401 timeout ($to) is smaller as your interval ($hash->{INTERVAL}) !") if ($to < $hash->{INTERVAL});
		$state = ($t > $to) ? 'absent' : 'timeout';
	    }

	    $hash->{helper}{OW}{100}{$dev}{presence} = $state;
	    readingsBulkUpdate($hash, $hash->{helper}{OW}{100}{$dev}{name}, $hash->{helper}{OW}{100}{$dev}{presence});
	    $hash->{helper}{OW}{100}{$dev}{busid} //= -1;
	    push @arr, "OW,$dev,DS2401,$hash->{helper}{OW}{100}{$dev}{presence},$hash->{helper}{OW}{100}{$dev}{busid}";
	}

	readingsBulkUpdate($hash, '.ds2401', OW_uniq($hash->{NAME}, '.ds2401', $hash->{DS2401})) if ($hash->{DS2401});
	delete $hash->{DS2401};

	if (!AttrNum($hash->{NAME}, 'useSubDevices', 0)) {
	    readingsEndUpdate($hash, 1);
	    return;
	}

	readingsEndUpdate($hash, 0);
	foreach my $dev (@arr) { Dispatch($hash, $dev); }
    }

    return;
}

#####################################

sub mapNames {

    my $hash    = shift;
    my $num     = shift // 0;
    my $address = shift // '';

    my $m = AttrVal($hash->{NAME}, 'mapOWIDs' , '');
    $hash->{helper}{OW}{$num}{name} = $hash->{helper}{OW}{$num}{addr} if ($num != 100);

    return $address if (!$m);

    $m =~ s/ //g;

    my @names = split(',', $m);

    foreach my $n (@names) {
	my ($addr,$reading) = split('=' , $n);
	if (($num != 100) && ($addr eq $hash->{helper}{OW}{$num}{addr})) {
	    $hash->{helper}{OW}{$num}{name} = $reading;
	    Log3($hash, 4, "$hash->{NAME}, found name $reading for device [$num] $addr");
	    return;
	}
	return $reading if (($num == 100) && ($addr eq $address));
    }

    return $address;
}

#####################################

sub SimpleWrite {

    my $hash = shift // return;
    my $msg  = shift // return;

    my $name = $hash->{NAME};
    Log3($name, 4, "$name, SimpleWrite: $msg");

    $msg .= "\n";

    $hash->{USBDev}->write($msg)    if ($hash->{USBDev});
    syswrite($hash->{TCPDev}, $msg) if ($hash->{TCPDev});
    syswrite($hash->{DIODev}, $msg) if ($hash->{DIODev});

    # Some linux installations are broken with 0.001, T01 returns no answer
    #select(undef, undef, undef, 0.01);
    sleep(0.01);
    return;
}

#####################################

sub OW_uniq {

    my @arr = split(',', ReadingsVal(shift, shift, ''));
    my @vals = split(',', shift);
    foreach (@vals) {push @arr, $_;}

    my @unique;
    my %h;

    foreach my $v (@arr) {
	if ( !$h{$v} ) {
	    push @unique, $v;
	    $h{$v} = 1;
	}
    }

    @arr = sort @unique;
    return join(',', @arr);
}


sub IsValidHex {

    my $d = shift;
    my $l = shift;
    return 0 if (length($d) != $l);
    for my $i (0..$l-1) {
	return 0 if (substr($d,$i,1) !~ m{ [0-9A-F] }x);
    }
    return 1;
}

#####################################

sub ErrorLog {

    my $hash  = shift;
    my $txt   = shift;
    my $level = shift // 3;

    Log3($hash, $level, "$hash->{NAME}, $txt");

    # ist readingsBulkUpdate ist aktiv ?  wird von fhem.pl gesetzt/gelöscht
    return readingsBulkUpdate($hash, 'error', $txt) if (exists($hash->{'.updateTimestamp'}));
    return readingsSingleUpdate($hash, 'error', $txt, 1);
}


1;

__END__

=pod
=over
=encoding utf8

=item summary Module for SMS USB Guard
=item summary_DE Modul für SMS USB Guard
=begin html

<a name="OW2S0SMSGUARD"></a>
<h3>OW2SMSGUARD.</h3>

FHEM Forum : <a href='https://forum.fhem.de/index.php/topic,28447.0.html'>1Wire</a><br>

 <a name="OW2S0SMSGUARDdefine"></a>
 <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OW2S0SMSGUARD &lt;IO Device&gt; [interval]</code><br><br>
    Example :<br><code>
    define myOW2S0 OW2S0SMSGUARD /dev/ttyUSB0@38400<br>
    define myOW2S0 OW2S0SMSGUARD /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A702PE1J-if00-port0@38400<br>
    define myOW2S0 OW2S0SMSGUARD 192.168.0.100:2000 (socat, ser2net)</code><br>
  </ul>

  <br>
  <a name="OW2S0SMSGUARDset"></a>
  <b>Set</b>
    <a name="reset"></a><li>reset IO device ( master only )</li><br>
    <a name="S0-reset"></a><li>S0-reset : reset of both S0 counters ( master only )</li><br>
    <a name="deleteDS2401"></a><li>deleteDS2401 : deletes reading and defined sub device ( master only )</li><br>

  <a name="OW2S0SMSGUARDget"></a>
  <b>Get</b>
    <a name="OWdeviceList"></a><li>list of found OW devices ( master only )</li><br>

  <a name="OW2S0SMSGUARDattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="mapOWIDs"></a><li>mapOWIDs ( master only )<br>
    Comma separeted list of ID=Name pairs<br>
    Example : <code>10D64CBF02080077=Badezimmer, 01E5D9370B00005D=Kellerfenster</code></li>
  </ul>
  <ul>
    <a name="model"></a><li>model<br>
     only for FHEM modul statistics at <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a></li>
 </ul>
  <ul>
    <a name="useSubDevices"></a><li>useSubDevices ( master only ) , default 0<br>
    create for each found device on the bus a separate subdevice<br></li>
  </ul>
 <ul>
    <a name="delay"></a><li>delay ( master only ) ,  default 0.5 seconds to read OW device values </li><br>
 </ul>

=end html

=begin html_DE

<a name="OW2S0SMSGUARD"></a>
<h3>OW2S0SMSGUARD.</h3>
1-wire USB Master von sms-guard.org
FHEM Forum : <a href='https://forum.fhem.de/index.php/topic,28447.0.html'>1Wire</a><br>

 <a name="OW2S0SMSGUARDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OW2S0SMSGUARD &lt;IO Device&gt; [interval]</code><br>
    Beispiel :<br><code>
    define myOW2S0 OW2S0SMSGUARD /dev/ttyUSB0@38400<br>
    define myOW2S0 OW2S0SMSGUARD /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A702PE1J-if00-port0@38400<br>
    define myOW2S0 OW2S0SMSGUARD 192.168.0.100:2000 (socat, ser2net)</code><br>

  </ul>

  <br>
  <a name="OW2S0SMSGUARDset"></a>
  <b>Set</b>
    <a name="reset"></a><li>reset IO Device ( nur Master Device )</li><br>
    <a name="S0-reset"></a><li>S0-resets ( nur Master Device )<br>
    setzt die beiden internen S0 Zähler ( A & B) auf 0 zurück</li><br>
    <a name="deleteDS2401"></a><li>deleteDS2401 ( nur Master Device )<br>
    löscht das das Reading und falls definiert auch das dazugehörige Sub-Device (siehe Attr useSubDevice)</li><br>
 
  <a name="OW2S0SMSGUARDget"></a>
  <b>Get</b>
    <a name="OWdeviceList"></a><li>OWdeviceList<br>
    Liste der aktuell gefunden OW Geräte ( nur Master Device )</li><br>

  <a name="OW2S0SMSGUARDattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="mapOWIDs"></a><li>mapOWIDs<br>
    Kommata getrennte Liste von ID=Name Paaren<br>
    Beispiel : <code>10D64CBF02080077=Badezimmer, 01E5D9370B00005D=Kellerfenster</code><br>
    Statt der OW ID wird Name als Reading verwendet.( nur Master Device )</li>
  </ul>
  <ul>
    <a name="model"></a><li>model<br>
    nur f&uuml;r die FHEM Modul Statistik unter <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a></li>
  </ul>
  <ul>
    <a name="useSubDevices"></a><li>useSubDevices ( nur Master Device ) , default 0<br>
    Legt für jedes gefundene Device am 1-W Bus ein eigenes extra Device an<br></li>
  </ul>
  <ul>
    <a name="delay"></a><li>delay ( nur Master Device ) , default 0.5 Sekukunden<br>
    Wartezeit in Sekunden zwischen dem Auslesen der Temperaturwerte wenn mehr als ein DS18XX am OW Bus angeschlosen ist</li><br>
   </ul>

=end html_DE

=for :application/json;q=META.json 00_OW2S0SMSGUARD.pm

{
  "abstract": "Module for 2 S0 counter and 1-wire USB Master from SMS-Guard.org",
  "x_lang": {
    "de": {
      "abstract": "Modul für zwei S0 counter and 1-wire USB Master von SMS-Guard.org"
    }
  },
  "keywords": [
    "S0",
    "One Wire",
    "counter",
    "1W"
  ],
  "version": "2.0",
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
        "Time::HiRes": 0
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
