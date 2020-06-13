# $Id: 10_MAX.pm 21928 2020-05-13 15:52:58Z Wzut $
# 
#  (c) 2019 Copyright: Wzut
#  (c) 2012 Copyright: Matthias Gehre, M.Gehre@gmx.de
#
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/board,23.0.html
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
# 2.0.0  =>  28.03.2020
# 1.0.0"  => (c) M.Gehre
################################################################

package FHEM::MAX;  ## no critic 'package'
# das no critic könnte weg wenn die Module nicht mehr zwingend mit NN_ beginnnen müssen

use strict;
use warnings;
#use utf8;
use Date::Parse;
#use Carp qw(croak carp);
use Time::HiRes qw(gettimeofday);
use Time::Local;
use GPUtils qw(GP_Import GP_Export); # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use AttrTemplate;
use Data::Dumper;

BEGIN
{
    # Import from main::
    GP_Import(
	qw(
	attr
	AttrVal
	AttrNum
	AttrTemplate_Set
	AssignIoPort
	CommandAttr
	CommandDeleteAttr
	CommandRename
	CommandSet
	defs
	devspec2array
	deviceEvents
	FileRead
	FileWrite
	init_done
	InternalTimer
	InternalVal
	RemoveInternalTimer
	IsDisabled
	IsIgnored
	IsDummy
	Log3
	modules
	readingsSingleUpdate
	readingsBulkUpdate
	readingsBeginUpdate
	readingsDelete
	readingsEndUpdate
	readingFnAttributes
	ReadingsNum
	ReadingsVal
	ReadingsAge
	setReadingsVal
	TimeNow
	configDBUsed
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
  8 => 'PlugAdapter'
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

my @ctrl_modes = ( 'auto', 'manual', 'temporary', 'boost' );

my %boost_durations = (0 => 0, 1 => 5, 2 => 10, 3 => 15, 4 => 20, 5 => 25, 6 => 30, 7 => 60);

my %boost_durationsInv = reverse %boost_durations;

my %decalcDays    = (0 => 'Sat', 1 => 'Sun', 2 => 'Mon', 3 => 'Tue', 4 => 'Wed', 5 => 'Thu', 6 => 'Fri');

my @weekDays      = ('Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri');

my %decalcDaysInv = reverse %decalcDays;

my %readingDef = ( #min/max/default
  'maximumTemperature'    => [ \&validTemperature, 'on' ],
  'minimumTemperature'    => [ \&validTemperature, 'off' ],
  'comfortTemperature'    => [ \&validTemperature, 21 ],
  'ecoTemperature'        => [ \&validTemperature, 17 ],
  'windowOpenTemperature' => [ \&validTemperature, 12 ],
  'windowOpenDuration'    => [ \&validWindowOpenDuration, 15 ],
  'measurementOffset'     => [ \&validMeasurementOffset, 0 ],
  'boostDuration'         => [ \&validBoostDuration, 5 ],
  'boostValveposition'    => [ \&validValvePosition, 80 ],
  'decalcification'       => [ \&validDecalcification, 'Sat 12:00' ],
  'maxValveSetting'       => [ \&validValvePosition, 100 ],
  'valveOffset'           => [ \&validValvePosition, 0 ],
  'groupid'               => [ \&validGroupId, 0 ],
  '.weekProfile'          => [ \&validWeekProfile, $defaultWeekProfile ]
 );

# Identify for numeric values and maps "on" and "off" to their temperatures
sub validTemperature        { my $v=shift; return $v eq 'on' || $v eq 'off' || ($v =~ /^\d+(\.[05])?$/x && $v >= 4.5 && $v <= 30.5); }
# Identify for numeric values and maps 'on' and 'off' to their temperatures
sub ParseTemperature        { my $v=shift; return $v eq 'on' ? 30.5 : ($v eq 'off' ? 4.5 :$v); }
sub validWindowOpenDuration { my $v=shift; return $v =~ /^\d+$/x && $v >= 0 && $v <= 60; }
sub validMeasurementOffset  { my $v=shift; return $v =~ /^-?\d+(\.[05])?$/x && $v >= -3.5 && $v <= 3.5; }
sub validBoostDuration      { my $v=shift; return $v =~ /^\d+$/x && exists($boost_durationsInv{$v}); }
sub validValvePosition      { my $v=shift; return $v =~ /^\d+$/x && $v >= 0 && $v <= 100; }
sub validWeekProfile        { my $v=shift; return length($v) == 364; }
sub validGroupId            { my $v=shift; return $v =~ /^\d+$/x && $v >= 0 && $v <= 255; }

sub MAX_uniq {

    my @arr = split(',', ReadingsVal(shift, shift, ''));
    push @arr , shift;

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

sub validDecalcification {
    my $v = shift;
    my ($decalcDay, $decalcHour) = ($v =~ /^(...)\s(\d{1,2}):00$/x);
    return defined($decalcDay) && defined($decalcHour) && exists($decalcDaysInv{$decalcDay}) && 0 <= $decalcHour && $decalcHour < 24; 
}

sub Log3Return {
    my $name  = shift;
    my $msg   = shift;
    my $level = shift // 3;
    Log3($name, $level, "$name, $msg");
    return $msg;
};

sub Initialize {

    my $hash = shift;

    $hash->{Match}         = '^MAX';
    $hash->{DefFn}         = \&FHEM::MAX::Define;
    $hash->{UndefFn}       = \&FHEM::MAX::Undef;
    $hash->{ParseFn}       = \&FHEM::MAX::Parse;
    $hash->{SetFn}         = \&FHEM::MAX::Set;
    $hash->{GetFn}         = \&FHEM::MAX::Get;
    $hash->{RenameFn}      = \&FHEM::MAX::RenameFn;
    $hash->{NotifyFn}      = \&FHEM::MAX::Notify;
    $hash->{DbLog_splitFn} = \&FHEM::MAX::DbLog_splitFn;
    $hash->{AttrFn}        = \&FHEM::MAX::Attr;
    $hash->{AttrList}      = 'IODev CULdev actCycle do_not_notify:1,0 ignore:0,1 dummy:0,1 keepAuto:0,1 debug:0,1 '
			    .'scanTemp:0,1 skipDouble:0,1 externalSensor '
			    .'model:Cube,HeatingThermostat,HeatingThermostatPlus,WallMountedThermostat,ShutterContact,PushButton,PlugAdapter,virtualShutterContact,virtualThermostat '
			    .'autosaveConfig:0,1 peers sendMode:peers,group,Broadcast dTempCheck:0,1 '
			    .'windowOpenCheck:0,1 DbLog_log_onoff:0,1 '
			    .$readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash ) if ($hasmeta);

    return;
}

#############################

sub Define {

    my $hash = shift;
    my $def  = shift;

    my ($name, undef, $type, $addr) = split(m{ \s+ }xms, $def, 4);

    return "name $name is reserved for internal use" if (($name eq 'fakeWallThermostat') || ($name eq 'fakeShutterContact'));

    my $devtype = MAX_TypeToTypeId($type);

    return "$name, invalid MAX type $type !" if ($devtype < 0);
    return "$name, invalid address $addr !"  if (($addr !~ m{\A[a-fA-F0-9]{6}\z}xms) || ($addr eq '000000'));

    $addr = lc($addr); # all addr should be lowercase

 
    if (exists($modules{MAX}{defptr}{$addr}) && $modules{MAX}{defptr}{$addr}->{NAME} ne $name) {
	my $dead = '';
	foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	    $dead .= $dev.',' if (!$modules{MAX}{defptr}{$dev}->{NAME});
	}
	Log3($name, 2 ,"$name, found incomplete MAX devices : $dead") if ($dead);
	my $msg = "$name, a MAX device with address $addr is already defined as ".$modules{MAX}{defptr}{$addr}->{NAME};
	#Log3($name, 2, $msg);
	return $msg;
    }
 
    my $old_addr = '';

    # check if we have this address already in use
    foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	next if (!$modules{MAX}{defptr}{$dev}->{NAME});
	$old_addr = $dev if  ($modules{MAX}{defptr}{$dev}->{NAME} eq $name);
	last if ($old_addr); # device found
    }

    if (($old_addr ne '') && ($old_addr ne $addr)){
	my $msg1 = 'please dont change the address direct in DEF or RAW !';
        my $msg2 = "If you want to change $old_addr please delete device $name first and create a new one";
	Log3($name, 3, "$name, $msg1 $msg2");
	return $msg1."\n".$msg2;
    }

    if (exists($modules{MAX}{defptr}{$addr}) && $modules{MAX}{defptr}{$addr}->{type} ne $type) {
	my $msg = "$name, type changed from $modules{MAX}{defptr}{$addr}->{type} to $type !";
	Log3($name, 2, $msg);
    }

    $hash->{type}                = $type;
    $hash->{devtype}             = $devtype;
    $hash->{addr}                = $addr;
    #$hash->{STATE}               = 'waiting for data';
    $hash->{TimeSlot}            = -1 if ($type =~ m{Thermostat}xms); # wird durch CUL_MAX neu gesetzt 
    $hash->{'.count'}            = 0; # ToDo Kommentar
    $hash->{'.sendToAddr'}       = '-1'; # zu wem haben wird direkt gesendet ?
    $hash->{'.sendToName'}       = '';
    $hash->{'.timer'}            = 300 if (($type ne 'PushButton') && ($type ne 'Cube'));
    $hash->{SVN}                 = (qw($Id: 10_MAX.pm 21928 2020-05-13 15:52:58Z Wzut $))[2];
    $modules{MAX}{defptr}{$addr} = $hash;

    CommandAttr(undef,"$name model $type"); # Forum Stats werten nur attr model aus

    if (($init_done == 1) && (($hash->{devtype} > 0) && ($hash->{devtype} < 4) || ($type eq 'virtualThermostat'))) {
	#nur beim ersten define setzen:
	readingsBeginUpdate($hash);
    	MAX_ReadingsVal($hash, 'groupid');
    	MAX_ReadingsVal($hash, 'windowOpenTemperature') if ($type eq 'virtualThermostat');
    	MAX_ParseWeekProfile($hash);
    	readingsEndUpdate($hash, 0);

	my ($io) = devspec2array('TYPE=CUL_MAX');
	($io)    = devspec2array('TYPE=MAXLAN') if (!$io);
	$attr{$name}{IODev} = $io  if (!exists($attr{$name}{IODev}) && $io);
	$attr{$name}{room} = 'MAX' if (!exists($attr{$name}{room}));
    }

    if ($type ne 'Cube') {
	AssignIoPort($hash);
    }
    else {
	CommandAttr(undef, "$name dummy 1");
	CommandDeleteAttr(undef, "$name IODev") if (exists($attr{$name}{IODev}));
    }

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, 'FHEM::MAX::OnTimer', $hash, 0) if (($type ne 'PushButton') && ($type ne 'Cube'));

    if ($hasmeta) {
	return $@ unless ( FHEM::Meta::SetInternals($hash) )
    }

    return;
}


sub OnTimer {

    my $hash = shift;
    my $name = $hash->{NAME};

    if (!$init_done) {
	InternalTimer(gettimeofday()+5, 'FHEM::MAX::OnTimer', $hash, 0);
	return;
    }

    $hash->{'.timer'} //= 0;

    return if ((int($hash->{'.timer'}) < 60) || IsDummy($name) || IsIgnored($name));

    InternalTimer(gettimeofday() + $hash->{'.timer'}, 'FHEM::MAX::OnTimer', $hash, 0);

    if (exists($hash->{IODevMissing})) {
	Log3($name, 1, "$name, Missing IODEV, call AssignIOPort");
	AssignIoPort($hash);
    }

    if (($hash->{type} =~ m{Thermostat}xms) || ($hash->{type} eq 'PlugAdapter')) {
	my $dt = ReadingsNum($name, 'desiredTemperature', 0);
	if ($dt == ReadingsNum($name, 'windowOpenTemperature', '0')) { # kein check bei offenen Fenster
   
	    my $age = sprintf '%02d:%02d', (gmtime(ReadingsAge($name, 'desiredTemperature', 0)))[2,1];
	    readingsSingleUpdate($hash,'windowOpen', $age, 1) if (AttrNum($name, 'windowOpenCheck', 0));
	    $hash->{'.timer'} = 60;
	    return;
	}

	if ((ReadingsVal($name, 'mode', 'manu') eq 'auto') && AttrNum($name, 'dTempCheck', 0)) {
	    MAX_ParseWeekProfile($hash, 1); # $hash->{helper}{dt} aktualisieren

	    my $c = ($dt != $hash->{helper}{dt}) ? sprintf('%.1f', ($dt-$hash->{helper}{dt})) : 0;
	    delete $hash->{helper}{dtc} if (!$c && exists($hash->{helper}{dtc}));
	    if ($c && (!exists($hash->{helper}{dtc}))) {
		$hash->{helper}{dtc} = 1;
		$c = 0; 
	    }; # um eine Runde verzögern

	    readingsBeginUpdate($hash);
	    readingsBulkUpdate($hash, 'dTempCheck', $c);
	    readingsBulkUpdate($hash, 'windowOpen', '0') if (AttrNum($name, 'windowOpenCheck', 0));
	    readingsEndUpdate($hash, 1);
	    $hash->{'.timer'} = 300;
	    Log3($hash, 3, "name, Tempcheck NOK Reading : $dt <-> WeekProfile : $hash->{helper}{dt}") if ($c);
	}
	return;
    }

    if (($hash->{type} =~ m{ShutterContact\z}xms) && AttrNum($name, 'windowOpenCheck', 1)) {
	if (ReadingsNum($name, 'onoff', 0)) {
	    my $age = (sprintf '%02d:%02d', (gmtime(ReadingsAge($name, 'onoff', 0)))[2,1]);
	    readingsSingleUpdate($hash, 'windowOpen', $age, 1);
	    $hash->{'.timer'} = 60;
	}
	else  {
	    readingsSingleUpdate($hash, 'windowOpen', '0', 1);
	    $hash->{'.timer'} = 300;
	}
    }
    return;
}


sub Attr {

    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    if ($cmd eq 'del') {

	return 'FHEM statistics are using this, please do not delete or change !' if ($attrName eq 'model');
	$hash->{'.actCycle'} = 0 if ($attrName eq 'actCycle');
	if ($attrName eq 'externalSensor') {
	    delete($hash->{NOTIFYDEV}); 
	    notifyRegexpChanged($hash, 'global');
	}
	return;
    }

    if ($cmd eq 'set') {
	if ($attrName eq 'model') {
	    return "$name, model is $hash->{type}" if ($attrVal ne $hash->{type});
	}

	if ($attrName eq 'dummy') {
	    $attr{$name}{scanTemp}  = '0' if (AttrNum($name, 'scanTemp', 0) && int($attrVal));
	}
  
	if ($attrName eq 'CULdev') {
	    # ohne Abfrage von init_done : Reihenfoleproblem in der fhem.cfg !
	    return "$name, invalid CUL device $attrVal" if (!exists($defs{$attrVal}) && $init_done);
	}

	if ($attrName eq 'actCycle') {
	    my @ar = split(':',$attrVal);
	    $ar[0] = 0 if (!$ar[0]);
	    $ar[1] = 0 if (!$ar[1]);
	    my $v = (int($ar[0])*3600) + (int($ar[1])*60);
	    $hash->{'.actCycle'} = $v if ($v >= 0);
	} 

	if ($attrName eq 'externalSensor') {
	    return $name.', attribute externalSensor is not supported for this device !' if ($hash->{devtype} > 2) && ($hash->{devtype} < 6);
	    my ($sd, $sr, $sn) = split (':', $attrVal);
	    if ($sd && $sr && $sn) {
		notifyRegexpChanged($hash, "$sd:$sr");
		$hash->{NOTIFYDEV}=$sd;
	    }
	}
    }
    return;
}

sub Undef {
    my $hash = shift;
    delete($modules{MAX}{defptr}{$hash->{addr}});
    return;
}

sub MAX_TypeToTypeId {
    my $type = shift;
    foreach my $id (keys %device_types) {
	return $id if ($type eq $device_types{$id});
    }
    return -1;
}

sub MAX_CheckIODev {

    my $hash = shift;
    return 'device has no valid IODev' if (!exists($hash->{IODev}));
    return 'device IODev has no TYPE' if (!exists($hash->{IODev}{TYPE}));
    return 'device IODev TYPE must be CUL_MAX or MAXLAN' if ($hash->{IODev}{TYPE} ne 'MAXLAN' && $hash->{IODev}{TYPE} ne 'CUL_MAX');
    return 'can not send a command with this IODev (missing IODev->Send)'  if (!exists($hash->{IODev}{Send}));
    return  $hash->{IODev}{TYPE};
}


sub MAX_SerializeTemperature {
    # Print number in format "0.0", pass "on" and "off" verbatim, convert 30.5 and 4.5 to "on" and "off"
    # Used for "desiredTemperature", "ecoTemperature" etc. but not "temperature"

    my $t = shift;
    #return $t    if ( ($t eq 'on') || ($t eq 'off') );
    #return $t if ($t =~ /\D/);
    return 'off' if ( $t eq  '4.5' );
    return 'on'  if ( $t eq '30.5' );
    return $t if ($t =~ /\D/);
    return sprintf('%2.1f', $t);
}

sub MAX_Validate {
    my $name = shift;
    my $val  = shift // 999;
    return 0 if (!exists($readingDef{$name}));
    return $readingDef{$name}[0]->($val);
}


sub MAX_ReadingsVal {
    # Get a reading, validating it's current value (maybe forcing to the default if invalid)
    # "on" and "off" are converted to their numeric values

    my $hash    = shift;
    my $reading = shift;
    my $newval  = shift // '';
    my $name    = $hash->{NAME};

    my $bulk = (exists($hash->{'.updateTimestamp'})) ? 1 : 0;  # readingsBulkUpdate ist aktiv, wird von fhem.pl gesetzt/gelöscht

    if ($newval ne '') {
	($bulk) ? readingsBulkUpdate($hash, $reading, $newval) : readingsSingleUpdate($hash, $reading, $newval, 1);
	return;
    }

    my $val = ReadingsVal($name, $reading, '');
    # $readingDef{$name} array is [validatingFunc, defaultValue]
    if (exists($readingDef{$reading}) && (!$readingDef{$reading}[0]->($val))) {
	#Error: invalid value
	my $err = "invalid or missing value $val for READING $reading";
	$val = $readingDef{$reading}[1];
	Log3($name, 3, "$name, $err , forcing to $val");

	# Save default value to READINGS
	readingsBeginUpdate($hash) if (!$bulk);
	readingsBulkUpdate($hash, $reading, $val);
	readingsBulkUpdate($hash, 'error', $err);
	readingsEndUpdate($hash,0) if (!$bulk);
    }

    return ParseTemperature($val);
}

sub MAX_ParseWeekProfile {

    my $hash     = shift;
    my $readOnly = shift // 0; # 0 = alle Readings neu setzen , 1 = nur lesen
    $hash->{helper}{dt} = -1; # noch keine gueltige Soll Temperatur gefunden
    my @lines;

    # Format of weekprofile: 16 bit integer (high byte first) for every control point, 13 control points for every day
    # each 16 bit integer value is parsed as
    # int time = (value & 0x1FF) * 5;
    # int hour = (time / 60) % 24;
    # int minute = time % 60;
    # int temperature = ((value >> 9) & 0x3F) / 2;

    my $curWeekProfile = MAX_ReadingsVal($hash, '.weekProfile');

    my (undef,$min,$hour,undef,undef,undef,$wday) = localtime(gettimeofday());
    # (Sun,Mon,Tue,Wed,Thu,Fri,Sat) -> localtime
    # (Sat,Sun,Mon,Tue,Wed,Thu,Fri) -> MAX intern
    $wday++; # localtime = MAX Day;
    $wday -= 7 if ($wday > 6);
    my $daymins = ($hour*60)+$min; 

    #parse weekprofiles for each day
    for (my $i=0; $i<7; $i++) {
	$hash->{helper}{myday} = $i if ($i == $wday);

	my (@time_prof, @temp_prof);
	for(my $j=0; $j<13; $j++) {
	    $time_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))& 0x1FF) * 5;
	    $temp_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))>> 9 & 0x3F ) / 2;
	}

	my @hours;
	my @minutes;
	my $j; # ToDo umschreiben ! 

	for ($j=0; $j<13; $j++) {
	    $hours[$j] = ($time_prof[$j] / 60 % 24);
	    $minutes[$j] = ($time_prof[$j]%60);
	    # if 00:00 reached, last point in profile was found

	    if (int($hours[$j]) == 0 && int($minutes[$j]) == 0) {
		$hours[$j] = 24;
		last;
	    }
	}

	my $time_prof_str = '00:00';
	my $temp_prof_str;
	my $line ='';
	my $json_ti ='';
	my $json_te ='';

	for (my $k=0; $k<=$j; $k++) {
	    $time_prof_str .= sprintf('-%02d:%02d', $hours[$k], $minutes[$k]);
	    $temp_prof_str .= sprintf('%2.1f °C', $temp_prof[$k]);

	    my $t = (sprintf('%2.1f', $temp_prof[$k])+0);
	    $line .=  $t.',';
	    $json_te .= "\"$t\"";

	    $t = sprintf('%02d:%02d', $hours[$k], $minutes[$k]);
	    $line .=  $t;
	    $json_ti .= "\"$t\"";

            # Finde die Soll Temperatur die jetzt aktuell ist
	    if (($i == $wday) && (((($hours[$k]*60)+$minutes[$k]) > $daymins) && ($hash->{helper}{dt} < 0))) {
		# der erste Schaltpunkt in der Zukunft ist 
		$hash->{helper}{dt} = sprintf('%.1f', $temp_prof[$k]);
	    }
 
	    if ($k < $j) {
		$time_prof_str .= '  /  ' . sprintf('%02d:%02d', $hours[$k], $minutes[$k]);
		$temp_prof_str .= '  /  ';
		$line .= ','; 
		$json_ti .= ',';
		$json_te .= ',';
	    }
	}

	if (!$readOnly) {
	    readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-time", $time_prof_str );
	    readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-temp", $temp_prof_str );
	}
	else {
	    push @lines , "set $hash->{NAME} weekProfile $decalcDays{$i} $line" if ($hash->{devtype} != 7);
	    push @lines , "setreading $hash->{NAME} weekprofile-$i-$decalcDays{$i}-time $time_prof_str";
	    push @lines , "setreading $hash->{NAME} weekprofile-$i-$decalcDays{$i}-temp $temp_prof_str";
	    push @lines , '"'.$decalcDays{$i}.'":{"time":['.$json_ti.'],"temp":['.$json_te.']}';
	}
    }

    return @lines;
}

#############################

sub Get {

    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // '?';
    my $dev  = shift // '';

    return if (IsDummy($name) || IsIgnored($name) || ($hash->{devtype} == 6));

    my $backuped_devs = MAX_BackupedDevs($name);

    return  if (!$backuped_devs);

    return "$name, get show_savedConfig : missing device name !" if (($cmd eq 'show_savedConfig') && !$dev);

    if ($cmd eq 'show_savedConfig') {
	my $ret;
	my $dir = AttrVal('global', 'logdir', './log/');
	$dir .='/' if ($dir  !~ m{\/\z}x);

	my ($error, @lines) = FileRead($dir.$dev.'.max');
	return $error if ($error);
	foreach my $line (@lines) { 
	    $ret .= $line."\n";
	}
	return $ret;
    }

    return "unknown argument $cmd , choose one of show_savedConfig:$backuped_devs";
}

sub Set {

    my ($hash, $devname, $cmd, @args) = @_;
    $cmd  // return "set $devname needs at least one argument !";

    my $ret = '';
    my $devtype = int($hash->{devtype});

    return if (IsDummy($devname) 
	   || IsIgnored($devname) 
           || !$devtype 
           || ($cmd eq 'valveposition')
	   || (($cmd eq 'temperature') && ($devtype != 7))
	    );

    return set_FW_HTML($hash, '?') if ($cmd eq '?');

    my $sets = {
		'ecoTemperature'           => \&_handle_ConfigTemperature ,
		'comfortTemperature'       => \&_handle_ConfigTemperature ,
		'measurementOffset'        => \&_handle_ConfigTemperature ,
		'maximumTemperature'       => \&_handle_ConfigTemperature ,
		'minimumTemperature'       => \&_handle_ConfigTemperature ,
		'windowOpenTemperature'    => \&_handle_ConfigTemperature ,
		'windowOpenDuration'       => \&_handle_ConfigTemperature ,
		'boostDuration'            => \&_handle_ConfigValve ,
		'boostValveposition'       => \&_handle_ConfigValve ,
		'decalcification'          => \&_handle_ConfigValve ,
		'maxValveSetting'          => \&_handle_ConfigValve ,
		'valveOffset'              => \&_handle_ConfigValve ,
		'desiredTemperature'       => \&_handle_SetTemperature ,
		'weekProfile'              => \&_handle_SetWeekProfile ,
		'displayActualTemperature' => \&_handle_SetDisplay ,
		'groupid'                  => \&_handle_SetGroupId ,
		'open'                     => \&_handle_SetOpenClose ,
		'close'                    => \&_handle_SetOpenClose ,
		'associate'                => \&_handle_Peering ,
		'deassociate'              => \&_handle_Peering ,
		'factoryReset'             => \&_handle_Peering ,
		'wakeUp'                   => \&_handle_WakeUp,
		'?'                        => \&set_FW_HTML
		};

    if (($cmd eq 'mode') && @args) {
	@args = ('manual' ,'30.5') if ($args[0] eq 'on');
	@args = ('manual' , '4.5') if ($args[0] eq 'off');
	@args = ('auto')           if ($args[0] eq 'auto');
	$cmd = 'desiredTemperature';
    }

    if (($cmd eq 'export_Weekprofile') && ReadingsVal($devname, '.wp_json', '')) {
	return CommandSet(undef, $args[0].' profile_data '.$devname.' '.ReadingsVal($devname,'.wp_json',''));
    }

    return _saveConfig($devname, $cmd, @args) if ($cmd eq 'saveConfig');

    return MAX_Save('all') if ($cmd eq 'saveAll');

    return readingsSingleUpdate($hash, 'temperature', $args[0], 1) if (($cmd eq 'temperature') && ($devtype == 7));


    if (($cmd eq 'restoreReadings') || ($cmd eq 'restoreDevice')) {
	my $f = $args[0];
	$args[0] =~ s/(.)/sprintf('%x', ord($1))/egx;
	return if (!$f || ($args[0] eq 'c2a0'));
	return MAX_Restore($devname, $cmd, $f);
    }

    return CommandRename(undef, "$devname $args[0]") if (($cmd eq 'deviceRename') && @args);

    # ab jetzt wird zwingend ein IO Dev gebraucht

    my $error = MAX_CheckIODev($hash);

    return Log3Return($devname, $error, 2) if (($error ne 'CUL_MAX') && ($error ne 'MAXLAN'));

    return $sets->{$cmd}->($hash, $cmd, @args) if ( ref $sets->{$cmd} eq 'CODE');

    return set_FW_HTML($hash, $cmd, @args);

}

sub MAX_Save {

    my $dev = shift // 'all';

    if ($dev eq 'all') {
	my   $list = join(',', map { defined($_->{type}) && $_->{type} =~ m{Thermostat}x ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
	my @ar = split(',' , $list);
	foreach my $dev (@ar) {
	    _saveConfig($dev);
	}
    }
    else { 
	return _saveConfig($dev);
    }

    return;
}

sub _saveConfig {
    my $name    = shift;
    my $cmd     = shift;
    my @args    = shift;
    my $fname   = $args[0] // $name;

    my $hash    = $defs{$name};
    my $devtype = int($hash->{devtype});
    my $dir     = AttrVal('global', 'logdir', './log/');
    $dir .='/' if ($dir  !~ m{\/\z}xms);
    my @lines;
    my %h;

    if (($devtype && ($devtype < 4)) || ($devtype == 8)) { # HT , HT+ , WT

	$h{'21comfortTemperature'}       = MAX_ReadingsVal($hash, 'comfortTemperature');
	$h{'22.comfortTemperature'}      = $h{'21comfortTemperature'};
	$h{'23.ecoTemperature'}          = MAX_ReadingsVal($hash, 'ecoTemperature');
	$h{'25.maximumTemperature'}      = MAX_ReadingsVal($hash, 'maximumTemperature');
	$h{'27.minimumTemperature'}      = MAX_ReadingsVal($hash, 'minimumTemperature');
	$h{'29.measurementOffset'}       = MAX_ReadingsVal($hash, 'measurementOffset');
	$h{'31.windowOpenTemperature'}   = MAX_ReadingsVal($hash, 'windowOpenTemperature');
	$h{'00groupid'}                  = MAX_ReadingsVal($hash, 'groupid');
	$h{'01.groupid'}                 = $h{'00groupid'};
	$h{'02.SerialNr'}                = ReadingsVal($name, 'SerialNr', '???');
	$h{'03.firmware'}                = ReadingsVal($name, 'firmware', '???');
	$h{'09'}                         = '#';
	$h{'50..weekProfile'}            = MAX_ReadingsVal($hash, '.weekProfile');
	$h{'96.peerIDs'}                 = ReadingsVal($name, 'peerIDs', '???');
	$h{'97.peerList'}                = ReadingsVal($name, 'peerList', '???');
	$h{'98.peers'}                   = ReadingsVal($name, 'peers', '???');
	$h{'99.PairedTo'}                = ReadingsVal($name, 'PairedTo', '???');
	$h{'35displayActualTemperature'} = ReadingsVal($name, 'displayActualTemperature', '???') if ($devtype == 3);
	$h{'36.displayActualTemperature'}= $h{'35displayActualTemperature'} if ($devtype == 3);
	$h{'59'}                         = '#';
	$h{'61.temperature'}             = MAX_ReadingsVal($hash, 'temperature');
	$h{'69'}                         = '#';
    }

    if (($devtype == 1) || ($devtype == 2) || ($devtype == 8)) { # HT , HT+
 
	$h{'10decalcification'}     = MAX_ReadingsVal($hash, 'decalcification');
	$h{'11.decalcification'}    = $h{'10decalcification'};
	$h{'12.boostDuration'}      = MAX_ReadingsVal($hash, 'boostDuration');
	$h{'13.boostValveposition'} = MAX_ReadingsVal($hash, 'boostValveposition');
	$h{'14.maxValveSetting'}    = MAX_ReadingsVal($hash, 'maxValveSetting');
	$h{'15.valveOffset'}        = MAX_ReadingsVal($hash, 'valveOffset');
	$h{'20'}                    = '#';
	$h{'33.windowOpenDuration'} = MAX_ReadingsVal($hash,'windowOpenDuration');
	$h{'39'}                    = '#';
    }

    if ($devtype == 4) { # SC
	$h{'00groupid'}      = MAX_ReadingsVal($hash, 'groupid');
	$h{'01.groupid'}     = $h{'00groupid'};
	$h{'02.SerialNr'}    = ReadingsVal($name, 'SerialNr', '???');
	$h{'03.firmware'}    = ReadingsVal($name, 'firmware', '???');
	$h{'96.peerIDs'}     = ReadingsVal($name, 'peerIDs',  '???');
	$h{'97.peerList'}    = ReadingsVal($name, 'peerList', '???');
	$h{'98.peers'}       = ReadingsVal($name, 'peers',    '???');
	$h{'99.PairedTo'}    = ReadingsVal($name, 'PairedTo', '???');
    }

    if ($devtype == 5) { # PushButton
	$h{'02.SerialNr'}    = ReadingsVal($name, 'SerialNr', '???');
	$h{'03.firmware'}    = ReadingsVal($name, 'firmware', '???');
	$h{'99.PairedTo'}    = ReadingsVal($name, 'PairedTo', '???');
    }

    if (($devtype == 6) || ($devtype == 7)) { # virtual
	$h{'00.groupid'}     = MAX_ReadingsVal($hash, 'groupid');
	$h{'96.peerIDs'}     = ReadingsVal($name, 'peerIDs',  '???');
	$h{'97.peerList'}    = ReadingsVal($name, 'peerList', '???');
    }

    if ($devtype == 7) { # vWT
	$h{'12.boostDuration'}         = MAX_ReadingsVal($hash, 'boostDuration');
	$h{'21.comfortTemperature'}    = MAX_ReadingsVal($hash, 'comfortTemperature');
	$h{'23.ecoTemperature'}        = MAX_ReadingsVal($hash, 'ecoTemperature');
	$h{'25.maximumTemperature'}    = MAX_ReadingsVal($hash, 'maximumTemperature');
	$h{'27.minimumTemperature'}    = MAX_ReadingsVal($hash, 'minimumTemperature');
	$h{'29.measurementOffset'}     = MAX_ReadingsVal($hash, 'measurementOffset');
	$h{'31.windowOpenTemperature'} = MAX_ReadingsVal($hash, 'windowOpenTemperature');
	$h{'50..weekProfile'}          = MAX_ReadingsVal($hash, '.weekProfile');
    }

    foreach my $val (sort keys %h) {
	next if (!defined($h{$val}) || (defined($h{$val}) && ($h{$val} eq '???')));

	if ($h{$val} eq '#') {
	    push @lines,'##############################################';
	    next;
	}
	my $r = substr($val,2,length($val)); # die Sortierung abschneiden
	if (substr($r,0,1) ne '.') {
	    push @lines,'set '.$fname.' '.$r.' '.$h{$val};
	}
	else {
	    push @lines,'setreading '.$fname.' '.substr($r,1,length($r)).' '.$h{$val};
	}
    }

    my @j_arr;

    if ($hash->{type} =~ m{Thermostat}xms) {

	#$hash->{saveConfig} = 1;
	my @ar;
	@ar = MAX_ParseWeekProfile($hash, 1) if (defined($h{'50..weekProfile'}));
	#delete $hash->{saveConfig};

	foreach my $s (@ar) {
	    next if (!$s);
	    $s =~ s/$name/$fname/ if ($name ne $fname);
	    (substr($s,0,1) eq '"') ? push @j_arr, $s : push @lines, $s;
	}

	push @lines , "setreading $fname .wp_json ".'{'.join(',', @j_arr).'}';
    }

    return "$name, nothing to save !" if (!@lines);

    my $error = FileWrite($dir.$fname.'.max', @lines);

    return Log3Return($name, $error, 2) if ($error);

    my $bulk = (exists($hash->{'.updateTimestamp'})) ? 1 : 0;  # readingsBulkUpdate ist aktiv, wird von fhem.pl gesetzt/gelöscht

    readingsBeginUpdate($hash) if (!$bulk);
    readingsBulkUpdate($hash, 'lastConfigSave', $dir.$fname.'.max');
    readingsBulkUpdate($hash, '.wp_json', '{'.join(',', @j_arr).'}') if (@j_arr);
    readingsEndUpdate($hash, 1) if (!$bulk);

    return;
}

sub MAX_Restore
{
    my $name   = shift;
    my $action = shift // '';
    my $fname  = shift // $name;
    my $hash   = $defs{$name};

    my $dir    = AttrVal('global', 'logdir', './log/');
    $dir .='/' if ($dir !~ m{\/\z}x);

    my ($error, @lines) = FileRead($dir.$fname.'.max');

    return Log3Return($name, $error, 2) if ($error);

    my $has_wp = 0;

    if (@lines) {
	readingsBeginUpdate($hash);
	foreach my $line (@lines) {
	    my ($cmd, $dname, $reading, @val) = split(' ', $line);
	    next if (!$cmd || !$dname || !$reading || !@val);
	    $has_wp = 1 if ($reading eq '.weekProfile');

	    readingsBulkUpdate($hash, $reading, join(' ', @val)) if ($cmd eq 'setreading');
	    $error.= CommandSet(undef, "$name $reading ".join(' ', @val)) if  (($cmd eq 'set') && ($action eq 'restoreDevice'));
	}

	MAX_ParseWeekProfile($hash) if ($has_wp);
	readingsEndUpdate($hash, 0);
    }

    return $error;
}


#############################

sub MAX_ParseDateTime {

    my ($byte1,$byte2,$byte3) = @_;
    my $day = $byte1 & 0x1F;
    my $month = (($byte1 & 0xE0) >> 4) | ($byte2 >> 7);
    my $year = $byte2 & 0x3F;
    my $time = ($byte3 & 0x3F);

    $time = ($time%2) ? int($time/2).':30' : int($time/2).':00';

    return {   'day' => $day,
	     'month' => $month,
	      'year' => $year,
	      'time' => $time,
	       'str' => "$day.$month.$year $time"
	    };
}

#############################

sub Parse {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $msg  = shift;

    Log3($name, 5, "MAX_Parse, $msg");

    my ($MAX,$isToMe,$msgtype,$addr,@args) = split(',',$msg);

    $MAX     // return;
    $isToMe  // return;
    $msgtype // return;
    $addr    // return;
    $args[0] //= 'noArgs';

    # $isToMe is 1 if the message was direct at the device $hash, and 0
    # if we just snooped a message directed at a different device (by CUL_MAX).

    #Log3($name, 1, "$name, msg $msg has no args !") if ($args[0] eq 'noArgs');
    # ToDo Msgtype error kommt ohne Args !

    if (!exists($modules{MAX}{defptr}{$addr})) {
	if (($msgtype eq 'Ack') || ($addr eq '111111') || ($addr eq '222222')) {
	    Log3($name, 4, "MAX_Parse, $msgtype for undefined device $addr - ignoring !");
	    return $name;
	}

	my $devicetype;
	$devicetype = $args[0] if ($msgtype eq 'define' && $args[0] ne 'Cube');
	$devicetype = 'ShutterContact'        if ($msgtype eq 'ShutterContactState');
	$devicetype = 'PushButton'            if ($msgtype eq 'PushButtonState');
	$devicetype = 'WallMountedThermostat' if ( ($msgtype eq 'WallThermostatConfig')
					        || ($msgtype eq 'WallThermostatState')
						|| ($msgtype eq 'WallThermostatControl'));
	$devicetype = 'HeatingThermostat'     if ( ($msgtype eq 'HeatingThermostatConfig')
						|| ($msgtype eq 'ThermostatState'));

	if ($devicetype) {
	    my $ac = (IsDisabled('autocreate')) ? 'disabled' : 'enabled' ; 
	    Log3($name, 3, "MAX_PARSE, got message $msgtype for undefined device $addr type $devicetype , autocreate is $ac");
	    return $name if ($ac eq 'disabled');
	    return "UNDEFINED MAX_$addr MAX $devicetype $addr";
	} 
	
	Log3($name, 3, "MAX_Parse, message for undefined device $addr and failed to guess devicetype from msg $msgtype - ignoring !");
	return $name;
    } # bisher unbekanntes Device

    ################################################################

    my $shash = $modules{MAX}{defptr}{$addr};

    if (!defined($shash->{NAME})) {
	Log3($name, 1, "MAX_Parse, missing name msg: $msg");
	return $name;
    }

    my $sname = $shash->{NAME};

    if (!defined $shash->{type} || !defined $shash->{devtype}) {
	Log3($name, 5, "MAX_Parse, no type or no devtype (maybe MAXLAN ?) : $addr, $sname, $msg");
	return $name;
    }


    # if $isToMe is true, then the message was directed at device $hash, thus we can also use it for sending
    if ($isToMe) {
	$shash->{IODev}   = $hash;
	#$shash->{backend} = $hash->{NAME}; # for user information , wozu soll das gut sein ???
    }

    my $skipDouble = AttrNum($sname,'skipDouble',0); # Pakete mit gleichem MSGCNT verwerfen, bsp WT/FK an alle seine HTs ?
    my $debug      = AttrNum($sname,'debug',0);
    #my $iogrp      = AttrVal($hash->{NAME} , 'IOgrp' ,''); # hat CUL_MAX eine IO Gruppe ?
    #my @ios        = split(',', AttrVal($name, 'IOgrp' ,''));

    readingsBeginUpdate($shash);
    readingsBulkUpdate($shash, '.lastact', time());
    readingsBulkUpdate($shash, 'Activity', 'alive') if (($hash->{TYPE} eq 'CUL_MAX') && InternalVal($sname, '.actCycle', '0'));

    if ($debug) {
	if (exists($shash->{helper}{io})) {
	    foreach my $cul (keys %{$shash->{helper}{io}}) {
		readingsBulkUpdate($shash, $cul.'_RSSI', $shash->{helper}{io}{$cul}{'rssi'});
	    }
	readingsBulkUpdate($shash, '.isToMe', $isToMe);
	}
    }

    if ($msgtype eq 'AckSetTemperature') {
	my $val; 
	my @ar;
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ' ,@args));

	#@ar = split(' ',$args[0]) if ($args[0]);
	#if (!$ar[0]) { 
	#    $val =  'auto/boost'; }
	#else {
	#    $val = MAX_SerializeTemperature($ar[0]);
	#    shift @ar;
	#    $val .= ' '.join(' ',@ar) if (@ar); # bei until kommt mehr zurück
	#}
	#readingsBulkUpdate($shash, 'lastcmd', "desiredTemperature $val");
        readingsBulkUpdate($shash, 'lastcmd', 'desiredTemperature '.join(' ',@args));
	readingsEndUpdate($shash,1);
	return $sname;
    }

    if (($msgtype eq 'AckAddLinkPartner') || ($msgtype eq 'AckRemoveLinkPartner')) {
	## AckLinkPartner
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));

	my $peers = MAX_uniq($sname, 'peers', $args[1]);

	if (($args[0] eq 'deassociate') && ($peers eq $args[1])) { # nur noch er da ?
	    readingsDelete($sname, 'peers');
	    $peers = '';
	}

        readingsBulkUpdate($shash, 'peers', $peers)  if ($peers);
	readingsBulkUpdate($shash, 'lastcmd', join(' ',@args));
	_saveConfig($sname) if (AttrNum($sname, 'autosaveConfig', 0));
	readingsEndUpdate($shash, 1);
	return $sname;
    }

    if ($msgtype eq 'AckWakeUp') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	my ($duration) = @args;
	# substract five seconds safety margin
	$shash->{wakeUpUntil} = gettimeofday() + $duration - 5;
	readingsBulkUpdate($shash, 'lastcmd', 'WakeUp');
	readingsEndUpdate($shash, 1);
	return $sname;
    }

    if ($msgtype eq 'AckConfigWeekProfile') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	my ($day, $part, $profile) = @args;
	my $curWeekProfile = MAX_ReadingsVal($shash, '.weekProfile');
	substr($curWeekProfile, $day*52+$part*2*2*7, length($profile)) = $profile;
	readingsBulkUpdate($shash, '.weekProfile', $curWeekProfile);
	readingsBulkUpdate($shash, 'lastcmd', 'ConfigWeekProfile');
	MAX_ParseWeekProfile($shash);
	_saveConfig($shash->{NAME}) if (AttrNum($shash->{NAME}, 'autosaveConfig', 0));
	Log3($sname, 5, "$sname, new weekProfile: " . MAX_ReadingsVal($shash, ".weekProfile"));
	readingsEndUpdate($shash,1);
	return $sname;
    }

    if ($msgtype eq 'Ack') {
	# The payload of an Ack is a 2-digit hex number (being "01" for OK and "81" for "invalid command/argument"
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	if ($isToMe && (unpack("C",pack("H*",$args[0])) & 0x80)) {
	    Log3($sname, 1, "$sname, invalid command/argument $args[0]");
	    readingsBulkUpdate($shash, 'error', "invalid command/argument $args[0]");
	    readingsEndUpdate($shash, 1);
	    return $sname;
	}

	# with unknown meaning plus the data of a State broadcast from the same device
	# For HeatingThermostats, it does not contain the last three "until" bytes (or measured temperature)

       if (!defined($shash->{type}))
       {
          Log3($name,1,Dumper($shash));
          return $name;
       }

	if ($shash->{type} =~ m{\AHeatingThermostat}xms || ($shash->{devtype} == 8)) {
	    $msgtype = 'ThermostatState';
	    $args[0] = substr($args[0],2);
	    $MAX = '';
	}

	if ($shash->{type} eq 'WallMountedThermostat') {
	    $msgtype = 'WallThermostatState';
	    $args[0] = substr($args[0],2);
	    $MAX = '';
	}

	if ($shash->{type} eq 'ShutterContact') {
	    $msgtype = 'ShutterContactState';
	    $args[0] = substr($args[0],2);
	    $MAX = '';
	}

	if ($shash->{type} eq 'PushButton') {
	    $msgtype = 'PushButtonState';
	    $args[0] = substr($args[0],2);
	    $MAX = '';
	}

	if ($MAX) { # noch da ?
	    if ($isToMe) {
		Log3($sname, 2, "$sname, don't know how to interpret Ack payload $args[0]");
		readingsBulkUpdate($shash, 'error', "unknown ack payload $args[0]");
	    }
	    readingsEndUpdate($shash, 1);
	    return $sname;
	}
    }

    if ($msgtype eq 'define') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	my $devicetype = $args[0];
	Log3 $hash, 2, "$sname changed type from $shash->{type} to $devicetype" if ($shash->{type} ne $devicetype);
	$shash->{type} = $devicetype;
	readingsBulkUpdate($shash, 'SerialNr', $args[1]) if (defined($args[1]));
	readingsBulkUpdate($shash, 'groupid',  $args[2]) if (defined($args[2]) && !$isToMe);# ToDo prüfen, wird hier die groupid beim repairing platt gemacht ?
	$shash->{IODev} = $hash;
        readingsEndUpdate($shash,1);
        return $sname;
    }

    if ($msgtype eq 'ThermostatState') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));

	if (($shash->{'.count'} < 0) && $skipDouble) {
	    Log3($sname, 4, "$sname, message ".abs($shash->{'.count'}).' already processed - skipping');
	    readingsEndUpdate($shash, 1);
	    return $sname; # vorzeitiger Abbruch
	}

	$shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'}>0);

	my ($bits2,$valveposition,$desiredTemperature,$until1,$until2,$until3) = unpack("aCCCCC",pack("H*",$args[0]));
	$shash->{'.mode'}       = vec($bits2, 0, 2); #
	$shash->{'.testbit'}    = vec($bits2, 2, 1); #
	$shash->{'.dstsetting'} = vec($bits2, 3, 1); # is automatically switching to DST activated
	$shash->{'.gateway'}    = vec($bits2, 4, 1); # ??
	$shash->{'.panel'}      = vec($bits2, 5, 1); # 1 if the heating thermostat is locked for manually setting the temperature at the device
	$shash->{'.rferror'}    = vec($bits2, 6, 1); # communication with link partner - if device is not accessible over the air from the cube
	$shash->{'.battery'}    = vec($bits2, 7, 1); # 1 if battery is low

	my $untilStr = (defined($until3) && ($shash->{'.mode'} == 2)) ? MAX_ParseDateTime($until1,$until2,$until3)->{str} : '';
	my $measuredTemperature = defined($until2) ? ((($until1 &0x01)<<8) + $until2)/10 : 0;
	# If the control mode is not "temporary", the cube sends the current (measured) temperature
	$measuredTemperature = '' if ($shash->{'.mode'} == 2 || $measuredTemperature == 0);
	#$untilStr = '' if ($shash->{'.mode'} != 2);

	$shash->{'.desiredTemperature'} = ($desiredTemperature&0x7F)/2.0; #convert to degree celcius

	my $log_txt = "$sname, desiredTemperature:$shash->{'.desiredTemperature'}, rferror:$shash->{'.rferror'}, battery:$shash->{'.battery'}, mode:$shash->{'.mode'}, gateway:$shash->{'.gateway'}, panel:$shash->{'.panel'}, dst:$shash->{'.dstsetting'}, valveposition:$valveposition";
	$log_txt .= ", until:$untilStr" if ($untilStr);
	$log_txt .= ", curTemp:$measuredTemperature" if ($measuredTemperature);
	Log3 $shash, 5, $log_txt;

	# Very seldomly, the HeatingThermostat sends us temperatures like 0.2 or 0.3 degree Celcius - ignore them
	$measuredTemperature = '' if (($measuredTemperature ne '') && ($measuredTemperature < 1));

	if ($shash->{'.mode'} == 2) { 
	    $shash->{'until'} = $untilStr;
	} 
	else { 
	    delete($shash->{'until'});
	}

	# The formatting of desiredTemperature must match with in MAX_Set:$templist
	# Sometime we get an MAX_Parse MAX,1,ThermostatState,01090d,180000000000, where desiredTemperature is 0 - ignore it

	readingsBulkUpdate($shash, 'temperature', MAX_SerializeTemperature($measuredTemperature)) if ($measuredTemperature ne '');

	if (!AttrVal($sname, 'externalSensor', '')) {
	    readingsBulkUpdate($shash, 'deviation', sprintf('%.1f',($measuredTemperature-$shash->{'.desiredTemperature'}))) if ($shash->{'.desiredTemperature'} && $measuredTemperature);
	}
	else {
	    my ($sensor, $t, $snotify) = split(':', AttrVal($sname, 'externalSensor', '::'));
	    $snotify //= 0;
	    my $ext = ReadingsNum($sensor, $t, 0);
	    readingsBulkUpdate($shash, 'deviation', sprintf('%.1f', ($ext-$shash->{'.desiredTemperature'}))) if ($shash->{'.desiredTemperature'} && $ext);
	    readingsBulkUpdate($shash, 'externalTemp', $ext) if ($ext && !$snotify);
	}

	if (($shash->{type} eq 'HeatingThermostatPlus') && ($hash->{TYPE} eq 'MAXLAN')) {
    	    readingsBulkUpdate($shash, 'valveposition', int($valveposition*MAX_ReadingsVal($shash, 'maxValveSetting')/100));
	} 
	else {
	    if ($shash->{devtype} != 8) {
		 readingsBulkUpdate($shash, 'valveposition', $valveposition);
	    }
	    else {
		$shash->{'.isopen'} = (int($valveposition) == 100) ? '0' : '1';
	    }
	}
	$MAX = '';
    }

    if (($msgtype eq 'WallThermostatState') || ($msgtype eq 'WallThermostatControl')) {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	if (($shash->{'.count'} < 0) && $skipDouble) {
	    Log3($name, 4, "$sname, message ".abs($shash->{'.count'}).' already processed - skipping');
	    readingsEndUpdate($shash, 1);
	    return $name; # vorzeitiger Abbruch
	}

	$shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'} > 0) ;

	my ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature);

	if (!defined($args[0]) || (length($args[0]) < 4)) {
	    Log3($sname, 2, "$sname, invalid $msgtype packet : args is to short"); # greift bei $args[0] undefined !
	    readingsEndUpdate($shash, 1);
	    return $name;
	}

	if ( length($args[0]) == 4 ) {
	    # This is the message that WallMountedThermostats send to paired HeatingThermostats
	    ($desiredTemperatureRaw,$temperature) = unpack("CC",pack("H*",$args[0]));
	    Log3($sname, 5, "$sname, deTempRaw:$desiredTemperatureRaw , temperature:$temperature");
	}

	elsif ( length($args[0]) >= 6 && length($args[0]) <= 14) { 
	    # len=14: This is the message we get from the Cube over MAXLAN and which is probably send by WallMountedThermostats to the Cube
	    # len=12: Payload of an Ack message, last field "temperature" is missing
	    # len=10: Received by MAX_CUL as WallThermostatState
	    # len=6 : Payload of an Ack message, last four fields (especially $heaterTemperature and $temperature) are missing
	    ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature) = unpack("aCCCCCC",pack("H*",$args[0]));
	    # $heaterTemperature/10 is the temperature measured by a paired HeatingThermostat
	    # we don't do anything with it here, because this value also appears as temperature in the HeatingThermostat's ThermostatState message
            $heaterTemperature //= '';
	    $temperature //= '';
	    $shash->{'.mode'}       = vec($bits2, 0, 2); #
	    $shash->{'.testbit'}    = vec($bits2, 2, 1); #
	    $shash->{'.dstsetting'} = vec($bits2, 3, 1); # is automatically switching to DST activated
	    $shash->{'.gateway'}    = vec($bits2, 4, 1); # ??
	    $shash->{'.panel'}      = vec($bits2, 5, 1); # 1 if the heating thermostat is locked for manually setting the temperature at the device
	    $shash->{'.rferror'}    = vec($bits2, 6, 1); # communication with link partner - if device is not accessible over the air from the cube
	    $shash->{'.battery'}    = vec($bits2, 7, 1);

	    my $untilStr = '';
	    if (defined($null2) && ($null1 != 0 || $null2 != 0)) {
		$untilStr = MAX_ParseDateTime($null1, $heaterTemperature, $null2)->{str};
		$heaterTemperature = '';
		$shash->{'until'} = $untilStr;
	    }
	    else { 
		delete($shash->{'until'});
		$heaterTemperature = sprintf('%.1f', $heaterTemperature/10) if ($heaterTemperature);
	    }

	    my $log_txt = "$sname, desiredTemperature:$desiredTemperatureRaw, rferror:$shash->{'.rferror'}, battery:$shash->{'.battery'}, mode:$shash->{'.mode'}, gateway:$shash->{'.gateway'}, panel:$shash->{'.panel'}, dst:$shash->{'.dstsetting'}, dATemperature:$displayActualTemperature";
	    $log_txt .= ", heaterTemperature:$heaterTemperature" if ($heaterTemperature);
	    $log_txt .= ", temperature:$temperature" if ($temperature);
	    $log_txt .= ", untilStr:$untilStr" if ($untilStr);
	    Log3($name, 5, $log_txt);

	    readingsBulkUpdate($shash, 'displayActualTemperature', ($displayActualTemperature) ? 1 : 0);
	} 
	else {
	    Log3($sname, 2, "$sname, invalid $msgtype packet, args > 14 ?"); # ToDo  greift bei $args[0] undefined !
	    readingsEndUpdate($shash, 1);
	    return $name;
	}

	$shash->{'.desiredTemperature'} = ($desiredTemperatureRaw &0x7F)/2.0; #convert to degree celcius # ToDo $desiredTemperatureRaw undefined , erledigt mit args[0] ?

	if ($temperature ne '') {
	    $temperature = ((($desiredTemperatureRaw &0x80)<<1) + $temperature)/10; # auch Temperaturen über 25.5 °C werden angezeigt !
	    Log3($sname, 5, "$sname, desiredTemperature:$shash->{'.desiredTemperature'}, temperature:$temperature");
	    readingsBulkUpdate($shash, 'temperature', sprintf('%.1f', $temperature));
	    readingsBulkUpdate($shash, 'deviation',   sprintf('%.1f', ($temperature-$shash->{'.desiredTemperature'})));
	} 
	else {
	    Log3($sname, 5, "$sname, desiredTemperature: $shash->{'.desiredTemperature'}");
	}

	$MAX = '';
    }

    if ($msgtype eq 'ShutterContactState') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	if (($shash->{'.count'} < 0) && $skipDouble) {
	    Log3($sname, 4 ,"$sname, message ".abs($shash->{'.count'}).' already processed - skipping');
	    readingsEndUpdate($shash, 1);
	    return $sname;
	}

	$shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'} >0) ;

	my $bits             = pack("H2",$args[0]);
	$shash->{'.isopen'}  = vec($bits,0,2) == 0 ? 0 : 1;
	my $unkbits          = vec($bits,2,4);
	$shash->{'.rferror'} = vec($bits,6,1);
	$shash->{'.battery'} = vec($bits,7,1);
	Log3($sname, 5, "$sname, battery:$shash->{'.battery'}, rferror:$shash->{'.rferror'}, isopen:$shash->{'.isopen'}, unkbits:$unkbits");
	$MAX = '';
    }

    if ($msgtype eq 'PushButtonState') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	my ($bits2, $isopen) = unpack("aC",pack("H*",$args[0]));
	$isopen //= '?';
	#The meaning of $bits2 is completly guessed based on similarity to other devices, TODO: confirm
	$shash->{'.gateway'} = vec($bits2, 4, 1); # Paired to a CUBE?
	$shash->{'.rferror'} = vec($bits2, 6, 1); # communication with link partner (1 if we did not sent an Ack)
	$shash->{'.battery'} = vec($bits2, 7, 1); # 1 if battery is low
	$shash->{'.isopen'}  = $isopen;
	Log3($sname, 5, "$sname, battery:$shash->{'.battery'}, rferror:$shash->{'.rferror'}, onoff:$shash->{'.isopen'}, gateway:$shash->{'.gateway'}");
	$MAX = '';
    }

    if (($msgtype eq 'HeatingThermostatConfig') || ($msgtype eq 'WallThermostatConfig')) { # ToDo : wann kommt das ?
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	readingsBulkUpdate($shash, 'ecoTemperature',     MAX_SerializeTemperature($args[0]));
	readingsBulkUpdate($shash, 'comfortTemperature', MAX_SerializeTemperature($args[1]));
	readingsBulkUpdate($shash, 'maximumTemperature', MAX_SerializeTemperature($args[2]));
	readingsBulkUpdate($shash, 'minimumTemperature', MAX_SerializeTemperature($args[3]));
	readingsBulkUpdate($shash, '.weekProfile', $args[4]);
	readingsBulkUpdate($shash, 'lastcmd', $msgtype);

	if (@args > 5) { # HeatingThermostat and WallThermostat with new firmware
	    readingsBulkUpdate($shash, 'boostValveposition',    $args[5]);
	    readingsBulkUpdate($shash, 'boostDuration',         $boost_durations{$args[6]});
	    readingsBulkUpdate($shash, 'measurementOffset',     MAX_SerializeTemperature($args[7]));
	    readingsBulkUpdate($shash, 'windowOpenTemperature', MAX_SerializeTemperature($args[8]));
	}

	if (@args > 9) { # HeatingThermostat
    	    readingsBulkUpdate($shash, 'windowOpenDuration', $args[9]);
    	    readingsBulkUpdate($shash, 'maxValveSetting',    $args[10]);
    	    readingsBulkUpdate($shash, 'valveOffset',        $args[11]);
    	    readingsBulkUpdate($shash, 'decalcification',    "$decalcDays{$args[12]} $args[13]:00");
	}

	MAX_ParseWeekProfile($shash);
	_saveConfig($shash->{NAME}) if (AttrNum($shash->{NAME}, 'autosaveConfig', 0));
	readingsEndUpdate($shash, 1);
	return $sname;
    }

    if ( $msgtype eq 'Error') { # ToDo : kommen die Errors nur von MAXLAN ? 
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));

	if (!@args || ($args[0] eq 'noArgs')) {
	    delete $shash->{ERROR} if (exists($shash->{ERROR}));
	} 
        else {
	    $shash->{ERROR} = join(',',@args);
	    readingsBulkUpdate($shash, 'error', $shash->{ERROR});
	    Log3($sname, 3 , "$sname, msg Type error :  $shash->{ERROR}");
	}
	readingsEndUpdate($shash, 1);
	return $sname;
    }
 
    if ( ($msgtype eq 'AckConfigValve')
      || ($msgtype eq 'AckConfigTemperatures')
      || ($msgtype eq 'AckSetDisplayActualTemperature')) {
	if ($args[0] eq 'windowOpenTemperature'
	 || $args[0] eq 'comfortTemperature'
	 || $args[0] eq 'ecoTemperature'
	 || $args[0] eq 'maximumTemperature'
	 || $args[0] eq 'minimumTemperature' ) {
	    Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	    my $t = MAX_SerializeTemperature($args[1]);
	    readingsBulkUpdate($shash, 'lastcmd', $args[0].' '.$t);
	    readingsBulkUpdate($shash, $args[0], $t);
	} 
        else {
	    # displayActualTemperature, boostDuration, boostValveSetting, maxValve, decalcification, valveOffset
	    Log3($sname, 5, "$sname, msgtype $msgtype Reading $args[0] : $args[1]");
	    readingsBulkUpdate($shash, $args[0], $args[1]);
	    readingsBulkUpdate($shash, 'lastcmd', $args[0].' '.$args[1]);
	}

	_saveConfig($shash->{NAME}) if (AttrNum($shash->{NAME}, 'autosaveConfig', 0));
	readingsEndUpdate($shash, 1);
	return $sname;
    } 

    if (($msgtype eq 'AckSetGroupId') || ($msgtype eq 'AckRemoveGroupId')) {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	readingsBulkUpdate($shash, 'groupid', int($args[0]));
	readingsBulkUpdate($shash, 'lastcmd', 'groupid '.int($args[0]));
	readingsEndUpdate($shash, 1);
	return $sname;
    }

    if ($msgtype eq 'SetTemperature') {
	Log3($sname, 5, "$sname, msgtype $msgtype : ".join(' ',@args));
	# SetTemperature is send by WallThermostat e.g. when pressing the boost button
	my $bits = unpack("C",pack("H*",$args[0]));
	$shash->{'.mode'} = $bits >> 6;
	my $desiredTemperature = ($bits & 0x3F) /2.0; #convert to degree celcius
	# This formatting must match with in MAX_Set:$templist
	$shash->{'.desiredTemperature'} = MAX_SerializeTemperature($desiredTemperature);
	Log3($sname, 5, "$sname, SetTemperature mode $ctrl_modes[$shash->{'.mode'}], desiredTemperature $shash->{'.desiredTemperature'}") ;
	$MAX = '';
    } 

    if ($MAX) {
	Log3($sname, 2, "$name, unknown message $msgtype !");
	readingsBulkUpdate($shash, 'error', "unknown message $msgtype");
	readingsEndUpdate($shash, 1);
	return $sname;
    }

    # Build state READING
    #my $state = ReadingsVal($name, 'state', 'waiting for data');

    my $state = 'waiting for data';
    $shash->{'.desiredTemperature'} = MAX_SerializeTemperature($shash->{'.desiredTemperature'}) if ($shash->{'.desiredTemperature'});

    my $c = '';
    #$c = '&deg;C' if (exists($shash->{'.desiredTemperature'}) && (substr($shash->{'.desiredTemperature'},0,1) ne 'o')); # on/off
    $c = '°C'      if (exists($shash->{'.desiredTemperature'}) && (substr($shash->{'.desiredTemperature'},0,1) ne 'o')); # on/off

    $state = $shash->{'.desiredTemperature'}.$c if (exists($shash->{'.desiredTemperature'}));
    $state = ($shash->{'.isopen'}) ? 'opened' : 'closed' if (exists($shash->{'.isopen'}) && ($shash->{devtype} != 8));
    $state = ($shash->{'.isopen'}) ? 'on' : 'off'        if (exists($shash->{'.isopen'}) && ($shash->{devtype} == 8));

    if ($shash->{devtype} > 5) {
	delete $shash->{'.rferror'} if ($shash->{devtype} != 8);
	delete $shash->{'.battery'};
	delete $shash->{'.gateway'} if ($shash->{devtype} != 8);
    }

    if (IsDummy($sname)) {
	$state .= ' (auto)'    if (exists($shash->{mode}) && (int($shash->{'.mode'}) == 0));
	$state .= ' (manual)'  if (exists($shash->{mode}) && (int($shash->{'.mode'}) == 1));
    }

    $state .= ' (boost)'                   if (exists($shash->{'.mode'})    && (int($shash->{'.mode'}) == 3));
    $state .= " (until $shash->{'until'})" if (exists($shash->{'.mode'})    && (int($shash->{'.mode'}) == 2) && exists($shash->{'until'}));
    $state .= ' (battery low)'             if (exists($shash->{'.battery'}) && $shash->{'.battery'});
    $state .= ' (rf error)'                if (exists($shash->{'.rferror'}) && $shash->{'.rferror'});
 
    readingsBulkUpdate($shash, 'state', $state);

    if (exists($shash->{'.desiredTemperature'})
        && $c # weder on noch off
        && ($shash->{'.desiredTemperature'} != ReadingsNum($sname, 'windowOpenTemperature', 0))
        && AttrNum($sname, 'windowOpenCheck', 0)) {
	    readingsBulkUpdate($shash, 'windowOpen', '0');
	}

    readingsBulkUpdate($shash, 'desiredTemperature',$shash->{'.desiredTemperature'}) if (exists($shash->{'.desiredTemperature'}));
    readingsBulkUpdate($shash, 'RSSI',         $shash->{'.rssi'})                    if (exists($shash->{'.rssi'}));
    readingsBulkUpdate($shash, 'battery',      $shash->{'.battery'} ? "low" : "ok")  if (exists($shash->{'.battery'}));
    readingsBulkUpdate($shash, 'batteryState', $shash->{'.battery'} ? "low" : "ok")  if (exists($shash->{'.battery'})); # Forum #87575
    readingsBulkUpdate($shash, 'rferror',      $shash->{'.rferror'})                 if (exists($shash->{'.rferror'}));
    readingsBulkUpdate($shash, 'gateway',      $shash->{'.gateway'})                 if (exists($shash->{'.gateway'}));
    readingsBulkUpdate($shash, 'mode',         $ctrl_modes[$shash->{'.mode'}] )      if (exists($shash->{'.mode'}));

    # ToDo open /close mag der MaxScanner gar nicht

    if (exists($shash->{'.isopen'})) {
	readingsBulkUpdate($shash, 'onoff', $shash->{'.isopen'} ? '1' : '0' );

	if ((AttrNum($sname, 'windowOpenCheck', 1)) && ($shash->{devtype} == 4)) {
	    if (!$shash->{'.isopen'}) {
		readingsBulkUpdate($shash, 'windowOpen', '0');
		$shash->{'.timer'} = 300;
	    }
	    else {
		$shash->{'.timer'} = 60; 
		RemoveInternalTimer($shash);
		InternalTimer(gettimeofday()+1, 'FHEM::MAX::OnTimer', $shash, 0);
	    }
	}
    }

    readingsBulkUpdate($shash, 'panel', $shash->{'.panel'} ? 'locked' : 'unlocked') if (exists($shash->{'.panel'}));

  if ($shash->{'.sendToName'} && ($shash->{'.sendToAddr'} ne '-1')) {
       $shash->{'.sendToName'} = 'Broadcast' if ($shash->{'.sendToAddr'} eq '000000');
	if (AttrNum($sname, 'debug', 0)) {
	    my $val = ReadingsNum($sname, 'sendTo_'.$shash->{'.sendToName'}, 0);
	    $val ++;
	    readingsBulkUpdate($shash, 'sendTo_'.$shash->{'.sendToName'}, $val);
	}
	if ($shash->{'.sendToAddr'} ne '000000') {
	    readingsBulkUpdate($shash, 'peerList', MAX_uniq($sname, 'peerList',$shash->{'.sendToName'}));
	    readingsBulkUpdate($shash, 'peerIDs',  MAX_uniq($sname, 'peerIDs', $shash->{'.sendToAddr'}));
	}
    }

    readingsEndUpdate($shash, 1);

    my @intvals = ('.desiredTemperature','.rssi','.rferror','.battery','.mode','.gateway','.isopen','.panel','.dstsetting');
    my $l4txt;

    foreach my $i (@intvals) {
	next if (!exists($shash->{$i}));
	$l4txt .= ', '.substr($i,1).':'.$shash->{$i};
        delete $shash->{$i};
    }

    Log3($sname, 4, $sname.$l4txt);

    return $sname;
}

#############################
sub DbLog_splitFn {

    my $event = shift;
    my $name  = shift;
    my ($reading, $value, $unit) = '';

    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $value = $parts[1]  if (defined($parts[1]) && (lc($value) =~ m{auto}xms));

    if (!AttrNum($name, 'DbLog_log_onoff', 0)) {
	$value = '4.5'  if ( $value eq 'off' );
	$value = '30.5' if ( $value eq 'on' );
    }

    $unit = '\xB0C' if ( lc($reading) =~ m{temp}xms );
    $unit = '%'     if ( lc($reading) =~ m{valve}xms );
    return ($reading, $value, $unit);
}

sub RenameFn {
  my $new = shift;
  my $old = shift;
  my $hash;

  for (devspec2array('TYPE=MAX'))
  {
    $hash = $defs{$_};
    next if (!$hash);
    if (exists($hash->{READINGS}{peerList}))
    {
     $hash->{READINGS}{peerList}{VAL} =~ s/$old/$new/x;
    }
  }
 return;
}


sub Notify {

    # $hash is my hash, $dev_hash is the hash of the changed device
    my $hash     = shift;
    my $dev_hash = shift;
    my $name = $hash->{NAME};

    my ($sd,$sr,$sn,$sm) = split(':', AttrVal($name, 'externalSensor', '::'));

    return  if ($dev_hash->{NAME} ne $sd);

    my $events = deviceEvents($dev_hash,0);
    my $reading; 
    my $val; 
    my $ret;

    foreach  my $event ( @{$events} ) {
	Log3($name, 5, "$name, NOTIFY EVENT -> Dev : $dev_hash->{NAME} | Event : $event");
	($reading,$val) = split(': ',$event);
	$reading =~ s/ //g;
	if (!defined($val) && defined($reading)) { # das muss state sein
	    $val     = $reading;
	    $reading = 'state';
	}
	last if ($reading eq $sr);
    }

    return if (!defined($val) || ($reading ne $sr)); # der Event war nicht dabei

    if (($hash->{devtype} < 6) || ($hash->{devtype} == 8)) {
	return if (!exists($hash->{READINGS}{desiredTemperature}{VAL}));
	my $dt = ParseTemperature($hash->{READINGS}{desiredTemperature}{VAL});

	Log3($name, 5, "$name, updating externalTemp with $val");
	setReadingsVal($hash, 'externalTemp', $val, TimeNow());

	my $check = MAX_CheckIODev($hash);
	$ret = $check  if ($check ne 'CUL_MAX');
	$ret = CommandSet(undef,$hash->{IODev}{NAME}." fakeWT $name $dt $val") if (!$ret && $sn);
    }

    if ($hash->{devtype} == 6) {
	Log3($name, 5, "$name, $reading - $val");
	return if (($val !~ m/$sn/x) && ($val !~ m/$sm/x));
	Log3($name, 4, "$name, got external open/close trigger -> $sd:$sr:$val");
	$ret = CommandSet(undef,$name.' open q')  if ($val =~ m/$sn/x);
	$ret = CommandSet(undef,$name.' close q') if ($val =~ m/$sm/x);
    }

    setReadingsVal($hash, 'temperature', sprintf('%.1f', $val), TimeNow()) if ($hash->{devtype} == 7);

    Log3($name, 3, "$name, NotifyFN : $ret") if ($ret);
    return;
}

sub MAX_FileList
{
    my $dir  = shift;
    my $file = shift // '';
    my @ret;
    my $found = (!$file) ? 1 : 0;

    if (configDBUsed()) {
	my @files = split(/\n/x, _cfgDB_Filelist('notitle'));
	foreach my $f (@files) {
	    next if ( $f !~ m{\A $dir}xms);
	    next if ( $f !~ m{\.max\z}xms);
	    $f =~ s/$dir//x;
	    $f =~ s/\.max//x;
	    next if (!$f);
	    $found = 1 if ($f eq $file);
	    push @ret, $f;
	}
    }
    else {
	return 0 if (!opendir(DH,$dir));
	while(readdir(DH)) {
	    next if ( $_ !~ m{\.max\z}xms);
	    $_ =~ s/\.max//x;
	    $found = 1 if ($_ eq $file);
	    push @ret, $_ if ($_) ;
	}
	closedir(DH);
    }
    return @ret if ($found);
    return 0;
}

sub MAX_BackupedDevs {

    my $name = shift;
    my $dir = AttrVal('global','logdir','./log/');
    $dir .='/' if ($dir  !~ m{\/\z}xms);
    my $files = '';
    my @list = MAX_FileList($dir, $name);
    if (!$list[0]) {
	$name = '&nbsp;'; # ist leer wenn der eigene Name nicht drin ist
	#@list = MAX_FileList($dir, '');
	@list = MAX_FileList($dir);
    }
    my @ar = grep {$_ ne $name } @list; # den eigenen Namen aus der Liste werfen
    @list = sort @ar;
    unshift @list,$name; # und wieder ganz vorne anstellen
    $files = join(',', @list);

    return $files;
}

sub _handle_WakeUp {
    my $hash = shift;
    MAX_ReadingsVal($hash, 'lastcmd', "set_WakeUp");
    #3F corresponds to 31 seconds wakeup (so its probably the lower 5 bits)
    return ($hash->{IODev}{Send})->($hash->{IODev}, 'WakeUp', $hash->{addr}, '3F', callbackParam => '31');
}

sub _handle_SetTemperature {

    my ($hash, undef, @args) = @_;
    my $name = $hash->{NAME};

    return Log3Return($name, 'missing parameter for set desiredTemperature !') if (!@args);

    my $devtype = $hash->{devtype};

    return Log3Return($name, 'command set desiredTemperature is not allowed for this device !') if (($hash->{type} !~ m{Thermostat}xms) && ($devtype != 8));

    my $temperature = -1; # not set yet
    my $until = '';
    my $ctrlmode = -1; # -1 = not set yet , 0 = auto, 1 = manual, 2 = temporary , 3 = boost

    Log3($name, 4, "$name, _handle_SetTemperature: ".join(' ',@args));

    return Log3Return($name, 'too many parameters: desiredTemperature auto [<temperature>]') if (($args[0] eq 'auto') && (@args > 2));
    return Log3Return($name, 'wrong parameters : desiredTemperature <temp> until <date> <time>') if (($args[0] eq 'until') && (@args != 4));

    if ($args[0] eq 'auto') {
	# This enables the automatic/schedule mode where the thermostat follows the weekly program
	# There can be a temperature supplied, which will be kept until the next switch point of the weekly program

	$temperature = 0 if (@args == 1); # use temperature from weekly program

	shift @args if (@args == 2); 

	$ctrlmode = 0; # auto
    } # auto

    if ($args[0] eq 'boost') {
	return Log3Return($name, 'set_desiredTemp : too many parameters for boost') if (@args > 1);
	$temperature = 0;
	$ctrlmode = 3;
	# TODO: auto mode with temperature is also possible
    } 

    if ($args[0] eq 'manual') {
	# User explicitly asked for manual mode
	$ctrlmode = 1; #manual, possibly overwriting keepAuto
	shift @args;
	return Log3Return($name, 'set_desiredTemp : not enough parameters after desiredTemperature manual') if (!@args);
    }
    elsif (AttrNum($name, 'keepAuto', 0)  && (ReadingsVal($hash, 'mode', 'auto') eq 'auto')) {
	# User did not ask for any mode explicitly, but has keepAuto
	Log3($hash, 5, "$name, SetTemperature: keepAuto and mode auto = staying in auto mode");
	$ctrlmode = 0; # auto
    }

    $temperature = MAX_ReadingsVal($hash, 'ecoTemperature') if ($args[0] eq 'eco');

    $temperature = MAX_ReadingsVal($hash, 'comfortTemperature') if ($args[0] eq 'comfort');

    # immer noch keine Temperatur ?
    if ($temperature < 0) {
        return Log3Return($name, "set_desiredTemp : Temperature $args[0] is invalid") if (!validTemperature($args[0])); #on/off & 5-30
	$temperature = ParseTemperature($args[0]); # on/off mit 30.5 /4.5 ersetzen
    }

    if (@args > 1) {
	return "$name, SetTemperature second parameter must be until" if ($args[1] ne 'until');
	$ctrlmode = 2; #switch manual to temporary
	
	my ($day,$month,$year);

	if ($args[2] eq 'today') {
	    (undef,undef,undef,$day,$month,$year) = localtime(gettimeofday());
	    $month++; $year+=1900;
	}
	else {
	    ($day, $month, $year) = split('\.',$args[2]);
	    $day   = int($day);
	}

	my ($hour,$min)  = split(":", $args[3]);
	$day   = int($day);
	$month = int($month);
	$year  = int($year);
	$hour  = int($hour);
	$min   = int($min);

	my $check;
	$check = 1 if (!$day || !$month || !$year || ($day > 31) || ($month > 12) || ($hour > 23));
	$check = 1 if (($min != 0) && ($min != 30));

	return Log3Return($name, "SetTemperature until : invalid Date or Time -> D[1-31] : $day, M[1-12] : $month, Y: $year, H[0-23]: $hour, M[0,30]: $min") if ($check);

	$year +=2000 if ($year < 100);

	if ((str2time("$month/$day/$year $hour:$min:00")-time()) < 30) {
	    return Log3Return($name, "SetTemperature until -> end $args[2] $args[3] is not future !");
	}

	$until = sprintf('%06x',(($month&0xE) << 20) | ($day << 16) | (($month&1) << 15) | (($year-2000) << 8) | ($hour*2 + int($min/30)));
    }

    if ($ctrlmode < 0) {
	Log3($hash, 4, "$name, missing control mode, setting to manual");
	$ctrlmode = 1;
    }

    my $payload = sprintf('%02x', int($temperature * 2) | ($ctrlmode << 6));
    $payload .= $until if ($until);

    my $groupid = MAX_ReadingsVal($hash, 'groupid');
    my $flags   = ($groupid) ? '04' : '00';
    $groupid = sprintf('%02x', $groupid);

    #$args[0] = $temperature;
    my $val  = join(' ',@args);

    MAX_ReadingsVal($hash, 'lastcmd', "set_desiredTemperature $val") if ($devtype != 7);

    Log3($name, 5, "$name, SetTemperature: val : $val, gid : $groupid, pl : $payload, flags : $flags");

    return ($hash->{IODev}{Send})->($hash->{IODev}, 'SetTemperature', $hash->{addr}, $payload, callbackParam => $val, groupId => $groupid, flags => $flags) if ($devtype != 7);

    # Baustelle virtualThermo

    my $mode; 

    if (!$ctrlmode) { 
	$mode = 'auto';
	MAX_ParseWeekProfile($hash, 1); # $hash->{helper}{dt} aktualisieren
	$temperature = ($hash->{helper}{dt} > 0) ? $hash->{helper}{dt} : 0; # aktuelle Soll Temp laut weekprofile
    }

    $mode = 'manual'    if ($ctrlmode == 1);
    $mode = 'temporary' if ($ctrlmode == 2);

    if ($ctrlmode == 3) {
	$mode = 'boost';
	$temperature = 'on';
    }


    readingsBeginUpdate($hash); 
    readingsBulkUpdate($hash, 'mode', $mode);
    readingsBulkUpdate($hash, 'desiredTemperature', $temperature);
    readingsBulkUpdate($hash, 'lastcmd', "desiredTemperature $val");
    readingsEndUpdate($hash ,1);

  return;
}

##############################################################################


sub _handle_ConfigValve {

    my ($hash, $cmd, @args) = @_;
    my $name    = $hash->{NAME};
    my $devtype = $hash->{devtype};

    return Log3Return($name, "$cmd is not allowed for this device !") if (($devtype != 1) && ($devtype != 2) && ($devtype != 7) && ($devtype != 8));
    return LogAndreturn($name, "missing parameter for set $cmd !") if (!@args);

    $args[0] =~ s/ //g;
    my $val = join(' ',@args); # decalcification contains a space, day HH:MM

    Log3($name, 4, "$name, _handle_ConfigValve: $val");

    my $error = "invalid value $val for set command $cmd";

    return Log3Return($name, "invalid set command $cmd") if (!exists($readingDef{$cmd}));

    if ($cmd eq 'boostDuration') {
	return Log3Return($name, $error) if (!validBoostDuration($val));
	if ($devtype == 7) {
	    MAX_ReadingsVal($hash, 'boostDuration', $val);
	    MAX_ReadingsVal($hash, 'lastcmd', "set_boostDuration $val");
	    return;
	}
    }

    return Log3Return($name, $error) if ( ($cmd =~ m{alve}xms ) && !validValvePosition($val));

    if (($args[0] =~ m/1$/x) && ($cmd eq 'decalcification')) {

	my (undef,undef,$hour,undef,undef,undef,$wday,undef,undef) = localtime(gettimeofday());

	# (Sun,Mon,Tue,Wed,Thu,Fri,Sat) -> localtime
	# (Sat,Sun,Mon,Tue,Wed,Thu,Fri) -> MAX intern

	if ($args[0] eq '1') { # morgen ?
	    $hour ++;
	    $hour  = 0 if ($hour > 23);
	    $wday += 2;
	    $wday -= 7 if ($wday > 6);
        } # else für args[0] == -1 gestern entfällt, da MAX eh einen -1 Versatz zu localtime hat

        $val = $decalcDays{$wday}.' '.sprintf('%02d', $hour).':00';
    }

    return Log3Return($name, $error) if (($cmd eq 'decalcification') && !validDecalcification($val));

    MAX_ReadingsVal($hash, 'lastcmd','set_'.$cmd.' '. $val);

    my %h;
    # zuerst alle Parameter im Payload mit aktuellen und gültigen Startwerten vorbesetzen
    $h{boostDuration}      = MAX_ReadingsVal($hash, 'boostDuration'); # valid : 0,5,10,15,20,25,30,60
    $h{boostValveposition} = MAX_ReadingsVal($hash, 'boostValveposition'); # max 80
    $h{decalcification}    = MAX_ReadingsVal($hash, 'decalcification'); # day HH:MM
    $h{maxValveSetting}    = MAX_ReadingsVal($hash, 'maxValveSetting'); # max 100
    $h{valveOffset}        = MAX_ReadingsVal($hash, 'valveOffset');

    $h{$cmd}               = $val; # und nun den einen wieder überschreiben

    my ($decalcDay, $decalcHour) = ($h{decalcification} =~ /^(...)\s(\d{1,2}):00$/x);

    my $payload = sprintf('%02x%02x%02x%02x',
		  ($boost_durationsInv{$h{boostDuration}} << 5) | int($h{boostValveposition}/5),
		  ($decalcDaysInv{$decalcDay} << 5) | $decalcHour,
		  int($h{maxValveSetting}*255/100),
		  int($h{valveOffset}*255/100)
		 );

    Log3($name, 5, "$name, ConfigValve: cmd : $cmd , val : $val,  pl : $payload");

    return ($hash->{IODev}{Send})->($hash->{IODev}, 'ConfigValve' ,$hash->{addr}, $payload, callbackParam => "$cmd,$val");
}

sub _handle_SetDisplay {
    my $hash    = shift;
    my $cmd     = shift;
    my $arg     = int(shift);
    my $name    = $hash->{NAME};
    my $devtype = int($hash->{devtype});

    Log3($hash, 4, "$name, _handle_SetDisplay: $arg");

    return Log3Return($name, 'set displayActualTemperature is not allowed for this devicetyp !') if ($devtype != 3);
    return Log3Return($name, "invalid arg $arg for displayActualTemperature") if (($arg != 0) && ($arg != 1));

    MAX_ReadingsVal($hash, 'lastcmd', 'set_displayActualTemperature '.$arg);
    return ($hash->{IODev}{Send})->($hash->{IODev},'SetDisplayActualTemperature',$hash->{addr},sprintf('%02x',$arg ? 4 : 0), callbackParam => "displayActualTemperature,$arg");
}

##############################################################################

sub _handle_SetGroupId {
    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $cmd     = shift;
    my $groupid = shift // return "$name, missig groupid !";
    $groupid    = int($groupid);

    my $devtype = int($hash->{devtype});

    Log3($hash, 4, "$name, _handle_SetGroupId: $groupid");

    return Log3Return($name, "invalid groupid $groupid") if (!validGroupId($groupid));

    MAX_ReadingsVal($hash, 'lastcmd', "set_groupid $groupid");


    if (($devtype > 0) && (($devtype < 5) || $devtype == 8)) {
	return ($hash->{IODev}{Send})->($hash->{IODev}, 'SetGroupId', $hash->{addr}, sprintf('%02x',$groupid), callbackParam => "$groupid" ) if ($groupid);
	return ($hash->{IODev}{Send})->($hash->{IODev}, 'RemoveGroupId', $hash->{addr}, '00', callbackParam => '00') if ($groupid == 0);
    }

    return MAX_ReadingsVal($hash, 'groupid', $groupid) if (($devtype == 6) || ($devtype == 7));

    return Log3Return($name, "$cmd is not allowed for this device !");
}

sub _handle_Peering {

    my $hash    = shift;
    my $cmd     = shift;
    my $name    = $hash->{NAME};
    my $devtype = int($hash->{devtype});
    my $culmax  = ($hash->{IODev}->{TYPE} eq 'CUL_MAX') ? 1 : 0;

    if ($cmd eq 'factoryReset') {
	return Log3Return($name, "invalid device type $hash->{type}", 3) if (!$devtype || ($hash->{type} =~ m{\Avirtual}xms));
	MAX_ReadingsVal($hash,'lastcmd','set_factoryReset');
	return ($culmax) ? ($hash->{IODev}{Send})->($hash->{IODev}, 'Reset', $hash->{addr}) : ($hash->{IODev}{RemoveDevice})->($hash->{IODev}, $hash->{addr});
    }

    my $partner = shift // return "$name, set $cmd : missig device name or address !";

    my $partnerType;

    Log3($name, 5, "$name, _handle_Peering: $cmd | $partner");

    if ($partner eq 'fakeWallThermostat') {
	return "$name, set $cmd : IODev is not CUL_MAX" if (!$culmax);
	$partner = AttrVal($hash->{IODev}->{NAME}, 'fakeWTaddr', '111111');
	return "$name, invalid fakeWTaddr attribute set (must not be 000000)" if ($partner eq '000000');
	$partnerType = 3;
    } 
    elsif ($partner eq 'fakeShutterContact') {
	return "$name, set $cmd : IODev is not CUL_MAX" if (!$culmax);
	$partner = AttrVal($hash->{IODev}->{NAME}, 'fakeSCaddr', '222222');
	return "$name, invalid fakeSCaddr attribute set (must not be 000000)"  if ($partner eq '000000');
	$partnerType = 4;
    } 
    else {
	if ($partner !~ m{\A[a-fA-F0-9]{6}\z}x) { # ist wohl der Name , keine HEX Adresse
	    return "$name, set $cmd : partner $partner not found !"           if (!exists($defs{$partner}{TYPE}));
	    return "$name, set $cmd : partner $partner is not a MAX device !" if ($defs{$partner}{TYPE} ne 'MAX');
	    $partner  = $defs{$partner}{addr}; # übersetzung des Namens in HEX Adresse
	}
	
	$partner = lc($partner);
	return "$name, set $cmd : no MAX device found with address $partner !"   if (!exists($modules{MAX}{defptr}{$partner}));

	$partnerType = MAX_TypeToTypeId($modules{MAX}{defptr}{$partner}{type});
	return "$name, set $cmd : partner $partner , invalid device type !" if (!$partnerType);

	# die virtuellen Typen in echte wandeln
	$partnerType = 4 if ($partnerType == 6);
	$partnerType = 3 if ($partnerType == 7);
    }

    Log3($name, 4, "$name, Setting $cmd, Partner $partner, Type $partnerType");

    MAX_ReadingsVal($hash, 'lastcmd', 'set_'.$cmd.' '. $partner);

    my $pT = sprintf('%s%02x', $partner, $partnerType);
    my $lp  = ($cmd eq 'associate') ? 'AddLinkPartner' : 'RemoveLinkPartner';

    return ($hash->{IODev}{Send})->($hash->{IODev}, $lp, $hash->{addr}, $pT, callbackParam => "$cmd,$partner") if ($culmax);
    return ($hash->{IODev}{Send})->($hash->{IODev}, $lp, $hash->{addr}, $pT);
}

sub _handle_SetOpenClose {

    my $hash    = shift;
    my $cmd     = shift;
    my $arg     = shift;
    my $name    = $hash->{NAME};
    my $devtype = int($hash->{devtype});

    my $dest     = '';
    my $state    = ($cmd eq 'open') ? '12' : '10';
    my $groupid  = int(MAX_ReadingsVal($hash, 'groupid'));
    my $sendMode = AttrVal($name, 'sendMode', 'Broadcast');

    my $ret;

    Log3($name, 4, "$name, _handle_OpenClose: $cmd | $arg");

    return "$name, wrong device type $devtype" if ($devtype != 6);
    return "$name, IODev is not CUL_MAX" if ($hash->{IODev}->{TYPE} ne 'CUL_MAX');

    if ($groupid && ($sendMode eq 'group')) {
	# alle Gruppenmitglieder finden
	foreach my $dev (keys %{$modules{MAX}{defptr}}) {
	    my $dname = (defined($modules{MAX}{defptr}{$dev}->{NAME})) ? $modules{MAX}{defptr}{$dev}->{NAME} : '' ;
	    next if (!$dname || ($dname eq $name) || (ReadingsNum($dname, 'groupid', 0) != $groupid)); # kein Name oder er selbst oder nicht in der Gruppe
	    $dest = $modules{MAX}{defptr}{$dev}->{addr};

	    Log3($hash, 5, "$name, send $cmd [$state] to $dest as member of group $groupid");
	    
	    my $flags = ($groupid) ? '04' : '06';
	    $groupid = sprintf('%02x', $groupid);

	    my $r = $hash->{IODev}{Send}->($hash->{IODev},
					   'ShutterContactState',
					   $dest,
					   $state,
					   groupId => $groupid,
					   flags   => $flags,
					   src     => $hash->{addr}
					  );
	    $ret .= $r if ($r);
	}
    }

    if ($sendMode eq 'peers') {
	my @peers = split(',', AttrVal($name,'peers',''));
	foreach my $peer (@peers) {
	    next if (!$peer);
	    $dest = lc($peer);
	    $dest =~ s/ //g;
	    next if ($dest !~ m{\A[a-f0-9]{6}\z}x); # addr 6 digits hex
	    Log3($name, 5, "$name, send $cmd [$state] to $dest as member of attribut peers [".AttrVal($name,'peers','???').']');

	    my $flags = ($groupid) ? '04' : '06';
	    $groupid = sprintf('%02x', $groupid);

	    my $r = $hash->{IODev}{Send}->($hash->{IODev},
					   'ShutterContactState',
					   $dest,
					   $state,
					   groupId => $groupid,
					   flags   => $flags,
					   src     => $hash->{addr}
					  );
	    $ret .= $r if ($r);
	}
    }

    if ($sendMode eq 'Broadcast') {
	$dest = '000000';
	Log3($name, 5, "$name, send $cmd [$state] to $dest as Broadcast message");
	my $flags = ($groupid) ? '04' : '06';
	$groupid = sprintf('%02x',$groupid);
	$ret = $hash->{IODev}{Send}->($hash->{IODev},
				      'ShutterContactState',
				      $dest,
				      $state,
				      groupId => $groupid,
				      flags   => $flags,
				      src     => $hash->{addr}
				     );
    }

    return Log3Return($name,  "no destination devices found for sendmode $sendMode !", 2) if (!$dest);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'onoff', (($cmd eq 'close') ? '0' : '1'));
    readingsBulkUpdate($hash,'state', (($cmd eq 'close') ? 'closed' : 'opened'));
    readingsBulkUpdate($hash,'windowOpen','0') if (AttrNum($name,'windowOpenCheck',1) && ($cmd eq 'close'));

    ($arg) ? readingsEndUpdate($hash, 1) : readingsEndUpdate($hash, 0);

    if ($cmd eq 'open') { # die 1 Minuten Abfrage ab jetzt
	RemoveInternalTimer($hash);
	$hash->{'.timer'} = 60;
	OnTimer($hash);
    }

    return;
}

sub _handle_ConfigTemperature {

    my $hash    = shift;
    my $cmd     = shift // 'unknown';
    my $arg     = shift // 0;
    my $name    = $hash->{NAME};
    my $devtype = $hash->{devtype};

    return Log3Return($name, "_handle_ConfigTemperature: invalid command $cmd !") if (!exists($readingDef{$cmd}));
    return Log3Return($name, "missing parameter for command set $cmd !") if (!$arg);
    return Log3Return($name, "invalid parameter $arg for command set $cmd") if (!validTemperature($arg) && ($cmd ne 'measurementOffset'));
    return Log3Return($name, "invalid parameter $arg for command set $cmd") if (!validMeasurementOffset($arg) && ($cmd eq 'measurementOffset'));
    return Log3Return($name, "wrong device type $hash->{type} !") if ($hash->{type} !~ m{Thermostat}xms);


    Log3($hash, 4, "$name, ConfigTemperature: $cmd | $arg");

    my %h;
    $h{comfortTemperature}    = MAX_ReadingsVal($hash, 'comfortTemperature');
    $h{ecoTemperature}        = MAX_ReadingsVal($hash, 'ecoTemperature');
    $h{maximumTemperature}    = MAX_ReadingsVal($hash, 'maximumTemperature');
    $h{minimumTemperature}    = MAX_ReadingsVal($hash, 'minimumTemperature');
    $h{windowOpenTemperature} = MAX_ReadingsVal($hash, 'windowOpenTemperature');
    $h{windowOpenDuration}    = MAX_ReadingsVal($hash, 'windowOpenDuration');
    $h{measurementOffset}     = MAX_ReadingsVal($hash, 'measurementOffset');

    $h{$cmd}                  = ($cmd ne 'measurementOffset') ? ParseTemperature($arg) : $arg;

    MAX_ReadingsVal($hash, 'lastcmd', 'set_'.$cmd.' '.$arg);

    return MAX_ReadingsVal($hash, $cmd, $arg) if ($hash->{devtype} == 7);

    my $groupid  = ($cmd eq 'measurementOffset') ? 0 : MAX_ReadingsVal($hash, 'groupid');

    my $flags    = ($groupid) ? '04' : '00';
    $groupid     =  sprintf('%02x', $groupid);

    my $payload        = sprintf('%02x%02x%02x%02x%02x%02x%02x',
                         int($h{comfortTemperature}*2),
                         int($h{ecoTemperature}*2),
                         int($h{maximumTemperature}*2),
                         int($h{minimumTemperature}*2),
                         int(($h{measurementOffset} + 3.5)*2),
                         int($h{windowOpenTemperature}*2),
                         int($h{windowOpenDuration}/5)
			);

    Log3($hash, 5, "$name, ConfigTemperature: gid : $groupid,  pl : $payload, flags : $flags");

    return ($hash->{IODev}{Send})->($hash->{IODev},'ConfigTemperatures',$hash->{addr},$payload, groupId => $groupid, flags => $flags, callbackParam => "$cmd,$arg");
}

sub _handle_SetWeekProfile {

    my ($hash, undef, @args) = @_;

    my $name    = $hash->{NAME};
    my $devtype = $hash->{devtype};

    return Log3Return($name, 'missing parameter for set weekProfile !') if (!@args);
    return Log3Return($name, 'command weekProfile is not allowed for this device !') if (($hash->{type} !~ m{Thermostat}xms) && ($devtype != 8));

    Log3($hash, 4, "$name, _handle_ConfigWeekProfile: ".join(' ',@args));

    # Send wakeUp, so we can send the weekprofile pakets without preamble
    # Disabled for now. Seems like the first packet is lost. Maybe inserting a delay after the wakeup will fix this
    # WakeUp($hash) if ( @args > 2 );

    return Log3Return($name, "Invalid arguments. You must specify at least one: <weekDay> <temp[,hh:mm]>\nExample: Mon 10,06:00,17,09:00") if (@args%2 == 1);

    for (my $i = 0; $i < @args; $i += 2) {
	return Log3Return($name, 'Expected day (one of '.join (',',@weekDays).'), got '.$args[$i]) if (!exists($decalcDaysInv{$args[$i]}));

	my $day = $decalcDaysInv{$args[$i]};
	my @controlpoints = split(',', $args[$i+1]);

	return Log3Return($name, 'not more than 13 control points are allowed!') if (@controlpoints > 13*2);

	my $newWeekprofilePart = '';

	for (my $j = 0; $j < 13*2; $j += 2) {
        #for my $j (0..24) {
	    #next if odd($j);
	    if ( $j >= @controlpoints ) {
		$newWeekprofilePart .= '4520';
		next;
	    }

	    my $hour = 24;
	    my $min  =  0;

	    ($hour, $min) = ($controlpoints[$j+1] =~ /^(\d{1,2}):(\d{1,2})$/x) if (($j + 1) != @controlpoints);

	    my $temperature = $controlpoints[$j];
	    return Log3Return($name, "invalid time: $controlpoints[$j+1]") if (!defined($hour) || !defined($min) || $hour > 24 || $min > 59 || ($hour == 24 && $min != 0));
	    return Log3Return($name, "invalid temperature $temperature") if (!validTemperature($temperature));

	    $temperature = ParseTemperature($temperature); #replace "on" and "off" by their values
	    $newWeekprofilePart .= sprintf('%04x', (int($temperature*2) << 9) | int(($hour * 60 + $min)/5));
	}

	Log3($name, 5, "$name, new Temperature part for $day: $newWeekprofilePart");

	#Each day has 2 bytes * 13 controlpoints = 26 bytes = 52 hex characters
	#we don't have to update the rest, because the active part is terminated by the time 0:00

	if ($devtype != 7) { # virtualThermo
	#First 7 controlpoints (2*7=14 bytes => 2*2*7=28 hex characters )
	($hash->{IODev}{Send})->($hash->{IODev},'ConfigWeekProfile',$hash->{addr},
	sprintf('0%1d%s', $day, substr($newWeekprofilePart, 0, 28)),
	callbackParam => "$day,0,".substr($newWeekprofilePart, 0, 28));

	#And then the remaining 6
	($hash->{IODev}{Send})->($hash->{IODev},'ConfigWeekProfile',$hash->{addr},
	sprintf('1%1d%s', $day, substr($newWeekprofilePart, 28, 24)),
	callbackParam => "$day,1,".substr($newWeekprofilePart, 28, 24))
            if (@controlpoints > 14);
	}

	else{
	    my $wp = MAX_ReadingsVal($hash,'.weekProfile');
	    substr($wp, ($day*52), 52, $newWeekprofilePart);
	    MAX_ReadingsVal($hash, '.weekProfile', $wp);
	    readingsBeginUpdate($hash);
	    MAX_ParseWeekProfile($hash);
	    readingsEndUpdate($hash,0);
	    _saveConfig($name) if (AttrNum($name, 'autosaveConfig', 0));
	}
    }
    return;
}

##############################################################################

sub set_FW_HTML {

    my ($hash, $cmd, @args) = @_;

    my $name    = $hash->{NAME};
    my $devtype = int($hash->{devtype});

    my $assocList = MAX_createAssocList($hash, (defined($hash->{IODev}->{TYPE}) && ($hash->{IODev}->{TYPE} eq 'CUL_MAX')) ? 1 : 0);

    my $wplist = '';

    for my $dev (devspec2array('TYPE=weekprofile')) {
	$wplist .= (!$wplist) ?  $defs{$dev}->{NAME} : ','.$defs{$dev}->{NAME};
    }

    $wplist = (ReadingsVal($name,'.wp_json','') && $wplist) ? " export_Weekprofile:$wplist" : '';

    my $backuped_devs = MAX_BackupedDevs($name);

    if ($devtype == 8) { # virtual WT
	MAX_ReadingsVal($hash, 'groupid');
	MAX_ReadingsVal($hash, '.weekProfile');
    }

    use constant { ## no critic 'constant'
	TEMPLIST       => 'off,5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0,on',
	TEMPOFFSET     => '-3.5,-3,-2.5,-2,-1.5,-1,-0.5,0,0.5,1,1.5,2,2.5,3,3.5',
	BOOSTDURATION  => '0,5,10,15,20,25,30,60',
    };

    my @set12 = ('windowOpenDuration','decalcification','maxValveSetting','valveOffset','boostValveposition');

    my @set123 = ('desiredTemperature:eco,comfort,boost,auto,on,off,'.TEMPLIST ,
             'comfortTemperature:'.TEMPLIST,
             'ecoTemperature:'.TEMPLIST,
	     'measurementOffset:'.TEMPOFFSET,
             'boostDuration:'.BOOSTDURATION,
	     'maximumTemperature:'.TEMPLIST,
             'minimumTemperature:'.TEMPLIST,
             'windowOpenTemperature:'.TEMPLIST,
             'weekProfile',
            );

    my @set143 = ('wakeUp:noArg','factoryReset:noArg','groupid');

    my %device_sets = (
          'HeatingThermostat'     => [ 'saveConfig', @set123 , @set12, @set143 , 'deviceRename'],
          'HeatingThermostatPlus' => [ 'saveConfig', @set123 , @set12, @set143 , 'deviceRename'],
          'WallMountedThermostat' => [ 'saveConfig', @set123 , @set143 , 'deviceRename', 'displayActualTemperature:0,1' ],
          'ShutterContact'        => [ 'saveConfig', @set143 , 'deviceRename'],
          'PushButton'            => [ 'saveConfig', 'deviceRename'],
          'virtualShutterContact' => [ 'saveConfig', 'groupid' ],
          'virtualThermostat'     => [ 'saveConfig', @set123 ],
	  'PlugAdapter'           => [ 'saveConfig', 'weekprofile','desiredTemperature:eco,comfort,boost,auto,on,off,'.TEMPLIST, 'mode:auto,on,off' ],
	);

    my @sets =  values @{$device_sets{$hash->{type}}};
    my $s = join(' ', @sets );
    $s .= ($backuped_devs) ? " restoreReadings:$backuped_devs" : '';
    $s .= ($assocList)     ? " associate:$assocList deassociate:$assocList" : '';
    $s .= ($backuped_devs) ? " restoreDevice:$backuped_devs" : '' if ($devtype < 5);
    $s .= (ReadingsNum($name, 'groupid', 0)) ? ' open:noArg close:noArg' : '' if ($devtype == 6); # vSC;
    $s .= $wplist if ($devtype < 4);

    return AttrTemplate_Set ($hash, $s, $name, $cmd, @args);
}

##############################################################################

sub MAX_createAssocList {
    my $hash    = shift;
    my $culmax  = shift;

    my $name    = $hash->{NAME};
    my $devtype = $hash->{devtype};

    my @assolist;

    # Build list of devices which this device can be associated to

    if (($hash->{type} =~ m{\AHeatingThermostat}xms) || ($hash->{devtype} == 128)) {
	foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	    next if (!$modules{MAX}{defptr}{$dev}->{NAME});

	    if (($modules{MAX}{defptr}{$dev}->{devtype} < 16) # 1 - 4
	    && !IsDummy  ($modules{MAX}{defptr}{$dev}->{NAME}) 
	    && !IsIgnored($modules{MAX}{defptr}{$dev}->{NAME})
	    && ($modules{MAX}{defptr}{$dev}->{NAME} ne $name)
		) {
		    push  @assolist, $modules{MAX}{defptr}{$dev}->{NAME}; 
		}
	}
	    push @assolist, ('fakeShutterContact','fakeWallThermostat') if ($culmax);
    }

    if ($hash->{type} eq 'WallMountedThermostat') {
	foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	    next if (!$modules{MAX}{defptr}{$dev}->{NAME});

	    if (($modules{MAX}{defptr}{$dev}->{devtype} <  5) # 1,2,4 nachrechnen
	    && ($modules{MAX}{defptr}{$dev}->{devtype} != 3)
	    && !IsDummy  ($modules{MAX}{defptr}{$dev}->{NAME}) 
	    && !IsIgnored($modules{MAX}{defptr}{$dev}->{NAME})
		) {
		    push  @assolist, $modules{MAX}{defptr}{$dev}->{NAME}; 
		}
	}

	push @assolist, 'fakeShutterContact' if ($culmax);
    }

    if ($hash->{type} eq 'ShutterContact') {
	foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	    next if (!$modules{MAX}{defptr}{$dev}->{NAME});

	    if (($modules{MAX}{defptr}{$dev}->{type} =~ m{Thermostat\z}xms)
	    && !IsDummy  ($modules{MAX}{defptr}{$dev}->{NAME}) 
	    && !IsIgnored($modules{MAX}{defptr}{$dev}->{NAME})
		) {
		    push  @assolist, $modules{MAX}{defptr}{$dev}->{NAME}; 
		}
	}
    }

    return join(',', sort @assolist);
}

##############################################################################

1;

__END__

=pod

=encoding utf8

=item device
=item summary controls an MAX! device
=item summary_DE Steuerung eines MAX! Geräts
=begin html

<a name="MAX"></a>
<h3>MAX</h3>
<ul>
  Devices from the eQ-3 MAX! group.<br>
  When heating thermostats show a temperature of zero degrees, they didn't yet send any data to the cube. You can
  force the device to send data to the cube by physically setting a temperature directly at the device (not through fhem).
  <br><br>
  <a name="MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAX &lt;type&gt; &lt;addr&gt;</code>
    <br><br>

    Define an MAX device of type &lt;type&gt; and rf address &lt;addr&gt.
    The &lt;type&gt; is one of HeatingThermostat, HeatingThermostatPlus, WallMountedThermostat, ShutterContact, PushButton, virtualShutterContact.
    The &lt;addr&gt; is a 6 digit hex number.
    You should never need to specify this by yourself, the <a href="#autocreate">autocreate</a> module will do it for you.<br>
    Exception : virtualShutterContact<br>
    It's advisable to set event-on-change-reading, like
    <code>attr MAX_123456 event-on-change-reading .*</code>
    because the polling mechanism will otherwise create events every 10 seconds.<br>

    Example:
    <ul>
      <code>define switch1 MAX PushButton ffc545</code><br>
    </ul>
  </ul>
  <br>

  <a name="MAXset"></a>
  <b>Set</b>
  <ul>
  <a name=""></a><li>deviceRename &lt;value&gt; <br>
   rename of the device and its logfile
  </li>
    <a name=""></a><li>desiredTemperature auto [&lt;temperature&gt;]<br>
        For devices of type HeatingThermostat only. If &lt;temperature&gt; is omitted,
        the current temperature according to the week profile is used. If &lt;temperature&gt; is provided,
        it is used until the next switch point of the week porfile. It maybe one of
        <ul>
          <li>degree celcius between 4.5 and 30.5 in 0.5 degree steps</li>
          <li>"on" or "off" set the thermostat to full or no heating, respectively</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
        </ul></li>
    <a name=""></a><li>desiredTemperature [manual] &lt;value&gt; [until &lt;date&gt;]<br>
        For devices of type HeatingThermostat only. &lt;value&gt; maybe one of
        <ul>
          <li>degree celcius between 4.5 and 30.5 in 0.5 degree steps</li>
          <li>"on" or "off" set the thermostat to full or no heating, respectively</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
        </ul>
        The optional "until" clause, with &lt;data&gt; in format "dd.mm.yyyy HH:MM" (minutes may only be "30" or "00"!),
        sets the temperature until that date/time. Make sure that the cube/device has a correct system time.
        If the keepAuto attribute is 1 and the device is currently in auto mode, 'desiredTemperature &lt;value&gt;'
        behaves as 'desiredTemperature auto &lt;value&gt;'. If the 'manual' keyword is used, the keepAuto attribute is ignored
        and the device goes into manual mode.</li>
    <a name=""></a><li>desiredTemperature boost<br>
      For devices of type HeatingThermostat only.
      Activates the boost mode, where for boostDuration minutes the valve is opened up boostValveposition percent.</li>
    <a name=""></a><li>groupid &lt;id&gt;<br>
      For devices of type HeatingThermostat only.
      Writes the given group id the device's memory. To sync all devices in one room, set them to the same groupid greater than zero.</li>
    <a name=""></a><li>ecoTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given eco temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <a name=""></a><li>comfortTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given comfort temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <a name=""></a><li>measurementOffset &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. If the internal temperature sensor is not well calibrated, it may produce a systematic error. Using measurementOffset, this error can be compensated. The reading temperature is equal to the measured temperature at sensor + measurementOffset. Usually, the internally measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small negative offset. Must be between -3.5 and 3.5 degree celsius.</li>
    <a name=""></a><li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <a name=""></a><li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <a name=""></a><li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected. Setting it to 4.5 degree or "off" will turn off reacting on open windows.</li>
    <a name=""></a><li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
    <a name=""></a><li>decalcification &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given decalcification time to the device's memory. Value must be of format "Sat 12:00" with minutes being "00". Once per week during that time, the HeatingThermostat will open the valves shortly for decalcification.</li>
    <a name=""></a><li>boostDuration &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost duration to the device's memory. Value must be one of 5, 10, 15, 20, 25, 30, 60. It is the duration of the boost function in minutes.</li>
    <a name=""></a><li>boostValveposition &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost valveposition to the device's memory. It is the valve position in percent during the boost function.</li>
    <a name=""></a><li>maxValveSetting &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given maximum valveposition to the device's memory. The heating thermostat will not open the valve more than this value (in percent).</li>
    <a name=""></a><li>valveOffset &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given valve offset to the device's memory. The heating thermostat will add this to all computed valvepositions during control.</li>
    <a name=""></a><li>factoryReset<br>
        Resets the device to factory values. It has to be paired again afterwards.<br>
        ATTENTION: When using this on a ShutterContact using the MAXLAN backend, the ShutterContact has to be triggered once manually to complete
        the factoryReset.</li>
    <a name=""></a><li>associate &lt;value&gt;<br>
        Associated one device to another. &lt;value&gt; can be the name of MAX device or its 6-digit hex address.<br>
        Associating a ShutterContact to a {Heating,WallMounted}Thermostat makes it send message to that device to automatically lower temperature to windowOpenTemperature while the shutter is opened. The thermostat must be associated to the ShutterContact, too, to accept those messages.
        <b>!Attention: After sending this associate command to the ShutterContact, you have to press the button on the ShutterContact to wake it up and accept the command. See the log for a message regarding this!</b>
        Associating HeatingThermostat and WallMountedThermostat makes them sync their desiredTemperature and uses the measured temperature of the
 WallMountedThermostat for control.</li>
    <a name=""></a><li>deassociate &lt;value&gt;<br>
        Removes the association set by associate.</li>
    <a name=""></a><li>weekProfile [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] ...<br>
      Allows setting the week profile. For devices of type HeatingThermostat or WallMountedThermostat only. Example:<br>
      <code>set MAX_12345 weekProfile Fri 24.5,6:00,12,15:00,5 Sat 7,4:30,19,12:55,6</code><br>
      sets the profile <br>
      <code>Friday: 24.5 &deg;C for 0:00 - 6:00, 12 &deg;C for 6:00 - 15:00, 5 &deg;C for 15:00 - 0:00<br>
      Saturday: 7 &deg;C for 0:00 - 4:30, 19 &deg;C for 4:30 - 12:55, 6 &deg;C for 12:55 - 0:00</code><br>
      while keeping the old profile for all other days.
    </li>
    <a name=""></a><li>saveConfig &lt;name&gt;<br>

    </li>

    <a name=""></a><li>restoreReadings &lt;name of saved config&gt;<br>

    </li>

    <a name=""></a><li>restoreDevice &lt;name of saved config&gt;<br>

    </li>

    <a name=""></a><li>exportWeekprofile &lt;name od weekprofile device&gt;<br>

    </li>

  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="actCycle"></a><li>actCycle &lt;hh:mm&gt; default none (only with CUL_MAX)<br>
    Provides life detection for the device. [hhh: mm] sets the maximum time without a message from this device.<br>
    If no messages are received within this time, the reading activity is set to dead.<br>
    If the device sends again, the reading is reset to alive.<br>
    <b>Important</b> : does not make sense with the ECO Pushbutton,<br>
    as it is the only member of the MAX! family that does not send cyclical status messages !</li><br>
    <a name="CULdev"></a><li>CULdev &lt;name&gt; default none (only with CUL_MAX)<br>
    send device when the CUL_MAX device is using a IOgrp (Multi IO)</li><br>
    <a name="DbLog_log_onoff"></a><li>DbLog_log_onoff (0|1) log on  and off or the real values 30.5 and 4.5</li><br>
    <a name="dummy"></a><li>dummy (0|1) default 0<br>sets device to a read-only device</li><br>
    <a name="debug"></a><li>debug (0|1) default 0<br>creates extra readings (only with CUL_MAX)</li><br>
    <a name="dTempCheck"></a><li>dTempCheck (0|1) default 0<br>
    monitors every 5 minutes whether the Reading desiredTemperature corresponds to the target temperature in the current weekprofile.<br>
    The result is a deviation in Reading dTempCheck, i.e. 0 = no deviation</li><br>
    <a name="externalSensor"></a><li>externalSensor &lt;device:reading&gt; default none<br>
    If there is no wall thermostat in a room but the room temperature is also recorded with an external sensor in FHEM (e.g. LaCrosse)<br>
    the current temperature value can be used to calculate the reading deviation instead of the own reading temperature</li><br>
    <a name="IODev"></a><li>IODev &lt;name&gt;<br>MAXLAN or CUL_MAX device name</li><br>
    <a name="keepAuto"></a><li>keepAuto (0|1) default 0<br>If set to 1, it will stay in the auto mode when you set a desiredTemperature while the auto (=weekly program) mode is active.</li><br>
    <a name="scanTemp"></a><li>scanTemp (0|1) default 0<br>used by MaxScanner</li><br>
    <a name="skipDouble"></a><li>skipDouble (0|1) default 0 (only with CUL_MAX)<br></li>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>desiredTemperature<br>Only for HeatingThermostat and WallMountedThermostat</li>
    <li>valveposition<br>Only for HeatingThermostat</li>
    <li>battery</li>
    <li>batteryState</li>
    <li>temperature<br>The measured temperature (= measured temperature at sensor + measurementOffset), only for HeatingThermostat and WallMountedThermostat</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="MAX"></a>
<h3>MAX</h3>
<ul>
  Verarbeitet MAX! Ger&auml;te, die von der eQ-3 MAX! Gruppe hergestellt werden.<br>
  Falls Heizk&ouml;rperthermostate eine Temperatur von Null Grad zeigen, wurde von ihnen
  noch nie Daten an den MAX Cube gesendet. In diesem Fall kann das Senden von Daten an
  den Cube durch Einstellen einer Temeratur direkt am Ger&auml;t (nicht &uuml;ber fhem)
  erzwungen werden.
  <br><br>
  <a name="MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAX &lt;type&gt; &lt;addr&gt;</code>
    <br><br>

    Erstellt ein MAX Ger&auml;t des Typs &lt;type&gt; und der RF Adresse &lt;addr&gt;.
    Als &lt;type&gt; kann entweder <code>HeatingThermostat</code> (Heizk&ouml;rperthermostat),
    <code>HeatingThermostatPlus</code> (Heizk&ouml;rperthermostat Plus),
    <code>WallMountedThermostat</code> (Wandthermostat), <code>ShutterContact</code> (Fensterkontakt),
    <code>PushButton</code> (Eco-Taster) oder <code>virtualShutterContact</code> (virtueller Fensterkontakt) gew&auml;hlt werden.
    Die Adresse &lt;addr&gt; ist eine 6-stellige hexadezimale Zahl.
    Da <a href="#autocreate">autocreate</a> diese vergibt, sollte diese eigentlich nie h&auml;ndisch gew&auml;hlt
    werden m&uuml;ssen. Ausnahme : virtueller Fensterkontakt<br>
    Es wird dringend  empfohlen das Atribut event-on-change-reading zu setzen, z.B.
    <code>attr MAX_123456 event-on-change-reading .*</code> da ansonsten der "Polling" Mechanismus
    alle 10 s ein Ereignis erzeugt.<br>

    Beispiel:
    <ul>
      <code>define switch1 MAX PushButton ffc545</code><br>
    </ul>
  </ul>
  <br>

  <a name="MAXset"></a>
  <b>Set</b>
  <ul>
    <a name="associate"></a><li>associate &lt;value&gt;<br>
      Verbindet ein Ger&auml;t mit einem anderen. &lt;value&gt; kann entweder der Name eines MAX Ger&auml;tes oder
      seine 6-stellige hexadezimale Adresse sein.<br>
      Wenn ein Fensterkontakt mit einem HT/WT verbunden wird, sendet der Fensterkontakt automatisch die <code>windowOpen</code> Information wenn der Kontakt
      ge&ouml;ffnet ist. Das Thermostat muss ebenfalls mit dem Fensterkontakt verbunden werden, um diese Nachricht zu verarbeiten.
      <b>Achtung: Nach dem Senden der Botschaft zum Verbinden an den Fensterkontakt muss der Knopf am Fensterkontakt gedr&uuml;ckt werden um den Fensterkonakt aufzuwecken
      und den Befehl zu verarbeiten. Details &uuml;ber das erfolgreiche Verbinden finden sich in der Logdatei!</b>
      Das Verbinden eines Heizk&ouml;rperthermostates und eines Wandthermostates synchronisiert deren
      <code>desiredTemperature</code> und verwendet die am Wandthermostat gemessene Temperatur f&uuml;r die Regelung.</li>

    <a name="comfortTemperature"></a><li>comfortTemperature &lt;value&gt;<br>
      Nur f&uuml;r HT/WT. Schreibt die angegebene <code>comfort</code> Temperatur in den Speicher des Ger&auml;tes.<br>
      Diese kann durch dr&uuml;cken der Taste Halbmond/Stern am Ger&auml;t aktiviert werden.</li>

    <a name="deassociate"></a><li>deassociate &lt;value&gt;<br>
      L&ouml;st die Verbindung, die mit <code>associate</code> gemacht wurde, wieder auf.</li>

    <a name="desiredTemperature"></a><li>desiredTemperature &lt;value&gt; [until &lt;date&gt;]<br>
        Nur f&uuml;r HT/WT &lt;value&gt; kann einer aus folgenden Werten sein
        <ul>
          <li>Grad Celsius zwischen 4,5 und 30,5 Grad Celisus in 0,5 Grad Schritten</li>
          <li>"on" (30.5) oder "off" (4.5) versetzt den Thermostat in volle Heizleistung bzw. schaltet ihn ab</li>
          <li>"eco" oder "comfort" mit der eco/comfort Temperatur, die direkt am Ger&auml;t
              eingestellt wurde (&auml;nhlich wie die Halbmond/Stern Taste am Ger&auml;t selbst)</li>
          <li>"auto &lt;temperature&gt;". Damit wird das am Thermostat eingestellte Wochenprogramm
              abgearbeitet. Wenn optional die Temperatur &lt;temperature&gt; angegeben wird, wird diese
              bis zum n&auml;sten Schaltzeitpunkt des Wochenprogramms als <code>desiredTemperature</code> gesetzt.</li>
          <li>"boost" aktiviert den Boost Modus, wobei f&uuml;r <code>boostDuration</code> Minuten
              das Ventil <code>boostValveposition</code> Prozent ge&ouml;ffnet wird.</li>
        </ul>
        Alle Werte au&szlig;er "auto" k&ouml;nnen zus&auml;zlich den Wert "until" erhalten,
        wobei &lt;date&gt; in folgendem Format sein mu&szlig;: "TT.MM.JJJJ SS:MM"
        (Minuten nur 30 bzw. 00 !), um kurzzeitige eine andere Temperatur bis zu diesem Datum und dieser
        Zeit einzustellen. Wichtig : der Zeitpunkt muß in der Zukunft liegen !<br>
	Wenn dd.mm.yyyy dem heutigen Tag entspricht kann statdessen auch das Schl&uml;sselwort today verwendet werden.
	Bitte sicherstellen, dass der Cube bzw. das Ger&auml;t die korrekte Systemzeit hat</li>

      <a name="deviceRename"></a><li>deviceRename &lt;value&gt; <br>
	Benennt das Device um, inklusive dem durch autocreate erzeugtem Logfile</li>

     <a name="ecoTemperature"></a><li>ecoTemperature &lt;value&gt;<br>
      Nur f&uuml;r HT/WT. Schreibt die angegebene <code>eco</code> Temperatur in den Speicher
      des Ger&auml;tes. Diese kann durch Dr&uuml;cken der Halbmond/Stern Taste am Ger&auml;t aktiviert werden.</li>

    <a name="export_Weekprofile"></a><li>export_Weekprofile [device weekprofile name]</li>

    <a name="factoryReset"></a><li>factoryReset<br>
      Setzt das Ger&auml;t auf die Werkseinstellungen zur&uuml;ck. Das Ger&auml;t muss anschlie&szlig;end neu angelernt werden.<br>
      ACHTUNG: Wenn dies in Kombination mit einem Fensterkontakt und dem MAXLAN Modul
      verwendet wird, muss der Fensterkontakt einmal manuell ausgel&ouml;st werden, damit das Zur&uuml;cksetzen auf Werkseinstellungen beendet werden kann.</li>


    <a name="groupid"></a><li>groupid &lt;id&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate.
      Schreibt die angegebene Gruppen ID in den Speicher des Ger&auml;tes.
      Um alle Ger&auml;te in einem Raum zu synchronisieren, k&ouml;nnen diese derselben Gruppen ID
      zugeordnet werden, diese mu&szlig; gr&ouml;&szlig;er Null sein.</li>

    <a name="measurementOffset"></a><li>measurementOffset &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene <code>offset</code> Temperatur in den Speicher
      des Ger&auml;tes. Wenn der interne Temperatursensor nicht korrekt kalibriert ist, kann dieses einen
      systematischen Fehler erzeugen. Mit dem Wert <code>measurementOffset</code>, kann dieser Fehler
      kompensiert werden. Die ausgelese Temperatur ist gleich der gemessenen
      Temperatur + <code>measurementOffset</code>. Normalerweise ist die intern gemessene Temperatur h&ouml;her
      als die Raumtemperatur, da der Sensor n&auml;her am Heizk&ouml;rper ist und man verwendet einen
      kleinen negativen Offset, der zwischen -3,5 und 3,5 Kelvin sein mu&szlig;.</li>
    <a name="minimumTemperature"></a><li>minimumTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>minimum</code> Temperatur in der Speicher
      des Ger&auml;tes. Diese begrenzt die Temperatur, die am Ger&auml;t manuell eingestellt werden kann.</li>
    <a name="maximumTemperature"></a><li>maximumTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>maximum</code> Temperatur in der Speicher
      des Ger&auml;tes. Diese begrenzt die Temperatur, die am Ger&auml;t manuell eingestellt werden kann.</li>
    <a name="windowOpenTemperature"></a><li>windowOpenTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>window open</code> Temperatur in den Speicher
      des Ger&auml;tes. Das ist die Tempereratur, die an der Heizung kurzfristig eingestellt wird, wenn ein
      ge&ouml;ffnetes Fenster erkannt wird. Der Wert 4,5 Grad bzw. "off" schaltet die Reaktion auf
      ein offenes Fenster aus.</li>
    <a name="windowOpenDuration"></a><li>windowOpenDuration &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene <code>window</code> open Dauer in den Speicher
      des Ger&auml;tes. Dies ist die Dauer, w&auml;hrend der die Heizung kurzfristig die window open Temperatur
      einstellt, wenn ein offenes Fenster durch einen schnellen Temperatursturz erkannt wird.
      (Wird nicht verwendet, wenn das offene Fenster von <code>ShutterControl</code> erkannt wird.)
      Parameter muss zwischen Null und 60 Minuten sein als Vielfaches von 5.</li>
    <a name="decalcification"></a><li>decalcification &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Zeit f&uuml;r <code>decalcification</code>
      in den Speicher des Ger&auml;tes. Parameter muss im Format "Sat 12:00" sein, wobei die Minuten
      "00" sein m&uuml;ssen. Zu dieser angegebenen Zeit wird das Heizk&ouml;rperthermostat das Ventil
      kurz ganz &ouml;ffnen, um vor Schwerg&auml;ngigkeit durch Kalk zu sch&uuml;tzen.</li>
    <a name="boostDuration"></a><li>boostDuration &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Boost Dauer in den Speicher
      des Ger&auml;tes. Der gew&auml;hlte Parameter muss einer aus 5, 10, 15, 20, 25, 30 oder 60 sein
      und gibt die Dauer der Boost-Funktion in Minuten an.</li>
    <a name="boostValveposition"></a><li>boostValveposition &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Boost Ventilstellung in den Speicher
      des Ger&auml;tes. Dies ist die Ventilstellung (in Prozent) die bei der Boost-Fumktion eingestellt wird.</li>
    <a name="maxValveSetting"></a><li>maxValveSetting &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene maximale Ventilposition in den Speicher
      des Ger&auml;tes. Der Heizk&ouml;rperthermostat wird das Ventil nicht weiter &ouml;ffnen als diesen Wert
      (Angabe in Prozent).</li>
    <a name="valveOffset"></a><li>valveOffset &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt den angegebenen <code>offset</code> Wert der Ventilstellung
      in den Speicher des Ger&auml;tes Der Heizk&ouml;rperthermostat wird diesen Wert w&auml;hrend der Regelung
      zu den berechneten Ventilstellungen hinzuaddieren.</li>


    <a name="weekProfile"></a><li>weekProfile [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;]
      [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] ...<br>
      Erlaubt das Setzen eines Wochenprofils. Nur f&uuml;r Heizk&ouml;rperthermostate bzw. Wandthermostate.<br>
      Beispiel:<br>
      <code>set MAX_12345 weekProfile Fri 24.5,6:00,12,15:00,5 Sat 7,4:30,19,12:55,6</code><br>
      stellt das folgende Profil ein<br>
      <code>Freitag: 24.5 &deg;C von 0:00 - 6:00, 12 &deg;C von 6:00 - 15:00, 5 &deg;C von 15:00 - 0:00<br>
      Samstag: 7 &deg;C von 0:00 - 4:30, 19 &deg;C von 4:30 - 12:55, 6 &deg;C von 12:55 - 0:00</code><br>
      und beh&auml;lt die Profile f&uuml;r die anderen Wochentage bei.
    </li>
    <a name="saveConfig">saveConfig</a><li>saveConfig [name]</li>
    <a name="restoreRedings"></a><li>restoreRedings [name]</li>
    <a name="restoreDevice"></a><li>restoreDevice [name]</li>
  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b>
   <ul>
   <a name=""></a><li>show_savedConfig <device><br>
   zeigt gespeicherte Konfigurationen an die mittels set restoreReadings / restoreDevice verwendet werden k&ouml;nnen<br>
   steht erst zur Verf&uuml;gung wenn für dieses Ger&auml;t eine gespeichrte Konfiguration gefunden wurde.
   </li>
  </ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="actCycle"></a> <li>actCycle &lt;hh:mm&gt; default leer (nur mit CUL_MAX)<br>
    Stellt eine Lebenserkennung für das Ger&auml;t zur Verf&uuml;gung. [hhh:mm] legt die maximale Zeit ohne eine Nachricht dieses Ger&auml;ts fest.<br>
    Wenn innerhalb dieser Zeit keine Nachrichten empfangen werden wird das Reading Actifity auf dead gesetzt.<br>
    Sendet das Ger&auml;t wieder wird das Reading auf alive zur&uuml;ck gesetzt.<br>
    <b>Wichtig</b> : Der Einsatz ist Nicht sinnvoll beim ECO Taster, da dieser als einziges Mitglied der MAX! Familie keine zyklischen Statusnachrichten verschickt !</li><br>
    <a name="CULdev"></a><li>CULdev &lt;name&gt; default leer (nur mit CUL_MAX)<br>
    CUL der zum senden benutzt wird wenn CUL_MAX eine IO Gruppe verwendet (Multi IO )</li><br>

    <a name="DbLog_log_onoff"></a><li>DbLog_log_onoff (0|1) schreibe die Werte on und off als Text in die DB oder ersetzt sie direkt durch
    ihre numerischen Werte 30.5 and 4.5<br>Hilfreich bei Plots da auf eine extra Plotfunktion verzichtet werden kann.</li><br>

    <a name="debug"></a><li>debug (0|1) default 0<br>erzeugt zus&auml;tzliche Readings (nur mit CUL_MAX)</li><br>

    <a name="dTempCheck"></a><li>dTempCheck (0|1) default 0<br>&uuml;berwacht im Abstand von 5 Minuten ob das Reading desiredTemperatur
     der Soll Temperatur im aktuellen Wochenprofil entspricht. (nur f&uuml; Ger&aumk;te vom Typ HT oder WT)<br>
     Das Ergebniss steht als Abweichung im Reading dTempCheck, d.h. 0 = keine Abweichung<br>
     Die &Uuml;berwachung is nur aktiv wenn die Soll Temperatur ungleich der Window Open Temperatur ist</li><br>

    <a name="dummy"></a><li>dummy (0|1) default 0<br>macht das Device zum read-only Device</li><br>

    <a name="externalSensor"></a><li>externalSensor &lt;device:reading&gt; default none<br>
    Wenn in einem Raum kein Wandthermostat vorhanden ist aber die Raumtemperatur zus&auml;tlich mit einem externen Sensor in FHEM erfasst wird (z.B. LaCrosse)<br>
    kann dessen aktueller Temperatur Wert zur Berechnung des Readings deviation benutzt werden statt des eigenen Readings temperature</li><br>

    <a name="IODev"></a><li>IODev &lt;name&gt;<br> MAXLAN oder CUL_MAX Device Name</li><br>

    <a name="keepAuto"></a><li>keepAuto (0|1) default 0<br>Wenn der Wert auf 1 gesetzt wird, bleibt das Ger&auml;t im Wochenprogramm auch wenn ein desiredTemperature gesendet wird.</li><br>

    <a name="scanTemp"></a><li>scanTemp (0|1) default 0<br>wird vom MaxScanner benutzt</li><br>

    <a name="skipDouble"></a><li>skipDouble (0|1) default 0 (nur mit CUL_MAX)<br>
    Wenn mehr als ein Thermostat zusammmen mit einem Fensterkontakt und/oder einem Wandthermostst eine Gruppe bildet,<br>
    versendet jedes Mitglieder der Gruppe seine Statusnachrichten einzeln an jedes andere Mitglied der Gruppe.<br>
    Das f&uuml;hrt dazu das manche Events doppelt oder sogar dreifach ausgel&ouml;st werden, kann mit diesem Attribut unterdr&uuml;ckt werden.</li><br>

    <a name="windowOpenCheck"></a><li>windowOpenCheck (0|1)<br>&uuml;berwacht im Abstand von 5 Minuten ob bei Geräten vom Typ ShutterContact das Reading onoff den Wert 1 hat (Fenster offen , default 1)<br>
     oder bei Geräten vom Typ HT/WT ob die Soll Temperatur gleich der Window Open Temperatur ist (default 0). Das Ergebniss steht im Reading windowOpen, Format hh:mm</li><br>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Erzeugte Ereignisse:</b>
  <ul>
    <li>desiredTemperature<br>Nur f&uuml;r Heizk&ouml;rperthermostate und Wandthermostate</li>
    <li>valveposition<br>Nur f&uuml;r Heizk&ouml;rperthermostate</li>
    <li>battery</li>
    <li>batteryState</li>
    <li>temperature<br>Die gemessene Temperatur (= gemessene Temperatur + <code>measurementOffset</code>),
       nur f&uuml;r Heizk&ouml;rperthermostate und Wandthermostate</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 10_MAX.pm

{
  "abstract": "controls a MAX! device",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Steuerung von MAX! Geräten"
    }
  },
  "keywords": [ "MAX" ],
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
        "Date::Parse": 0,
        "Time::HiRes": 0,
        "Time::Local": 0
     },
      "recommends": { "FHEM::Meta": 0 },
      "suggests": { "FHEM::AttrTemplate": 0 }
    }
  }
}
=end :application/json;q=META.json
=cut
