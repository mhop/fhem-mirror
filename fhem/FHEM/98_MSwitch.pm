# $Id$

# 98_MSwitch.pm
#
# copyright #####################################################
#
# 98_MSwitch.pm
#
# written by Byte09
# Maintained by Byte09
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# FHEM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FHEM.  If not, see <http://www.gnu.org/licenses/>.
#################################################################
# Todo's:
#
# 
#################################################################

package main;
use Time::Local;
use strict;
use warnings;
use POSIX;

# Version #######################################################
my $autoupdate = 'on'; #off/on
my $version = 'V2.01';
my $vupdate = 'V2.00';
my $savecount = 30;
my $standartstartdelay =60;
# standartlist ignorierter Devices
my @doignore =qw(notify allowed at watchdog doif fhem2fhem telnet FileLog readingsGroup FHEMWEB autocreate eventtypes readingsproxy svg cul);

##################### ############################################

sub MSwitch_Checkcond_time($$);
sub MSwitch_Checkcond_state($$);
sub MSwitch_Checkcond_day($$$$);
sub MSwitch_Createtimer($);
sub MSwitch_Execute_Timer($);
sub MSwitch_LoadHelper($);
sub MSwitch_debug2($$);
sub MSwitch_ChangeCode($$);
sub MSwitch_Add_Device($$);
sub MSwitch_Del_Device($$);
sub MSwitch_Debug($);
sub MSwitch_Exec_Notif($$$$$);
sub MSwitch_checkcondition($$$);
sub MSwitch_Delete_Delay($$);
sub MSwitch_Check_Event($$);
sub MSwitch_makeAffected($);
sub MSwitch_backup($);
sub MSwitch_backup_this($);
sub MSwitch_backup_all($);
sub MSwitch_backup_done($);
sub MSwitch_checktrigger(@);
sub MSwitch_Cmd(@);
sub MSwitch_toggle($$);
sub MSwitch_Getconfig($);
sub MSwitch_saveconf($$);
sub MSwitch_replace_delay($$);
sub MSwitch_repeat($);
sub MSwitch_Createrandom($$$);
sub MSwitch_Execute_randomtimer($);
sub MSwitch_Clear_timer($);
sub MSwitch_Createnumber($);
sub MSwitch_Createnumber1($);
sub MSwitch_Savemode($);
sub MSwitch_set_dev($);
sub MSwitch_EventBulk($$$);
sub MSwitch_priority ;
sub MSwitch_dec($$);
sub MSwitch_makefreecmd($$);
sub MSwitch_clearlog($);
sub MSwitch_LOG($$$);
sub MSwitch_confchange($$);


my %sets = (
    "on"             => "noArg",
    "off"            => "noArg",
	"reload_timer"   => "noArg",
    "active"         => "noArg",
    "inactive"       => "noArg",
    "devices"        => "noArg",
    "details"        => "noArg",
    "del_trigger"    => "noArg",
    "del_delays"     => "noArg",
    "trigger"        => "noArg",
    "filter_trigger" => "noArg",
    "add_device"     => "noArg",
    "del_device"     => "noArg",
    "addevent"       => "noArg",
    "backup_MSwitch" => "noArg",
    "import_config"  => "noArg",
    "saveconfig"     => "noArg",
	"savesys"     => "noArg",
	"fakeevent"       => "noArg",
	"exec_cmd1"       => "noArg",
	"exec_cmd2"       => "noArg",
	"exec_cmd1+2"       => "noArg",
	"wait"            => "noArg",
	"VUpdate"            => "noArg",
	"confchange"            => "noArg",
	"clearlog"            => "noArg",
    "set_trigger"    => "noArg"
);
my %gets = (
    "active_timer"         => "noArg",
    "restore_MSwitch_Data" => "noArg",
    "get_config"           => "noArg"
);



####################
sub MSwitch_Initialize($) {
    my ($hash) = @_;
    $hash->{SetFn}             = "MSwitch_Set";
    $hash->{AsyncOutput}       = "MSwitch_AsyncOutput";
	$hash->{RenameFn}            = "MSwitch_Rename";
	$hash->{CopyFn}            = "MSwitch_Copy";
    $hash->{GetFn}             = "MSwitch_Get";
    $hash->{DefFn}             = "MSwitch_Define";
    $hash->{UndefFn}           = "MSwitch_Undef";
    $hash->{DeleteFn}          = "MSwitch_Delete";
    $hash->{ParseFn}           = "MSwitch_Parse";
    $hash->{AttrFn}            = "MSwitch_Attr";
    $hash->{NotifyFn}          = "MSwitch_Notify";
    $hash->{FW_detailFn}       = "MSwitch_fhemwebFn";
    $hash->{FW_deviceOverview} = 1;
    $hash->{FW_summaryFn}      = "MSwitch_summary";
    $hash->{NotifyOrderPrefix} = "45-";
    $hash->{AttrList} =
        "  disable:0,1"
	  . "  disabledForIntervals"
      . "  MSwitch_Help:0,1"
      . "  MSwitch_Debug:0,1,2,3,4"
      . "  MSwitch_Expert:0,1"
      . "  MSwitch_Delete_Delays:0,1"
      . "  MSwitch_Include_Devicecmds:0,1"
      . "  MSwitch_Include_Webcmds:0,1"
      . "  MSwitch_Include_MSwitchcmds:0,1"
      . "  MSwitch_Activate_MSwitchcmds:0,1"
      . "  MSwitch_Lock_Quickedit:0,1"
      . "  MSwitch_Ignore_Types"
      . "  MSwitch_Trigger_Filter"
      . "  MSwitch_Extensions:0,1"
      . "  MSwitch_Inforoom"
      . "  MSwitch_Mode:Full,Notify,Toggle"
      . "  MSwitch_Condition_Time:0,1"
      . "  MSwitch_RandomTime"
      . "  MSwitch_RandomNumber"
	  . "  MSwitch_Safemode:0,1"
	  . "  MSwitch_Startdelay:0,10,20,30,60,90,120"
      . "  MSwitch_Wait";
    $hash->{FW_addDetailToSummary} = 0;
}
####################
sub MSwitch_Rename ($)
{
	my ( $new_name, $old_name ) = @_;
	my $hash_new = $defs{$new_name};
	
#Log3( $new_name, 0,"new_name " .$new_name  );
#Log3( $new_name, 0,"old_name " .$old_name  );	
	
$modules{MSwitch}{defptr}{$new_name} = $hash_new;

#foreach my $testdevice ( keys %{ $modules{MSwitch}{defptr} } )    #
   # {
     #  Log3( $new_name, 0,"dev " .$testdevice  );	
	  # Log3( $new_name, 0,"devnhash " .$defs{$testdevice}  );
    #}



}

####################
sub MSwitch_Copy ($)
{
	my ( $old_name, $new_name ) = @_;
	my $hash = $defs{$new_name};
	my @areadings =
      qw(.Device_Affected .Device_Affected_Details .Device_Events .First_init .Trigger_Whitelist .Trigger_cmd_off .Trigger_cmd_on .Trigger_condition .Trigger_off .Trigger_on .Trigger_time .V_Check Exec_cmd Trigger_device Trigger_log last_event state .sysconf Sys_Extension) ;    #alle readings
  
	my $cs = "attr $new_name disable 1";
    my $errors = AnalyzeCommandChain( undef, $cs );
    if ( defined($errors) ) 
		{
           Log3( $new_name, 1, "ERROR $cs" );
        }
	  
	 foreach my $key (@areadings) 
		{
        my $tmp = ReadingsVal( $old_name, $key, 'undef' );
		fhem("setreading ".$new_name." ".$key." ".$tmp);
        }
	MSwitch_LoadHelper($hash);
}

####################
sub MSwitch_summary($) {
    my ( $wname, $name, $room ) = @_;
    my $hash = $defs{$name};
    my $testroom = AttrVal( $name, 'MSwitch_Inforoom', 'undef' );
    if ( $testroom ne $room ) { return; }
    my $test = AttrVal( $name, 'comment', '0' );
    my $info = AttrVal( $name, 'comment', 'No Info saved at ATTR omment' );
    my $image    = ReadingsVal( $name, 'state', 'undef' );
    my $ret      = '';
    my $devtitle = '';
    my $option   = '';
    my $html     = '';
    my $triggerc = 1;
    my $timer    = 1;
    my $trigger = ReadingsVal( $name, 'Trigger_device', 'undef' );
    my @devaff = split( / /, MSwitch_makeAffected($hash) );
    $option .= "<option value=\"affected devices\">affected devices</option>";

    foreach (@devaff) 
	{
        $devtitle .= $_ . ", ";
        $option   .= "<option value=\"$_\">" . $_ . "</option>";
    }
	
    chop($devtitle);
    chop($devtitle);
    my $affected = "<select style='width: 12em;' title=\"". $devtitle . "\" >". $option. "</select>";
	### time
    my $optiontime;
    my $devtitletime = '';
    my $triggertime  = ReadingsVal( $name, 'Trigger_device', 'not defined' );
	
	my $devtime = ReadingsVal( $name, '.Trigger_time', '' );
	$devtime =~ s/\[//g;
	$devtime =~ s/\]/ /g;
	
	my @devtime      = split( /~/, $devtime );
    $optiontime .= "<option value=\"Time:\">At: aktiv</option>";
    my $count = @devtime;

	$devtime[0] =~ s/on/on+cmd1: /g if defined $devtime[0];
	$devtime[1] =~ s/off/off+cmd2: /g if defined $devtime[1];
	$devtime[2] =~ s/ononly/only cmd1: /g if defined $devtime[2];
	$devtime[3] =~ s/offonly/only cmd2: /g if defined $devtime[3];
	
	if ( AttrVal( $name, 'MSwitch_Mode', 'Full' ) ne "Notify" ) 
		{
		$optiontime   .= "<option value=\"$devtime[0]\">" . $devtime[0] . "</option>" if defined $devtime[0];
		$optiontime   .= "<option value=\"$devtime[1]\">" . $devtime[1] . "</option>" if defined $devtime[1];
		}
		
	$optiontime   .= "<option value=\"$devtime[2]\">" . $devtime[2] . "</option>" if defined $devtime[2];
	$optiontime   .= "<option value=\"$devtime[3]\">" . $devtime[3] . "</option>" if defined $devtime[3];

    my $affectedtime = '';
    if ( $count == 0 ) 
		{
			$timer = 0;
			$affectedtime =
				"<select style='width: 12em;' title=\""
			  . $devtitletime
			  . "\" disabled ><option value=\"Time:\">At: inaktiv</option></select>";
		}
    else 
		{
			chop($devtitletime);
			chop($devtitletime);
			$affectedtime =
				"<select style='width: 12em;' title=\""
			  . $devtitletime . "\" >"
			  . $optiontime
			  . "</select>";
		}
    if ( $info eq 'No Info saved at ATTR omment' )
		{
			$ret .=
				"<input disabled title=\""
			  . $info
			  . "\" name='info' type='button'  value='Info' onclick =\"FW_okDialog('"
			  . $info . "')\">";
		}
    else 
		{
			$ret .=
				"<input title=\""
			  . $info
			  . "\" name='info' type='button'  value='Info' onclick =\"FW_okDialog('"
			  . $info . "')\">";
		}

    if ( $trigger eq 'no_trigger' || $trigger eq 'undef' ) 
		{
			$triggerc = 0;
			if ( $triggerc != 0 || $timer != 0 )
				{
					$ret .="<select style='width: 18em;' title=\"\" disabled ><option value=\"Trigger:\">Trigger: inaktiv</option></select>";
				}
			else
				{
					$affectedtime = "";
					$ret .= "&nbsp;&nbsp;Multiswitchmode (no trigger / no timer)&nbsp;";
				}
		}
    else 
		{
			$ret .= "<select style='width: 18em;' title=\"\" >";
			$ret .= "<option value=\"Trigger:\">Trigger: " . $trigger . "</option>";
			$ret .=
				"<option value=\"Trigger:\">on+cmd1: "
			  . ReadingsVal( $name, '.Trigger_on', 'not defined' )
			  . "</option>";
			$ret .=
				"<option value=\"Trigger:\">off+cmd2: "
			  . ReadingsVal( $name, '.Trigger_off', 'not defined' )
			  . "</option>";
			$ret .=
				"<option value=\"Trigger:\">only cmd1: "
			  . ReadingsVal( $name, '.Trigger_cmd_on', 'not defined' )
			  . "</option>";
			$ret .=
				"<option value=\"Trigger:\">only cmd2: "
			  . ReadingsVal( $name, '.Trigger_cmd_off', 'not defined' )
			  . "</option>";
			$ret .= "</select>";
		}
		
    $ret .= $affectedtime;
    $ret .= $affected;
	
	if (ReadingsVal( $name, '.V_Check', 'not defined' ) ne $vupdate)
	{
		$ret .= "
		</td><td informId=\"" . $name . "tmp\">Versionskonflikt ! 
		</td><td informId=\"" . $name . "tmp\">
		<div class=\"dval\" informid=\"" . $name . "-state\"></div>
		</td><td informId=\"" . $name . "tmp\">
		<div informid=\"" . $name . "-state-ts\">(please help)</div>
		 ";
	
	}
	else{
    if ( AttrVal( $name, 'disable', "0" ) eq '1' ) 
		{
			$ret .= "
		</td><td informId=\"" . $name . "tmp\">State: 
		</td><td informId=\"" . $name . "tmp\">
		<div class=\"dval\" informid=\"" . $name . "-state\"></div>
		</td><td informId=\"" . $name . "tmp\">
		<div informid=\"" . $name . "-state-ts\">disabled</div>
		 ";
		}
    else
		{
			$ret .= "
		</td><td informId=\"" . $name . "tmp\">
		State: </td><td informId=\"" . $name . "tmp\">
		<div class=\"dval\" informid=\"". $name . "-state\">" . ReadingsVal( $name, 'state', '' ) . "</div>
		</td><td informId=\"" . $name . "tmp\">";

			if ( AttrVal( $name, 'MSwitch_Mode', 'Full' ) ne "Notify" ) 
				{
					$ret .=
						"<div informid=\""
					  . $name
					  . "-state-ts\">"
					  . ReadingsTimestamp( $name, 'state', '' )
					  . "</div>";
				}
			 else
				{
							 $ret .=
						 "<div informid=\""
					   . $name
					   . "-state-ts\">"
					   . ReadingsTimestamp( $name, 'state', '' )
					   . "</div>";
				}
		}
		}
    $ret .= "<script>
	\$( \"td[informId|=\'" . $name . "\']\" ).attr(\"informId\", \'test\');
	\$(document).ready(function(){
	\$( \".col3\" ).text( \"\" );
	\$( \".devType\" ).text( \"MSwitch Inforoom: Anzeige der Deviceinformationen, Änderungen sind nur in den Details möglich.\" );
	});
	</script>";
    return $ret;
}

####################
sub MSwitch_LoadHelper($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
    my $oldtrigger = ReadingsVal( $Name, 'Trigger_device', 'undef' );
    my $devhash    = undef;
    my $cdev       = '';
    my $ctrigg     = '';
    if ( defined $hash->{DEF} ) 
	{
        $devhash = $hash->{DEF};
        my @dev = split( /#/, $devhash );
        $devhash = $dev[0];
        ( $cdev, $ctrigg ) = split( / /, $devhash );
		if ( defined $ctrigg ) 
		{
			$ctrigg =~ s/\.//g;
		}
		else
		{
			$ctrigg = ''
		}
		if ( defined $devhash )
		{
			$hash->{NOTIFYDEV} = $cdev; # stand aug global ... änderung auf ...
			readingsSingleUpdate( $hash, "Trigger_device", $cdev, 0 );
			if ( defined $cdev && $cdev ne '' )
			{
				readingsSingleUpdate( $hash, "Trigger_device", $cdev, 0 );
			}
		}
        else 
		{
            $hash->{NOTIFYDEV} = 'no_trigger';
            readingsSingleUpdate( $hash, "Trigger_device", 'no_trigger', 0 );
        }
    }
	
    if (   !defined $hash->{NOTIFYDEV} || $hash->{NOTIFYDEV} eq 'undef' || $hash->{NOTIFYDEV} eq '' )
	{
		$hash->{NOTIFYDEV} = 'no_trigger';
	}
	
    if ( $oldtrigger ne 'undef' ) 
	{
        $hash->{NOTIFYDEV} = $oldtrigger;
        readingsSingleUpdate( $hash, "Trigger_device", $oldtrigger, 0 );
    }
####################
	 MSwitch_set_dev($hash);
#################
    if ( AttrVal( $Name, 'MSwitch_Activate_MSwitchcmds', "0" ) eq '1' )
	{
        addToAttrList('MSwitchcmd');
    }
################erste initialisierung eines devices
   if ( ReadingsVal( $Name, '.V_Check', 'undef' ) ne $vupdate && $autoupdate eq "on") 
	{
        MSwitch_VUpdate($hash);
   }
################
    if ( ReadingsVal( $Name, '.First_init', 'undef' ) ne 'done' ) 
	{
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, ".V_Check", $vupdate );
        readingsBulkUpdate( $hash, "state",    'off' );
        if ( defined $ctrigg && $ctrigg ne '' ) 
		{
            readingsBulkUpdate( $hash, ".Device_Events", $ctrigg );
            $hash->{DEF} = $cdev;
        }
        else
		{
            readingsBulkUpdate( $hash, ".Device_Events", 'no_trigger' );
        }
        readingsBulkUpdate( $hash, ".Trigger_on",      'no_trigger' );
        readingsBulkUpdate( $hash, ".Trigger_off",     'no_trigger' );
        readingsBulkUpdate( $hash, ".Trigger_cmd_on",  'no_trigger' );
        readingsBulkUpdate( $hash, ".Trigger_cmd_off", 'no_trigger' );
        readingsBulkUpdate( $hash, "Trigger_log",      'off' );
        readingsBulkUpdate( $hash, ".Device_Affected", 'no_device' );
        readingsBulkUpdate( $hash, ".First_init",      'done' );
        readingsEndUpdate( $hash, 0 );
        # setze ignoreliste
        $attr{$Name}{MSwitch_Ignore_Types} = join( " ", @doignore );
        # setze attr inforoom
        my $testdev = '';
		LOOP22:
        foreach my $testdevices ( keys %{ $modules{MSwitch}{defptr} } )    #
			{
				if ( $Name eq $testdevices ) { next LOOP22; }
				$testdev = AttrVal( $testdevices, 'MSwitch_Inforoom', '' );
			}
        if ( $testdev ne '' ) 
		{
			$attr{$Name}{MSwitch_Inforoom} = $testdev ,
		}
        #setze alle attrs
        $attr{$Name}{MSwitch_Help}                = '0';
        $attr{$Name}{MSwitch_Debug}               = '0';
        $attr{$Name}{MSwitch_Expert}              = '0';
        $attr{$Name}{MSwitch_Delete_Delays}       = '1';
        $attr{$Name}{MSwitch_Include_Devicecmds}  = '1';
        $attr{$Name}{MSwitch_Include_Webcmds}     = '0';
        $attr{$Name}{MSwitch_Include_MSwitchcmds} = '0';
        $attr{$Name}{MSwitch_Include_MSwitchcmds} = '0';
        $attr{$Name}{MSwitch_Lock_Quickedit}      = '1';
        $attr{$Name}{MSwitch_Extensions}          = '0';
        $attr{$Name}{MSwitch_Mode}                = 'Full';
    }
	
	# NEU; ZUVOR IN SET
	my $testnew = ReadingsVal( $Name, '.Trigger_on', 'undef' );
    if ( $testnew eq 'undef' ) 
	{
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, ".Device_Events",   'no_trigger' );
        readingsBulkUpdate( $hash, ".Trigger_on",      'no_trigger' );
        readingsBulkUpdate( $hash, ".Trigger_off",     'no_trigger' );
        readingsBulkUpdate( $hash, "Trigger_log",      'on' );
        readingsBulkUpdate( $hash, ".Device_Affected", 'no_device' );
        readingsEndUpdate( $hash, 0 );
    }
    MSwitch_Createtimer($hash);    #Neustart aller timer
}

####################
sub MSwitch_Define($$) {
    my $loglevel = 0;
    my ( $hash, $def ) = @_;
    my @a          = split( "[ \t][ \t]*", $def );
    my $name       = $a[0];
    my $devpointer = $name;
    my $devhash    = '';
	my $old=$hash->{OLDDEF};
	$old = '' if !defined $old;
    $modules{MSwitch}{defptr}{$devpointer} = $hash;
    $hash->{Version_Modul} = $version;
	$hash->{Version_Datenstruktur} = $vupdate;
	$hash->{Version_autoupdate} = $autoupdate;
	
	if ($init_done && $old ne '')
	{
		my $timecond = gettimeofday() + 5;
		InternalTimer( $timecond, "MSwitch_LoadHelper", $hash); 
	}
    return;
}

####################
sub MSwitch_Get($$@) {
    my ( $hash, $name, $opt, @args ) = @_;
    my $ret;
	
	if ( ReadingsVal( $name, '.change', '' ) ne '' ) 
		{
			return "Unknown argument, choose one of ";
		}
	
    return "\"get $name\" needs at least one argument" unless ( defined($opt) );
####################
    if ( $opt eq 'restore_MSwitch_Data' && $args[0] eq "this_Device" ) {
        $ret = MSwitch_backup_this($hash);
        return $ret;
    }
####################
    if ( $opt eq 'restore_MSwitch_Data' && $args[0] eq "all_Devices" ) {
        open( BACKUPDATEI, "<MSwitch_backup_$vupdate.cfg" )
          || return "no Backupfile found\n";
        close(BACKUPDATEI);
        $hash->{helper}{RESTORE_ANSWER} = $hash->{CL};
        my $ret = MSwitch_backup_all($hash);
        return $ret;
    }
####################
    if ( $opt eq 'checkevent' ) {
        $ret = MSwitch_Check_Event( $hash, $args[0] );
        return $ret;
    }
####################
    if ( $opt eq 'get_config' ) {
        $ret = MSwitch_Getconfig($hash);
        return $ret;
    }
####################
    if ( $opt eq 'get_sysextension' ) {
        $ret = MSwitch_Sysextension($hash);
        return $ret;
    }
####################

    if ( $opt eq 'checkcondition' ) {
        my ( $condstring, $eventstring ) = split( /\|/, $args[0] );
		$condstring =~ s/#\[dp\]/:/g;
		$condstring =~ s/#\[pt\]/./g;
		$condstring =~ s/#\[ti\]/~/g;
		$condstring =~ s/#\[sp\]/ /g;
		$eventstring =~ s/#\[dp\]/:/g;
		$eventstring =~ s/#\[pt\]/./g;
		$eventstring =~ s/#\[ti\]/~/g;
		$eventstring =~ s/#\[sp\]/ /g;
        $condstring =~ s/\(DAYS\)/|/g;
        my $ret1 = MSwitch_checkcondition( $condstring, $name, $eventstring );
        my $condstring1 = $hash->{helper}{conditioncheck};
        my $errorstring = $hash->{helper}{conditionerror};
        if ( !defined $errorstring ) { $errorstring = '' }
        $condstring1 =~ s/</\&lt\;/g;
        $condstring1 =~ s/>/\&gt\;/g;
        $errorstring =~ s/</\&lt\;/g;
        $errorstring =~ s/>/\&gt\;/g;

        if ( $errorstring ne '' && $condstring1 ne 'Klammerfehler' ) 
		{
            $ret1 =
                '<div style="color: #FF0000">Syntaxfehler:<br>'
              . $errorstring
              . '</div><br>';
        }
        elsif ( $condstring1 eq 'Klammerfehler' ) 
		{
            $ret1 =
'<div style="color: #FF0000">Syntaxfehler:<br>Fehler in der Klammersetzung, die Anzahl öffnender und schliessender Klammern stimmt nicht überein . </div><br>';
        }
        else 
		{
			if ( $ret1 eq 'true' ) 
			{
                $ret1 = 'Bedingung ist Wahr und wird ausgeführt';
            }
            if ( $ret1 eq 'false' ) 
			{
                $ret1 = 'Bedingung ist nicht Wahr und wird nicht ausgeführt';
            }
        }
        $condstring =~ s/~/ /g;
        my $condmarker = $condstring1;
        my $x          = 0;              # exit 
        while ( $condmarker =~ m/(.*)(\d{10})(.*)/ ) 
		{
            $x++;                        # exit 
            last if $x > 20;             # exit 
            my $timestamp = FmtDateTime($2);
            chop $timestamp;
            chop $timestamp;
            chop $timestamp;
            my ( $st1, $st2 ) = split( / /, $timestamp );
            $condmarker = $1 . $st2 . $3;
        }
        $ret ="eingehender String:<br>$condstring<br><br>If Anweisung Perl:<br>$condstring1<br><br>";
        $ret .= "If Anweisung Perl Klarzeiten:<br>$condmarker<br><br>"
		if $x > 0;
        $ret .= $ret1;
		my $condsplit = $condmarker;
		my $reads ='<br><br>States der geprüften Readings:<br>';

		$x          = 0;              # exit 
        while ( $condsplit =~ m/(.*')(.*)',\s'(.*)',\s(.*)/ ) 
		{
		$x++;                        # exit 
        last if $x > 20;             # exit 
		$reads .="Reading: [$2:$3]      -      Inhalt: ".ReadingsVal( $2, $3, 'undef' );
		$reads .="<div style=\"color: #FF0000\">Reading nicht vorhanden !</div>" if (ReadingsVal( $2, $3, 'undef' )) eq "undef";
		$reads .="<br>";
		$condsplit = $1.$4;
		}
		$ret .= $reads if $x > 0;
        my $err1;
        my $err2;
	
        if ( $errorstring ne '' )
		{
            ( $err1, $err2 ) = split( /near /, $errorstring );
            chop $err2;
            chop $err2;
            $err2 = substr( $err2, 1 );
            $ret =~ s/$err2/<span style="color: #FF0000">$err2<\/span>/ig;
        }
        $hash->{helper}{conditioncheck} = '';
        $hash->{helper}{conditionerror} = '';
        return "<span style=\"font-size: medium\">" . $ret . "<\/span>";
    }
    #################################################
    if ( $opt eq 'active_timer' && $args[0] eq 'delete' ) 
	{
        MSwitch_Clear_timer($hash);
        MSwitch_Createtimer($hash);
        MSwitch_Delete_Delay( $hash, 'all' );
        $ret .="<br>INFO: Alle anstehenden Timer wurden neu berechnet, alle Delays wurden gelöscht<br>";
        return $ret;
    }
#################################################
    if ( $opt eq 'active_timer' && $args[0] eq 'show' ) 
	{
	
	    $ret .= "<div nowrap>Systemzeit: ".localtime()."</div><hr>";
        $ret .= "<div nowrap>Schaltzeiten (at - kommandos).</div><hr>";
        #timer
        my $timehash = $hash->{helper}{timer};
        foreach my $a ( sort keys %{$timehash} ) 
		{
            my $time = FmtDateTime( $hash->{helper}{timer}{$a} );
            my @timers = split( /,/, $a );
            if ( substr( $hash->{helper}{timer}{$a}, 11, 1 ) eq '1' ) 
			{
                $ret .=
                    "<div nowrap>"
                  . $time
                  . " switch MSwitch on + execute 'on' cmds</div>";
            }
            if ( substr( $hash->{helper}{timer}{$a}, 11, 1 ) eq '2' ) 
			{
                $ret .=
                    "<div nowrap>"
                  . $time
                  . " switch MSwitch off + execute 'off' cmds</div>";
            }
            if ( substr( $hash->{helper}{timer}{$a}, 11, 1 ) eq '3' ) 
			{
                $ret .=
                  "<div nowrap>" . $time . " execute 'on' commands only</div>";
            }
            if ( substr( $hash->{helper}{timer}{$a}, 11, 1 ) eq '4' ) 
			{
                $ret .=
                  "<div nowrap>" . $time . " execute 'off' commands only</div>";
            }
            if ( substr( $hash->{helper}{timer}{$a}, 11, 1 ) eq '5' ) 
			{
                $ret .=
                    "<div nowrap>"
                  . $time
                  . " neuberechnung aller Schaltzeiten </div>";
            }
        }

        #delays
        $ret .= "<br>&nbsp;<br><div nowrap>aktive Delays:</div><hr>";
        $timehash = $hash->{helper}{delays};
        foreach my $a ( sort keys %{$timehash} ) 
		{
            my $b      = substr( $hash->{helper}{delays}{$a}, 0, 10 );
            my $time   = FmtDateTime($b);
            my @timers = split( /,/, $a );
            $ret .= "<div nowrap>" . $time . " " . $timers[0] . "</div>";
        }
        if ( $ret ne "<div nowrap>Schaltzeiten (at - kommandos).</div><hr><div nowrap>aktive Delays:</div><hr>")
        {
            return $ret;
        }
        return "<span style=\"font-size: medium\">Keine aktiven Delays/Ats gefunden <\/span>";
    }
	
	
	my $extension='';
	if (ReadingsVal( $name, 'Sys_Extension', '')  eq 'on')
	{
	$extension='get_sysextension:noArg';
	}
    return "Unknown argument $opt, choose one of get_config:noArg active_timer:show,delete restore_MSwitch_Data:this_Device,all_Devices $extension";
}

####################
sub MSwitch_AsyncOutput ($) {
    my ( $client_hash, $text ) = @_;
    return $text;
}
####################


sub MSwitch_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    return "" if ( IsDisabled($name) && ($cmd eq 'on' || $cmd eq 'off') );# Return without any further action if the module is disabled
	my $execids = "0";
	
	
	
	
	# verry special commands readingactivated
	my $special='';
	my $cs = ReadingsVal( $name,'.sysconf', 'undef' );
	if ($cs ne "undef")
	{
	$cs =~ s/#\[wa\]/|/g;
	$cs =~ s/#\[sp\]/ /g;
	$cs =~ s/#\[nl\]/\n/g;
	$cs =~ s/#\[se\]/;/g;
	$cs =~ s/#\[dp\]/:/g;
	$cs =~ s/#\[st\]/'/g;
	$cs =~ s/#\[dst\]/\"/g;
	$cs =~ s/#\[tab\]/    /g;
	$cs =~ s/#\[ko\]/,/g;
	$cs =~ s/#.*\n//g;	
	$cs =~ s/\n//g;
	
	my $return ="no value";
	$return = eval($cs);
            if ($@) 
			{
                Log3( $name, 1,"$name MSwitch_repeat: ERROR $cs: $@ " . __LINE__ );
				#MSwitch_LOG( $name, 5,"$name MSwitch_repeat: ERROR $cs: $@ " . __LINE__ );
				
            }
			
		#MSwitch_LOG( $name, 5,"$name MSwitch_repeat: $return" );	
		
		return if $return eq "exit";
	} 
	############################	

	

		
	if (!defined $args[0]) { $args[0]='';}
	if ( $cmd eq 'exec_cmd1' && $args[0] eq 'ID')
	{
	Log3( $name, 5,"$name: execids werden gesetzt -> ".$args[1]  );
	$execids = $args[1];
	$args[0] = 'ID' ;
	}
	
	
	if ( $cmd eq 'exec_cmd2' && $args[0] eq 'ID')
	{
	Log3( $name, 5,"$name: execids werden gesetzt als -> ".$args[1]  );
	$execids = $args[1];
	$args[0] = 'ID' ;
	}
	my $ic ='';
	$ic = $hash->{IncommingHandle};
	#######################################
	if ((($cmd eq 'on') || ($cmd eq 'off')) && ($args[0] ne '') && ($ic ne 'fromnotify'))
	{
	readingsSingleUpdate( $hash, "Parameter", $args[0], 1 );
	if ($cmd eq 'on'){$args[0] = "$name:on_with_Parameter:$args[0]";}
	if ($cmd eq 'off'){$args[0] = "$name:off_with_Parameter:$args[0]";}
	}
	
	delete( $hash->{IncommingHandle} );
	
	
	#######################################
    if ( AttrVal( $name, 'MSwitch_Debug', "0" ) eq '4' ) 
	#AUFRUF DEBUGFUNKTIONEN
	{
        MSwitch_Debug($hash);
    }

    if ( !exists( $sets{$cmd} )) 
	{
        my @cList;
        # Overwrite %sets with setList
        my $atts = AttrVal( $name, 'setList', "" );
        my %setlist = split( "[: ][ ]*", $atts );
        foreach my $k ( sort keys %sets ) 
		{
            my $opts = undef;
            $opts = $sets{$k};
            $opts = $setlist{$k} if ( exists( $setlist{$k} ) );
            if ( defined($opts) ) 
			{
                push( @cList, $k . ':' . $opts );
            }
            else 
			{
                push( @cList, $k );
            }
        }# end foreach
		
		 if ( ReadingsVal( $name, '.change', '' ) ne '' ) 
		{
			return "Unknown argument $cmd, choose one of ";
		}
		
        if ( AttrVal( $name, 'MSwitch_Mode', 'Full' ) eq "Notify" ) 
		{
			return "Unknown argument $cmd, choose one of active:noArg inactive:noArg del_delays:noArg backup_MSwitch:all_devices fakeevent exec_cmd1 exec_cmd2 exec_cmd1+2 wait reload_timer:noArg";
		}
        elsif ( AttrVal( $name, 'MSwitch_Mode', 'Full' ) eq "Toggle" )
		{
			return "Unknown argument $cmd, choose one of on offdel_delays:noArg backup_MSwitch:all_devices fakeevent wait reload_timer:noArg";
		}
        else 
		{
			return "Unknown argument $cmd, choose one of on off  del_delays:noArg backup_MSwitch:all_devices fakeevent exec_cmd1 exec_cmd2 exec_cmd1+2 wait reload_timer:noArg $special";
				
        }
    }

	if ( AttrVal( $name, 'MSwitch_RandomNumber', '' ) ne '' )
	{
		# randomnunner erzeugen wenn attr an
		MSwitch_Createnumber1($hash);
	}	

	
	
#######################################
	if ( $cmd eq 'reload_timer' )
		{
        MSwitch_Clear_timer($hash);
        MSwitch_Createtimer($hash);
				return;
        }
	
#######################################
	if ( $cmd eq 'VUpdate' )
		{
                MSwitch_VUpdate($hash);
				return;
        }
#######################################
	if ( $cmd eq 'confchange' )
		{
                MSwitch_confchange($hash,$args[0]);
				return;
        }
###################################	
	if ( $cmd eq 'clearlog' )
		{
                MSwitch_clearlog($hash);
				return;
        }

##############################
	if ( $cmd eq 'wait' )
		{
  
                 readingsSingleUpdate( $hash, "waiting", ( time + $args[0] ),0 );
				 return;
        }
##############################

    if ( $cmd eq 'inactive' )
	{
	# setze device auf inaktiv
        my $cs = "setstate $name inactive";
        my $errors = AnalyzeCommandChain( undef, $cs );
        if ( defined($errors) ) 
		{
           Log3( $name, 1,"$name MSwitch_Notify: Fehler bei Befehlsausführung $errors -> Comand: $_ " . __LINE__ );
        }
        return;
    }
##############################
    if ( $cmd eq 'aktive' ) 
	{
	# setze device auf aktiv
        my $cs = "setstate $name active";
        my $errors = AnalyzeCommandChain( undef, $cs );
        if ( defined($errors) ) 
		{
            Log3( $name, 1,"$name MSwitch_Notify: Fehler bei Befehlsausführung $errors -> Comand: $_ ". __LINE__ );
        }
    return;
    }
##############################	
	
	if ( $cmd eq 'fakeevent' ) 
	{
	# fakeevent abarbeiten
		MSwitch_Check_Event($hash,$args[0]);
        return;
    }
	
##############################

	if ( $cmd eq 'exec_cmd1' ) 
	{
	# cmd1 abarbeiten	
		MSwitch_Exec_Notif($hash,'on','nocheck','',$execids) ;
        return;
    }
	
##############################	

	if ( $cmd eq 'exec_cmd2' ) 
	{
	# cmd1 abarbeiten
		MSwitch_Exec_Notif($hash,'off','nocheck','',$execids) ;
        return;
    }
	
##############################

    if ( $cmd eq 'backup_MSwitch' ) 
	{
	# backup erstellen
        MSwitch_backup($hash);
        return;
    }
	
##############################

    if ( $cmd eq 'del_delays' ) 
	{
	# löschen aller delays
        MSwitch_Delete_Delay( $hash, $name );
        MSwitch_Createtimer($hash);
        return;
    }
##############################
    if ( $cmd eq 'saveconfig' )
	{
	# configfile speichern
        $args[0] =~ s/\[s\]/ /g;
        MSwitch_saveconf( $hash, $args[0] );
        return;
    }
##############################
    if ( $cmd eq 'savesys' )
	{
	# sysfile speichern
        MSwitch_savesys( $hash, $args[0] );
        return;
    }
##############################

    if ( $cmd eq "addevent" )
	{
	# event manuell zufügen
        my $devName = ReadingsVal( $name, 'Trigger_device', '' );
        $args[0] =~ s/~/ /g;
        my @newevents = split( /,/, $args[0] );
        if ( ReadingsVal( $name, 'Trigger_device', '' ) eq "all_events" ) 
		{
            foreach (@newevents) 
			{
                $hash->{helper}{events}{all_events}{$_} = "on";
            }
        }
        else
		{
            foreach (@newevents)
			{
                $hash->{helper}{events}{$devName}{$_} = "on";
            }
        }
        my $events    = '';
        my $eventhash = $hash->{helper}{events}{$devName};
        foreach my $name ( keys %{$eventhash} ) 
		{
            $events = $events . $name . '#[tr]';
        }
        chop($events);
		chop($events);
		chop($events);
		chop($events);
		chop($events);
        readingsSingleUpdate( $hash, ".Device_Events", $events, 1 );
        return;
    }
##############################
    if ( $cmd eq "add_device" ) 
	{
	#add device
        MSwitch_Add_Device( $hash, $args[0] );
        return;
    }
##############################
    if ( $cmd eq "del_device" ) 
	{
	#del device
        MSwitch_Del_Device( $hash, $args[0] );
        return;
    }
##############################
    if ( $cmd eq "del_trigger" ) 
	{
	#lösche trigger
        MSwitch_Delete_Triggermemory($hash);
        return;
    }
##############################
    if ( $cmd eq "filter_trigger" ) 
	{
	#filter to trigger
        MSwitch_Filter_Trigger($hash);
        return;
    }
##############################
    if ( $cmd eq "set_trigger" ) 
	{
	# setze trigger
        chop( $args[1], $args[2], $args[3], $args[4], $args[5] );
        my $triggertime = 'on'
          . $args[1] . '~off'
          . $args[2]
          . '~ononly'
          . $args[3]
          . '~offonly'
          . $args[4];

        my $oldtrigger = ReadingsVal( $name, 'Trigger_device', '' );
        readingsSingleUpdate( $hash, "Trigger_device",     $args[0], '1' );
        readingsSingleUpdate( $hash, ".Trigger_condition", $args[5], 0 );

        if ( !defined $args[6] ) 
		{
            readingsDelete( $hash, '.Trigger_Whitelist' );
        }
        else 
		{
            readingsSingleUpdate( $hash, ".Trigger_Whitelist", $args[6], 0 );
        }
        my $testtrig = ReadingsVal( $name, 'Trigger_device', '' );
		
        if ( $oldtrigger ne $args[0] ) 
		{
            # lösche alle events
            MSwitch_Delete_Triggermemory($hash);
        }

        if (   $args[1] ne '' || $args[2] ne '' || $args[3] ne '' || $args[4] ne '' )
        {
            readingsSingleUpdate( $hash, ".Trigger_time", $triggertime, 0 );
            MSwitch_Createtimer($hash);
        }
        else 
		{
            readingsSingleUpdate( $hash, ".Trigger_time", '', 0 );
            MSwitch_Clear_timer($hash);
        }
		
        $hash->{helper}{events}{ $args[0] }{'no_trigger'} = "on";

        if ( $args[0] ne 'no_trigger' ) 
		{
            if ( $args[0] eq "all_events" ) 
			{
                delete( $hash->{NOTIFYDEV} );
                if ( ReadingsVal( $name, '.Trigger_Whitelist', '' ) ne '' )
				{
                    $hash->{NOTIFYDEV} =
                      ReadingsVal( $name, '.Trigger_Whitelist', '' );
                }
            }
            else 
			{
                $hash->{NOTIFYDEV} = $args[0];
                my $devices = MSwitch_makeAffected($hash);
                $hash->{DEF} = $args[0] . ' # ' . $devices;
            }
        }
        else 
		{
            $hash->{NOTIFYDEV} = 'no_trigger';
            delete $hash->{DEF};
        }
    return;
    }
##############################
    if ( $cmd eq "trigger" ) 
	{
	# setze trigger events
        my $triggeron     = '';
        my $triggeroff    = '';
        my $triggercmdon  = '';
        my $triggercmdoff = '';
        $args[0] =~ s/~/ /g;
        $args[1] =~ s/~/ /g;
        $args[2] =~ s/~/ /g;
        $args[3] =~ s/~/ /g;
        $args[4] =~ s/~/ /g;
        if ( !defined $args[1] ) { $args[1] = "" }
        if ( !defined $args[3] ) { $args[3] = "" }
        $triggeron  = $args[0];
        $triggeroff = $args[1];
        if ( !defined $args[3] ) { $args[3] = "" }
        if ( !defined $args[4] ) { $args[4] = "" }
        $triggercmdon  = $args[3];
        $triggercmdoff = $args[4];
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, ".Trigger_on",  $triggeron );
        readingsBulkUpdate( $hash, ".Trigger_off", $triggeroff );

        if ( $args[2] eq 'nein' ) 
		{
            readingsBulkUpdate( $hash, "Trigger_log", 'off' );
        }
        if ( $args[2] eq 'ja' )
		{
            readingsBulkUpdate( $hash, "Trigger_log", 'on' );
        }
        readingsBulkUpdate( $hash, ".Trigger_cmd_on",  $triggercmdon );
        readingsBulkUpdate( $hash, ".Trigger_cmd_off", $triggercmdoff );
        readingsEndUpdate( $hash, 0 );
        return;
    }
##############################
    if ( $cmd eq "devices" ) 
	{
	# setze devices
        my $devices = $args[0];
        if ( $devices eq 'null' ) 
		{
            readingsSingleUpdate( $hash, ".Device_Affected", 'no_device', 0 );
            return;
        }
        my @olddevices = split( /,/, ReadingsVal( $name, '.Device_Affected', 'no_device' ) );
        my @devices = split( /,/, $args[0] );
        my $addolddevice = '';
        foreach (@devices) 
		{
            my $testdev = $_;
			LOOP6:foreach my $olddev (@olddevices) {
            my $oldcmd  = '';
            my $oldname = '';
            ( $oldname, $oldcmd ) = split( /-AbsCmd/, $olddev );
            if ( !defined $oldcmd ) { $oldcmd = '' }
			if ( $oldcmd eq '1' ) { next LOOP6 }
            if ( $oldname eq $testdev ) 
				{
                    $addolddevice = $addolddevice . $olddev . ',';
                }
            }
            $_ = $_ . '-AbsCmd1';
        }
        chop($addolddevice);
        $devices = join( ',', @devices ) . ',' . $addolddevice;
        my @sortdevices = split( /,/, $devices );
        @sortdevices = sort @sortdevices;
        $devices = join( ',', @sortdevices );
        readingsSingleUpdate( $hash, ".Device_Affected", $devices, 0 );
        $devices = MSwitch_makeAffected($hash);
        if ( defined $hash->{DEF} ) 
		{
            my $devhash = $hash->{DEF};
            my @dev = split( /#/, $devhash );
            $hash->{DEF} = $dev[0] . ' # ' . $devices;
        }
        else 
		{
            $hash->{DEF} = ' # ' . $devices;
        }
        return;
    }
##############################
    if ( $cmd eq "details" ) 
	{
	# setze devices details
    $args[0] = urlDecode( $args[0] );

        my @devices =split( /,/, ReadingsVal( $name, '.Device_Affected', '' ) );
		my @inputcmds = split( /#\[ND\]/, $args[0] );
		my $counter     = 0;
        my $error       = '';
        my $key         = '';
        my $savedetails = '';
		LOOP10: foreach (@devices)
		{
            if ( $inputcmds[$counter] eq '' ) { next LOOP10; }
			#new 
			my @devicecmds = split( /#\[NF\]/, $inputcmds[$counter] );
			
            $savedetails = $savedetails . $_ . '#[NF]';
            $savedetails = $savedetails . $devicecmds[0] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[1] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[2] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[3] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[4] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[5] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[7] . '#[NF]';
            $savedetails = $savedetails . $devicecmds[6] . '#[NF]';

            if ( defined $devicecmds[8] ) 
			{
                $savedetails = $savedetails . $devicecmds[8] . '#[NF]';
            }
            else 
			{
                $savedetails = $savedetails . '' . '#[NF]';
            }

            if ( defined $devicecmds[9] ) 
			{
                $savedetails = $savedetails . $devicecmds[9] . '#[NF]';
            }
            else 
			{
                $savedetails = $savedetails . '' . '#[NF]';
            }

            if ( defined $devicecmds[10] )
			{
                $savedetails = $savedetails . $devicecmds[10] . '#[NF]';
            }
            else 
			{
                $savedetails = $savedetails . '' . '#[NF]';
            }

			
			if ( defined $devicecmds[11] )
			{
                $savedetails = $savedetails . $devicecmds[11] . '#[NF]';
            }
            else 
			{
                $savedetails = $savedetails . '' . '#[NF]';
            }
			
			
			# priority
            if ( defined $devicecmds[12]  && $devicecmds[12] ne 'undefined')
			{
                $savedetails = $savedetails . $devicecmds[12] . '#[NF]';
            }
            else 
			{
                $savedetails = $savedetails . '1' . '#[NF]';
            }
			
			# id
			 if ( defined $devicecmds[13]  && $devicecmds[13] ne 'undefined')
			{
                $savedetails = $savedetails . $devicecmds[13] . '#[ND]';
            }
            else 
			{
                $savedetails = $savedetails . '0' . '#[ND]';
            }

            $counter++;

        }
        chop($savedetails);
		chop($savedetails);
		chop($savedetails);
		chop($savedetails);
		chop($savedetails);
		
		# ersetzung sonderzeichen etc mscode
		# auskommentierte wurden bereits dur jscript ersetzt
		
		$args[0] = urlDecode( $args[0] );
		$savedetails =~ s/\n/#[nl]/g; 
		$savedetails =~ s/\t/    /g; 
		$savedetails =~ s/ /#[sp]/g; 
		$savedetails =~ s/\\/#[bs]/g; 
		$savedetails =~ s/,/#[ko]/g;
		$savedetails =~ s/^#\[/#[eo]/g;
		$savedetails =~ s/^#\]/#[ec]/g;
		$savedetails =~ s/\|/#[wa]/g;
		$savedetails =~ s/\|/#[ti]/g;
        readingsSingleUpdate( $hash, ".Device_Affected_Details", $savedetails,0 );
        return;
    }


	##################################################################
    my $update = '';

# unbedingt überarbeiten !!!
    my @testdetails = qw(_on _off _onarg _offarg _playback _record _timeon _timeoff _conditionon _conditionoff);
    my @testdetailsstandart =( 'no_action', 'no_action', '', '', 'nein', 'nein', 0, 0, '', '' );
	##################################
	
	#neu ausführung on/off
	if ( $cmd eq "off" || $cmd eq "on") 
	{
	# ausführen des off befehls
	my $zweig = 'nicht definiert';
	$zweig = "cmd1" if $cmd eq "on";
	$zweig = "cmd2" if $cmd eq "off";
	
	MSwitch_Safemode($hash);
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	MSwitch_LOG( $name, 5, "$name: aufruf on/off -> $cmd"  ); 
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	
        my @cmdpool;
        my %devicedetails = MSwitch_makeCmdHash($name);
        my @devices = split( /,/, ReadingsVal( $name, '.Device_Affected', '' ) );
		
		# liste anpassen ( reihenfolge ) wenn expert = 1
		@devices = MSwitch_priority($hash,$execids,@devices);
		
		LOOP1: foreach my $device (@devices) 
		{
		MSwitch_LOG( $name, 5, "$name: angesprochener zweig ".$zweig." -> device -> -".$device."-"  ); 
		# teste auf on kommando
			next LOOP1 if  $device eq "no_device" ;
            my @devicesplit = split( /-AbsCmd/, $device );
            my $devicenamet = $devicesplit[0];
            my $count       = 0;
            foreach my $testset (@testdetails) 
			{
            if ( !defined( $devicedetails{ $device . $testset } ) )
				{
                    my $key = '';
                    $key = $device . $testset;
                    $devicedetails{$key} = $testdetailsstandart[$count];
                }
            $count++;
            }

            my $key      = $device . "_".$cmd;
            my $timerkey = $device . "_time".$cmd;
            my $testtstate = $devicedetails{$timerkey};

			# teste auf delayinhalt
			MSwitch_LOG( $name, 5, "$name: teste auf timerstatus -> $testtstate"  ); 
            $testtstate =~ s/[A-Za-z0-9#\.\-_]//g;
			
			
			
			
			
		       if ( $testtstate eq "[:]" || $testtstate eq "[\$:]") 
		{
		
            $devicedetails{$timerkey} =
            eval MSwitch_Checkcond_state( $devicedetails{$timerkey}, $name );
			
			
			
	if ($devicedetails{$timerkey} =~ m/[0-9]\d:[0-9]\d:[0-9]\d/)
	{
	MSwitch_LOG( $name, 5,"$name:   format ok ");
	
	  my $hdel = ( substr( $devicedetails{$timerkey}, 0, 2 ) ) * 3600;
      my $mdel = ( substr( $devicedetails{$timerkey}, 3, 2 ) ) * 60;
      my $sdel = ( substr( $devicedetails{$timerkey}, 6, 2 ) ) * 1;
      $devicedetails{$timerkey} = $hdel + $mdel + $sdel;
			
			
	}	
	else 
	{
	MSwitch_LOG( $name, 1,"$name: ERROR Timerformat ".$devicedetails{$timerkey}." fehlerhaf ");
	$devicedetails{$timerkey} = 0;
	}
			
			
			
          
        }
			
			
			
			MSwitch_LOG( $name, 5, "$name: timerstatus nach test -> ".$devicedetails{$timerkey}  ); 
			
			# suche befehl
            if (   $devicedetails{$key} ne "" && $devicedetails{$key} ne "no_action" ) #befehl gefunden
            {
				my $cs='';
				$cs ="set $devicenamet $devicedetails{$device.'_off'} $devicedetails{$device.'_offarg'}" if $cmd eq "off";
				$cs ="set $devicenamet $devicedetails{$device.'_on'} $devicedetails{$device.'_onarg'}" if $cmd eq "on";
			
                if ( $devicenamet eq 'FreeCmd' ) 
				{
                    $cs = "$devicedetails{$device.'_'.$cmd.'arg'}";
					$cs = MSwitch_makefreecmd($hash,$cs);
                }
				
			MSwitch_LOG( $name, 5, "$name: befehl gefunden -> ".$cs  ); 
			MSwitch_LOG( $name, 5, "$name: teste auf delay -> ".$devicedetails{$timerkey}  ); 

			my $conditionkey = $device . "_condition".$cmd; 
			
			
			
			
			
			
			
			
			MSwitch_LOG( $name, 5, "$name: TIMERKEY -> ".$devicedetails{$timerkey}  );
			
            if (   $devicedetails{$timerkey} eq "0" || $devicedetails{$timerkey} eq "" )
                {
                   # $conditionkey = $device . "_conditionoff";
					MSwitch_LOG( $name, 5, "$name: teste auf condition -> aufruf sub checkcondition mit ".$devicedetails{$conditionkey}   )if $devicedetails{$conditionkey} ne '';
					MSwitch_LOG( $name, 5, "$name: teste auf condition -> wird nicht getestet - kein eintrag".$devicedetails{$conditionkey}   )if $devicedetails{$conditionkey} eq '';
					my $execute ="true";
                    $execute = MSwitch_checkcondition( $devicedetails{$conditionkey}, $name, $args[0] ) if $devicedetails{$conditionkey} ne '';
					MSwitch_LOG( $name, 5, "$name: ergebniss condition -> ergebniss ".$execute  );
                    if ( $execute eq 'true' ) 
					{
                        $cs =~ s/\$NAME/$hash->{helper}{eventfrom}/;
						$cs =~ s/\$SELF/$name/;
						MSwitch_LOG( $name, 5, "$name: in exec-cmdpool geschrieben ->".$cs  );
                        push @cmdpool, $cs . '|' . $device;
                        $update = $device . ',' . $update;
                    }
                }
            else
				{
				MSwitch_LOG( $name, 5, "$name: teste auf condition -> keine vorhanden " );
				
                    if ( AttrVal( $name, 'MSwitch_RandomTime', '' ) ne '' && $devicedetails{$timerkey} eq '[random]' )
                    {
						MSwitch_LOG( $name, 5, "$name: randomtimer gefunden attr gesetzt -> ".$devicedetails{$timerkey} );
                        $devicedetails{$timerkey} =MSwitch_Execute_randomtimer($hash);
                        # ersetzt $devicedetails{$timerkey} gegen randomtimer
						MSwitch_LOG( $name, 5, "$name: timerd ersetzt-> ".$devicedetails{$timerkey} );
                    }
                    elsif ( AttrVal( $name, 'MSwitch_RandomTime', '' ) eq '' && $devicedetails{$timerkey} eq '[random]' )
                    {
					MSwitch_LOG( $name, 5, "$name: randomtimer gefunden attr nicht gesetzt -> 0" );
                        $devicedetails{$timerkey} = 0;
                    }
					
					# ?				
					my $execute ="true";
					# conditiontest nur dann, wenn cond-test nicht nur nach verzögerung
					if ($devicedetails{$device . "_delayat".$cmd} ne "delay2" && $devicedetails{$device . "_delayat".$cmd} ne "at02")
					{
					MSwitch_LOG( $name, 5, "$name: checkcondition bei gefundem delay -> ".$devicedetails{$device . "_delayat".$cmd} );
					$execute = MSwitch_checkcondition( $devicedetails{$conditionkey},$name, $args[0] ) ;
					MSwitch_LOG( $name, 5, "$name: ergebniss checkcondition für delay-> ".$execute );
					}
					MSwitch_LOG( $name, 5,"$name: ----------------- Delay -> ".$devicedetails{$timerkey} );

                    if ( $execute eq 'true' ) 
					{
                        MSwitch_LOG( $name, 5,"$name: conidtion ok - Befehl mt at/delay wird ausgefuehrt -> ".$cs );
                        my $delaykey    = $device . "_delayat".$cmd;
                        my $delayinhalt = $devicedetails{$delaykey};
                        my $delaykey1    = $device . "_delayat".$cmd."org";
                        my $teststateorg = $devicedetails{$delaykey1};
						MSwitch_LOG( $name, 5,"$name: delaykey -> ".$delaykey );
						MSwitch_LOG( $name, 5,"$name: delaykeyinhalt -> ".$delayinhalt);
						MSwitch_LOG( $name, 5,"$name: delaykeyinhaltorg -> ".$teststateorg  );
                        if ( $delayinhalt eq 'at0' || $delayinhalt eq 'at1' ) 
						{
						MSwitch_LOG( $name, 5,"$name: delay mit at erkannt -> ".$devicedetails{$timerkey} );
						MSwitch_LOG( $name, 5,"$name: delay wird ersetzt " );
                        $devicedetails{$timerkey} = MSwitch_replace_delay( $hash, $teststateorg );
						Log3( $name, 5,"$name: delay ersetzt -> ".$devicedetails{$timerkey} );	
                        }

                        if ( $delayinhalt eq 'at1' || $delayinhalt eq 'delay0' )
                        {
						MSwitch_LOG( $name, 5,"$name: delay ohne zusatzprüfung erkannt -> ".$delayinhalt );
                        $conditionkey = 'nocheck';
						MSwitch_LOG( $name, 5,"$name: conditionkey ersetzt -> ".$conditionkey );
                        }

						my $timecond = gettimeofday() + $devicedetails{$timerkey};
                        my $msg =
                            $cs . "#[tr]"
                          . $name . "#[tr]"
                          . $conditionkey . "#[tr]#[tr]"
                          . $timecond . "#[tr]"
                          . $device;

                        # variabelersetzung
                        $msg =~ s/\$NAME/$hash->{helper}{eventfrom}/;
						$msg =~ s/\$SELF/$name/;
                        $hash->{helper}{delays}{$msg} = $timecond;
                        InternalTimer( $timecond, "MSwitch_Restartcmd", $msg );
						MSwitch_LOG( $name, 5,"$name: verzögerte befehl gesetzt -> ".$timecond." : ".$msg );
						
                    }
                }
            }
        }

        if ( AttrVal( $name, 'MSwitch_Mode', 'Full' ) ne "Notify" ) 
		{
            readingsSingleUpdate( $hash, "state", $cmd, 1 );
        }
        else 
		{
            readingsSingleUpdate( $hash, "state", 'active', 1 );
        }
		
		MSwitch_EventBulk($hash,$args[0],'0');
		my $anzahl = @cmdpool;
		MSwitch_LOG( $name, 5,"$name: anzahl der auszufuehrenden befehle -> ".$anzahl );
		MSwitch_LOG( $name, 5,"$name: uebergabe an sub execute " ) if $anzahl > 0;
        MSwitch_Cmd( $hash, @cmdpool ) if $anzahl > 0;
        return;
    }
    return;
}
###################################

sub MSwitch_Cmd(@) {

    my ( $hash, @cmdpool ) = @_;
    my $Name = $hash->{NAME};

    my %devicedetails = MSwitch_makeCmdHash($Name);
    foreach my $cmds (@cmdpool) 
	{
	MSwitch_LOG( $Name, 5,"$Name:     execute -> ".$cmds );
        my @cut = split( /\|/, $cmds );
        $cmds = $cut[0];
		
		# ersetze platzhakter vor ausführung
		#change		# $cmds =~ s/#\[wa\]/|/g; #neu
		
        my $device = $cut[1];
        my $toggle = '';
        if ( $cmds =~ m/set (.*)(MSwitchtoggle)(.*)/ )
		{
			MSwitch_LOG( $Name, 5,"$Name:     togglemode erkannt -> ".$cmds );
            $toggle = $cmds;
            $cmds = MSwitch_toggle( $hash, $cmds );
        }

		if (   AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' && $devicedetails{ $device . '_repeatcount' } ne '')
		{
			MSwitch_LOG( $Name, 5,"$Name:     teste auf repeatcount -> ".$devicedetails{ $device . '_repeatcount' } );
			my $x =0;
			
				while ( $devicedetails{ $device . '_repeatcount' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # exit
					last if $x > 20;             # exitg
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeatcount' } = $setmagic
					}
			MSwitch_LOG( $Name, 5,"$Name:     repeatcount nach setmagicersetzung -> ".$devicedetails{ $device . '_repeatcount' } );
		}

		if (   AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' && $devicedetails{ $device . '_repeattime' }  ne '')
		{
		
			MSwitch_LOG( $Name, 5,"$Name:     teste auf repeattime -> ".$devicedetails{ $device . '_repeattime' } );
			my $x =0;
			
				while ( $devicedetails{ $device . '_repeattime' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # exit
					last if $x > 20;             # exitg
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeattime' } = $setmagic
					}
			MSwitch_LOG( $Name, 5,"$Name:     _repeattime nach setmagicersetzung -> ".$devicedetails{ $device . '_repeattime' }  );
		
		}
		
		if (   AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1'&& $devicedetails{ $device . '_repeatcount' } > 0 && $devicedetails{ $device . '_repeattime' } > 0 )
        {

            my $i;
            for ( $i = 0; $i <= $devicedetails{ $device . '_repeatcount' };$i++)
            {
                my $msg = $cmds . "|" . $Name;
                if ( $toggle ne '' ) 
				{
					$msg = $toggle . "|" . $Name;
                }
				my $timecond = gettimeofday()+(($i+1)*$devicedetails{ $device . '_repeattime' } );
				$msg = $msg."|".$timecond;
				$hash->{helper}{repeats}{$timecond} = "$msg";
				
				MSwitch_LOG( $Name, 5,"$Name:     repeat gesetzt -> ".$timecond." : ".$msg );
                InternalTimer( $timecond, "MSwitch_repeat", $msg );
            }
        }

		my $todec = $cmds;
		$cmds = MSwitch_dec($hash,$todec);
		MSwitch_LOG( $Name, 5,"$Name:     cmd nach decodierung -> ".$cmds );			
		
        ############################
		
		# debug2 mode , kein execute
		if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '2' )
		{
		MSwitch_LOG( $Name, 5,"$Name:     exec comand -> ".$cmds );
		}
		else
		{
        if ( $cmds =~ m/{.*}/ ) 
		{
		MSwitch_LOG( $Name, 5,"$Name:     exec als perlcode -> ".$cmds );
        
            eval($cmds);
            if ($@) 
			{
                MSwitch_LOG( $Name, 1,"$Name MSwitch_Set: ERROR $cmds: $@ " . __LINE__ );
            }
        }
        else
		{
			MSwitch_LOG( $Name, 5,"$Name:     execute als fhemcode -> ".$cmds );
            my $errors = AnalyzeCommandChain( undef, $cmds );
            if ( defined($errors) )
			{
                MSwitch_LOG( $Name, 1, "$Name MSwitch_Set: ERROR $cmds: $errors " . __LINE__ );
            }
        }
		}
        #############################
    }
    my $showpool = join( ',', @cmdpool );

	if (length($showpool) > 100 ){ $showpool = substr($showpool,0,100).'....';}
    readingsSingleUpdate( $hash, "Exec_cmd", $showpool, 1 ) if $showpool ne '';
}
####################

sub MSwitch_toggle($$) {

    my ( $hash, $cmds ) = @_;
    my $Name = $hash->{NAME};
    $cmds =~ m/(set) (.*)( )MSwitchtoggle (.*)/;
    my @tcmd = split( /\//, $4 );
    if ( !defined $tcmd[2] ) { $tcmd[2] = 'state' }
    if ( !defined $tcmd[3] ) { $tcmd[3] = $tcmd[0] }
    if ( !defined $tcmd[4] ) { $tcmd[4] = $tcmd[1] }
    my $cmd1 = $1 . " " . $2 . " " . $tcmd[0];
    my $cmd2 = $1 . " " . $2 . " " . $tcmd[1];
    my $chk1 = $tcmd[0];
    my $chk2 = $tcmd[1];
    my $testnew = ReadingsVal( $2, $tcmd[2], 'undef' );
    if ( $testnew =~ m/$tcmd[3]/ ) 
	{
        $cmds = $cmd2;
    }
    elsif ( $testnew =~ m/$tcmd[4]/ ) 
	{
        $cmds = $cmd1;
    }
    else
	{
        $cmds = $cmd1;
    }
    return $cmds;
}

##############################

sub MSwitch_Attr(@) {
    my ( $cmd, $name, $aName, $aVal ) = @_;
    my $hash = $defs{$name};
    if ( $aName eq 'MSwitch_Debug' && ( $aVal == 0 || $aVal == 1 || $aVal == 2 || $aVal == 3 ) ) 
	{
        delete( $hash->{READINGS}{Device_Affected} );
        delete( $hash->{READINGS}{Device_Affected_Details} );
        delete( $hash->{READINGS}{Device_Events} );
    }

    if ( $aName eq 'MSwitch_RandomTime' && $aVal ne '' ) 
	{
        if ( $aVal !~ m/([0-9]{2}:[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}:[0-9]{2})/ )
        {
            return 'wrong syntax !<br>the syntax must be: HH:MM:SS-HH:MM:SS';
        }
        else 
		{
            $aVal =~ s/\://g;
            my @test = split( /-/, $aVal );
            if ( $test[0] >= $test[1] )
			{
                return'fist '. $test[0]. ' parameter must be lower than second parameter '. $test[1];
            }
        }
        return;
    }

    if ( $cmd eq 'set' && $aName eq 'disable' && $aVal == 1 ) 
	{
        $hash->{NOTIFYDEV} = 'no_trigger';
		MSwitch_Delete_Delay($hash,'all');
		MSwitch_Clear_timer($hash);
    }
	
	
	if (   $cmd eq 'set' && $aName eq 'disable' && $aVal == 0 )
    {
		delete( $hash->{helper}{savemodeblock} );
		delete( $hash->{READINGS}{Safemode} );
		MSwitch_Createtimer($hash);
	}
	

    if ($cmd eq 'set'&& $aName eq 'disable'&& $aVal == 0 && ReadingsVal($name, 'Trigger_device', 'no_trigger') ne'no_trigger' )
    {
        $hash->{NOTIFYDEV} =
        ReadingsVal( $name, 'Trigger_device', 'no_trigger' );
    }
	
    if ($cmd eq 'del'&& $aName eq 'disable'&& ReadingsVal($name, 'Trigger_device', 'no_trigger') ne 'no_trigger' )
    {
        $hash->{NOTIFYDEV} =
        ReadingsVal( $name, 'Trigger_device', 'no_trigger' );
    }

    if ($aName eq 'MSwitch_Activate_MSwitchcmds' && $aVal == 1 ) 
	{
        addToAttrList('MSwitchcmd');
    }
	
	
	
	
	if ($aName eq 'MSwitch_Debug' && $aVal eq '0' ) 
	{
       unlink ("./log/MSwitch_debug_$name.log") ;
    }
	
	if ($aName eq 'MSwitch_Debug' && $aVal eq '2' || $aVal eq '3'  ) 
	{
       MSwitch_clearlog($hash);
    }

    if ( $cmd eq 'set' && $aName eq 'MSwitch_Inforoom' ) 
	{
        my $testarg = $aVal;
        foreach my $testdevices ( keys %{ $modules{MSwitch}{defptr} } )
        {
            $attr{$testdevices}{MSwitch_Inforoom} = $testarg;
        }
    }

    if ( $aName eq 'MSwitch_Mode' && ( $aVal eq 'Full' || $aVal eq 'Toggle' ) )
    {
        my $cs = "setstate $name ???";
        my $errors = AnalyzeCommandChain( undef, $cs );
    }

    if ( $aName eq 'MSwitch_Mode' && $aVal eq 'Notify' ) 
	{
        readingsSingleUpdate( $hash, "state", 'active', 1 );
        my $cs = "setstate $name active";
        my $errors = AnalyzeCommandChain( undef, $cs );
        if ( defined($errors) ) 
		{
            Log3( $name, 1,"$name MSwitch_Notify: Fehler bei Befehlsausführung $errors -> Comand: $_ ". __LINE__ );
        }

    }

#############

    if ( $cmd eq 'del' ) 
	{
        my $testarg = $aName;
        my $errors;
        if ( $testarg eq 'MSwitch_Inforoom' ) 
		{
			LOOP21:
            foreach my $testdevices ( keys %{ $modules{MSwitch}{defptr} } )
            {
                if ( $testdevices eq $name ) { next LOOP21; }
                delete( $attr{$testdevices}{MSwitch_Inforoom} );
            }
        }
		
		 if ( $testarg eq 'disable' ) 
		 {
				MSwitch_Delete_Delay($hash, "all");
				MSwitch_Clear_timer($hash);
				delete( $hash->{helper}{savemodeblock} );
				delete( $hash->{READINGS}{Safemode} );
		}
    }
return undef;
}
####################
sub MSwitch_Delete($$) {
    my ( $hash, $name ) = @_;
    RemoveInternalTimer($hash);
    return undef;
}
####################
sub MSwitch_Undef($$) {
    my ( $hash, $name ) = @_;
    RemoveInternalTimer($hash);
    delete( $modules{MSwitch}{defptr}{$name} );
    return undef;
}
#################### 


sub MSwitch_Notify($$) {
    my $testtoggle = '';
    my ( $own_hash, $dev_hash ) = @_;
    my $ownName = $own_hash->{NAME};    # own name / hash
	my $devName = $dev_hash->{NAME};
	my $events = deviceEvents( $dev_hash, 1 );
	my $trigevent='';

	my $execids = "0";
	
	
# nur abfragen für eigenes Notify 	
										if ($init_done && $devName eq "global" && grep( m/^MODIFIED $ownName$/, @{$events} ) )
										{
										# reaktion auf eigenes notify start / define / modify
											#Log3( $ownName, 5, 'FOUND MODIFIED' );
											my $timecond = gettimeofday() + 5;
											InternalTimer( $timecond, "MSwitch_LoadHelper", $own_hash);
										#	return;
										}

										if ($init_done && $devName eq "global" && grep( m/^DEFINED $ownName$/, @{$events} ) )
										{
										# reaktion auf eigenes notify start / define / modify
											#Log3( $ownName, 5, 'FOUND DEFINED' );
											#MSwitch_LoadHelper($own_hash);
											my $timecond = gettimeofday() + 5;
											InternalTimer( $timecond, "MSwitch_LoadHelper", $own_hash);
										#	return;
										}
										
										if ( $devName eq "global" && grep( m/^INITIALIZED|REREADCFG$/, @{$events} ) )
										{
										# reaktion auf eigenes notify start / define / modify
											#Log3( $ownName, 5, 'FOUND INITIALIZED|REREADCF' );
											MSwitch_LoadHelper($own_hash);
										#	return;
										}
                                        # nur abfragen für eigenes Notify ENDE
	return "" if ( IsDisabled($ownName) );# Return without any further action if the module is disabled
	# startverzöferung abwarten
	my $startdelay = AttrVal( $ownName, 'MSwitch_Startdelay', $standartstartdelay );
	my $diff = int(time) -  $fhem_started;
	if  ($diff  < $startdelay)
	{
	
	MSwitch_LOG( $ownName, 4, 'Anfrage fuer '.$ownName.' blockiert - Zeit seit start:'. $diff );
	return;
	}
	
	# safemode testen
    MSwitch_Safemode($own_hash);

	MSwitch_LOG( $ownName, 5, "----------------------------------------"  );
	MSwitch_LOG( $ownName, 5, "$ownName: eingehendes Event von -> ".$devName  ); 
	MSwitch_LOG( $ownName, 5, "----------------------------------------"  );
	
	# versionscheck
	if ( ReadingsVal( $ownName, '.V_Check', $vupdate ) ne $vupdate )
	{
	my $ver = ReadingsVal( $ownName, '.V_Check', '' );
	MSwitch_LOG( $ownName, 4, $ownName.' Versionskonflikt, aktion abgebrochen !  erwartet:'.$vupdate.' vorhanden:'.$ver );
	return;
	}

	if ( AttrVal( $ownName, 'MSwitch_RandomNumber', '' ) ne '' ) 
	{
	# create randomnumber wenn attr an
		MSwitch_Createnumber1($own_hash);
	}

    if ( ReadingsVal( $ownName, "waiting", '0' ) > time ) 
	{
	MSwitch_LOG( $ownName, 5, '$ownName: Aktion abgebrochen - wait gesetzt ->'. ReadingsVal( $ownName, "waiting", '0'));
	# teste auf attr waiting verlesse wenn gesetzt
        return "";
    }
    else 
	{
	# reading löschen
        delete( $own_hash->{READINGS}{waiting} );
    }

    my $incommingdevice = '';
    if ( defined( $own_hash->{helper}{testevent_device} ) ) 
	{
	# unklar
        $events          = 'x';
        $incommingdevice = ( $own_hash->{helper}{testevent_device} );
    }
    else
	{
        $incommingdevice = $dev_hash->{NAME};    # aufrufendes device
    }
    
    return if ( !$events );

	my $triggerdevice = ReadingsVal( $ownName, 'Trigger_device', '' );# Triggerdevice
	
	my @cmdarray;
    my @cmdarray1;# enthält auszuführende befehle nach conditiontest
	
########### ggf. löschen
    my $triggeron     = ReadingsVal( $ownName, '.Trigger_on',      '' );
    my $triggeroff    = ReadingsVal( $ownName, '.Trigger_off',     '' );
    my $triggercmdon  = ReadingsVal( $ownName, '.Trigger_cmd_on',  '' );
    my $triggercmdoff = ReadingsVal( $ownName, '.Trigger_cmd_off', '' );

    if ( AttrVal( $ownName, 'MSwitch_Mode', 'Full' ) eq "Notify" ) 
	{
	# passt triggerfelder an attr an
        $triggeron  = 'no_trigger';
        $triggeroff = 'no_trigger';
    }

    if ( AttrVal( $ownName, 'MSwitch_Mode', 'Full' ) eq "Toggle" ) 
	{
	# passt triggerfelder an attr an
        $triggeroff    = 'no_trigger';
        $triggercmdon  = 'no_trigger';
        $triggercmdoff = 'no_trigger';
    }

    my $set        = "noset";
    my $eventcopy  = "";

    # notify für eigenes device
    my $devcopyname = $devName;
    $own_hash->{helper}{eventfrom} = $devName;
	
    my @eventscopy;
    if ( defined( $own_hash->{helper}{testevent_event} ) ) 
	{
	# unklar
    # wenn global , sonst ohne 1
        @eventscopy = "$own_hash->{helper}{testevent_event}";
    }
    else 
	{
        @eventscopy = ( @{$events} );
    }

	my $triggerlog = ReadingsVal( $ownName, 'Trigger_log', 'off' );
    if (   $incommingdevice eq $triggerdevice || $triggerdevice eq "all_events" ) 
    {
        # teste auf triggertreffer oder GLOBAL trigger
		my $activecount = 0;
		my $anzahl  ;
		EVENT: foreach my $event (@eventscopy)
        {
		
		MSwitch_LOG( $ownName, 5, "$ownName: eingehendes Event -> ".$incommingdevice." ".$event );
		
		# durchlauf für jedes ankommende event
		#
            $event = "" if ( !defined($event) );
			
            $eventcopy = $event;
            $eventcopy =~ s/: /:/s;    # BUG  !!!!!!!!!!!!!!!!!!!!!!!!
			
            if ( $triggerlog eq 'on' )
			{
			# wird nur ausgefüht wenn ankommende events gelogd werden
                my @filters =split( /,/, AttrVal( $ownName, 'MSwitch_Trigger_Filter', '' ));# beinhaltet filter durch komma getrennt
                foreach my $filter (@filters) 
				{
                    my $wildcarttest = index( $filter, "*", 0 );
                    if ( $wildcarttest > -1 )    ### filter auf wildcart
                    {
                        $filter = substr( $filter, 0, $wildcarttest );
                        my $testwildcart = index( $eventcopy, $filter, 0 );
                        if ( $testwildcart eq '0' ) { next EVENT; }
                    }
                    else ### filter genauen ausdruck
                    {
                        if ( $eventcopy eq $filter ) { next EVENT; }
                    }
                }

                if ( $triggerdevice eq "all_events" ) 
				{
                    $own_hash->{helper}{events}{'all_events'}{ $devName . ':' . $eventcopy } = "on";
                }
                else 
				{
                    $own_hash->{helper}{events}{$devName}{$eventcopy} = "on";
                }
            }
			
            my $eventcopy1 = $eventcopy;
			
            if ( $triggerdevice eq "all_events" ) 
			{
			# fügt dem event den devicenamen hinzu , wenn global getriggert wird
                $eventcopy1 = "$devName:$eventcopy";
            }

            my $direktswitch = 0;
            my @eventsplit   = split( /\:/, $eventcopy );
            my $eventstellen = @eventsplit;
			my $testvar = '';
			my $check=0;
			
			
			#test auf zweige cmd1/2 and switch MSwitch on/off
					if ( $triggeron ne 'no_trigger' )
					{
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger trigger cmd1 -> " );
					$testvar = MSwitch_checktrigger( $own_hash, $ownName, $eventstellen,$triggeron, $incommingdevice, 'on',$eventcopy,@eventsplit );
						
						if( $testvar ne 'undef')
						{
							$set = $testvar ;
							$check=1;
							$trigevent = $eventcopy;
						}
						
						MSwitch_LOG( $ownName, 5, "$ownName: checktrigger ergebniss -> ".$testvar );
					}

					if ( $triggeroff ne 'no_trigger' ) 
					{
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger trigger cmd2 -> " );
					$testvar = MSwitch_checktrigger( $own_hash, $ownName, $eventstellen,$triggeroff, $incommingdevice, 'off',$eventcopy, @eventsplit );			
						if ($testvar ne 'undef')
						{
							$set = $testvar ;
							$check=1;
							$trigevent = $eventcopy;
						}
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger ergebniss -> ".$testvar );		
					}
				
			#test auf zweige cmd1/2 and switch MSwitch on/off ENDE
			
			#test auf zweige cmd1/2 only 
			# ergebnisse werden in  @cmdarray geschrieben
					if ( $triggercmdoff ne 'no_trigger' )
					{
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger trigger cmd4 -> " );
					$testvar = MSwitch_checktrigger( $own_hash, $ownName, $eventstellen,$triggercmdoff, $incommingdevice, 'offonly', $eventcopy, @eventsplit );
						if ($testvar ne 'undef')
						{
						   push @cmdarray, $own_hash . ',off,check,' . $eventcopy1;
						   $check=1;
						}
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger ergebniss -> ".$testvar );	  
					}
					
					if ( $triggercmdon ne 'no_trigger' )
					{
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger trigger cmd4 -> " );
					$testvar = MSwitch_checktrigger( $own_hash, $ownName, $eventstellen,$triggercmdon, $incommingdevice, 'ononly', $eventcopy, @eventsplit );
						if ( $testvar ne 'undef')
						{
							push @cmdarray, $own_hash . ',on,check,' . $eventcopy1;
							$check=1;
						} 
					MSwitch_LOG( $ownName, 5, "$ownName: checktrigger ergebniss -> ".$testvar );						
					}
		#test auf zweige cmd1/2 only ENDE
		
        $anzahl = @cmdarray;
		MSwitch_LOG( $ownName, 5, "$ownName: anzahl gefundener Befehle -> ".$anzahl );
		MSwitch_LOG( $ownName, 5, "$ownName: inhalt gefundener Befehle -> ".@cmdarray );
		$own_hash->{IncommingHandle}='fromnotify';
		$event =~ s/ //ig;		#?
		$event =~ s/~/ /g;		#?	
			if ( AttrVal( $ownName, 'MSwitch_Mode', 'Full' ) eq "Notify" and $activecount == 0 ) 
				{
				# reading activity aktualisieren
					readingsSingleUpdate( $own_hash, "state", 'active', 1 );
					$activecount = 1;
				}  
			 
			#Readings aktualisieren, wenn gleiches event nicht schom gesetzt	
			if (ReadingsVal( $ownName, 'last_event', '' ) ne $event && $event ne '' && $anzahl > 0 && $check ==1 && $anzahl > 0)
			{	
			MSwitch_EventBulk($own_hash ,$event ,'0')
			} 

		# abfrage und setzten von blocking
		# schalte blocking an , wenn anzahl grösser 0 und MSwitch_Wait gesetzt
            my $mswait = $attr{$ownName}{MSwitch_Wait};
            if ( !defined $mswait ) { $mswait = '0'; }
            if ( $anzahl > 0 && $mswait > 0 ) 
			{
                readingsSingleUpdate( $own_hash, "waiting", ( time + $mswait ),0 );
            }
		# abfrage und setzten von blocking ENDE
			
            if ( AttrVal( $ownName, 'MSwitch_Mode', 'Full' ) eq "Toggle" && $set eq 'on' )
            {# umschalten des devices nur im togglemode
			
                my $cmd = '';
                my $statetest = ReadingsVal( $ownName, 'state', 'on' );
                $cmd = "set $ownName off" if $statetest eq 'on';
                $cmd = "set $ownName on"  if $statetest eq 'off';
				
				 MSwitch_LOG( $ownName, 5, "$ownName: togglemode execute -> ".$cmd);
				
				if ( AttrVal( $ownName, 'MSwitch_Debug', "0" ) ne '2' )
					{
					my $errors = AnalyzeCommandChain( undef, $cmd );
					if ( defined($errors) )
					{
						MSwitch_LOG( $ownName, 1,"$ownName MSwitch_Notify: Fehler bei Befehlsausführung $errors -> Comand: $_ " . __LINE__ );
					}
				}
                return;
            }
		}	
			
#ausführen aller cmds in @cmdarray nach triggertest aber vor conditiontest
#my @cmdarray1;	#enthält auszuführende befehle nach conditiontest
#schaltet zweig 3 und 4
	
            if ( $anzahl != 0 )
			{
		    MSwitch_LOG( $ownName, 5, "$ownName: abarbeiten aller befehle aus eventprüfung ");
			#aberabeite aller befehlssätze in cmdarray
				MSwitch_Safemode($own_hash);
				LOOP31: foreach (@cmdarray)
				{
				MSwitch_LOG( $ownName, 5, "$ownName: Befehl -> ".$_);

                    if ( $_ eq 'undef' ) { next LOOP31; }
                    my ( $ar1, $ar2, $ar3, $ar4 ) = split( /,/, $_ );
					if ( !defined $ar2 ) { $ar2 =''; }
                    if ( $ar2 eq '' )    { next LOOP31; }
                    my $returncmd = 'undef';
					
					#MSwitch_LOG( $ownName, 0,"$ownName: aufruf execnotif  $_ $ar2, $ar3, $ar4 ");
                    $returncmd = MSwitch_Exec_Notif( $own_hash, $ar2, $ar3, $ar4,$execids );
					#MSwitch_LOG( $ownName, 0,"$ownName: ergebniss execnotif -> ".$returncmd);
					
                    if ( defined $returncmd && $returncmd ne 'undef' ) 
					{
					# datensatz nur in cmdarray1 übernehme wenn 
                        chop $returncmd;    #CHANGE
						MSwitch_LOG( $ownName, 5,"$ownName: ergebniss execnotif datensatz to array -> ".$returncmd);
                        push( @cmdarray1, $returncmd );
                    }
                }
				
                my $befehlssatz = join( ',', @cmdarray1 );
				
                foreach ( split( /,/, $befehlssatz ) ) 
				{
                    my $ecec = $_;
                    if ( !$ecec =~ m/set (.*)(MSwitchtoggle)(.*)/ ) 
					{
						if ( AttrVal( $ownName, 'MSwitch_RandomNumber', '' ) ne '' ) 
						{
							MSwitch_Createnumber($own_hash);
						}
						MSwitch_LOG( $ownName, 5,"$ownName: Befehlsausfuehrung -> ".$ecec);
                       
					   
					  if ( AttrVal( $ownName, 'MSwitch_Debug', "0" ) ne '2' )
						{
					   
							my $errors = AnalyzeCommandChain( undef, $_ );
						
							if ( defined($errors) ) 
								{
								MSwitch_LOG( $ownName, 1,"$ownName MSwitch_Notify: Fehler bei Befehlsausführung $errors -> Comand: $_ ". __LINE__ );
								}
						}		
						if (length($ecec) > 100 ){ $ecec = substr($ecec,0,100).'....';}
                        readingsSingleUpdate( $own_hash, "Exec_cmd", $ecec, 1 ) if $ecec ne '';
					}
                    else 
					{
                    }
                }
            }
        # ende loopeinzeleventtest
        # schreibe gruppe mit events
        my $events    = '';
        my $eventhash = $own_hash->{helper}{events}{$devName};
        if ( $triggerdevice eq "all_events" ) 
		{
            $eventhash = $own_hash->{helper}{events}{all_events};
        }
        else
		{
            $eventhash = $own_hash->{helper}{events}{$devName};
        }
		
        foreach my $name ( keys %{$eventhash} )
		{
		
            $events = $events . $name . '#[tr]';
        }
        chop($events);
		chop($events);
		chop($events);
		chop($events);
		chop($events);
        if ( $events ne "" ) 
		{
            readingsSingleUpdate( $own_hash, ".Device_Events", $events, 1 );
        }
		# schreiben ende
        # schalte modul an/aus bei entsprechendem notify
        # teste auf condition
		
		return if $set eq 'noset';# keine MSwitch on/off incl cmd1/2 gefunden

		# Teste auf einhaltung Triggercondition für ausführung zweig 1 und zweig 2
		# kann ggf an den anfang der routine gesetzt werden ? test erforderlich 
		my $triggercondition =ReadingsVal( $ownName, '.Trigger_condition', '' );
		$triggercondition =~ s/#\[dp\]/:/g;
		$triggercondition =~ s/#\[pt\]/./g;
		$triggercondition =~ s/#\[ti\]/~/g;
		$triggercondition =~ s/#\[sp\]/ /g;
		
        if ( $triggercondition ne '') 
		{
			MSwitch_LOG( $ownName, 5,"$ownName: teste Triggercondition -> ".$triggercondition);
            my $ret =MSwitch_checkcondition( $triggercondition, $ownName, $eventcopy );
			MSwitch_LOG( $ownName, 5,"$ownName: ergebniss Triggercondition -> ".$ret);
            if ( $ret eq 'false' ) 
			{
			MSwitch_LOG( $ownName, 5,"$ownName: ergebniss Triggercondition false-> abbruch");
                return;
            }
        }
		# Teste auf einhaltung Triggercondition ENDE
		# schaltet zweig 1 und 2 , wenn $set befehl enthält , es wird nur MSwitch geschaltet, Devices werden dann 'mitgerissen'
			my $cs;
			if ( $triggerdevice eq "all_events" ) 
			{
				$cs = "set $ownName $set $devName:$trigevent";
			}
			else 
			{
				$cs = "set $ownName $set $trigevent";
			}

            MSwitch_LOG( $ownName, 3,"$ownName MSwitch_Notif: Befehlsausfuehrung -> $cs " . __LINE__ );
            # variabelersetzung
            $cs =~ s/\$NAME/$own_hash->{helper}{eventfrom}/;
			$cs =~ s/\$SELF/$ownName/;
			if ( AttrVal( $ownName, 'MSwitch_RandomNumber', '' ) ne '' ) 
			{
				MSwitch_Createnumber($own_hash);
			}
			MSwitch_LOG( $ownName, 5,"$ownName: Befehlsausführung -> ".$cs);
			if ( AttrVal( $ownName, 'MSwitch_Debug', "0" ) ne '2' )
			{
            my $errors = AnalyzeCommandChain( undef, $cs );
			}
			
        return;
    }
}
#########################


sub MSwitch_fhemwebFn($$$$) {

    #  my $loglevel = 5;
    my ( $FW_wname, $d, $room, $pageHash ) =
      @_;    # pageHash is set for summaryFn.
    my $hash     = $defs{$d};
    my $Name     = $hash->{NAME};
    my $jsvarset = '';
    my $j1       = '';
	my $border =0;
	
	
	#Log3( $Name, 0,"hash ---> $hash " . __LINE__ );
	#Log3( $Name, 0,"name ---> $Name " . __LINE__ );
	
	
	if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '4' )
	{
		$border =1;
	}
	
	#versetzen nach ATTR
	if ( AttrVal( $Name, 'MSwitch_RandomNumber', '' ) eq '' )
    {
		delete( $hash->{READINGS}{RandomNr} );
		delete( $hash->{READINGS}{RandomNr1} );
	}
	####################
    ### teste auf new defined device
	
    my $hidden = '';
    if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '4' ) 
	{ 
		$hidden = ''
	}
    else 
	{ 
		$hidden = 'hidden' 
	}

    my $triggerdevices = '';
    my $events         = ReadingsVal( $Name, '.Device_Events', '' );
    my @eventsall      = split( /#\[tr\]/, $events );
    my $Triggerdevice  = ReadingsVal( $Name, 'Trigger_device', '' );
    my $triggeron      = ReadingsVal( $Name, '.Trigger_on', '' );
    if ( !defined $triggeron ) { $triggeron = "" }
    my $triggeroff = ReadingsVal( $Name, '.Trigger_off', '' );
    if ( !defined $triggeroff ) { $triggeroff = "" }
    my $triggercmdon = ReadingsVal( $Name, '.Trigger_cmd_on', '' );
    if ( !defined $triggercmdon ) { $triggercmdon = "" }
    my $triggercmdoff = ReadingsVal( $Name, '.Trigger_cmd_off', '' );
    if ( !defined $triggercmdoff ) { $triggercmdoff = "" }
    my $disable = "";

    my %korrekt;
    foreach (@eventsall) 
	{
        $korrekt{$_} = 'ok';
    }
    $korrekt{$triggeron}     = 'ok';
    $korrekt{$triggeroff}    = 'ok';
    $korrekt{$triggercmdon}  = 'ok';
    $korrekt{$triggercmdoff} = 'ok';
	
    my @eventsallnew;
    for my $name ( sort keys %korrekt ) 
	{
        push( @eventsallnew, $name );
    }
	
    @eventsall = @eventsallnew;

    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Notify" ) 
	{
        readingsSingleUpdate( $hash, "state", 'active', 1 );
        $triggeroff = "";
        $triggeron  = "";
    }

    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Toggle" ) 
	{
        $triggeroff    = "";
        $triggercmdoff = "";
        $triggercmdon  = "";
    }

    #eigene trigger festlegen
    my $optionon      = '';
    my $optiongeneral = '';
    my $optioncmdon   = '';
    my $alltriggers   = '';
    my $to            = '';
    my $toc           = '';
	LOOP12: foreach (@eventsall)
	{
        $alltriggers =
        $alltriggers . "<option value=\"$_\">" . $_ . "</option>";
		
        if ( $_ eq 'no_trigger' ) 
		{
			next LOOP12;
		}
		
        if ( $triggeron eq $_ ) 
		{
            $optionon =$optionon
              . "<option selected=\"selected\" value=\"$_\">". $_. "</option>";
            $to = '1';
        }
        else 
		{
            $optionon = $optionon . "<option value=\"$_\">" . $_ . "</option>";
        }

        if ( $triggercmdon eq $_ ) 
		{
            $optioncmdon =$optioncmdon. "<option selected=\"selected\" value=\"$_\">". $_. "</option>";
            $toc = '1';
        }
        else 
		{
            $optioncmdon =$optioncmdon . "<option value=\"$_\">" . $_ . "</option>";
        }

        ####################  nur bei entsprechender regex
        my $test = $_;
        if ( $test =~ m/(.*)\((.*)\)(.*)/ ) 
		{
        }
        else 
		{
            if ( index( $_, '*', 0 ) == -1 ) 
			{
                if ( ReadingsVal( $Name, 'Trigger_device', '' ) ne "all_events" )
                {
                    $optiongeneral = $optiongeneral. "<option value=\"$_\">". $_. "</option>";
                }
                else 
				{
                    $optiongeneral =$optiongeneral. "<option value=\"$_\">". $_. "</option>";
                }
            }
        }

        #####################
    }
    if ( $to eq '1' )
	{
        $optionon ="<option value=\"no_trigger\">no_trigger</option>" . $optionon;
    }
    else 
	{
        $optionon ="<option selected=\"selected\" value=\"no_trigger\">no_trigger</option>" . $optionon;
    }
	
    if ( $toc eq '1' )
	{
        $optioncmdon ="<option value=\"no_trigger\">no_trigger</option>" . $optioncmdon;
    }
    else 
	{
        $optioncmdon ="<option selected=\"selected\" value=\"no_trigger\">no_trigger</option>". $optioncmdon;
    }
	
    my $optioncmdoff = '';
    my $optionoff    = '';
    $to  = '';
    $toc = '';
	
	LOOP14: foreach (@eventsall) 
	{
        if ( $_ eq 'no_trigger' ) { next LOOP14 }
        if ( $triggeroff eq $_ ) 
		{
            $optionoff = $optionoff. "<option selected=\"selected\" value=\"$_\">$_</option>";
            $to = '1';
        }
        else 
		{
            $optionoff = $optionoff . "<option value=\"$_\">$_</option>";
        }
        if ( $triggercmdoff eq $_ ) 
		{
            $optioncmdoff = $optioncmdoff . "<option selected=\"selected\" value=\"$_\">$_</option>";
            $toc = '1';
        }
        else 
		{
            $optioncmdoff = $optioncmdoff . "<option value=\"$_\">$_</option>";
        }
    }
	
    if ( $to eq '1' ) 
	{
        $optionoff = "<option value=\"no_trigger\">no_trigger</option>" . $optionoff;
    }
    else
	{
        $optionoff ="<option selected=\"selected\" value=\"no_trigger\">no_trigger</option>". $optionoff;
    }

    if ( $toc eq '1' ) 
	{
        $optioncmdoff = "<option value=\"no_trigger\">no_trigger</option>" . $optioncmdoff;
    }
    else 
	{
        $optioncmdoff ="<option selected=\"selected\" value=\"no_trigger\">no_trigger</option>". $optioncmdoff;
    }
	
	$optionon =~ s/\[bs\]/|/g;
	$optionoff =~ s/\[bs\]/|/g;
	$optioncmdon =~ s/\[bs\]/|/g;
	$optioncmdoff =~ s/\[bs\]/|/g;
	
####################
    # mögliche affected devices und mögliche triggerdevices
    my $devicesets;
    my $deviceoption = "";
    my $selected     = "";
    my $errors       = "";
    my $javaform     = "";    # erhält javacode für übergabe devicedetail
    my $cs           = "";
    my %cmdsatz;              # ablage desbefehlssatzes jedes devices
    my $globalon = 'off';

    if ( ReadingsVal( $Name, 'Trigger_device', 'no_trigger' ) eq 'no_trigger' )
    {
        $triggerdevices ="<option selected=\"selected\" value=\"no_trigger\">no_trigger</option>";
    }
    else
	{
        $triggerdevices = "<option  value=\"no_trigger\">no_trigger</option>";
    }
	
    if ( AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' ) 
	{
        if ( ReadingsVal( $Name, 'Trigger_device', 'no_trigger' ) eq 'all_events' )
        {
            $triggerdevices .="<option selected=\"selected\" value=\"all_events\">GLOBAL</option>";
            $globalon = 'on';
        }
        else 
		{
            $triggerdevices .= "<option  value=\"all_events\">GLOBAL</option>";
        }
    }
	
    my @notype = split( / /, AttrVal( $Name, 'MSwitch_Ignore_Types', "" ) );
    my $affecteddevices = ReadingsVal( $Name, '.Device_Affected', 'no_device' );

    # affected devices to hash
    my %usedevices;
    my @deftoarray = split( /,/, $affecteddevices );
	my $anzahl = @deftoarray;

	my $reihenfolgehtml="";
	if ( AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' ) 
		{
			$reihenfolgehtml="<select name = 'reihe' id=''>";
			for (my $i=1; $i<$anzahl+1; $i++)
			{
				$reihenfolgehtml.="<option value='$i'>$i</option>";
			}			
			$reihenfolgehtml.="</select>";

		}
		
	my $idfolgehtml="";	
	if ( AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' ) 
		{
			$idfolgehtml="<select name = 'idreihe' id=''>";
			for (my $i=-1; $i<$anzahl+1; $i++)
			{
				$idfolgehtml.="<option value='$i'>$i</option>" if $i > 0 ;
				$idfolgehtml.="<option value='$i'>-</option>" if $i == 0 ;
			}			
			$idfolgehtml.="</select>";

		}	

    foreach (@deftoarray) 
	{
        my ( $a, $b ) = split( /-/, $_ );
        $usedevices{$a} = 'on';
    }

	LOOP9: for my $name ( sort keys %defs ) 
	{
        my $selectedtrigger = '';
        my $devicealias = AttrVal( $name, 'alias', "" );
        my $devicewebcmd =AttrVal( $name, 'webCmd', "noArg" );    # webcmd des devices
        my $devicehash = $defs{$name};            #devicehash
        my $deviceTYPE = $devicehash->{TYPE};

        # triggerfile erzeugen
        foreach (@notype) 
		{
            if ( lc($_) eq lc($deviceTYPE) ) { next LOOP9; }
        }
		
        if ( ReadingsVal( $Name, 'Trigger_device', '' ) eq $name ) 
		{
            $selectedtrigger = 'selected=\"selected\"';
            if ( $name eq 'all_events' ) { $globalon = 'on' }
        }
		
        $triggerdevices .="<option $selectedtrigger value=\"$name\">$name (a:$devicealias t:$deviceTYPE)</option>";

        # filter auf argumente on oder off ;
        if ( $name eq '' ) { next LOOP9; }
		
        my $cs = "set $name ?";

        # abfrage und auswertung befehlssatz
        if ( AttrVal( $Name, 'MSwitch_Include_Devicecmds', "1" ) eq '1' ) 
		{
            $errors = AnalyzeCommandChain( undef, $cs );
            if ($errors) { }
        }
        else 
		{
            $errors = '';
        }
		
        if ( !defined $errors ) { $errors = '' }
		
        my @tmparg = split( /of /, $errors );
		
		if (!defined $tmparg[1]){$tmparg[1]=""};
        #if ( defined $tmparg[1] && $tmparg[1] ne '' ) { $errors = $tmparg[1]; }
		if ( $tmparg[1] ne '' ) 
		{ 
		$errors = $tmparg[1]; 
		}
		else{
		$errors = ''; 
		}

        $errors = '|' . $errors;
        $errors =~ s/\| //g;
        $errors =~ s/\|//g;

        if ( $errors eq '' && AttrVal( $Name, 'MSwitch_Include_Webcmds', "1" ) eq '1' )
        {
            if ( $devicewebcmd ne "noArg" )
			{
                my $device = '';
                my @webcmd = split( /:/, $devicewebcmd );
                foreach (@webcmd) {
                    $_ =~ tr/ /:/;
                    my @parts = split( /:/, $_ );
                    if ( !defined $parts[1] || $parts[1] eq '' ) 
					{
                        $device .= $parts[0] . ':noArg ';
                    }
                    else 
					{
                        $device .= $parts[0] . ':' . $parts[1] . ' ';
                    }
                }
                chop $device;
                $devicewebcmd = $device;
                $errors       = $devicewebcmd;
            }
        }
		
        my $usercmds = AttrVal( $name, 'MSwitchcmd', '' );
        if ( $usercmds ne ''&& AttrVal( $Name, 'MSwitch_Include_MSwitchcmds', "1" ) eq '1' )
        {
            $usercmds =~ tr/:/ /;
            $errors .= ' ' . $usercmds;
        }

        my $extensions = AttrVal( $Name, 'MSwitch_Extensions', "0" );
        if ( $extensions eq '1' ) 
		{
            $errors .= ' ' . 'MSwitchtoggle';
        }
		
        if ( $errors ne '' ) 
		{
            $selected = "";
            if ( exists $usedevices{$name} && $usedevices{$name} eq 'on' ) 
			{
                $selected = "selected=\"selected\" ";
            }
            $deviceoption =
                $deviceoption
              . "<option "
              . $selected
              . "value=\""
              . $name . "\">"
              . $name . " (a:"
              . $devicealias
              . ")</option>";

            # befehlssatz für device in scalar speichern
            $cmdsatz{$name} = $errors;
        }
        else
		{}
    }
	
    my $select = index( $affecteddevices, 'FreeCmd', 0 );
	$selected = "";
    if ( $select > -1 ) { $selected = "selected=\"selected\" " }
    $deviceoption =
        "<option "
      . "value=\"FreeCmd\" "
      . $selected
      . ">Free Cmd (nicht an ein Device gebunden)</option>"
      . $deviceoption;
	  

	$select = index( $affecteddevices, 'MSwitch_Self', 0 );
	$selected = "";
    if ( $select > -1 ) { $selected = "selected=\"selected\" " } 
	   $deviceoption =
        "<option "
      . "value=\"MSwitch_Self\" "
      . $selected
      . ">MSwitch_Self (".$Name.")</option>"
      . $deviceoption;
	  
####################
# #devices details
# detailsatz in scalar laden
# my @devicedatails = split(/:/,ReadingsVal($Name, '.Device_Affected_Details', '')); #inhalt decice und cmds # durch komma getrennt

    my %savedetails = MSwitch_makeCmdHash($Name);
    my $detailhtml  = "";
    my @affecteddevices = split( /,/, ReadingsVal( $Name, '.Device_Affected', 'no_device' ) );
    if ( $affecteddevices[0] ne 'no_device' ) 
	{
        $detailhtml =
		"<table border='$border' class='block wide' id='MSwitchDetails' nm='MSwitch'>
		<tr class='even'>
		<td colspan='5'>device actions :<br>&nbsp;
		<input type='hidden' id='affected' name='affected' size='40'  value ='"
		. ReadingsVal( $Name, '.Device_Affected', 'no_device' ) . "'>
		</td></tr>";    #start
		
        foreach (@affecteddevices)
		{

         # $cmdsatz{$_} enthält befehlssatz als string getrennt durch " " und :
            my @devicesplit  = split( /-AbsCmd/, $_ );
			
			my $devicenamet  = $devicesplit[0];
			
			my $zusatz ="";
			if ($devicenamet eq "MSwitch_Self")
			{
			$devicenamet = $Name;
			$zusatz ="MSwitch_Self -> ";
			}

            my $devicenumber = $devicesplit[1];
            my @befehlssatz  = '';
			if ($devicenamet eq "FreeCmd")
			{
				$cmdsatz{$devicenamet}='';
			}

            @befehlssatz = split( / /, $cmdsatz{$devicenamet} );
            my $aktdevice = $_;

            ## optionen erzeugen
            my $option1html  = '';
            my $option2html  = '';
            my $selectedhtml = "";
			
            if ( !defined( $savedetails{ $aktdevice . '_on' } ) )
			{
                my $key = '';
                $key = $aktdevice . "_on";
                $savedetails{$key} = 'no_action';
            }

            if ( !defined( $savedetails{ $aktdevice . '_off' } ) )
			{
                my $key = '';
                $key = $aktdevice . "_off";
                $savedetails{$key} = 'no_action';
            }
			
            if ( !defined( $savedetails{ $aktdevice . '_onarg' } ) ) 
			{
                my $key = '';
                $key = $aktdevice . "_onarg";
                $savedetails{$key} = '';
            }
			
            if ( !defined( $savedetails{ $aktdevice . '_offarg' } ) )
			{
                my $key = '';
                $key = $aktdevice . "_offarg";
                $savedetails{$key} = '';
            }

            if ( !defined( $savedetails{ $aktdevice . '_delayaton' } ) ) 
			{
                my $key = '';
                $key = $aktdevice . "_delayaton";
                $savedetails{$key} = 'delay1';
            }

            if ( !defined( $savedetails{ $aktdevice . '_delayatoff' } ) )
			{
                my $key = '';
                $key = $aktdevice . "_delayatoff";
                $savedetails{$key} = 'delay1';
            }

            if ( !defined( $savedetails{ $aktdevice . '_timeon' } ) ) 
			{
                my $key = '';
                $key = $aktdevice . "_timeon";
                $savedetails{$key} = '000000'; 
            }
			
            if ( !defined( $savedetails{ $aktdevice . '_timeoff' } ) )
			{
                my $key = '';
                $key = $aktdevice . "_timeoff";
                $savedetails{$key} = '000000'; 
            }
			
            if ( !defined( $savedetails{ $aktdevice . '_conditionon' } ) ) 
			{
                my $key = '';
                $key = $aktdevice . "_conditionon";
                $savedetails{$key} = '';
            }
			
            if ( !defined( $savedetails{ $aktdevice . '_conditionoff' } ) ) 
			{
                my $key = '';
                $key = $aktdevice . "_conditionoff";
                $savedetails{$key} = '';
            }

            foreach (@befehlssatz)    #befehlssatz einfügen
            {
			
                my @aktcmdset = split( /:/, $_ );    # befehl von noarg etc. trennen
                $selectedhtml = "";
				next if !defined $aktcmdset[0]; #changed 19.06
				
                if ( $aktcmdset[0] eq $savedetails{ $aktdevice . '_on' } )
				{
                    $selectedhtml = "selected=\"selected\"";
                }
				
                $option1html = $option1html . "<option $selectedhtml value=\"$aktcmdset[0]\">$aktcmdset[0]</option>";
                $selectedhtml = "";
				
                if ( $aktcmdset[0] eq $savedetails{ $aktdevice . '_off' } ) 
				{
                    $selectedhtml = "selected=\"selected\"";
                }
				
                $option2html = $option2html . "<option $selectedhtml value=\"$aktcmdset[0]\">$aktcmdset[0]</option>";
            }

            if ( '' eq $savedetails{ $aktdevice . '_delayaton' } ) 
			{
                $savedetails{ $aktdevice . '_delayaton' } = 'delay1';
            }

            if ( '' eq $savedetails{ $aktdevice . '_delayatoff' } )
			{
                $savedetails{ $aktdevice . '_delayatoff' } = 'delay1';
            }

            if ( '' eq $savedetails{ $aktdevice . '_timeoff' } )
			{
                $savedetails{ $aktdevice . '_timeoff' } = '0';
            }
            if ( '' eq $savedetails{ $aktdevice . '_timeon' } ) 
			{
                $savedetails{ $aktdevice . '_timeon' } = '0';
            }

			
            $savedetails{ $aktdevice . '_onarg' } =~ s/~/ /g;
            $savedetails{ $aktdevice . '_offarg' } =~ s/~/ /g;
			
			$savedetails{ $aktdevice . '_onarg' } =~ s/#\[ti\]/~/g;;
            $savedetails{ $aktdevice . '_offarg' } =~ s/#\[ti\]/~/g;;
			
			$savedetails{ $aktdevice . '_onarg' } =~ s/#\[wa\]/|/g; #neu
            $savedetails{ $aktdevice . '_offarg' } =~ s/#\[wa\]/|/g; #neu
			
          
			my $dalias='';
			if ($devicenamet ne "FreeCmd")
			{
				$dalias = "(a: " . AttrVal( $devicenamet, 'alias', "no" ) . ")" if AttrVal( $devicenamet, 'alias', "no" ) ne "no";
			}
			if ( AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' ) 
			{

			    $detailhtml = $detailhtml . "
				<tr class='odd'>
				<td colspan='4' class='col1' style=\"width: 100%\">";
				
				$detailhtml = $detailhtml . "$zusatz $devicenamet&nbsp&nbsp;&nbsp;$dalias
				</td>";
				
			# priority		
				my $aktfolge = $reihenfolgehtml;
				my $newname = "reihe".$_;
				my $tochange = "<option value='$savedetails{ $aktdevice . '_priority' }'>$savedetails{ $aktdevice . '_priority' }</option>";
				my $change = "<option selected value='$savedetails{ $aktdevice . '_priority' }'>$savedetails{ $aktdevice . '_priority' }</option>";
				$aktfolge =~ s/reihe/$newname/g;
				$aktfolge =~ s/$tochange/$change/g;
				$detailhtml = $detailhtml ."<td nowrap style='text-align: right;' class='col1'>";
				if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
				{
					$detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('priority')\">&nbsp;";
				}
				$detailhtml = $detailhtml ."priority: ". $aktfolge ."&nbsp;";
				#$detailhtml = $detailhtml ."</td>";
			# ende

			# ID
				 $aktfolge = $idfolgehtml;
				 $newname = "idreihe".$_;
				 $tochange = "<option value='$savedetails{ $aktdevice . '_id' }'>$savedetails{ $aktdevice . '_id' }</option>";
				 
				 
				 
				 $change = "<option selected value='$savedetails{ $aktdevice . '_id' }'>$savedetails{ $aktdevice . '_id' }</option>";
				$aktfolge =~ s/idreihe/$newname/g;
				$aktfolge =~ s/$tochange/$change/g;

				$detailhtml = $detailhtml ."ID: ". $aktfolge;
				$detailhtml = $detailhtml ."</td>";
			
			# ende
				
			}
			else
			{
			    $detailhtml = $detailhtml . "
				<tr class='odd'>
				<td colspan='5' class='col1'>";
				$detailhtml = $detailhtml . "$zusatz $devicenamet&nbsp&nbsp;&nbsp;$dalias
				</td>";
			}
	
			$detailhtml = $detailhtml . "</td></tr>
			<tr class=''>
			";

            my $rephide = "style='display:none;'";
            my $rows    = 7;
			
            if ( AttrVal( $Name, 'MSwitch_Expert', "0" ) eq '1' )
            {
                $rephide = '';
                $rows    = 8;
            }

            $detailhtml = $detailhtml . "<td rowspan='$rows' class='col2'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";

            if ( $devicenamet ne 'FreeCmd' ) 
			{
                $detailhtml = $detailhtml . "</td>
				<td nowrap class='col2' style='text-align: left;'>
				
				<table border='0'><tr>
				<td nowrap class='col2' style='text-align: left;'>
				
				<br>";
				
				if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('onoff')\">&nbsp;";
            }
				
				$detailhtml = $detailhtml. "MSwitch 'cmd1': 
				Set <select class=\"devdetails2\" id='"
                . $_
                . "_on' name='cmdon"
                . $_
                . "' onchange=\"javascript: activate(document.getElementById('"
                . $_
                . "_on').value,'"
                . $_
                . "_on_sel','"
                . $cmdsatz{$devicenamet}
                . "','cmdonopt"
                . $_
                . "1')\" >
				<option value='no_action'>no_action</option>";
                $detailhtml = $detailhtml . $option1html;
                $detailhtml = $detailhtml . "
				</select>
				<td nowrap valign=bottom id='" . $_ . "_on_sel'>&nbsp;</td>
				</tr></table>
				<td nowrap>
				</td>
				
				<td  class='col2' style=\"width: 100%\">&nbsp;<br><input type='$hidden' id='cmdseton"
                . $_
                . "' name='cmdseton"
                . $_
                . "' size='20'  value ='"
                . $cmdsatz{$devicenamet} . "'>
				<input type='$hidden' id='cmdonopt"
                . $_
                . "1' name='cmdonopt"
                . $_
                . "' size='20'  value ='"
                . $savedetails{ $aktdevice . '_onarg' }
                . "'>&nbsp;&nbsp;&nbsp;";
				
				
            }
            else
			{

			$savedetails{ $aktdevice . '_onarg' }=~ s/'/&#039/g;
			$detailhtml = $detailhtml . "</td>
			<td class='col2' nowrap style='text-align: left;vertical-align: middle;'>
			
			<table><tr>
			<td>";
				
				if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('onoff')\">&nbsp;";
            }
				
				$detailhtml = $detailhtml. "MSwitch 'cmd1':</td>
			<td><textarea class=\"devdetails\" cols='50' rows='3' id='cmdonopt". $_. "1' name='cmdonopt".$_. "'
			>".$savedetails{ $aktdevice . '_onarg' }."</textarea>
			</td>
			</tr></table>
			
			</td>";
			
			$detailhtml = $detailhtml . "
			<td  style='text-align: left;' class='col2' nowrap id='" . $_ . "_on_sel'></td>
			
			<td nowrap><input type='$hidden' id='". $_ . "_on' name='cmdon" . $_ . "' size='20'  value ='cmd'></td>
			
			<td  class='col2' style=\"width: 100%\">&nbsp;<br><input type='$hidden' id='cmdseton"
            . $_ . "' name='cmdseton" . $_ . "' size='20'  value ='cmd'>";	
            }

            $detailhtml = $detailhtml . "</td><td></td></tr>";

            # block off #$devicename
            if ( $devicenamet ne 'FreeCmd' ) 
			{
                $detailhtml = $detailhtml . "		
				<tr class='even'>
				<td  class='col2' nowrap style='text-align: left;'>
				<table><tr>
				<td  class='col2' nowrap style='text-align: left;'>
				";
				
				if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('onoff')\">&nbsp;";
            }
				
				$detailhtml = $detailhtml. "MSwitch 'cmd2':
				Set <select class=\"devdetails2\" id='"
                . $_
                . "_off' name='cmdoff"
                . $_
                . "' onchange=\"javascript: activate(document.getElementById('"
                . $_
                . "_off').value,'"
                . $_
                . "_off_sel','"
                . $cmdsatz{$devicenamet}
                . "','cmdoffopt"
                . $_
                . "1')\" >
				<option value='no_action'>no_action</option>";
                $detailhtml = $detailhtml
                . $option2html;    #achtung tausch $_ devicenamet oben unten
                $detailhtml = $detailhtml . "
				</select>
				</td>
				<td  class='col2' nowrap id='" . $_ . "_off_sel' >&nbsp;</td>
				</tr></table>
				</td>
				<td></td>
				
				<td  class='col2' nowrap>
				<input type='$hidden' id='cmdsetoff"
                . $_
                . "' name='cmdsetoff"
                . $_
                . "' size='20'  value ='"
                . $cmdsatz{$devicenamet} . "'>
				<input type='$hidden'   id='cmdoffopt"
                . $_
                . "1' name='cmdoffopt"
                . $_
                . "' size='20' value ='"
                . $savedetails{ $aktdevice . '_offarg' } . "'>&nbsp;&nbsp;&nbsp;";
            }
            else 
			{
				$savedetails{ $aktdevice . '_offarg' }=~ s/'/&#039/g;
				$detailhtml = $detailhtml . "		
				<tr class='even'>
				<td  class='col2' nowrap style='text-align: left;'>
				
				<table><tr>
				<td>";
				
				if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('onoff')\">&nbsp;";
            }
				
				$detailhtml = $detailhtml. "MSwitch 'cmd2':</td>
				<td>
				<textarea class=\"devdetails\" cols='50' rows='3' id='cmdoffopt"
                . $_
                . "1' name='cmdoffopt".$_
                . "'
				>".$savedetails{ $aktdevice . '_offarg' }."</textarea>
				</td>
				</tr></table>
				</td>
				<td style='text-align: left;' class='col2' nowrap id='" . $_ . "_off_sel' ></td>
				<td><input type='$hidden' id='". $_ . "_off' name='cmdoff" . $_ . "' size='20'  value ='cmd'></td>
				<td  class='col2' nowrap>
				<input type='$hidden' id='cmdsetoff"
                . $_
                . "' name='cmdsetoff"
                . $_
                . "' size='20'  value ='cmd'>";
            }
			
            $detailhtml = $detailhtml . "</td><td></td></tr>";
            $detailhtml = $detailhtml . "	
			<tr class='even'>
			<td  class='col2' colspan='4' nowrap style='text-align: left;'>";
			
			 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('condition')\">&nbsp;";
            }
			
			$detailhtml = $detailhtml. "'cmd1' condition: <input class=\"devdetails\" type='text' id='conditionon"
            . $_
            . "' name='conditionon"
            . $_
            . "' size='55' value ='"
            . $savedetails{ $aktdevice . '_conditionon' }
            . "' onClick=\"javascript:bigwindow(this.id);\">&nbsp;&nbsp;&nbsp;";

            if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '1' )
			{
                $detailhtml =$detailhtml
                . "<input name='info' type='button' value='check condition' onclick=\"javascript: checkcondition('conditionon"
                . $_
                . "',document.querySelector('#checkon"
                . $_
                . "').value)\"> with \$EVENT=<select id = \"checkon"
                . $_
                . "\" name=\"checkon"
                . $_ . "\">"
                . $optiongeneral
                . "</select>";
            }

            #alltriggers
           
            $detailhtml = $detailhtml . "</td></tr>
			<tr class='even'>
			<td  class='col2' colspan='4' nowrap style='text-align: left;'>";
			
			 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('condition')\">&nbsp;";
            }
			
			$detailhtml = $detailhtml. "'cmd2' condition: <input class=\"devdetails\" type='text' id='conditionoff"
            . $_
            . "' name='conditionoff"
            . $_
            . "' size='55' value ='"
            . $savedetails{ $aktdevice . '_conditionoff' }
            . "' onClick=\"javascript:bigwindow(this.id);\">&nbsp;&nbsp;&nbsp;";

            if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml
                . "<input name='info' type='button' value='check condition' onclick=\"javascript: checkcondition('conditionoff"
                . $_
                . "',document.querySelector('#checkoff"
                . $_
                . "').value)\"> with \$EVENT=<select id = \"checkoff"
                . $_
                . "\" name=\"checkoff"
                . $_ . "\">"
                . $optiongeneral
                . "</select>";
            }
			
            #### zeitrechner
            my $delaym = 0;
            my $delays = 0;
            my $delayh = 0;
            my $timestroff;
            my $testtimestroff = $savedetails{ $aktdevice . '_timeoff' };

            if ( $testtimestroff ne '[random]' ) 
			{
                $testtimestroff =~ s/[A-Za-z0-9#\.\-_]//g;
                if ( $testtimestroff eq "[:]" || $testtimestroff eq "[\$:]" ) 
				{
                    $timestroff =
                     $savedetails{ $aktdevice . '_timeoff' };    #sekunden
                }
                else 
				{
                    $timestroff =
                    $savedetails{ $aktdevice . '_timeoff' };    #sekunden
                    $delaym = int $timestroff / 60;
                    $delays = $timestroff - ( $delaym * 60 );
                    $delayh = int $delaym / 60;
                    $delaym = $delaym - ( $delayh * 60 );
                    $timestroff =
                     sprintf( "%02d:%02d:%02d", $delayh, $delaym, $delays );
                }
            }
            else 
			{ 
				$timestroff = "[random]"; 
			}

            my $timestron;
            my $testtimestron = $savedetails{ $aktdevice . '_timeon' };

			
			
			#Log3( $Name, 0,"testtimestron -> $testtimestron " . __LINE__ );
			
			
			
            if ( $testtimestron ne '[random]' ) 
			{
                $testtimestron =~ s/[A-Za-z0-9#\.\-_]//g;
                if ( $testtimestron eq "[:]"  || $testtimestron eq "[\$:]" ) 
				{
                    $timestron =$savedetails{ $aktdevice . '_timeon' };    #sekunden
                }
                else 
				{
                    $timestron =
                    $savedetails{ $aktdevice . '_timeon' };    #sekunden
                    $delaym = int $timestron / 60;
                    $delays = $timestron - ( $delaym * 60 );
                    $delayh = int $delaym / 60;
                    $delaym = $delaym - ( $delayh * 60 );
                    $timestron =
                    sprintf( "%02d:%02d:%02d", $delayh, $delaym, $delays );
                }

            }
            else 
			{
				$timestron = "[random]"; 
			}

         

            $detailhtml = $detailhtml . "</td></tr><tr class='even'>
			<td  class='col2' colspan='4' nowrap style='text-align: left;'>";
			
			
			 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('timer')\">&nbsp;";
            }
			
			$detailhtml = $detailhtml. "'cmd1'&nbsp;
			<select id = '' name='onatdelay" . $_ . "'>";

            my $se11 = '';
            my $sel2 = '';
            my $sel3 = '';
            my $sel4 = '';
			my $sel5 = '';
			my $sel6 = '';

            my $testkey = $aktdevice . '_delaylaton';

            $se11 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "delay1" ) ;
            $sel2 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "delay0" ) ; 
			$sel5 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "delay2" ) ;
            $sel4 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "at0" ) ;
            $sel3 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "at1" ); 
		
			$sel6 = 'selected' if ( $savedetails{ $aktdevice . '_delayaton' } eq "at2" );	
			
            $detailhtml = $detailhtml . "<option $se11 value='delay1'>delay with Cond-check immediately and delayed: +</option>";
            $detailhtml = $detailhtml . "<option $sel2 value='delay0'>delay with Cond-check immediately only: +</option>";
			$detailhtml = $detailhtml . "<option $sel5 value='delay2'>delay with Cond-check delayed only: +</option>";
			$detailhtml = $detailhtml . "<option $sel4 value='at0'>at with Cond-check immediately and delayed:</option>";
            $detailhtml = $detailhtml . "<option $sel3 value='at1'>at with Cond-check immediately only:</option>";
			$detailhtml = $detailhtml . "<option $sel6 value='at0'>at with Cond-check delayed only:</option>";
			
            $detailhtml = $detailhtml . "</select><input type='text' class=\"devdetails\" id='timeseton"
            . $_
            . "' name='timeseton"
            . $_
            . "' size='30' value ='"
            . $timestron
            . "'> (hh:mm:ss)</td></tr>";
			$detailhtml = $detailhtml . "
			<tr class='even'>
			<td  class='col2' colspan='4' nowrap style='text-align: left;'>";
			
			
			 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('timer')\">&nbsp;";
            }
			
			$detailhtml = $detailhtml. "'cmd2'&nbsp;
			<select id = '' name='offatdelay" . $_ . "'>";

            $se11 = '';
            $sel2 = '';
            $sel3 = '';
            $sel4 = '';
			$sel5 = '';
			$sel6 = '';
            $testkey = $aktdevice . '_delaylatoff';

			$se11 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "delay1" ) ;
            $sel2 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "delay0" ) ; 
			$sel5 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "delay2" ) ;
			
            $sel4 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "at0" ) ;
            $sel3 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "at1" ); 
			$sel6 = 'selected' if ( $savedetails{ $aktdevice . '_delayatoff' } eq "at2" ); 

            $detailhtml = $detailhtml . "<option $se11 value='delay1'>delay with Cond-check immediately and delayed: +</option>";
            $detailhtml = $detailhtml . "<option $sel2 value='delay0'>delay with Cond-check immediately only: +</option>";
			
			$detailhtml = $detailhtml . "<option $sel5 value='delay2'>delay with Cond-check delayed only: +</option>";
			
			$detailhtml = $detailhtml . "<option $sel4 value='at0'>at with Cond-check immediately and delayed:</option>";
            $detailhtml = $detailhtml . "<option $sel3 value='at1'>at with Cond-check immediately only:</option>";
			$detailhtml = $detailhtml . "<option $sel6 value='at0'>at with Cond-check delayed only:</option>";
			
            $detailhtml = $detailhtml . "</select><input type='text' class=\"devdetails\" id='timesetoff"
            . $_
            . "' name='timesetoff"
            . $_
            . "' size='30' value ='"
            . $timestroff
            . "'> (hh:mm:ss)&nbsp;&nbsp;&nbsp;";

            $detailhtml = $detailhtml . "</td></tr>";
            $detailhtml = $detailhtml . "<tr $rephide class='even'>
			<td  class='col2' colspan='4' style='text-align: left;'>";
			
			 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
                $detailhtml = $detailhtml. "<input name='info' type='button' value='?' onclick=\"javascript: info('repeats')\">&nbsp;";
            }
			
			$detailhtml = $detailhtml. "Repeats: 
			<input type='text' id='repeatcount' name='repeatcount"
            . $_
			. "' size='10' value ='"
            . $savedetails{ $aktdevice . '_repeatcount' } . "'>
			&nbsp;&nbsp;&nbsp;
			Repeatdelay in sec:
			<input type='text' id='repeattime' name='repeattime"
            . $_
            . "' size='10' value ='"
            . $savedetails{ $aktdevice . '_repeattime' } . "'>
			</td></tr>";
            $detailhtml = $detailhtml . "<tr $rephide class='even'>
			<td  class='col2' colspan='4' style='text-align: left;'>
			<br>
			</td></tr>";
            $detailhtml = $detailhtml . "<tr class='even'>
			<td  class='col2' colspan='5' style='text-align: left;'>";
            if ( $devicenumber == 1 ) 
			{
                $detailhtml = $detailhtml . "<input name='info' class=\"randomidclass\" id=\"add_action1_".rand(1000000)."\" type='button' value='add action for $devicenamet' onclick=\"javascript: addevice('$devicenamet')\">";
            }
            $detailhtml = $detailhtml . "<input name='info' id=\"del_action1_".rand(1000000)."\" class=\"randomidclass\" type='button' value='delete this action for $devicenamet' onclick=\"javascript: deletedevice('$_')\">";
            $detailhtml = $detailhtml . "<br>&nbsp;</td></tr>";

            #middle
####################change1 = change.replace(/,/g,'##');
            # javazeile für übergabe erzeugen
			 $javaform = $javaform . "
			devices += \$(\"[name=cmdon$_]\").val()+'#[NF]';
			devices += \$(\"[name=cmdoff$_]\").val()+'#[NF]';
			change = \$(\"[name=cmdonopt$_]\").val();
			devices += change+'#[NF]';;
			change = \$(\"[name=cmdoffopt$_]\").val();
			devices += change+'#[NF]';;
			devices += \$(\"[name=onatdelay$_]\").val();
			devices += '#[NF]';
			devices += \$(\"[name=offatdelay$_]\").val();
			devices += '#[NF]';
			delay1 = \$(\"[name=timesetoff$_]\").val();
			devices += delay1+'#[NF]';
			delay2 = \$(\"[name=timeseton$_]\").val();
			devices += delay2+'#[NF]';
			devices1 = \$(\"[name=conditionon$_]\").val();
			devices2 = \$(\"[name=conditionoff$_]\").val();
			devices2 = devices2.replace(/\\|/g,'(DAYS)');
			devices += devices1+'#[NF]';
			devices += devices2;
			devices += '#[NF]';
			devices3 = \$(\"[name=repeatcount$_]\").val();
			devices += devices3;
			devices += '#[NF]';
			devices += \$(\"[name=repeattime$_]\").val();
			devices += '#[NF]';
			devices += \$(\"[name=reihe$_]\").val();
			devices += '#[NF]';
			devices += \$(\"[name=idreihe$_]\").val();
			devices += '#[ND]';

			";
        }
			
	
####################
        $detailhtml = $detailhtml;
        $detailhtml = $detailhtml . "<tr class='even'><td colspan='5'><left>
		<input type='button' id='aw_det' value='modify Actions' >
		</td></tr></table>";    #end
    }
	
####################
    my $triggercondition = ReadingsVal( $Name, '.Trigger_condition', '' );
    $triggercondition =~ s/~/ /g;
	
		$triggercondition =~ s/#\[dp\]/:/g;
		$triggercondition =~ s/#\[pt\]/./g;
		$triggercondition =~ s/#\[ti\]/~/g;
		$triggercondition =~ s/#\[sp\]/ /g;
	
	
	#MSwitch_LOG( $name, 5, "$name: aufruf on/off -> $cmd"  );
	
	my $triggertime = ReadingsVal( $Name, '.Trigger_time', '' );
	$triggertime =~ s/#\[dp\]/:/g;
	
	
	
	
    my @triggertimes = split( /~/, $triggertime );
    my $condition   = ReadingsVal( $Name, '.Trigger_time', '' );
    my $lenght      = length($condition);
    my $timeon      = '';
    my $timeoff     = '';
    my $timeononly  = '';
    my $timeoffonly = '';

	
	
	
	
	
    if ( $lenght != 0 ) {
        $timeon      = substr( $triggertimes[0], 2 );
        $timeoff     = substr( $triggertimes[1], 3 );
        $timeononly  = substr( $triggertimes[2], 6 );
        $timeoffonly = substr( $triggertimes[3], 7 );
    }
	
	my $ret ='';
	$ret .="<p id=\"triggerdevice\">";
########################
	my $blocking ='' ;
	$blocking =$hash->{helper}{savemodeblock}{blocking} if ( defined $hash->{helper}{savemodeblock}{blocking}) ;
	if ($blocking eq 'on')
	{
		$ret .="<table border='$border' class='block wide' id=''>
		<tr class='even'>
		<td><center>&nbsp;<br>ACHTUNG: Der Safemodus hat eine Endlosschleife erkannt, welche zum Fhemabsturz führen könnte.<br>Dieses Device wurde automatisch deaktiviert ( ATTR 'disable') !<br>&nbsp;
		</td></tr></table><br>&nbsp;<br>
		";
	}
	
	my $errortest="";
	$errortest = $hash->{helper}{error} if ( defined $hash->{helper}{error}) ;
	
	if ($errortest ne "")
	{
		 $ret .="<table border='$border' class='block wide' id=''>
		 <tr class='even'>
		 <td><center>&nbsp;<br>AT-Kommandos können nicht ausgeführt werden !<br>".$errortest."<br>&nbsp;
		 </td></tr></table><br>&nbsp;<br>
		 ";
	}
	

	if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '2' || AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '3' )
	{
	
	
	my $Zeilen = ("");
    open( BACKUPDATEI, "./log/MSwitch_debug_$Name.log" ) ;
    while (<BACKUPDATEI>)
	{
        $Zeilen = $Zeilen . $_;
    }
    close(BACKUPDATEI);

	my $text ="";
	$text = "Das Device befindet sich im Debug 2 Mode. Es werden keine Befehle ausgeführt, sondern nur protokolliert." if AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '2';
	
	$text = "Das Device befindet sich im Debug 3 Mode. Alle Aktionen werden protokolliert." if AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '3';
	

	 $ret .="<table border='$border' class='block wide' id=''>
		 <tr class='even'>
		 <td><center>&nbsp;<br>
		 $text<br>&nbsp;<br>
		 <textarea name=\"log\" id=\"log\" rows=\"5\" cols=\"160\" STYLE=\"font-family:Arial;font-size:9pt;\">"
          . $Zeilen
          . "</textarea>
		  <br>&nbsp;<br>
		<input type=\"button\" id=\"\"
		value=\"clear log\" onClick=\"clearlog();\"> 
		 <br>&nbsp;<br>
		 </td></tr></table><br>
		 <br>
		 ";

	}
	

	# anpassung durch configeinspielung
if ( ReadingsVal( $Name, '.change', 'undef') ne "undef")
	{
	
	# geräteliste
	my $dev;
	for my $name ( sort keys %defs ) 
		{
			my $devicealias = AttrVal( $name, 'alias', "" );
			my $devicewebcmd =AttrVal( $name, 'webCmd', "noArg" );    
			my $devicehash = $defs{$name}; 
			my $deviceTYPE = $devicehash->{TYPE};
			$dev .="<option selected=\"\" value=\"$name\">". $name." (a: ".$devicealias. ")</option>";
		}
		
	my $sel="<select id = \"CID\" name=\"trigon\">" . $dev . "</select>";
	

	my @change = split( "\\|", ReadingsVal( $Name, '.change', 'undef') );
	my $out ='';
	my $count = 0;
	foreach my $changes (@change) 
		{
		my @set =  split( "#", $changes );
		$out .="<tr class='even'>";
		$out .="<td>";
		$out .= $set[1];
		$out .="</td>";
		$out .="<td>";
		#$out .= $set[0];
		$out .="</td>";
		$out .="<td>";
		$out .="<input type='' id='cdorg".$count."' name=''  value ='$set[0]' disabled> ersetzen durch:";
			if ($set[2] eq "device")
			{
			
			my $newstring = $sel;
			my $newname = "cdnew".$count;
			$newstring =~ s/CID/$newname/g;
			$out .=$newstring;
			}
			else{
			$out .="&nbsp;<input type='' id='cdnew".$count."' name='' size='20'  value =''>";
			}
		$out .="</td>";
		$out .="</tr>";
		#$out ="<tr><td>test</td></tr>";
		$count++;
		}
	
		$ret .="
		<table border='$border' class='block wide' id=''>
		<tr class='even'>
		<td colspan ='3'><center>&nbsp;<br>Eingriff erforderlich !<br>&nbsp;";
		$ret .=ReadingsVal( $Name, '.change_info', '') ;
		$ret .="</td></tr>".$out."
		<tr class='even'>
		<td colspan ='3'><center>&nbsp;<br>
		<input type=\"button\" id=\"\"
		value=\"save changes\" onClick=\"changedevices();\"> 
		<br>&nbsp;<br>
		</td></tr></table><br>
		<br>
		 ";
		 
		 
	$j1 = "<script type=\"text/javascript\">{";	
	$j1 .=
	"var t=\$(\"#MSwitchWebTR\"), ip=\$(t).attr(\"ip\"), ts=\$(t).attr(\"ts\");
	FW_replaceWidget(\"[name=aw_ts]\", \"aw_ts\", [\"time\"], \"12:00\");
	\$(\"[name=aw_ts] input[type=text]\").attr(\"id\", \"aw_ts\");";
	
	
	$j1 .= "function changedevices(){
    var count = $count;
	var string = '';
	for (i=0; i<count; i++)
		{
		var field1 = 'cdorg'+i;
		var field2 = 'cdnew'+i;
		string +=  document.getElementById(field1).value + '#' + document.getElementById(field2).value + '|';
		}

	var strneu = string.substr(0, string.length-1);
	strneu = strneu.replace(/ /g,'#[sp]');
	var  def = \"".$Name."\"+\" confchange \"+encodeURIComponent(strneu);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}";	 
	$j1 .= "}</script>"; 
	return "$ret"."$j1";
	}

	
	#readingsSingleUpdate( $hash, ".wrong_version", $1, 0 );
	if ( ReadingsVal( $Name, '.wrong_version', 'undef') ne "undef")
	{
		 $ret .="<table border='$border' class='block wide' id=''>
		 <tr class='even'>
		 <td><center>&nbsp;<br>Einspielen des Configfiles nicht möglich !<br>falsche Versionsnummer: ".ReadingsVal( $Name, '.wrong_version', '')."<br>geforderte Versionsnummer $vupdate<br>&nbsp;
		
		</td></tr></table><br>
		<br>
		 
		 ";
	fhem("deletereading $Name .wrong_version");

	}

	if ( ReadingsVal( $Name, '.V_Check', $vupdate ) ne $vupdate )
	{
	
	my $ver = ReadingsVal( $Name, '.V_Check', '' );
	 $ret .="<table border='$border' class='block wide' id=''>
		 <tr class='even'>
		 <td><center>&nbsp;<br>Versionskonflikt erkannt!<br>Das Device führt derzeit keine Aktionen aus. Bitte ein Update des Devices vornehmen.<br>Erwartete Strukturversionsnummer: $vupdate<br>Vorhandene Strukturversionsnummer: $ver <br>&nbsp;<br>
		<input type=\"button\" id=\"\"
		value=\"try update to $vupdate\" onClick=\"vupdate();\"> 
		<br>&nbsp;<br>
		</td></tr></table><br>
		<br>
		 
		 ";

	$j1 = "<script type=\"text/javascript\">{";	
	$j1 .=
	"var t=\$(\"#MSwitchWebTR\"), ip=\$(t).attr(\"ip\"), ts=\$(t).attr(\"ts\");
	FW_replaceWidget(\"[name=aw_ts]\", \"aw_ts\", [\"time\"], \"12:00\");
	\$(\"[name=aw_ts] input[type=text]\").attr(\"id\", \"aw_ts\");";
	$j1 .= "function vupdate(){
    conf='';
	var  def = \"".$Name."\"+\" VUpdate \"+encodeURIComponent(conf);
	//alert(def);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}";	 
	$j1 .= "}</script>"; 	  
	return "$ret"."$j1";
	}
	
	
	
	 $ret .="<table border='$border' class='block wide' id=''>
		 <tr class='even'>
		 <td><center>&nbsp;<br>Device is disabled, configuration avaible<br>&nbsp;<br>
		 </td></tr></table><br>" if ( IsDisabled($Name));
	
####################
	$ret .="<table border='$border' class='block wide' id='MSwitchWebTR' nm='$hash->{NAME}'>";
	$ret .="	<tr class=\"even\">";
	$ret .="<td colspan=\"3\" id =\"savetrigger\">trigger  device/time:&nbsp;&nbsp;&nbsp;";
  
    $ret = $ret . "</td>
	</tr>
	<tr class=\"even\">
	<td></td>
	<td></td>
	<td></td>
	</tr>
	<tr class=\"even\">
	<td>";
	 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' )
	{
        $ret = $ret. "<input name='info' type='button' value='?' onclick=\"javascript: info('trigger')\">&nbsp;";
    }
	
	
	$ret .="Trigger device: </td>
	<td  colspan =\"2\">
	<select id =\"trigdev\" name=\"trigdev\">".$triggerdevices."</select>
	</td>
	</tr>";
    my $visible = 'visible';
    if ( $globalon ne 'on' ) 
	{
        $visible = 'collapse';
    }
    $ret = $ret . "<tr class=\"even\"  id='triggerwhitelist' style=\"visibility:" . $visible . ";\" >
	<td nowrap>";
	
	  if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
	{
        $ret = $ret. "<input name='info' type='button' value='?' onclick=\"javascript: info('whitelist')\">&nbsp;";
    }
	$ret = $ret. "Trigger Device Global Whitelist: 
	</td>
	<td></td>
	<td><input type='text' id ='triggerwhite' name='triggerwhitelist' size='30' value ='"
    . ReadingsVal( $Name, '.Trigger_Whitelist', '' )
    . "' onClick=\"javascript:bigwindow(this.id);\" >";
  
    $ret = $ret . "</td></tr>";

    my $inhalt  = "execute 'cmd1' only at :";
    my $inhalt1 = "execute 'cmd2' only at :";
    my $inhalt2 = "execute 'cmd1' only";
    my $inhalt3 = "execute 'cmd2' only";
    my $inhalt4 = "switch MSwitch on + execute 'cmd1' at :";
    my $inhalt5 = "switch $Name on + execute 'cmd1'";
    my $displaynot  = '';
    my $displayntog = '';

	my $help ="";
		if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
		{
            $help = "<input name='info' type='button' value='?' onclick=\"javascript: info('execcmd')\">&nbsp;";
        }

	
    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Notify" ) 
	{
        $displaynot = "style='display:none;'";
        $inhalt     = "execute 'cmd1' at :";
        $inhalt1    = "execute 'cmd2' at :";
        $inhalt2    = $help."execute 'cmd1'";
        $inhalt3    = $help."execute 'cmd2'";
    }

    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Toggle" ) 
	{
        $displayntog = "style='display:none;'";
        $inhalt4     = "toggle $Name + execute 'cmd1/cmd2' at :";
        $inhalt5     = "toggle $Name + execute 'cmd1/cmd2'";
    }

    $ret = $ret . "
	<tr class=\"even\">
	<td>";
	
		 if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' )
	{
        $ret = $ret. "<input name='info' type='button' value='?' onclick=\"javascript: info('trigger')\">&nbsp;";
    }
	
	$ret = $ret. "Trigger time: </td>
	<td></td>
	<td>
	</td>
	</tr>
	<tr " . $displaynot . " class=\"even\">
	<td></td>
	<td>" . $inhalt4 . "</td>
	<td><input type='text' id='timeon' name='timeon' size='60'  value ='"
    . $timeon . "'></td>
	</tr>
	<tr  " . $displaynot . $displayntog . " class=\"even\">
	<td></td>
	<td>switch MSwitch off + execute 'cmd2' at :</td>
	<td><input type='text' id='timeoff' name='timeoff' size='60'  value ='"
    . $timeoff . "'></td>
	</tr>
	<tr " . $displayntog . "class=\"even\">
	<td></td>
	<td>" . $inhalt . "</td>
	<td><input type='text' id='timeononly' name='timeononly' size='60'  value ='"
    . $timeononly . "'></td>
	</tr>
	<tr " . $displayntog . "class=\"even\">
	<td></td>
	<td>" . $inhalt1 . "</td>
	<td><input type='text' id='timeoffonly' name='timeoffonly' size='60'  value ='"
      . $timeoffonly . "'></td>
	</tr>";
    my $triggerinhalt = "Trigger condition (events only): ";
    if ( AttrVal( $Name, 'MSwitch_Condition_Time', "0" ) eq '1' ) 
	{
        $triggerinhalt ="Trigger condition (time&events): ";
    }
    $ret = $ret . "<tr class=\"even\">
	<td>";
	if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
	{
        $ret = $ret .= "<input name='info' type='button' value='?' onclick=\"javascript: info('triggercondition')\">&nbsp;";
    }
	
	$ret = $ret . $triggerinhalt."</td>
	<td></td>
	<td><input type='text' id='triggercondition' name='triggercondition' size='60' value ='"
    . $triggercondition . "' onClick=\"javascript:bigwindow(this.id);\" >";
	
    if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '1' ) 
	{
       # $ret = $ret. " <input name='info' type='button' value='check condition' onclick=\"javascript: checkcondition('triggercondition',document.querySelector('#triggercondition').value)\">";
		
		$ret = $ret. " <input name='info' type='button' value='check condition' onclick=\"javascript: checkcondition('triggercondition','$Name:trigger:conditiontest')\">";

    }

    $ret = $ret . "</td></tr>";
    $ret = $ret . "<tr class=\"even\">
	<td colspan=\"3\"><left>
	<input type=\"button\" id=\"aw_trig\" value=\"modify Trigger Device\"$disable>
	</td>
	</tr>
	</table></p>";
####################
# triggerdetails
    my $selectedcheck3 = "";
    my $testlog = ReadingsVal( $Name, 'Trigger_log', 'on' );
    if ( $testlog eq 'on' ) 
	{
        $selectedcheck3 = "checked=\"checked\"";
    }
    if ( ReadingsVal( $Name, 'Trigger_device', 'no_trigger' ) ne 'no_trigger' )
    {
        $ret .="<table border='$border' class='block wide' id='MSwitchWebTRDT' nm='$hash->{NAME}'>
		<tr class=\"even\">
		<td id =\"triggerdetails\">trigger details :</td>
		<td></td>
		<td></td>
		</tr>
		<tr class=\"even\">
		<td></td>
		<td></td>
		<td></td>
		</tr>";
        $ret .= "<tr " . $displaynot . " class=\"even\"><td>";

		$ret .= $inhalt5. "</td><td>
		Trigger " . $Triggerdevice . " :
		</td>
		<td>
		<select id = \"trigon\" name=\"trigon\">" . $optionon . "</select>
		</td>
		</tr>
		<tr " . $displaynot . $displayntog . "class=\"even\">
		<td>
		switch " . $Name . " off + execute 'cmd2'</td>
		<td>
		Trigger " . $Triggerdevice . " :
		</td>
		<td>
		<select id = \"trigoff\" name=\"trigoff\">" . $optionoff . "</select>
		</td>
		</tr>";

        $ret .= "<tr class=\"even\">
		<td colspan=\"3\" >&nbsp</td>
		</tr>
		<tr " . $displayntog . "  class=\"even\">
		<td>" . $inhalt2 . "</td>
		<td>
		Trigger " . $Triggerdevice . " :
		</td>
		<td>
		<select id = \"trigcmdon\" name=\"trigcmdon\">" . $optioncmdon . "</select>
		</td>
		</tr>
		<tr " . $displayntog . "class=\"even\">
		<td>" . $inhalt3 . "</td>
		<td>
		Trigger " . $Triggerdevice . " :
		</td>
		<td>
		<select id = \"trigcmdoff\" name=\"trigcmdoff\">"
        . $optioncmdoff . "</select>
		</td>
		</tr>
		
		<tr class=\"even\">
		<td colspan=\"1\"><left>";
		if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
		{
            $ret = $ret . "<input name='info' type='button' value='?' onclick=\"javascript: info('saveevent')\">&nbsp;";
        }
		
		$ret = $ret . "Save incomming events : 
		
		</td>
		<td><input $selectedcheck3 name=\"aw_save\" type=\"checkbox\" $disable></td>
		<td></td>
		</tr>
	
		<tr class=\"even\">
		<td colspan=\"1\"><left>";
		if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
		{
            $ret = $ret . "<input name='info' type='button' value='?' onclick=\"javascript: info('addevent')\">&nbsp;";
        }
		
		$ret .= "Add event manually : 
		</td>
		<td><left>
		<input type='text' id='add_event' name='add_event' size='40'  value =''>
		<input type=\"button\" id=\"aw_addevent\" value=\"add event\"$disable>";

        $ret .= "</td>
		<td><left>
		</td>
		</tr>

		<tr class=\"even\">
		<td colspan=\"2\"><left>
		<input type=\"button\" id=\"aw_md\" value=\"modify Trigger\"$disable>
		<input type=\"button\" id=\"aw_md1\" value=\"apply filter to saved events\" $disable>
		<input type=\"button\" id=\"aw_md2\" value=\"clear saved events\"$disable>&nbsp;&nbsp;&nbsp;
		</td>
		<td><left>";

        if ( AttrVal( $Name, 'MSwitch_Debug', "0" ) eq '1' && $optiongeneral ne '' )
        {
            $ret .="<select id = \"eventtest\" name=\"eventtest\">"
            . $optiongeneral
            . "</select><input type=\"button\" id=\"aw_md2\" value=\"test event\"$disable onclick=\"javascript: checkevent(document.querySelector('#eventtest').value)\">";
        }
		
        $ret .= "</td></tr>	</table></p>";
    }
    else 
	{
        $ret .= "<p id=\"MSwitchWebTRDT\"></p>";
    }

    # affected devices
    $ret .= "<table border='$border' class='block wide' id='MSwitchWebAF' nm='$hash->{NAME}'>
	<tr class=\"even\">
	<td>affected devices :</td>
	<td></td>
	<td></td>
	</tr>
	<tr class=\"even\">
	<td>
	</td>
	<td>
	</td>
	<td></td>
	</tr>
	<tr class=\"even\">
	<td>";
	
		if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
		{
            $ret .= "<input name='info' type='button' value='?' onclick=\"javascript: info('affected')\">&nbsp;";
        }

	$ret .="multiple selection with ctrl + mousebutton</td>
	<td><p id =\"textfie\">
	<select id =\"devices\" multiple=\"multiple\" name=\"affected_devices\" size=\"6\" disabled >";
    $ret .= $deviceoption;
    $ret .= "</select>
	</p>
	</td>
	<td><center>
	<input type=\"button\" id=\"aw_great\"
	value=\"edit list\" onClick=\"javascript:deviceselect();\">
	<br>
	<input onChange=\"javascript:switchlock();\" checked=\"checked\" id=\"lockedit\" name=\"lockedit\" type=\"checkbox\" value=\"lockedit\" /> quickedit locked
	<br>
	<br>
	</td>
	</tr>
	<tr class=\"even\">
	<td><leftt>
	<input type=\"button\" id=\"aw_dev\" value=\"modify Devices\"$disable>
	</td>
	<td>&nbsp;</td>
	<td>&nbsp;</td>
	</tr>
	</table>";
####################
    #javascript$jsvarset
    my $triggerdevicehtml = $Triggerdevice;
    $triggerdevicehtml =~ s/\(//g;
    $triggerdevicehtml =~ s/\)//g;

    $j1 = "<script type=\"text/javascript\">{";
    if ( AttrVal( $Name, 'MSwitch_Lock_Quickedit', "1" ) eq '0' ) 
	{
        $j1 .= "
		\$(\"#devices\").prop(\"disabled\", false);
		document.getElementById('aw_great').value='schow greater list';
		document.getElementById('lockedit').checked = false  ;	
		";
    }

    if ( $affecteddevices[0] ne 'no_device' )
	{
        $j1 .= "	
		var affected = document.getElementById('affected').value 
		var devices = affected.split(\",\");
		var i;
		var len = devices.length;
		for (i=0; i<len; i++)
		{
		testname = devices[i].split(\"-\");
		if (testname[0] == \"FreeCmd\") {
		continue;
		}
		sel = devices[i] + '_on';
		sel1 = devices[i] + '_on_sel';
		sel2 = 'cmdonopt' +  devices[i] + '1';
		sel3 = 'cmdseton' +  devices[i];
		aktcmd = document.getElementById(sel).value;
		aktset = document.getElementById(sel3).value;
		activate(document.getElementById(sel).value,sel1,aktset,sel2);
		sel = devices[i] + '_off';
		sel1 = devices[i] + '_off_sel';
		sel2 = 'cmdoffopt' +  devices[i] + '1';
		sel3 = 'cmdsetoff' +  devices[i];
		aktcmd = document.getElementById(sel).value;
		aktset = document.getElementById(sel3).value;
		activate(document.getElementById(sel).value,sel1,aktset,sel2); 
		};"
    }
 # java wird bei seitenaufruf ausgeführt
    $j1 .= "
	var globallock='';
	var randomdev=[];
	var x = document.getElementsByClassName('randomidclass');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	randomdev.push(t);
	}";
	
	$j1 .= "
	var globaldetails2='undefined';
	var x = document.getElementsByClassName('devdetails2');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	globaldetails2 +=document.getElementById(t).value;
	}

	var globaldetails='undefined';
	var x = document.getElementsByClassName('devdetails');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	globaldetails +=document.getElementById(t).value;
	
	document.getElementById(t).onchange = function() 
	{
	//alert('changed');
	var changedetails;
	var y = document.getElementsByClassName('devdetails');
    for (var i = 0; i < y.length; i++) 
	{
    var t  = y[i].id;
	changedetails +=document.getElementById(t).value;
	}
	if( changedetails != globaldetails)
		{
		globallock =' unsaved device actions';
		[ \"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\",\"aw_dev\"].forEach (lock,);
		randomdev.forEach (lock);
		}
	if( changedetails == globaldetails)
		{
		[ \"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\",\"aw_dev\"].forEach (unlock,);
			randomdev.forEach (unlock);
		}
	}
	}
	";
	
	# triggerlock
	$j1 .= "
	var triggerdetails = document.getElementById('MSwitchWebTRDT').innerHTML;
	var saveddevice = '" . $triggerdevicehtml . "';
	var sel = document.getElementById('trigdev');
	sel.onchange = function() 
	{
	trigdev = this.value;
	if (trigdev != '";
		$j1 .= $triggerdevicehtml;
		$j1 .= "')
		{
		//document.getElementById('savetrigger').innerHTML = '<font color=#FF0000>trigger device : unsaved!</font> ';	 
		//document.getElementById('MSwitchWebTRDT').innerHTML = '';
		
		globallock =' unsaved trigger';
		[\"aw_dev\", \"aw_det\"].forEach (lock);
		randomdev.forEach (lock,);
		}
	else
		{	
		//alert (randomdev);
		[\"aw_dev\", \"aw_det\"].forEach (unlock);
		randomdev.forEach (unlock);
		document.getElementById('savetrigger').innerHTML = 'trigger device :';
		document.getElementById('MSwitchWebTRDT').innerHTML = triggerdetails;	
		}
	
	if (trigdev == 'all_events')
		{
		document.getElementById(\"triggerwhitelist\").style.visibility = \"visible\"; 
		}
	else
		{
		document.getElementById(\"triggerwhitelist\").style.visibility = \"collapse\"; 
		}
	}
	";

	#####################
	$j1 .= "
	
	
		if (document.getElementById('trigon')){
	var trigonfirst = document.getElementById('trigon').value;
	var sel2 = document.getElementById('trigon');
	sel2.onchange = function() 
	{
	if (trigonfirst != document.getElementById('trigon').value)
		{
		closetrigger();
		}
		else{
		opentrigger();
		}
	}
	}
	
	if (document.getElementById('trigoff')){
	var trigofffirst = document.getElementById('trigoff').value;
	var sel3 = document.getElementById('trigoff');
	sel3.onchange = function() 
	{
	if (trigofffirst != document.getElementById('trigoff').value)
		{
		closetrigger();
		}
		else{
		opentrigger();
		}
	}
	}
	
	if (document.getElementById('trigcmdoff')){
	var trigcmdofffirst = document.getElementById('trigcmdoff').value;
	var sel4 = document.getElementById('trigcmdoff');
	sel4.onchange = function() 
	{
	if (trigcmdofffirst != document.getElementById('trigcmdoff').value)
		{
		closetrigger();
		}
		else{
		opentrigger();
		}
	}
	}
	
	if (document.getElementById('trigcmdon')){
	var trigcmdonfirst = document.getElementById('trigcmdon').value;
	var sel5 = document.getElementById('trigcmdon');
	sel5.onchange = function() 
	{
	if (trigcmdonfirst != document.getElementById('trigcmdon').value)
		{
		closetrigger();
		}
		else{
		opentrigger();
		}
	}
	}
	
	function closetrigger(){
			globallock =' unsaved trigger details';
			[\"aw_dev\", \"aw_det\",\"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\"].forEach (lock,);
			randomdev.forEach (lock);
	}
	
	function opentrigger(){
			//alert('call unlock');
			[ \"aw_dev\",\"aw_det\",\"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\"].forEach (unlock,);
			randomdev.forEach (unlock);
	}
	
	";
	
	#####################
	#affected lock
	$j1 .= "
	var globalaffected;
	var auswfirst=document.getElementById('devices');
	for (i=0; i<auswfirst.options.length; i++)
	{
	var pos=auswfirst.options[i];
	if(pos.selected)
	{
	//alert (pos.value);
	globalaffected +=pos.value;
	}
	}
	///alert (globalaffected);
	var sel1 = document.getElementById('devices');
	sel1.onchange = function() 
	{
		var actaffected;
		var auswfirst=document.getElementById('devices');
		for (i=0; i<auswfirst.options.length; i++)
			{
			var pos=auswfirst.options[i];
			if(pos.selected)
				{
				//alert (pos.value);
				actaffected +=pos.value;
				}
			}

		if (actaffected != globalaffected)
			{
			globallock =' unsaved affected device';
			[ \"aw_det\",\"aw_trig\",\"aw_md\",\"aw_md1\",\"aw_md2\",\"aw_addevent\"].forEach (lock,);
			randomdev.forEach (lock);
			}
		else
			{
			[ \"aw_det\",\"aw_trig\",\"aw_md\",\"aw_md1\",\"aw_md2\",\"aw_addevent\"].forEach (unlock,);
			randomdev.forEach (unlock);
			}
	
	}
	";
	#function lock unlock
	$j1 .= "function lock (elem, text){
	
	if (document.getElementById(elem)){
	document.getElementById(elem).style.backgroundColor = \"#ADADAD\"
	document.getElementById(elem).disabled = true;
	
	if (!document.getElementById(elem).model)
	{
	document.getElementById(elem).model=document.getElementById(elem).value;
	}

	document.getElementById(elem).value = 'N/A'+globallock;
	}
	
	}";
	
	$j1 .= "function unlock (elem, index){
	if (document.getElementById(elem)){
	document.getElementById(elem).style.backgroundColor = \"\"
	document.getElementById(elem).disabled = false;
	document.getElementById(elem).value=document.getElementById(elem).model;
	}
	}";
	#####################
	
    $j1 .= "function saveconfig(conf){
	
	conf = conf.replace(/\\n/g,'#[EOL]');
	conf = conf.replace(/:/g,'#c[dp]');
	conf = conf.replace(/;/g,'#c[se]');
	conf = conf.replace(/ /g,'#c[sp]');
	
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" saveconfig \"+encodeURIComponent(conf);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}";
	
	
	$j1 .= "function vupdate(){
    conf='';
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" VUpdate \"+encodeURIComponent(conf);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}";
	
	
	 $j1 .= "function clearlog(){
     conf='';
	 var nm = \$(t).attr(\"nm\");
	 var  def = nm+\" clearlog \"+encodeURIComponent(conf);
	 location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	 }";
	
	
	
	$j1 .= "function savesys(conf){
	conf = conf.replace(/:/g,'#[dp]');
	conf = conf.replace(/;/g,'#[se]');
	conf = conf.replace(/ /g,'#[sp]');
	conf = conf.replace(/'/g,'#[st]');
	
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" savesys \"+encodeURIComponent(conf);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}";

	
	$j1 .= "function checkcondition(condition,event){	

    //alert(condition,event);
	var selected =document.getElementById(condition).value;
	// event = \"test:test:test\";
	if (selected == '')
	{
	var textfinal = \"<div style ='font-size: medium;'>Es ist keine Bedingung definiert, das Kommando wird immer ausgeführt.</div>\";
	FW_okDialog(textfinal);
	return;
	}

	selected = selected.replace(/\\|/g,'(DAYS)');
	selected = selected.replace(/\\./g,'#[pt]');
	selected = selected.replace(/:/g,'#[dp]');
	selected= selected.replace(/~/g,'#[ti]');
	selected = selected.replace(/ /g,'#[sp]');

	event = event.replace(/~/g,'#[ti]');
	event = event.replace(/ /g,'#[sp]');

	cmd ='get " . $Name . " checkcondition '+selected+'|'+event;
	FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1', function(resp){FW_okDialog(resp);});
	}

	function checkevent(event){	
	event = event.replace(/ /g,'~');
	cmd ='get " . $Name . " checkevent '+event;
	FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1');
	}
";
	
	
	
	if ( AttrVal( $Name, 'MSwitch_Help', "0" ) eq '1' ) 
			{
			
	$j1 .= "		
	function info(from){
	text='Help: ' + from +'<br><br>';
	if (from == 'timer'){
	text = text +  'Hier kann entweder eine direkte Angabe einer Verzögerungszeit (delay with Cond_check) angegeben werden, oder es kann eine Ausführungszeit (at with Cond-check) für den Befehl angegeben werden<br> Bei der Angabe einer Ausführungszeit wird der Schaltbefehl beim nächsten erreichen der angegebenen Zeit ausgeführt. Ist die Zeit am aktuellen Tag bereits überschritten , wird der angegebene Zeitpunkt am Folgetag gesetzt.<br>Die Auswahl \"with Conf-check\" oder \"without Conf-check\" legt fest, ob unmittelbar vor Befehlsausführung nochmals die Condition für den Befehl geprüft wird oder nicht.<br><brAlternativ kann hier auch ein Verweis auf ein beliebiges Reading eines Devices erfolgen, das entsprechenden Wert enthält. Dieser Verweis muss in folgendem Format erfolgen:<br><br>[NAME.reading] des Devices  ->z.B.  [dummy.state]<br>Das Reading muss in folgendem Format vorliegen: hh:mm:ss ';}
					   
	if (from == 'trigger'){
	text = text +  'Trigger ist das Gerät, oder die Zeit, auf die das Modul reagiert, um andere devices anzusprechen.<br>Das Gerät kann aus der angebotenen Liste ausgewählt werden, sobald dieses ausgewählt ist werden weitere Optionen angeboten.<br>Soll auf mehrereGerät gleichzeitig getriggert werden , so ist dieses ebenfalls möglich. Hierzu muss das Attribut \"MSwitch_Expert\" auf 1 gesetzt sein und als Auswahl \"GLOBAL\" erfolgen.<br><br>Zeitangaben können ebenso als Trigger genutzt werden, das Format muss wie folgt lauten:<br><br> [STUNDEN:MINUTEN|TAGE] - Tage werden von 1-7 gezählt, wobei 1 für Montag steht, 7 für Sonntag.<br /><br>Die Variable \$we ist anstatt der Tagesangabe verwendbar<br> [STUNDEN:MINUTEN|\$we] - Schaltvorgang nur an Wochenenden.<br>[STUNDEN:MINUTEN|!\$we] - Schaltvorgang nur an Werktagen.<br><br>Mehrere Zeitvorgaben können aneinandergereiht werden.<br>[17:00|1][18:30|23] würde den Trigger Montags um 17 Uhr auslösen und Dienstags,Mittwochs um 18 Uhr 30.<br><br>Sunset - Zeitangaben können mit folgender Sytax eingebunden werden: z.B [{sunset()}] , [{sunrise(+1800)}].<br><br>Es ist eine gleichzeitige Nutzung für Trigger durch Zeitangaben und Trigger durch Deviceevents möglich.<br><br>Sonderformate:<br>[?20:00-21:00|5] - Zufälliger Schaltvorgang zwischen 20 Uhr und 21 Uhr am Freitag<br>[00:02*04:10-06:30] - Schaltvorgang alle 2 Minuten zwischen 4.10 Uhr und 6.30 Uhr';}
					   
	if (from == 'triggercondition'){
	text = text + 'Hier kann die Angabe von Bedingungen erfolgen, die zusätzlich zu dem triggernden Device erfuellt sein müssen.<br> Diese Bedingunge sind eng an DOIF- Bedingungen angelehnt .<br>Zeitabhängigkeit: [19.10-23:00] - Trigger des Devices erfolgt nur in angegebenem Zeitraum<br>Readingabhängige Trigger [Devicename:Reading] =/>/< X oder [Devicename:Reading] eq \"x\" - Trigger des Devicec erfolgt nur bei erfüllter Bedingung.<br>Achtung ! Bei der Abfrage von Readings nach Strings ( on,off,etc. ) ist statt \"=\" \"eq\" zu nutzen und der String muss in \"\" gesetzt werden!<br>Die Kombination mehrerer Bedingungen und Zeiten ist durch AND oder OR möglich.<br>[19.10-23:00] AND [Devicename:Reading] = 10 - beide Bedingungen müssen erfüllt sein<br>[19.10-23:00] OR [Devicename:Reading] = 10 - eine der Bedingungen muss erfüllt sein.<br>Es ist auf korrekte Eingabe der Leerzeichen zu achten.<br><br>sunset - Bedingungen werden mit zusätzlichen {} eingefügt z.B. : [{ sunset() }-23:00].<br><br>Variable \$we:<br>Die globlae Variable \$we ist nutzbar und muss in {} gesetzt werden .<br>{ !\$we } löst den Schaltvorgang nur Werktagen an aus<br>{ \$we } löst den Schaltvorgang nur an Wochenenden, Feiertagen aus<br><br>Soll nur an bestimmten Wochentagen geschaltet werden, muss eine Zeitangsbe gemacht werden und durch z.B. |135 ergänzt werden.<br>[10:00-11:00|13] würde den Schaltvorgang z.B nur Montag und Mitwoch zwischen 10 uhr und 11 uhr auslösen. Hierbei zählen die Wochentage von 1-7 für Montag-Sonntag.<br>Achtung: Bei Anwendung der geschweiften Klammern zur einletung eines Perlasdrucks ist unbedingt auf die Leerzeichen hinter und vor der Klammer zu achten !<br> Überschreitet die Zeitangabe die Tagesgrenze (24.00 Uhr ), so gelten die angegebenen Tage noch bis zum ende der angegebenen Schaltzeit,<br> d.H. es würde auch am Mitwoch noch der schaltvorgang erfolgen, obwohl als Tagesvorgabe Dienstag gesetzt wurde.<br><br>Wird in diesem Feld keine Angabe gemacht , so erfolgt der Schaltvorgang nur durch das triggernde Device ohne weitere Bedingungen.<br><br>Achtung: Conditions gelten nur für auslösende Trigger eines Devices und habe keinen Einfluss auf zeitgesteuerte Auslöser. Um Zeitgesteuerte Auslösr ebenfalls an Bedingungen zu Knüpfen muss dieses in den Attributen aktiviert werden.';}
					   
	if (from == 'whitelist'){
	text = text +  'Bei der Auswahl \\\'GLOBAL\\\' als Triggerevent werde alle von Fhem erzeugten Events an dieses Device weitergeleitet. Dieses kann eine erhöhte Systemlast erzeugen.<br>In dem Feld \\\'Trigger Device Global Whitelist:\\\' kann dieses eingeschränkt werden , indem Devices oder Module benannt werden , deren Events Berücksichtigt werden. Sobald hier ein Eintrag erfolgt , werden nur noch Diese berücksichtigt , gibt es keinen Eintrag , werden alle berücksichtigt ( Whitelist ).<br> Format: Die einzelnen Angaben müssen durch Komma getrennt werden .<br><br>Mögliche Angaben :<br>Modultypen: TYPE=CUL_HM<br>Devicenamen: NAME<br><br>';}
					   
	if (from == 'addevent'){
	text = text +  'Hier können manuell Events zugefügt werden , die in den Auswahllisten verfügbar sein sollen und auf die das Modul reagiert.<br>Grundsätzlich ist zu unterscheiden , ob das Device im Normal-, oder Globalmode betrieben wird<br>Im Normalmode bestehen die Events aus 2 Teilen , dem Reading und dem Wert \"state:on\"<br>Wenn sich das Device im GLOBAL Mode befindet müssen die Events aus 3 Teilen bestehen , dem Devicename, dem Reading und dem Wert \"device:state:on\".<br>Wird hier nur ein \"*\" angegeben , reagiert der entsprechende Zweig auf alle eingehenden Events.<br>Weitherhin sind folgende Syntaxmöglichkeiten vorgesehen :<br> device:state:*, device:*:*, *:state:* , etc.<br>Der Wert kann mehrere Auswahlmöglichkeiten haben , durch folgende Syntax: \"device:state:(on/off)\". In diesem Fal reagiert der Zweig sowohl auf den Wert on, als auch auf off.<br><br>Es können mehrere Evebts gleichzeitig angelegt werden . Diese sind durch Komma zu trennen .<br><br>Seit V1.7 kann hier die gängige RegEx-Formulierung erfolgen.';}
					   
	if (from == 'condition'){
	text = text +  'Hier kann die Angabe von Bedingungen erfolgen, die erfüllt sein müssen um den Schaltbefehl auszuführen.<br>Diese Bedingunge sind eng an DOIF- Bedingungen angelehnt.<br><br>Zeitabhängiges schalten: [19.10-23:00] - Schaltbefehl erfolgt nur in angegebenem Zeitraum<br>Readingabhängiges schalten [Devicename:Reading] =/>/< X oder [Devicename:Reading] eq \"x\" - Schaltbefehl erfolgt nur bei erfüllter Bedingung.<br>Achtung! Bei der Abfrage von Readings nach Strings ( on,off,etc. ) ist statt \"=\" \"eq\" zu nutzen und der String muss in \"x\" gesetzt werden!<br> Die Kombination mehrerer Bedingungen und Zeiten ist durch AND oder OR möglich:<br> [19.10-23:00] AND [Devicename:Reading] = 10 - beide Bedingungen müssen erfüllt sein<br>[19.10-23:00] OR [Devicename:Reading] = 10 - eine der Bedingungen muss erfüllt sein.<br>Es ist auf korrekte Eingabe der Leerzeichen zu achten.<br><br>sunset - Bedingungen werden mit zusätzlichen {} eingefügt z.B. : [{ sunset() }-23:00].<br><br>Variable \$we:<br>Die globlae Variable \$we ist nutzbar und muss {} gesetzt werden .<br>{ !\$we } löst den Schaltvorgang nur Werktagen aus<br>{ \$we } löst den Schaltvorgang nur Wochenenden, Feiertagen aus<br><br>Soll nur an bestimmten Wochentagen geschaltet werden, muss eine Zeitangsbe gemacht werden und durch z.B. |135 ergänzt werden.<br>[10:00-11:00|13] würde den Schaltvorgang z.B nur Montag und Mitwoch zwischen 10 uhr und 11 uhr auslösen. Hierbei zählen die Wochentage von 1-7 für Montag-Sonntag.<br>Achtung: Bei Anwendung der geschweiften Klammern zur einletung eines Perlasdrucks ist unbedingt auf die Leerzeichen hinter und vor der Klammer zu achten !<br>Überschreitet die Zeitangabe die Tagesgrenze (24.00 Uhr ), so gelten die angegebenen Tage noch bis zum ende der angegebenen Schaltzeit , d.H. es würde auch am Mitwoch noch der schaltvorgang erfolgen, obwohl als Tagesvorgabe Dienstag gesetzt wurde.<br><br>\$EVENT Variable: Die Variable EVENT enthält den auslösenden Trigger, d.H. es kann eine Reaktion in direkter Abhängigkeit zum auslösenden Trigger erfolgen.<br>[\$EVENT] eq \"state:on\" würde den Kommandozweig nur dann ausführen, wenn der auslösende Trigger \"state:on\" war.<br>Wichtig ist dieses, wenn bei den Triggerdetails nicht schon auf ein bestimmtes Event getriggert wird, sondern hier durch die Nutzung eines wildcards (*) auf alle Events getriggert wird, oder auf alle Events eines Readings z.B. (state:*)<br><br>Bei eingestellter Delayfunktion werden die Bedingungen je nach Einstellung sofort,verzögert oder sowohl-als-auch überprüft, d.H hiermit sind verzögerte Ein-, und Ausschaltbefehle möglich die z.B Nachlauffunktionen oder verzögerte Einschaltfunktionen ermöglichen, die sich selbst überprüfen. z.B. [wenn Licht im Bad an -> schalte Lüfter 2 Min später an -> nur wenn Licht im Bad noch an ist]<br><br>Anstatt einer Verzögerung kann hier auch eine festgelegte Schaltzeit erfolgen.';}
					   
	if (from == 'onoff'){
	text = text +  'Einstellung des auzuführenden Kommandos bei entsprechendem getriggerten Event.<br>Bei angebotenen Zusatzfeldern kann ein Verweis auf ein Reading eines anderen Devices gesetzt werden mit [Device:Reading].<br>\$NAME wird ersetzt durch den Namen des triggernden Devices.<br><br>Bei Nutzung von FreeCmd kann hier entweder reiner FhemCode, oder reiner Perlcode verwendet werden. Perlcode muss mit geschweiften Klammern beginnen und enden. Das Mischen beider Codes ist nicht zulässig.';}
					   
	if (from == 'affected'){
	text = text + 'Einstellung der Geräte, die auf ein Event oder zu einer bestimmten Zeit reagieren sollen.<br>Die Auswahl von FreeCmd ermöglicht eine deviceungebundene Befehlseingabe oder die Eingabe von reinem Perlcode.';}

	if (from == 'repeats'){
	text = text + 'Eingabe von Befehlswiederholungen.<br>Bei Belegung der Felder wird ein Befehl um die Angabe \"Repeats\" mit der jeweiligen Verzögerung \"Repeatdelay in sec\" wiederholt.<br>In dem Feld \"Repeats\" ist eine Angabe im \"setmagic\"-Format möglich.';}

	if (from == 'priority'){
	text = text + 'priority - Auswahl der Reihenfolge der Befehlsabarbeitung. Ein Befehl mit der Nr. 1 wird als erstes ausgeführt , die höchste Nummer zuletzt.<br> Sollte mehrere Befehle die gleiche Nummer haben , so werden diese Befehle in dargestellter Reihenfolge ausgeführt.<br><br>ID - Devices denen eine ID zugewiesen ist , werden in der normalen abarbeitung der Befehle nicht mehr berücksichtigt und somit nicht ausgeführt. Wenn eine ID-Zuweisung erfolgt ist, kann dieser Befehlszweig nur noch über das cmd set DEVICE ID NR on/off erfolgen. Diese Option wird nur in Ausnahmefällen benötigt , wenn die Pipes nicht ausrechend sind um verschiedene Aktionen unter verschiedenen Bedingungen auszuführen. ';}

	if (from == 'saveevent'){
	text = text + 'Bei Anwahl dieser Option werden alle eingehenden Events des ausgewählten Triggerdevices gespeichert und sind in den Auswahlfeldern \"execute cmd1\" und \"execute cmd2\" sowie in allen \"Test-Condition\" zur Auswahl verfügbar.<br>Diese Auswahl sollte zur Resourcenschonung nach der Einrichtung des MSwitchdevices abgewählt werden , da hier je nach Trigger erhebliche Datenmengen anfallen können und gespeichert werden.';}
	
	if (from == 'execcmd'){
	text = text + 'In diesem Feld wird das Event bestimmt, welches zur Ausführung des cmd Zweiges 1 oder 2 führt. Hier stehen entweder gespeicherte Events zur Verfügung ( wenn \"Save incomming events\" aktiviert ist ) , oder es können mit \"Add event manually\" Events hinzugefügt werden. ';}

	
	var textfinal =\"<div style ='font-size: small;'>\"+ text +\"</div>\";
	FW_okDialog(textfinal);
	return;
	}";
	}
	
	$j1 .= "
	function aktvalue(target,cmd){
	document.getElementById(target).value = cmd; 
	return;
	}

	function noarg(target,copytofield){
	document.getElementById(copytofield).value = '';
	document.getElementById(target).innerHTML = '';
	return;
	}
					   
	function noaction(target,copytofield){
	document.getElementById(copytofield).value = '';
	document.getElementById(target).innerHTML = '';
	return;}

	function slider(first,step,last,target,copytofield){
	var selected =document.getElementById(copytofield).value;
	var selectfield = \"&nbsp;<br><input type='text' id='\" + target +\"_opt' size='3' value='' readonly>&nbsp;&nbsp;&nbsp;\" + first +\"<input type='range' min='\" + first +\"' max='\" + last + \"' value='\" + selected +\"' step='\" + step + \"' onchange=\\\"javascript: showValue(this.value,'\" + copytofield + \"','\" + target + \"')\\\">\" + last  ;
	document.getElementById(target).innerHTML = selectfield + '<br>';
	var opt = target + '_opt';
	document.getElementById(opt).value=selected;
	return;
	}

	function showValue(newValue,copytofield,target){
	var opt = target + '_opt';
	document.getElementById(opt).value=newValue;
	document.getElementById(copytofield).value = newValue;
	}

	function showtextfield(newValue,copytofield,target){
	document.getElementById(copytofield).value = newValue;
	}

	function textfield(copytofield,target){
	//alert(copytofield,target);
	var selected =document.getElementById(copytofield).value;
	if (copytofield.indexOf('cmdonopt') != -1) {

	var selectfield = \"&nbsp;<br><input type='text' size='30' value='\" + selected +\"' onchange=\\\"javascript: showtextfield(this.value,'\" + copytofield + \"','\" + target + \"')\\\">\"  ;
	document.getElementById(target).innerHTML = selectfield + '<br>';	
	}
	else{
	var selectfield = \"<input type='text' size='30' value='\" + selected +\"' onchange=\\\"javascript: showtextfield(this.value,'\" + copytofield + \"','\" + target + \"')\\\">\"  ;
	document.getElementById(target).innerHTML = selectfield + '<br>';
	}

	return;
	}

	function selectfield(args,target,copytofield){
	var cmdsatz = args.split(\",\");
	var selectstart = \"<select id=\\\"\" +target +\"1\\\" name=\\\"\" +target +\"1\\\" onchange=\\\"javascript: aktvalue('\" + copytofield + \"',document.getElementById('\" +target +\"1').value)\\\">\"; 
	var selectend = '<\\select>';
	var option ='<option value=\"noArg\">noArg</option>'; 
	var i;
	var len = cmdsatz.length;
	var selected =document.getElementById(copytofield).value;
	for (i=0; i<len; i++){
	if (selected == cmdsatz[i]){
	option +=  '<option selected value=\"' + cmdsatz[i] + '\">' + cmdsatz[i] + '</option>';
	}
	else{
	option +=  '<option value=\"' + cmdsatz[i] + '\">' + cmdsatz[i] + '</option>';
	}
	}
	var selectfield = selectstart + option + selectend;
	document.getElementById(target).innerHTML = selectfield + '<br>';	
	return;
	}


	function activate(state,target,options,copytofield) ////aufruf durch selctfield
	{

	var globaldetails3='undefined';
	var x = document.getElementsByClassName('devdetails2');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	globaldetails3 +=document.getElementById(t).value;
	
	}
	

	if ( globaldetails2 )
	{
	if (globaldetails3 != globaldetails2)
	{
	globallock =' unsaved device actions';
		[ \"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\",\"aw_dev\"].forEach (lock,);
		randomdev.forEach (lock);
	
	}
	else
	{
	[ \"aw_trig\",\"aw_md1\",\"aw_md2\",\"aw_addevent\",\"aw_dev\"].forEach (unlock,);
			randomdev.forEach (unlock);
	}
	}
	

	var ausgabe = target + '<br>' + state + '<br>' + options;
	if (state == 'no_action'){noaction(target,copytofield);return}
	var optionarray = options.split(\" \");
	var werte = new Array();
	for (var key in optionarray )
	{
	var satz = optionarray[key].split(\":\");
	werte[satz[0]] = satz[1];
	}
	var devicecmd = new Array();
	if (typeof werte[state] === 'undefined') {werte[state]='textField';}
	devicecmd = werte[state].split(\",\");
	if (devicecmd[0] == 'noArg'){noarg(target,copytofield);return;}
	//else if (devicecmd[0] == 'slider'){slider(devicecmd[1],devicecmd[2],devicecmd[3],target,copytofield);return;}

	else if (devicecmd[0] == 'slider'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'undefined'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'textField'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'colorpicker'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'RGB'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'no_Action'){noaction();return;}
	else {selectfield(werte[state],target,copytofield);return;}
	
	return;
	}


	function addevice(device){
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" add_device \"+device;
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}

	function deletedevice(device){
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" del_device \"+device;
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	}
	";
    $j1 .=
	"var t=\$(\"#MSwitchWebTR\"), ip=\$(t).attr(\"ip\"), ts=\$(t).attr(\"ts\");
	FW_replaceWidget(\"[name=aw_ts]\", \"aw_ts\", [\"time\"], \"12:00\");
	\$(\"[name=aw_ts] input[type=text]\").attr(\"id\", \"aw_ts\");
	   
	// modify trigger aw_save
	\$(\"#aw_md\").click(function(){
	var nm = \$(t).attr(\"nm\");
	trigon = \$(\"[name=trigon]\").val();
	trigon = trigon.replace(/ /g,'~');
	trigoff = \$(\"[name=trigoff]\").val();
	trigoff = trigoff.replace(/ /g,'~');
	trigcmdon = \$(\"[name=trigcmdon]\").val();
	trigcmdon = trigcmdon.replace(/ /g,'~');
	trigcmdoff = \$(\"[name=trigcmdoff]\").val();
	trigcmdoff = trigcmdoff.replace(/ /g,'~');
	trigsave = \$(\"[name=aw_save]\").prop(\"checked\") ? \"ja\":\"nein\";
	trigwhite = \$(\"[name=triggerwhitelist]\").val();
	if (trigcmdon == trigon  && trigcmdon != 'no_trigger' && trigon != 'no_trigger'){
	FW_okDialog('on triggers for \\'switch Test on + execute on commands\\' and \\'execute on commands only\\' may not be the same !');
	return;
	} 
	if (trigcmdoff == trigoff && trigcmdoff != 'no_trigger' && trigoff != 'no_trigger'){
	FW_okDialog('off triggers for \\'switch Test off + execute on commands\\' and \\'execute off commands only\\' may not be the same !');
	return;
	} 
	if (trigon == trigoff && trigon != 'no_trigger'){
	FW_okDialog('trigger for \\'switch Test on + execute on commands\\' and \\'switch Test off + execute off commands\\' must not both be \\'*\\'');
	return;
	} 

	var  def = nm+\" trigger \"+trigon+\" \"+trigoff+\" \"+trigsave+\" \"+trigcmdon+\" \"+trigcmdoff+\" \"  ;
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		
	//delete trigger
	\$(\"#aw_md2\").click(function(){
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" del_trigger \";
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		
	//aplly filter to trigger
	\$(\"#aw_md1\").click(function(){
	var nm = \$(t).attr(\"nm\");
	var  def = nm+\" filter_trigger \";
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});

	\$(\"#aw_trig\").click(function(){
	var nm = \$(t).attr(\"nm\");
	trigdev = \$(\"[name=trigdev]\").val();
	//trigdev = trigdev.replace(/\:/g,'#[dp]');
	//alert(trigdev);
	
	
	timeon =  \$(\"[name=timeon]\").val();
	timeoff =  \$(\"[name=timeoff]\").val();
	timeononly =  \$(\"[name=timeononly]\").val();
	timeoffonly =  \$(\"[name=timeoffonly]\").val();
	

	trigdevcond = \$(\"[name=triggercondition]\").val();
	
	//trigdevcond = trigdevcond.replace(/:/g,'#[dp]');
	
	trigdevcond = trigdevcond.replace(/\\./g,'#[pt]');
	trigdevcond = trigdevcond.replace(/:/g,'#[dp]');
	trigdevcond= trigdevcond.replace(/~/g,'#[ti]');
	//trigdevcond = trigdevcond.replace(/ /g,'~');
	trigdevcond = trigdevcond.replace(/ /g,'#[sp]');
	
	trigdevcond = trigdevcond+':';
	
	
	
	timeon = timeon.replace(/ /g, '');
	timeoff = timeoff.replace(/ /g, '');
	timeononly = timeononly.replace(/ /g, '');
	timeoffonly = timeoffonly.replace(/ /g, '');
	
	timeon = timeon.replace(/:/g, '#[dp]');
	timeoff = timeoff.replace(/:/g, '#[dp]');
	timeononly = timeononly.replace(/:/g, '#[dp]');
	timeoffonly = timeoffonly.replace(/:/g, '#[dp]');
	
	
	timeon = timeon+':';
	timeoff = timeoff+':';
	timeononly = timeononly+':';
	timeoffonly = timeoffonly+':';
	
	
	//alert(timeon);
	
	trigwhite = \$(\"[name=triggerwhitelist]\").val();
	var  def = nm+\" set_trigger  \"+trigdev+\" \"+timeon+\" \"+timeoff+\" \"+timeononly+\" \"+timeoffonly+\" \"+trigdevcond+\" \"+trigwhite+\" \" ;
	
	//alert(def);
	def =  encodeURIComponent(def);
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		
	\$(\"#aw_addevent\").click(function(){
	var nm = \$(t).attr(\"nm\");
	event = \$(\"[name=add_event]\").val();
	event= event.replace(/ /g,'~');
	event= event.replace(/\\|/g,'[bs]');
	if (event == ''){
	//alert('no event specified');
	return;
	}	  
	var  def = nm+\" addevent \"+event+\" \";
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		
	\$(\"#aw_dev\").click(function(){
	var nm = \$(t).attr(\"nm\");
	devices = \$(\"[name=affected_devices]\").val();
	var  def = nm+\" devices \"+devices+\" \";
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		

		
	\$(\"#aw_det\").click(function(){
	var nm = \$(t).attr(\"nm\");
	devices = '';
	$javaform

	devices = devices.replace(/:/g,'#[dp]');
	devices = devices.replace(/;/g,'#[se]');
	devices = devices.replace(/ /g,'#[sp]');
	devices =  encodeURIComponent(devices);

	var  def = nm+\" details \"+devices+\" \";
	
	location = location.pathname+\"?detail=" . $Name . "&cmd=set \"+addcsrf(def);
	});
		
	function  switchlock(){	
	test = document.getElementById('lockedit').checked ;	
	if (test){
	\$(\"#devices\").prop(\"disabled\", 'disabled');
	document.getElementById('aw_great').value='edit list';
	}
	else{
	\$(\"#devices\").prop(\"disabled\", false);
	document.getElementById('aw_great').value='schow greater list';
	}
	}
	
	function  deviceselect(){
	sel ='<div style=\"white-space:nowrap;\"><br>';
	var ausw=document.getElementById('devices');
	for (i=0; i<ausw.options.length; i++)
	{
	var pos=ausw.options[i];
	if(pos.selected)
	{
	//targ.options[i].selected = true;
	sel = sel+'<input id =\"Checkbox-'+i+'\" checked=\"checked\" name=\"Checkbox-'+i+'\" type=\"checkbox\" value=\"test\" /> '+pos.value+'<br />';
	}
	else 
	{
	sel = sel+'<input id =\"Checkbox-'+i+'\" name=\"Checkbox-'+i+'\" type=\"checkbox\" /> '+pos.value+'<br />';
	}
	} 
	sel = sel+'</div>';
	FW_okDialog(sel,'',removeFn) ; 
	}
	
	function bigwindow(targetid){	
	targetval =document.getElementById(targetid).value;
	sel ='<div style=\"white-space:nowrap;\"><br>';
	sel = sel+'<textarea id=\"valtrans\" cols=\"80\" name=\"TextArea1\" rows=\"10\" onChange=\" document.getElementById(\\\''+targetid+'\\\').value=this.value; \">'+targetval+'</textarea>';
	sel = sel+'</div>';
	FW_okDialog(sel,''); 
	}	
	


	function removeFn() {
    var targ = document.getElementById('devices');
    for (i = 0; i < targ.options.length; i++) {
    test = document.getElementById('Checkbox-' + i).checked;
    targ.options[i].selected = false;
    if (test) {
    targ.options[i].selected = true;
    }
    }
	}
	
	\$(\"#aw_little\").click(function(){
	var veraenderung = 3; // Textfeld veraendert sich stets um 3 Zeilen
	var sel = document.getElementById('textfie').innerHTML;
	var show = document.getElementById('textfie2');
	var2 = \"size=\\\"6\\\"\";
	var result = sel.replace(/size=\\\"15\\\"/g,var2);
	document.getElementById('textfie').innerHTML = result;      
	});

	}
	</script>";
    return "$ret<br>$detailhtml<br>$j1";
} 

####################

sub MSwitch_makeCmdHash($) {
    my $loglevel = 5;
    my ($Name) = @_;

    # detailsatz in scalar laden
	my @devicedatails ;
	@devicedatails = split( /#\[ND\]/, ReadingsVal( $Name, '.Device_Affected_Details', 'no_device' ) ) if defined ReadingsVal( $Name, '.Device_Affected_Details', 'no_device');#inhalt decice und cmds durch komma getrennt
  
    my %savedetails;
    foreach (@devicedatails) 
	{
	
	
	 	#	ersetzung 
		$_ =~ s/#\[sp\]/ /g;
		$_ =~ s/#\[nl\]/\n/g;
		$_ =~ s/#\[se\]/;/g;
		$_ =~ s/#\[dp\]/:/g;
		$_ =~ s/\(DAYS\)/|/g;
	    $_ =~ s/#\[ko\]/,/g; #neu
		$_ =~ s/#\[bs\]/\\/g; #neu
	
        my @detailarray = split( /#\[NF\]/, $_ );    #enthält daten 0-5 0 - name 1-5 daten 7 und9 sind zeitangaben

        my $key = '';
        my $testtimestroff = $detailarray[7];
        $key = $detailarray[0] . "_delayatonorg";
        $savedetails{$key} = $detailarray[7];

        if ( $testtimestroff ne '[random]' )
		{
            $testtimestroff =~ s/[A-Za-z0-9#\.\-_]//g;
			
			
			
			#Log3( $Name, 0,"testtimestron -> $testtimestroff" . __LINE__ );
			
			
            if ( $testtimestroff ne "[:]" && $testtimestroff ne "[\$:]" ) 
			{
                my $hdel = ( substr( $detailarray[7], 0, 2 ) ) * 3600;
                my $mdel = ( substr( $detailarray[7], 3, 2 ) ) * 60;
                my $sdel = ( substr( $detailarray[7], 6, 2 ) ) * 1;
                $detailarray[7] = $hdel + $mdel + $sdel;
            }
        }

		
        my $testtimestron = $detailarray[8];
        $key = $detailarray[0] . "_delayatofforg";
        $savedetails{$key} = $detailarray[8];

        if ( $testtimestron ne '[random]' ) 
		{
            $testtimestron =~ s/[A-Za-z0-9#\.\-_]//g;
			

            if ( $testtimestron ne "[:]" && $testtimestroff ne "[\$:]" ) 
			{
                my $hdel = substr( $detailarray[8], 0, 2 ) * 3600;
                my $mdel = substr( $detailarray[8], 3, 2 ) * 60;
				
				
                my $sdel = substr( $detailarray[8], 6, 2 ) * 1;

				$detailarray[8] = $hdel + $mdel + $sdel;

            }
        }


        $key               = $detailarray[0] . "_on";
        $savedetails{$key} = $detailarray[1];
        $key               = $detailarray[0] . "_off";
        $savedetails{$key} = $detailarray[2];
        $key               = $detailarray[0] . "_onarg";
        $savedetails{$key} = $detailarray[3];
        $key               = $detailarray[0] . "_offarg";
        $savedetails{$key} = $detailarray[4];
        $key               = $detailarray[0] . "_delayaton";
        $savedetails{$key} = $detailarray[5];
        $key               = $detailarray[0] . "_delayatoff";
        $savedetails{$key} = $detailarray[6];
        $key               = $detailarray[0] . "_timeon";
        $savedetails{$key} = $detailarray[7];
        $key               = $detailarray[0] . "_timeoff";
        $savedetails{$key} = $detailarray[8];
        $key = $detailarray[0] . "_repeatcount";
		
        if ( defined $detailarray[11] ) 
		{
		
            $savedetails{$key} = $detailarray[11];
        }
        else 
		{
            $savedetails{$key} = 0;
        }

        $key = $detailarray[0] . "_repeattime";
        if ( defined $detailarray[12] ) 
		{
            $savedetails{$key} = $detailarray[12];
        }
        else 
		{
            $savedetails{$key} = 0;
        }
		
		
		 $key = $detailarray[0] . "_priority";
        if ( defined $detailarray[13] ) 
		{
            $savedetails{$key} = $detailarray[13];
        }
        else 
		{
            $savedetails{$key} = 1;
        }

		
			 $key = $detailarray[0] . "_id";
        if ( defined $detailarray[14] ) 
		{
            $savedetails{$key} = $detailarray[14];
        }
        else 
		{
            $savedetails{$key} = 0;
        }
		

        $key = $detailarray[0] . "_conditionon";

        if ( defined $detailarray[9] )
		{

        $savedetails{$key} = $detailarray[9];
        }
        else 
		{
            $savedetails{$key} = '';
        }
        $key = $detailarray[0] . "_conditionoff";
		
        if ( defined $detailarray[10] ) 
		{

        $savedetails{$key} = $detailarray[10];
        }
        else 
		{
            $savedetails{$key} = '';
        }
    }
	
    my @pass = %savedetails;
    return @pass;
}
########################################

sub MSwitch_Delete_Triggermemory($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
    my $events = ReadingsVal( $Name, '.Device_Events', '' );
  #  my @eventsall     = split( /#\[tr\]/, $events );
    my $Triggerdevice = $hash->{Trigger_device};
    my $triggeron     = ReadingsVal( $Name, '.Trigger_on', 'no_trigger' );
    if ( !defined $triggeron ) { $triggeron = "" }
    my $triggeroff = ReadingsVal( $Name, '.Trigger_off', 'no_trigger' );
    if ( !defined $triggeroff ) { $triggeroff = "" }
    my $triggercmdon = ReadingsVal( $Name, '.Trigger_cmd_on', 'no_trigger' );
    if ( !defined $triggercmdon ) { $triggercmdon = "" }
    my $triggercmdoff = ReadingsVal( $Name, '.Trigger_cmd_off', 'no_trigger' );
    if ( !defined $triggercmdoff ) { $triggercmdoff = "" }
    my $triggerdevice = ReadingsVal( $Name, 'Trigger_device', '' );
    delete( $hash->{helper}{events} );
    $hash->{helper}{events}{$triggerdevice}{'no_trigger'}   = "on";
    $hash->{helper}{events}{$triggerdevice}{$triggeron}     = "on";
    $hash->{helper}{events}{$triggerdevice}{$triggeroff}    = "on";
    $hash->{helper}{events}{$triggerdevice}{$triggercmdon}  = "on";
    $hash->{helper}{events}{$triggerdevice}{$triggercmdoff} = "on";
    readingsSingleUpdate( $hash, ".Device_Events", 'no_trigger', 1 );
    my $eventhash = $hash->{helper}{events}{$triggerdevice};
    $events = "";
    foreach my $name ( keys %{$eventhash} )
	{
		$name =~ s/#\[tr//ig;
        $events = $events . $name . '#[tr]';
    }
    chop($events);
	chop($events);
	chop($events);
	chop($events);
	chop($events);
	
    readingsSingleUpdate( $hash, ".Device_Events", $events, 0 );
    return;
}
###########################################################################
sub MSwitch_Exec_Notif($$$$$) {
#Inhalt Übergabe ->  push @cmdarray, $own_hash . ',on,check,' . $eventcopy1
    my ( $hash, $comand, $check, $event,$execids ) = @_;
    my $name      = $hash->{NAME};
    my $protokoll = '';
    my $satz;
	
	
	$execids = "0";
	
	
	MSwitch_LOG( $name, 5,"$name:     execnotif -> $hash, $comand, $check, $event,$execids  ");
	
    #### teste auf condition nur wenn nicht von timer
	return "" if ( IsDisabled($name) );# Return without any further action if the module is disabled

    if ( $check ne 'nocheck' ) 
	{
        my $triggercondition = ReadingsVal( $name, '.Trigger_condition', '' );

# achtung format change		
		
		$triggercondition =~ s/#\[dp\]/:/g;
		$triggercondition =~ s/#\[pt\]/./g;
		$triggercondition =~ s/#\[ti\]/~/g;
		$triggercondition =~ s/#\[sp\]/ /g;
		
        if ( $triggercondition ne '' ) 
		{
		MSwitch_LOG( $name, 5,"$name:     check triggercondition -> ");
            my $ret = MSwitch_checkcondition( $triggercondition, $name, '' );
		MSwitch_LOG( $name, 5,"$name:     ergebniss triggercondition -> ".$ret);	
            if ( $ret eq 'false' ) 
			{
			MSwitch_LOG( $name, 5,"$name:     ergebniss triggercondition false -> abbruch");
                return;
            }
        }
    }

    
    my %devicedetails = MSwitch_makeCmdHash($name);

    # betroffene geräte suchen
    my @devices    = split( /,/, ReadingsVal( $name, '.Device_Affected', 'no_device' ) );
    my $update     = '';
    my $testtoggle = '';
	
	MSwitch_LOG( $name, 5,"$name:     zu schaltende devices -> ".@devices);
	
	
	# liste nach priorität ändern , falls expert
	@devices = MSwitch_priority($hash,$execids,@devices);
	
    foreach my $device (@devices)
	{
		if ( AttrVal( $name, 'MSwitch_Delete_Delays', '0' ) eq '1' ) 
		{
			MSwitch_Delete_Delay( $hash, $device );
		}

        my @devicesplit = split( /-AbsCmd/, $device );
        my $devicenamet = $devicesplit[0];

        # teste auf on kommando
        my $key      = $device . "_" . $comand;
        my $timerkey = $device . "_time" . $comand;
        my $testtstate = $devicedetails{$timerkey};
		
#MSwitch_LOG( $name, 0,"$name: testtstat1e -> ".$testtstate);		
        $testtstate =~ s/[A-Za-z0-9#\.\-_]//g;
#MSwitch_LOG( $name, 0,"$name:testtstate2 -> ".$testtstate);



             if ( $testtstate eq "[:]" || $testtstate eq "[\$:]") 
		{
		
            $devicedetails{$timerkey} =
            eval MSwitch_Checkcond_state( $devicedetails{$timerkey}, $name );
			
			
			
	if ($devicedetails{$timerkey} =~ m/[0-9]\d:[0-9]\d:[0-9]\d/)
	{
	MSwitch_LOG( $name, 5,"$name:   format ok ");
	
	  my $hdel = ( substr( $devicedetails{$timerkey}, 0, 2 ) ) * 3600;
      my $mdel = ( substr( $devicedetails{$timerkey}, 3, 2 ) ) * 60;
      my $sdel = ( substr( $devicedetails{$timerkey}, 6, 2 ) ) * 1;
      $devicedetails{$timerkey} = $hdel + $mdel + $sdel;
			
			
	}	
	else 
	{
	MSwitch_LOG( $name, 1,"$name: ERROR Timerformat ".$devicedetails{$timerkey}." fehlerhaf ");
	$devicedetails{$timerkey} = 0;
	}
			
			
			
          
        }
		MSwitch_LOG( $name, 5,"$name:     timer des devices -> ".$devicedetails{$timerkey});
        # teste auf condition
        # antwort $execute 1 oder 0 ;

        my $conditionkey = $device . "_condition" . $comand;
        if ( $devicedetails{$key} ne "" && $devicedetails{$key} ne "no_action" )
        {
            my $cs = '';
            if ( $devicenamet eq 'FreeCmd' )
			{
                $cs = "  $devicedetails{$device.'_'.$comand.'arg'}";
				$cs = MSwitch_makefreecmd($hash,$cs);
            }
            else 
			{
                $cs ="set $devicenamet $devicedetails{$device.'_'.$comand} $devicedetails{$device.'_'.$comand.'arg'}";
            }

			
            #Variabelersetzung
            $cs =~ s/\$NAME/$hash->{helper}{eventfrom}/;
			$cs =~ s/\$SELF/$name/;
			
			
            if (   $devicedetails{$timerkey} eq "0" || $devicedetails{$timerkey} eq "" )
            {
                # teste auf condition
                # antwort $execute 1 oder 0 ;
                $conditionkey = $device . "_condition" . $comand;
                my $execute = MSwitch_checkcondition( $devicedetails{$conditionkey}, $name, $event );
                $testtoggle = 'undef';
                if ( $execute eq 'true' ) 
				{
                    $testtoggle = $cs;
                    #############
                    Log3( $name, 3,"$name MSwitch_Restartcm: Befehlsausfuehrung -> $cs ". __LINE__ );
                    my $toggle = '';
                    if ( $cs =~ m/set (.*)(MSwitchtoggle)(.*)/ ) 
					{
                        $toggle = $cs;
                        $cs = MSwitch_toggle( $hash, $cs );
                    }
				MSwitch_LOG( $name, 5,"$name:     auszufuehrender Befehl -> ".$cs);
# neu
				$devicedetails{ $device . '_repeatcount' } = 0 if !defined $devicedetails{ $device . '_repeatcount' };
				$devicedetails{ $device . '_repeattime' } = 0 if !defined $devicedetails{ $device . '_repeattime' };
					
					
				MSwitch_LOG( $name, 5,"$name:     teste auf repeasts ");	
				my $x =0;
				while ( $devicedetails{ $device . '_repeatcount' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # exit
					last if $x > 20;             # exit
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeatcount' } = $setmagic
					}
					
					 $x =0;
				while ( $devicedetails{ $device . '_repeattime' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # exit
					last if $x > 20;             # exit
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeattime' } = $setmagic
					}	
					

					if ($devicedetails{ $device . '_repeatcount' } eq  "") {$devicedetails{ $device . '_repeatcount' } = 0};
					if ($devicedetails{ $device . '_repeattime' } eq  "") {$devicedetails{ $device . '_repeattime' } = 0};
					
					MSwitch_LOG( $name, 5,"$name:     anzahl repeats -> ".$devicedetails{ $device . '_repeatcount' });
					MSwitch_LOG( $name, 5,"$name:     delay repeats -> ".$devicedetails{ $device . '_repeattime' });
					
                    if (   AttrVal( $name, 'MSwitch_Expert', "0" ) eq '1' && $devicedetails{ $device . '_repeatcount' } > 0 && $devicedetails{ $device . '_repeattime' } > 0 )
                    {
                        my $i;
                        for ( $i = 0 ;$i <= $devicedetails{ $device . '_repeatcount' }; $i++)
                        {
                            my $msg = $cs . "|" . $name;
                            if ( $toggle ne '' )
							{
                                $msg = $toggle . "|" . $name;
                            }
                            my $timecond =gettimeofday() +( ( $i + 1 ) * $devicedetails{ $device . '_repeattime' } );
							$msg = $msg.",".$timecond;
							$hash->{helper}{repeats}{$timecond} = "$msg";
							
							MSwitch_LOG( $name, 5,"$name:     repeat gesetzt -> ".$timecond." ".$msg);
                            InternalTimer( $timecond, "MSwitch_repeat", $msg );
                        }
                    }

					my $todec = $cs;
					$cs = MSwitch_dec($hash,$todec);
                    ############################
					
					if ( AttrVal( $name, 'MSwitch_Debug', "0" ) eq '2' )
					{
					MSwitch_LOG( $name, 5,"$name:     execute -> ".$cs);
					}
					else{
					
                    if ( $cs =~ m/{.*}/ ) 
					{
                        eval($cs);
                        if ($@) 
						{
                            Log3( $name, 1,"$name MSwitch_Set: ERROR $cs: $@ ". __LINE__ );
                        }
                    }
                    else
					{
					
					
                        my $errors = AnalyzeCommandChain( undef, $cs );
                        if ( defined($errors) ) 
						{
                            Log3( $name, 1,"$name Absent_Exec_Notif $comand: ERROR $device: $errors -> Comand: $cs" );
                        }
                    }
					}

                    my $msg = $cs;
					if (length($msg) > 100 ){ $msg = substr($msg,0,100).'....';}
                    readingsSingleUpdate( $hash, "Exec_cmd", $msg, 1 ) if $msg ne '';
                   
                }
            }
            else 
			{
			# ################### magictimer
				# my $x = 0;
				# while ( $devicedetails{$timerkey} =~ m/(.*?)(\$SELF)(.*)?/)
				# {
				# my $firstpart = $1;
				# my $secondpart = $2;
				# my $lastpart = $3;
				# $devicedetails{$timerkey} = $firstpart.$name.$lastpart;
				# $x++;
				# last if $x > 10;    #notausstieg
				# }
			    # # setmagic ersetzun
				# MSwitch_LOG( $name, 5, "vor freecmd: ".$cs );	
				# $x =0;
				# while ( $devicedetails{$timerkey} =~ m/(.*)\[(.*)\:(.*)\](.*)/ ) 
					# {
					# $x++;                        # notausstieg notausstieg
					# last if $x > 20;             # notausstieg notausstieg
					# my $setmagic = ReadingsVal( $2, $3, 0 );
					# $devicedetails{$timerkey} = $1.$setmagic.$4;
					# }
			###################
			
			
                if ( AttrVal( $name, 'MSwitch_RandomTime', '' ) ne ''&& $devicedetails{$timerkey} eq '[random]' )
                {
                    $devicedetails{$timerkey} =
                    MSwitch_Execute_randomtimer($hash);
                    # ersetzt $devicedetails{$timerkey} gegen randomtimer
                }
                elsif ( AttrVal( $name, 'MSwitch_RandomTime', '' ) eq '' && $devicedetails{$timerkey} eq '[random]' )
                {
                    $devicedetails{$timerkey} = 0;
                }
                my $timecond = gettimeofday() + $devicedetails{$timerkey};
                my $delaykey     = $device . "_delayat" . $comand;
                my $delayinhalt  = $devicedetails{$delaykey};
                my $delaykey1    = $device . "_delayat" . $comand . "org";
                my $teststateorg = $devicedetails{$delaykey1};
	 
				$conditionkey = $device . "_condition" . $comand;
				my $execute = "true";
				
				if ($delayinhalt ne "delay2" && $delayinhalt ne "at02")
					{
					$execute =  MSwitch_checkcondition( $devicedetails{$conditionkey}, $name, $event);
					}

				
				if ($execute eq "true")
				{	
					if ( $delayinhalt eq 'at0' || $delayinhalt eq 'at1' ) 
					{
						$timecond = MSwitch_replace_delay( $hash, $teststateorg );
					}

					if ( $delayinhalt eq 'at1' || $delayinhalt eq 'delay0' ) 
					{
						$conditionkey = "nocheck";
					}
				
				
					$cs =~ s/,/##/g;
					my $msg =
						$cs . "#[tr]"
					  . $name . "#[tr]"
					  . $conditionkey . "#[tr]"
					  . $event . "#[tr]"
					  . $timecond . "#[tr]"
					  . $device;
					$hash->{helper}{delays}{$msg} = $timecond;
					$testtoggle = 'undef';
					
					
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt -> ".$cs);
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt name -> ".$name);
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt conditionkey-> ".$conditionkey);
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt event-> ".$event);
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt timecond-> ".$timecond);
					MSwitch_LOG( $name, 5,"$name:     timer gesetzt -> device ".$device);
					InternalTimer( $timecond, "MSwitch_Restartcmd", $msg );
				}
            }
        }
        if ( $testtoggle ne ''  && $testtoggle ne 'undef' )
        {
            $satz .= $testtoggle . ',';
        }
    }
    return $satz;
}
####################
sub MSwitch_Filter_Trigger($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
    if ( !exists $hash->{Trigger_device} ) { return; }    #CHANGE
    my $Triggerdevice = $hash->{Trigger_device};
    my $triggeron = ReadingsVal( $Name, '.Trigger_on', 'no_trigger' );
    if ( !defined $triggeron ) { $triggeron = "" }
    my $triggeroff = ReadingsVal( $Name, '.Trigger_off', 'no_trigger' );
    if ( !defined $triggeroff ) { $triggeroff = "" }
    my $triggercmdon = ReadingsVal( $Name, '.Trigger_cmd_on', 'no_trigger' );
    if ( !defined $triggercmdon ) { $triggercmdon = "" }
    my $triggercmdoff = ReadingsVal( $Name, '.Trigger_cmd_off', 'no_trigger' );
    if ( !defined $triggercmdoff ) { $triggercmdoff = "" }
    my $triggerdevice = ReadingsVal( $Name, 'Trigger_device', '' );
    delete( $hash->{helper}{events}{$Triggerdevice} );
    $hash->{helper}{events}{$Triggerdevice}{'no_trigger'}   = "on";
    $hash->{helper}{events}{$Triggerdevice}{$triggeron}     = "on";
    $hash->{helper}{events}{$Triggerdevice}{$triggeroff}    = "on";
    $hash->{helper}{events}{$Triggerdevice}{$triggercmdon}  = "on";
    $hash->{helper}{events}{$Triggerdevice}{$triggercmdoff} = "on";
    my $events = ReadingsVal( $Name, '.Device_Events', '' );
    my @eventsall = split( /#\[tr\]/, $events );
	EVENT: foreach my $eventcopy (@eventsall) 
	{
        my @filters =split( /,/, AttrVal( $Name, 'MSwitch_Trigger_Filter', '' ) ) ;# beinhaltet filter durch komma getrennt
        foreach my $filter (@filters) 
		{
            my $wildcarttest = index( $filter, "*", 0 );
            if ( $wildcarttest > -1 )    ### filter auf wildcart
            {
                $filter = substr( $filter, 0, $wildcarttest );
                my $testwildcart = index( $eventcopy, $filter, 0 );
                if ( $testwildcart eq '0' ) 
				{
                    next EVENT;
                }
            }
            else### filter genauen ausdruck
            {
                if ( $eventcopy eq $filter ) 
				{
                    next EVENT;
                }
            }
        }
        $hash->{helper}{events}{$Triggerdevice}{$eventcopy} = "on";
    }
    my $eventhash = $hash->{helper}{events}{$Triggerdevice};
    $events = "";
    foreach my $name ( keys %{$eventhash} ) 
	{
        $events = $events . $name . '#[tr]';
    }
    chop($events);
	chop($events);
	chop($events);
	chop($events);
	chop($events);
    readingsSingleUpdate( $hash, ".Device_Events", $events, 0 );
    return;
}
####################
sub MSwitch_Restartcmd($) {
    my $incomming = $_[0];
    my @msgarray = split( /#\[tr\]/, $incomming );
    my $name = $msgarray[1];
	
	return "" if ( IsDisabled($name) );
	
	
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	MSwitch_LOG( $name, 5, "$name: aufruf restartcmd -> ".$incomming  ); 
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	
	
	
	# checke versionskonflikt der datenstruktur
	if ( ReadingsVal( $name, '.V_Check', $vupdate ) ne $vupdate )
	{
	my $ver = ReadingsVal( $name, '.V_Check', '' );
	MSwitch_LOG( $name, 5, "$name: Versionskonflikt - aktion abgebrochen");
	return;
	}
		
    my $cs   = $msgarray[0];
    #$cs =~ s/##/,/g;
    my $conditionkey = $msgarray[2];
    my $event        = $msgarray[2];
    my $device       = $msgarray[5];
	
    my $hash = $modules{MSwitch}{defptr}{$name};
	
	#MSwitch_LOG( $name, 5, "$name: msga4 -> ".$msgarray[4]);
	#MSwitch_LOG( $name, 5, "$name: msga5 -> ".$msgarray[5]);
	#MSwitch_LOG( $name, 5, "$name: msga6 -> ".$msgarray[6]);
	
	#MSwitch_LOG( $name, 5, "$name: befehl -> ".$cs);
	#MSwitch_LOG( $name, 5, "$name: event -> ".$event);
	#MSwitch_LOG( $name, 5, "$name: device -> ".$device);
	#MSwitch_LOG( $name, 5, "$name: befehl -> ".$cs);
	
	MSwitch_LOG( $name, 5, "$name: erstelle cmdhash -> ".$name);
    my %devicedetails = MSwitch_makeCmdHash($name);
	
	
	if ( AttrVal( $name, 'MSwitch_RandomNumber', '' ) ne '' ) 
	{
		MSwitch_Createnumber1($hash);
	}
	
    ############ teste auf condition
    ### antwort $execute 1 oder 0 ;

	
	
	my $execute = "true";
	MSwitch_LOG( $name, 5, "$name: kein aufruf checkcondition - nicht gesetzt ->".$execute) if $devicedetails{$conditionkey} eq '' || $devicedetails{$conditionkey} eq 'nocheck';
    
    if ( $msgarray[2] ne 'nocheck' ) 
	{
		MSwitch_LOG( $name, 5, "$name: aufruf checkcondition mit -> ".$devicedetails{$conditionkey});
        $execute = MSwitch_checkcondition( $devicedetails{$conditionkey}, $name,$event );
		MSwitch_LOG( $name, 5, "$name: ergebniss checkcondition -> ".$execute);
    }
	

  
    my $toggle = '';
    if ( $execute eq 'true' ) 
	{
        Log3( $name, 3, "$name MSwitch_Restartcm: Befehlsausfuehrung -> $cs " . __LINE__ );
        
		if ( $cs =~ m/set (.*)(MSwitchtoggle)(.*)/ )
		{
            $toggle = $cs;
            $cs = MSwitch_toggle( $hash, $cs );
        }

		
		MSwitch_LOG( $name, 5, "$name: teste repeat -> ".$devicedetails{ $device . '_repeatcount' });
			my $x =0;
				while ( $devicedetails{ $device . '_repeatcount' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # notausstieg notausstieg
					last if $x > 20;             # notausstieg notausstieg
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeatcount' } = $setmagic
					}
					
			 $x =0;
				while ( $devicedetails{ $device . '_repeattime' } =~ m/\[(.*)\:(.*)\]/ ) 
					{
					$x++;                        # notausstieg notausstieg
					last if $x > 20;             # notausstieg notausstieg
					my $setmagic = ReadingsVal( $1, $2, 0 );
					$devicedetails{ $device . '_repeattime' } = $setmagic
					}		
			
			MSwitch_LOG( $name, 5, "$name: repetcount nach test -> ".$devicedetails{ $device . '_repeatcount' });
			MSwitch_LOG( $name, 5, "$name: repeattime nach test -> ".$devicedetails{ $device . '_repeattime' });
			
        ######################################
        if (   AttrVal( $name, 'MSwitch_Expert', "0" ) eq '1' && $devicedetails{ $device . '_repeatcount' } > 0 && $devicedetails{ $device . '_repeattime' } > 0 )
        {
            my $i;
            for ($i = 0 ;$i <= $devicedetails{ $device . '_repeatcount' } ;$i++ )
            {
                my $msg = $cs . "|" . $name;
                if ( $toggle ne '' ) 
				{
                    $msg = $toggle . "|" . $name;
                }
                my $timecond = gettimeofday() +( ( $i + 1 ) * $devicedetails{ $device . '_repeattime' } );
				
				$msg = $msg."|".$timecond;
				$hash->{helper}{repeats}{$timecond} = "$msg";
				MSwitch_LOG( $name, 5, "$name: repeat gesetzt -> ".$timecond." - ".$msg);
                InternalTimer( $timecond, "MSwitch_repeat", $msg );
            }
        }
		

		my $todec = $cs;
	
		$cs = MSwitch_dec($hash,$todec);
        ############################
		
		if ( AttrVal( $name, 'MSwitch_Debug', "0" ) eq '2' )
		{
		MSwitch_LOG( $name, 5,"$name:     exec comand -> ".$cs );
		}
		else
		{
		
        if ( $cs =~ m/{.*}/ ) 
		{
		MSwitch_LOG( $name, 5,"$name:     exec als perlcode -> ".$cs );
            eval($cs);
            if ($@) 
			{
                MSwitch_LOG( $name, 1,"$name MSwitch_Set: ERROR $cs: $@ " . __LINE__ );
            }
        }
        else 
		{
		MSwitch_LOG( $name, 5,"$name:     execute als fhemcode -> ".$cs );
            my $errors = AnalyzeCommandChain( undef, $cs );
            if ( defined($errors) ) 
			{
                MSwitch_LOG( $name, 1,"$name MSwitch_Restartcmd :Fehler bei Befehlsausfuehrung  ERROR $errors ". __LINE__ );
            }
        }
		}
		if (length($cs) > 100 ){ $cs = substr($cs,0,100).'....';}
        readingsSingleUpdate( $hash, "Exec_cmd", $cs, 1 ) if $cs ne '';
    }
    RemoveInternalTimer($incomming);
    delete( $hash->{helper}{delays}{$incomming} );
    return;
}
####################
sub MSwitch_checkcondition($$$) {
    # antwort execute 0 oder 1
    my ( $condition, $name, $event ) = @_;
	
	my $hash     = $modules{MSwitch}{defptr}{$name};

	#$event ="test:test:test" if $event eq "";
	
	MSwitch_LOG( $name, 5,"$name:     Checkcondition - Parameter condition -> ".$condition ) ;
	MSwitch_LOG( $name, 5,"$name:     Checkcondition - Parameter event -> ".$event ) ;
	
	
	MSwitch_EventBulk($hash,$event ,'0');
	
    if ( !defined($condition) ) { return 'true'; }
    if ( $condition eq '' )     { return 'true'; }
    
	if ( AttrVal( $name, 'MSwitch_RandomNumber', '' ) ne '' ) {MSwitch_Createnumber($hash);}
    my $anzahlk1 = $condition =~ tr/{//;
    my $anzahlk2 = $condition =~ tr/}//;
	
    if ( $anzahlk1 ne $anzahlk2 )
	{
        $hash->{helper}{conditioncheck} = "Klammerfehler";
        return "false";
    }
	
    $anzahlk1 = $condition =~ tr/(//;
    $anzahlk2 = $condition =~ tr/)//;
	
    if ( $anzahlk1 ne $anzahlk2 )
	{
        $hash->{helper}{conditioncheck} = "Klammerfehler";
        return "false";
    }
	
    $anzahlk1 = $condition =~ tr/[//;
    $anzahlk2 = $condition =~ tr/]//;
	
    if ( $anzahlk1 ne $anzahlk2 ) 
	{
        $hash->{helper}{conditioncheck} = "Klammerfehler";
        return "false";
    }

    #$event =~ s/ //ig;
    #$event =~ s/~/ /g;

	MSwitch_EventBulk($hash , $event , '0')  if $event eq "";;
	
	
    my $arraycount = '0';
    my $finalstring;
    my $answer;
    my $i;
    my $pos;
    my $pos1;
    my $part;
    my $part1;
    my $part2;
    my $part3;
    my $lenght;
	
    # wildcardcheck

    my $we = AnalyzeCommand( 0, '{return $we}' );
    my @perlarray;
    ### perlteile trennen

    $condition =~ s/{!\$we}/ !\$we /ig;
    $condition =~ s/{\$we}/ \$we /ig;
    $condition =~ s/{sunset\(\)}/{ sunset\(\) }/ig;
    $condition =~ s/{sunrise\(\)}/{ sunrise\(\) }/ig;
    $condition =~ s/\$EVENT/$name\:last_event/ig;
    $condition =~ s/\$EVTFULL/$name\:EVTFULL/ig;
    $condition =~ s/\$EVTPART1/$name\:EVTPART1/ig;
    $condition =~ s/\$EVTPART2/$name\:EVTPART2/ig;
    $condition =~ s/\$EVTPART3/$name\:EVTPART3/ig;

	my $x = 0;
    while ( $condition =~ m/(.*?)(\$NAME)(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$condition = $firstpart.$name.$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}
	
		$x = 0;
    while ( $condition =~ m/(.*?)(\$SELF)(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$condition = $firstpart.$name.$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}
	
    my $searchstring;
    $x = 0;
    while ( $condition =~m/(.*?)(\[\[[a-zA-Z][a-zA-Z0-9_]{0,30}:[a-zA-Z0-9_]{0,30}\]-\[[a-zA-Z][a-zA-Z0-9_]{0,30}:[a-zA-Z0-9_]{0,30}\]\])(.*)?/)
    {
        my $firstpart = $1;
        $searchstring = $2;
        my $lastpart = $3;
        $x++;
        last if $x > 10;#notausstieg
        my $x = 0;
        # Searchstring -> [[t1:state]-[t2:state]]
        while ( $searchstring =~ m/(.*?)(\[[a-zA-Z][a-zA-Z0-9_]{0,30}:[a-zA-Z0-9_]{0,30}\])(.*)?/ )
        {
            my $read1           = '';
            my $firstpart       = $1;
            my $secsearchstring = $2;
            my $lastpart        = $3;
            if ( $secsearchstring =~ m/\[(.*):(.*)\]/ ) 
			{
                $read1 = ReadingsVal( $1, $2, 'undef' );
            }
            $searchstring = $firstpart . $read1 . $lastpart;
            $x++;
            last if $x > 10;    #notausstieg
        }
        $condition = $firstpart . $searchstring . $lastpart;
    }

	
    $x = 0;
    while ( $condition =~ m/(.*)({ )(.*)(\$we)( })(.*)/ )
	{
        last if $x > 20;    # notausstieg
        $condition = $1 . " " . $3 . $4 . " " . $6;
    }

    ###################################################
    # ersetzte sunset sunrise
    # regex (.*[^~])(~{|{)(sunset\(|sunrise\()(.*\))(~}|})(.*)

    $x = 0;# notausstieg
    while ($condition =~ m/(.*)({ )(sunset\([^}]*\)|sunrise\([^}]*\))( })(.*)/ )
    {
        $x++;    # notausstieg
        last if $x > 20;    # notausstieg
        if ( defined $2 )
		{
            my $part2 = eval $3;
            chop($part2);
            chop($part2);
            chop($part2);
            my ( $testhour, $testmin ) = split( /:/, $part2 );
            if ( $testhour > 23 ) 
			{
                $testhour = $testhour - 24;
                $testhour = '0' . $testhour if $testhour < 10;
                $part2    = $testhour . ':' . $testmin;
            }
            $condition = $part2;
            $condition = $1 . $condition if ( defined $1 );
            $condition = $condition . $5 if ( defined $5 );
        }
    }
    my $conditioncopy = $condition;
    my @argarray;
    $arraycount = '0';
    $pos        = '';
    $pos1       = '';
    $part       = '';
    $part1      = '';
    $part2      = '';
    $part3      = '';
    $lenght     = '';
	ARGUMENT: for ( $i = 0 ; $i <= 10 ; $i++ ) 
	{
        $pos = index( $condition, "[", 0 );
        my $x = $pos;
        if ( $x == '-1' ) { last ARGUMENT; }
        $pos1 = index( $condition, "]", 0 );
        $argarray[$arraycount] =substr( $condition, $pos, ( $pos1 + 1 - $pos ) );
        $lenght = length($condition);
        $part1  = substr( $condition, 0, $pos );
        $part2  = 'ARG' . $arraycount;
        $part3 =substr( $condition, ( $pos1 + 1 ), ( $lenght - ( $pos1 + 1 ) ) );
        $condition = $part1 . $part2 . $part3;
        $arraycount++;
    }
	
    $condition =~ s/ AND / && /ig;
    $condition =~ s/ OR / || /ig;
    #$condition =~ s/~/ /ig;
    $condition =~ s/ = / == /ig;

	END:

    # teste auf typ
    my $count = 0;
    my $testarg;
    my @newargarray;
    foreach my $args (@argarray) 
	{
        $testarg = $args;
        $testarg =~ s/[0-9]+//gs;
        if ( $testarg eq '[:-:|]' || $testarg eq '[:-:]' ) 
		{
            # timerformatierung erkannt - auswerten über sub
            my $param = $argarray[$count];
            $newargarray[$count] = MSwitch_Checkcond_time( $args, $name );
        }
        else 
		{
            my $param = $argarray[$count];
            # stateformatierung erkannt - auswerten über sub
            $newargarray[$count] = MSwitch_Checkcond_state( $args, $name );
        }
        $count++;
    }
	
    $count = 0;
    my $tmp;
    foreach my $args (@newargarray) 
	{
        $tmp = 'ARG' . $count;
        $condition =~ s/$tmp/$args/ig;
        $count++;
    }

    $finalstring ="if (" . $condition . "){\$answer = 'true';} else {\$answer = 'false';} ";
	
	MSwitch_LOG( $name, 5,"$name:     Checkcondition - finalstring -> ".$finalstring ) ;
	
    my $ret = eval $finalstring;
	MSwitch_LOG( $name, 5,"$name:     Checkcondition - return -> ".$ret ) ;
    if ($@)
	{
        MSwitch_LOG( $name, 1, "ERROR: $@ " . __LINE__ );
		MSwitch_LOG( $name, 1, "$finalstring " . __LINE__ );
        $hash->{helper}{conditionerror} = $@;
        return 'false';
    }
    my $test = ReadingsVal( $name, 'last_event', 'undef' );
    $hash->{helper}{conditioncheck} = $finalstring;
	
	
	
    return $ret;
}
####################
####################

sub MSwitch_Checkcond_state($$) {
    my ( $condition, $name ) = @_;
	
	
	
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	MSwitch_LOG( $name, 5, "$name: MSwitch_Checkcond_state -> ".$condition  ); 
	MSwitch_LOG( $name, 5, "----------------------------------------"   ); 
	
	
	my $x = 0;
    while ( $condition =~ m/(.*?)(\$SELF)(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$condition = $firstpart.$name.$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}
	
	
	
	
    $condition =~ s/\[//;
    $condition =~ s/\]//;
    my @reading = split( /:/, $condition );
    my $return  = "ReadingsVal('$reading[0]', '$reading[1]', '00:00:00')";
    my $test    = ReadingsVal( $reading[0], $reading[1], 'undef' );
	
	MSwitch_LOG( $name, 5, "$name: MSwitch_Checkcond_state OUT -> ".$return  ); 
	
    return $return;
}
####################
sub MSwitch_Checkcond_time($$) {
    my ( $condition, $name ) = @_;
    $condition =~ s/\[//;
    $condition =~ s/\]//;
    my $adday        = 0;
    my $days         = '';
    my $daycondition = '';
    ( $condition, $days ) = split( /\|/, $condition ) if index( $condition, "|", 0 ) > -1;
    my $hour1 = substr( $condition, 0, 2 );
    my $min1  = substr( $condition, 3, 2 );
    my $hour2 = substr( $condition, 6, 2 );
    my $min2  = substr( $condition, 9, 2 );

    if ( $hour1 eq "24" )# test auf 24 zeitangabe
    {
        $hour1 = "00";
    }
	
    if ( $hour2 eq "24" ) 
	{
        $hour2 = "00";
    }
	
    my $time = localtime;
    $time =~ s/\s+/ /g;
    my ( $day, $month, $date, $n, $time1 ) = split( / /, $time );
    my ( $akthour, $aktmin, $aktsec ) = split( /:/, $n );
	
    ############ timecondition 1
    my $timecondtest;
    my $timecond1;
    #my $time1;
    my ( $tday, $tmonth, $tdate, $tn );   #my ($tday,$tmonth,$tdate,$tn,$time1);
    if ( ( $akthour < $hour1 && $akthour < $hour2 ) && $hour2 < $hour1 )  # und
    {
        use constant SECONDS_PER_DAY => 60 * 60 * 24;
        $timecondtest = localtime( time - SECONDS_PER_DAY );
        $timecondtest =~ s/\s+/ /g;
        ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
        $timecond1 = timelocal( '00', $min1, $hour1, $tdate, $tmonth, $time1 );
        $adday = 1;
    }
    else
	{
        $timecondtest = localtime;
        $timecondtest =~ s/\s+/ /g;
        ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
        $timecond1 = timelocal( '00', $min1, $hour1, $tdate, $tmonth, $time1 );
    }
	
    ############# timecondition 2
    my $timecond2;
    $timecondtest = localtime;
    if ( $hour2 < $hour1 ) 
	{
        if ( $akthour < $hour1 && $akthour < $hour2 ) 
		{
            $timecondtest = localtime;
            $timecondtest =~ s/\s+/ /g;
            ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
            $timecond2 =timelocal( '00', $min2, $hour2, $tdate, $tmonth, $time1 );
        }
        else
		{
            use constant SECONDS_PER_DAY => 60 * 60 * 24;
            $timecondtest = localtime( time + SECONDS_PER_DAY );
            $timecondtest =~ s/\s+/ /g;
            my ( $tday, $tmonth, $tdate, $tn, $time1 ) =split( / /, $timecondtest );
            $timecond2 =timelocal( '00', $min2, $hour2, $tdate, $tmonth, $time1 );
            $adday = 1;
        }
    }
    else 
	{
        $timecondtest = localtime;
        $timecondtest =~ s/\s+/ /g;
        ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
        $timecond2 = timelocal( '00', $min2, $hour2, $tdate, $tmonth, $time1 );
    }
    my $timeaktuell = timelocal( '00', $aktmin, $akthour, $date, $month, $time1 );
    my $return = "($timecond1 < $timeaktuell && $timeaktuell < $timecond2)";
    if ( $days ne '' )
	{
        $daycondition = MSwitch_Checkcond_day( $days, $name, $adday, $day );
        $return = "($return $daycondition)";
    }
    return $return;
}
####################
sub MSwitch_Checkcond_day($$$$) {
    my ( $days, $name, $adday, $day ) = @_;

    my %daysforcondition = (
        "Mon" => 1,
        "Tue" => 2,
        "Wed" => 3,
        "Thu" => 4,
        "Fri" => 5,
        "Sat" => 6,
        "Sun" => 7
    );
    $day = $daysforcondition{$day};
    my @daycond = split //, $days;
    my $daycond = '';
    foreach my $args (@daycond) 
	{
        if ( $adday == 1 ) { $args++; }
        if ( $args == 8 ) { $args = 1 }
        $daycond = $daycond . "($day == $args) || ";
    }
    chop $daycond;
    chop $daycond;
    chop $daycond;
    chop $daycond;
    $daycond = "&& ($daycond)";
    return $daycond;
}

####################
sub MSwitch_Createtimer($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};

	
	
	
	
    # keine timer vorhenden
    my $condition = ReadingsVal( $Name, '.Trigger_time', '' );
	#MSwitch_LOG( $Name, 0,"create timer: ".$condition);
	
	$condition =~ s/#\[dp\]/:/g;
	
				my	$x =0;
				# (.*)\[(.*[a-zA-Z].*)\:(.*)\](.*)
				while ( $condition =~ m/(.*)\[(.*[^0-9]{2})\:(.*[^0-9]{2})\](.*)/ ) 
				#while ( $condition =~ m/(.*)\[(.*[a-zA-Z].*)\:(.*)\](.*)/ ) 
					{
					$x++;                        # notausstieg notausstieg
					last if $x > 20;             # notausstieg notausstieg
					my $setmagic = ReadingsVal( $2, $3, 0 );
					$condition = $1.'['.$setmagic.']'.$4;
					}
	
    my $lenght = length($condition);

	
	#MSwitch_LOG( $Name, 0,"create timer: ".$condition);
	
	
    #remove all timers
    MSwitch_Clear_timer($hash);

    if ( $lenght == 0 )
	{
        return;
    }

    # trenne timerfile
    my $key = 'on';
    $condition =~ s/$key//ig;
    $key = 'off';
    $condition =~ s/$key//ig;
    $key = 'ly';
    $condition =~ s/$key//ig;

	$x =0;
	# achtung perl 5.30
	  while ($condition =~ m/(.*).\{(.*)\}.(.*)/ )
    {
        $x++;    # notausstieg
        last if $x > 20;    # notausstieg
        if ( defined $2 )
		{
		my $part2 = "[".substr( (eval $2)  , 0, 5 )."]";
		my $test = substr( (eval $2)  , 0, 2 ) *1;
		$part2 ="" if $test > 23 ;
		$condition = $1.$part2.$3;
        }
    }
	
    my @timer = split /~/, $condition;

    $timer[0] = '' if ( !defined $timer[0] );
    $timer[1] = '' if ( !defined $timer[1] );
    $timer[2] = '' if ( !defined $timer[2] );
    $timer[3] = '' if ( !defined $timer[3] );
 
 MSwitch_LOG( $Name, 0,"timer0  $timer[0]");
 MSwitch_LOG( $Name, 0,"timer1  $timer[1]");
 MSwitch_LOG( $Name, 0,"timer2  $timer[2]");
 MSwitch_LOG( $Name, 0,"timer3  $timer[3]");
 
 
    # lösche bei notify und toggle
    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Notify" )
	{
        $timer[0] = '';
        $timer[1] = '';
    }

    if ( AttrVal( $Name, 'MSwitch_Mode', 'Full' ) eq "Toggle" ) 
	{
        $timer[1] = '';
        $timer[2] = '';
        $timer[3] = '';
    }

    my $akttimestamp = TimeNow();

    my ( $aktdate, $akttime ) = split / /, $akttimestamp;
    my ( $aktyear, $aktmonth, $aktmday ) = split /-/, $aktdate;
    $aktmonth = $aktmonth - 1;
    $aktyear  = $aktyear - 1900;

    my $jetzt = gettimeofday();

    # aktuelle zeit setzen
    my $time = localtime;
    $time =~ s/\s+/ /g;
    my ( $day, $month, $date, $n, $time1 ) =
      split( / /, $time );    # day enthält aktuellen tag als wochentag

    my $aktday           = $day;
    my %daysforcondition = (
        "Mon" => 1,
        "Tue" => 2,
        "Wed" => 3,
        "Thu" => 4,
        "Fri" => 5,
        "Sat" => 6,
        "Sun" => 7
    );
    $day = $daysforcondition{$day};    # enthält aktuellen tag

    ###

    ## für jeden Timerfile ( 0 -4 )
    my $i = 0;
	LOOP2: foreach my $option (@timer) 
	{
        $i++;
        #### inhalt array für eine option on , off ...
        $key = '\]\[';
        $option =~ s/$key/ /ig;
        $key = '\[';
        $option =~ s/$key//ig;
        $key = '\]';
        $option =~ s/$key//ig;
  
        if ( $option =~m/(.*?)([0-9]{2}):([0-9]{2})\*([0-9]{2}:[0-9]{2})-([0-9]{2}:[0-9]{2})\|?([0-9]{0,7})(.*)?/ )
        {
            my $part1 = '';
            $part1 = $1 . ' ' if defined $1;
            my $part6 = '';
            if ( defined $6 && $part6 ne '' ) { $part6 = '|' . $6 }
            my $part7 = '';
            $part7 = ' ' . $7 if defined $7;
            my $sectoadd = $2 * 3600 + $3 * 60;
            my $t1 = $4;
            my $t2 = $5;
            my $timecondtest = localtime;
            $timecondtest =~ s/\s+/ /g;
            my ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
            my $timecond1 = timelocal( '00', substr( $t1, 3, 2 ),substr( $t1, 0, 2 ),$tdate, $tmonth, $time1 );
            my $timecond2 = timelocal('00',substr( $t2, 3, 2 ), substr( $t2, 0, 2 ), $tdate, $tmonth, $time1);

            my @newarray;
            while ( $timecond1 < $timecond2 ) 
			{
                #my $timestamp = FmtDateTime($timecond1);
                my $timestamp =substr( FmtDateTime($timecond1), 11, 5 ) . $part6;
                $timecond1 = $timecond1 + $sectoadd;
                push( @newarray, $timestamp );
            }
            my $newopt = join( ' ', @newarray );
            my $newoption = $part1 . $newopt . $part7;
            $newoption =~ s/  / /g;
            $option = $newoption;
        }

        my @optionarray = split / /, $option;
        # für jede angabe eines files
		LOOP3: foreach my $option1 (@optionarray) {

            if ( $option1 =~ m/\?(.*)(-)([0-9]{2}:[0-9]{2})(\|[0-9]{0,7})?(.*)?/ )
            {
                my $testrandom = $1 . $2 . $3;
                my $part4 = '';
                $part4 = $4 if defined $4;
                my $opdays = $part4;
                #testrandomsaved erstellen
                my $newoption1 = MSwitch_Createrandom( $hash, $1, $3 );
                $option1 = $newoption1 . $opdays;
            }

            if ( $option1 =~ m/{/i || $option1 =~ m/}/i )
			{
                my $newoption1 = MSwitch_ChangeCode( $hash, $option1 );
                $option1 = $newoption1;
            }

            my ( $time, $days ) = split /\|/, $option1;
            $time = '' if ( !defined $time );
            $days = '' if ( !defined $days );

            if ( $days eq '!$we' || $days eq '$we' )
			{
                my $we = AnalyzeCommand( 0, '{return $we}' );
                if ( $days eq '$we'  && $we == 1 ) { $days = $day; }
                if ( $days eq '!$we' && $we == 0 ) { $days = $day; }
            }

            if ( !defined($days) ) { $days = '' }
            if ( $days eq '' )     { $days = '1234567' }

            if ( index( $days, $day, 0 ) == -1 ) 
			{
                next LOOP3;
            }

            $time = $time . ':00';

			delete( $hash->{helper}{error} );

			
            my $timecond = timelocal( substr( $time, 6, 2 ),substr( $time, 3, 2 ),substr( $time, 0, 2 ),$date, $aktmonth, $aktyear);
            my $test = FmtDateTime($timecond);
            my $sectowait = $timecond - $jetzt;
            if ( $timecond > $jetzt ) 
			{
                my $inhalt = $timecond . "-" . $i;
				$hash->{helper}{timer}{$inhalt} = "$inhalt";
                my $msg = $Name . " " . $timecond . " " . $i;
                my $gettime = gettimeofday();
                InternalTimer( $timecond, "MSwitch_Execute_Timer", $msg );
            }
        }
    }

    # berechne zeit bis 23,59 und setze timer auf create timer
    my $newask = timelocal( '00', '59', '23', $date, $aktmonth, $aktyear );
    $newask = $newask + 70;
    my $newassktest = FmtDateTime($newask);
    my $msg = $Name . " " . $newask . " " . 5;
    my $inhalt = $newask . "-" . 5;
    $hash->{helper}{timer}{$newask} = "$inhalt";
    InternalTimer( $newask, "MSwitch_Execute_Timer", $msg );

}

##############################
sub MSwitch_Createrandom($$$) {
    my ( $hash, $t1, $t2 ) = @_;
    my $Name = $hash->{NAME};
    my $testrandom = $t1 . "-" . $t2;
    my $testt1 = $t1;
    my $testt2 = $t2;
    $testt1 =~ s/\://g;
    $testt2 =~ s/\://g;
    my $timecondtest = localtime;
    $timecondtest =~ s/\s+/ /g;
    my ( $tday, $tmonth, $tdate, $tn, $time1 ) = split( / /, $timecondtest );
    my $timecond1 = timelocal( '00', substr( $t1, 3, 2 ), substr( $t1, 0, 2 ), $tdate, $tmonth, $time1 );
    my $timecond2 = timelocal( '00', substr( $t2, 3, 2 ), substr( $t2, 0, 2 ), $tdate, $tmonth, $time1 );
    if ( $testt2 < $testt1 ) { $timecond2 = $timecond2 + 86400 }
    my $newtime = int( rand( $timecond2 - $timecond1 ) ) + $timecond1;
    my $timestamp = FmtDateTime($newtime);
    my $timestamp1 = substr( $timestamp, 11, 5 );
    return $timestamp1;
}

###########################

sub MSwitch_Execute_Timer($) {
    my ($input) = @_;
    my ( $Name, $timecond, $param ) = split( / /, $input );
    my $hash = $defs{$Name};
	return "" if ( IsDisabled($Name) );
	
	if ( ReadingsVal( $Name, '.V_Check', $vupdate ) ne $vupdate )
	{
	my $ver = ReadingsVal( $Name, '.V_Check', '' );
	Log3( $Name, 1, $Name.' Versionskonflikt, aktion abgebrochen !  erwartet:'.$vupdate.' vorhanden:'.$ver );
	return;
	}

	
	if ( AttrVal( $Name, 'MSwitch_RandomNumber', '' ) ne '' ) {MSwitch_Createnumber1($hash);}
    if ( $param eq '5' )
	{
        MSwitch_Createtimer($hash);
        return;
    }
	
    if ( AttrVal( $Name, 'MSwitch_Condition_Time', "0" ) eq '1' ) 
	{
        my $triggercondition = ReadingsVal( $Name, '.Trigger_condition', '' );
       # $triggercondition =~ s/\./:/g;
		$triggercondition =~ s/#\[dp\]/:/g;
		$triggercondition =~ s/#\[pt\]/./g;
		$triggercondition =~ s/#\[ti\]/~/g;
		$triggercondition =~ s/#\[sp\]/ /g;
		
        if ( $triggercondition ne '' ) 
		{
            my $ret = MSwitch_checkcondition( $triggercondition, $Name, '' );
            if ( $ret eq 'false' )
			{
                return;
            }
        }
    }
	
 my $extime = POSIX::strftime("%H:%M",localtime);
 
 
	 readingsBeginUpdate($hash);
     readingsBulkUpdate( $hash, "EVENT", $Name.":execute_timer_P".$param.":".$extime );
	 readingsBulkUpdate( $hash, "EVTFULL",  $Name.":execute_timer_P".$param.":".$extime );
	 readingsBulkUpdate( $hash, "EVTPART1", $Name );
	 readingsBulkUpdate( $hash, "EVTPART2","execute_timer_P".$param );
	 readingsBulkUpdate( $hash, "EVTPART3",$extime );
     readingsEndUpdate( $hash, 1 );

    if ( $param eq '1' )
	{
        my $cs = "set $Name on";
        Log3( $Name, 3, "$Name MSwitch_Execute_Timer: Befehlsausfuehrung -> $cs" . __LINE__ );
        my $errors = AnalyzeCommandChain( undef, $cs );
        if ( defined($errors) ) 
		{
            Log3( $Name, 1,"$Name MSwitch_Execute_Timer: Fehler bei Befehlsausfuehrung ERROR $Name: $errors ". __LINE__ );
        }
        return;
    }
	
    if ( $param eq '2' ) 
	{
        my $cs = "set $Name off";
        Log3( $Name, 3,"$Name MSwitch_Execute_Timer: Befehlsausfuehrung -> $cs" . __LINE__ );
        my $errors = AnalyzeCommandChain( undef, $cs );
        if ( defined($errors) )
		{
            Log3( $Name, 1,"$Name MSwitch_Execute_Timer: Fehler bei Befehlsausfuehrung ERROR $Name: $errors " . __LINE__ );
        }
        return;
    }
	
    if ( $param eq '3' ) 
	{
        MSwitch_Exec_Notif( $hash, 'on', 'nocheck', '',0 );
        return;
    }
	
    if ( $param eq '4' ) 
	{
        MSwitch_Exec_Notif( $hash, 'off', 'nocheck', '',0 );
        return;
    }
    return;
}

####################
sub MSwitch_ChangeCode($$) {
    my ( $hash, $option ) = @_;
    my $Name = $hash->{NAME};
    my $x    = 0;               # exit secure
	#achtung perl5.30
	while ( $option =~ m/(.*)\{(sunset|sunrise)(.*)\}(.*)/ )
    #while ( $option =~ m/(.*){(sunset|sunrise)(.*)}(.*)/ )
	{
        $x++;                   # exit secure
        last if $x > 20;        # exit secure
        if ( defined $2 ) 
		{
            my $part2 = eval $2 . $3;
            chop($part2);
            chop($part2);
            chop($part2);
            $option = $part2;
            $option = $1 . $option if ( defined $1 );
            $option = $option . $4 if ( defined $4 );
        }
    }
    return $option;
}

####################
sub MSwitch_Add_Device($$) {
    my ( $hash, $device ) = @_;
    my $Name       = $hash->{NAME};
    my @olddevices = split( /,/, ReadingsVal( $Name, '.Device_Affected', '' ) );
    my $count      = 1;
	LOOP7: foreach (@olddevices)
	{
        my ( $devicename, $devicecmd ) = split( /-AbsCmd/, $_ );
        if ( $device eq $devicename ) { $count++; }
    }
    my $newdevices .= ',' . $device . '-AbsCmd' . $count;
    my $newset = ReadingsVal( $Name, '.Device_Affected', '' ) . $newdevices;
    $newdevices = join( ',', @olddevices ) . ',' . $newdevices;
    my @sortdevices = split( /,/, $newdevices );
    @sortdevices = sort @sortdevices;
    $newdevices  = join( ',', @sortdevices );
    $newdevices  = substr( $newdevices, 1 );
    readingsSingleUpdate( $hash, ".Device_Affected", $newdevices, 1 );
    return;
}
###################################
sub MSwitch_Del_Device($$) {
    my ( $hash, $device ) = @_;
    my $Name = $hash->{NAME};
    my @olddevices = split( /,/, ReadingsVal( $Name, '.Device_Affected', '' ) );
    my @olddevicesset = split( /#\[ND\]/, ReadingsVal( $Name, '.Device_Affected_Details', '' ) );
	
	#Log3( $Name, 5, "olddevice:  @olddevicesset" );
	
	
    my @newdevice;
    my @newdevicesset;
    my $count = 0;
	LOOP8: foreach (@olddevices)
	{
	#Log3( $Name, 5, "olddevice:  $_" );
	
	
        if ( $device eq $_ )
		{
            $count++;
            next LOOP8;
        }
        push( @newdevice,     $olddevices[$count] );
        push( @newdevicesset, $olddevicesset[$count] );
        $count++;
    }
	
    my ( $devicemaster, $devicedeleted ) = split( /-AbsCmd/, $device );
    $count = 1;
    my @newdevice1;
	LOOP9: foreach (@newdevice) 
	{
        my ( $devicename, $devicecmd ) = split( /-AbsCmd/, $_ );
        if ( $devicemaster eq $devicename ) 
		{
            my $newname = $devicename . '-AbsCmd' . $count;
            $count++;
            push( @newdevice1, $newname );
            next LOOP9;
        }
        push( @newdevice1, $_ );
    }
    $count = 1;
    my @newdevicesset1;
	
	LOOP10: foreach (@newdevicesset) 
	{
      #  my ( $name,       @comands )   = split( /,/,       $_ );
	  
	   my ( $name,       @comands )   = split( /#\[NF\]/,       $_ );
        my ( $devicename, $devicecmd ) = split( /-AbsCmd/, $name );
        if ( $devicemaster eq $devicename ) 
		{
           # my $newname = $devicename . '-AbsCmd' . $count . ',' . join( ',', @comands );
		   my $newname = $devicename . '-AbsCmd' . $count . '#[NF]' . join( '#[NF]', @comands );
            push( @newdevicesset1, $newname );
            $count++;
            next LOOP10;
        }
        push( @newdevicesset1, $_ );
    }
	
    my $newaffected = join( ',', @newdevice1 );
    if ( $newaffected eq '' ) { $newaffected = 'no_device' }
    my $newaffecteddet = join( '#[ND]', @newdevicesset1 );
	
	#Log3( $Name, 5, "deldevice new: $newaffecteddet" );
	
	#return;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, ".Device_Affected",         $newaffected );
    readingsBulkUpdate( $hash, ".Device_Affected_Details", $newaffecteddet );
    readingsEndUpdate( $hash, 0 );
    my $devices = MSwitch_makeAffected($hash);
    my $devhash = $hash->{DEF};
    my @dev     = split( /#/, $devhash );
    $hash->{DEF} = $dev[0] . ' # ' . $devices;
}
###################################
sub MSwitch_Debug($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
    my $debug1 = ReadingsVal( $Name, '.Device_Affected',         0 );
    my $debug2 = ReadingsVal( $Name, '.Device_Affected_Details', 0 );
    my $debug3 = ReadingsVal( $Name, '.Device_Events',           0 );
    $debug2 =~ s/:/ /ig;
    $debug3 =~ s/,/, /ig;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "Device_Affected",         $debug1 );
    readingsBulkUpdate( $hash, "Device_Affected_Details", $debug2 );
    readingsBulkUpdate( $hash, "Device_Events",           $debug3 );
    readingsEndUpdate( $hash, 0 );
}
###################################
sub MSwitch_Delete_Delay($$) {

    my ( $hash, $device ) = @_;
    my $Name     = $hash->{NAME};
    my $timehash = $hash->{helper}{delays};
	if ($device eq 'all')
	{
	foreach my $a ( keys %{$timehash} ) 
		{
			my $inhalt = $hash->{helper}{delays}{$a};
			 RemoveInternalTimer($a);
			 RemoveInternalTimer($inhalt);
			 delete( $hash->{helper}{delays}{$a} );
		}
	}
	else
	{
	foreach my $a ( keys %{$timehash} ) 
		{
			my $pos = index( $a, "$device", 0 );
			if ( $pos != -1 )
			{
				#Log3( $Name, 5,"lösche timer  $a". __LINE__ );
				RemoveInternalTimer($a);
				my $inhalt = $hash->{helper}{delays}{$a};
				RemoveInternalTimer($a);
				RemoveInternalTimer($inhalt);
				delete( $hash->{helper}{delays}{$a} );
			}
		}
	}
	

}


###################################

sub MSwitch_Clear_timer($) {
    my ( $hash, $device ) = @_;
    my $name = $hash->{NAME};
    my $timehash = $hash->{helper}{timer};
    foreach my $a ( keys %{$timehash} ) 
	{
        my $inhalt = $hash->{helper}{timer}{$a};
        RemoveInternalTimer($inhalt);
        $inhalt = $hash->{helper}{timer}{$a};
        $inhalt =~ s/-/ /g;
        $inhalt = $name . ' ' . $inhalt;
        RemoveInternalTimer($inhalt);
    }
    delete( $hash->{helper}{timer} );
}

##################################
# Eventsimulation
sub MSwitch_Check_Event($$) {
    my ( $hash, $eventin ) = @_;
    my $Name = $hash->{NAME};
    $eventin =~ s/~/ /g;
    my $dev_hash = "";
    if ( ReadingsVal( $Name, 'Trigger_device', '' ) eq "all_events" )
	{
        my @eventin = split( /:/, $eventin );
        $dev_hash                         = $defs{ $eventin[0] };
        $hash->{helper}{testevent_device} = $eventin[0];
        $hash->{helper}{testevent_event}  = $eventin[1] . ":" . $eventin[2];
        $hash->{helper}{testevent_event}  = $eventin[1] . ":" . $eventin[2];
    }
    else 
	{
        my @eventin = split( /:/, $eventin );
        $dev_hash = $defs{ ReadingsVal( $Name, 'Trigger_device', '' ) };
        $hash->{helper}{testevent_device} =ReadingsVal( $Name, 'Trigger_device', '' );
        $hash->{helper}{testevent_event} = $eventin[0] . ":" . $eventin[1];
    }
    my $we = AnalyzeCommand( 0, '{return $we}' );
    MSwitch_Notify( $hash, $dev_hash );
    delete( $hash->{helper}{testevent_device} );
    delete( $hash->{helper}{testevent_event} );
    delete( $hash->{helper}{testevent_event1} );
    return;
}
#########################################
sub MSwitch_makeAffected($) {
    my ($hash)  = @_;
    my $Name    = $hash->{NAME};
    my $devices = '';
    my %saveaffected;
    my @affname;
    my $affected = ReadingsVal( $Name, '.Device_Affected', 'nodevices' );
    my @affected = split( /,/, $affected );
	LOOP30: foreach (@affected) 
	{
        @affname = split( /-/, $_ );
        $saveaffected{ $affname[0] } = 'on';
    }
    foreach my $a ( keys %saveaffected )
	{
        $devices = $devices . $a . ' ';
    }
    chop($devices);
    return $devices;
}

#############################
sub MSwitch_checktrigger(@) {

    my ( $own_hash, $ownName, $eventstellen, $triggerfield, $device, $zweig,$eventcopy, @eventsplit )= @_;
    my $triggeron     = ReadingsVal( $ownName, '.Trigger_on', '' );
    my $triggeroff    = ReadingsVal( $ownName, '.Trigger_off', '' );
    my $triggercmdon  = ReadingsVal( $ownName, '.Trigger_cmd_on', '' );
    my $triggercmdoff = ReadingsVal( $ownName, '.Trigger_cmd_off', '' );
	my $answer="";
	
	#$triggerfield =~ s/\(//g;
	#$triggerfield =~ s/\)//g;
    unshift( @eventsplit, $device ) if ReadingsVal( $ownName, 'Trigger_device', '' ) eq "all_events";
	
    if (ReadingsVal( $ownName, 'Trigger_device', '' ) eq "all_events" )
    {
	$eventcopy =$device.":".$eventcopy;
		if ($triggerfield eq "*")
		{
		
			$triggerfield = "*:*:*";
		}
    }
    if ( $triggerfield eq "*" && ReadingsVal( $ownName, 'Trigger_device', '' ) ne "all_events" )
    {
        $triggerfield = "*:*";
    }
    $triggerfield =~ s/\*/.*/g;
	
# erkennunhg der formartierung bis v1.66 ( <1.67)
	my $x =0;
	while ( $triggerfield =~ m/(.*)(\()(.*)(\/)(.*)(\))(.*)/ ) 
		{
        $x++;                        # exit secure
        last if $x > 20;             # exit secure
		$triggerfield = $1 . $3 ."|" . $5 . $7;
        }
################

	if ( $eventcopy =~m/^$triggerfield/)
    {
	$answer = "wahr";
	}
	
    return 'on'
      if $zweig eq 'on'
      && $answer eq 'wahr'
      && $eventcopy ne $triggercmdoff
      && $eventcopy ne $triggercmdon
      && $eventcopy ne $triggeroff;

	
    return 'off'
      if $zweig eq 'off'
      && $answer eq 'wahr'
      && $eventcopy ne $triggercmdoff
      && $eventcopy ne $triggercmdon
      && $eventcopy ne $triggeron;

	
    return 'offonly' if $zweig eq 'offonly' && $answer eq 'wahr';
    return 'ononly'  if $zweig eq 'ononly'  && $answer eq 'wahr';
	
    return 'undef';
}
###############################
sub MSwitch_VUpdate($) {
	my ($hash) = @_;
	my $Name = $hash->{NAME};
	
	readingsSingleUpdate( $hash, ".V_Check", $vupdate, 0 );
	my $devs =  ReadingsVal( $Name, '.Device_Affected_Details', '' ) ;
	
	# encode from old format
	
	$devs =~ s/,/#[NF]/g;
	$devs =~ s/\|/#[ND]/g;
	$devs =~ s/~/ /g;
	$devs =~ s/\[cnl\]/\n/g;
	$devs =~ s/\[se\]/;/g;
	$devs =~ s/#\[ko\]/,/g;
	$devs =~ s/#\[sp\]/ /g;
	
	# decode to new format
	
	$devs =~ s/#\[wa\]/|/g; 
	$devs =~ s/\n/#[nl]/g; 
	$devs =~ s/;/#[se]/g; 
	$devs =~ s/\:/#[dp]/g;
	$devs =~ s/\t/    /g; 
	$devs =~ s/ /#[sp]/g; 
	$devs =~ s/\\/#[bs]/g; 
	$devs =~ s/,/#[ko]/g;
	$devs =~ s/^#\[/#[eo]/g;
	$devs =~ s/^#\]/#[ec]/g;
	$devs =~ s/\|/#[wa]/g;
	
	# change timerkey to new format
	
	my $x =0;	
	while ( $devs =~ m/(.*#\[NF\])([0-9]{2})([0-9]{2})([0-9]{2})(#\[NF\].*)/ ) 
	{
	

	
	$x++;                        # exit
	last if $x > 20;             # exit
	$devs =  $1.$2."#[dp]".$3."#[dp]".$4.$5 ;
	
	}
	
		
	readingsSingleUpdate( $hash, ".Device_Affected_Details", $devs, 0 );

	
	return;
}
################################
sub MSwitch_backup($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};

    my @areadings =
      qw(.Device_Affected .Device_Affected_Details .Device_Events .First_init .Trigger_Whitelist .Trigger_cmd_off .Trigger_cmd_on .Trigger_condition .Trigger_off .Trigger_on .Trigger_time .V_Check Exec_cmd Trigger_device Trigger_log last_event state .sysconf Sys_Extension) ;    #alle readings

	my %keys;
    open( BACKUPDATEI, ">MSwitch_backup_$vupdate.cfg" );    # Datei zum Schreiben öffnen
    print BACKUPDATEI "# Mswitch Devices\n";       #
    foreach my $testdevice ( keys %{ $modules{MSwitch}{defptr} } )    #
    {
        print BACKUPDATEI "$testdevice\n";
    }
    print BACKUPDATEI "# Mswitch Devices END\n";    #
  
  print BACKUPDATEI "\n";                         # HTML-Datei schreiben
    foreach my $testdevice ( keys %{ $modules{MSwitch}{defptr} } )    #
    {
        print BACKUPDATEI "#N -> $testdevice\n";                      #
        foreach my $key (@areadings) 
		{
            my $tmp = ReadingsVal( $testdevice, $key, 'undef' );
            print BACKUPDATEI "#S $key -> $tmp\n";
        }
		
        my %keys;
        foreach my $attrdevice ( keys %{ $attr{$testdevice} } )       #geht
        {
            print BACKUPDATEI "#A $attrdevice -> ". AttrVal( $testdevice, $attrdevice, '' ) . "\n";
        }
        print BACKUPDATEI "#E -> $testdevice\n";
        print BACKUPDATEI "\n";
    }
    close(BACKUPDATEI);
}

################################
sub MSwitch_backup_this($) {
    my ($hash) = @_;
    my $Name   = $hash->{NAME};
    my $Zeilen = ("");
	my $Zeilen1 ="";
    open( BACKUPDATEI, "<MSwitch_backup_$vupdate.cfg" ) || return "no Backupfile found!\n";
    while (<BACKUPDATEI>)
	{
        $Zeilen = $Zeilen . $_;
    }
    close(BACKUPDATEI);

    $Zeilen =~ s/\n/[NL]/g;

    if ( $Zeilen !~ m/#N -> $Name\[NL\](.*)#E -> $Name\[NL\]/ ) 
	{
        return "no Backupfile found\n";
    }

    my @found = split( /\[NL\]/, $1 );
    foreach (@found) 
	{
        if ( $_ =~ m/#S (.*) -> (.*)/ )    # setreading
        {
		# Log3( $Name, 0, "s1 $1" );
		# Log3( $Name, 0, "s2 $2" );
		
            if ( $2 eq 'undef' || $2 eq '' || $2 eq ' ' ) 
			{
            }
            else
			{
			$Zeilen1 = $2;
            readingsSingleUpdate( $hash, "$1", $Zeilen1, 0 );
            }
        }
        if ( $_ =~ m/#A (.*) -> (.*)/ )    # setattr
        {
            my $cs = "attr $Name $1 $2";
            my $errors = AnalyzeCommandChain( undef, $cs );
            if ( defined($errors) ) 
			{
                Log3( $Name, 1, "ERROR $cs" );
            }
        }
    }

	MSwitch_LoadHelper($hash);
    return "MSwitch $Name restored.\nPlease refresh device.";
}

# ################################

sub MSwitch_Getconfig($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME}; 
	my @areadings = qw(.Device_Affected .Device_Affected_Details .Device_Events .First_init .Trigger_Whitelist .Trigger_cmd_off .Trigger_cmd_on .Trigger_condition .Trigger_off .Trigger_on .Trigger_time .V_Check Trigger_device Trigger_log last_event .sysconf state Sys_Extension);  

	#.sysconf
	

    #alle readings
    #   my %keys; $vupdate 
    my $count      = 0;
    my $out        = "#V $version\\n";
	$out        .= "#VS $vupdate\\n";
    my $testdevice = $Name;
    foreach my $key (@areadings)
	{
		my $tmp = ReadingsVal( $testdevice, $key, 'undef' );
		if ($key eq ".Device_Affected_Details")
		{
		$tmp =~ s/#\[nl\]/;;/g;
		
		$tmp =~ s/#\[sp\]/ /g;
		$tmp =~ s/#\[nl\]/\\n/g;
		$tmp =~ s/#\[se\]/;/g;
		$tmp =~ s/#\[dp\]/:/g;
		$tmp =~ s/\(DAYS\)/|/g;
	    $tmp =~ s/#\[ko\]/,/g; #neu
		$tmp =~ s/#\[wa\]/|/g;
		$tmp =~ s/#\[st\]/\\'/g;
		$tmp =~ s/'/\\'/g;
		$tmp =~ s/#\[bs\]/\\\\/g;
		#Log3( $Name, 0, $tmp );
		}
		
		if ($key eq ".sysconf")
		{

		}
		
		if ($key eq ".Device_Events")
		{
		$tmp =~ s/#\[tr\]/ /g;
		
		}
		

        $out .= "#S $key -> $tmp\\n";
        $count++;
    }

    #  my %keys;
    foreach my $attrdevice ( keys %{ $attr{$testdevice} } )    #geht
    {
        $out .= "#A $attrdevice -> ". AttrVal( $testdevice, $attrdevice, '' ) . "\\n";
        $count++;
    }
    $count++;
    $count++;

	
    my $client_hash = $hash->{CL};
	
    asyncOutput( $hash->{CL},
            "<html>Änderungen sollten hier nur von erfahrenen Usern durchgeführt werden.<textarea name=\"edit1\" id=\"edit1\" rows=\""
          . $count
          . "\" cols=\"160\" STYLE=\"font-family:Arial;font-size:9pt;\">"
          . $out
          . "</textarea><br><input name\"edit\" type=\"button\" value=\"save changes\" onclick=\" javascript: saveconfig(document.querySelector(\\\'#edit1\\\').value) \"></html>"
    );
	

	
    return;
}

#######################################################
sub MSwitch_Sysextension($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME}; 
	my $count = 30;
	my $out = ReadingsVal( $Name,'.sysconf', '' );
	

	$out =~ s/#\[sp\]/ /g;
	$out =~ s/#\[nl\]/\\n/g;
	$out =~ s/#\[se\]/;/g;
	$out =~ s/#\[dp\]/:/g;
	$out =~ s/#\[st\]/\\'/g;
	$out =~ s/#\[dst\]/\"/g;
	$out =~ s/#\[tab\]/    /g;
	$out =~ s/#\[ko\]/,/g;
	$out =~ s/#\[wa\]/|/g;
	
	
	$out =~ s/#\[bs\]/\\\\/g;
	
	my $client_hash = $hash->{CL};
    asyncOutput( $hash->{CL},
            "<html><center>Achtung! Hier angegebener Code greift direkt in das Programm 98_MSwitch ein und wird unmittelbar zu beginn der Routine X_Set ausgeführt<br><textarea name=\"sys\" id=\"sys\" rows=\""
          . $count
          . "\" cols=\"160\" STYLE=\"font-family:Arial;font-size:9pt;\">"
          . $out
          . "</textarea><br><input type=\"button\" value=\"save changes\" onclick=\" javascript: savesys(document.querySelector(\\\'#sys\\\').value) \"></html>"
    );
    return;
	
	}
################################
sub MSwitch_backup_all($) {
    my ($hash) = @_;
    my $Name   = $hash->{NAME};
    my $answer = '';
    my $Zeilen = ("");
    open( BACKUPDATEI, "<MSwitch_backup_$vupdate.cfg" )|| return "$Name|no Backupfile MSwitch_backup_$vupdate.cfg found\n";
    while (<BACKUPDATEI>) 
	{
        $Zeilen = $Zeilen . $_;
    }
    close(BACKUPDATEI);
    foreach my $testdevice ( keys %{ $modules{MSwitch}{defptr} } )    #
    {
	
	Log3( $testdevice, 0, "MSWITCH-RESTORE: ".$testdevice );
        my $devhash = $defs{$testdevice};
        $Zeilen =~ s/\n/[NL]/g;

        if ( $Zeilen !~ m/#N -> $testdevice\[NL\](.*)#E -> $testdevice\[NL\]/ )
        {
            $answer = $answer . "no Backupfile found for $testdevice\n";
        }
        my @found = split( /\[NL\]/, $1 );
        foreach (@found) {
            if ( $_ =~ m/#S (.*) -> (.*)/ )    # setreading
            {
                if ( $2 eq 'undef' || $2 eq '' || $2 eq ' ' ) 
				{
                }
                else
				{
                    readingsSingleUpdate( $devhash, "$1", $2, 0 );
                }
            }
            if ( $_ =~ m/#A (.*) -> (.*)/ )    # setattr
            {
                my $cs = "attr  $testdevice $1 $2";
                my $errors = AnalyzeCommandChain( undef, $cs );
                if ( defined($errors) ) 
				{
                    Log3( $testdevice, 1, "ERROR $cs" );
                }
            }
        }

		
		my  $cs = "attr  $testdevice verbose 0";
               my   $errors = AnalyzeCommandChain( undef, $cs );
                 if ( defined($errors) ) 
				 {
                     Log3( $testdevice, 1, "ERROR $cs" );
                 }

		MSwitch_LoadHelper($devhash);
		Log3( $testdevice, 0, "MSWITCH-RESTORE ready -> ".$testdevice );
        $answer = $answer . "MSwitch $testdevice restored.\n";
    }
    return $answer;
}

################################################
sub MSwitch_savesys($$) {
my ( $hash, $cont ) = @_;
    my $name = $hash->{NAME};
	
	
	$cont = urlDecode( $cont );
		$cont =~ s/\n/#[nl]/g; 
		$cont =~ s/\t/    /g; 
		$cont =~ s/ /#[sp]/g; 
		$cont =~ s/\\/#[bs]/g; 
		$cont =~ s/,/#[ko]/g;
		$cont =~ s/^#\[/#[eo]/g;
		$cont =~ s/^#\]/#[ec]/g;
		$cont =~ s/\|/#[wa]/g;

	if (!defined $cont){$cont ="";};
	
	if ($cont ne '')
	{
	readingsSingleUpdate( $hash, ".sysconf", $cont, 0 ); 
	}
	else
	{
	fhem("deletereading $name .sysconf");
	}
	
	

	
return;
}
################################################
sub MSwitch_saveconf($$) {

    my ( $hash, $cont ) = @_;
    my $name = $hash->{NAME};
	my $contcopy = $cont;
	$cont =~ s/#c\[sp\]/ /g;
	$cont =~ s/#c\[se\]/;/g;
	$cont =~ s/#c\[dp\]/:/g;
	
	my @changes;
	my $info ="";
    my @found = split( /#\[EOL\]/, $cont );
    foreach (@found) 
	{

	
		 if ( $_ =~ m/#Q (.*)/ )    # setattr
			{
			push(@changes,$1);
			}
	
		if ( $_ =~ m/#I (.*)/ )    # setattr
			{
			$info =$1;
			}

	
	   if ( $_ =~ m/#VS (.*)/ )    # setattr
			{
		     if ( $1 ne $vupdate )
			 {
			 readingsSingleUpdate( $hash, ".wrong_version", $1, 0 );
			 return ;
			 }
			 
			}
	
        if ( $_ =~ m/#S (.*) -> (.*)/ )    # setreading
			{
			if ( $2 eq 'undef' || $2 eq '' || $2 eq ' ' ) 
				{
				}
			else 
				{
				my $newstring =$2;
				if ($1 eq ".Device_Affected_Details")
					{
					$newstring =~ s/;/#[se]/g; 
					$newstring =~ s/:/#[dp]/g; 
					$newstring =~ s/\t/    /g; 
					$newstring =~ s/ /#[sp]/g; 
					$newstring =~ s/\\/#[bs]/g; 
					$newstring =~ s/,/#[ko]/g;
					$newstring =~ s/^#\[/#[eo]/g;
					$newstring =~ s/^#\]/#[ec]/g;
					$newstring =~ s/\|/#[wa]/g;
					$newstring =~ s/#\[se\]#\[se\]#\[se\]/#[se]#[nl]/g;
					$newstring =~ s/#\[se\]#\[se\]/#[nl]/g;
					}
					
				if ($1 eq ".sysconf")
					{
					}
					
					
				
				if ($1 eq ".Device_Events")
					{
					$newstring =~ s/ /#[tr]/g;
					}

				readingsSingleUpdate( $hash, "$1", $newstring, 0 );
				}
			}
			
        if ( $_ =~ m/#A (.*) -> (.*)/ )    # setattr
			{
				$attr{$name}{$1} = $2;
			}
    }
	MSwitch_set_dev($hash);
	
	if (@changes > 0)
	{
	my $save = join( '|', @changes );
	readingsSingleUpdate( $hash, ".change", $save, 0 );
	}
	
		if ($info ne "")
	{
	
	
	readingsSingleUpdate( $hash, ".change_info", $info, 0 );
	}
	
	
    return;
}

################################################
sub MSwitch_backup_done($) {
    my ($string) = @_;
    return unless ( defined($string) );
    my @a      = split( "\\|", $string );
    my $Name   = $a[0];
    my $answer = $a[1];
    my $hash   = $defs{$Name};
    delete( $hash->{helper}{RUNNING_PID} );
    my $client_hash = $hash->{helper}{RESTORE_ANSWER};
    $answer =~ s/\[nl\]/\n/g;
    foreach my $testdevice ( keys %{ $modules{MSwitch}{defptr} } )    #
    {
        my $devhash = $defs{$testdevice};
        MSwitch_Createtimer($devhash);
    }
    asyncOutput( $client_hash, $answer );
    return;
}
###########################################

sub MSwitch_Execute_randomtimer($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
    my $param = AttrVal( $Name, 'MSwitch_RandomTime', '0' );
    my $min = substr( $param, 0, 2 ) * 3600;
    $min = $min + substr( $param, 3, 2 ) * 60;
    $min = $min + substr( $param, 6, 2 );
    my $max = substr( $param, 9, 2 ) * 3600;
    $max = $max + substr( $param, 12, 2 ) * 60;
    $max = $max + substr( $param, 15, 2 );
    my $sekmax = $max - $min;
    my $ret    = $min + int( rand $sekmax );
    return $ret;
}

############################################
sub MSwitch_replace_delay($$) {
    my ( $hash, $timerkey ) = @_;
    my $name = $hash->{NAME};
    my $time  = time;
    my $ltime = TimeNow();
	
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	MSwitch_LOG( $name, 5, "$name: MSwitch_replace_delay-> $timerkey"  ); 
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	
	
    my ( $aktdate, $akttime ) = split / /, $ltime;
    my $hh = ( substr( $timerkey, 0, 2 ) );
    my $mm = ( substr( $timerkey, 2, 2 ) );
    my $ss = ( substr( $timerkey, 4, 2 ) );
    my $referenz = time_str2num("$aktdate $hh:$mm:$ss");
    if ( $referenz < $time ) 
	{
        $referenz = $referenz + 86400;
    }
    if ( $referenz >= $time )
	{
    }
    $referenz = $referenz - $time;
    my $timestampGMT = FmtDateTimeRFC1123($referenz);
    return $referenz;
}

############################################################
sub MSwitch_repeat($) {
    my ( $msg, $name ) = @_;
    my $incomming = $_[0];
    my @msgarray  = split( /\|/, $incomming );
    $name      = $msgarray[1];
	
	my $time = $msgarray[2];
    my $cs        = $msgarray[0];
    my $hash      = $defs{$name};
	$cs =~ s/\n//g;
	
	
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	MSwitch_LOG( $name, 5, "$name: Repeat -> ".$cs  ); 
	MSwitch_LOG( $name, 5, "----------------------------------------"  );
	
	
    if ( $cs =~ m/set (.*)(MSwitchtoggle)(.*)/ ) 
	{
		$cs = MSwitch_toggle( $hash, $cs );
		MSwitch_LOG( $name, 5, "$name: fround toggle -> ".$cs  ); 
        
    }
	
	
	
	MSwitch_LOG( $name, 5, "$name: execute repeat $time -> ".$cs  ); 
	if ( AttrVal( $name, 'MSwitch_Debug', "0" ) ne '2' )
					{
	
	
	if ( $cs =~ m/{.*}/ ) 
		{
            eval($cs);
            if ($@) 
			{
                MSwitch_LOG( $name, 1,"$name MSwitch_repeat: ERROR $cs: $@ " . __LINE__ );
            }
        }
        else 
		{
			my $errors = AnalyzeCommandChain( undef, $cs );
			if ( defined($errors) ) 
				{
					MSwitch_LOG( $name, 1, "$name Absent_repeat $cs: ERROR : $errors -> Comand: $cs" );
				}
		}
		
		
		}
	
	 delete( $hash->{helper}{repeats}{$time} );
	
}

#########################
sub MSwitch_Createnumber($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
	my $number =  AttrVal( $Name, 'MSwitch_RandomNumber', '' )+1;
	my $number1 = int (rand ($number));
	readingsSingleUpdate( $hash, "RandomNr", $number1, 1 );
	return;		
			
	}
################################
	sub MSwitch_Createnumber1($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
	my $number =  AttrVal( $Name, 'MSwitch_RandomNumber', '' )+1;
	my $number1 = int (rand ($number));
	readingsSingleUpdate( $hash, "RandomNr1", $number1, 1 );
	return;		
	}
###############################	
	
	sub MSwitch_Safemode($) {
    my ($hash) = @_;
    my $Name = $hash->{NAME};
	if (AttrVal( $Name, 'MSwitch_Safemode', '0' ) == 0){ return;}
	my $time = gettimeofday();
	$time =~ s/\.//g;
	my $time1 =int ($time);
	my $count =0;
	my $timehash = $hash->{helper}{savemode};
	foreach my $a ( keys %{$timehash} ) 
	{
		$count++;
		if ($a < $time1-1000000)  # für 10 sekunden
			{
				delete( $hash->{helper}{savemode}{$a} );
				$count = $count-1;
			}
	}
			
	$hash->{helper}{savemode}{$time1} =$time1;		
	if ($count > $savecount)
	{
		Log3( $Name, 1, "Das Device ".$Name." wurde automatisch deaktiviert ( Safemode )" );
		$hash->{helper}{savemodeblock}{blocking} ='on';
		readingsSingleUpdate( $hash, "Safemode", 'on', 1 ); 
		foreach my $a ( keys %{$timehash} ) 
			{
				delete( $hash->{helper}{savemode}{$a} );
			}
		$attr{$Name}{disable}       = '1'; 
	}
	return;	
	}

###############################################################
sub MSwitch_EventBulk($$$){
	my ( $hash, $event, $update ) = @_;

	my $name = $hash->{NAME};

	return if !defined $event;
	return if !defined $hash;
	if ($hash eq ""){return;}
	my @evtparts = split( /:/, $event );
	$update ='1';
	
    my $evtsanzahl = @evtparts;
    if ( $evtsanzahl < 3 ) 
	{
        my $eventfrom = $hash->{helper}{eventfrom};
        unshift( @evtparts, $eventfrom );
        $evtsanzahl = @evtparts;
    }
    my $evtfull = join( ':', @evtparts );
	$evtparts[2] ='' if !defined $evtparts[2];

	if (ReadingsVal( $name, 'last_event', '' ) ne $event && $event ne '')
		{
	
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "EVENT",    $event )       if $event ne '';
		readingsBulkUpdate( $hash, "EVTFULL",  $evtfull )     if $evtfull ne '';
		readingsBulkUpdate( $hash, "EVTPART1", $evtparts[0] ) if $evtparts[0] ne '';
		readingsBulkUpdate( $hash, "EVTPART2", $evtparts[1] ) if $evtparts[1] ne '';
		readingsBulkUpdate( $hash, "EVTPART3", $evtparts[2] ) if $evtparts[2] ne '';
		readingsBulkUpdate( $hash, "last_event", $event ) if $event ne '';
		readingsEndUpdate( $hash, $update );
		}
		return;
}
##########################################################


# setzt reihenfolge und testet ID
sub MSwitch_priority(@) 
{
	my ( $hash,$execids, @devices ) = @_;
	my $name = $hash->{NAME};

	
	MSwitch_LOG( $name, 5, "$name:     zuweisung der reihenfolge und der id" );
	
	if ( AttrVal( $name, 'MSwitch_Expert', "0" ) ne'1' )
            {
			return @devices;
			}
			
		
			
	my %devicedetails = MSwitch_makeCmdHash($name);
	
	#	my $execids = "0" if !defined $execids;
	
	my %new;
		foreach my $device (@devices) 
		{
		
		
		# $execids beinhaltet auszuführende ids gesetzt bei init
		
		    my $key1 = $device . "_id";
			Log3( $name, 5, "$name:     device hat die ID $device - $devicedetails{$key1}" );
			next if $devicedetails{$key1} ne $execids; 
		
			my $key = $device . "_priority";
			
			
			my $prio = $devicedetails{$key};
			
			MSwitch_LOG( $name, 5, "$name:     device hat die priority $device - $devicedetails{$key1}" );
			$new{$device}=$prio;
			
			
			
			
			
		}
		
		
		my @new = %new;
		my @newlist;
		for my $key (sort { $new{ $a } <=> $new{ $b } } keys %new)
		{
		if ($key ne "" && $key ne " "){
			push(@newlist,$key);
			}
		}
		@devices=@newlist;
		my $test = join( '|', @devices );
		return @devices;
}


##########################################################




sub MSwitch_set_dev($) {
# setzt NOTIFYDEF
    my ($hash) = @_;
    my $name = $hash->{NAME};
	my $not         = ReadingsVal( $name, 'Trigger_device', '' );
        if ( $not ne 'no_trigger' ) 
		{
            if ( $not eq "all_events" ) 
			{
                delete( $hash->{NOTIFYDEV} );
                if ( ReadingsVal( $name, '.Trigger_Whitelist', '' ) ne '' )
				{
                    $hash->{NOTIFYDEV} =
                      ReadingsVal( $name, '.Trigger_Whitelist', '' );
                }
            }
            else 
			{
                $hash->{NOTIFYDEV} = $not;
                my $devices = MSwitch_makeAffected($hash);
                $hash->{DEF} = $not . ' # ' . $devices;
            }
        }
        else 
		{
            $hash->{NOTIFYDEV} = 'no_trigger';
            delete $hash->{DEF};
        }
}	


##############################################################

sub MSwitch_dec($$) {
# ersetzungen direkt vor befehlsausführung
my ( $hash, $todec) = @_;
my $name = $hash->{NAME};
$todec =~ s/\n//g;
$todec =~ s/#\[wa\]/|/g; 


	$todec =~ s/\$NAME/$hash->{helper}{eventfrom}/;
	
	$todec =~ s/MSwitch_Self/$name/;
	
	
	
	
	
	my $x = 0;
    while ( $todec =~ m/(.*?)(\$SELF)(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$todec = $firstpart.$name.$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}


 # setmagic ersetzun
				 $x =0;
				while ( $todec =~ m/(.*)\[(.*)\:(.*)\](.*)/ ) 
					{
					$x++;                        # notausstieg notausstieg
					last if $x > 20;             # notausstieg notausstieg
					my $setmagic = ReadingsVal( $2, $3, 0 );
					$todec = $1.$setmagic.$4;
					}
					
					
return $todec;				
}
	
################################################################
sub MSwitch_clearlog($){

my ( $hash, $cs) = @_;
my $name = $hash->{NAME};

open( BACKUPDATEI, ">./log/MSwitch_debug_$name.log" ); 
print BACKUPDATEI localtime()." Starte Log\n";    #
  
    
close(BACKUPDATEI);

}
################################################################



sub MSwitch_debug2($$) {

my ( $hash, $cs) = @_;
my $name = $hash->{NAME};
return if $cs eq '';
open( BACKUPDATEI, ">>./log/MSwitch_debug_$name.log" );    # Datei zum Schreiben öffnen
print BACKUPDATEI localtime().": -> $cs\n";    #
  
    
close(BACKUPDATEI);
}
##################################



##################################
sub MSwitch_LOG($$$) 
{

my ( $name,$level, $cs) = @_;
my $hash = $defs{$name};


	if ( AttrVal( $name, 'MSwitch_Debug', "0" ) eq '2' || AttrVal( $name, 'MSwitch_Debug', "0" ) eq '3' )
		{
		MSwitch_debug2($hash, $cs);
		}


Log3( $name, $level, $cs );	

}
#########################
sub MSwitch_confchange($$) 
{

# change wenn folgende einträge vorhanden 

#I testinfo
#Q dummy1#zu schaltendes geraet#device

my ( $hash, $cs) = @_;
my $name = $hash->{NAME};
MSwitch_clearlog($hash);

$cs = urlDecode( $cs );
$cs =~ s/#\[sp\]/ /g;

my @changes = split( /\|/, $cs );
	 foreach my $change (@changes) 
	{
    #MSwitch_LOG( $name, 5, "zu ersetzen: ".$change );	
	my @names = split( /#/, $change );
	
	# afected devices
	my $tochange1 = ReadingsVal( $name, ".Device_Affected", "" );
	my $oldname = $names[0]."-";
	my $newname = $names[1]."-";
	my @devices = split( /,/,$tochange1 );
	my $x =0;
	foreach  (@devices)
	{
	$_    =~  s/$oldname/$newname/g;
	$devices[$x] = $_;
	$x++;
	}
	my $newdevices  = join( ',', @devices );
readingsSingleUpdate( $hash, ".Device_Affected", $newdevices, 0 );





	#details
	my $tochange2 = ReadingsVal( $name, ".Device_Affected_Details", "" );
Log3( $name, 0, "vor change: ".$tochange2 );	
	my @devicesdetails = split( /#\[ND\]/,$tochange2 );
	$x =0;
	foreach  (@devicesdetails)
	{
	$_    =~  s/$oldname/$newname/g;
	$devicesdetails[$x] = $_;
	$x++;
	}
	$tochange2  = join( '#[ND]', @devicesdetails );
	
#Log3( $name, 0, "oldname: ".$oldname );	
#Log3( $name, 0, "newname: ".$newname );	

#Log3( $name, 0, "navh change: ".$tochange2 );	
	
	$x = 0;
    while ( $tochange2 =~ m/(.*?)($names[0])(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$tochange2 = $firstpart.$names[1].$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}
	
#	Log3( $name, 0, "navh 2 change: ".$tochange2 );	
	
	
readingsSingleUpdate( $hash, ".Device_Affected_Details", $tochange2, 0 );
	}
fhem("deletereading $name .change");
fhem("deletereading $name .change_info");
}
#########################

sub MSwitch_makefreecmd($$) {
#ersetzungen und variablen für freecmd
	my ( $hash, $cs) = @_;
    my $name = $hash->{NAME};

				my $ersetzung ="";
				
				
				# entferne kommntarzeilen
				$cs =~ s/#.*\n//g;	
				# entferne zeilenumbruch
				$cs =~ s/\n//g;
				
				# ersetze Eventvariablen
				$ersetzung = ReadingsVal( $name, "EVTPART3", "" );
				$cs =~ s/\$EVTPART3/$ersetzung/g;
				$ersetzung = ReadingsVal( $name, "EVTPART2", "" );
				$cs =~ s/\$EVTPART2/$ersetzung/g;
				$ersetzung = ReadingsVal( $name, "EVTPART1", "" );
				$cs =~ s/\$EVTPART1/$ersetzung/g;
				$ersetzung = ReadingsVal( $name, "EVENT", "" );
				$cs =~ s/\$EVENT/$ersetzung/g;
				$ersetzung = ReadingsVal( $name, "EVENTFULL", "" );
				$cs =~ s/\$EVENTFULL/$ersetzung/g;
				
				$cs =~ s/\$NAME/$hash->{helper}{eventfrom}/;
				
				
				
				#$cs =~ s/\$SELF/$name/;
				
				
	my $x = 0;
    while ( $cs =~ m/(.*?)(\$SELF)(.*)?/)
	{
		my $firstpart = $1;
		my $secondpart = $2;
		my $lastpart = $3;
		$cs = $firstpart.$name.$lastpart;
		$x++;
		last if $x > 10;    #notausstieg
	}
				
				
                # setmagic ersetzun
	MSwitch_LOG( $name, 5, "vor freecmd: ".$cs );	
				$x =0;
				while ( $cs =~ m/(.*)\[(.*)\:(.*)\](.*)/ ) 
					{
					$x++;                        # notausstieg notausstieg
					last if $x > 20;             # notausstieg notausstieg
					my $setmagic = ReadingsVal( $2, $3, 0 );
					$cs = $1.$setmagic.$4;
					}
					
	MSwitch_LOG( $name, 5, "after freecmd: ".$cs );				
					
					
					
	return $cs;
}

#################################					


		#	devices = devices.replace(/:/g,'#[dp]');
		#	devices = devices.replace(/;/g,'#[se]');
		#	devices = devices.replace(/ /g,'#[sp]');

		# auskommentierte wurden bereits dur jscript ersetzt
		# $savedetails =~ s/#\[wa\]/|/g; 
		# $savedetails =~ s/\n/#[nl]/g; 
		# $savedetails =~ s/;/#[se]/g; 
		# $savedetails =~ s/\:/#[dp]/g;
		# $savedetails =~ s/\t/    /g; 
		# $savedetails =~ s/ /#[sp]/g; 
		# $savedetails =~ s/\\/#[bs]/g; 
		# $savedetails =~ s/,/#[ko]/g;
		# $savedetails =~ s/^#\[/#[eo]/g;
		# $savedetails =~ s/^#\]/#[ec]/g;
		# $savedetails =~ s/\|/#[wa]/g;

		
1;

=pod
=item helper
=item summary       MultiswitchModul
=item summary_DE    Modul zum event und zeitgesteuerten Schalten von Devices etc.

=begin html

<a name="MSwitch"></a>
<h3>MSwitch</h3>
<ul>
  <u><b>MSwitch</b></u>
  <br />
MSwitch is an auxiliary module that works both event- and time-controlled. <br />
  For a detailed description see Wiki
  <br /><br />
  <a name="MSwitchdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt; Name &gt; MSwitch;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define Schalter MSwitch</code><br />
    </ul>
    <br />
    The command creates a device of type MSwitch named Switch. <br />
    All further configuration takes place at a later time and can be modified and adjusted within the device at any time
  </ul>
  <br /><br />
  <a name="MSwitch set"></a>
  <b>Set</b>
  <ul>
  <li> inactive - sets the device inactive </li>
    <li> active - sets the device active </li>
    <li> backup MSwitch - creates a backup file with the configuration of all MSwitch devices </li>
    <li> del_delays - deletes all pending timed commands </li>
    <li> exec_cmd1 - immediate execution of the command branch1 </li>
    <li> exec_cmd2 - immediate execution of command branch2 </li>
    <li> fakeevent [event] - simulation of an incoming event </li>
    <li> wait [sec] - no acceptance of events for given period </li>
    <br />
  </ul>
  <br /><br />
  <a name="MSwitch get"></a>
  <b>Get</b>
  <ul>
 <li> active_timer show - displays a list of all pending timers and delays </li>
    <li> active_timer delete - deletes all pending timers and delays. Timers are recalculated </li>
    <li> get_config - shows the config set  associated with the device</li>
    <li> restore_Mswitch_date this_device - restore the device from the backupfile </li>
    <li> restore_Mswitch_date all_devices - restore all MSwitchdevices from the backupfile </li>
    <br />
  </ul>
  <br /><br />
  <a name="MSwitch attribut"></a>
  <b>Attribute</b>
  <ul>
  <li> MSwitch_Help: 0.1 - displays help buttons for all relevant fields </li>
    <li> MSwitch_Debug: 0,1,2,3 - 1. switches test fields to Conditions etc. / 2. Testmode, no active cmds / 3. pure development mode </li>
    <li> MSwitch_Expert: 0.1 - 1. enables additional options such as global triggering, priority selection, command repetition, etc. </li>
    <li> MSwitch_Delete_Delays: 0.1 - 1. deletes all pending delays when another suitable event arrives</li>
    <li> MSwitch_Include_Devicecmds: 0,1 - 1. all devices with own command set (set?) are included in affected devices </li>
    <li> MSwitch_Include_Webcmds: 0.1 - 1. all devices with existing WbCmds are included in affected devices </li>
    <li> MSwitch_Include_MSwitchcmds: 0.1 - 1. all devices with existing MSwitchcmds are included in affected devices </li>
    <li> MSwitch_Activate_MSwitchcmds: 0.1 - 1. activates the attribute MSwitchcmds in all devices </li>
    <li> MSwitch_Lock_Quickedit: 0,1 - 1. activates the lock of the selection field 'affected devices' </li>
    <li> MSwitch_Ignore_Types: - List of all device types that are not displayed in the 'affected devices' </li>
    <li> MSwitch_Trigger_Filter - List of events to ignore </li>
    <li> MSwitch_Extensions: 0.1 - 1. Enables additional option Devicetogggle </li>
	<li>MSwitch_Startdelay - delays the start of MSwitch after Fhemstart by the specified time in seconds. Recommended: 30 seconds</li>
    <li> MSwitch_Inforoom - contains a room name where MSwitches are displayed in detail </li>
    <li> MSwitch_Mode: Full, Notify, Toggle - Device Operation Mode </li>
    <li> MSwitch_Condition_Time: 0.1 - activation of the trigger conditions for timed triggering </li>
    <li> MSwitch_Safemode: 0.1 - 1. aborts all actions of the device if more than 20 calls per second take place </li>
    <li> MSwitch_RandomTime - see Wiki </li>
    <li> MSwitch_RandomNumber - see Wiki </li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="MSwitch"></a>
<h3>MSwitch</h3>
<ul>
  <u><b>MSwitch</b></u>
  <br />
  MSwitch ist ein Hilfsmodul , das sowohl event-, als auch zeitgesteuert arbeitet.<br />
  Für eine umfangreche Beschreibung siehe Wiki: https://wiki.fhem.de/wiki/MSwitch
  <br /><br />
  <a name="MSwitchdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt; Name &gt; MSwitch;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define Schalter MSwitch</code><br />
    </ul>
    <br />
    Der Befehl legt ein Device vom Typ MSwitch an mit dem Namen Schalter.<br />
    sämtliche weitere Konfiguration erfolgt zu einem späteren Zeitpunkt und kann innerhalb des Devices jerderzeit verändert und angepasst werden
  </ul>
  <br /><br />
  <a name="MSwitch set"></a>
  <b>Set</b>
  <ul>
    <li>inactive - setzt das Device inaktiv</li>
    <li>active - setzt das Device aktiv</li>
    <li>backup MSwitch - legt eine Backupdatei mit der Konfiguration aller MSwitchdevices an</li>
    <li>del_delays - löscht alle anstehenden timer für zeitversetzte Befehle</li>
    <li>exec_cmd1 - sofortiges Ausführen des Kommandozweiges1</li>
    <li>exec_cmd2 - sofortiges Ausführen des Kommandozweiges2</li>
    <li>fakeevent [event] - simulation eines eingehenden Events</li>
    <li>wait [sek] - keine annahme von Events für vorgegebenen Zeitraum</li>
    <br />
  </ul>
  <br /><br />
  <a name="MSwitch get"></a>
  <b>Get</b>
  <ul>
    <li>active_timer show - zeigt eine Liste aller anstehenden Timer und Delays</li>
    <li>active_timer delete - löscht alle anstehenden Timer und Delays. Timer werden neu berechnet</li>
    <li>get_config - zeigt den dem Device zugeordneten Configsatz</li>
    <li>restore_Mswitch_date this_device - restore des Devices aus dem Backupfile</li>
    <li>restore_Mswitch_date all_devices - restore aller MSwitchdevices aus dem Backupfile</li>
    <br />
  </ul>
  <br /><br />
  <a name="MSwitch attribut"></a>
  <b>Attribute</b>
  <ul>
    <li>MSwitch_Help:0,1 - zeigt Hilfebuttons zu allen relevanten Feldern</li>
    <li>MSwitch_Debug:0,1,2 - 1. schaltet Prüffelder zu Conditions etc. an / 2. Testmode shreibt alle Aktionen in ein seperates Log, führt diese aber nicht aus / 3. reiner Entwicklungsmode</li>
    <li>MSwitch_Expert:0,1 - 1. aktiviert Zusatzoptionenv wi z.B globales triggern, prioritätsauswahl, Befehlswiederholungesn etc. </li>
    <li>MSwitch_Delete_Delays:0,1 - 1. löscht alle anstehenden Delays bei erneutem eintreffen eines passenden Events</li>
    <li>MSwitch_Include_Devicecmds:0,1 - 1. alles Devices mit eigenem Befehlssatz (set ?) werden in affected Devices einbezogen</li>
    <li>MSwitch_Include_Webcmds:0,1 - 1. alles Devices mit vorhandenen WbCmds werden in affected Devices einbezogen</li>
    <li>MSwitch_Include_MSwitchcmds:0,1 - 1. alles Devices mit vorhandenen MSwitchcmds werden in affected Devices einbezogen</li>
    <li>MSwitch_Activate_MSwitchcmds:0,1 - 1. aktiviert in allen Devices das Attribut MSwitchcmds</li>
    <li>MSwitch_Lock_Quickedit:0,1 - 1. aktiviert die sperre des Auswahlfeldes 'affected devices'</li>
    <li>MSwitch_Ignore_Types: - Liste aller DeviceTypen , die nicht in den 'affected devices' dargestellt werden'</li>
    <li>MSwitch_Trigger_Filter - Liste aller zu ignorierenden Events</li>
    <li>MSwitch_Extensions:0,1 - 1. aktiviert zusatzoption Devicetogggle</li>
	<li>MSwitch_Startdelay - verzögert den Start von MSwitch nach Fhemstart um die angegebene Zeit in Sekunden . Empfohlen:30 sekunden</li>
    <li>MSwitch_Inforoom - beinhalttet einen Raumnamen , in dem MSwitches detailiert dargestellt werden</li>
    <li>MSwitch_Mode:Full,Notify,Toggle - Betriebsmodus des Devices</li>
    <li>MSwitch_Condition_Time:0,1 - zuschaltung der Triggerconditions für zeitgesteuertes Auslösen</li>
    <li>MSwitch_Safemode:0,1 - 1. bricht alle Aktionen des Devices ab, wenn mehr als 20 Aufrufe pro Sekunde erfolgen</li>
    <li>MSwitch_RandomTime - siehe Wiki</li>
    <li>MSwitch_RandomNumber - siehe Wiki</li>

  </ul>
</ul>

=end html_DE

=cut


