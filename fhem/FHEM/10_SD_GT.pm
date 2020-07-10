#################################################################
# $Id$
#
# The file is part of the SIGNALduino project.
#
# 2019 - HomeAuto_User & elektron-bbs
# for remote controls using protocol QUIGG Gt-9000
# based on code quigg_gt9000.c from pilight
#################################################################

package SD_GT;

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);

our $VERSION = '1.0';

# Export to main context with different name
GP_Export(qw(
	Initialize
	)
);

## Import der FHEM Funktionen
BEGIN {
	GP_Import(qw(
		AssignIoPort
		AttrVal
		attr
		defs
		DoTrigger
		IOWrite
		IsIgnored
		Log3
		modules
		ReadingsVal
		readingsBeginUpdate
		readingsBulkUpdate
		readingsEndUpdate
		readingsSingleUpdate
	))
};

sub Initialize {
	my ($hash) = @_;
	$hash->{DefFn}      = \&Define;
	$hash->{UndefFn}    = \&Undef;
	$hash->{SetFn}      = \&Set;
	$hash->{ParseFn}    = \&Parse;
	$hash->{Match}      = '^P49#[A-Fa-f0-9]+';
	$hash->{AttrList}   = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 $main::readingFnAttributes";
	$hash->{AutoCreate} = {'SD_GT_LEARN' => {FILTER => '%NAME', autocreateThreshold => '5:180', GPLOT => q{}}};
	return;
}

sub parseSystemcodeHex;
sub decodePayload;
sub checkVersion;
sub getSystemCodes;

my %buttons = (
	'1' => { # Version 1
						'hash' => [0x0, 0x9, 0xF, 0x4, 0xA, 0xD, 0x5, 0xB, 0x3, 0x2, 0x1, 0x7, 0xE, 0x6, 0xC, 0x8],
						'C' => { # unit C
											'unit' => 'A',
											'1' => 'on',
											'5' => 'on',
											'6' => 'on',
											'A' => 'on',
											'2' => 'off',
											'7' => 'off',
											'8' => 'off',
											'B' => 'off',
                    },
						'5' => { # unit 5
											'unit' => 'B',
											'0' => 'on',
											'3' => 'on',
											'E' => 'on',
											'F' => 'on',
											'4' => 'off',
											'9' => 'off',
											'C' => 'off',
											'D' => 'off',
                    },
						'E' => { # unit 5
											'unit' => 'C',
											'2' => 'on',
											'7' => 'on',
											'8' => 'on',
											'B' => 'on',
											'1' => 'off',
											'5' => 'off',
											'6' => 'off',
											'A' => 'off',
                    },
						'7' => { # unit 7
											'unit' => 'D',
											'4' => 'on',
											'9' => 'on',
											'C' => 'on',
											'D' => 'on',
											'0' => 'off',
											'3' => 'off',
											'E' => 'off',
											'F' => 'off',
                    },
						'2' => { # unit 2
											'unit' => 'all',
											'2' => 'on',
											'7' => 'on',
											'8' => 'on',
											'B' => 'on',
											'1' => 'off',
											'5' => 'off',
											'6' => 'off',
											'A' => 'off',
                    },
					},
	'2' => { # Version 2
						'hash' => [0x0, 0x9, 0x5, 0xF, 0x3, 0x6, 0xC, 0x7, 0xE, 0xD, 0x1, 0xB, 0x2, 0xA, 0x4, 0x8],
						'0' => { # unit 0
											'unit' => 'A',
											'3' => 'on',
											'4' => 'on',
											'7' => 'on',
											'B' => 'on',
											'1' => 'off',
											'2' => 'off',
											'9' => 'off',
											'A' => 'off',
                    },
						'4' => { # unit 4
											'unit' => 'B',
											'3' => 'on',
											'4' => 'on',
											'7' => 'on',
											'B' => 'on',
											'1' => 'off',
											'2' => 'off',
											'9' => 'off',
											'A' => 'off',
                   },
						'C' => { # unit C
											'unit' => 'C',
											'3' => 'on',
											'4' => 'on',
											'7' => 'on',
											'B' => 'on',
											'1' => 'off',
											'2' => 'off',
											'9' => 'off',
											'A' => 'off',
                    },
						'2' => { # unit 2
											'unit' => 'D',
											'1' => 'on',
											'2' => 'on',
											'9' => 'on',
											'A' => 'on',
											'3' => 'off',
											'4' => 'off',
											'7' => 'off',
											'B' => 'off',
                    },
						'A' => { # unit A
											'unit' => 'all',
											'1' => 'on',
											'2' => 'on',
											'9' => 'on',
											'A' => 'on',
											'3' => 'off',
											'4' => 'off',
											'7' => 'off',
											'B' => 'off',
                    },
					}
);

sub Define {
	my ($hash, $def) = @_;
	my @a = split m{\s+}xms , $def;
	my $name = $hash->{NAME};
	my $iodevice;
	my $ioname;

	if( @a < 3 ) { return 'SD_GT: wrong syntax for define, must be: define <name> SD_GT <DEF> <IODev>' };

	$hash->{DEF} = $a[2];
	if ($a[3]) { $iodevice = $a[3] }
	if ($a[4]) { readingsSingleUpdate($hash,'SystemCode',$a[4],1) }
	if ($a[5]) { readingsSingleUpdate($hash,'Version',$a[5],1) }
	$hash->{VersionModule} = $VERSION;

	$modules{SD_GT}{defptr}{$hash->{DEF}} = $hash;
	if (exists $modules{SD_GT}{defptr}{ioname} && !$iodevice) { $ioname = $modules{SD_GT}{defptr}{ioname} };
	if (not $iodevice) { $iodevice = $ioname }

	AssignIoPort($hash, $iodevice);
	return;
}

sub Set {
	my ($hash, $name, $cmd, @a) = @_;
	my $ioname = $hash->{IODev}{NAME};
	my $repeats = AttrVal($name,'repeats', '5');
	my $ret = undef;
	my $EMPTY = q{};

  if (not defined $cmd) { return "The command \"set $name\" requires at least one of the arguments: \"on\" or \"off\"" };

	if ($cmd eq q{?}) {
		if ($hash->{DEF} ne 'LEARN') {
			if (ReadingsVal($name, 'CodesOff', $EMPTY) ne $EMPTY) { $ret .= 'off:noArg ' };
			if (ReadingsVal($name, 'CodesOn', $EMPTY) ne $EMPTY) { $ret .= 'on:noArg ' };
		}
		return $ret;
	}

	my $sendCodesStr;
	my @sendCodesAr;
	my $sendCodesCnt;
	my $sendCode = ReadingsVal($name, 'SendCode', $EMPTY); # load last sendCode
	if ($cmd eq 'on') { $sendCodesStr = ReadingsVal($name, 'CodesOn', $EMPTY) };
	if ($cmd eq 'off') { $sendCodesStr = ReadingsVal($name, 'CodesOff', $EMPTY) };
	@sendCodesAr = split /[,]/xms , $sendCodesStr;
	$sendCodesCnt = scalar @sendCodesAr;
  if ($sendCodesCnt < 1) { return "$name: No codes available for sending, please press buttons on your remote for learning." };
	my ($index) = grep { $sendCodesAr[$_] eq $sendCode } (0 .. $sendCodesCnt - 1);
	if (not defined $index) { $index = -1 };
	$index++;
	if ($index >= $sendCodesCnt) { $index = 0 };
	$sendCode = $sendCodesAr[$index]; # new sendCode

	Log3 $name, 3, "$ioname: SD_GT set $name $cmd";
	Log3 $name, 4, "$ioname: SD_GT_Set $name $cmd ($sendCodesCnt codes $sendCodesStr - send $sendCode)";

	if ($hash->{DEF} =~ /_all$/xms) { # send button all
		my $systemCode = ReadingsVal($name, 'SystemCode', $EMPTY);
		foreach my $d (keys %defs) { # sucht angelegte SD_GT mit gleichem Sytemcode 
			if(defined($defs{$d}) && $defs{$d}{TYPE} eq 'SD_GT' && $defs{$d}{DEF} =~ /$systemCode/xms && $defs{$d}{DEF} =~ /[ABCD]$/xms && ReadingsVal($d, 'state', $EMPTY) ne $cmd) {
				readingsSingleUpdate($defs{$d}, 'state' , $cmd , 1);
				Log3 $name, 3, "$ioname: SD_GT set $d $cmd";
			}
		}
	}

	my $msg = 'P49#0x' . $sendCode . '#R4';
	Log3 $name, 5, "$ioname: $name SD_GT_Set first set sendMsg $msg";
	IOWrite($hash, 'sendMsg', $msg);
	$msg = 'P49.1#0x' . $sendCode . '#R4';
	Log3 $name, 5, "$ioname: $name SD_GT_Set second set sendMsg $msg";
	IOWrite($hash, 'sendMsg', $msg);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', $cmd);
	readingsBulkUpdate($hash, 'SendCode', $sendCode, 0);
	readingsEndUpdate($hash, 1);
	return $ret;
}

sub Undef {
	my ($hash, $name) = @_;
	if(defined($hash->{DEF}) && defined($modules{SD_GT}{defptr}{$hash->{DEF}})) {delete($modules{SD_GT}{defptr}{$hash->{DEF}}) };
	return;
}

sub Parse {
	my ($iohash, $msg) = @_;
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split /[#]/xms , $msg;
	my $devicedef;
	my $version = 0;
	my $systemCode = 0;
	my $level; # A, B, C, D or all
	my $state;
	my $EMPTY = q{};

	my ($systemCode1, $systemCode2) = getSystemCodes($rawData);
	Log3 $ioname, 4, "$ioname: SD_GT_Parse $rawData, possible codes version 1 $systemCode1 or version 2 $systemCode2";

	# sucht Version und SytemCode in bereits angelegten SD_GT
	foreach my $d (keys %defs) {
		if($defs{$d}{TYPE} eq 'SD_GT' && defined $defs{$d}) {
			$version = ReadingsVal($d, 'Version', 0) ;
			$systemCode = ReadingsVal($d, 'SystemCode', 0);
			Log3 $iohash, 4, "$ioname: SD_GT_Parse found $d, version $version, systemCode $systemCode";
			last if ($systemCode1 eq $systemCode && $version == 1);
			last if ($systemCode2 eq $systemCode && $version == 2);
		}
		$version = 0; # reset version
		$systemCode = 0; # reset systemCode
	}
	Log3 $ioname, 4, "$ioname: SD_GT_Parse $rawData, found version $version with systemCode $systemCode";

	if ($version == 0 && $systemCode eq '0') { # Version und systemCode nicht gefunden
		$devicedef = 'LEARN';
	} else { # Version und systemCode gefunden
		my $statecode = substr $rawData,4,1;
		my $unit = substr $rawData,5,1;
		$state = $buttons{$version}->{$unit}->{$statecode};
		$level = $buttons{$version}->{$unit}->{'unit'};
		$devicedef = $systemCode . '_' . $level;
		Log3 $ioname, 4, "$ioname: SD_GT_Parse code $rawData, device $devicedef";
	}

	my $def = $modules{SD_GT}{defptr}{$devicedef};
	$modules{SD_GT}{defptr}{ioname} = $ioname;
	if(!$def) {
		Log3 $ioname, 1, "$ioname: SD_GT_Parse UNDEFINED SD_GT_$devicedef device detected";
		return "UNDEFINED SD_GT_$devicedef SD_GT $devicedef";
	}
	my $hash = $def;
	my $name = $hash->{NAME};
	if (IsIgnored($name)) { return $EMPTY };

	my $learnCodesStr;
	my @learnCodesAr;
	my $learnCodesCnt;

	if ($devicedef eq 'LEARN') {
		$learnCodesStr = ReadingsVal($name, 'LearnCodes', $EMPTY );
		@learnCodesAr = split /[,]/xms , $learnCodesStr;
		$learnCodesCnt = scalar @learnCodesAr;
		Log3 $name, 3, "$ioname: $name $rawData, $learnCodesCnt learned codes $learnCodesStr";
		if ($learnCodesCnt == 0) { # erster Code empfangen
			push @learnCodesAr, $rawData ;
			$learnCodesCnt++;
			Log3 $name, 3, "$ioname: $name code $rawData is first plausible code";
		} elsif (grep {/$rawData/xms} @learnCodesAr) { # Code schon vorhanden
			$state = 'code already registered, please press another button';
			Log3 $name, 3, "$ioname: $name code $rawData already registered ($learnCodesStr)";
		} else { # Code pruefen und evtl. uebernehmen
			push @learnCodesAr, $rawData;
			($version, $systemCode) = checkVersion(@learnCodesAr);
			if ($version == 0) { # Fehler Version oder Systemcode
				if ($learnCodesCnt == 1) {
					@learnCodesAr = ();
					$systemCode = 0;
				} else {
					pop @learnCodesAr; # Wir entfernen das letzte Element des Arrays
				}
				$state = 'version not unique, please press another button';
				Log3 $name, 3, "$ioname: $name ERROR - version not unique";
			} else { # Version und Code OK
				$learnCodesCnt++;
				Log3 $name, 3, "$ioname: $name code $learnCodesCnt $rawData, version $version, systemCode $systemCode";
			}
		}
		if (not defined $state) { $state = "learned code $learnCodesCnt, please press another button" };
	}

	if ($state eq 'on') {
		$learnCodesStr = ReadingsVal($name, 'CodesOn', $EMPTY);
		@learnCodesAr = split /[,]/xms , $learnCodesStr;
		if (not grep {/$rawData/xms} @learnCodesAr) { push @learnCodesAr, $rawData };
	}
	if ($state eq 'off') {
		$learnCodesStr = ReadingsVal($name, 'CodesOff', $EMPTY);
		@learnCodesAr = split /[,]/xms , $learnCodesStr;
		if (not grep {/$rawData/xms} @learnCodesAr) { push @learnCodesAr, $rawData };
	}

	if (defined $level) { Log3 $name, 4, "$ioname: SD_GT_Parse code $rawData, $name, button $level $state" };

	if (defined $level && $level eq 'all') { # received button all
		foreach my $d (keys %defs) { # sucht angelegte SD_GT mit gleichem Sytemcode 
			if(defined($defs{$d}) && $defs{$d}{TYPE} eq 'SD_GT' && $defs{$d}{DEF} =~ /$systemCode/xms && $defs{$d}{DEF} =~ /[ABCD]$/xms && ReadingsVal($d, 'state', $EMPTY) ne $state) {
				readingsSingleUpdate($defs{$d}, 'state' , $state , 1);
				DoTrigger($d, undef, 0);
				Log3 $name, 4, "$ioname: SD_GT_Parse received button $level, set $d $state";
			}
		}
	}

	$learnCodesStr = join q{,} , @learnCodesAr;
	my $systemCodeDec = hex $systemCode;

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', $state);
	if ($devicedef eq 'LEARN') { readingsBulkUpdate($hash, 'LearnCodes', $learnCodesStr) };
	if ($state eq 'on') { readingsBulkUpdate($hash, 'CodesOn', $learnCodesStr, 0) };
	if ($state eq 'off') { readingsBulkUpdate($hash, 'CodesOff', $learnCodesStr, 0) };
	if ($devicedef ne 'LEARN' || $learnCodesCnt > 5) {
		if ($version != 0) { readingsBulkUpdate($hash, 'Version', $version, 0) };
		if ($systemCode ne '0') { readingsBulkUpdate($hash, 'SystemCode', $systemCode, 0) };
		if ($systemCodeDec != 0) { readingsBulkUpdate($hash, 'SystemCodeDec', $systemCodeDec, 0) };
	}
	readingsEndUpdate($hash, 1);
	return $name;
}

sub parseSystemcodeHex {
	my $rawData = shift;
	my $version = shift;
	my $systemCode1dec = hex substr $rawData,0,1;
	my $systemCode2enc = hex substr $rawData,1,1;
	my $systemCode2dec = 0; # calculate all codes with base syscode2 = 0
	my $systemCode3enc = hex substr $rawData,2,1;
	my $systemCode3dec = decodePayload($systemCode3enc, $systemCode2enc, $systemCode1dec, $version);
	my $systemCode4enc = hex substr $rawData,3,1;
	my $systemCode4dec = decodePayload($systemCode4enc, $systemCode3enc, $systemCode1dec, $version);
	my $systemCode5enc = hex substr $rawData,4,1;
	my $systemCode5dec = decodePayload($systemCode5enc, $systemCode4enc, $systemCode1dec, $version);
	my $systemCode = ($systemCode1dec<<16) + ($systemCode2dec<<12) + ($systemCode3dec<<8) + ($systemCode4dec<<4) + $systemCode5dec;
	my $systemCodeHex = sprintf '%X', $systemCode;
	return $systemCodeHex;
}

sub checkVersion {
	my (@rawData) = @_;
	my $anzahl = scalar @rawData;
	my $x = 0;
	my @codes;
	my $systemCode = q{};
	my $version = 1;
	while ($x < $anzahl) {
		$systemCode = parseSystemcodeHex($rawData[$x], $version);
		if ( not grep {/$systemCode/xms} @codes) {
			push @codes, $systemCode;
		}
		$x++;
	}
	$anzahl = scalar @codes;
	$x = 0;
	if ($anzahl > 1) {
		$version = 2;
		@codes =();
		while ($x < $anzahl) {
			$systemCode = parseSystemcodeHex($rawData[$x], $version);
			if ( not grep {/$systemCode/xms} @codes) {
				push @codes, $systemCode;
			}
			$x++;
		}
		$anzahl = scalar @codes;
	}
	if ($anzahl > 1) { # keine eindeutige Version erkannt
		$version = 0;
		$systemCode = 0;
	}
	return ($version, $systemCode);
}

sub decodePayload {
	my $payload = shift;
	my $index = shift;
	my $syscodetype = shift;
	my $version = shift;
	my $ret = -1;
	if ($version >= 1) {
		my @gt9000_hash = @{ $buttons{$version}->{'hash'} };
		$ret = int($payload) ^ int($gt9000_hash[$index]);
	}
	return $ret;
}

sub getSystemCodes {
	my ($rawData) = shift;
	my $systemCode1 = parseSystemcodeHex($rawData, 1);
	my $systemCode2 = parseSystemcodeHex($rawData, 2);
	return ($systemCode1, $systemCode2);
}

1;

=pod
=item device
=item summary Processing of messages from remote controls
=item summary_DE Verarbeitung der Nachrichten von Fernbedienungen

=begin html

<a name="SD_GT"></a>
<h3>SD_GT</h3>
<ul>
	The SD_GT module decodes and sends messages using the GT-9000 protocol.
	This protocol is used by a variety of remote controls, which are traded under different names.
	The messages are received and sent by a SIGNALduino.
	<br><br>
	The following models are currently known that use this protocol:
	<br><br>
	<ul>
		<li>EASY HOME RCT DS1 CR-A 3725</li>
		<li>Globaltronics GT-3000, GT-9000</li>
		<li>OBI Emil Lux / CMI Art.Nr.: 315606</li>
		<li>SilverCrest FSS B 20-A (3726) / 66538</li>
		<li>Tec Star Modell 2335191R</li>
		<li>uniTEC 48110 Funkfernschalterset (Receiver 55006x10, Transmitter: 50074)</li>
	</ul>
	<br>
	New devices are usually automatically created in FHEM via autocreate.
	Since the protocol uses encryption, manual setup is virtually impossible.
	<br><br>
	The remote control is set up in a learning process.
	After receiving at least 5 messages within 3 minutes, a new device "SD_GT_LEARN" will be created.
	Setting up the individual buttons of the remote control starts after receiving another 6 different messages.
	This learning process is signaled with the status "learned code 4, please press another button", whereby the counter displays the number of currently registered codes.
	<br>
	All buttons of the remote control must now be pressed several times.
	Upon successful decoding of the radio signals, the individual keys are created.
	<br><br>
	The programming of the remote control is finished, if all key levels (A, B, C, D and possibly all) are created and the commands "on" and "off" are displayed.
	For each device, the Readings "CodesOn" and "CodesOff" must be set up with at least one code each.
	Without these learned codes no sending is possible.
	<br>
	The device "SD_GT_LEARN" is no longer needed and can be deleted.
	<br><br>
	If several remote controls are to be taught in, this process must be carried out separately for each remote control.
	The "SD_GT_LEARN" device must be deleted before starting to learn a new remote control.
	<br><br>
	<p><strong>Readings:</strong></p>
	<ul>
		<li>CodesOff: one to four hexadecimal codes for "off" that have been taught and used for sending</li>
		<li>CodesOn: one to four hexadecimal codes for "on" that have been learned and used for sending</li>
		<li>SendCode: the last sent code</li>
		<li>SystemCode: System code hexadecimal, the same for all buttons on a remote control</li>
		<li>SystemCodeDec: System code in decimal representation</li>
		<li>Version: Version of the encryption used</li>
		<li>state: State, "on" or "off"</li>
	</ul>
</ul>

=end html

=begin html_DE

<a name="SD_GT"></a>
<h3>SD_GT</h3>
<ul>
	Das SD_GT-Modul dekodiert und sendet Nachrichten unter Verwendung des Protokolls vom Typ GT-9000.
	Dieses Protokoll wird von einer Vielzahl Fernbedienungen verwendet, die unter verschiedene Namen gehandelt werden.
	Die Nachrichten werden von einem SIGNALduino empfangen und gesendet.
	<br><br>
	Folgende Modelle sind zur Zeit bekannt, die dieses Protokoll verwenden:
	<br><br>
	<ul>
		<li>EASY HOME RCT DS1 CR-A 3725</li>
		<li>Globaltronics GT-3000, GT-9000</li>
		<li>OBI Emil Lux / CMI Art.Nr.: 315606</li>
		<li>SilverCrest FSS B 20-A (3726) / 66538</li>
		<li>Tec Star Modell 2335191R</li>
		<li>uniTEC 48110 Funkfernschalterset (Receiver 55006x10, Transmitter: 50074)</li>
	</ul>
	<br>
	Neue Ger&auml;te werden in FHEM normalerweise per autocreate automatisch angelegt.
	Da das Protokoll eine Verschl&uuml;sselung nutzt, ist ein manuelles Einrichten praktisch nicht m&ouml;glich.
	<br><br>
	Das Einrichten der Fernbedienung erfolgt in einem Lernprozess.
	Nach dem Empfang von mindestens 5 Nachrichten innerhalb von 3 Minuten wird ein neues Ger&auml;t "SD_GT_LEARN" angelegt.
	Das Einrichten der einzelnen Tasten der Fernbedienung beginnt nach dem Empfang weiterer 6 verschiedener Nachrichten.
	Dieser Lernprozess wird mit dem Status "learned code 4, please press another button" signalisiert, wobei der Z&auml;hler die Anzahl der aktuell registrierten Codes anzeigt.
	<br>
	Es m&uuml;ssen jetzt s&auml;mtliche Tasten der Fernbedienung mehrmals bet&auml;tigt werden.
	Bei erfolgreicher Dekodierung der Funksignale werden dabei die einzelnen Tasten angelegt.
	<br><br>
	Das Anlernen der Fernbedienung ist beendet, wenn alle Tastenebenen (A, B, C, D und evtl. all) angelegt sind und jeweils die Befehle "on" und "off" angezeigt werden.
	Bei jedem Ger&auml;t m&uuml;ssen die Readings "CodesOn" und "CodesOff" mit jeweils mindestens einem Code eingerichtet sein.
	Ohne diese gelernten Codes ist kein Senden m&ouml;glich.
	<br>
	Das Ger&auml;t "SD_GT_LEARN" wird jetzt nicht mehr ben&ouml;tigt und kann gel&ouml;scht werden.
	<br><br>
	Sollen mehrere Fernbedienungen angelernt werden, muss dieser Prozess für jede Fernbedienung getrennt durchgef&uuml;hrt werden.
	Das Gerät "SD_GT_LEARN" muss jeweils vor Beginn des Anlernens einer neuen Fernbedienung gel&ouml;scht werden.
	<br><br>
	<p><strong>Readings:</strong></p>
	<ul>
		<li>CodesOff: ein bis vier hexadezimale Codes f&uuml;r "off", die angelernt wurden und zum Senden verwendet werden</li>
		<li>CodesOn: ein bis vier hexadezimale Codes f&uuml;r "on", die angelernt wurden und zum Senden verwendet werden</li>
		<li>SendCode: der zuletzt gesendete Code</li>
		<li>SystemCode: Systemcode hexadezimal, bei allen Tasten einer Fernbedienung gleich</li>
		<li>SystemCodeDec: Systemcode in dezimaler Darstellng</li>
		<li>Version: Version der verwendeten Verschl&uuml;sselung</li>
		<li>state: Zustand, "on" oder "off"</li>
	</ul>
</ul>

=end html_DE

=cut
