#################################################################################################################
# $Id$
#################################################################################################################
#
# Daikin Airconditioning webconnect interface
#
# Roel Bouwman (roel@bouwman.net) / 3/2020
#
#################################################################################################################

package main;

use strict;
use warnings;
our $ERR = '';

eval "use LWP::UserAgent;1" or $ERR.= "Required module LWP::UserAgent missing";
eval "use HTTP::Request;1"  or $ERR.= "Required module HTTP::Request mssing";
eval "use JSON;1"  or $ERR.= "Required module JSON mssing";

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local;
use List::Util qw(sum);
use Blocking;

# Version history
#
# REMINDER: Don't forget to update version number in META.json info at bottom of file
#
our %HVAC_DaikinAC_VERSION = (
  "1.0.9"  => "28.05.2020  Added on and off shortcut commands, as expected by for example the Alexa module",
  "1.0.8"  => "21.04.2020  Initial checkin into FHEM repository. Fixed some syntax errors in documentation HTML. No code changes",
  "1.0.7"  => "11.04.2020  Added two examples to define Usage error and documentation; add interval and interval_powered attributes on startup for clarity; Poll daily and monthly power usage statistics once per hour, so that the current days and current months usage are represented correctly",
  "1.0.6"  => "04.04.2020  Bugfix in pwrconsumption code that caused 'Label not found' error",
  "1.0.5"  => "02.04.2020  Differentiate between polling intervals based on poweron status to allow for faster polling when powered on; added power usage statistics; set shum through relative offset and check if shum%5=0; added info on sane logging to documentation",
  "1.0.4"  => "01.04.2020  Changed compfreq to cmpfreq, and get update has now become a set command (set refresh) - set update still works",
  "1.0.3"  => "31.03.2020  Bugfix in reschedule on aborted polls; bugfix on powerful/streamer modes; added econo mode; added cmpfreq and name readings; added set update feature; added powerful, econo and streamer on/off readings. Thanks to \@hugomckinley for his feedback",
  "1.0.2"  => "26.03.2020  Rename to 58_HVAC_DaikinAC, cleanup loglevels, removed unused constant definitions, comment cleanup",
  "1.0.1"  => "26.03.2020  Documentation included, ready for production",
  "1.0.0"  => "23.03.2020  Initial version"
);

our $HVAC_DaikinAC_RE_IPADDRESS = qr/^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$/;
our $HVAC_DaikinAC_RE_HOSTNAME = qr/^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/;
our %HVAC_DaikinAC_MODE = (
	0	=> 'auto',
	1	=> 'auto',
	2	=> 'dehumidify',
	3	=> 'cool',
	4	=> 'heat',
	6	=> 'vent'
);
our %HVAC_DaikinAC_SWING = (
	0	=> 'none',
	1	=> 'vertical',
	2	=> 'horizontal',
	3	=> '3d',
);
our %HVAC_DaikinAC_RATE = (
	"A" => "auto",
	"B" => "silent",
	"3" => "lowest",
	"4" => "low",
	"5" => "medium",
	"6" => "high",
	"7" => "highest",
);

# Initialize
#
sub HVAC_DaikinAC_Initialize($) {
	my ($hash) = @_;
	$hash->{"DefFn"}	= "HVAC_DaikinAC_Define";
	$hash->{"UndefFn"}	= "HVAC_DaikinAC_Undef";
	$hash->{"GetFn"}	= "HVAC_DaikinAC_Get";
	$hash->{"SetFn"}	= "HVAC_DaikinAC_Set";
	$hash->{"AttrList"}	= "timeout:slider,0,1,60 " .
					"interval " .
					"interval_powered " .
					"pwrconsumption:1,0 " .
					"disable:1,0 " .
					"rawdata:1,0 " .
					$readingFnAttributes;
	$hash->{"AttrFn"}	= "HVAC_DaikinAC_Attr";

	eval { FHEM::Meta::InitMod( __FILE__, $hash ) };
	return;
} # Initialize()

# Define
# Syntax: define <name> HVAC_DaikinAC <hostname or IP address> [interval=60]
#
# Defines a new HVAC_DaikinAC device that has a Wifi interface on the provided
# hostname or IP address
# Automatic status polling will be done every [ interval ] seconds.
# If not supplied, this defaults to 60 seconds
#
sub HVAC_DaikinAC_Define($$) {
	my ($hash, $def) = @_;
	my $name = $hash->{"NAME"};
	my @F = split("[ \t][ \t]*", $def);
	our $ERR;

	Log3($name, 5, "$name HVAC_DaikinAC_Define(): entry");

	my $SYNTAX = "Syntax: define <name> HVAC_DaikinAC <hostname/ip> [interval=60] [interval_powered=10]"
			."\n\nExamples:\n\n"
			."    define MYDEVICENAME HVAC_DaikinAC 172.12.1.10\n\n"
			."      create a device with name MYDEVICENAME. Unit has IP address 172.12.1.10.\n"
			."      Use the default polling intervals (60 seconds when off, 10 seconds when\n"
			."      powered on)\n\n"
			."    define MYDEVICENAME HVAC_DaikinAC daikin-living.mydomainname 300 60\n\n"
			."      create a device with name MYDEVICENAME. Unit can be reached through DNS\n"
			."      name daikin-living.mydomainname. Set polling intervals to 300 seconds\n"
			."      when turned off and 60 seconds when the unit is powered on.\n";

	return "Error initializing: ".$ERR if ($ERR);
	return $SYNTAX if scalar(@F)<3 or scalar(@F)>5;

	my @v = reverse sort keys our %HVAC_DaikinAC_VERSION;

	$hash->{"VERSION"}	= shift @v;
	$hash->{"LASTUPDATE"}	= 0;
	$hash->{"INTERVAL"}	= defined($F[3])?int($F[3]):60;
	$hash->{"INTERVAL_PWRD"}	= defined($F[4])?int($F[4]):10;
	$hash->{"HOST"}		= $F[2];
	$hash->{"INITIALIZED"}	= 0;
	$hash->{"HELPER"}{"FAULTS"}	= 0;

	# Verify supplied hostname.
	# Do not fail if we are unable to resolve or reach at this time, just verify syntax.
	#
	our $HVAC_DaikinAC_RE_IPADDRESS;
	our $HVAC_DaikinAC_RE_HOSTNAME;
	$hash->{"HOST"} =~ m/$HVAC_DaikinAC_RE_IPADDRESS/ or $hash->{"HOST"} =~ m/$HVAC_DaikinAC_RE_HOSTNAME/ or return "Invalid hostname - $SYNTAX";

	# Set default attributes
	#
	# stateFormat & devStateIcon for representation purposes in FHEM webinterface
	#
	our $attr;
	$attr{$name}{"stateFormat"} = "power/mode\n<br>In: htemp &degC <br>Out: otemp &degC" if !exists($attr{$name}{"stateFormat"});
	$attr{$name}{"devStateIcon"} = "off.*:control_standby\@gray on.*cool:frost\@blue on.*heat:sani_heating\@red on.*dehumidify:humidity\@blue on.*vent:vent_ventilation\@green on.*auto:temp_temperature\@red" if !exists($attr{$name}{"devStateIcon"});
	$attr{$name}{"interval"} = $hash->{"INTERVAL"};
	$attr{$name}{"interval_powered"} = $hash->{"INTERVAL_PWRD"};

	# All OK. Set up the first poll to our AC system and finish up
	#
	InternalTimer(gettimeofday()+1, "HVAC_DaikinAC_StartPoll", $hash, 0);
	return undef;
} # Define()

# Undefine
#
# Removes HVAC_DaikinAC device
# Drop timer and kill any running poll
#
sub HVAC_DaikinAC_Undef($$) {
	my ($hash, $name) = @_;

	#
	# Remove any poll timers
	#
	RemoveInternalTimer($hash);

	#
	# Kill both blocking poll and write helper if currently active
	#
	BlockingKill($hash->{"HELPER"}{"POLL_PID"}) if exists($hash->{"HELPER"}{"POLL_PID"});
	BlockingKill($hash->{"HELPER"}{"WRITE_PID"}) if exists($hash->{"HELPER"}{"WRITE_PID"});
	return undef;
} # Undefine()

# Get
#
# update:nodata - Force reread of data from device
#
sub HVAC_DaikinAC_Get($$) {
	my ($hash, $name, @a) = @_;

	return undef;
} # Get()

# Write($s)
#
# Nonblocking function that writes new settings to aircon unit using HTTP
# $s is the setting to change
#
sub HVAC_DaikinAC_Write {
	my ($s) = @_;
	my $name;
	($name,$s)	= split '\|', $s, 2;
	our $defs;
	my $hash	= $defs{$name};
	Log3 ($name, 5, "$name HVAC_DaikinAC_Write($s): starting");

	my ($chmode, $pow, $f_mode, $stemp, $shum, $f_rate, $f_dir) = (
		0,
		$defs{$name}{"READINGS"}{"pow"}{"VAL"},
		$defs{$name}{"READINGS"}{"f_mode"}{"VAL"},
		$defs{$name}{"READINGS"}{"stemp"}{"VAL"},
		$defs{$name}{"READINGS"}{"shum"}{"VAL"},
		$defs{$name}{"READINGS"}{"f_rate"}{"VAL"},
		$defs{$name}{"READINGS"}{"f_dir"}{"VAL"}
	);

	# Process changes provided in $s
	# Format is "var=val" where var follows device naming
	#
	my ($key, $val) = split /=/, $s, 2;
	my $q;
	SWITCH: {
		$q=sprintf("http://%s/", $hash->{"HOST"});

		# Handle special modes first
		#
		$key eq "powerful" && $val =~ m/^[01]$/ && do {
			$q = sprintf($q . "aircon/set_special_mode?spmode_kind=%d&set_spmode=%d", 1, $val);
			last SWITCH;
		};
		$key eq "econo" && $val =~ m/^[01]$/ && do {
			$q = sprintf($q . "aircon/set_special_mode?spmode_kind=%d&set_spmode=%d", 2, $val);
			last SWITCH;
		};
		$key eq "streamer" && $val =~ m/^[01]$/ && do {
			$q = sprintf($q . "aircon/set_special_mode?en_streamer=%d", $val);
			last SWITCH;
		};
		$key eq "reboot" && $val == 1 && do {
			$q = sprintf($q . "common/reboot");
			last SWITCH;
		};

		# Not a special mode, so we continue with /set_control_info
		#
		$q .= "aircon/set_control_info?";

		$key eq "pow" && do { $pow=$val; goto ENDSWITCH; };
		$key eq "f_mode" && do { $chmode=1; $f_mode=$val; goto ENDSWITCH; };
		$key eq "stemp" && do {
			# Handle relative offset
			#
			$val =~ m/^[+-](.*)$/ && do { $stemp+=$val; goto ENDSWITCH; };
			$stemp=$val; goto ENDSWITCH;
		};
		$key eq "shum" && do {
			# Handle relative offset
			#
			$val =~ m/^[+-](.*)$/ && do {
				$shum+=$val;
				$shum = 0 if $shum<0;
				$shum = 100 if $shum>100;
				goto ENDSWITCH;
			};
			$shum=$val; goto ENDSWITCH;
		};
		$key eq "f_rate" && do { $f_rate=$val; goto ENDSWITCH; };
		$key eq "f_dir" && do { $f_dir=$val; goto ENDSWITCH; };

		# We should never get here with a valid call. But if we do, log an error and return
		# 

		Log3($name, 3, "$name HVAC_DaikinAC_Write(): invalid request: " . $s);
		return $name;

		ENDSWITCH:

		# Build our URL / query string for queries to /aircon/set_control_info
		#
		$q=sprintf($q."pow=%d&f_rate=%s&f_dir=%d&mode=%d",
				$pow, $f_rate, $f_dir, $f_mode
		);

		# Add stemp and shum as needed
		#
		!$chmode && do {
			$q.=sprintf("&stemp=%s&shum=%s", $stemp eq ""?"--":$stemp, $shum eq ""?"--":$shum);
			last SWITCH;
		};

		# If we are changing modes (to, cool, heat, vent, dehumidify or auto), we need to use stored values for stemp/shum
		#
		($f_mode eq 0 || $f_mode eq 1) && do {
			# Set automatic mode. Use stored setpoint and humidity
			$q.=sprintf("&stemp=%.1f&shum=%s", $defs{$name}{"READINGS"}{"dt1"}{"VAL"} || "22", $defs{$name}{"READINGS"}{"dh1"}{"VAL"} || 'AUTO');
			last SWITCH;
		};
		$f_mode eq 2 && do {
			# Set dehumify mode. We need to send "M" as temperature setpoint
			$q.=sprintf("&stemp=M&shum=%d", $shum);
			last SWITCH;
		};
		$f_mode eq 3 && do {
			# Set cooling mode. Use stored setpoint and humidity if switching mode
			$q.=sprintf("&stemp=%.1f&shum=%d", $defs{$name}{"READINGS"}{"dt3"}{"VAL"} || "18", $defs{$name}{"READINGS"}{"dh3"}{"VAL"} || 0);
			last SWITCH;
		};
		$f_mode eq 4 && do {
			# Set heating mode. Use stored setpoint and humidity if switching mode
			$q.=sprintf("&stemp=%.1f&shum=%d", $defs{$name}{"READINGS"}{"dt4"}{"VAL"} || "24", $defs{$name}{"READINGS"}{"dh4"}{"VAL"} || 0);
			last SWITCH;
		};
		$f_mode eq 6 && do {
			# Set ventilation mode. We need to send "--" as both setpoint and stemp
			$q.="&stemp=--&shum=--";
			last SWITCH;
		};
	};

	# We now have a valid request string in $q
	#

	Log3 ($name, 5, "$name HVAC_DaikinAC_Write(): request " . $q);

	my $timeout  = AttrVal($name, "timeout", 5);
	my $ua = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => $timeout);
        my $req = HTTP::Request->new('GET', $q);
        my $r = $ua->request($req);

	if (!$r->is_success) {
		Log3($name, 3, "$name HVAC_DaikinAC_Write(): FAILED request to " . $q . ": " .  $r->decoded_content);
	} else {
		Log3($name, 5, "$name HVAC_DaikinAC_Write(): Success - response: " . $r->decoded_content);
	}

	return $name;
} # Write()

# WriteDone
#
# Callback after successful completion of write
#
sub HVAC_DaikinAC_WriteDone($) {
	my ($name)			= @_;
	our $defs;

	my $hash = $defs{$name};
	delete($hash->{"HELPER"}{"POLL_PID"});

	Log3 ($name, 5, "$name HVAC_DaikinAC_Write(): finished");

	# Schedule a direct poll
	HVAC_DaikinAC_StartPoll($hash);

	return undef;
} # Writedone()

# WriteAbort
#
# Callback after unsuccessful completion of write
#
sub HVAC_DaikinAC_WriteAbort(@) {
	my ($hash,$cause)	= @_;
	my $name		= $hash->{"NAME"};

	delete($hash->{"HELPER"}{"WRITE_PID"});

	# Provide some sensible feedback to our users in log
	#
	$cause = "Timeout while attempting to write settings to " . $hash->{"HOST"} . " ($cause)";
	Log3 ($name, 2, "$name HVAC_DaikinAC_Write(): failed (" . $hash->{"HELPER"}{"WRITE_PID"}{"fn"} . ") - " . $cause);
	return undef;
} # WriteAbort()

sub HVAC_DaikinAC_Set($@) {
	my ($hash, $name, @a) = @_;
	return undef if not scalar @a;
	my $cmd = shift(@a);
	our %HVAC_DaikinAC_MODE;
	our %HVAC_DaikinAC_SWING;
	our %HVAC_DaikinAC_RATE;
	my $s;

	return "Device $name is currently disabled" if IsDisabled($name);

	Log3 ($name, 5, "$name HVAC_DaikinAC_Set(): setting " . join(" ", @a));

	SWITCH: {
		($cmd eq "update" || $cmd eq "refresh") && do {
			# Force reread of basic_info and model_info and force a poll
			BlockingKill($hash->{"HELPER"}{"POLL_PID"}) if exists($hash->{"HELPER"}{"POLL_PID"});
			delete $hash->{"HELPER"}{"POLL_PID"};
			$hash->{"INITIALIZED"} = 2;
			HVAC_DaikinAC_StartPoll($hash);
			return undef;
		};
		$hash->{"INITIALIZED"} or return "Not initialized - nu current values";
		$cmd eq "on" && do {
			$s = "pow=1";
			last SWITCH;
		};
		$cmd eq "off" && do {
			$s = "pow=0";
			last SWITCH;
		};
		$cmd eq "power" && do {
			my $val = shift @a or goto usage;;
			my %str2i = qw(off 0 on 1);
			goto usage if !exists($str2i{$val});
			$s = sprintf("pow=%d", $str2i{$val});
			last SWITCH;
		};
		$cmd eq "mode" && do {
			my $val = shift @a or goto usage;;
			my %str2i = reverse %HVAC_DaikinAC_MODE;
			goto usage if !exists($str2i{$val});
			$s = sprintf("f_mode=%d", $str2i{$val});
			last SWITCH;
		};
		$cmd eq "stemp" && do {
			my $val = shift @a or goto usage;;
			goto usage if !$val =~ m/^[+-]?\d+([\.]\d)?$/;
			$s = sprintf("stemp=%s", $val);
			last SWITCH;
		};
		$cmd eq "shum" && do {
			my $val = shift @a;
			goto usage if !defined($val);
			goto usage if not ($val =~ m/^[+-]?(\d+)$/);
			goto usage if $1 > 100;
			goto usage if $1%5;
			$s = sprintf("shum=%s", $val);
			last SWITCH;
		};
		$cmd eq "rate" && do {
			my $val = shift @a or goto usage;;
			my %str2i = reverse %HVAC_DaikinAC_RATE;
			goto usage if !exists($str2i{$val});
			$s = sprintf("f_rate=%s", $str2i{$val});
			last SWITCH;
		};
		$cmd eq "swing" && do {
			my $val = shift @a or goto usage;;
			my %str2i = reverse %HVAC_DaikinAC_SWING;
			goto usage if !exists($str2i{$val});
			$s = sprintf("f_dir=%d", $str2i{$val});
			last SWITCH;
		};
		$cmd eq "powerful" && do {
			my $val = shift @a or 1;
			$s = sprintf("powerful=%d", $val eq "off" || !$val?0:1);
			last SWITCH;
		};
		$cmd eq "econo" && do {
			my $val = shift @a or 1;
			$s = sprintf("econo=%d", $val eq "off" || !$val?0:1);
			last SWITCH;
		};
		$cmd eq "streamer" && do {
			my $val = shift @a or 1;
			$s = sprintf("streamer=%d", $val eq "off" || !$val?0:1);
			last SWITCH;
		};
		$cmd eq "reboot" && do {
			$s = sprintf("reboot=1");
			last SWITCH;
		};
		goto usage;
	};

	# $s is now the variable we need to change. Set up a nonblocking call to HVAC_DaikinAC_Write() 
	# 
	my $timeout  = AttrVal($name, "timeout", 5);
	$hash->{"HELPER"}{"WRITE_PID"} = BlockingCall(
			"HVAC_DaikinAC_Write", $name . "|" . $s,
			"HVAC_DaikinAC_WriteDone", $timeout,
			"HVAC_DaikinAC_WriteAbort", $hash
	);

	return undef;
usage:

	return "Invalid command, choose one of refresh:noArg mode:".join(',', map{$HVAC_DaikinAC_MODE{$_}} keys %HVAC_DaikinAC_MODE) . " " .
		"swing:".join(',', map{$HVAC_DaikinAC_SWING{$_}} keys %HVAC_DaikinAC_SWING) . " " .
		"rate:".join(',', map{$HVAC_DaikinAC_RATE{$_}} keys %HVAC_DaikinAC_RATE) . " " .
		"powerful:on,off" . " " .
		"econo:on,off" . " " .
		"streamer:on,off" . " " .
		"reboot:nodata" . " " .
		"shum:slider,0,5,100" . " " .
		"stemp:slider,18,0.5,30" . " " .
		"power:on,off" . " " .
		"on" . " " .
		"off";
} # Set()

# Attr
#
# update:nodata - Force reread of data from device
#
sub HVAC_DaikinAC_Attr(@) {
	my ($cmd, $name, $att,$val) = @_;

	# $cmd in ("del","set")
	#
	our $defs;
	my $hash = $defs{$name};
	my $do;

	SWITCH: {
		$att eq "interval" && do {
			$cmd eq "del" && do {
				# Set to default and fall through to "set"
				$cmd="set";
				$val=60;
			};
			$cmd eq "set" && $hash->{"INTERVAL"} != int($val) && do {
				RemoveInternalTimer($hash) if $hash->{"INTERVAL"}>0;
				$hash->{"INTERVAL"} = int($val);
				InternalTimer(gettimeofday()+1, 'HVAC_DaikinAC_StartPoll', $hash, 0) if $hash->{"INTERVAL"}>0;
			};
			last SWITCH;
		};
		$att eq "interval_powered" && do {
			$cmd eq "del" && do {
				# Set to default and fall through to "set"
				$cmd="set";
				$val=10;
			};
			$cmd eq "set" && $hash->{"INTERVAL_PWRD"} != int($val) && do {
				$hash->{"INTERVAL_PWRD"} = int($val);
			};
			last SWITCH;
		};
		$att eq "disable" && do {
			my $curstate = AttrVal($name, "disable", 0);
			$cmd eq "del" && $curstate && do {
				RemoveInternalTimer($hash);
				readingsSingleUpdate($hash, "state", "disabled", 1);
				last SWITCH;
			};
			$cmd eq "set" && !$curstate && do {
				InternalTimer(gettimeofday()+1, 'HVAC_DaikinAC_StartPoll', $hash, 0) if $hash->{"INTERVAL"}>0;
				readingsSingleUpdate($hash, "state", "initialized", 1);
			};
			last SWITCH;
		};
		$att eq "rawdata" && do {
			($cmd eq "del" || int($val)==0) && do {
				# Delete raw readings if attribute is deleted or set to 0
				CommandDeleteReading(undef, "$name basic_info");
				CommandDeleteReading(undef, "$name model_info");
				CommandDeleteReading(undef, "$name control_info");
				CommandDeleteReading(undef, "$name sensor_info");
			};
			$cmd eq "set" && $val && do {
				# Force reread of get_basic_info and get_model_info if rawdata is requested
				$hash->{"INITIALIZED"}=2;
			};
		};
		$att eq "pwrconsumption" && ($cmd eq "del" || int($val)==0) && do {
			# Delete raw readings if attribute is deleted or set to 0
			CommandDeleteReading(undef, "$name pwr_hour_cur");
			CommandDeleteReading(undef, "$name pwr_hour_last");
			CommandDeleteReading(undef, "$name pwr_day_cur");
			CommandDeleteReading(undef, "$name pwr_day_last");
			CommandDeleteReading(undef, "$name pwr_month_cur");
			CommandDeleteReading(undef, "$name pwr_month_last");
			CommandDeleteReading(undef, "$name pwr_year_cur");
			CommandDeleteReading(undef, "$name pwr_year_last");
			CommandDeleteReading(undef, "$name pwr_history_hourly_today");
			CommandDeleteReading(undef, "$name pwr_history_hourly_yesterday");
			CommandDeleteReading(undef, "$name unit_date");
		};
        };
	return undef;
} # Attr()

# StartPoll
#
# Start periodic or manual poll/parse/store sequence
#
sub HVAC_DaikinAC_StartPoll($) {
	my ($hash) = @_;
	my $name = $hash->{"NAME"};
	my $timeout  = AttrVal($name, "timeout", 5);

	# Guarantee a minimum timeout of 1 second.
	$timeout=1 if !$timeout;

	RemoveInternalTimer($hash, "HVAC_DaikinAC_StartPoll");

	our $init_done;
	if ($init_done != 1) {
		InternalTimer(gettimeofday()+1, "HVAC_DaikinAC_StartPoll", $hash, 0);
		return;
	}

	return if IsDisabled($name);

	if (exists($hash->{"HELPER"}{"POLL_PID"})) {
		Log3 ($name, 3, "HVAC_DaikinAC_StartPoll(): $name - WARNING - still running (" . $hash->{"HELPER"}{"POLL_PID"}{"fn"} . ") - skipping poll");
		return undef;
	}

	Log3 ($name, 4, "$name - HVAC_DaikinAC_StartPoll(): Setting up blockingcall");

	$hash->{"HELPER"}{"POLL_PID"} = BlockingCall("HVAC_DaikinAC_Poll", $name, "HVAC_DaikinAC_PollDone", $timeout, "HVAC_DaikinAC_PollAbort", $hash);
	$hash->{"HELPER"}{"POLL_PID"}{"loglevel"} = 4;

	return undef;
} # StartPoll()

# Parse($r, $s, $l)
#
# Parse polled data ($s) from device and return as hash
# Only include parameters passed in $l (comma seperated list)
# Store retrieved values in hash ref $r->{...} 
#
# Return: true is successfull, false otherwise
#
sub HVAC_DaikinAC_Parse {
	my ($name, $r, $s, $l) = @_;
	my @F = split ',', $s;
	my %L = map { $_ => 1 } split(/,/, $l);

	# We expect the first key/value pair to be "ret=OK" on success
	# or ret=<error message> in all other cases
	#
	my $ret = shift @F or return 0;
	my ($key,$val) = split /=/, $ret, 2;
	return 0 if not ($key eq "ret" and $val eq "OK");

	# No error, so return all requested key/value pairs
	#
	while ($_ = shift @F) {
		my ($key, $val) = split(/=/, $_, 2);
		next if !exists($L{$key});
		SWITCH: {
			$key eq "mode" && do {
				our %HVAC_DaikinAC_MODE;
				$r->{"mode"} = $HVAC_DaikinAC_MODE{$val} || 'unknown';
				$key = "f_mode";
				last SWITCH;
			};
			$key eq "pow" && do {
				$r->{"power"} = $val?"on":"off";
				last SWITCH;
			};
			$key eq "f_dir" && do {
				our %HVAC_DaikinAC_SWING;
				$r->{"swing"} = $HVAC_DaikinAC_SWING{$val} || 'unknown';
				last SWITCH;
			};
			$key eq "f_rate" && do {
				our %HVAC_DaikinAC_RATE;
				$r->{"rate"} = $HVAC_DaikinAC_RATE{$val} || 'unknown';
				last SWITCH;
			};
			$key eq "adv" && do {
	                        my %adv = map { $_ => 1 } split('/', $val);
				$r->{"powerful"} = "off";
				$r->{"powerful"} = "on" if ($adv{"2"});
				$r->{"econo"} = "off";
				$r->{"econo"} = "on" if ($adv{"12"});
				$r->{"streamer"} = "off";
				$r->{"streamer"} = "on" if ($adv{"13"});
				last SWITCH;
			};
			$key eq "name" && do {
				$val = urlDecode($val);
				last SWITCH;
			};
			$key eq "cmpfreq" && do {
				$r->{"cmpfreq_max"} = $val if $val>ReadingsVal($name, "cmpfreq_max", 0);
				last SWITCH;
			};
			$key eq "mompow" && do {
				# We force this to 0 if we're not running.
				# It seems to be rounded up to 1 (100W power usage) by the unit, even if powered off
				$val = 0 if $val==1 && !$r->{"pow"};
				last SWITCH if !$val;
				$val/=10;
				$r->{"mompow_max"} = $val if $val>ReadingsVal($name, "mompow_max", 0);
				last SWITCH;
			};
			$key eq "htemp" && do {
				$r->{"htemp_ifchanged"} = $val;
				last SWITCH;
			};
			$key eq "hhum" && do {
				$r->{"hhum_ifchanged"} = $val;
				last SWITCH;
			};
			$key eq "otemp" && do {
				$r->{"otemp_ifchanged"} = $val;
				last SWITCH;
			};
		};
		$r->{$key} = $val;
	}

	return 1;
} # Parse()

# Pwrconsumption_Stats
#
# Maintain power consumption reading values
# Only enabled if attribute "pwrconsumption" set to 1;
#
sub HVAC_DaikinAC_Pwrconsumption_Stats($$$) {
	my ($name, $ua, $r) = @_;
	our $defs;
	my $hash	= $defs{$name};

	# As we are minimizing the number of requests , we poll at most once a minute
	# Hourly, daily and monthly history are read and updated (if needed) at most once per hour
	#
	return if ReadingsAge($name, "unit_date", 60) < 60;

	# Oke, so at least a minute has passed since the last poll, or we have never polled before.
	# Let's get the date/timestamp for the unit itsself. We use this as a basis for determining
	# if the current hour, day or month has passed and we should update values.
	#
	my %ret;
	my $req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/common/get_datetime");
	my $s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, \%ret, $s->content, "sta,cur,dst,zone") or do {
		Log3($name, 3, "Invalid response for /common/get_datetime: " . $s->content);
		return;
	};

	# Validate the reading for current time. If the unit does not hold a valid date/time, skip out
	# on updating any stats.
	$ret{"cur"}=~ m/^\d\d\d\d\/\d+\/\d+ \d+:\d+:\d+$/ or return;

	# Parse and store unit's current date/time
	#
	# Format: @t/@prev_t = (year[xxxx],month[1-12],day[1-31],hour[0-23],minute[0-59],second[0-59]
	#
	my @t = split(/[\/ :]/, $ret{"cur"});
	my @prev_t = split(/[\/ :]/, ReadingsVal($name, "unit_date", "1970/1/1 00:00:00"));

	# Update the reading
	#
	$r->{"unit_date"} = sprintf("%.4d/%.2d/%.2d %.2d:%.2d:%.2d", @t);

	# We now set $t and $prev_t with the timestamp as read from the unit
	# and base all of our calculations on that data. If $prev_t is unitialized, it will be set to the epoch.
	#
	my $t = POSIX::mktime(0, $t[4], $t[3], $t[2], $t[1]-1, $t[0]-1900);
	my $prev_t = POSIX::mktime(0, $prev_t[4], $prev_t[3], $prev_t[2], $prev_t[1]-1, $prev_t[0]-1900);

	# Fetch hourly readings. These are reported in *100Wh
	#
	$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_day_power_ex");
	$s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, \%ret, $s->content, "curr_day_heat,prev_1day_heat,curr_day_cool,prev_1day_cool") or do {
		Log3($name, 3, "Invalid response for /aircon/get_day_power_ex: " . $s->content);
		return;
	};

	# Split and sum into a single array [0..47]
	# We divide by 10 to get a representation in kWh for our readings
	#
	my (@a, @b);
	@a = split("/", $ret{"prev_1day_heat"} ."/".$ret{"curr_day_heat"});
	@b = split("/", $ret{"prev_1day_cool"} ."/".$ret{"curr_day_cool"});
	my @pwr_history_hourly = map { ($a[$_] + $b[$_])/10 } 0..47;

	# Always update the current hour reading if changed
	#
	my $pwr_hour_cur = ReadingsVal($name, "pwr_hour_cur", 0);
	$r->{"pwr_hour_cur"} = $pwr_history_hourly[24+$t[3]];

	# Calculate the difference in power usage between last and current reading
	# We use this to maintain our daily,monthly and yearly totals, even if we
	# have no other need for daily or monthly usage data.  
	#
	# The code below seems to be redundant for now, as all units observed only
	# update their statistics once every hour. However, let's keep it in here, commented
	# out, in case new units emerge that do update these power usage statistics more
	# often than that.
	my $diff;
	if (int($t/3600) == int($prev_t/3600)) {
		# Still in the same hour. Calculate difference between current and stored reading
		# Not observed to happen in any of the units this has been tested on. They update
		# the value just once every hour, after the hour has passed.
		$diff = $r->{"pwr_hour_cur"}-ReadingsVal($name, "pwr_hour_cur", 0);

		# Use the calculated difference to offset our daily, monthly and yearly readings
		if ($diff) {
			$r->{"pwr_day_cur"} = ReadingsVal($name, "pwr_day_cur", 0) + $diff;
			$r->{"pwr_month_cur"} = ReadingsVal($name, "pwr_month_cur", 0) + $diff;
			$r->{"pwr_year_cur"} = ReadingsVal($name, "pwr_year_cur", 0) + $diff;
		} # END redundant code
		return;
	}

	# More than one hour has passed since the last poll.
	# Poll and update hourly, daily and monthly readings
	#
	$r->{"pwr_hour_last"} = $pwr_history_hourly[24+$t[3]-1];
	$r->{"pwr_history_hourly_yesterday"} = join(",", @pwr_history_hourly[0..23]);
	$r->{"pwr_history_hourly_today"} = join(",", @pwr_history_hourly[24..47]);

	# Now fetch and update daily readings
	#
	$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_month_power_ex");
	$s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, \%ret, $s->content, "curr_month_heat,prev_month_heat,curr_month_cool,prev_month_cool") or do {
		Log3($name, 3, "Invalid response for /aircon/get_month_power_ex: " . $s->content);
		return;
	};

	# Split and sum into a single array [0..61]
	@a = split("/", $ret{"prev_month_heat"});
	@b = split("/", $ret{"prev_month_cool"});
	$#a = 30;
	$#b = 30;
	push @a, split("/", $ret{"curr_month_heat"});
	push @b, split("/", $ret{"curr_month_cool"});
	$#a = 61;
	$#b = 61;
	my @pwr_history_daily = map { defined($a[$_])?($a[$_]+$b[$_])/10:"" } 0..61;

	# Update the current day reading once per hour
	#
	$r->{"pwr_day_cur"} = $pwr_history_daily[31+$t[2]-1];

	# update daily readings. Once per hour so that the current day is correctly reflected in stats
	#
	$r->{"pwr_day_last"} = $pwr_history_daily[31+$t[2]-2];

	my @months = ("jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec");
	$r->{"pwr_history_daily_" . $months[$t[1]-2%12]} = join(",", @pwr_history_daily[0..30]);
	$r->{"pwr_history_daily_" . $months[$t[1]-1]} = join(",", @pwr_history_daily[31..61]);

	# Now fetch and update monthly readings
	#
	$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_year_power_ex");
	$s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, \%ret, $s->content, "curr_year_heat,prev_year_heat,curr_year_cool,prev_year_cool") or do {
		Log3($name, 3, "Invalid response for /aircon/get_year_power_ex: " . $s->content);
		return;
	};

	# Split and sum into a single array [0..23]
	@a = split("/", $ret{"prev_year_heat"} ."/".$ret{"curr_year_heat"});
	@b = split("/", $ret{"prev_year_cool"} ."/".$ret{"curr_year_cool"});
	my @pwr_history_monthly = map { ($a[$_] + $b[$_])/10 } 0..23;

	# Update the current month reading
	#
	$r->{"pwr_month_cur"} = $pwr_history_monthly[12+$t[1]-1];

	# And update monthly readings. We do this every hour, to make sure the current months
	# usage is correctly reflected. If there are no changes, this will not trigger a
	# change event.
	$r->{"pwr_month_last"} = $pwr_history_monthly[12+$t[1]-2];
	$r->{"pwr_history_monthly_" . sprintf("%.4d", $t[0]-1)} = join(",", @pwr_history_monthly[0..11]);
	$r->{"pwr_history_monthly_" . sprintf("%.4d", $t[0])} = join(",", @pwr_history_monthly[12..23]);

	# And finally, add two yearly readings
	$r->{"pwr_year_cur"} = sum(@pwr_history_monthly[12..23]);
	$r->{"pwr_year_last"} = sum(@pwr_history_monthly[0..11]);
	return;
} # Pwrconsumption_Stats()


# Poll
#
# Poll data from device
sub HVAC_DaikinAC_Poll($) {
	my ($name)	= @_;
	our $defs;
	my $hash	= $defs{$name};

	Log3($name, 4, "$name HVAC_DaikinAC_Poll(): entry");

	my $timeout  = AttrVal($name, "timeout", 5);
        my $ua = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => $timeout);
	my $req;
	my $s;
	my $r = {};

	if ($hash->{"INITIALIZED"} != 1) {
		#
		# Poll basic info
		#
		$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/common/basic_info");
		$s = $ua->request($req);
		$r->{"basic_info"} = $s->content if AttrVal($name, "rawdata", 0);

		HVAC_DaikinAC_Parse($name, $r, $s->content, "type,reg,ver,rev,name,method,port,id,pw,mac") or do {
			$r->{"ERR"}="Invalid response on get_basic_info: " . $s->content;
			goto POLL_END;
		};

		#
		# Poll model info
		#
		$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_model_info");
		$s = $ua->request($req);
		HVAC_DaikinAC_Parse($name, $r, $s->content, "model,type") or do {;
			$r->{"ERR"}="Invalid response on get_model_info: " . $s->content;
			goto POLL_END;
		};
		$r->{"model_info"} = $s->content if AttrVal($name, "rawdata", 0);
	}

	HVAC_DaikinAC_Pwrconsumption_Stats($name, $ua, $r) if AttrVal($name, "pwrconsumption", 0);

	#
	# control info
	#
        $req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_control_info");
        $s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, $r, $s->content, "pow,mode,adv,stemp,shum,dt1,dt3,dt4,dh1,dh3,dh4,f_rate,f_dir") or do {
		$r->{"ERR"}="Invalid response on get_control_info: " . $s->content;
		goto POLL_END;
	};
	$r->{"control_info"} = $s->content if AttrVal($name, "rawdata", 0);

	#
	# sensor info
	#
	# Important: there is a rewrite dependency for mompow on "pow", so always poll after get_control_info
	#
	$req = HTTP::Request->new('GET', 'http://' . $hash->{"HOST"} . "/aircon/get_sensor_info");
	$s = $ua->request($req);
	HVAC_DaikinAC_Parse($name, $r, $s->content, "htemp,hhum,otemp,mompow,cmpfreq") or do {
		$r->{"ERR"}="Invalid response on get_sensor_info: " . $s->content;
		goto POLL_END;
	};
	$r->{"sensor_info"} = $s->content if AttrVal($name, "rawdata", 0);


	Log3($name, 5, "$name HVAC_DaikinAC_Poll(): poll done");
	Log3($name, 5, "$name HVAC_DaikinAC_Poll(): return " . encode_json($r));

POLL_END:
	$r->{"INSTANCE_NAME"} = $name;
	return encode_json($r);
} # Poll()

# PollDone
#
# Callback after successful completion of poll
#
sub HVAC_DaikinAC_PollDone($) {
	my ($s)			= @_;
	our $defs;

	my $r = decode_json($s);

	my $name = $r->{"INSTANCE_NAME"} or die "FATAL ERROR: Instance name not set";
	my $hash = $defs{$name};
	delete($hash->{"HELPER"}{"POLL_PID"});

	# Just do nothing but reschedule if an error occured.
	if (exists($r->{"ERR"})) {
		Log3($name, 3, "$name HVAC_DaikinAC_PollDone(): " . $r->{"ERR"});
		goto POLLDONE_END;
	}

	if ($hash->{"INITIALIZED"} ne "1") {
		my @v = reverse sort keys our %HVAC_DaikinAC_VERSION;
		$hash->{"VERSION"}	= shift @v;
		$hash->{"INITIALIZED"}=1;
	}

	Log3($name, 5, "$name HVAC_DaikinAC_Poll(): successful completion - storing results");

	# Get current time
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	$hash->{"LASTUPDATE"} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;

	readingsBeginUpdate($hash);
	my $key;
	for $key (keys %$r) {
		if ($key eq "htemp" || $key eq "hhum" || $key eq "otemp"
			|| $key eq "unit_date") {
			# We always update the timestamp for these readings
			# This means that a current timestamp reflects validity for this reading
			# As for the pwr_..._last statistics, they are generated once per hour/day/month
			# and reflect usage in the past period. They should always be logged as well,
			# even if the value is exactly the same as in the previous period.
			readingsBulkUpdate($hash, $key, $r->{$key}) if $key ne "INSTANCE_NAME";
		} else {
			readingsBulkUpdateIfChanged($hash, $key, $r->{$key}) if $key ne "INSTANCE_NAME";
		}
	}
	readingsBulkUpdateIfChanged($hash, "state", $r->{"power"}, 1);
	readingsEndUpdate($hash, 1);

POLLDONE_END:
	# Schedule next poll
	#
	# Use INTERVAL if we are powered off. INTERVAL_PWRD if we are powered on.
	my $interval = $hash->{"INTERVAL"};
	$interval = $hash->{"INTERVAL_PWRD"} if ReadingsVal($name, "pow", 0);
	InternalTimer(gettimeofday()+$interval, "HVAC_DaikinAC_StartPoll", $hash, 0) if $interval>0;

	Log3 ($name, 5, "$name HVAC_DaikinAC_Poll(): finished");

	return undef;
} # PollDone()

# PollAbort
#
# Callback after unsuccessful completion of poll
#
sub HVAC_DaikinAC_PollAbort(@) {
	my ($hash,$cause)	= @_;
	my $name		= $hash->{"NAME"};

	# Keep a failure count
	#
	$hash->{"HELPER"}{"FAULTS"}++;

	# Provide some sensible feedback to our users in log
	#
	$cause = "Timeout while attempting to poll " . $hash->{"HOST"} . " ($cause)";
	Log3 ($name, 2, "$name HVAC_DaikinAC_Poll(): failed (" . $hash->{"HELPER"}{"POLL_PID"}{"fn"} . ") - " . $cause);

	delete($hash->{"HELPER"}{"POLL_PID"});

	# Schedule next poll
	#
	# Use INTERVAL if we are powered off. INTERVAL_PWRD if we are powered on.
	my $interval = $hash->{"INTERVAL"};
	$interval = $hash->{"INTERVAL_PWRD"} if ReadingsVal($name, "pow", 0);
	InternalTimer(gettimeofday()+$interval, "HVAC_DaikinAC_StartPoll", $hash, 0) if $interval>0;

	return undef;
} # PollAbort()

1;

=pod
=item summary    Daikin Airconditioning unit control
=item summary_DE Daikin Airconditioning kontrol


=begin html

<a name="HVAC_DaikinAC"></a>
<h3>HVAC_DaikinAC</h3>

<p>This module can control indoor Daikin airconditioning units that have been equipped with a Daikin WiFi adapter.
Supported adapters are:

<ul>
 <li>BRP069B41</li>
 <li>BRP069B42</li>
 <li>BRP069B43</li>
 <li>BRP069B45</li>
 <li>BRP069A81</li>
 <li>All integrated adapters</li>
</ul>

  <p>
   One HVAC_DaikinAC device is required for each indoor unit to be controlled. On multisplit systems,
   each indoor unit needs to be equipped with it's own Wifi adapter and be reachable for FHEM.
  <p>
   A unit can be specified with either a hostname or an IP address. As long as FHEM can resolve
   the hostname and reach the unit's Wifi adapter with a TCP connection to port 80, you should be ok.
  <p>
   All requests to the airconditioner are made using a nonblocking call. Only a single call can be
   active at any time. A default timeout of 5 seconds applies for all requests.
  <p>
   Normal execution flow:
  <ul>
   <li>Device is defined.</li>
   <li>Initial poll is performed after 1 second if <em>[ interval ]</em> is not set to 0.</li>
   <li>Device will be repolled every <em>[ interval ]</em> seconds and readings updated. When powered on, the <interval_powered> attribute is used.</li>
   <li>On the initial poll, the model and wifi adapter info will be polled. This info will not be automatically updated afterwards.</li>
   <li>If interval is set to 0, a poll can be initiated by running a "get update" command on the device. This get command can also be used to forcibly refresh the model and wifi adapter info</li>
   <li>On each poll, the htemp, hhum and otemp readings will always be updated, even if they are unchanged. That will make their last updated timestamp meaningful as a validity timestamp and these readings are most useful for interactive display, for example in TabletUI. All other readings will only be updated if they have changed.</li>
   <li>The htemp_ifchanged, hhum_ifchanged and otemp_ifchanged readings will only be updated if they are different from the previous reading. These can be used for logging purposes</li>
   <li>Any set command is sent to the airconditioner, and will be immediately followed by a poll. The set command itsself will never modify a reading. The change in the reading value will always be the result of the subsequent poll and therefore will be the current reading from the airconditioner unit.</li>
   <li>If the operation mode is changed (cool to heat, heat to vent, etc), the units stored temperature and humidity setting will be used for the new mode. Each mode has it's own stored temperature and humidity settings. The "stemp" and "shum" readings reflect the temperature and humidity setpoint for the currently active operation mode.</li>
 </ul>

<p>
 <b>Define</b>
 <p>
   <code>define &lt;name&gt; HVAC_DaikinAC &lt;hostname or ip&gt; [interval] [interval_powered]</code>
 <ul>
   <li>hostname or ip: Hostname or IPv4 address of unit</li>
   <li>interval: Poll interval in seconds. Default value is 60. Set to 0 to disable automatic polling of the device.</li>
   <li>interval_powered: Poll interval in seconds as long as the device is turned on. Default value is 10. Set to 0 to disable automatic polling when on.</li>
 </ul>

  <p>Examples:
  <ul>
  <li><b>define MYDEVICENAME HVAC_DaikinAC 172.12.1.10</b><br>
create a device with name MYDEVICENAME. Unit has IP address 172.12.1.10.
Use the default polling intervals (60 seconds when off, 10 seconds when
powered on)</li>
  <li><b>define MYDEVICENAME HVAC_DaikinAC daikin-living.mydomainname 300 60</b><br>
create a device with name MYDEVICENAME. Unit can be reached through DNS
name daikin-living.mydomainname. Set polling intervals to 300 seconds
when turned off and 60 seconds when the unit is powered on.</li>
  </ul>

  <p>Note: if interval is set to 0, but interval_powered is not (or left to it's default value of 10 seconds), the device will not be automatically polled. However, if it is turned on through FHEM, or a forced "set update" is run and the unit is turned on, the interval_powered setting is evaluated. This will cause automatic polling to start until the device is turned off again. This can be used for devices that are exclusively controlled through FHEM. In such a case, there is no need to keep polling the device when it's turned off if the temperature or humidity readings are not used for other purposes.

<p>

 <b>Readings</b>
 <ul>
   <li><b>power</b>: [ on | off ] Unit's current power status (on or off)</li>
   <li><b>mode</b>: [ auto | dehumidify | cool | heat | vent ] Current active mode</li>
   <li><b>rate</b>: [ auto | silent | lowest | low | medium | high | highest ] Current fan speed setting</li>
   <li><b>swing</b>: [ none | vertical | horizontal | 3d ] Current airflow swing setting</li>
   <li><b>stemp</b>: Setpoint temperature (18 - 30 degrees C)</li>
   <li><b>shum</b>: Humidity setpoint (0-100/5). Must be set with a number that is a multiple of 5. So 0, 5, 10, ... 95 or 100</li>
   <li><b>htemp</b>: Measured indoor temperature (only valid if running)</li>
   <li><b>htemp_ifchanged</b>: Measured indoor temperature (Equal to htemp, but only modified if value changed)</li>
   <li><b>otemp</b>: Measured outdoor temperature (not always present, depends on unit type). For some unit types, this value is always present, even if turned off. Others only supply the outside temperature while the unit is running. Most units set this to "-" if not present.</li>
   <li><b>otemp_ifchanged</b>: Measured outdoor temperature (Equal to otemp, but only modified if value changed)</li>
   <li><b>hhum</b>: Current indoor relative humidity if supported</li>
   <li><b>hhum_hhum</b>: Measured indoor relative humidity (Equal to hhum, but only modified if value changed)</li>
   <li><b>adv</b>: List of currently active additional settings, slash seperated (2=powerful, 13=streamer)</li>
   <li><b>powerful</b>: [ on | off ] Current status of "Powerful" special mode (powerful ventilation, automatically turned off by unit after 20 mins)</li>
   <li><b>econo</b>: [ on | off ] Current status of "Econo" special mode (econo mode)</li>
   <li><b>streamer</b>: [ on | off ] Current status of "Streamer" special mode (ionized air cleaner)</li>
   <li><b>cmpfreq</b>: Current compressor frequency in number of revolutions per second</li>
   <li><b>cmpfreq_max</b>: Maximum compressor frequency observed since creation</li>
   <li><b>name</b>: Unit name (can be changed using the Daikin online controller app)</li>
   <li><b>mac</b>: MAC address of Wifi unit's adapter</li>
   <li><b>id</b>: Username in use with Daikin online controller if this unit is registered for the service</li>
   <li><b>pw</b>: Password that is in use with Daikin online controller service</li>
   <li><b>port</b>: TCP port number in use for communcations with Daikin online controller</li>
   <li><b>rev</b>: Revision of Wifi adapter</li>
   <li><b>ver</b>: Software version for Wifi adapter</li>
   <li><b>model</b>: Model name of unit if supported</li>
   <li><b>method</b>: Currently selected protocol for communications (should be "polling")</li>
   <li><b>mompow</b>: Current (momentary) power usage (in kW, 100W resolution). Forced to 0 is the unit is turned off, as most units seem to report a 100W value in idle mode, even though the unit does not consume anywhere close to 100W while turned off.</li>
   <li><b>mompow_max</b>: Maximum value for mompow observed since device creation</li>
   <li><b>reg</b>: Area/country of registration (EU for EU models)</li>
   <li><b>type</b>: Unknown (all units here I've send always have "N" stored here)</li>
  </ul>

   <p>The readings below are for internal use, but might prove useful
  <ul>
   <li><b>dh1</b>: Stored humidity setpoint for mode 1 (auto)</li>
   <li><b>dh3</b>: Stored humidity setpoint for mode 3 (cool)</li>
   <li><b>dh4</b>: Stored humidity setpoint for mode 3 (heat)</li>
   <li><b>dt1</b>: Stored temperature setpoint for mode 1 (auto)</li>
   <li><b>dt3</b>: Stored temperature setpoint for mode 3 (cool)</li>
   <li><b>dt4</b>: Stored temperature setpoint for mode 3 (heat)</li>
   <li><b>f_dir</b>: Airflow swing setting (0=off, 1=vertical, 2=horizontal, 3=3D)</li>
   <li><b>f_rate</b>: Fan speed setting (A=auto, B=silent, 3=lowest .. 7=highest)</li>
   <li><b>f_moode</b>: Operation mode (1=auto, 2=dehumidify, 3=cool, 4=heat, 6=fan)</li>
   <li><b>pow</b>: Power status numeric (0=off, 1=on)</li>
 </ul>

   <p>The readings below are only stored when the pwrconsumption attribute is set to 1
	<ul>
	 <li><b>unit_date</b>: Current date and time according to the unit. This is used as the basis for all data represented below. If the unit is in a different timezone (or set at an offset), the hour, day and month breaks will not sync up with the system date and time. That will not cause any problems, but the data might be harder to interpret.</li>
	 <li><b>pwr_hour_cur</b>: Power consumption for current hour. On all units that I have observed, power readings are updated just once per hour and this reading will always read 0.</li>
	 <li><b>pwr_hour_last</b>: Power consumption for last complete hour. Updated once per hour. Good for logging and plotting in a graph.</li>
	 <li><b>pwr_day_cur</b>: Power consumption for current day up to now. Updated once every hour for most units</li>
	 <li><b>pwr_day_last</b>: Power consumption for previous day. Similar to pwr_hour_last. Updated once per day.</li>
	 <li><b>pwr_month_cur</b>: Power consumption for current calendar month to date. Updated once per hour for most units</li>
	 <li><b>pwr_month_last</b>: Power consumption for previous calendar month. Updated once per month.</li>
	 <li><b>pwr_year_cur</b>: Power consumption for current calendar year to date. Updated once per hour for most units</li>
	 <li><b>pwr_year_last</b>: Power consumption for previous calendar year. Updated once per year.</li>
	 <li><b>pwr_history_hourly_today</b>: Power consumption history for today, per hour. Updated once per hour. This is a comma seperated list with 24 values, each representing an hourly slice of the day. The value at position 0 represents the timeframe from midnight to 1am and so forth. Last value will always be 0 (day will rollover as soon as the hourly data for that hour is known)</li>
	 <li><b>pwr_history_hourly_yesterday</b>: same as pwr_history_hourly_today, but for previous day.</li>
	 <li><b>pwr_history_daily_<month></b>: Power consumption history calendar month, per day. Updated once per day. This is a comma seperated list with 31 values. The value at position 0 represents day 1 and so forth. There will be no value (empty string) for any days that are non-existant in this month. Month names are "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov" and "dec". Only the current and previous month are retained in the unit and will be created upon device definition.</li>
	 <li><b>pwr_history_monthly_<year></b>: Power consumption history for complete calendar year <year>, per month. Updated once per month. This is a comma seperated list with 12 values. The value at position 0 represents the month of january and so forth. Only the current and previous year are retained in the unit and will be created upon device definition.</li>
	</ul>

<p>
 <b>Attributes</b>
 <ul>
   <li><b>disable</b>: [ 0 | 1 ] If set to 1, disable all polling. Set will not be possible on a disabled device. If you just need to stop automatic polls, use the "interval" attribute</li>
   <li><b>interval</b>: Set the polling interval (in seconds). This will override the interval as set in the define command. If set to "0", no more scheduled polling will happen. However, the device will be polled one time directly following a "set" command so that the requested change is reflected in the readings. A poll can also be forced by issuing the "set refresh" command. Keep in mind that any change in ambient or outside temperature will not be reflected in FHEM. Also, any changes resulting from a control action that was initiated through another channel (e.g. the remote control or Daikin's online controller) will not be reflected in the FHEM device readings.</li>
   <li><b>interval_powered</b>: Set the polling interval (in seconds) in case the unit is turned on.</li>
   <li><b>pwrconsumption</b>: [ 0 | 1 ] If set to 1, power consumption data is read from the unit and stored in the readings specified above. This is not supported by older units, who will return all 0 readings for power usage. All consumption data is represented in kWh, as a floating point number with a precision of 1/10 kWh. For all of the the pwr_period_last readings readings to be correctly updated, automatic polling must be enabled with an interval of at most 3600 seconds (1 hour).</li>

   <li><b>rawdata</b>: [ 0 | 1 ] If set to 1, 4 extra readings will be generated:
	<ul>
	 <li><b>basic_info</b>: Raw data from get_basic_info request (on new define or after "set refresh")</li>
	 <li><b>model_info</b>: Raw data from get_model_info request (on new define or after "set refresh")</li>
	 <li><b>sensor_info</b>: Raw data from get_sensor_info request (on each poll or after set command)</li>
	 <li><b>control_info</b>: Raw data from get_control_info request (on each poll or after set command)</li>
	</ul></li>
   <li><b>timeout</b>: Sets the request timeout - default 5 seconds. Any request to the airconditioner will be aborted after this interval and readings will not be updated. Only set to a higher value if you have a very slow or unreliable network connection to the airconditioner and you are aware of what you are doing. A value as low a 1 second should work just fine under normal circumstances.</li>
 </ul>

  If using the FHEM standard web frontend, you can use the <em>stateFormat</em> and <en>devStateIcon</em> attributes
  to visualize the current state and temperature readings. The default setting is:

  <pre>
attr [devicename] stateFormat power/mode&#92;
&lt;br&gt;In: htemp &amp;degC &lt;br&gt;Out: otemp &amp;degC
attr [devicename] devStateIcon off.*:control_standby@gray on.*cool:frost@blue on.*heat:sani_heating@red on.*dehumidify:humidity@blue on.*vent:vent_ventilation@green on.*auto:temp_temperature@red
</pre>

<p>

 <b>Set</b>
  <ul>
   <li><b>refresh</b>: Force immediate poll of device - will also request and update version and device info</li>
   <li><b>power</b>: [ on | off ] Set power status (on or off)</li>
   <li><b>on</b>: Shortcut for "power on"</li>
   <li><b>off</b>: Shortcut for "power off"</li>
   <li><b>mode</b>: [ auto | dehumidify | cool | heat | vent ] Set new operation mode</li>
   <li><b>rate</b>: [ auto | silent | lowest | low | medium | high | highest ] Set fan speed (silent not supported on all Wifi controllers, even if the unit itsself supports the mode)</li>
   <li><b>swing</b>: [ none | vertical | horizontal | 3d ] Set airflow swing setting (horizontal or 3D not present on all units)</li>
   <li><b>stemp</b>: Set setpoint temperature. Can be an absolute temperature (resolution 0.5 degrees) or an offset (prefix with + or -, e.g. "set stemp -0.5" or "set stemp -2")</li>
   <li><b>shum</b>: Set humidity setpoint if supported. Valid numbers are between 0 and 100 and a multiple of 5. An offset can be set in a similar way as with stemp. The offset needs to be a multiple of 5 as well.</li>
   <li><b>powerful</b>: [ on | off ] Activate or deactivate powerful mode if unit supports remote activation. Older models will not support this option, even though the powerful mode is present and can be controlled through the IR remote.</li>
   <li><b>streamer</b>: [ on | off ] Activate or deactivate ion streamer mode if present</li>
   <li><b>econo</b>: [ on | off ] Activate or deactivate econo mode if present and units supports remote activation</li>
   <li><b>reboot</b>: Reboots the units' wifi module</li>
  </ul>

<p>

 <b>Get</b>
  <ul>
    No parameters at this time
  </ul>

<p>

 <b>Logging</b>

  <p>A log definition that will allow you to track and graph the units' status, power usage and temperature and humidity readings
  without clogging up the file with unneccesary log entries should include the following readings:

  <pre>pwr.*_last, pwr_year_cur, power, pow, cmpfreq, mompow, stemp, shum, mode, rate, swing, powerful, streamer, econo, .*_ifchanged</pre>

  <p>It might include other readings, but never htemp, hhum, or otemp or unit_date, as these readings are produced on each poll.

  <p>For example, for an FHEM device named MYDAIKINAC:

  <pre>
  define MYDAIKINAC_LOG FileLog mydaikinac-%Y.log MYDAIKINAC:(pwr.*_last|pwr_year_cur|power|pow|cmpfreq|mompow|stemp|shum|mode|rate|swing|powerful|streamer|econo|.*_ifchanged:.*
  </pre>

<p>

 <b>Notes</b>
   <ul>
   <li>Be careful if you are thinking about using the htemp reading as a temperature input for other devices (room thermostat for example). The reading does not seem to be reliable when the airconditioner is not turned on.</li>
   <li>Behaviour on US based models using a fahrenheit scale is unknown. If you have one of those, I'ld love to hear from you.</li>
   <li>If you have issues with your aircon, please report back and include the readings that are returned if you set the attribute "rawdata" to 1.</li>
   <li>If there are other modes that you can set using the Daikin online controller app that are not present in this module, please let me know and include the readings that are returned if you set the attribute "rawdata" to 1 and turn the function on and off through the Daikin app. </li>
   </ul>

<p>

 <b>Tablet UI</b>

   <p>An example Tablet UI frontend can be found in <a href="https://forum.fhem.de/index.php/topic,109562.0.html">this topic on the FHEM forum</a>

=end html

=for :application/json;q=META.json 58_HVAC_DaikinAC.pm
{
  "abstract": "Daikin Airconditioning control",
  "keywords": [
    "Daikin",
    "Airconditioning",
    "HVAC",
    "Heating",
    "Cooling"
  ],
  "version": "v1.0.9",
  "release_status": "stable",
  "author": [
    "Roel Bouwman (roel@bouwman.net)"
  ],
  "x_fhem_maintainer": [
    "roelb"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 0,
        "perl": 0,
	"LWP::UserAgent": 0 ,
	"HTTP::Request": 0,
	"JSON": 0,
        "Time::HiRes": 0,
        "List::Util": 0,
        "Blocking": 0,
        "Time::Local": 0
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

=cut
