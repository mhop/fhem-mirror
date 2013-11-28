################################################################################
# 98_FHTCONF.pm
#
# Version: 1.5
# Stand: 09/2010
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
# Update:
# 09/2010 Added PRIV-CGI OverView
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
  # FHTCONF CGI
  my $name = "FHTCONF";
  my $fhem_url = "/" . $name ; 
  $data{FWEXT}{$fhem_url}{FUNC} = "FHTCONF_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = $name;
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
		$defs{$dn}{STATE} = "[DISBALED] ". TimeNow();
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
		# GetDevType_ROOM[ERROR]: No Room"
		if($device_list_reading =~ m/\[ERROR\]/) {
			$defs{$dn}{STATE} = "[ERROR] ". TimeNow();
			Log $ll ,"FHTCONF-CMD[ERROR] $dn: $device_list_reading";
      return undef;
		}
	  $defs{$dn}{READINGS}{A0_FHT_DEVICES}{VAL} = $device_list_reading;
	  $defs{$dn}{READINGS}{A0_FHT_DEVICES}{TIME} = TimeNow();
	}
	else {
	    Log 0,"FHTCONF[ERROR] no FHTRoom defined";
			$defs{$dn}{STATE} = "[ERROR] No FHTRoom defined ". TimeNow();
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

	@fht_devices = split(/\|/,$device_list_reading);

	my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(time());
	$month = $month + 1;
	$year = $year + 1900;
	
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
	else {
			Log 0, "FHTCONF-CMD-SEND: $fht No Changes";}

	# Report 1&2
	fhem "set $fht report1 255 report2 255";
	# FHT Time&Date
	fhem "set $fht hour $hour minute $min year $year month $month day $mday";
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
################################################################################
# FHTCONF CGI
################################################################################
sub FHTCONF_CGI() {
  my ($htmlarg) = @_;
  # htmlarg = /GROUPS/<CAT-NAME>
  my $Cat = FHTCONF_CGI_DISPTACH_URL($htmlarg);
  if(!defined($Cat)){$Cat = ""};
  my ($ret_html);
  $ret_html = "<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD HTML 4.01\/\/EN\" \"http:\/\/www.w3.org\/TR\/html4\/strict.dtd\">\n";
  $ret_html .= "<html>\n";
  $ret_html .= "<head>\n";
  $ret_html .= &FHTCONF_CGI_CSS();
  $ret_html .= "<title>FHEM GROUPS<\/title>\n";
  $ret_html .= "<link href=\"$__ME/style.css\" rel=\"stylesheet\"/>\n";
  $ret_html .= "<\/head>\n";
  $ret_html .= "<body>\n";
  # DIV HDR
  $ret_html .= &FHTCONF_CGI_TOP($Cat);
  # DIV LEFT
  $ret_html .= &FHTCONF_CGI_LEFT($Cat);
  # DIV RIGHT
  if($Cat ne "") {
    $ret_html .= &FHTCONF_CGI_RIGHT($Cat);
  }
  # HTML
  $ret_html .= "</body>\n";
  $ret_html .= "</html>\n";
  return ("text/html; charset=ISO-8859-1", $ret_html);
}
#-------------------------------------------------------------------------------
sub FHTCONF_CGI_DISPTACH_URL($){
  my ($htmlarg) = @_;
  my @params = split(/\//,$htmlarg);
  my $CAT = undef;
  if($params[2]) {
    $CAT = $params[2];
    # Log 0,"GRP URL-DISP-CAT: " . $CAT;
    }
  return $CAT;
}
#-------------------------------------------------------------------------------
sub FHTCONF_CGI_CSS() {
  my $css;
  $css   =  "<style type=\"text/css\"><!--\n";
  $css .= "\#left {float: left; width: 15%; height:100%;}\n";
  $css .= "table.GROUP { border:thin solid; background: #E0E0E0; text-align:left;}\n";
  $css .= "table.GROUP tr.odd { background: #F0F0F0;}\n";
  $css .= "table.GROUP td {nowrap;}";
  $css .= "\/\/--><\/style>";
  # TEST
  #$css = "<link href=\"$__ME/group.css\" rel=\"stylesheet\"/>\n";
  return $css;
}
#-------------------------------------------------------------------------------
sub FHTCONF_CGI_TOP($) {
  my $CAT = shift(@_);
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"hdr\">\n";
  $rh .= "<form method=\"get\" action=\"" . $__ME . "\">\n";
  $rh .= "<table WIDTH=\"100%\">\n";
  $rh .= "<tr>";
  $rh .= "<td><a href=\"" . $__ME . "\">FHEM:</a>$CAT</td>";
  $rh .= "<td><input type=\"text\" name=\"cmd\" size=\"30\"/></td>";
  $rh .= "</tr>\n";
  $rh .= "</table>\n";
  $rh .= "</form>\n";
  $rh .= "<br>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub FHTCONF_CGI_LEFT(){
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"logo\"><img src=\"" . $__ME . "/fhem.png\"></div>";
  $rh .= "<div id=\"menu\">\n";
  # Print FHTCONF-Devices
  $rh .= "<table class=\"room\">\n";
    foreach my $d (sort keys %defs) {
    next if($defs{$d}{TYPE} ne "FHTCONF");
    $rh .= "<tr><td>";
    $rh .= "<a href=\"" . $__ME . "/FHTCONF/$d\">$d</a></h3>";
    $rh .= "</td></tr>\n";
    }
  $rh .= "</table>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub FHTCONF_CGI_RIGHT(){
  my ($CAT) = @_;
  my ($rh,$fhtroom,$fht,@fhts,@ft,@fp,$fht_list);
  $fhtroom = $attr{$CAT}{FHTRoom};
  $fht_list = GetDevType_Room($fhtroom);
  $rh = "<div id=\"content\">\n";
  if($CAT eq "") {$CAT = "***";}
  # $rh .="CAT: " . $CAT . " FHTROOM:" . $fhtroom . "<br>\n";
  # $rh .= "FHT-Devices: " . $fht_list . "<br>\n";
  $rh .= "<table>\n";
  # Tabelle
  # Zeile - Row Namen FHTCONFDevice FHT-Devices
  $fp[0] .= "<th></th>";
  $fp[1] .= "<td></td>";
  $fp[2] .= "<td>IODEV</td>"; 
  $fp[3] .= "<td>Warnings</td>";
  $fp[4] .= "<td></td>";
  $fp[5] .= "<td>Mode</td>";
  $fp[6] .= "<td>Day-Temp</td>";
  $fp[7] .= "<td>LowTemp-OffSet</td>";
  $fp[8] .= "<td>Night-Temp</td>";
  $fp[9] .= "<td>WindowOpen-Temp</td>";
  $fp[10] .= "<td></td>";
  $fp[11] .= "<td>Montag</td>";
  $fp[12] .= "<td>Dienstag</td>";
  $fp[13] .= "<td>Mittwoch</td>";
  $fp[14] .= "<td>Donnerstag</td>";
  $fp[15] .= "<td>Freitag</td>";
  $fp[16] .= "<td>Samstag</td>";
  $fp[17] .= "<td>Sonntag</td>";
  $fp[18] .= "<td></td>";
  #Values FHTCONF-Device
  $fp[0] .= "<th><a href=\"$__ME?detail=$CAT\">$CAT</a></th>";
  # $fp[0] .= "<th>" . $CAT . "</th>";
  $fp[1] .= "<td></td>";
  $fp[2] .= "<td></td>";
  $fp[3] .= "<td></td>";
  $fp[4] .= "<td></td>";
  $fp[5] .= "<td>" . $defs{$CAT}{READINGS}{A1_mode}{VAL} . "</td>";
  $fp[6] .= "<td>" . $defs{$CAT}{READINGS}{A2_day_temp}{VAL} . "</td>";
  $fp[7] .= "<td>" . $defs{$CAT}{READINGS}{A2_lowtemp_offset}{VAL} . "</td>";
  $fp[8] .= "<td>" . $defs{$CAT}{READINGS}{A2_night_temp}{VAL} . "</td>";
  $fp[9] .= "<td>" . $defs{$CAT}{READINGS}{A2_windowopen_temp}{VAL} . "</td>";
  $fp[10] .= "<td></td>";
  $fp[11] .= "<td>" . $defs{$CAT}{READINGS}{B0_MONTAG}{VAL} . "</td>";
  $fp[12] .= "<td>" . $defs{$CAT}{READINGS}{B1_DIENSTAG}{VAL} . "</td>";
  $fp[13] .= "<td>" . $defs{$CAT}{READINGS}{B2_MITTWOCH}{VAL} . "</td>";
  $fp[14] .= "<td>" . $defs{$CAT}{READINGS}{B3_DONNERSTAG}{VAL} . "</td>";
  $fp[15] .= "<td>" . $defs{$CAT}{READINGS}{B4_FREITAG}{VAL} . "</td>";
  $fp[16] .= "<td>" . $defs{$CAT}{READINGS}{B5_SAMSTAG}{VAL} . "</td>";
  $fp[17] .= "<td>" . $defs{$CAT}{READINGS}{B6_SONNTAG}{VAL} . "</td>";
  $fp[18] .= "<td></td>";
  # FHT Devices
  @fhts = split(/\|/,$fht_list);
  foreach $fht (@fhts){
	$fp[0] .= "<th><a href=\"$__ME?detail=$fht\">$fht</a></th>";
    # $fp[0] .= "<th>" . $fht . "</td>";
    $fp[1] .= "<td></td>";
    $fp[2] .= "<td>" . $attr{$fht}{IODev} . "</td>";
    $fp[3] .= "<td>" . $defs{$fht}{READINGS}{warnings}{VAL} . "</td>";
    $fp[4] .= "<td></td>";
    $fp[5] .= "<td>" . $defs{$fht}{READINGS}{mode}{VAL} . "</td>";
    $fp[6] .= "<td>" . $defs{$fht}{READINGS}{'day-temp'}{VAL} . "</td>";
    $fp[7] .= "<td>" . $defs{$fht}{READINGS}{'lowtemp-offset'}{VAL} . "</td>";
    $fp[8] .= "<td>" . $defs{$fht}{READINGS}{'night-temp'}{VAL} . "</td>";
    $fp[9] .= "<td>" . $defs{$fht}{READINGS}{'windowopen-temp'}{VAL} . "</td>";
    $fp[10] .= "<td></td>";
    $fp[11] .= "<td>" . $defs{$fht}{READINGS}{'mon-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'mon-to1'}{VAL} . "|";
    $fp[11] .= $defs{$fht}{READINGS}{'mon-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'mon-to2'}{VAL} . "</td>";
    $fp[12] .= "<td>" . $defs{$fht}{READINGS}{'tue-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'tue-to1'}{VAL} . "|";
    $fp[12] .= $defs{$fht}{READINGS}{'tue-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'tue-to2'}{VAL} . "</td>";
    $fp[13] .= "<td>" . $defs{$fht}{READINGS}{'wed-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'wed-to1'}{VAL} . "|";
    $fp[13] .= $defs{$fht}{READINGS}{'wed-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'wed-to2'}{VAL} . "</td>";
    $fp[14] .= "<td>" . $defs{$fht}{READINGS}{'thu-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'thu-to1'}{VAL} . "|";
    $fp[14] .= $defs{$fht}{READINGS}{'thu-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'thu-to2'}{VAL} . "</td>";
    $fp[15] .= "<td>" . $defs{$fht}{READINGS}{'fri-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'fri-to1'}{VAL} . "|";
    $fp[15] .= $defs{$fht}{READINGS}{'fri-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'fri-to2'}{VAL} . "</td>";
    $fp[16] .= "<td>" . $defs{$fht}{READINGS}{'sat-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'sat-to1'}{VAL} . "|";
    $fp[16] .= $defs{$fht}{READINGS}{'sat-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'sat-to2'}{VAL} . "</td>";
    $fp[17] .= "<td>" . $defs{$fht}{READINGS}{'sun-from1'}{VAL} . "|" . $defs{$fht}{READINGS}{'sun-to1'}{VAL} . "|";
    $fp[17] .= $defs{$fht}{READINGS}{'sun-from2'}{VAL} . "|" . $defs{$fht}{READINGS}{'sun-to2'}{VAL} . "</td>";
	$fp[18] .= "<td>" . $attr{$fht}{comment} . "</td>";
  }
  foreach (@fp) {
  $rh .= "<tr ALIGN=LEFT>" . $_ . "</tr>\n";
  }
  $rh .= "</table>\n";
  $rh .= "</div>\n";
  return $rh;
}
################################################################################
1;