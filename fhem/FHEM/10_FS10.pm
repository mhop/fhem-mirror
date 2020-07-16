##############################################
# $Id$
#
# FS10 basierend auf dem FS20 Modul angepasst fuer SIGNALduino, elektron-bbs
#
# 2020-06-06                    Ueberarbeitung PBP
# 2020-04-28                    Einschraenkung bei Kommando "attr FS10_x_xx repetition x" auf gueltige Werte 1 - 9
# 2019-03-23                    Forward declarations and rename subs
# 2018-04-28  FS10_Define       IO-Device kann angegeben werden
# 2017-11-25  FS10_Set          Checksumme fuer Wiederholung wurde falsch berechnet
#                               Pause zwischen Wiederholung jetzt immer 200 mS
#                               SignalRepeats jetzt auch im Abstand von 200 mS
#                               Anzahl Wiederholungen bei Dimm-Befehlen korrigiert
#                               Anzahl Dimup/Dimdown auf 1-10 begrenzt
#             FS10_Initialize   Anzahl Wiederholungen auf 1 bis 9 begrenzt

package FS10;

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);

our $VERSION = '1.1';

# Export to main context with different name
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
		CommandDefine
		CommandDelete
		IOWrite
		IsDummy
		IsIgnored
		Log3
		modules
		SetExtensions
		readingsSingleUpdate
	))
};

# Forward declarations
sub nibble2dec;
sub dec2nibble;

my %fs10_c2b; # reverse codes
my %codes = (
	'0' => 'off_1',
	'2' => 'off_2',
	'1' => 'on_1',
	'3' => 'on_2',
	'8' => 'dimdown_1',  # 0 | 8 = 8
	'4' => 'dimdown_2',
	'9' => 'dimup_1',    # 1 | 8 = 9
	'5' => 'dimup_2',
);

my %models = (
	FS10_ST => 'simple',
	FS10_DI => 'dimmer',
	FS10_HD => 'dimmer',
	FS10_SA => 'timer',
	FS10_MS => 'simple',
	FS10_S4 => 'remote',
	FS10_S8 => 'remote',
);

sub Initialize {
	my ($hash) = @_;
	for my $k (keys %codes) {
		$fs10_c2b{$codes{$k}} = $k; # reverse codes
	}
	$hash->{Match}      = '^P61#[a-fA-F0-9]{8,12}';
	$hash->{SetFn}      = \&Set;
	$hash->{DefFn}      = \&Define;
	$hash->{UndefFn}    = \&Undef;
	$hash->{ParseFn}    = \&Parse;
	$hash->{AttrFn}     = \&Attr;
	$hash->{AttrList}   = 'IODev follow-on-for-timer:1,0 follow-on-timer '.
	                      'do_not_notify:1,0 repetition:1,2,3,4,5,6,7,8,9 '.
	                      'ignore:1,0 dummy:1,0 showtime:1,0 '.
	                      "$main::readingFnAttributes " .
	                      'model:'.join q{,} , sort keys %models;
	$hash->{AutoCreate} = {'FS10.*' => {FILTER => '%NAME', autocreateThreshold => '5:180', GPLOT => q{}}};
	return
}

sub Attr {
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
	# $cmd  - Vorgangsart, kann die Werte "del" (loeschen) oder "set" (setzen) annehmen
	# $name - Geraetename
	# $attrName - Attribut-Name
	# $attrValue - Attribut-Wert

	if ($cmd eq 'set') {
		if ($attrName eq 'repetition') {
			if ($attrValue !~ m/^[1-9]$/xms) { return "$name: Unallowed value $attrValue for the attribute repetition (must be 1 - 9)!" };
		}
	}
	return;
}

sub Set {
	my ($hash, $name, @a) = @_;
	my $ioname = $hash->{IODev}{NAME};
	my $ret = undef;
	my $na = int @a; # Anzahl in Array

	return 'no set value specified' if ($na < 1); # if ($na < 2 || $na > 3);
	return "Dummydevice $hash->{NAME}: will not set data" if (IsDummy($hash->{NAME}));

	my $model = AttrVal($name, 'model', 'FS10_ST');
	my $modelType = $models{$model};
	my $alias = AttrVal($name, 'alias', q{});
	my $list;
	if ($modelType ne 'remote') { $list .= 'off:noArg on:noArg ' };
	if ($modelType eq 'dimmer' ) { $list .= 'dimup:1,2,3,4,5,6,7,8,9,10 dimdown:1,2,3,4,5,6,7,8,9,10 ' };

	return SetExtensions($hash, $list, $name, @a) if ( $a[0] eq q{?} );
	return SetExtensions($hash, $list, $name, @a) if ( !grep { /^\Q$a[0]\E($|:)/xms } split q{ } , $list );

	my $setstate = $a[0];
	my $ebeneh = substr $hash->{BTN}, 0, 1;
	my $ebenel = substr $hash->{BTN}, 1, 1;
	my $housecode = $hash->{HC} - 1;
	my $kc;
	my $SignalRepeats = AttrVal($name,'repetition', '0') + 1;
	my $dimm = 0;
	my $newmsg = 'P61#';

	if ($model eq 'FS10_MS') {
		$SignalRepeats = 1;
	}

	if ($SignalRepeats > 10) {
		$SignalRepeats = 10;
	}

	if ($na > 1 && $setstate =~ m/dim/xms) { # Anzahl dimup / dimdown
		$dimm += $a[1];
		if ($dimm < 1 || $dimm > 10) {
			Log3 $name, 1, "$ioname: FS10 set $name $setstate $dimm - ERROR dimm value too low or high (1-10)";
			return "FS10 set $name $setstate $dimm - ERROR: dimm value too low or high (1-10)";
		} else {
			Log3 $name, 3, "$ioname: FS10 set $name $setstate $dimm $alias";
		}
	} else {
		Log3 $name, 3, "$ioname: FS10 set $name $setstate $alias";
	}
	Log3 $name, 5, "$ioname: FS10 set $name hc=$housecode ebeneHL=$ebeneh$ebenel setstate=$setstate";

	for my $i (1..2) {
		my $sum = 0;
		$kc = $fs10_c2b{$setstate . '_' . $i};
		$kc = $kc & 7;
		if (defined $kc) {
			Log3 $name, 5, "$ioname: FS10 set $name setstate$i=$setstate command=$kc";
			$newmsg .= '0000000000001'; # 12 Bit Praeambel, 1 Pruefbit
			$newmsg .= dec2nibble($kc); # 1. setstate
			$sum += $kc;
			$newmsg .= dec2nibble($ebenel); # 2. Ebene low
			$sum += $ebenel;
			$newmsg .= dec2nibble($ebeneh); # 3. Ebene high
			$sum += $ebeneh;
			$newmsg .= '10001'; # 4. unused
			$newmsg .= dec2nibble($housecode); # 5. housecode
			$sum += $housecode;
			$sum = (10 - $sum) & 7;
			$newmsg .= dec2nibble($sum); # 6. Summe
			if ($dimm == 0) { # ein / aus
				if ($i == 1) { # 1. Teil Nachricht
					$newmsg .= 'PPP'; # 3*32400=97200 Pause
				} else { # 2. Teil Nachricht
					if ($SignalRepeats == 1) {
						$newmsg .= '#R1'; # 1 Repeat
					} else {
						$newmsg .= 'PPPPPP#R' . $SignalRepeats; # 6*32400=194400 Pause . Repeats
					}
				}
			} else { # dimmen
				if ($i == 1) { # 1. Nachricht
					$newmsg .= 'PPPPPPPPPPPPPPPP'; # 16*32400=518400 Pause . 1 Repeat (original remote control)
					if ($dimm >= 2) {
						$newmsg .= '#R1';
						IOWrite($hash, 'sendMsg', $newmsg);
						Log3 $name, 5, "$ioname: FS10 set dimm $dimm, 1. sendMsg=$newmsg";
						$newmsg = 'P61#'; # Reset newmsg fuer 2. Nachricht
					}
				} else { # 2. Nachricht
					if ($dimm == 1) {
						$newmsg .= '#R1'; # 1 Repeat
					} else {
						$newmsg .= 'PPPPPP#R' . $dimm; # 6*32400=194400 Pause . Repeats
						Log3 $name, 5, "$ioname: FS10 set dimm $dimm, 2. sendMsg=$newmsg";
					}
				}
			}
			if ($i == 2) { # 2. Nachricht
				Log3 $name, 5, "$ioname: FS10 set sendMsg=$newmsg";
				IOWrite($hash, 'sendMsg', $newmsg);
			}
		}
	}

	# Set the state of a device to off if on-for-timer is called
	if ($modules{FS10}{ldata}{$name}) {
		CommandDelete(undef, $name . '_timer');
		delete $modules{FS10}{ldata}{$name};
	}

	# following timers
	if ($setstate eq 'on' && AttrVal($name, 'follow-on-for-timer', 0)) {
		my $dur = AttrVal($name, 'follow-on-timer', 0);
		if ($dur > 0) {
			my $newState = 'off';
			my $to = sprintf '%02d:%02d:%02d', $dur/3600, ($dur%3600)/60, $dur%60;
			Log3 $name, 3, "$ioname: FS10_set $name Set_Follow +$to setstate $newState";
			CommandDefine(undef, $name."_timer at +$to "."setstate $name $newState; trigger $name $newState");
			$modules{FS10}{ldata}{$name} = $to;
		}
	}

	readingsSingleUpdate($hash, 'state', $setstate, 1);
	return $ret;
}

sub Define {
	# define <name> FS10 <hauscode>_<button>
	# define FS10_Test_1 FS10 7_11
	# define <name> FS10 <hauscode>_<button> <iodevice>
	# define FS10_Test_1 FS10 7_11 sduino434
	my ($hash, $def) = @_;
	my @a = split m{\s+}xms , $def;
	my $name = $hash->{NAME};
	my $iodevice;
	my $ioname;

	return 'Define FS10 wrong syntax: define <name> FS10 housecode_button' if (int(@a) < 3);
	my ($housecode, $btncode) = split /[_]/xms , $a[2], 2;
	return 'Define FS10 wrong syntax, must be: housecode_button' if (!defined $housecode || !defined $btncode);
	return 'Define FS10 wrong housecode format: specify a 1 digit value [1-8]' if ($housecode !~ m/^[1-8]$/xms );
	return 'Define FS10 wrong button format: specify a 2 digit value [0-7]' if ($btncode !~ m/^[0-7]{2}$/xms ); # Ebene Low, Ebene High
	if (scalar @a == 4) { $iodevice = $a[3] };

	$hash->{DEF} = $a[2];
	$hash->{HC} = $housecode;
	$hash->{BTN} = $btncode;
	$hash->{CODE} = $a[2];
	$hash->{VersionModule} = $VERSION;

	$modules{FS10}{defptr}{$hash->{DEF}} = $hash;
	if (exists $modules{FS10}{defptr}{ioname} && !defined $iodevice) { $ioname = $modules{FS10}{defptr}{ioname} };
	if (!defined $iodevice) { $iodevice = $ioname }
	AssignIoPort($hash, $iodevice);

	Log3 $name, 4, "FS10_Define: $a[0] HC=$housecode BTN=$btncode";
	return;
}

sub Undef {
	my ($hash, $name) = @_;
	if (defined($hash->{CODE}) && defined($modules{FS10}{defptr}{$hash->{CODE}})) { delete($modules{FS10}{defptr}{$hash->{CODE}}) };
	return;
}

sub Parse {
	my ($iohash, $msg) = @_;
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split /[#]/xms , $msg;
	my $err;
	my $gesErr;
	my $cde;
	my $ebenel;
	my $ebeneh;
	my $u;
	my $dev;
	my $sum;
	my $rsum;
	my $hlen = length $rawData;
	my $blen = $hlen * 4;
	$protocol =~ s/^[P](\d+)/$1/xms; # extract protocol
	my $bitData = unpack "B$blen" , pack "H$hlen", $rawData;
	my $EMPTY = q{};

	Log3 $ioname, 5, "$ioname: FS10_Parse Protocol $protocol, rawData $rawData";
	Log3 $ioname, 5, "$ioname: FS10_Parse rawBitData $bitData ($blen)";

	my $datastart = 0;
	while ($datastart < $blen) {
		last if substr($bitData,$datastart,1) eq q{1} ; # Start bei erstem Bit mit Wert 1 suchen
		$datastart++;
	}

	if ($datastart == $blen || $datastart > 12) { # all bits are 0 || more then 12 bit preamble
		Log3 $ioname, 4, "$ioname: FS10_Parse $msg - ERROR message contains too many zeros";
		return $EMPTY;
	}
	$bitData = substr $bitData , $datastart;
	$blen = length $bitData;
	if ($blen < 30 || $blen > 40) {
		Log3 $ioname, 4, "$ioname: FS10_Parse $msg - ERROR message too short or too long ($blen bit) ";
		return $EMPTY;
	}

	Log3 $ioname, 5, "$ioname: FS10_Parse preamble $datastart bit, bitData=$bitData ($blen bit)";

	($err, $cde) = nibble2dec(substr $bitData, 0, 5); # Command Code
	$gesErr = $err;
	$sum = $cde;
	($err, $ebenel) = nibble2dec(substr $bitData, 5, 5); # EbeneL
	$gesErr += $err;
	$sum += $ebenel;
	($err, $ebeneh) = nibble2dec(substr $bitData,10,5); # EbeneH
	$gesErr += $err;
	$sum += $ebeneh;
	($err, $u) = nibble2dec(substr $bitData,15,5); # unbenutzt, muss 0 sein
	if ($u != 0) {
		$gesErr++;
	}
	$sum += $u;
	($err, $dev) = nibble2dec(substr $bitData,20,5); # housecode
	$gesErr += $err;
	$sum += $dev;
	($err, $rsum) = nibble2dec(substr $bitData,25,5); # Summe
	$gesErr += $err;

	$sum = (10 - $sum) & 7;
	if ($sum != $rsum) {
		Log3 $ioname, 4, "$ioname: FS10_Parse $msg - ERROR sum=$sum != rsum=$rsum";
		return $EMPTY;
	}
	if ($gesErr > 0) {
		Log3 $ioname, 4, "$ioname: FS10_Parse $msg - ERROR parity/bit5 $gesErr errors";
		return $EMPTY;
	}

	$dev++;
	my $v = $codes{$cde};
	if (!defined $v) { $v = "unknown_$cde"; }
	my $btn = $ebeneh . $ebenel;
	my $deviceCode = $dev . q{_} . $btn;

	Log3 $ioname, 5, "$ioname: FS10_Parse cde=$cde $v ebeneHL=$btn u=$u hc=$dev rsum=$rsum";

	$v =~ s/_[12]$//xms; # _1 oder _2 am Ende abschneiden

	my $def = $modules{FS10}{defptr}{$iohash->{NAME} . q{.} . $deviceCode};
	$modules{FS10}{defptr}{ioname} = $ioname;
	if (!$def) { $def = $modules{FS10}{defptr}{$deviceCode} };

	if (!$def) {
		Log3 $ioname, 3, "$ioname: FS10_Parse unknown device housecode $dev button $btn code $cde ($v), please define it";
		return "UNDEFINED FS10_$deviceCode FS10 $deviceCode";
	}

	my $hash = $def;
	my $name = $hash->{NAME};
	return $EMPTY if (IsIgnored($name));
	Log3 $name, 5, "$ioname: FS10_Parse $name $v";
	Log3 $name, 5, "$ioname: FS10_Parse $name bitdata=$bitData blen=$blen";

	if ($v eq 'on' && AttrVal($name, 'follow-on-for-timer', 0)) {
		my $dur = AttrVal($name, 'follow-on-timer', 0);
		if ($dur > 0) {
			my $newState = 'off';
			my $to = sprintf '%02d:%02d:%02d', $dur/3600, ($dur%3600)/60, $dur%60;
			Log3 $name, 4, "$ioname: FS10_Parse $name Set_Follow +$to setstate $newState";
			CommandDefine(undef, $name."_timer at +$to "."setstate $name $newState; trigger $name $newState");
			$modules{FS10}{ldata}{$name} = $to;
		}
	}

	readingsSingleUpdate($hash, 'state', $v, 1);
	return $name;
}

sub nibble2dec {
	my $nibble = shift;
	my $parity = 1; # Paritaet ungerade
	my $err;
	my $dec = oct '0b' . substr $nibble, 2;

	for my $i (1 .. 4) {
		$parity += substr $nibble, $i, 1;
	}
	$err = $parity % 2;
	if (substr($nibble, 0, 1) eq '0') { # das erste Bit muss 1 sein
		$err += 1;
	}
	return ($err, $dec);
}

sub dec2nibble {
	my $num = shift;
	my $parity = 1; # Paritaet ungerade
	my $result = q{};

	for (0 .. 2) {
		my $reminder = $num % 2; # Modulo division to get reminder
		$result = $reminder . $result; # Concatenation of two numbers
		$parity += $reminder;
		$num /= 2; # New Value of decimal number to do next set of above operations
	}
	$result = ($parity % 2) . $result . '1'; # paritybit . bin(num) . checkbit
	return $result;
}

1;

__END__

=pod
=encoding utf8
=item device
=item summary devices communicating using the ELV FS10 protocol
=item summary_DE Anbindung von FS10 Ger&auml;ten

=begin html

<a name="FS10"></a>
<h3>FS10</h3>
<ul>
	The FS10 module decrypts and sends FS10 messages, which are processed by the SIGNALduino.
	The following types are supported at the moment: FS10-ST, FS10-DI, FS10-HD, FS10-SA, FS10-MS, FS10-S4 and FS10-S8.
	<br><br>

	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; FS10 &lt;hauscode&gt;_&lt;button&gt;</code>
		<br><br>
		<code>&lt;name&gt;</code> is any name that is assigned to the device.
		For a better overview it is recommended to use a name in the form &quot;FS10_6_12&quot;,
		where &quot;6&quot; is the used house code and &quot;12&quot; is the address of the button.
		<br><br>
		<code>&lt;hauscode&gt;</code> corresponds to the house code of the remote control or the device to be controlled. The house code is 1-8.
		<br><br>
		<code>&lt;button&gt;</code> represents the keyboard level or address of the devices used.
		Address &quot;11&quot; corresponds to the two buttons at the top row of remote control FS10-S8.
	</ul>
	<br><br>

	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;value&gt; [&lt;anz&gt;]</code>
		<br><br>
		<code>&lt;value&gt;</code> can be one of the following values::<br>
		<ul>
			<li>dimdown</li>
			<li>dimup</li>
			<li>off</li>
			<li>on</li>
		</ul>
		With dimup and dimdown, optionally with &lt;anz&gt; the number of repetitions can be specified in the range from 1 to 9.
		<br><br>
		The <a href="#setExtensions">set extensions</a> are supported.
	</ul>
	<br><br>

	<b>Attribute</b>
	<ul>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#eventMap">eventMap</a></li>
		<li>follow-on-for-timer (enable/disable follow-on-timer)</li>
		<li>follow-on-timer (Number of seconds after the timer of the FS10_SA the state automatically goes back to off.)</li>
		<li><a href="#ignore">ignore</a></li>
		<li><a name="model"></a>model (Model type of the device)</li>
		<ul>
			<li>FS10_ST: Switch socket</li>
			<li>FS10_DI: Socket dimmer</li>
			<li>FS10_HD: Ceiling lighting dimmer</li>
			<li>FS10_SA: Surface-mounted radio switch</li>
			<li>FS10_MS: Awning control</li>
			<li>FS10_S4: Remote control 4 buttons</li>
			<li>FS10_S8: Remote control 8 buttons</li>
		</ul>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<li>repetition (Number of repetitions of the send commands)</li>
	</ul>
</ul>

=end html

=begin html_DE

<a name="FS10"></a>
<h3>FS10</h3>
<ul>
	Das FS10-Modul entschl&uuml;sselt und sendet Nachrichten vom Typ FS10, die vom SIGNALduino verarbeitet werden.
	Unterst&uuml;tzt werden z.Z. folgende Typen: FS10-ST, FS10-DI, FS10-HD, FS10-SA, FS10-MS, FS10-S4 und FS10-S8.
	<br><br>

	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; FS10 &lt;hauscode&gt;_&lt;button&gt;</code>
		<br><br>
		<code>&lt;name&gt;</code> ist ein beliebiger Name, der dem Ger&auml;t zugewiesen wird.
		Zur besseren &Uuml;bersicht wird empfohlen einen Namen in der Form &quot; FS10_6_12&quot; zu verwenden,
		wobei &quot;6&quot; den verwendeten Hauscode und &quot;12&quot; die Adresse darstellt.
		<br><br>
		<code>&lt;hauscode&gt;</code> entspricht dem Hauscode der verwendeten Fernbedienung bzw. des Ger&auml;tes, das gesteuert werden soll. Als Hauscode wird 1-8 verwendet.
		<br><br>
		<code>&lt;button&gt;</code> stellt die Tastaturebene bzw. Adresse der verwendeten Ger&auml;te dar.
		Adresse &quot;11&quot; entspricht auf der Fernbedienung FS10-S8 z.B. den beiden Tasten der obersten Reihe.
	</ul>
	<br><br>

	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;value&gt; [&lt;anz&gt;]</code>
		<br><br>
		<code>&lt;value&gt;</code> kann einer der folgenden Werte sein:<br>
		<ul>
			<li>dimdown</li>
			<li>dimup</li>
			<li>off</li>
			<li>on</li>
		</ul>
		Bei dimup und dimdown kann optional mit &lt;anz&gt; die Anzahl der Wiederholungen im Bereich von 1 bis 9 angegeben werden.
		<br><br>
		Die <a href="#setExtensions">set extensions</a> werden unterst&uuml;tzt.
	</ul>
	<br><br>

	<b>Attribute</b>
	<ul>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#eventMap">eventMap</a></li>
		<li>follow-on-for-timer (aktivieren/deaktivieren follow-on-timer)</li>
		<li>follow-on-timer (Anzahl Sekunden nachdem beim Timer des FS10_SA der state automatisch wieder auf off geht)</li>
		<li><a href="#ignore">ignore</a></li>
		<li><a name="model"></a>model (Modelltyp des Ger&auml;tes)</li>
		<ul>
			<li>FS10_ST: Schaltsteckdose</li>
			<li>FS10_DI: Steckdosendimmer</li>
			<li>FS10_HD: Deckenbeleuchtungsdimmer</li>
			<li>FS10_SA: Aufputz-Funkschalter</li>
			<li>FS10_MS: Markisensteuerung</li>
			<li>FS10_S4: Fernbedienung 4 Tasten</li>
			<li>FS10_S8: Fernbedienung 8 Tasten</li>
		</ul>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<li>repetition (Anzahl Wiederholungen der Sendebefehle)</li>
	</ul>
</ul>

=end html_DE
=cut
