##############################################
# $Id$
#

package SD_Rojaflex;

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);
use FHEM::Meta;

our $VERSION = '1.00';

GP_Export(qw(
	Initialize
	)
);

# Import der FHEM Funktionen
BEGIN {
	GP_Import(qw(
		AssignIoPort
		AttrVal
		attr
		CommandSet
		defs
		devspec2array
		DoTrigger
		gettimeofday
		InternalTimer
		IOWrite
		IsDummy
		IsIgnored
		Log3
		modules
		ReadingsVal
		RemoveInternalTimer
		readingsBeginUpdate
		readingsBulkUpdate
		readingsEndUpdate
	))
};

my %rev_codes; # reverse codes
my %codes = (
	'0' => 'stop',
	'1' => 'up',
	'8' => 'down',
	'9' => 'savefav',
	'D' => 'gotofav',
	'E' => 'request',
	'x' => 'pct',
	'y' => 'clearfav',
);

sub Initialize {
	my ($hash) = @_;
	for my $k (keys %codes) {
		$rev_codes{$codes{$k}} = $k; # reverse codes
	}
	$hash->{Match}      = '^P109#[a-fA-F0-9]{18}';
	$hash->{SetFn}      = \&Set;
	$hash->{DefFn}      = \&Define;
	$hash->{UndefFn}    = \&Undef;
	$hash->{ParseFn}    = \&Parse;
	$hash->{AttrFn}     = \&Attr;
	$hash->{AttrList}   = 'IODev '.
	                      'bidirectional:1,0 '.
	                      'do_not_notify:0,1 '.
	                      'inversePosition:0,1 '.
	                      'repetition:1,2,3,4,5,6,7,8,9 '.
	                      'timeToClose '.
	                      'timeToOpen '.
	                      'ignore:1,0 dummy:0,1 showtime:0,1 '.
	                      "$main::readingFnAttributes";
	$hash->{AutoCreate} = {'SD_Rojaflex.*' => {FILTER => '%NAME', autocreateThreshold => '5:180', GPLOT => q{}}};
	return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Attr {
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
	# $cmd - Vorgangsart, kann die Werte "del" (loeschen) oder "set" (setzen) annehmen
	# $name - Geraetename
	# $attrName - Attribut-Name
	# $attrValue - Attribut-Wert
	my $hash = $defs{$name};
	return "\"Attr: \" $name does not exist" if (!defined($hash));

	if ($cmd eq 'set') {
		if ($attrName eq 'repetition') {
			return "$name: Unallowed value $attrValue for the attribute repetition (must be 1 - 9)!" if ($attrValue !~ m/^[1-9]$/xms);
		} elsif ($attrName eq 'inversePosition') {
			my $oldinvers = AttrVal($name, 'inversePosition', 0);
			if ($attrValue ne $oldinvers) {
				my $pct = ReadingsVal($name, 'pct', 0);
				$pct = 100 - $pct;
				my $cpos = ReadingsVal($name, 'cpos', 0);
				$cpos = 100 - $cpos;
				my $tpos = ReadingsVal($name, 'tpos', 0);
				$tpos = 100 - $tpos;
				my $state;
				if ($pct > 0 && $pct < 100) {$state = $pct};
				my %mapping= (
					up => 'down',  down => 'up', open => 'closed', closed => 'open', 0 => 'na',
				);
				$state = $mapping{ReadingsVal($name, 'state', 0)};
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, 'state', $state, 1);
				if (AttrVal($name,'bidirectional',1) eq '0') {
					readingsBulkUpdate($hash, 'pct', $pct, 1);
					readingsBulkUpdate($hash, 'cpos', $cpos, 1);
				}
				readingsBulkUpdate($hash, 'tpos', $tpos, 1);
				readingsEndUpdate($hash, 1);
			}
		} elsif ($attrName eq 'bidirectional') {
			return "$name: Unallowed value $attrValue for the attribute bidirectional (must be 0 - 1)!" if ($attrValue !~ m/^[0-1]$/xms);
		} elsif ($attrName eq 'timeToClose' || $attrName eq 'timeToOpen') {
			return "$name: Unallowed value $attrValue for the attribute $attrName (must be 1 - 999)!" if ($attrValue !~ m/^\d{1,3}$/xms || $attrValue < 1);
		}
	}
	return;
}

sub Set {
	my ($hash, $name, @a) = @_;
	my $ioname = $hash->{IODev}{NAME};
	my $na = scalar @a; # Anzahl in Array
	my $cmd = $a[0];

	return q(down:noArg stop:noArg up:noArg savefav:noArg gotofav:noArg clearfav:noArg pct:0,10,20,30,40,50,60,70,80,90,100) if ($cmd eq q(?));
	return qq($name, no set command specified) if ($na < 1);
	return qq($name, invalid set command) if (not exists $rev_codes{$cmd});
	return qq($name, invalid parameter for command pct, must be 0-100) if ($cmd eq 'pct' && ($na < 2 || $a[1] !~ m/^\d+$/xms || $a[1] > 100));
	return qq(Dummydevice $name: will not set data) if (IsDummy($name));

	my $state;
	my $motor = ReadingsVal($name, 'motor', 'stop');
	my $cpos = ReadingsVal($name, 'cpos', undef);
	my $tpos = ReadingsVal($name, 'tpos', 50);
	if (!defined $cpos) {$cpos = $tpos};
	if (AttrVal($name,'inversePosition',0) eq '1') {
		$cpos = 100 - $cpos; # inverse position
		$tpos = 100 - $tpos; # inverse position
	}
	my $timeToClose = AttrVal($name,'timeToClose',30);
	my $timeToOpen = AttrVal($name,'timeToOpen',30);

	if ($cmd eq 'pct') {
		$tpos = $a[1];
		if (AttrVal($name,'inversePosition',0) eq '1') {$tpos = 100 - $tpos}; # inverse position
		if ($tpos eq '0') {$cmd = 'up'} # Fahr hoch
		elsif ($tpos eq '100') {$cmd = 'down'}; # Fahr runter
		if ($tpos != $cpos) {
			Log3 $name, 3, "$ioname: SD_Rojaflex set $name pct $tpos";
			if ($tpos > 0 && $tpos < 100) {
				my $duration;
				if ($tpos > $cpos) { # Rolladen steht höher soll position
					$cmd = 'down'; # Fahr runter
					$duration = ($tpos - $cpos) * $timeToClose / 100;
				} elsif ($tpos < $cpos) { # Rolladen steht niedriger soll position
					$cmd = 'up';# Fahr hoch
					$duration = ($cpos - $tpos) * $timeToOpen / 100;
				}
				Log3 $name, 4, "$ioname: SD_Rojaflex set $name duration running time $duration s";
				InternalTimer( (gettimeofday() + $duration), \&SD_Rojaflex_pctStop, $name );
			}
		} else {
			$cmd = 'stop';
		}
	}

	# Build msg and send it
	my ($housecode,$channel) = split m/[_]/xms,$hash->{DEF};
	my $msg = q(P109#08) . $housecode . sprintf('%X',$channel);
	if ($cmd eq 'clearfav') {
		$msg .= q(D) . q(A01) . q(D); # gotofav
	} else {
		$msg .= $rev_codes{$cmd} . q(A01) . $rev_codes{$cmd};
	}
	$msg .= q(A);
  my $sum = 0;
  for (my $i = 7; $i < 20; $i += 2) {
    $sum += hex(substr($msg, $i, 2));
  }
  $sum &= 0xFF;
	$msg .= sprintf('%02X',$sum);
	Log3 $name, 4, "$ioname: $name sendMsg=$msg";
	for my $i (1 .. AttrVal($name, 'repetition', 1)) {
		IOWrite($hash, 'sendMsg', $msg);
	}

	if ($cmd eq 'clearfav') {
		my $timelongest = $timeToOpen;
		if ($timeToClose > $timeToOpen) {$timelongest = $timeToClose};
		Log3 $name, 4, "$ioname: SD_Rojaflex set $name clearFav running time $timelongest s";
		InternalTimer( (gettimeofday() + $timelongest), \&SD_Rojaflex_clearfav, $name );
		$hash->{clearfavcount} = 0;
	} elsif ($cmd eq 'down') { # Calculate target position and motor state
		if ($na == 1) {$tpos = '100'}; # nicht bei "set pct xx"
		$motor = ($cpos ne $tpos) ? 'down' : 'stop'; # Wenn nicht schon unten, sonst wenn unten.
	} elsif ($cmd eq 'up') {
		if ($na == 1) {$tpos = '0'}; # nicht bei "set pct xx"
		$motor = ($cpos ne $tpos) ? 'up' : 'stop'; # Wenn nicht schon oben, sonst wenn oben
	} elsif ($cmd eq 'stop' || $cmd eq 'savefav') {
		$motor = 'stop';
	}

	$state = $cmd;
	Log3 $name, 3, "$ioname: SD_Rojaflex set $name $state";

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', $state, 1);
	if ($state ne 'clearfav' && $state ne 'gotofav') {
		# Wenn keine PositionUpdates vom Motor kommen, setze gleich die finale Position
		if (AttrVal($name,'bidirectional',1) eq '0') {
			# Jump direct to the final position, because we have no position updates and set motor stop
			$cpos = $tpos;
			$motor = 'stop';
			# Save current position
			if (AttrVal($name,'inversePosition',0) eq '1') {$cpos = 100 - $cpos}; # inverse position
			readingsBulkUpdate($hash, 'pct', $cpos, 1);
			readingsBulkUpdate($hash, 'cpos', $cpos, 1);
		}
		readingsBulkUpdate($hash, 'motor', $motor, 1);
		if (AttrVal($name,'inversePosition',0) eq '1') {$tpos = 100 - $tpos}; # inverse position
		readingsBulkUpdate($hash, 'tpos', $tpos, 1);
	}
	readingsEndUpdate($hash, 1);

	# channel 0 set all devices, we must update all other devices with the same housecode
	if ($channel eq '0') {
		foreach my $d (devspec2array("TYPE=SD_Rojaflex:FILTER=DEF=^$housecode(?!(_0\$)).*\$")) {
			Log3 $name, 3, "$ioname: SD_Rojaflex update $d $state";
			readingsBeginUpdate($defs{$d});
			readingsBulkUpdate($defs{$d}, 'state' , $state , 1);
			if ($state ne 'clearfav' && $state ne 'gotofav') {
				readingsBulkUpdate($defs{$d}, 'motor', $motor, 1);
				readingsBulkUpdate($defs{$d}, 'tpos', $tpos, 1);
				if (AttrVal($defs{$d}{NAME},'bidirectional',1) eq '0') {
					readingsBulkUpdate($defs{$d}, 'pct', $cpos, 1);
					readingsBulkUpdate($defs{$d}, 'cpos', $cpos, 1);
				}
			}
			readingsEndUpdate($defs{$d}, 1);
		}
	}
	return;
}

sub SD_Rojaflex_pctStop {
	my ($name) = @_;
	my $hash = $defs{$name};
	RemoveInternalTimer($name);
	CommandSet($hash, "$name stop");
	return;
}

sub SD_Rojaflex_clearfav {
	my ($name) = @_;
	my $hash = $defs{$name};
	RemoveInternalTimer($name);
	$hash->{clearfavcount} += 1;
	if ($hash->{clearfavcount} < 4) { # 3 mal stop senden
		CommandSet($hash, "$name stop");
		InternalTimer( (gettimeofday() + 1), \&SD_Rojaflex_clearfav, $name );
	} else {
		CommandSet($hash, "$name savefav");
		delete($hash->{clearfavcount});
	}
	return;
}

sub Define {
	# define <name> SD_Rojaflex <hauscode>_<channel>
	# define SD_Rojaflex_Test_11 SD_Rojaflex 7AE3121_11
	# define <name> SD_Rojaflex <hauscode>_<channel> <iodevice>
	# define SD_Rojaflex_Test_11 SD_Rojaflex 7AE3121_11 sduino434

	my ($hash, $def) = @_;
	my @a = split m{\s+}xms , $def;
	my $name = $hash->{NAME};
	my $iodevice;
	my $ioname;

	return 'Define SD_Rojaflex wrong syntax: define <name> SD_Rojaflex housecode_channel' if (int(@a) < 3);
	my ($housecode, $channel) = split /[_]/xms , $a[2], 2;
	return 'Define SD_Rojaflex wrong syntax, must be: housecode_channel' if (!defined $housecode || !defined $channel);
	return 'Define SD_Rojaflex wrong housecode format: specify a 7 digit hex value [a-fA-F0-9]' if ($housecode !~ m/^[a-fA-F0-9]{7}$/xms );
	return 'Define SD_Rojaflex wrong channel format: specify a decimal value [0-15]' if ($channel !~ m/^[0-9]{1,2}$/xms || $channel > 15);
	if (scalar @a == 4) { $iodevice = $a[3] };

	$hash->{DEF} = $a[2];
	$hash->{VersionModule} = $VERSION;

	$modules{SD_Rojaflex}{defptr}{$hash->{DEF}} = $hash;
	if (exists $modules{SD_Rojaflex}{defptr}{ioname} && !defined $iodevice) { $ioname = $modules{SD_Rojaflex}{defptr}{ioname} };
	if (!defined $iodevice) { $iodevice = $ioname }
	AssignIoPort($hash, $iodevice);

	if (not defined($attr{$name}{webCmd})) {$attr{$name}{webCmd} = 'up:stop:down'};

	Log3 $name, 4, "SD_Rojaflex_Define: $a[0] HC=$housecode CHN=$channel";
	return;
}

sub Undef {
	my ($hash, $name) = @_;
	if (defined($hash->{CODE}) && defined($modules{SD_Rojaflex}{defptr}{$hash->{CODE}})) { delete($modules{SD_Rojaflex}{defptr}{$hash->{CODE}}) };
	RemoveInternalTimer($name);
	return;
}

sub Parse {
	my ($iohash, $msg) = @_;
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split /[#]/xms , $msg;
	$protocol =~ s/^[P](\d+)/$1/xms; # extract protocol
	my $EMPTY = q{};

	if (length ($rawData) < 18 ) { # 083122FD2C1A011AB1
		Log3 $ioname, 1, "$ioname: SD_Rojaflex_Parse, rawData $rawData, message is to short";
		return;
	}

	Log3 $ioname, 4, "$ioname: SD_Rojaflex_Parse, Protocol $protocol, rawData $rawData";

	my $housecode = substr $rawData,2,7;
	my $channel = hex substr $rawData,9,1;
	my $deviceCode = $housecode . q{_} . $channel;

	Log3 $ioname, 4, "$ioname: SD_Rojaflex_Parse, deviceCode $deviceCode, housecode $housecode, channel $channel";

	my $def = $modules{SD_Rojaflex}{defptr}{$iohash->{NAME} . q{_} . $deviceCode};
	$modules{SD_Rojaflex}{defptr}{ioname} = $ioname;
	if (!$def) { $def = $modules{SD_Rojaflex}{defptr}{$deviceCode} };

	if (!$def) {
		Log3 $ioname, 3, "$ioname: SD_Rojaflex_Parse, UNDEFINED device detected, Protocol $protocol, deviceCode $deviceCode, housecode $housecode, channel $channel, please define it";
		return "UNDEFINED SD_Rojaflex_$deviceCode SD_Rojaflex $deviceCode";
	}

	my $hash = $def;
	my $name = $hash->{NAME};
	return $EMPTY if (IsIgnored($name));

	my $state;
	my $cmd = substr $rawData,10,1; # (0x0 = stop, 0x1 = up,0x8 = down, 0xE = Request, 0x9 = save/clear Pos, 0xD = goto Pos)
	my $dev = substr $rawData,11,1; # (0xA = remote control, 0x5 = tubular motor)
	my $motor = ReadingsVal($name, 'motor', 'stop');
	my $cpos = ReadingsVal($name, 'cpos', 50);
	my $tpos = ReadingsVal($name, 'tpos', 50);
	if (AttrVal($name,'inversePosition',0) eq '1') {
		$cpos = 100 - $cpos; # inverse position
		$tpos = 100 - $tpos; # inverse position
	}

	if ($dev eq 'A') { # remote control
		$state = $codes{$cmd};
		# Calculate target position and motor state
		if ($cmd eq '8') { # down
			$tpos = '100';
			if (AttrVal($name,'bidirectional',1) eq '0') {$cpos = $tpos};
			if ($cpos ne $tpos) {$motor = 'down'}; # Wenn nicht schon unten
			if ($cpos eq $tpos) {$motor = 'stop'}; # Wenn unten
		} elsif ($cmd eq '1') { # up
			$tpos = '0';
			if (AttrVal($name,'bidirectional',1) eq '0') {$cpos = $tpos};
			if ($cpos ne $tpos) {$motor = 'up'}; # Wenn nicht schon oben
			if ($cpos eq $tpos) {$motor = 'stop'}; # Wenn oben
		} elsif ($cmd eq '0' || $cmd eq '9') { # stop || savefav
			$motor = 'stop';
		}
	} elsif ($dev eq '5') { # tubular motor
		$cpos = hex substr $rawData,12,2;
		if ($cpos == 100) {$state = 'closed'}
		elsif ($cpos == 0) {$state = 'open'}
		else {$state = $cpos};
		# Calculate target position and motor state
		if ($cpos eq '0' && $motor eq 'up') {$motor = 'stop'} # open
		elsif ($cpos eq '100' && $motor eq 'down') {$motor = 'stop'}; # closed
	}

	if (AttrVal($name,'inversePosition',0) eq '1') {
		$cpos = 100 - $cpos; # inverse position
		$tpos = 100 - $tpos; # inverse position
	}

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', $state);
	if ($state ne 'clearfav' && $state ne 'gotofav' && $state ne 'request') {
		readingsBulkUpdate($hash, 'motor', $motor);
		readingsBulkUpdate($hash, 'tpos', $tpos);
		if (AttrVal($name,'bidirectional',1) eq '0' || $dev eq '5') {
			readingsBulkUpdate($hash, 'pct', $cpos);
			readingsBulkUpdate($hash, 'cpos', $cpos);
		}
	}
	readingsEndUpdate($hash, 1);

	# channel 0 set all devices, we must update all other devices with the same housecode
	if ($channel eq '0' && $state ne 'request') {
		foreach my $d (devspec2array("TYPE=SD_Rojaflex:FILTER=DEF=^$housecode(?!(_0\$)).*\$")) {
			Log3 $name, 3, "$ioname: SD_Rojaflex receive $housecode channel 0, update $d $state";
			readingsBeginUpdate($defs{$d});
			readingsBulkUpdate($defs{$d}, 'state' , $state , 1);
			if ($state ne 'clearfav' && $state ne 'gotofav') {
				readingsBulkUpdate($defs{$d}, 'motor', $motor, 1);
				readingsBulkUpdate($defs{$d}, 'tpos', $tpos, 1);
				if (AttrVal($defs{$d}{NAME},'bidirectional',1) eq '0') {
					readingsBulkUpdate($defs{$d}, 'pct', $cpos, 1);
					readingsBulkUpdate($defs{$d}, 'cpos', $cpos, 1);
				}
			}
			readingsEndUpdate($defs{$d}, 1);
			DoTrigger($defs{$d}{NAME},undef);
		}
	}
	return $name;
}

1;

=pod
=encoding utf8
=item device
=item summary devices communicating using the Rojaflex protocol
=item summary_DE Anbindung von Rojaflex Ger&auml;ten

=begin html

<a id="SD_Rojaflex"></a>
<h3>SD_Rojaflex</h3>
<ul>
	The SD_Rojaflex module decrypts and sends messages that are processed by the SIGNALduino.<br>
	Currently supported are the following types: Rojaflex HSR-15 (only modus bidirectional).
	<br><br>

	<a id="SD_Rojaflex-define"></a>
	<b>Define</b>
	<ul>
		Newly received devices are usually automatically created in FHEM via autocreate in the following form:<br>
		<code>SD_Rojaflex_3122FD2_9</code><br><br>
		But it is also possible to define the devices yourself:<br>
		<code>define &lt;name&gt; SD_Rojaflex &lt;housecode&gt;_&lt;channel&gt;</code>
		<br><br>
		<code>&lt;name&gt;</code> is any name assigned to the device.
		For a better overview, we recommend a name in the form &quot;SD_Rojaflex_AE22F31_12&quot; to use,
		in which &quot;AE22F31&quot; the house code used and &quot;12&quot; represents the channel.
		<br><br>
		<code>&lt;housecode&gt;</code> corresponds to the house code of the remote control used or of the device that is to be controlled.
		<br><br>
		<code>&lt;channel&gt;</code> represents the channel of the devices used.
		A special feature is channel 0. This is used to control all drives with the same house code simultaneously.
	</ul>
	<br>

	<a id="SD_Rojaflex-set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;value&gt; [&lt;num&gt;]</code>
		<br><br>
		<code>&lt;value&gt;</code> can be one of the following values:<br>
		<ul>
			<a id="SD_Rojaflex-set-clearfav"></a>
			<li>clearfav - Deletes the saved position.</li>
			<a id="SD_Rojaflex-set-down"></a>
			<li>down - Moves the drive completely down.</li>
			<a id="SD_Rojaflex-set-gotofav"></a>
			<li>gotofav - Moves the drive to the saved position.</li>
			<a id="SD_Rojaflex-set-pct"></a>
			<li>pct - Moves the drive to the position specified in percent.</li>
			<a id="SD_Rojaflex-set-savefav"></a>
			<li>savefav - Saves the current position.</li>
			<a id="SD_Rojaflex-set-stop"></a>
			<li>stop - Stops the drive.</li>
			<a id="SD_Rojaflex-set-up"></a>
			<li>up - Moves the drive completely upwards.</li>
		</ul>
		Optionally with &lt;num&gt; the number of repetitions of the messages when sending in the range from 1 to 9 can be specified.<br>
		At <code>&lt;pct&gt;</code> a percentage value can be selected as the target position from a drop-down list.
	</ul>
	<br>

	<a id="SD_Rojaflex-attr"></a>
	<b>Attributes</b>
	<ul>
		<a id="SD_Rojaflex-attr-IODev"></a>
		<li><a href="#IODev">IODev</a> - Sets the device that is to be used to send the signals.</li>
		<a id="SD_Rojaflex-attr-bidirectional"></a>
		<li>bidirectional - If there is no feedback from the drive, the readings pct and cpos are calculated.</li>
		<a id="SD_Rojaflex-attr-do_not_notify"></a>
		<li><a href="#do_not_notify">do_not_notify</a> - Disable FileLog/notify/inform notification for a device. This affects the received signal, the set and trigger commands.</li>
		<a id="SD_Rojaflex-attr-inversePosition"></a>
		<li>inversePosition - Reverses the readings of positions pct, cpos, and tpos.</li>
		<a id="SD_Rojaflex-attr-dummy"></a>
		<li>dummy - If the attribute is set, it is no longer possible to send.</li>
		<a id="SD_Rojaflex-attr-ignore"></a>
		<li><a href="#ignore">ignore</a> - The device will be ignored in the future if this attribute is set.</li>
		<a id="SD_Rojaflex-attr-repetition"></a>
		<li>repetition - Number of repetitions of the send commands.</li>
		<a id="SD_Rojaflex-attr-showtime"></a>
		<li><a href="#showtime">showtime</a> - Used in FHEMWEB to show the time of the last activity instead of the status in the overall view.</li>
		<a id="SD_Rojaflex-attr-timeToClose"></a>
		<li>timeToClose - Duration for complete closing in seconds.</li>
		<a id="SD_Rojaflex-attr-timeToOpen"></a>
		<li>timeToOpen - Time for complete opening in seconds.</li>
	</ul>
	<br>

	<b>Readings</b>
	<ul>
		<li>IODev - Device used for sending.</li>
		<li>cpos - Current position in percent.</li>
		<li>motor - State of the drive.</li>
		<li>pct - Current position in percent.</li>
		<li>state - Current status.</li>
		<li>tpos - Target position in percent.</li>
	</ul>

</ul>

=end html

=begin html_DE

<a id="SD_Rojaflex"></a>
<h3>SD_Rojaflex</h3>
<ul>
	Das SD_Rojaflex-Modul entschl&uuml;sselt und sendet Nachrichten, die vom SIGNALduino verarbeitet werden.<br>
	Unterst&uuml;tzt werden z.Z. folgende Typen: Rojaflex HSR-15 (nur Modus bidirektional).
	<br><br>

	<a id="SD_Rojaflex-define"></a>
	<b>Define</b>
	<ul>
		Neu empfangene Geräte werden in FHEM normalerweise per autocreate automatisch in folgender Form angelegt:<br>
		<code>SD_Rojaflex_3122FD1_9</code><br><br>
		Es ist aber auch möglich, die Geräte selbst zu definieren:<br>
		<code>define &lt;name&gt; SD_Rojaflex &lt;hauscode&gt;_&lt;kanal&gt;</code>
		<br><br>
		<code>&lt;name&gt;</code> ist ein beliebiger Name, der dem Ger&auml;t zugewiesen wird.
		Zur besseren &Uuml;bersicht wird empfohlen einen Namen in der Form &quot;SD_Rojaflex_AE22F31_12&quot; zu verwenden,
		wobei &quot;AE22F31&quot; den verwendeten Hauscode und &quot;12&quot; den Kanal darstellt.
		<br><br>
		<code>&lt;hauscode&gt;</code> entspricht dem Hauscode der verwendeten Fernbedienung bzw. des Ger&auml;tes, das gesteuert werden soll.
		<br><br>
		<code>&lt;kanal&gt;</code> stellt den Kanal der verwendeten Ger&auml;te dar.
		Eine Besonderheit ist Kanal 0. Dieser wird verwendet, um sämtliche Antriebe mit gleichem Hauscode simultan zu steuern.
	</ul>
	<br>

	<a id="SD_Rojaflex-set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;value&gt; [&lt;anz&gt;]</code>
		<br><br>
		<code>&lt;value&gt;</code> kann einer der folgenden Werte sein:<br>
		<ul>
			<a id="SD_Rojaflex-set-clearfav"></a>
			<li>clearfav - Löscht die gespeicherte Position.</li>
			<a id="SD_Rojaflex-set-down"></a>
			<li>down - Fährt den Antrieb komplett nach unten.</li>
			<a id="SD_Rojaflex-set-gotofav"></a>
			<li>gotofav - Fährt den Antrieb auf die gespeicherte Position.</li>
			<a id="SD_Rojaflex-set-pct"></a>
			<li>pct - Fährt den Antrieb auf die in Prozent angegebene Position.</li>
			<a id="SD_Rojaflex-set-savefav"></a>
			<li>savefav - Speichert die aktuelle Position.</li>
			<a id="SD_Rojaflex-set-stop"></a>
			<li>stop - Stoppt den Antrieb.</li>
			<a id="SD_Rojaflex-set-up"></a>
			<li>up - Fährt den Antrieb komplett nach oben.</li>
		</ul>
		Optional kann mit &lt;anz&gt; die Anzahl Wiederholungen der Nachrichten beim Senden im Bereich von 1 bis 9 angegeben werden.<br>
		Bei <code>&lt;pct&gt;</code> kann als Zielposition aus einer Dropdown-Liste ein prozentualer Wert gewählt werden.
	</ul>
	<br>

	<a id="SD_Rojaflex-attr"></a>
	<b>Attribute</b>
	<ul>
		<a id="SD_Rojaflex-attr-IODev"></a>
		<li><a href="#IODev">IODev</a> - Setzt das Gerät, welches zum Senden der Signale verwendet werden soll.</li>
		<a id="SD_Rojaflex-attr-bidirectional"></a>
		<li>bidirectional - Falls vom Antrieb keine Rückmeldungen erfolgen, werden die Readings pct und cpos errechnet.</li>
		<a id="SD_Rojaflex-attr-do_not_notify"></a>
		<li><a href="#do_not_notify">do_not_notify</a> - Deaktiviert die Benachrichtigungen FileLog/notify/inform für das Gerät. Dies betrifft das empfangene Signal, die Set- und Triggerbefehle.</li>
		<a id="SD_Rojaflex-attr-inversePosition"></a>
		<li>inversePosition - Kehrt die Readings der Positionen pct, cpos und tpos um.</li>
		<a id="SD_Rojaflex-attr-dummy"></a>
		<li>dummy - Wenn das Attribut gesetzt ist, kann nicht mehr gesendet werden.</li>
		<a id="SD_Rojaflex-attr-ignore"></a>
		<li><a href="#ignore">ignore</a> - Das Gerät wird in Zukunft ignoriert, wenn dieses Attribut gesetzt ist.</li>
		<a id="SD_Rojaflex-attr-repetition"></a>
		<li>repetition - Anzahl Wiederholungen der Sendebefehle.</li>
		<a id="SD_Rojaflex-attr-showtime"></a>
		<li><a href="#showtime">showtime</a> - Wird im FHEMWEB verwendet, um die Zeit der letzten Aktivität anstelle des Status in der Gesamtansicht anzuzeigen.</li>
		<a id="SD_Rojaflex-attr-timeToClose"></a>
		<li>timeToClose - Dauer für komplettes Schließen in Sekunden.</li>
		<a id="SD_Rojaflex-attr-timeToOpen"></a>
		<li>timeToOpen - Dauer für komplettes Öffnen in Sekunden.</li>
	</ul>
	<br>

	<b>Readings</b>
	<ul>
		<li>IODev - Gerät, das zum Senden verwendet wird.</li>
		<li>cpos - Aktuelle Position in Prozent.</li>
		<li>motor - Zustand des Antriebes.</li>
		<li>pct - Aktuelle Position in Prozent.</li>
		<li>state - Aktueller Status.</li>
		<li>tpos - Zielposition in Prozent.</li>
	</ul>

</ul>

=end html_DE
=for :application/json;q=META.json 10_SD_Rojaflex.pm
{
  "abstract": "devices communicating using the Rojaflex protocol",
  "author": [
    "Sidey <>",
    "elektron-bbs <>"
  ],
  "x_fhem_maintainer": [
    "Sidey"
  ],
  "x_fhem_maintainer_github": [
    "Sidey79",
    "elektron-bbs",
	"HomeAutoUser"
  ],
  "description": "The SD_Rojaflex module decrypts and sends messages that are processed by the SIGNALduino.",
  "dynamic_config": 1,
  "keywords": [
    "fhem-sonstige-systeme",
    "fhem-hausautomations-systeme",
    "fhem-mod",
    "signalduino",
	"Rojaflex"    
  ],
  "license": [
    "GPL_2"
  ],
  "meta-spec": {
    "url": "https://metacpan.org/pod/CPAN::Meta::Spec",
    "version": 2
  },
  "name": "FHEM::SD_Rojaflex",
  "prereqs": {
    "runtime": {
      "requires": {
        "GPUtils": "0"
      }
    },
    "develop": {
      "requires": {
        "GPUtils": "0"
      }
    }
  },
  "release_status": "stable",
  "resources": {
    "bugtracker": {
      "web": "https://github.com/RFD-FHEM/RFFHEM/issues/"
    },
    "x_testData": [
      {
        "url": "https://raw.githubusercontent.com/RFD-FHEM/RFFHEM/master/t/FHEM/10_SD_Rojaflex/testData.json",
        "testname": "Testdata with SD_Rojaflex sensors"
      }
    ],
    "repository": {
      "x_master": {
        "type": "git",
        "url": "https://github.com/RFD-FHEM/RFFHEM.git",
        "web": "https://github.com/RFD-FHEM/RFFHEM/tree/master"
      }
    },
    "x_support_community": {
      "board": "Sonstige Systeme",
      "boardId": "29",
      "cat": "FHEM - Hausautomations-Systeme",
      "description": "Sonstige Hausautomations-Systeme",
      "forum": "FHEM Forum",
      "rss": "https://forum.fhem.de/index.php?action=.xml;type=rss;board=29",
      "title": "FHEM Forum: Sonstige Systeme",
      "web": "https://forum.fhem.de/index.php/board,29.0.html"
    },
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SIGNALduino"
    }
  }
}
=end :application/json;q=META.json
=cut
