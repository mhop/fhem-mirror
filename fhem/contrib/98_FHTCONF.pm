################################################################################
# 98_FHTCONF.pm
#
# Konfiguration von FHTs
# 
################################################################################
package main;

use strict;
use warnings;
use Data::Dumper;
# FHEM Command to Update FHTs
sub Commandfhtconf($);
################################################################################
sub FHTCONF_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FHTCONF_Set";
  $hash->{StateFn}   = "FHTCONF_SetState";
  $hash->{DefFn}     = "FHTCONF_Define";
  $hash->{AttrList}  = "loglevel:0,5 disable:0,1 SendIntervall";
	# FHEM Command to Update FHTs
	$cmds{fhtconf}{Fn} = "Commandfhtconf";
	$cmds{fhtconf}{Hlp} = "FHTCONF[HELP]: fhtconf <FHTCONF-NAME>";
	
  Log 0, "FHEM-MODUL[98_FHTCONF.pm] LOADED";
}
################################################################################
sub FHTCONF_Define($)
{
    my ($hash, @a) = @_;
    Log 0, "FHTCONF|DEFINE|Anzahl ARG: " . int(@a);
    return "Wrong syntax: use define <name> fht_conf" if(int(@a) !=1 );
    # Default Room
    my $room = "GRP.FHTCONF";
		# INIT READINGs
		# FHT's
    $hash->{READINGS}{A0_FHT_DEVICES}{TIME} = TimeNow();
    $hash->{READINGS}{A0_FHT_DEVICES}{VAL} = "";
		#Mode
    # Values auto, manual, holiday or holiday_short
    $hash->{READINGS}{A1_mode}{TIME} = TimeNow();
    $hash->{READINGS}{A1_mode}{VAL} = "auto";
    # Temperaturen...defualt 5.5 = disable
    $hash->{READINGS}{A2_day_temp}{TIME} = TimeNow();
    $hash->{READINGS}{A2_day_temp}{VAL} = "5.5";
    $hash->{READINGS}{A2_night_temp}{TIME} = TimeNow();
    $hash->{READINGS}{A2_night_temp}{VAL} = "5.5";
    $hash->{READINGS}{A2_windowopen_temp}{TIME} = TimeNow();
    $hash->{READINGS}{A2_windowopen_temp}{VAL} = "5.5";
    # LowTemp-Offest
    $hash->{READINGS}{A2_lowtemp_offset}{TIME} = TimeNow();
    $hash->{READINGS}{A2_lowtemp_offset}{VAL} = "2.0";
		# Montag = Monday
    $hash->{READINGS}{B0_MONTAG}{TIME} = TimeNow();
    $hash->{READINGS}{B0_MONTAG}{VAL} = "24:00|24:00";
    # Dienstag = Tuesday
    $hash->{READINGS}{B1_DIENSTAG}{TIME} = TimeNow();
    $hash->{READINGS}{B1_DIENSTAG}{VAL} = "24:00|24:00";
    # Mittwoch = Wednesday
    $hash->{READINGS}{B2_MITTWOCH}{TIME} = TimeNow();
    $hash->{READINGS}{B2_MITTWOCH}{VAL} = "24:00|24:00";
    # Donnerstag = Thursday
    $hash->{READINGS}{B3_DONNERSTAG}{TIME} = TimeNow();
    $hash->{READINGS}{B3_DONNERSTAG}{VAL} = "24:00|24:00";
    # Freitag = Friday
    $hash->{READINGS}{B4_FREITAG}{TIME} = TimeNow();
    $hash->{READINGS}{B4_FREITAG}{VAL} = "24:00|24:00";
    # Samstag = Saturday
    $hash->{READINGS}{B5_SAMSTAG}{TIME} = TimeNow();
    $hash->{READINGS}{B5_SAMSTAG}{VAL} = "24:00|24:00";
    # Sonntag = Sunday
    $hash->{READINGS}{B6_SONNTAG}{TIME} = TimeNow();
    $hash->{READINGS}{B6_SONNTAG}{VAL} = "24:00|24:00";
		my $name = $hash->{NAME};
    #Room
    $attr{$name}{room} = $room;
		# State
		$hash->{STATE} = "Created " . TimeNow();
		return undef;
}
################################################################################
sub FHTCONF_SetState($)
{
	my ($hash, $tim, $vt, $val) = @_;
  Log 0,"FHTCONF SETSTATE: ". Dumper(@_);
  return undef;
}
################################################################################
sub FHTCONF_Set($)
{
	my ($hash, @a) = @_;
	Log 0, "FHTCONF DEFINE Anzahl ARG: " . int(@a);
	# 4 Argumente
	# 1. Device Selbst als HASH
	# $a[0] => Device Name als String
	# $a[1] => Reading
	# $a[2] => Value for READING
	return "Unknown argument $a[1], choose one of ". join(" ",sort keys %{$hash->{READINGS}}) if($a[1] eq "?");
	
	# A0_FHT_DEVICES => List of FHT-Devices seperated by -------------------------
	if($a[1] eq "A0_FHT_DEVICES") {
			Log 0, "FHTCONF[SET] => FHT_DEVICES = $a[1]";
			if($a[2] =~ /\|/) {
			my @fht_devices = split(/\|/,$a[2]);
					foreach my $device (@fht_devices){
							if (!defined($defs{$device}) || $defs{$device}{TYPE} ne "FHT") {
							return "FHTCONF[ERROR] => $device => Is Not defined or a FHT-DEVICE";}
					}
			 }
			else {
					if (!defined($defs{$a[2]}) || $defs{$a[2]}{TYPE} ne "FHT") {
					return "FHTCONF[ERROR] => $a[2] => Is Not defined or a FHT-DEVICE";}
			}
	}
	# A1_mode FHT Modes ----------------------------------------------------------
	if($a[1] eq "A1_mode") {
	Log 0, "FHT_CONF|SET|MODE-Values: auto,manual,holiday,holiday_short";
	my $mode_value_ok = undef;
	my @mode_values = ("auto","manual","holiday","holiday_short");
			foreach my $value(@mode_values) {
					if($a[2] =~ /$value/){
					$mode_value_ok = 1;
					}
			}
	if(!$mode_value_ok) {return "FHTCONF[ERROR] MODE $a[2]: choose on of auto,manual,holiday,holiday_short";}
	}
	# FHT-Temperatures => NUR Ziffern und EIN Punkt [0-9.] -----------------------
	if($a[1] =~ /^A2/) {
			if($a[2] =~ /[^0-9.]/) {
			return "FHTCONF|$a[2]|ERROR|wrong format: 00.00";
			}
			if($a[1] ne "A2_lowtemp_offset" && $a[2] < 5.5) {$a[2] = 5.5}; 
			Log 0, "FHTCONF[SET] => Temperatures => $a[1] = $a[2]";
	 }
	# B* FHT-Times
	if($a[1] =~ /^B/) {
	# Time Values
	# Sort-Array @b = sort(@b)
	# Values = 12:00;13:00 => mindestens 2 maximal 4; kein Wert über 24
	my @times = split(/\|/,$a[2]);
	Log 0, "FHT_TIMES[INFO] times = " . @times;
	if (@times ne 2 && @times ne 4) {
			return "FHT_TIMES[ERROR] Wrong Argument count";}
	foreach my $time (@times) {
			if (not ($time =~ /([01][0-9]:[0-4])|[0-5][0-9]/) ) {
			return "FHT_TIMES[ERROR] $time => 00:00";}
    }
    # Sort
    @times = sort(@times);
    $a[2] = join("|", @times);
	}
	# Set READINGs
	$hash->{READINGS}{$a[1]}{TIME} = TimeNow();
	$hash->{READINGS}{$a[1]}{VAL} = $a[2];
	return undef;
}
################################################################################
sub Commandfhtconf($)
{
	my ($cl, $dn) = @_;
	# $dn = FHTCONF Device-Name
	# Device exists
	if(!defined($defs{$dn})){
		Log 0, "FHTCONF CMD Device $dn not found";
		return undef;
		}
	# Type FHTCONF
	if($defs{$dn}{TYPE} ne "FHTCONF") {
		Log 0, "FHTCONF CMD $dn wrong Device-Type";
		return undef;
		}		
	# Device disabled
	if(defined($attr{$dn}{disable})) {
		Log 0, "FHTCONF CMD $dn disabled";
		return undef;
		}
	#LogLevel
  my $ll = 0;
	if(defined($attr{$dn}{'loglevel'})) {
		$ll = $attr{$dn}{'loglevel'};
		}
	Log $ll, "FHTCONF-CMD: $dn";
	#-----------------------------------------------------------------------------
	# Building FHEM-Commands to send
	# fhem "set <DAVEICE-NAME> params
	my (%params);
	$params{"mode"} = $defs{$dn}{READINGS}{A1_mode}{VAL};
	$params{"day-temp"} = $defs{$dn}{READINGS}{A2_day_temp}{VAL};
	$params{"night-temp"} = $defs{$dn}{READINGS}{A2_night_temp}{VAL};
	$params{"windowopen-temp"} = $defs{$dn}{READINGS}{A2_windowopen_temp}{VAL};
	$params{"lowtemp-offset"} = $defs{$dn}{READINGS}{A2_lowtemp_offset}{VAL};
	# Times ----------------------------------------------------------------------
	# Mapping ersten drei Buchstaben Wochentag => from1 to1 bzw. from2 to2
	 my ($reading,@times,$j,$index);
    my %weekdays = (
        B0_MONTAG => ["mon-from1", "mon-to1", "mon-from2","mon-to2"],
        B1_DIENSTAG=> ["tue-from1", "tue-to1", "tue-from2","tue-to2"],
        B2_MITTWOCH => ["wed-from1", "wed-to1", "wed-from2","wed-to2"],
        B3_DONNERSTAG => ["thu-from1", "thu-to1", "thu-from2","thu-to2"],
        B4_FREITAG => ["fri-from1", "fri-to1", "fri-from2","fri-to2"],
        B5_SAMSTAG => ["sat-from1", "sat-to1", "sat-from2","sat-to2"],
        B6_SONNTAG => ["sun-from1", "sun-to1", "sun-from2","sun-to2"],
        );
	foreach $reading (sort keys %{$defs{$dn}{READINGS}}) {
		next if($reading !~ /^B/);
		@times = split(/\|/,$defs{$dn}{READINGS}{$reading}{VAL});
		for ($j=0; $j < @times; $j++) {
			$index = $weekdays{$reading}[$j];
			$params{$index} = $times[$j];
		}
	}
	# FHT-Devices ----------------------------------------------------------------
	my (@fht_devices,$fht);
	my $device_list_reading = $defs{$dn}{READINGS}{A0_FHT_DEVICES}{VAL};
	Log $ll ,"FHTCONF $dn update FHT-DEVICES: $device_list_reading";
	if($device_list_reading eq ""){
      Log 0 ,"FHTCONF-CMD $dn: NO FHT-DEVICES";
      return undef;}
	@fht_devices = split(/\|/,$device_list_reading);
	# Send Commands via at-Jobs --------------------------------------------------
	# SendIntervall = $sn Default 5 sec
	my ($sn,$p,$old,$new,$at_time,$at_name,$tsecs,$i,$sec,$min,$hour,$mday,$month);
	$sn = 5;
	if(defined($attr{$dn}{SendIntervall})){
		$sn = $attr{$dn}{SendIntervall};
		}
	$tsecs = time() + $sn;
	foreach $fht (@fht_devices){
		$i = 1;
		foreach $p (sort keys %params){
		# Send only Changes
		$old = $defs{$fht}{READINGS}{$p}{VAL};
		$new = $params{$p};
		if($old ne $new){
			($sec,$min,$hour) = (localtime($tsecs))[0..2];
			$at_time = sprintf("%02d:%02d:%02d\n",$hour,$min,$sec);
			$at_name = $fht . "_AT_" . sprintf("%02d",$i);
			if(defined($defs{$at_name})){fhem "delete $at_name";}
			fhem "define $at_name at $at_time set $fht $p $new";
			fhem "attr $at_name room GRP.FHTCONF";
			$tsecs = $tsecs + $sn;
			$i++
			}
		}
	# Report 1
	$tsecs = $tsecs + $sn + 120;
	($sec,$min,$hour) = (localtime($tsecs))[0..2];
	$at_time = sprintf("%02d:%02d:%02d\n",$hour,$min,$sec);
	$at_name = $fht . "_AT_REP1";
	if(defined($defs{$at_name})){fhem "delete $at_name";}
	fhem "define $at_name at $at_time set $fht report1 255";
	fhem "attr $at_name room GRP.FHTCONF";
	# Report 2
	$tsecs = $tsecs + 120;
	($sec,$min,$hour) = (localtime($tsecs))[0..2];
	$at_time = sprintf("%02d:%02d:%02d\n",$hour,$min,$sec);
	$at_name = $fht . "_AT_REP2";
	if(defined($defs{$at_name})){fhem "delete $at_name";}
	fhem "define $at_name at $at_time set $fht report2 255";
	fhem "attr $at_name room GRP.FHTCONF";
	# FHT Time
	$tsecs = $tsecs + 120;
	($sec,$min,$hour,$mday,$month) = (localtime($tsecs))[0..4];
	$at_time = sprintf("%02d:%02d:%02d\n",$hour,$min,$sec);
	$at_name = $fht . "_AT_FHTTIME";
	if(defined($defs{$at_name})){fhem "delete $at_name";}
	fhem "define $at_name at $at_time set $fht hour $hour day $mday month $month";
	fhem "attr $at_name room GRP.FHTCONF";
	}
	# Set STATE
	$defs{$dn}{STATE} = "LastUpdate ". TimeNow();
	return undef;
}
################################################################################
1;