################################################################################
# 98_FHTCONF.pm
#
# Version: 1.0
# Stand: 08/2010
# Autor: Axel Rieger
# a[PUNKT]r[BEI]oo2p[PUNKT]net
#
# Configure multiple FHT´s
# Usage: define <NAME> FHTCONF
# FHTConf-Name: FHTC01
# Assign FHTROOM...All FHT´s in this Room will be configured
# FHEM: define FHTC01 FHTCONF
# FHEM: attr FHTC01 FHTRoom R01
# Assign FHT-Device to FHTRoom
# FHEM: attr <FHT-Name> room R01
# Get a list of FHT-Devices in FHTRoom:
# FHEM: set FHTC01 A0_FHT_DEVICES
#
# Configuration
# 
################################################################################
package main;

use strict;
use warnings;
use Data::Dumper;
use vars qw(%data);
use vars qw(%cmds);
use vars qw(%attr);
# FHEM Command to Update FHTs
sub Commandfhtconf($);
################################################################################
sub FHTCONF_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FHTCONF_Set";
  $hash->{DefFn}     = "FHTCONF_Define";
  $hash->{AttrList}  = "loglevel:0,5 disable:0,1 FHTRoom";
  # FHEM Command to Update FHTs
  $cmds{fhtconf}{Fn} = "Commandfhtconf";
  $cmds{fhtconf}{Hlp} = "FHTCONF[HELP]: fhtconf <FHTCONF-NAME>";
	
  Log 0, "FHEM-MODUL[98_FHTCONF.pm] LOADED";
}
################################################################################
sub FHTCONF_Define($)
{
    my ($hash, @a) = @_;
    return "Wrong syntax: use define <name> fht_conf" if(int(@a) !=1 );
    # Default Room
    my $room = "GRP.FHTCONF";

	my $name = $hash->{NAME};
    #Room
    $attr{$name}{room} = $room;
    # State
    $hash->{STATE} = "Created " . TimeNow();
    return undef;
}
################################################################################
sub FHTCONF_Set($)
{
	my ($hash, @a) = @_;
	# 4 Argumente
	# 1. Device Selbst als HASH
	# $a[0] => Device Name als String
	# $a[1] => Reading
	# $a[2] => Value for READING
	my $fields;
	$fields = join(" ",sort keys %{$hash->{READINGS}});
	$fields = "A1_mode A2_day_temp A2_night_temp ";
	$fields .= "A2_windowopen_temp A2_lowtemp_offset ";
	$fields .= "B0_MONTAG B1_DIENSTAG B2_MITTWOCH B3_DONNERSTAG B4_FREITAG B5_SAMSTAG B6_SONNTAG ";
	return "Unknown argument $a[1], choose one of ". $fields if($a[1] eq "?");
	
	my ($name,$room);
	$name = $hash->{NAME};
	# LogLevel
	my $ll = 0;
	if(defined($attr{$name}{loglevel})) {$ll = $attr{$name}{loglevel};}
	# INIT READINGS
	if(!defined($defs{$name}{READINGS}{Z0_INIT})) {
	  &FHTCONF_init_READINGS($name);
	}
	# A0_FHT_DEVICES => List of FHT-Devices in Room <FHTRoom>
	if($a[1] eq "A0_FHT_DEVICES") {
	  if(defined($attr{$name}{FHTRoom})){
	    $room = $attr{$name}{FHTRoom};
	    my $fht_devices = GetDevType_Room($room);
	    Log 0, "FHTCONF[SET] => FHT_DEVICES Room:$room -> " . $fht_devices;
	    $a[2] = $fht_devices;
	  }
	else {return "FHTCONF[ERROR] no FHTRoom defined";}
	  
	  
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
    # Allwas 4 Values 24:00|24:00|24:00|24:00
	if(@times == 2) {push(@times,"24:00");}
	if(@times == 3) {push(@times,"24:00");}
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
	# FHT_Devices
	my ($room,$device_list_reading);
	if(defined($attr{$dn}{FHTRoom})){
	  $room = $attr{$dn}{FHTRoom};
	  $device_list_reading = GetDevType_Room($room);
	  $defs{$dn}{READINGS}{A0_FHT_DEVICES}{VAL} = $device_list_reading;
	  $defs{$dn}{READINGS}{A0_FHT_DEVICES}{TIME} = TimeNow();
	}
	else {
	    Log 0,"FHTCONF[ERROR] no FHTRoom defined";
	    return undef;
	  }
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
	Log $ll ,"FHTCONF $dn update FHT-DEVICES: $device_list_reading";
	if($device_list_reading eq ""){
      Log $ll ,"FHTCONF-CMD $dn: NO FHT-DEVICES";
      return undef;}
	@fht_devices = split(/\|/,$device_list_reading);
	# Send Commands via at-Jobs --------------------------------------------------
	# SendIntervall = $sn Default 5 sec
	my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(time());
	my ($p,$old,$new,$at_time,$at_name,$tsecs);
	# SendList
	my $fhemcmd = "";
	foreach $fht (@fht_devices){
		foreach $p (sort keys %params){
		# Send only Changes
		$old = $defs{$fht}{READINGS}{$p}{VAL};
		$new = $params{$p};
		Log $ll, "FHTCONF-CMD-OLD: $fht -> $p -> OLD:$old NEW:$new";
		if($old ne $new){
			# Commands to Send
			$fhemcmd .= " $p $new";
			}
		}
	# Send Out
	if($fhemcmd ne "") {
	  my $cmd = "set $fht" . $fhemcmd;
	  Log $ll, "FHTCONF-CMD-SEND: $fhemcmd";
	  fhem $cmd;
	  #Reset
	  $fhemcmd = "";
	  $cmd = "";
	}
	else {Log 0, "FHTCONF-CMD-SEND: No Changes";}

	# Report 2
	fhem "set $fht report2 255";
	# FHT Time
	fhem "set $fht hour $hour day $mday month $month";
	}
	# Set STATE
	$defs{$dn}{STATE} = "LastUpdate ". TimeNow();
	return undef;
}
################################################################################
sub GetDevType_Room($){
  # Get All Dives By Type from Room
  # Params: GetDevType_Room <ROOM>
  # GetDevType_Room
  # Return: List of Devices seperated by | <PIPE>
  my ($room) = @_;
  my $type = "FHT";
  if(!defined($room)) {return "GetDevType_ROOM[ERROR]: No Room";}
  if(!defined($type)) {return "GetDevType_ROOM[ERROR]: No Type";}
  my (@devices);
  foreach my $d (sort keys %attr) {
    if($defs{$d}{TYPE} eq $type && $attr{$d}{room} =~ /$room/ ) {
      push(@devices,$d);
    }
  }
  return join("|",@devices);
}
################################################################################
sub FHTCONF_init_READINGS($) {
  my ($name) = @_;
  Log 0,"FHTCONF:$name ------INIT--------------";
  # Set DEFAULT Values
  # FHT's
  $defs{$name}{READINGS}{A0_FHT_DEVICES}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A0_FHT_DEVICES}{VAL} = "";
  #Mode
  # Values auto, manual, holiday or holiday_short
  $defs{$name}{READINGS}{A1_mode}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A1_mode}{VAL} = "auto";
  # Temperaturen...defualt 5.5 = disable
  $defs{$name}{READINGS}{A2_day_temp}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A2_day_temp}{VAL} = "5.5";
  $defs{$name}{READINGS}{A2_night_temp}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A2_night_temp}{VAL} = "5.5";
  $defs{$name}{READINGS}{A2_windowopen_temp}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A2_windowopen_temp}{VAL} = "5.5";
  # LowTemp-Offest
  $defs{$name}{READINGS}{A2_lowtemp_offset}{TIME} = TimeNow();
  $defs{$name}{READINGS}{A2_lowtemp_offset}{VAL} = "2.0";
  # Montag = Monday
  $defs{$name}{READINGS}{B0_MONTAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B0_MONTAG}{VAL} = "24:00|24:00|24:00|24:00";
  # Dienstag = Tuesday
  $defs{$name}{READINGS}{B1_DIENSTAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B1_DIENSTAG}{VAL} = "24:00|24:00|24:00|24:00";
  # Mittwoch = Wednesday
  $defs{$name}{READINGS}{B2_MITTWOCH}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B2_MITTWOCH}{VAL} = "24:00|24:00|24:00|24:00";
  # Donnerstag = Thursday
  $defs{$name}{READINGS}{B3_DONNERSTAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B3_DONNERSTAG}{VAL} = "24:00|24:00|24:00|24:00";
  # Freitag = Friday
  $defs{$name}{READINGS}{B4_FREITAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B4_FREITAG}{VAL} = "24:00|24:00|24:00|24:00";
  # Samstag = Saturday
  $defs{$name}{READINGS}{B5_SAMSTAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B5_SAMSTAG}{VAL} = "24:00|24:00|24:00|24:00";
  # Sonntag = Sunday
  $defs{$name}{READINGS}{B6_SONNTAG}{TIME} = TimeNow();
  $defs{$name}{READINGS}{B6_SONNTAG}{VAL} = "24:00|24:00|24:00|24:00";
  
  # INIT done
  $defs{$name}{READINGS}{Z0_INIT}{VAL} = 1;
  $defs{$name}{READINGS}{Z0_INIT}{TIME} = TimeNow();
  return undef;
}

1;