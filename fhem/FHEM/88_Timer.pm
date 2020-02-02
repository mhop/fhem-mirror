#################################################################
# $Id$
#
# The module is a timer for executing actions with only one InternalTimer.
# Github - FHEM Home Automation System
# https://github.com/fhem/Timer
#
# FHEM Forum: Automatisierung
# https://forum.fhem.de/index.php/board,20.0.html
# https://forum.fhem.de/index.php/topic,103848.html | https://forum.fhem.de/index.php/topic,103986.0.html
#
# 2019 | 2020 - HomeAuto_User, elektron-bbs
#################################################################
# notes:
# - module mit package umsetzen
#################################################################


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

my @action = ("on","off","DEF");
my @names;
my @designations;
my $description_all;
my $cnt_attr_userattr = 0;
my $language = uc(AttrVal("global", "language", "EN"));

if ($language eq "DE") {
	@designations = ("Sonnenaufgang","Sonnenuntergang","lokale Zeit","Uhr","SA","SU");
	$description_all = "alle";   # using in RegEx
	@names = ("Nr.","Jahr","Monat","Tag","Stunde","Minute","Sekunde","Ger&auml;t oder Bezeichnung","Aktion","Mo","Di","Mi","Do","Fr","Sa","So","aktiv","");
} else {
	@designations = ("Sunrise","Sunset","local time","","SR","SS");
	$description_all = "all";     # using in RegEx
	@names = ("No.","Year","Month","Day","Hour","Minute","Second","Device or label","Action","Mon","Tue","Wed","Thu","Fri","Sat","Sun","active","");
}

##########################
sub Timer_Initialize($) {
	my ($hash) = @_;

	$hash->{AttrFn}       = "Timer_Attr";
	$hash->{AttrList}     = "disable:0,1 ".
													"Offset_Horizon:REAL,CIVIL,NAUTIC,ASTRONOMIC ".
													"Show_DeviceInfo:alias,comment ".
													"Timer_preselection:on,off ".
													"Table_Border_Cell:on,off ".
													"Table_Border:on,off ".
													"Table_Header_with_time:on,off ".
													"Table_Style:on,off ".
													"Table_Size_TextBox:15,20,25,30,35,40,45,50 ".
													"Table_View_in_room:on,off ".
													"stateFormat:textField-long ";
	$hash->{DefFn}        = "Timer_Define";
	$hash->{SetFn}        = "Timer_Set";
	$hash->{GetFn}        = "Timer_Get";
	$hash->{UndefFn}      = "Timer_Undef";
	$hash->{NotifyFn}     = "Timer_Notify";
	#$hash->{FW_summaryFn} = "Timer_FW_Detail";    # displays html instead of status icon in fhemweb room-view

	$hash->{FW_detailFn}	= "Timer_FW_Detail";
	$hash->{FW_deviceOverview} = 1;
	$hash->{FW_addDetailToSummary} = 1;            # displays html in fhemweb room-view
}

##########################
# Predeclare Variables from other modules may be loaded later from fhem
our $FW_wname;

##########################
sub Timer_Define($$) {
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);
	my $name = $arg[0];                    ## Definitionsname, mit dem das Gerät angelegt wurde
	my $typ = $hash->{TYPE};               ## Modulname, mit welchem die Definition angelegt wurde
	my $filelogName = "FileLog_$name";
	my ($cmd, $ret);
	my ($autocreateFilelog, $autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) = ('%L' . $name . '-%Y-%m.log', undef, 'autocreate', $typ, $typ);
	$hash->{NOTIFYDEV} = "global,TYPE=$typ";

	return "Usage: define <name> $name"  if(@arg != 2);

	if ($init_done) {
		if (!defined(AttrVal($autocreateName, "disable", undef)) && !exists($defs{$filelogName})) {
			### create FileLog ###
			$autocreateFilelog = AttrVal($autocreateName, "filelog", undef) if (defined AttrVal($autocreateName, "filelog", undef));
			$autocreateFilelog =~ s/%NAME/$name/g;
			$cmd = "$filelogName FileLog $autocreateFilelog $name";
			Log3 $filelogName, 2, "$name: define $cmd";
			$ret = CommandDefine(undef, $cmd);
			if($ret) {
				Log3 $filelogName, 2, "$name: ERROR: $ret";
			} else {
				### Attributes ###
				CommandAttr($hash,"$filelogName room $autocreateDeviceRoom");
				CommandAttr($hash,"$filelogName logtype text");
				CommandAttr($hash,"$name room $autocreateDeviceRoom");
			}
		}

		### Attributes ###
		CommandAttr($hash,"$name room $typ") if (!defined AttrVal($name, "room", undef));				# set room, if only undef --> new def
	}

	### default value´s ###
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state" , "Defined");
	readingsBulkUpdate($hash, "internalTimer" , "stop");
	readingsEndUpdate($hash, 0);
	return undef;
}

#####################
sub Timer_Set($$$@) {
	my ( $hash, $name, @a ) = @_;
	return "no set value specified" if(int(@a) < 1);

	my $setList = "addTimer:noArg ";
	my $cmd = $a[0];
	my $cmd2 = $a[1];
	my $Timers_Count = 0;
	my $Timers_Count2;
	my $Timers_diff = 0;
	my $Timer_preselection = AttrVal($name,"Timer_preselection","off");
	my $value;

	foreach my $d (sort keys %{$hash->{READINGS}}) {
		if ($d =~ /^Timer_(\d)+$/) {
			$Timers_Count++;
			$d =~ s/Timer_//;
			$setList.= "deleteTimer:" if ($Timers_Count == 1);
			$setList.= $d.",";
		}
	}

	if ($Timers_Count != 0) {
		$setList = substr($setList, 0, -1);  # cut last ,
		$setList.= " saveTimers:noArg";
	}

	$setList.= " sortTimer:noArg" if ($Timers_Count > 1);

	Log3 $name, 4, "$name: Set | cmd=$cmd" if ($cmd ne "?");

	if ($cmd eq "sortTimer") {
		my @timers_unsortet;
		my @userattr_values;
		my @attr_values_names;
		my $timer_nr_new;
		my $array_diff = 0;             # difference, Timer can be sorted >= 1
		my $array_diff_cnt1 = 0;        # need to check 1 + 1
		my $array_diff_cnt2 = 0;        # need to check 1 + 1

		foreach my $readingsName (sort keys %{$hash->{READINGS}}) {
			if ($readingsName =~ /^Timer_(\d+)$/) {
				my $value = ReadingsVal($name, $readingsName, 0);
				$value =~ /^.*\d{2},(.*),(on|off|DEF)/;
				push(@timers_unsortet,$1.",".ReadingsVal($name, $readingsName, 0).",$readingsName");   # unsort Reading Wert in Array
				$array_diff_cnt1++;
				$array_diff_cnt2 = substr($readingsName,-2) * 1;
				$array_diff = 1 if ($array_diff_cnt1 != $array_diff_cnt2 && $array_diff == 0);
			}
		}

		my @timers_sort = sort @timers_unsortet;                              # Timer in neues Array sortieren

		for (my $i=0; $i<scalar(@timers_unsortet); $i++) {
			$array_diff++ if ($timers_unsortet[$i] ne $timers_sort[$i]);
		}

		RemoveInternalTimer($hash, "Timer_Check") if ($array_diff != 0);
		return "cancellation! No sorting necessary." if ($array_diff == 0);   # check, need action continues

		for (my $i=0; $i<scalar(@timers_sort); $i++) {
			readingsDelete($hash, substr($timers_sort[$i],-8));                 # Readings Timer loeschen
		}

		for (my $i=0; $i<scalar(@timers_sort); $i++) {
			$timer_nr_new = sprintf("%02s",$i + 1);                             # neue Timer-Nummer
			if ($timers_sort[$i] =~ /^.*\d{2},(.*),(DEF),.*,(Timer_\d+)/) {     # filtre DEF values - Perl Code (DEF must in S2 - Timer nr old $3)
				Log3 $name, 4, "$name: Set | $cmd: ".$timers_sort[$i];
				if (defined AttrVal($name, $3."_set", undef)) {
					Log3 $name, 4, "$name: Set | $cmd: ".$3." remember values";
					push(@userattr_values,"Timer_$timer_nr_new".",".AttrVal($name, $3."_set",0));  # userattr value in Array with new numbre
				}
				Timer_delFromUserattr($hash,$3."_set:textField-long");                           # delete from userattr (old numbre)
				Log3 $name, 4, "$name: Set | $cmd: added to array attr_values_names -> "."Timer_$timer_nr_new"."_set:textField-long";
				push(@attr_values_names, "Timer_$timer_nr_new"."_set:textField-long");
			}
			$timers_sort[$i] = substr( substr($timers_sort[$i],index($timers_sort[$i],",")+1) ,0,-9);
			readingsSingleUpdate($hash, "Timer_".$timer_nr_new , $timers_sort[$i], 1);
		}

		for (my $i=0; $i<scalar(@attr_values_names); $i++) {
			Log3 $name, 4, "$name: Set | $cmd: from array to attrib userattr -> $attr_values_names[$i]";
			addToDevAttrList($name,$attr_values_names[$i]);                     # added to userattr (new numbre)
		}

		addStructChange("modify", $name, "attr $name userattr");              # note with question mark

		if (scalar(@userattr_values) > 0) {                                   # write userattr_values
			for (my $i=0; $i<scalar(@userattr_values); $i++) {
				my $timer_nr = substr($userattr_values[$i],0,8)."_set";
				my $value_attr = substr($userattr_values[$i],index($userattr_values[$i],",")+1);
				CommandAttr($hash,"$name $timer_nr $value_attr");
			}
		}
		Timer_Check($hash);
	}

	if ($cmd eq "addTimer") {
		$Timers_Count = 0;
		foreach my $d (sort keys %{$hash->{READINGS}}) {
			if ($d =~ /^Timer_(\d+)$/) {
				$Timers_Count++;
				$Timers_Count2 = $1 * 1;
				if ($Timers_Count != $Timers_Count2 && $Timers_diff == 0) {       # only for diff
					$Timers_diff++;
					last;
				}
			}
		}

		if ($Timer_preselection eq "on") {
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			$value = $year + 1900 .",".sprintf("%02s", ($mon + 1)).",".sprintf("%02s", $mday).",".sprintf("%02s", $hour).",".sprintf("%02s", $min).",00,,on,1,1,1,1,1,1,1,0";
		} else {
			$value = "$description_all,$description_all,$description_all,$description_all,$description_all,00,,on,1,1,1,1,1,1,1,0";
		}

		$Timers_Count = $Timers_Count + 1 if ($Timers_diff == 0);
		readingsSingleUpdate($hash, "Timer_".sprintf("%02s", $Timers_Count) , $value, 1);
	}

	if ($cmd eq "saveTimers") {
		open(SaveDoc, '>', "./FHEM/lib/$name"."_conf.txt") || return "ERROR: file $name"."_conf.txt can not open!";
			foreach my $d (sort keys %{$hash->{READINGS}}) {
				print SaveDoc "Timer_".$1.",".$hash->{READINGS}->{$d}->{VAL}."\n" if ($d =~ /^Timer_(\d+)$/);
			}

			print SaveDoc "\n";

			foreach my $e (sort keys %{$attr{$name}}) {
				my $LE = "";
				$LE = "\n" if (AttrVal($name, $e, undef) !~ /\n$/);
				print SaveDoc $e.",".AttrVal($name, $e, undef).$LE if ($e =~ /^Timer_(\d+)_set$/);
			}
		close(SaveDoc);
	}

	if ($cmd eq "deleteTimer") {
		readingsDelete($hash, "Timer_".$cmd2);

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state" , "Timer_$cmd2 deleted");

		if ($Timers_Count == 0) {
			readingsBulkUpdate($hash, "internalTimer" , "stop",1);
			RemoveInternalTimer($hash, "Timer_Check");
		}

		readingsEndUpdate($hash, 1);

		my $deleteTimer = "Timer_$cmd2"."_set:textField-long";
		Timer_delFromUserattr($hash,$deleteTimer);
		Timer_PawList($hash);                                                  # list, Probably associated with
		addStructChange("modify", $name, "attr $name userattr Timer_$cmd2");   # note with question mark
	}

	return $setList if ( $a[0] eq "?");
	return "Unknown argument $cmd, choose one of $setList" if (not grep /$cmd/, $setList);
	return undef;
}

#####################
sub Timer_Get($$$@) {
	my ( $hash, $name, $cmd, @a ) = @_;
	my $list = "loadTimers:no,yes";
	my $cmd2 = $a[0];
	my $Timer_cnt_name = -1;

	if ($cmd eq "loadTimers") {
		if ($cmd2 eq "no") {
			return "";
		}

		if ($cmd2 eq "yes") {
			my $error = "";
			my $line = 0;
			my @lines_readings;
			my @attr_values;
			my @attr_values_names;
			RemoveInternalTimer($hash, "Timer_Check");

			open (InputFile,"<./FHEM/lib/$name"."_conf.txt") || return "ERROR: No file $name"."_conf.txt found in ./FHEM/lib directory from FHEM!";
			while (<InputFile>) {
				$line++;
				# Timer_04,alle,alle,alle,12,00,00,Update FHEM,Def,1,0,0,0,0,0,0,1
				if ($_ =~ /^(.*),.*,.*,.*,.*,.*,.*,.*,(.*),.*,.*,.*,.*,.*,.*,.*,[0-1]$/) {
					chomp ($_);                              # Zeilenende entfernen
					$_ =~ s/,Def,/,DEF,/g if ($2 =~ /Def/);  # Compatibility modify Def to DEF
					push(@lines_readings,$_);                # lines in array
					my @values = split(",",$_);              # split line in array to check
					#$error.= "- scalar arrray\n" if (scalar(@values) != 17);
					push(@attr_values_names, $values[0]."_set") if($values[8] eq "DEF");
					for (my $i=0;$i<@values;$i++) {
						$error.= "- ".$values[0]." is no $name description" if ($i == 0 && $values[0] !~ /^Timer_\d{2}$/);
						$error.= "- ".$values[1]." invalid value" if ($i == 1 && $values[1] !~ /^\d{4}$|^$description_all$/);
						if ($i >= 2 && $i <= 5 && $values[$i] ne "$description_all") {
							$error.= "- ".$values[$i]." not decimal" if ($i >= 2 && $i <= 3 && $values[$i] !~ /^\d{2}$/);
							$error.= "- ".$values[2]." wrong value (allowed 1-12)" if ($i == 2 && ($values[2] * 1) < 1 && ($values[2] * 1) > 12);
							$error.= "- ".$values[3]." wrong value (allowed 1-31)" if ($i == 3 && ($values[3] * 1) < 1 && ($values[3] * 1) > 31);

							if ($i >= 4 && $i <= 5 && $values[$i] ne $designations[4] && $values[$i] ne $designations[5]) { # SA -> 4 SU -> 5
								$error.= "- ".$values[$i]." not support" if ($i >= 4 && $i <= 5 && $values[$i] !~ /^\d{2}$/);
								$error.= "- ".$values[4]." wrong value (allowed 00-23)" if ($i == 4 && ($values[4] * 1) > 23);
								$error.= "- ".$values[5]." wrong value (allowed 00-59)" if ($i == 5 && ($values[5] * 1) > 59);
							}
						}
						$error.= "- ".$values[$i]." is no % 10\n" if ($i == 6 && $values[$i] % 10 != 0);
						$error.= "- ".$values[$i]." is no allowed action \n" if ($i == 8 && not grep { $values[$i] eq $_ } @action);
						$error.= "- ".$values[$i]." is not 0 or 1 \n" if ($i >= 9 && $values[$i] ne "0" && $values[$i] ne "1");

						if ($error ne "") {
							close InputFile;
							Timer_Check($hash);
							$error.= "\nYour language is wrong! ($language)" if ($error =~ /-\s(all\s|alle\s|SA\s|SU\s|SR\s|SS\s)/);
							return "ERROR: your file is NOT valid!\n\nline $line\n$error";
						}
					}
				}

				if ($_ =~ /^Timer_\d{2}_set,/) {
					$Timer_cnt_name++;
					push(@attr_values, substr($_,13));
				} elsif ($_ !~ /^Timer_\d{2},/) {
					$attr_values[$Timer_cnt_name].= $_ if ($Timer_cnt_name >= 0);
					if ($_ =~ /.*}.*/){                                               # letzte } Klammer finden
						my $err = perlSyntaxCheck($attr_values[$Timer_cnt_name], ());   # check PERL Code
						if($err) {
							$err = "ERROR: your file is NOT valid! \n \n".$err;
							close InputFile;
							Timer_Check($hash);
							return $err;
						}
					}
				}
			}
			close InputFile;

			foreach my $d (sort keys %{$hash->{READINGS}}) {         # delete all readings
				readingsDelete($hash, $d) if ($d =~ /^Timer_(\d+)$/);
			}

			foreach my $f (sort keys %{$attr{$name}}) {              # delete all attributes Timer_xx_set ...
				CommandDeleteAttr($hash, $name." ".$f) if ($f =~ /^Timer_(\d+)_set$/);
			}

			my @userattr_values = split(" ", AttrVal($name, "userattr", "none"));
			for (my $i=0;$i<@userattr_values;$i++) {                 # delete userattr values Timer_xx_set:textField-long ...
				delFromDevAttrList($name, $userattr_values[$i]) if ($userattr_values[$i] =~ /^Timer_(\d+)_set:textField-long$/);
			}

			foreach my $e (@lines_readings) {                        # write new readings
				my $Timer_nr = substr($e,0,8);
				readingsSingleUpdate($hash, "$Timer_nr" , substr($e,9,length($e)-9), 1) if ($e =~ /^Timer_\d{2},/);
			}

			for (my $i=0;$i<@attr_values_names;$i++) {               # write new userattr
				addToDevAttrList($name,$attr_values_names[$i].":textField-long"); 
			}

			for (my $i=0;$i<@attr_values;$i++) {                     # write new attr value
				chomp ($attr_values[$i]);                              # Zeilenende entfernen
				CommandAttr($hash,"$name $attr_values_names[$i] $attr_values[$i]");
			}

			Timer_PawList($hash);                                    # list, Probably associated with

			readingsSingleUpdate($hash, "state" , "Timers loaded", 1);
			FW_directNotify("FILTER=(room=)?$name", "#FHEMWEB:WEB", "location.reload('true')", "");
			Timer_Check($hash);

			return undef;
		}
	}

	return "Unknown argument $cmd, choose one of $list";
}

#####################
sub Timer_Attr() {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};

	if ($cmd eq "set" && $init_done == 1 ) {
		Log3 $name, 5, "$name: Attr | set $attrName to $attrValue";
		if ($attrName eq "disable") {
			if ($attrValue eq "1") {
				readingsSingleUpdate($hash, "internalTimer" , "stop",1);
				RemoveInternalTimer($hash, "Timer_Check");
			} elsif ($attrValue eq "0") {
				Timer_Check($hash);
			}
		}

		if ($attrName =~ /^Timer_\d{2}_set$/) {
			my $err = perlSyntaxCheck($attrValue, ());   # check PERL Code
			InternalTimer(gettimeofday()+0.1, "Timer_PawList", $hash);
			return $err if($err);
		}
	}

	if ($cmd eq "del") {
		Log3 $name, 5, "$name: Attr | Attributes $attrName deleted";
		if ($attrName eq "disable") {
			Timer_Check($hash);
		}

		if ($attrName eq "userattr") {
			if (defined AttrVal($FW_wname, "confirmDelete", undef) && AttrVal($FW_wname, "confirmDelete", undef) == 0) {
				$cnt_attr_userattr++;
				return "Please execute again if you want to force the attribute to delete!" if ($cnt_attr_userattr == 1);
				$cnt_attr_userattr = 0;
			}
		}
		
		if ($attrName =~ /^Timer_\d{2}_set$/) {
			Log3 $name, 3, "$name: Attr | Attributes $attrName deleted";
			InternalTimer(gettimeofday()+0.1, "Timer_PawList", $hash);
		}
	}
}

#####################
sub Timer_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash, "Timer_Check");
	Log3 $name, 4, "$name: Undef | device is delete";

	return undef;
}

#####################
sub Timer_Notify($$) {
	my ($hash, $dev_hash) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	return "" if(IsDisabled($name));	# Return without any further action if the module is disabled
	my $devName = $dev_hash->{NAME};	# Device that created the events
	my $events = deviceEvents($dev_hash, 1);

	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}) && $typ eq "Timer") {
		Log3 $name, 5, "$name: Notify is running and starting $name";

		### Compatibility Check Def to DEF ###
		Log3 $name, 4, "$name: Notify Compatibility check";
		foreach my $d (keys %{$hash->{READINGS}}) {
			if ( $d =~ /^Timer_\d+$/ && ReadingsVal($name, $d, "") =~ /,Def,/ ) {
				Log3 $name, 4, "$name: $d with ".ReadingsVal($name, $d, "")." must modify!";
				my $ReadingsMod = ReadingsVal($name, $d, "");
				$ReadingsMod =~ s/,Def,/,DEF,/g;
				readingsSingleUpdate($hash, $d , $ReadingsMod, 0);
			}
		}
		Timer_Check($hash);
	}

	return undef;
}

##### HTML-Tabelle Timer-Liste erstellen #####
sub Timer_FW_Detail($$$$) {
	my ($FW_wname, $d, $room, $pageHash) = @_;		# pageHash is set for summaryFn.
	my $hash = $defs{$d};
	my $name = $hash->{NAME};
	my $html = "";
	my $selected = "";
	my $Timers_Count = 0;
	my $Table_Border = AttrVal($name,"Table_Border","off");
	my $Table_Border_Cell = AttrVal($name,"Table_Border_Cell","off");
	my $Table_Header_with_time = AttrVal($name,"Table_Header_with_time","off");
	my $Table_Size_TextBox = AttrVal($name,"Table_Size_TextBox",20);
	my $Table_Style = AttrVal($name,"Table_Style","off");
	my $Table_View_in_room = AttrVal($name,"Table_View_in_room","on");
	my $style_code1 = "";
	my $style_code2 = "";
	my $time = FmtDateTime(time());
	my $horizon = AttrVal($name,"Offset_Horizon","REAL");
	my $FW_room_dupl = $FW_room;
	my @timer_nr;
	my $cnt_max = scalar(@names);

	return $html if((!AttrVal($name, "room", undef) && $FW_detail eq "") || ($Table_View_in_room eq "off" && $FW_detail eq ""));

	if ($Table_Style eq "on") {
		### style via CSS for Checkbox ###
		$html.= '<style>
		/* Labels for checked inputs */
		input:checked {
		}

		/* Checkbox element, when checked */
		input[type="checkbox"]:checked {
			box-shadow: 2px -2px 1px #13ab15;
			-moz-box-shadow: 2px -2px 1px #13ab15;
			-webkit-box-shadow: 2px -2px 1px #13ab15;
			-o-box-shadow: 2px -2px 1px #13ab15;
		}

		/* Checkbox element, when NO checked */
		input[type="checkbox"] {
			box-shadow: 2px -2px 1px #b5b5b5;
			-moz-box-shadow: 2px -2px 1px #b5b5b5;
			-webkit-box-shadow: 2px -2px 1px #b5b5b5;
			-o-box-shadow: 2px -2px 1px #b5b5b5;
		}

		/* Checkbox element, when checked and hover */
		input:hover[type="checkbox"]{
			box-shadow: 2px -2px 1px red;
			-moz-box-shadow: 2px -2px 1px red;
			-webkit-box-shadow: 2px -2px 1px red;
			-o-box-shadow: 2px -2px 1px red;
		}

		/* Save element */
		input[type="reset"] {
			border-radius:4px;
		}

		</style>';
	}

	Log3 $name, 5, "$name: attr2html is running";

	foreach my $d (sort keys %{$hash->{READINGS}}) {
		if ($d =~ /^Timer_\d+$/) {
			$Timers_Count++;
			push(@timer_nr, substr($d,index($d,"_")+1));		
		}
	}
	$style_code2 = "border:2px solid #00FF00;" if($Table_Border eq "on");

	$html.= "<div style=\"text-align: center; font-size:medium; padding: 0px 0px 6px 0px;\">$designations[0]: ".sunrise_abs($horizon)." $designations[3]&nbsp;&nbsp;|&nbsp;&nbsp;$designations[1]: ".sunset_abs($horizon)." $designations[3]&nbsp;&nbsp;|&nbsp;&nbsp;$designations[2]: ".TimeNow()." $designations[3]</div>" if($Table_Header_with_time eq "on");
	$html.= "<div id=\"table\"><table class=\"block wide\" style=\"$style_code2\">";

	#         Timer Jahr  Monat Tag   Stunde Minute Sekunde Gerät   Aktion Mo Di Mi Do Fr Sa So aktiv speichern
	#         -------------------------------------------------------------------------------------------------
	#               2019  09    03    18     15     00      Player  on     0  0  0  0  0  0  0  0
	# Spalte: 0     1     2     3     4      5      6       7       8      9  10 11 12 13 14 15 16    17
	#         -------------------------------------------------------------------------------------------------
	# T 1 id: 20    21    22    23    24     25     26      27      28     29 30 31 32 33 34 35 36    37         ($id = timer_nr * 20 + $Spalte)
	# T 2 id: 40    41    42    43    44     45     46      47      48     49 50 51 52 53 54 55 56    57         ($id = timer_nr * 20 + $Spalte)

	## Ueberschrift
	$html.= "<tr class=\"odd\">";
	####
	$style_code1 = "border:1px solid #D8D8D8;" if($Table_Border_Cell eq "on");
	for(my $spalte = 0; $spalte <= $cnt_max - 1; $spalte++) {
		$html.= "<td align=\"center\" style=\"$style_code1 Padding-top:3px; Padding-left:5px; text-decoration:underline\">".$names[$spalte]."</td>" if ($spalte == 0);							# Timer-Nummer - auto Breite
		$html.= "<td align=\"center\" width=70 style=\"$style_code1 Padding-top:3px; text-decoration:underline\">".$names[$spalte]."</td>" if ($spalte >= 1 && $spalte <= 6);				# Dropdown-Listen - definierte Breite
		$html.= "<td align=\"center\" style=\"$style_code1 Padding-top:3px; text-decoration:underline\">".$names[$spalte]."</td>" if ($spalte > 6 && $spalte < $cnt_max - 1);				# auto Breite
		$html.= "<td align=\"center\" style=\"$style_code1 Padding-top:3px; Padding-right:5px; text-decoration:underline\">".$names[$spalte]."</td>" if ($spalte == $cnt_max - 1);	# Button save - auto Breite
	}
	$html.= "</tr>";

	for(my $zeile = 0; $zeile < $Timers_Count; $zeile++) {
		$html.= sprintf("<tr class=\"%s\">", ($zeile & 1)?"odd":"even");
		my $id = $timer_nr[$zeile] * 20; # id 20, 40, 60 ...
		# Log3 $name, 3, "$name: Zeile $zeile, id $id, Start";
		my @select_Value = split(",", ReadingsVal($name, "Timer_".$timer_nr[$zeile], "$description_all,$description_all,$description_all,$description_all,$description_all,00,Lampe,on,0,0,0,0,0,0,0,0,,"));
		for(my $spalte = 1; $spalte <= $cnt_max; $spalte++) {
			$style_code1 .= "Padding-bottom:5px; " if ($zeile == $Timers_Count - 1);	# letzte Zeile
			$html.= "<td align=\"center\" style=\"$style_code1\">".sprintf("%02s", $timer_nr[$zeile])."</td>" if ($spalte == 1);	# Spalte Timer-Nummer
			if ($spalte >=2 && $spalte <= 7) {              ## DropDown-Listen fuer Jahr, Monat, Tag, Stunde, Minute, Sekunde
				my $start = 0;																# Stunde, Minute, Sekunde
				my $stop = 12;																# Monat
				my $step = 1;																	# Jahr, Monat, Tag, Stunde, Minute
				$start = substr($time,0,4) if ($spalte == 2);	# Jahr
				$stop = $start + 10 if ($spalte == 2);				# Jahr
				$start = 1 if ($spalte == 3 || $spalte == 4);	# Monat, Tag
				$stop = 31 if ($spalte == 4);									# Tag
				$stop = 23 if ($spalte == 5);									# Stunde
				$stop = 59 if ($spalte == 6);									# Minute
				$stop = 50 if ($spalte == 7);									# Sekunde
				$step = 10 if ($spalte == 7);									# Sekunde
				$id++;

				# Log3 $name, 3, "$name: Zeile $zeile, id $id, select";
				$html.= "<td align=\"center\" style=\"$style_code1\"><select id=\"".$id."\">";	# id need for java script
				$html.= "<option>$description_all</option>" if ($spalte <= 6);     # Jahr, Monat, Tag, Stunde, Minute
				if ($spalte == 5 || $spalte == 6) {                                # Stunde, Minute
					$selected = $select_Value[$spalte-2] eq $designations[4] ? "selected=\"selected\"" : "";
					$html.= "<option $selected value=\"".$designations[4]."\">".$designations[4]."</option>";		# Sonnenaufgang -> pos 4 array
					$selected = $select_Value[$spalte-2] eq $designations[5] ? "selected=\"selected\"" : "";
					$html.= "<option $selected value=\"".$designations[5]."\">".$designations[5]."</option>";		# Sonnenuntergang -> pos 5 array
				}
				for(my $k = $start ; $k <= $stop ; $k += $step) {
					$selected = $select_Value[$spalte-2] eq sprintf("%02s", $k) ? "selected=\"selected\"" : "";
					$html.= "<option $selected value=\"" . sprintf("%02s", $k) . "\">" . sprintf("%02s", $k) . "</option>";
				}
				$html.="</select></td>";
			}

			if ($spalte == 8) {  ## Spalte Geraete
				$id ++;
				my $comment = "";
				$comment = AttrVal($select_Value[$spalte-2],"alias","") if (AttrVal($name,"Show_DeviceInfo","") eq "alias");
				$comment = AttrVal($select_Value[$spalte-2],"comment","") if (AttrVal($name,"Show_DeviceInfo","") eq "comment");
				$html.= "<td align=\"center\" style=\"$style_code1\"><input size=\"$Table_Size_TextBox\" type=\"text\" placeholder=\"Timer_".($zeile + 1)."\" id=\"".$id."\" value=\"".$select_Value[$spalte-2]."\"><br><small>$comment</small></td>";
			}

			if ($spalte == 9) {  ## DropDown-Liste Aktion
				$id ++;
				$html.= "<td align=\"center\" style=\"$style_code1\"><select id=\"".$id."\">";							# id need for java script
				foreach (@action) {
					$html.= "<option> $_ </option>" if ($select_Value[$spalte-2] ne $_);
					$html.= "<option selected=\"selected\">".$select_Value[$spalte-2]."</option>" if ($select_Value[$spalte-2] eq $_);
				}
				$html.="</select></td>";
			}

			if ($spalte > 9 && $spalte < $cnt_max) {  ## Spalte Wochentage + aktiv
				$id ++;
				$html.= "<td align=\"center\" style=\"$style_code1\"><input type=\"checkbox\" name=\"days\" id=\"".$id."\" value=\"0\" onclick=\"Checkbox(".$id.")\"></td>" if ($select_Value[$spalte-2] eq "0");
				$html.= "<td align=\"center\" style=\"$style_code1\"><input type=\"checkbox\" name=\"days\" id=\"".$id."\" value=\"1\" onclick=\"Checkbox(".$id.")\" checked></td>" if ($select_Value[$spalte-2] eq "1");
			}

			if ($spalte == $cnt_max) {  ## Button Speichern
				$id ++;
				$html.= "<td align=\"center\" style=\"$style_code1 Padding-right:5px\"> <INPUT type=\"reset\" onclick=\"pushed_savebutton(".$id.")\" value=\"&#128190;\"/></td>"; # &#128427; &#128190;
			}
			Log3 $name, 5, "$name: attr2html | Timer=".$timer_nr[$zeile]." ".$names[$spalte-1]."=".$select_Value[$spalte-2]." cnt_max=$cnt_max ($spalte)" if ($spalte > 1 && $spalte < $cnt_max);
		}
		$html.= "</tr>";  ## Zeilenende
	}
	$html.= "</table>";  ## Tabellenende

	## Tabellenende	+ Script
	$html.= '</div>

	<script>
	/* checkBox Werte von Checkboxen Wochentage */
	function Checkbox(id) {
		var checkBox = document.getElementById(id);
		if (checkBox.checked) {
			checkBox.value = 1;
		} else {
			checkBox.value = 0;
		}
	}

	/* Aktion wenn Speichern */
	function pushed_savebutton(id) {
		var allVals = [];
		var timerNr = (id - 17) / 20;
		allVals.push(timerNr);
		var start = id - 17 + 1;
		for(var i=start; i<id; i++) {
			allVals.push(document.getElementById(i).value);
		}

		/* check Semicolon description */
		var n = allVals[7].search(";");       /* return -1 if not found */
		if (n != -1) {
			FW_errmsg("ERROR: Semicolon not allowed in description!", 4000);
			return;
		}
		FW_cmd(FW_root+ \'?XHR=1"'.$FW_CSRF.'"&cmd={FW_pushed_savebutton("'.$name.'","\'+allVals+\'","'.$FW_room_dupl.'")}\');
	}

	/* Popup DEF - Zusammenbau (PERL -> Rueckgabe -> Javascript) */
	function show_popup(button) {
		FW_cmd(FW_root+\'?cmd={Timer_Popup("'.$name.'","\'+button+\'")}&XHR=1"'.$FW_CSRF.'"\', function(data){popup_return(data)});
	}

	/* Popup DEF - Aktionen */
	function popup_return(txt) {
		var div = $("<div id=\"popup_return\">");
		$(div).html(txt);
		$("body").append(div);
		var oldPos = $("body").scrollTop();

		$(div).dialog({
			dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:false,
			maxHeight:$(window).height()*0.95,
			title: " infobox for user ",
			buttons: [
				{text:"close", click:function(){
					$(this).dialog("close");
					$(div).remove();
					location.reload();
				}}]
		});
	}
	</script>';

	return $html;
}

### for function from pushed_savebutton ###
sub FW_pushed_savebutton {
	my $name = shift;
	my $hash = $defs{$name};
	my $selected_buttons = shift;														# neu,alle,alle,alle,alle,alle,00,Beispiel,on,0,0,0,0,0,0,0,0
	my @selected_buttons = split("," , $selected_buttons);
	my $timer = $selected_buttons[0];
	my $timers_count = 0;																		# Timer by counting
	my $timers_count2 = 0;																	# need to check 1 + 1
	my $timers_diff = 0;																		# need to check 1 + 1
	my $FW_room_dupl = shift;
	my $cnt_names = scalar(@selected_buttons);
	my $devicefound = 0;                                    # to check device exists
	my $reload = 0;

	my $timestamp = TimeNow();                              # Time now -> 2016-02-16 19:34:24
	my @timestamp_values = split(/-|\s|:/ , $timestamp);    # Time now splitted
	my ($sec, $min, $hour, $mday, $month, $year) = ($timestamp_values[5], $timestamp_values[4], $timestamp_values[3], $timestamp_values[2], $timestamp_values[1], $timestamp_values[0]);

	Log3 $name, 5, "$name: FW_pushed_savebutton is running";

	return "ERROR: Comma not allowed in description!" if ($cnt_names > 17);

	foreach my $d (sort keys %{$hash->{READINGS}}) {
		if ($d =~ /^Timer_(\d+)$/) {
			$timers_count++;
			$timers_count2 = $1 * 1;
			if ($timers_count != $timers_count2 && $timers_diff == 0) {  # only for diff
				$timer = $timers_count;
				$timers_diff = 1;
			}
		}
	}

	for(my $i = 0;$i < $cnt_names;$i++) {
		Log3 $name, 5, "$name: FW_pushed_savebutton | ".$names[$i]." -> ".$selected_buttons[$i];
		## to set time to check input ## SA -> pos 4 array | SU -> pos 5 array ##
		if ($i >= 1 && $i <=6 && ( $selected_buttons[$i] ne "$description_all" && $selected_buttons[$i] ne $designations[4] && $selected_buttons[$i] ne $designations[5] )) {
			$sec = $selected_buttons[$i] if ($i == 6);
			$min = $selected_buttons[$i] if ($i == 5);
			$hour = $selected_buttons[$i] if ($i == 4);
			$mday = $selected_buttons[$i] if ($i == 3);
			$month = $selected_buttons[$i]-1 if ($i == 2);
			$year = $selected_buttons[$i]-1900 if ($i == 1);
		}

		if ($i == 7) {
			Log3 $name, 5, "$name: FW_pushed_savebutton | check: exists device or name -> ".$selected_buttons[$i];

			foreach my $d (sort keys %defs) {
				if (defined($defs{$d}{NAME}) && $defs{$d}{NAME} eq $selected_buttons[$i]) {
					$devicefound++;
					Log3 $name, 5, "$name: FW_pushed_savebutton | ".$selected_buttons[$i]." is checked and exists";
				}
			}

			if ($devicefound == 0 && ($selected_buttons[$i+1] eq "on" || $selected_buttons[$i+1] eq "off")) {
				Log3 $name, 5, "$name: FW_pushed_savebutton | ".$selected_buttons[$i]." is NOT exists";
				return "ERROR: device not exists or no description! NO timer saved!";
			}
		}
	}

	return "ERROR: The time is in the past. Please set a time in the future!" if ((time() - fhemTimeLocal($sec, $min, $hour, $mday, $month - 1, $year)) > 0);
	return "ERROR: The next switching point is too small!" if ((fhemTimeLocal($sec, $min, $hour, $mday, $month - 1, $year) - time()) < 60);

	readingsDelete($hash,"Timer_".sprintf("%02s", $timer)."_set") if ($selected_buttons[8] ne "DEF" && ReadingsVal($name, "Timer_".sprintf("%02s", $timer)."_set", 0) ne "0");

	my $oldValue = ReadingsVal($name,"Timer_".sprintf("%02s", $selected_buttons[0]) ,0);
	my $newValue = substr($selected_buttons,(index($selected_buttons,",") + 1));
	$reload++ if ($oldValue ne $newValue && $FW_room_dupl);

	my @Value_split = split(/,/ , $oldValue);
	$oldValue = $Value_split[7];

	@Value_split = split(/,/ , $newValue);
	$newValue = $Value_split[7];

	if ($Value_split[6] eq "" && $Value_split[7] eq "DEF") {                        # standard name, if no name set in DEF option
		my $replace = "Timer_".sprintf("%02s", $selected_buttons[0]);
		$selected_buttons =~ s/,,/,$replace,/g;
	}

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "Timer_".sprintf("%02s", $selected_buttons[0]) , substr($selected_buttons,(index($selected_buttons,",") + 1)));

	my $state = "Timer_".sprintf("%02s", $selected_buttons[0])." saved";
	my $userattrName = "Timer_".sprintf("%02s", $selected_buttons[0])."_set:textField-long";
	my $popup = 0;

	if (($oldValue eq "on" || $oldValue eq "off") && $newValue eq "DEF") {
		$state = "Timer_".sprintf("%02s", $selected_buttons[0])." is saved and revised userattr. Please set DEF in attribute Timer_".sprintf("%02s", $selected_buttons[0])."_set !";
		addToDevAttrList($name,$userattrName);
		addStructChange("modify", $name, "attr $name userattr");                     # note with question mark
		$popup++;
	}

	if ($oldValue eq "DEF" && ($newValue eq "on" || $newValue eq "off")) {
		$state = "Timer_".sprintf("%02s", $selected_buttons[0])." is saved and deleted from userattr";
		Timer_delFromUserattr($hash,$userattrName) if (AttrVal($name, "userattr", undef));
		addStructChange("modify", $name, "attr $name userattr");                     # note with question mark
		$reload++;
	}

	readingsBulkUpdate($hash, "state" , $state, 1);
	readingsEndUpdate($hash, 1);

	Timer_PawList($hash);                                                          # list, Probably associated with

	## popup user message (jump to javascript) ##
	if ($popup != 0) {
		FW_directNotify("FILTER=(room=)?$name", "#FHEMWEB:WEB", "show_popup(".$selected_buttons[0].")", "");
		$reload = 0 if ($reload != 0); # reset, need to right running
	}

	## refresh site, need for userattr & right view checkboxes ##
	FW_directNotify("FILTER=(room=)?$name", "#FHEMWEB:WEB", "location.reload('true')", "") if ($reload != 0);

	Timer_Check($hash) if ($selected_buttons[16] eq "1" && ReadingsVal($name, "internalTimer", "stop") eq "stop");

	return;
}

### Popup DEF - Zusammenbau (Rueckgabe -> Javascript) ###
sub Timer_Popup {
	my $name = shift;
	my $selected_button = shift;
	$selected_button = sprintf("%02s", $selected_button);
	my $ret = "";

	Log3 $name, 5, "$name: Timer_Popup is running";

	if ($language eq "DE") {
		$ret.= "<p style=\"text-decoration-line: underline;\">Hinweis:</p>";
		$ret.= "Das Attribut <code>userattr</code> wurde automatisch angepasst.<br>";
		$ret.= "Um <code>DEF</code> zu definieren, geben Sie bitte das FHEM Kommando oder den PERL Code in das Attribut <code>Timer_$selected_button"."_set</code> ein.<br>";
		$ret.= "<small><code>attr $name Timer_$selected_button"."_set \"DEF Code\"</code> (ohne \" \")</small><br><br>";
		$ret.= "Die Eingabe entspricht der FHEM-Befehlszeile im Browser.<br>";
		$ret.= "<p style=\"text-decoration-line: underline;\">DEF Beispiele:</p>";
		$ret.= "&#8226; FHEM Kommando: <code>set TYPE=IT:FILTER=room=03_Stube.*:FILTER=state=on off</code><br>";
		$ret.= "&#8226; PERL Code: <code>{ Log 1, \"$name: schaltet jetzt\" }</code><br><br>";
		$ret.= "<i>Weitere Beispiele oder Intervallschaltungen finden Sie in der ger&auml;tespezifischen Hilfe.</i><br><br>";
		$ret.= "Klicken Sie auf close, um fortzufahren.";
	} else {
		$ret.= "<p style=\"text-decoration-line: underline;\">Note:</p>";
		$ret.= "The attribute <code>userattr</code> has been automatically revised.<br>";
		$ret.= "To define <code>DEF</code>, please input the FHEM command or PERL code in attribute <code>Timer_$selected_button"."_set</code>.<br>";
		$ret.= "<small><code>attr $name Timer_$selected_button"."_set \"DEF code\"</code> (without \" \")</small><br><br>";
		$ret.= "The input is made equal to the FHEM command line in the browser.<br>";
		$ret.= "<p style=\"text-decoration-line: underline;\">DEF examples:</p>";
		$ret.= "&#8226; FHEM command: <code>set TYPE=IT:FILTER=room=03_Stube.*:FILTER=state=on off</code><br>";
		$ret.= "&#8226; PERL code: <code>{ Log 1, \"$name: switch now\" }</code><br><br>";
		$ret.= "<i>For more examples or interval switching please look into the Device specific help.</i><br><br>";
		$ret.= "Click close to continue.";	
	}
	return $ret;
}

### for delete Timer value from userattr ###
sub Timer_delFromUserattr($$) {
	my $hash = shift;
	my $deleteTimer = shift;
	my $name = $hash->{NAME};

	if (AttrVal($name, "userattr", undef) =~ /$deleteTimer/) {
		delFromDevAttrList($name, $deleteTimer);
		Log3 $name, 5, "$name: delete $deleteTimer from userattr Attributes";
	}
}

### for Check ###
sub Timer_Check($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my @timestamp_values = split(/-|\s|:/ , TimeNow());		# Time now (2016-02-16 19:34:24) splitted in array
	my $dayOfWeek = strftime('%w', localtime);						# Wochentag
	$dayOfWeek = 7 if ($dayOfWeek eq "0");								# Sonntag nach hinten (Position 14 im Array)
	my $intervall = 60;                                   # Intervall to start new InternalTimer (standard)
	my $cnt_activ = 0;                                    # counter for activ timers
	my ($seconds, $microseconds) = gettimeofday();
	my $horizon = AttrVal($name,"Offset_Horizon","REAL");
	my @sunriseValues = split(":" , sunrise_abs($horizon));	# Sonnenaufgang (06:34:24) splitted in array
	my @sunsetValues = split(":" , sunset_abs($horizon));		# Sonnenuntergang (19:34:24) splitted in array
	my $state;;

	Log3 $name, 5, "$name: Check is running, Sonnenaufgang $sunriseValues[0]:$sunriseValues[1]:$sunriseValues[2], Sonnenuntergang $sunsetValues[0]:$sunsetValues[1]:$sunsetValues[2]";
	Log3 $name, 4, "$name: Check is running, drift $microseconds microSeconds";

	foreach my $d (keys %{$hash->{READINGS}}) {
		if ($d =~ /^Timer_\d+$/) {
			my @values = split("," , $hash->{READINGS}->{$d}->{VAL});
			#Jahr  Monat Tag   Stunde Minute Sekunde Gerät              Aktion Mo Di Mi Do Fr Sa So aktiv
			#alle, alle, alle, alle,  alle,  00,     BlueRay_Player_LG, on,    0, 0, 0, 0, 0, 0, 0, 0
			#0     1     2     3      4      5       6                  7      8  9  10 11 12 13 14 15
			my $set = 1;
			if ($values[15] == 1) {                                 # Timer aktiv
				$cnt_activ++;
				$values[3] = $sunriseValues[0] if $values[3] eq $designations[4];	# Stunde | Sonnenaufgang -> pos 4 array
				$values[4] = $sunriseValues[1] if $values[4] eq $designations[4];	# Minute | Sonnenaufgang -> pos 4 array
				$values[3] = $sunsetValues[0] if $values[3] eq $designations[5];	# Stunde | Sonnenuntergang -> pos 5 array
				$values[4] = $sunsetValues[1] if $values[4] eq $designations[5];	# Stunde | Sonnenuntergang -> pos 5 array
				for (my $i = 0;$i < 5;$i++) {													# Jahr, Monat, Tag, Stunde, Minute
					$set = 0 if ($values[$i] ne "$description_all" && $values[$i] ne $timestamp_values[$i]);
				}
				$set = 0 if ($values[(($dayOfWeek*1) + 7)] eq "0");		# Wochentag
				$set = 0 if ($values[5] eq "00" && $timestamp_values[5] ne "00");				# Sekunde (Intervall 60)
				$set = 0 if ($values[5] ne "00" && $timestamp_values[5] ne $values[5]);	# Sekunde (Intervall 10)
				$intervall = 10 if ($values[5] ne "00");
				Log3 $name, 5, "$name: $d - set=$set intervall=$intervall dayOfWeek=$dayOfWeek column array=".(($dayOfWeek*1) + 7)." (".$values[($dayOfWeek*1) + 7].") $values[0]-$values[1]-$values[2] $values[3]:$values[4]:$values[5]";
				if ($set == 1) {
					Log3 $name, 4, "$name: $d - set $values[6] $values[7] ($dayOfWeek, $values[0]-$values[1]-$values[2] $values[3]:$values[4]:$values[5])";
					CommandSet($hash, $values[6]." ".$values[7]) if ($values[7] ne "DEF");
					# $state = "$d set $values[6] $values[7] accomplished";
					readingsSingleUpdate($hash, "state" , "$d set $values[6] $values[7] accomplished", 1);
					if ($values[7] eq "DEF") {
						if (AttrVal($name, $d."_set", undef)) {
							Log3 $name, 5, "$name: $d - exec at command: ".AttrVal($name, $d."_set", undef);
							my $ret = AnalyzeCommandChain(undef, SemicolonEscape(AttrVal($name, $d."_set", undef)));
							Log3 $name, 3, "$name: $d\_set - ERROR: $ret" if($ret);
						} else {
							$state = "$d missing userattr to work!";
						}
					}
				}
			}
		}
	}

	readingsBeginUpdate($hash);
	if ($intervall == 60) {
	 if ($timestamp_values[5] != 0 && $cnt_activ > 0) {
			$intervall = 60 - $timestamp_values[5];
			readingsBulkUpdate($hash, "internalTimer" , $intervall, 1);
			Log3 $name, 3, "$name: time difference too large! interval=$intervall, Sekunde=$timestamp_values[5]";
		}
	}
	## calculated from the starting point at 00 10 20 30 40 50 if Seconds interval active ##
	if ($intervall == 10) {
		if ($timestamp_values[5] % 10 != 0 && $cnt_activ > 0) {
			$intervall = $intervall - ($timestamp_values[5] % 10);
			readingsBulkUpdate($hash, "internalTimer" , $intervall, 1);
			Log3 $name, 3, "$name: time difference too large! interval=$intervall, Sekunde=$timestamp_values[5]";
		}
	}
	$intervall = ($intervall - $microseconds / 1000000); # Korrektur Zeit wegen Drift
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday()+$intervall, "Timer_Check", $hash, 0) if ($cnt_activ > 0);

	$state = "no timer active" if ($cnt_activ == 0 && ReadingsVal($name, "internalTimer", "stop") ne "stop");
	readingsBulkUpdate($hash, "state" , "$state", 1) if defined($state);
	readingsBulkUpdate($hash, "internalTimer" , "stop") if ($cnt_activ == 0 && ReadingsVal($name, "internalTimer", "stop") ne "stop");
	readingsBulkUpdate($hash, "internalTimer" , $intervall, 0) if($cnt_activ > 0);
	readingsEndUpdate($hash, 1);
}

### list, Probably associated with ###
sub Timer_PawList($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $associatedWith = "";

	Log3 $name, 5, "$name: Timer_PawList is running";

	foreach my $d (keys %{$hash->{READINGS}}) {
		if ($d =~ /^Timer_(\d+)$/) {
			my @values = split("," , ReadingsVal($name, $d, ""));
			### clear value, "Probably associated with" ne DEF
			if ($values[7] ne "DEF") {
				if (not grep /$values[6]/, $associatedWith) {
					$associatedWith = $associatedWith eq "" ? $values[6] : $associatedWith.",".$values[6];
				}
			### Self-administration test, "Probably associated with" for DEF
			} elsif ($values[7] eq "DEF") {
				my $Timer_set_attr = AttrVal($name, $d."_set", "");
				if ($Timer_set_attr ne "") {
					Log3 $name, 5, "$name: Timer_PawList | look at DEF: ".$Timer_set_attr;
					$Timer_set_attr =~ /(get|set)\s(\w+)\s/;
					if ($2) {
						Log3 $name, 5, "$name: Timer_PawList | found in DEF: ".$2;
						if (not grep /$2/, $associatedWith) {
							$associatedWith = $associatedWith eq "" ? $2 : $associatedWith.",".$2;
						}
					}
				}
			}
			### END ###
		}
	}

	Log3 $name, 5, "$name: Timer_PawList | Reading .associatedWith is: ".$associatedWith;
	if ($associatedWith ne "") {
		CommandSetReading(undef, "$name .associatedWith $associatedWith");	
	} else {
		readingsDelete($hash,".associatedWith") if(ReadingsVal($name, ".associatedWith", undef));
	}
	## current list "Probably associated with" finish ##
}

##########################################

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper]
=item summary Programmable timer
=item summary_DE Programmierbare Zeitschaltuhr

=begin html

<a name="Timer"></a>
<h3>Timer Modul</h3>
<ul>
The timer module is a programmable timer.<br><br>
In Frontend you can define new times and actions. The smallest possible definition of an action is a 10 second interval.<br>
You can use the dropdown menu to make the settings for the time switch point. Only after clicking on the <code> Save </code> button will the setting be taken over.
In the drop-down list, the numerical values ​​for year / month / day / hour / minute / second are available for selection.<br><br>
In addition, you can use the selection <code> SR </code> and <code> SS </code> in the hour and minute column. These rumps represent the time of sunrise and sunset.<br>
For example, if you select at minute <code> SS </code>, you have set the minutes of the sunset as the value. As soon as you set the value to <code> SS </code> at hour and minute
the timer uses the calculated sunset time at your location. <u><i>(For this calculation the FHEM global attributes latitude and longitude are necessary!)</u></i>

<br><br>
<u>Programmable actions are currently:</u><br>
<ul>
	<li><code> on | off</code> - The states must be supported by the device</li>
	<li><code>DEF</code> - for a PERL code or a FHEM command <font color="red">*</font color> <br><br>
	<ul><u>example for DEF:</u>
	<li><code>{ Log 1, "Timer: now switch" }</code> (PERL code)</li>
	<li><code>update</code> (FHEM command)</li>
	<li><code>trigger Timer state:ins Log geschrieben</code> (FHEM-command)</li>
	<li><code>set TYPE=IT:FILTER=room=Stube.*:FILTER=state=on off</code> (FHEM-command)</li></ul>
	</li>
</ul>
<br>

<b><font color="red">*</font color></b> To do this, enter the code to be executed in the respective attribute. example: <code>Timer_03_set</code>

<br><br>
<u>Interval switching of the timer is only possible in the following variants:</u><br>
<ul><li>minute, define second and set all other values ​​(minute, hour, day, month, year) to <code>all</code></li>
   <li>hourly, define second + minute and set all other values ​​(hour, day, month, year) to <code>all</code></li>
	 <li>daily, define second + minute + hour and set all other values ​​(day, month, year) to <code>all</code></li>
	 <li>monthly, define second + minute + hour + day and set all other values ​​(month, year) to <code>all</code></li>
	 <li>annually, define second + minute + hour + day + month and set the value (year) to <code>all</code></li>
	 <li>sunrise, define second & define minute + hour with <code>SR</code> and set all other values ​​(day, month, year) to <code>all</code></li>
	 <li>sunset, define second & define minute + hour with <code>SS</code> and set all other values ​​(day, month, year) to <code>all</code></li></ul>
<br>
Any interval circuits can be defined in which in the associated timer attribute e.g. the following Perl code is inserted:<br>
<code>{if ($min % 5 == 0) {fhem("set FS10_6_11 toggle");}}</code><br>
This timer would run every 5 minutes if the timer is configured to run in a minute as described.<br>
The following variables for time and date are available:<br>
<code>$sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst, $week, $hms, $hm, $md, $ymd, $we, $twe</code><br>
This makes it possible, for example, to have a timer run every Sunday at 15:30:00.
<br><br>

<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; Timer</code><br><br>
		<u>example:</u>
		<ul>
		define timer Timer
		</ul>
	</ul><br>

<b>Set</b><br>
	<ul>
		<a name="addTimer"></a>
		<li>addTimer: Adds a new timer</li><a name=""></a>
		<a name="deleteTimer"></a>
		<li>deleteTimer: Deletes the selected timer</li><a name=""></a>
		<a name="saveTimers"></a>
		<li>saveTimers: Saves the settings in file <code>Timers.txt</code> on directory <code>./FHEM/lib</code>.</li>
		<a name="sortTimer"></a>
		<li>sortTimer: Sorts the saved timers alphabetically.</li>
	</ul><br><br>

<b>Get</b><br>
	<ul>
		<a name="loadTimers"></a>
		<li>loadTimers: Loads a saved configuration from file <code>Timers.txt</code> from directory <code>./FHEM/lib</code>.</li><a name=""></a>
	</ul><br><br>

<b>Attribute</b><br>
	<ul><li><a href="#disable">disable</a></li></ul><br>
	<ul><li><a name="stateFormat">stateFormat</a><br>
	It is used to format the value <code>state</code><br>
	<u>example:</u> <code>{ ReadingsTimestamp($name, "state", 0) ."&amp;nbsp;- ". ReadingsVal($name, "state", "none");}</code><br>
	&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- will format to output: <code>2019-09-19 17:51:44 - Timer_04 saved</code></li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Border">Table_Border</a><br>
	Shows the table border. (on | off = default)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Border_Cell">Table_Border_Cell</a><br>
	Shows the cell frame. (on | off = default)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Header_with_time">Table_Header_with_time</a><br>
	Shows or hides the sunrise and sunset with the local time above the table. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Size_TextBox">Table_Size_TextBox</a><br>
	Correction value to change the length of the text box for the device name / designation. (default 20)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Style">Table_Style</a><br>
	Turns on the defined table style. (on | off, default off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_View_in_room">Table_View_in_room</a><br>
	Toggles the tables UI in the room view on or off. (on | off, standard on)<br>
	<small><i>In the room <code> Unsorted </code> the table UI is always switched off!</i></small></li><a name=" "></a></ul><br>
	<ul><li><a name="Timer_preselection">Timer_preselection</a><br>
	Sets the input values ​​for a new timer to the current time. (on | off = default)</li><a name=" "></a></ul><br>
	<ul><li><a name="Timer_xx_set">Timer_xx_set</a><br>
	Location for the FHEM command or PERL code of the timer (xx has the numerical value of 01-99). WITHOUT this attribute, which <b> only appears if action <code> DEF </code> is set </b>,
	The module does not process FHEM command or PERL code from the user. <code><font color="red">*</font color> </code></li><a name=" "></a></ul><br>
	<ul><li><a name="Offset_Horizon">Offset_Horizon</a><br>
	Different elevation angles are used to calculate sunrise and sunset times.<br>
	(REAL = 0°, CIVIL = -6°, NAUTIC = -12°, ASTRONOMIC = -18°, default REAL)</li><a name=" "></a></ul><br>
	<ul><li><a name="Show_DeviceInfo">Show_DeviceInfo</a><br>
	Shows the additional information (alias | comment, default off)</li><a name=" "></a></ul><br>
	<br>

<b><i>Generated readings</i></b><br>
	<ul><li>Timer_xx<br>
	Memory values ​​of the individual timer</li><br>
	<li>internalTimer<br>
	State of the internal timer (stop or Interval until the next call)</li><br><br></ul>

<b><i><u>Hints:</u></i></b><br>
<ul><li>Entries in the system logfile like: <code>2019.09.20 22:15:01 3: Timer: time difference too large! interval=59, Sekunde=01</code> say that the timer has recalculated the time.</li></ul>

</ul>
=end html


=begin html_DE

<a name="Timer"></a>
<h3>Timer Modul</h3>
<ul>
Das Timer Modul ist eine programmierbare Schaltuhr.<br><br>
Im Frontend k&ouml;nnen Sie neue Zeitpunkte und Aktionen definieren. Die kleinstm&ouml;gliche Definition einer Aktion ist ein 10 Sekunden Intervall.<br>
Mittels der Dropdown Men&uuml;s k&ouml;nnen Sie die Einstellungen f&uuml;r den Zeitschaltpunkt vornehmen. Erst nach dem dr&uuml;cken auf den <code>Speichern</code> Knopf wird die Einstellung &uuml;bernommen.<br><br>
In der DropDown-Liste stehen jeweils die Zahlenwerte f&uuml;r Jahr	/ Monat	/ Tag	/ Stunde / Minute / Sekunde zur Auswahl.<br>
Zus&auml;tzlich k&ouml;nnen Sie in der Spalte Stunde und Minute die Auswahl <code>SA</code> und <code>SU</code> nutzen. Diese K&uuml;rzel stehen f&uuml;r den Zeitpunkt Sonnenaufgang und Sonnenuntergang.<br>
Wenn sie Beispielsweise bei Minute <code>SU</code> ausw&auml;hlen, so haben Sie die Minuten des Sonnenuntergang als Wert gesetzt. Sobald Sie bei Stunde und Minute den Wert auf <code>SU</code>
stellen, so nutzt der Timer den errechnenten Zeitpunkt Sonnenuntergang an Ihrem Standort. <u><i>(F&uuml;r diese Berechnung sind die FHEM globalen Attribute latitude und longitude notwendig!)</u></i>

<br><br>
<u>Programmierbare Aktionen sind derzeit:</u><br>
<ul>
	<li><code> on | off</code> - Die Zust&auml;nde m&uuml;ssen von dem zu schaltenden Device unterst&uuml;tzt werden</li>
	<li><code>DEF</code> - f&uuml;r einen PERL-Code oder ein FHEM Kommando <font color="red">*</font color> <br><br>
	<ul><u>Beispiele f&uuml;r DEF:</u>
	<li><code>{ Log 1, "Timer: schaltet jetzt" }</code> (PERL-Code)</li>
	<li><code>update</code> (FHEM-Kommando)</li>
	<li><code>trigger Timer state:ins Log geschrieben</code> (FHEM-Kommando)</li>
	<li><code>set TYPE=IT:FILTER=room=Stube.*:FILTER=state=on off</code> (FHEM-Kommando)</li></ul>
	</li>
</ul>
<br>

<b><font color="red">*</font color></b> Hierf&uuml;r hinterlegen Sie den auszuf&uuml;hrenden PERL-Code in das jeweilige Attribut. Bsp.: <code>Timer_03_set</code>

<br><br>
<u>Eine Intervallschaltung des Timer ist nur m&ouml;glich in folgenden Varianten:</u><br>
<ul><li>min&uuml;tlich, Sekunde definieren und alle anderen Werte (Minute, Stunde, Tag, Monat, Jahr) auf <code>alle</code> setzen</li>
   <li>st&uuml;ndlich, Sekunde + Minute definieren und alle anderen Werte (Stunde, Tag, Monat, Jahr) auf <code>alle</code> setzen</li>
	 <li>t&auml;glich, Sekunde + Minute + Stunde definieren und alle anderen Werte (Tag, Monat, Jahr) auf <code>alle</code> setzen</li>
	 <li>monatlich, Sekunde + Minute + Stunde + Tag definieren und alle anderen Werte (Monat, Jahr) auf <code>alle</code> setzen</li>
	 <li>j&auml;hrlich, Sekunde + Minute + Stunde + Tag + Monat definieren und den Wert (Jahr) auf <code>alle</code> setzen</li>
	 <li>Sonnenaufgang, Sekunde definieren & Minute + Stunde definieren mit <code>SA</code> und alle anderen Werte (Tag, Monat, Jahr) auf <code>alle</code> setzen</li>
	 <li>Sonnenuntergang, Sekunde definieren & Minute + Stunde definieren mit <code>SU</code> und alle anderen Werte (Tag, Monat, Jahr) auf <code>alle</code> setzen</li></ul>
<br>
Beliebige Intervallschaltungen k&ouml;nnen definiert werden, in dem im zugeh&ouml;rigen Timer-Attribut z.B. folgender Perl-Code eingef&uuml;gt wird:<br>
<code>{if ($min % 5 == 0) {fhem("set FS10_6_11 toggle");}}</code><br>
Dieser Timer w&uuml;rde dann aller 5 Minuten ausgef&uuml;hrt, wenn der Timer wie beschrieben auf min&uuml;tliches Ausf&uuml;hren konfiguriert ist.<br>
Folgende Variablen f&uuml;r Zeit- und Datumsangaben stehen zur Verf&uuml;gung:<br>
<code>$sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst, $week, $hms, $hm, $md, $ymd, $we, $twe</code><br>
Damit ist es m&ouml;glich, einen Timer beispielsweise nur jeden Sonntag um 15:30:00 Uhr etwas ausf&uuml;hren zu lassen.
<br><br>

<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; Timer</code><br><br>
		<u>Beispiel:</u>
		<ul>
		define Schaltuhr Timer
		</ul>
	</ul><br>

<b>Set</b><br>
	<ul>
		<a name="addTimer"></a>
		<li>addTimer: F&uuml;gt einen neuen Timer hinzu.</li><a name=""></a>
		<a name="deleteTimer"></a>
		<li>deleteTimer: L&ouml;scht den ausgew&auml;hlten Timer.</li><a name=""></a>
		<a name="saveTimers"></a>
		<li>saveTimers: Speichert die eingestellten Timer in der Datei <code>Timers.txt</code> im Verzeichnis <code>./FHEM/lib</code>. </li>
		<a name="sortTimer"></a>
		<li>sortTimer: Sortiert die gespeicherten Timer alphabetisch.</li>
	</ul><br><br>

<b>Get</b><br>
	<ul>
		<a name="loadTimers"></a>
		<li>loadTimers: L&auml;d eine gespeicherte Konfiguration aus der Datei <code>Timers.txt</code> aus dem Verzeichnis <code>./FHEM/lib</code>.</li><a name=""></a>
	</ul><br><br>

<b>Attribute</b><br>
	<ul><li><a href="#disable">disable</a></li></ul><br>
	<ul><li><a name="stateFormat">stateFormat</a><br>
	Es dient zur Formatierung des Wertes <code>state</code><br>
	<u>Beispiel:</u> <code>{ ReadingsTimestamp($name, "state", 0) ."&amp;nbsp;- ". ReadingsVal($name, "state", "none");}</code><br>
	&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- wird zur formatieren Ausgabe: <code>2019-09-19 17:51:44 - Timer_04 saved</code></li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Border">Table_Border</a><br>
	Blendet den Tabellenrahmen ein. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Border_Cell">Table_Border_Cell</a><br>
	Blendet den Cellrahmen ein. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Header_with_time">Table_Header_with_time</a><br>
	Blendet den Sonnenauf und Sonnenuntergang mit der lokalen Zeit &uuml;ber der Tabelle ein oder aus. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Size_TextBox">Table_Size_TextBox</a><br>
	Korrekturwert um die L&auml;nge der Textbox f&uuml;r die Ger&auml;tenamen / Bezeichung zu ver&auml;ndern. (standard 20)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_Style">Table_Style</a><br>
	Schaltet den definierten Tabellen-Style ein. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Table_View_in_room">Table_View_in_room</a><br>
	Schaltet das Tabellen UI in der Raumansicht an oder aus. (on | off, standard on)<br>
	<small><i>Im Raum <code>Unsorted</code> ist das Tabellen UI immer abgeschalten!</i></small></li><a name=" "></a></ul><br>
	<ul><li><a name="Timer_preselection">Timer_preselection</a><br>
	Setzt die Eingabewerte bei einem neuen Timer auf die aktuelle Zeit. (on | off, standard off)</li><a name=" "></a></ul><br>
	<ul><li><a name="Timer_xx_set">Timer_xx_set</a><br>
	Speicherort f&uuml;r das FHEM-Kommando oder den PERL-Code des Timers (xx hat den Zahlenwert von 01-99). OHNE dieses Attribut, welches <b>nur erscheint wenn die Aktion <code> DEF </code> eingestellt </b> ist,
	verarbeitet das Modul kein Kommando oder PERL-Code vom Benutzer. <code> <font color="red">*</font color> </code></li><a name=" "></a></ul><br>
	<ul><li><a name="Offset_Horizon">Offset_Horizon</a><br>
	F&uuml;r die Berechnung der Zeiten von Sonnenaufgang und Sonnenuntergang werden verschiedene H&ouml;henwinkel verwendet.<br>
	(REAL = 0°, CIVIL = -6°, NAUTIC = -12°, ASTRONOMIC = -18°, Standard REAL)</li><a name=" "></a></ul><br>
	<ul><li><a name="Show_DeviceInfo">Show_DeviceInfo</a><br>
	Blendet die Zusatzinformation ein. (alias | comment, standard off)</li><a name=" "></a></ul><br>
	<br>

<b><i>Generierte Readings</i></b><br>
	<ul><li>Timer_xx<br>
	Speicherwerte des einzelnen Timers</li><br>
	<li>internalTimer<br>
	Zustand des internen Timers (stop oder Intervall bis zum n&auml;chsten Aufruf)</li><br><br></ul>

<b><i><u>Hinweise:</u></i></b><br>
<ul><li>Eintr&auml;ge im Systemlogfile wie: <code>2019.09.20 22:15:01 3: Timer: time difference too large! interval=59, Sekunde=01</code> sagen aus, das der Timer die Zeit neu berechnet hat.</li></ul>

</ul>
=end html_DE

# Ende der Commandref
=cut