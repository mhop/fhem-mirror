##############################################
# $Id$
#
# HMUARTLGW provides support for the eQ-3 HomeMatic Wireless LAN Gateway
# (HM-LGW-O-TW-W-EU) and the eQ-3 HomeMatic UART module (HM-MOD-UART), which
# is part of the HomeMatic wireless module for the Raspberry Pi
# (HM-MOD-RPI-PCB).
#
# TODO:
# - Filter out "A112" from CUL_HM and synthesize response

package main;

use strict;
use warnings;

use Digest::MD5;
use Time::HiRes qw(gettimeofday time);
use Time::Local;
eval "use Crypt::Rijndael";
my $cryptFunc = ($@)?0:1;

use constant {
	HMUARTLGW_OS_GET_APP               => "00",
	HMUARTLGW_OS_GET_FIRMWARE          => "02",
	HMUARTLGW_OS_CHANGE_APP            => "03",
	HMUARTLGW_OS_ACK                   => "04",
	HMUARTLGW_OS_UPDATE_FIRMWARE       => "05",
	HMUARTLGW_OS_UNSOL_CREDITS         => "05",
	HMUARTLGW_OS_NORMAL_MODE           => "06",
	HMUARTLGW_OS_UPDATE_MODE           => "07",
	HMUARTLGW_OS_GET_CREDITS           => "08",
	HMUARTLGW_OS_ENABLE_CREDITS        => "09",
	HMUARTLGW_OS_ENABLE_CSMACA         => "0A",
	HMUARTLGW_OS_GET_SERIAL            => "0B",
	HMUARTLGW_OS_SET_TIME              => "0E",

	HMUARTLGW_APP_SET_HMID             => "00",
	HMUARTLGW_APP_GET_HMID             => "01",
	HMUARTLGW_APP_SEND                 => "02",
	HMUARTLGW_APP_SET_CURRENT_KEY      => "03", #key index, 00x17 when no key
	HMUARTLGW_APP_ACK                  => "04",
	HMUARTLGW_APP_RECV                 => "05",
	HMUARTLGW_APP_ADD_PEER             => "06",
	HMUARTLGW_APP_REMOVE_PEER          => "07",
	HMUARTLGW_APP_GET_PEERS            => "08",
	HMUARTLGW_APP_PEER_ADD_AES         => "09",
	HMUARTLGW_APP_PEER_REMOVE_AES      => "0A",
	HMUARTLGW_APP_SET_TEMP_KEY         => "0B", #key index, 00x17 when no key
	HMUARTLGW_APP_SET_PREVIOUS_KEY     => "0F", #key index, 00x17 when no key
	HMUARTLGW_APP_DEFAULT_HMID         => "10",

	HMUARTLGW_DUAL_GET_APP             => "01",
	HMUARTLGW_DUAL_CHANGE_APP          => "02",

	HMUARTLGW_ACK_NACK                 => "00",
	HMUARTLGW_ACK                      => "01",
	HMUARTLGW_ACK_INFO                 => "02",
	HMUARTLGW_ACK_WITH_RESPONSE        => "03",
	HMUARTLGW_ACK_EUNKNOWN             => "04",
	HMUARTLGW_ACK_ENOCREDITS           => "05",
	HMUARTLGW_ACK_ECSMACA              => "06",
	HMUARTLGW_ACK_WITH_MULTIPART_DATA  => "07", #04 07 XX YY: part XX of YY
	HMUARTLGW_ACK_EINPROGRESS          => "08",
	HMUARTLGW_ACK_WITH_RESPONSE_AES_OK => "0C",
	HMUARTLGW_ACK_WITH_RESPONSE_AES_KO => "0D",
	HMUARTLGW_RECV_RESP                => "01",
	HMUARTLGW_RECV_RESP_WITH_AES_OK    => "02",
	HMUARTLGW_RECV_RESP_WITH_AES_KO    => "03",
	HMUARTLGW_RECV_TRIG                => "11",
	HMUARTLGW_RECV_TRIG_WITH_AES_OK    => "12",

	HMUARTLGW_DST_OS                   => 0,
	HMUARTLGW_DST_APP                  => 1,
	HMUARTLGW_DST_DUAL                 => 254,
	HMUARTLGW_DST_DUAL_ERR             => 255,

	HMUARTLGW_STATE_NONE               => 0,
	HMUARTLGW_STATE_QUERY_APP          => 1,
	HMUARTLGW_STATE_ENTER_APP          => 2,
	HMUARTLGW_STATE_GETSET_PARAMETERS  => 3,
	HMUARTLGW_STATE_SET_HMID           => 4,
	HMUARTLGW_STATE_GET_HMID           => 5,
	HMUARTLGW_STATE_GET_DEFAULT_HMID   => 6,
	HMUARTLGW_STATE_SET_TIME           => 7,
	HMUARTLGW_STATE_GET_FIRMWARE       => 8,
	HMUARTLGW_STATE_GET_SERIAL         => 9,
	HMUARTLGW_STATE_SET_NORMAL_MODE    => 10,
	HMUARTLGW_STATE_ENABLE_CSMACA      => 11,
	HMUARTLGW_STATE_ENABLE_CREDITS     => 12,
	HMUARTLGW_STATE_GET_INIT_CREDITS   => 13,
	HMUARTLGW_STATE_SET_CURRENT_KEY    => 14,
	HMUARTLGW_STATE_SET_PREVIOUS_KEY   => 15,
	HMUARTLGW_STATE_SET_TEMP_KEY       => 16,
	HMUARTLGW_STATE_UPDATE_PEER        => 90,
	HMUARTLGW_STATE_UPDATE_PEER_AES1   => 91,
	HMUARTLGW_STATE_UPDATE_PEER_AES2   => 92,
	HMUARTLGW_STATE_UPDATE_PEER_CFG    => 93,
	HMUARTLGW_STATE_SET_UPDATE_MODE    => 95,
	HMUARTLGW_STATE_KEEPALIVE_INIT     => 96,
	HMUARTLGW_STATE_KEEPALIVE_SENT     => 97,
	HMUARTLGW_STATE_GET_CREDITS        => 98,
	HMUARTLGW_STATE_RUNNING            => 99,
	HMUARTLGW_STATE_SEND               => 100,
	HMUARTLGW_STATE_SEND_NOACK         => 101,
	HMUARTLGW_STATE_SEND_TIMED         => 102,
	HMUARTLGW_STATE_UPDATE_COPRO       => 200,
	HMUARTLGW_STATE_UNSUPPORTED_FW     => 999,

	HMUARTLGW_CMD_TIMEOUT              => 3,
	HMUARTLGW_CMD_RETRY_CNT            => 3,
	HMUARTLGW_FIRMWARE_TIMEOUT         => 10,
	HMUARTLGW_SEND_TIMEOUT             => 10,
	HMUARTLGW_SEND_RETRY_SECONDS       => 3,
	HMUARTLGW_BUSY_RETRY_MS            => 50,
	HMUARTLGW_CSMACA_RETRY_MS          => 200,
	HMUARTLGW_KEEPALIVE_SECONDS        => 10,
	HMUARTLGW_KEEPALIVE_WARN_LATE_S    => 4,
};

my %sets = (
	"hmPairForSec" => "",
	"hmPairSerial" => "",
	"reopen"       => "noArg",
	"open"         => "noArg",
	"close"        => "noArg",
	"restart"      => "noArg",
	"updateCoPro"  => "",
);

my %gets = (
	"assignIDs"    => "noArg",
);

sub HMUARTLGW_Initialize($)
{
	my ($hash) = @_;

	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	$hash->{ReadyFn}   = "HMUARTLGW_Ready";
	$hash->{ReadFn}    = "HMUARTLGW_Read";
	$hash->{WriteFn}   = "HMUARTLGW_Write";
	$hash->{DefFn}     = "HMUARTLGW_Define";
	$hash->{UndefFn}   = "HMUARTLGW_Undefine";
	$hash->{SetFn}     = "HMUARTLGW_Set";
	$hash->{GetFn}     = "HMUARTLGW_Get";
	$hash->{AttrFn}    = "HMUARTLGW_Attr";
	$hash->{RenameFn}  = "HMUARTLGW_Rename";
	$hash->{ShutdownFn}= "HMUARTLGW_Shutdown";

	$hash->{AttrList}= "hmId " .
	                   "lgwPw " .
	                   "hmKey hmKey2 hmKey3 " .
	                   "dutyCycle:1,0 " .
	                   "csmaCa:0,1 " .
	                   "qLen " .
	                   "logIDs ".
	                   "dummy:1 ".
	                   "loadEvents:0,1 ".
	                   $readingFnAttributes;
}

sub HMUARTLGW_Connect($$);
sub HMUARTLGW_SendPendingCmd($);
sub HMUARTLGW_SendCmd($$);
sub HMUARTLGW_GetSetParameterReq($);
sub HMUARTLGW_getAesKeys($);
sub HMUARTLGW_updateMsgLoad($$);
sub HMUARTLGW_Read($);
sub HMUARTLGW_RemoveHMPair($);
sub HMUARTLGW_send($$$;$);
sub HMUARTLGW_send_frame($$);
sub HMUARTLGW_crc16($;$);
sub HMUARTLGW_encrypt($$);
sub HMUARTLGW_decrypt($$);
sub HMUARTLGW_getVerbLvl($$$$);
sub HMUARTLGW_firmwareGetBlock($$$);
sub HMUARTLGW_updateCoPro($$);

sub HMUARTLGW_DoInit($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{CNT} = 0x00;
	delete($hash->{DEVCNT});
	delete($hash->{'.crypto'});
	delete($hash->{keepAlive});
	delete($hash->{Helper});
	delete($hash->{AssignedPeerCnt});
	delete($hash->{msgLoadCurrent});
	delete($hash->{msgLoadHistory});
	delete($hash->{msgLoadHistoryAbs});
	delete($hash->{owner});
	$hash->{DevState} = HMUARTLGW_STATE_NONE;
	$hash->{XmitOpen} = 0;
	$hash->{LastOpen} = gettimeofday();

	$hash->{LGW_Init} = 1 if ($hash->{DevType} =~ m/^LGW/);

	$hash->{Helper}{Log}{IDs} = [ split(/,/, AttrVal($name, "logIDs", "")) ];
	$hash->{Helper}{Log}{Resolve} = 1;

	RemoveInternalTimer($hash);

	if ($hash->{DevType} eq "LGW") {
		my $keepAlive = {
			NR => $devcount++,
			NAME => "${name}:keepAlive",
			STATE => "uninitialized",
			TYPE => $hash->{TYPE},
			TEMPORARY => 1,
			directReadFn => \&HMUARTLGW_Read,
			DevType => "LGW-KeepAlive",
			'.lgwHash' => $hash,
		};

		$attr{$keepAlive->{NAME}}{room} = "hidden";
		$attr{$keepAlive->{NAME}}{verbose} = AttrVal($name, "verbose", undef);
		$defs{$keepAlive->{NAME}} = $keepAlive;

		DevIo_CloseDev($keepAlive);
		my ($ip, $port) = split(/:/, $hash->{DeviceName});
		$keepAlive->{DeviceName} = "${ip}:" . ($port + 1);
		DevIo_OpenDev($keepAlive, 0, "HMUARTLGW_DoInit", \&HMUARTLGW_Connect);
		$hash->{keepAlive} = $keepAlive;
	}

	InternalTimer(gettimeofday()+1, "HMUARTLGW_StartInit", $hash, 0);

	return;
}

sub HMUARTLGW_Connect($$)
{
	my ($hash, $err) = @_;

	Log3($hash, 5, "HMUARTLGW $hash->{NAME}: ${err}") if ($err);
}

sub HMUARTLGW_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	if (@a != 3) {
		return "wrong syntax: define <name> HMUARTLGW /path/to/port|hostname";
	}

	my $name = $a[0];
	my $dev = $a[2];

	HMUARTLGW_Undefine($hash, $name);

	if ($dev !~ m/\//) {
		$dev .= ":2000" if ($dev !~ m/:/);
		$hash->{DevType} = "LGW";
	} else {
		if ($dev =~ m/^uart:\/\/(.*)$/) {
			$dev = $1;
		} elsif ($dev !~ m/\@/) {
			$dev .= "\@115200";
		}
		$hash->{DevType} = "UART";
		$hash->{model} = "HM-MOD-UART";
		readingsBeginUpdate($hash);
		delete($hash->{READINGS}{"D-LANfirmware"});
		readingsBulkUpdate($hash, "D-type", $hash->{model});
		readingsEndUpdate($hash, 1);
	}

	$hash->{DeviceName} = $dev;

	$hash->{Clients} = ":CUL_HM:";
	my %ml = ( "1:CUL_HM" => "^A......................" );
	$hash->{MatchList} = \%ml;

	if (defined(AttrVal($name, "dummy", undef))) {
		readingsSingleUpdate($hash, "state", "dummy", 1);
		HMUARTLGW_updateCondition($hash);
		return;
	}

	return DevIo_OpenDev($hash, 0, "HMUARTLGW_DoInit", \&HMUARTLGW_Connect);
}

sub HMUARTLGW_Undefine($$;$)
{
	my ($hash, $name, $noclose) = @_;

	RemoveInternalTimer($hash);
	RemoveInternalTimer("HMUARTLGW_CheckCredits:$name");
	RemoveInternalTimer("hmPairForSec:$name");
	if ($hash->{keepAlive}) {
		RemoveInternalTimer($hash->{keepAlive});
		DevIo_CloseDev($hash->{keepAlive});
		delete($attr{$hash->{keepAlive}->{NAME}});
		delete($defs{$hash->{keepAlive}->{NAME}});
		delete($hash->{keepAlive});
	}

	if (!$noclose) {
		DevIo_CloseDev($hash);
		Log3($hash, 3, "${name} device closed") if (!defined($hash->{FD}));
	}
	$hash->{DevState} = HMUARTLGW_STATE_NONE;
	$hash->{XmitOpen} = 0;
	HMUARTLGW_updateCondition($hash);
}

sub HMUARTLGW_Reopen($;$)
{
	my ($hash, $noclose) = @_;
	$hash = $hash->{'.lgwHash'} if ($hash->{'.lgwHash'});
	my $name = $hash->{NAME};

	Log3($hash, 4, "HMUARTLGW ${name} Reopen");

	HMUARTLGW_Undefine($hash, $name, $noclose);

	return DevIo_OpenDev($hash, 1, "HMUARTLGW_DoInit", \&HMUARTLGW_Connect);
}

sub HMUARTLGW_Ready($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $state = ReadingsVal($name, "state", "unknown");

	Log3($hash, 4, "HMUARTLGW ${name} ready: ${state}");

	if ((!$hash->{'.lgwHash'}) && $state eq "disconnected") {
		#don't immediately reconnect when we just connected, delay
		#for 5s because remote closed the connection on us
		if (defined($hash->{LastOpen}) &&
		    $hash->{LastOpen} + 5 >= gettimeofday()) {
			return 0;
		}
		return HMUARTLGW_Reopen($hash, 1);
	}

	return 0;
}

sub HMUARTLGW_Rename($$)
{
	my ($name, $old_name) = @_;
	my $hash = $defs{$name};

	if (defined($hash->{Helper}{Initialized})) {
		RemoveInternalTimer("HMUARTLGW_CheckCredits:${old_name}");
		InternalTimer(gettimeofday()+1, "HMUARTLGW_CheckCredits", "HMUARTLGW_CheckCredits:${name}", 0);
	}

	if ($hash->{hmPair}) {
		HMUARTLGW_RemoveHMPair("hmPairForSec:${old_name}");
	}
}

sub HMUARTLGW_Shutdown($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	#switch to bootloader to stop the module from interfering
	HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS)
		if ($hash->{DevState} > HMUARTLGW_STATE_ENTER_APP);

	DevIo_CloseDev($hash->{keepAlive}) if ($hash->{keepAlive});
	DevIo_CloseDev($hash);

	return undef;
}

#HM-LGW communicates line-based during init
sub HMUARTLGW_LGW_Init($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $p = pack("H*", $hash->{PARTIAL});

	while($p =~ m/\n/) {
		(my $line, $p) = split(/\n/, $p, 2);
		$line =~ s/\r$//;
		Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5), "HMUARTLGW ${name} read (".length($line)."): ${line}");

		my $msg;

		if ($line =~ m/^H(..),01,([^,]*),([^,]*),([^,]*)$/) {
			$hash->{DEVCNT} = hex($1);
			$hash->{CNT} = hex($1);

			if ($hash->{DevType} eq "LGW") {
				$hash->{model} = $2;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "D-type", $2);
				readingsBulkUpdate($hash, "D-serialNr", $4);
				my $fw = $3;
				if ($fw =~ m/^(\d+)\.(\d+)\.(\d+)$/) {
					my $fwver = (int($1) << 16) | (int($2) << 8) | int($3);
					$fw .= " (outdated)" if ($fwver < 0x010105);
				}
				readingsBulkUpdate($hash, "D-LANfirmware", $fw);
				readingsEndUpdate($hash, 1);
			}
		} elsif ($line =~ m/^V(..),(................................)$/) {
			$hash->{DEVCNT} = hex($1);
			$hash->{CNT} = hex($1);

			my $lgwName = $name;
			$lgwName = $hash->{'.lgwHash'}->{NAME} if ($hash->{'.lgwHash'});

			my $lgwPw = AttrVal($lgwName, "lgwPw", undef);

			if (!$cryptFunc) {
				Log3($hash, 1, "HMUARTLGW ${name} wants to initiate encrypted communication, but Crypt::Rijndael is not installed.");
			} elsif (!$lgwPw) {
				Log3($hash, 1, "HMUARTLGW ${name} wants to initiate encrypted communication, but no lgwPw set!");
			} else {
				my($s,$us) = gettimeofday();
				my $myiv = sprintf("%08x%06x%s", ($s & 0xffffffff), ($us & 0xffffff), scalar(reverse(substr($2, 14)))); #FIXME...
				my $key = Digest::MD5::md5($lgwPw);
				$hash->{'.crypto'}{cipher} = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_ECB());
				$hash->{'.crypto'}{encrypt}{keystream} = '';
				$hash->{'.crypto'}{encrypt}{ciphertext} = pack("H*", $2);
				$hash->{'.crypto'}{decrypt}{keystream} = '';
				$hash->{'.crypto'}{decrypt}{ciphertext} = pack("H*", $myiv);

				$msg = "V%02x,${myiv}\r\n";
			}
		} elsif ($line =~ m/^S(..),([^-]*)-/) {
			$hash->{DEVCNT} = hex($1);
			$hash->{CNT} = hex($1);

			if ($2 eq "BidCoS") {
				Log3($hash, 3, "HMUARTLGW ${name} BidCoS-port opened");
			} elsif ($2 eq "SysCom") {
				Log3($hash, 3, "HMUARTLGW ${name} KeepAlive-port opened");
			} else {
				Log3($hash, 1, "HMUARTLGW ${name} Unknown port identification received: ${2}, reopening");
				HMUARTLGW_Reopen($hash);

				return;
			}

			$msg = ">%02x,0000\r\n";
			delete($hash->{LGW_Init});
		}

		HMUARTLGW_sendAscii($hash, $msg) if ($msg);
	}

	$hash->{PARTIAL} = unpack("H*", $p);
}

#LGW KeepAlive
sub HMUARTLGW_LGW_HandleKeepAlive($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $p = pack("H*", $hash->{PARTIAL});

	while($p =~ m/\n/) {
		(my $line, $p) = split(/\n/, $p, 2);
		$line =~ s/\r$//;
		Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5), "HMUARTLGW ${name} read (".length($line)."): ${line}");

		my $msg;

		if ($line =~ m/^>L(..)/) {
			$hash->{DEVCNT} = hex($1);
			RemoveInternalTimer($hash);
			$hash->{DevState} = HMUARTLGW_STATE_KEEPALIVE_SENT;

			$msg = "K%02x\r\n";

			InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
		} elsif ($line =~ m/^>K(..)/) {
			$hash->{DEVCNT} = hex($1);
			RemoveInternalTimer($hash);
			$hash->{DevState} = HMUARTLGW_STATE_RUNNING;

			#now we have 15s
			$hash->{Helper}{NextKeepAlive} = gettimeofday() + HMUARTLGW_KEEPALIVE_SECONDS;
			InternalTimer($hash->{Helper}{NextKeepAlive}, "HMUARTLGW_SendKeepAlive", $hash, 0);
		}

		HMUARTLGW_sendAscii($hash, $msg) if ($msg);
	}

	$hash->{PARTIAL} = unpack("H*", $p);

	return;
}

sub HMUARTLGW_SendKeepAlive($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	$hash->{DevState} = HMUARTLGW_STATE_KEEPALIVE_SENT;
	HMUARTLGW_sendAscii($hash, "K%02x\r\n");

	my $diff = gettimeofday() - $hash->{Helper}{NextKeepAlive};
	Log3($hash, 1, "HMUARTLGW ${name} KeepAlive sent " .
		sprintf("%.3f", $diff) .
		"s too late, this might cause a disconnect!")
			if ($diff > HMUARTLGW_KEEPALIVE_WARN_LATE_S);

	InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);

	return;
}

sub HMUARTLGW_CheckCredits($)
{
	my ($in) = shift;
	my (undef, $name) = split(':',$in);
	my $hash = $defs{$name};

	my $next = 15;

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING) {
		Log3($hash, 5, "HMUARTLGW ${name} checking credits (from timer)");
		$hash->{Helper}{OneParameterOnly} = 1;
		if (++$hash->{Helper}{CreditTimer} % (4*60*2)) { #about every 2h
			$hash->{DevState} = HMUARTLGW_STATE_GET_CREDITS;
		} else {
			$hash->{DevState} = HMUARTLGW_STATE_SET_TIME;
			$next = 1;
		}
		HMUARTLGW_GetSetParameterReq($hash);
	} else {
		$next = 1;
	}
	RemoveInternalTimer("HMUARTLGW_CheckCredits:$name");
	InternalTimer(gettimeofday()+$next, "HMUARTLGW_CheckCredits", "HMUARTLGW_CheckCredits:$name", 0);
}

sub HMUARTLGW_SendPendingCmd($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (defined($hash->{XmitOpen}) &&
	    $hash->{XmitOpen} == 2) {
		if ($hash->{Helper}{PendingCMD}) {
			my $qLen = AttrVal($name, "qLen", 60);
			if (scalar(@{$hash->{Helper}{PendingCMD}}) < $qLen) {
				$hash->{XmitOpen} = 1;
			}
		} else {
			$hash->{XmitOpen} = 1;
		}
	}

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING &&
	    defined($hash->{Helper}{PendingCMD}) &&
	    @{$hash->{Helper}{PendingCMD}}) {
		my $cmd = $hash->{Helper}{PendingCMD}->[0];

		if ($cmd->{cmd} eq "AESkeys") {
			Log3($hash, 5, "HMUARTLGW ${name} setting keys");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_SET_CURRENT_KEY;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "Credits") {
			Log3($hash, 5, "HMUARTLGW ${name} checking credits (from send)");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_GET_CREDITS;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "HMID") {
			Log3($hash, 5, "HMUARTLGW ${name} setting hmId");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_SET_HMID;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "DutyCycle") {
			Log3($hash, 5, "HMUARTLGW ${name} Enabling/Disabling DutyCycle");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_ENABLE_CREDITS;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "CSMACA") {
			Log3($hash, 5, "HMUARTLGW ${name} Enabling/Disabling CSMA/CA");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_ENABLE_CSMACA;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "UpdateMode") {
			Log3($hash, 5, "HMUARTLGW ${name} Entering HM update mode (100k)");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_SET_UPDATE_MODE;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} elsif ($cmd->{cmd} eq "NormalMode") {
			Log3($hash, 5, "HMUARTLGW ${name} Entering HM normal mode (10k)");
			$hash->{Helper}{OneParameterOnly} = 1;
			$hash->{DevState} = HMUARTLGW_STATE_SET_NORMAL_MODE;
			HMUARTLGW_GetSetParameterReq($hash);
			shift(@{$hash->{Helper}{PendingCMD}}); #retry will be handled by GetSetParameter
		} else {
			#try for HMUARTLGW_SEND_RETRY_SECONDS, packet was not sent wirelessly yet!
			if (defined($cmd->{RetryStart}) &&
			    $cmd->{RetryStart} + HMUARTLGW_SEND_RETRY_SECONDS <= gettimeofday()) {
				my $oldmsg = shift(@{$hash->{Helper}{PendingCMD}});
				Log3($hash, 1, "HMUARTLGW ${name} resend failed too often, dropping packet: 01 $oldmsg->{cmd}");
				#try next command
				return HMUARTLGW_SendPendingCmd($hash);
			} elsif ($cmd->{RetryStart}) {
				Log3($hash, 5, "HMUARTLGW ${name} Retry, initial retry initiated at: ".$cmd->{RetryStart});
			}

			RemoveInternalTimer($hash);

			my $dst = substr($cmd->{cmd}, 20, 6);
			if ((!defined($cmd->{delayed})) &&
			    $modules{CUL_HM}{defptr}{$dst}{helper}{io}{nextSend}){
				my $tn = gettimeofday();
				my $dDly = $modules{CUL_HM}{defptr}{$dst}{helper}{io}{nextSend} - $tn;
				#$dDly -= 0.05 if ($typ eq "02");# delay at least 50ms for ACK, but not 100
				if ($dDly > 0.01) {
					Log3($hash, 5, "HMUARTLGW ${name} delaying send to ${dst} for ${dDly}");
					$hash->{DevState} = HMUARTLGW_STATE_SEND_TIMED;
					InternalTimer($tn + $dDly, "HMUARTLGW_SendPendingTimer", $hash, 0);
					$cmd->{delayed} = 1;
					return;
				}
			}

			delete($cmd->{delayed}) if (defined($cmd->{delayed}));

			if (hex(substr($cmd->{cmd}, 10, 2)) & (1 << 5)) { #BIDI
				InternalTimer(gettimeofday()+HMUARTLGW_SEND_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
				$hash->{DevState} = HMUARTLGW_STATE_SEND;
			} else {
				Log3($hash, 5, "HMUARTLGW ${name} !BIDI");
				InternalTimer(gettimeofday()+0.3, "HMUARTLGW_CheckCmdResp", $hash, 0);
				$hash->{DevState} = HMUARTLGW_STATE_SEND_NOACK;
			}

			$cmd->{CNT} = HMUARTLGW_send($hash, $cmd->{cmd}, HMUARTLGW_DST_APP);
		}
	}
}

sub HMUARTLGW_SendPendingTimer($)
{
	my ($hash) = @_;

	$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
	return HMUARTLGW_SendPendingCmd($hash);
}

sub HMUARTLGW_SendCmd($$)
{
	my ($hash, $cmd) = @_;

	#Drop commands when device is not active
	return if ($hash->{DevState} == HMUARTLGW_STATE_NONE);

	push @{$hash->{Helper}{PendingCMD}}, { cmd => $cmd };
	return HMUARTLGW_SendPendingCmd($hash);
}

sub HMUARTLGW_UpdatePeerReq($;$) {
	my ($hash, $peer) = @_;
	my $name = $hash->{NAME};

	$peer = $hash->{Helper}{UpdatePeer} if (!$peer);

	Log3($hash, 4, "HMUARTLGW ${name} UpdatePeerReq: ".$peer->{id}.", state ".$hash->{DevState});

	my $msg;

	if ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER) {
		$hash->{Helper}{UpdatePeer} = $peer;

		if ($peer->{operation} eq "+") {
			my $flags = hex($peer->{flags});

			$msg = HMUARTLGW_APP_ADD_PEER .
			       $peer->{id} .
			       $peer->{kNo} .
			       (($flags & 0x02) ? "01" : "00") . #Wakeup?
			       "00"; #setting this causes "0013" messages for thermostats on wakeup ?!
		} else {
			$msg = HMUARTLGW_APP_REMOVE_PEER . $peer->{id};
		}

		$hash->{Helper}{UpdatePeer}{msg} = $msg;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_AES1) {
		my $offset = 0;
		foreach my $c (reverse(unpack "(A2)*", $hash->{Helper}{UpdatePeer}{aes})) {
			$c = ~hex($c);
			for (my $chan = 0; $chan < 8; $chan++) {
				if ($c & (1 << $chan)) {
					Log3($hash, 4, "HMUARTLGW ${name} Disabling AES for channel " . ($chan+$offset));
					$msg .= sprintf("%02x", $chan+$offset);
				}
			}
			$offset += 8;
		}

		if (defined($msg)) {
			$msg = HMUARTLGW_APP_PEER_REMOVE_AES . $hash->{Helper}{UpdatePeer}{id} . ${msg};
		} else {
			return HMUARTLGW_GetSetParameters($hash);
		}

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_AES2) {
		if ($peer->{operation} eq "+" && defined($peer->{aesChannels})) {
			Log3($hash, 4, "HMUARTLGW ${name} AESchannels: " . $peer->{aesChannels});
			my $offset = 0;
			foreach my $c (unpack "(A2)*", $peer->{aesChannels}) {
				$c = hex($c);
				for (my $chan = 0; $chan < 8; $chan++) {
					if ($c & (1 << $chan)) {
						Log3($hash, 4, "HMUARTLGW ${name} Enabling AES for channel " . ($chan+$offset));
						$msg .= sprintf("%02x", $chan+$offset);
					}
				}
				$offset += 8;
			}
		}

		if (defined($msg)) {
			$msg = HMUARTLGW_APP_PEER_ADD_AES . $peer->{id} . $msg;
		} else {
			return HMUARTLGW_GetSetParameters($hash);
		}

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_CFG) {
		$msg = $hash->{Helper}{UpdatePeer}{msg};
	}

	if ($msg) {
		HMUARTLGW_send($hash, $msg, HMUARTLGW_DST_APP, $peer->{id});
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
	}
}

sub HMUARTLGW_UpdatePeer($$) {
	my ($hash, $peer) = @_;

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING) {
		$hash->{DevState} = HMUARTLGW_STATE_UPDATE_PEER;
		HMUARTLGW_UpdatePeerReq($hash, $peer);
	} else {
		#enqueue for next update
		push @{$hash->{Helper}{PeerQueue}}, $peer;
	}
}

sub HMUARTLGW_UpdateQueuedPeer($) {
	my ($hash) = @_;

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING &&
	    $hash->{Helper}{PeerQueue} &&
	    @{$hash->{Helper}{PeerQueue}}) {
		return HMUARTLGW_UpdatePeer($hash, shift(@{$hash->{Helper}{PeerQueue}}));
	}
}

sub HMUARTLGW_ParsePeer($$) {
	my ($hash, $msg) = @_;

	#040701010002fffffffffffffff9
	$hash->{AssignedPeerCnt} = hex(substr($msg, 8, 4));
	if (length($msg) > 12) {
		$hash->{Peers}{$hash->{Helper}{UpdatePeer}->{id}} = $hash->{Helper}{UpdatePeer}->{config};
		$hash->{Helper}{UpdatePeer}{aes} = substr($msg, 12);
		Log3($hash, HMUARTLGW_getVerbLvl($hash, $hash->{Helper}{UpdatePeer}->{id}, $hash->{Helper}{UpdatePeer}->{id}, 4),
			"HMUARTLGW $hash->{NAME} added peer: " . $hash->{Helper}{UpdatePeer}->{id} .
			", aesChannels: " . $hash->{Helper}{UpdatePeer}{aes});
	} else {
		delete($hash->{Peers}{$hash->{Helper}{UpdatePeer}->{id}});
		Log3($hash, HMUARTLGW_getVerbLvl($hash, $hash->{Helper}{UpdatePeer}->{id}, $hash->{Helper}{UpdatePeer}->{id}, 4),
			"HMUARTLGW $hash->{NAME} remove peer: ". $hash->{Helper}{UpdatePeer}->{id});
	}
}

sub HMUARTLGW_GetSetParameterReq($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	if ($hash->{DevState} == HMUARTLGW_STATE_SET_HMID) {
		my $hmId = AttrVal($name, "hmId", undef);

		if (!defined($hmId)) {
			$hash->{DevState} = HMUARTLGW_STATE_GET_HMID;
			return HMUARTLGW_GetSetParameterReq($hash);
		}
		HMUARTLGW_send($hash, HMUARTLGW_APP_SET_HMID . $hmId, HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_HMID) {
		HMUARTLGW_send($hash, HMUARTLGW_APP_GET_HMID, HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_DEFAULT_HMID) {
		HMUARTLGW_send($hash, HMUARTLGW_APP_DEFAULT_HMID, HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_TIME) {
		my $tmsg = HMUARTLGW_OS_SET_TIME;

		my $t = time();
		my @l = localtime($t);
		my $off = (timegm(@l) - timelocal(@l)) / 1800;

		$tmsg .= sprintf("%04x%02x", $t, $off & 0xff);

		HMUARTLGW_send($hash, $tmsg, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_FIRMWARE) {
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_FIRMWARE, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_SERIAL) {
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_SERIAL, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_NORMAL_MODE) {
		HMUARTLGW_send($hash, HMUARTLGW_OS_NORMAL_MODE, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_ENABLE_CSMACA) {
		my $csma_ca = AttrVal($name, "csmaCa", 0);

		HMUARTLGW_send($hash, HMUARTLGW_OS_ENABLE_CSMACA . sprintf("%02x", $csma_ca), HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_ENABLE_CREDITS) {
		my $dutyCycle = AttrVal($name, "dutyCycle", 1);

		HMUARTLGW_send($hash, HMUARTLGW_OS_ENABLE_CREDITS . sprintf("%02x", $dutyCycle), HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_INIT_CREDITS) {
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_CREDITS, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_CURRENT_KEY) {
		#current key is key with highest idx
		@{$hash->{Helper}{AESKeyQueue}} = HMUARTLGW_getAesKeys($hash);
		my $key = shift(@{$hash->{Helper}{AESKeyQueue}});
		HMUARTLGW_send($hash, HMUARTLGW_APP_SET_CURRENT_KEY . ($key?$key:"00"x17), HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_PREVIOUS_KEY) {
		#previous key has second highest index
		my $key = shift(@{$hash->{Helper}{AESKeyQueue}});
		HMUARTLGW_send($hash, HMUARTLGW_APP_SET_PREVIOUS_KEY . ($key?$key:"00"x17), HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_TEMP_KEY) {
		#temp key has third highest index
		my $key = shift(@{$hash->{Helper}{AESKeyQueue}});
		delete($hash->{Helper}{AESKeyQueue});
		HMUARTLGW_send($hash, HMUARTLGW_APP_SET_TEMP_KEY . ($key?$key:"00"x17), HMUARTLGW_DST_APP);

	} elsif ($hash->{DevState} >= HMUARTLGW_STATE_UPDATE_PEER &&
	         $hash->{DevState} <= HMUARTLGW_STATE_UPDATE_PEER_CFG) {
		HMUARTLGW_UpdatePeerReq($hash);
		return;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_CREDITS) {
		$hash->{Helper}{RoundTrip}{Calc} = 1;
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_CREDITS, HMUARTLGW_DST_OS);

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_UPDATE_MODE) {
		#E9CA is magic
		HMUARTLGW_send($hash, HMUARTLGW_OS_UPDATE_MODE . "E9CA", HMUARTLGW_DST_OS);

	} else {
		return;
	}

	InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
}

sub HMUARTLGW_GetSetParameters($;$$)
{
	my ($hash, $msg, $recvtime) = @_;
	my $name = $hash->{NAME};
	my $oldState = $hash->{DevState};
	my $hmId = AttrVal($name, "hmId", undef);
	my $ack = substr($msg, 2, 2) if ($msg);

	RemoveInternalTimer($hash);

	Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5), "HMUARTLGW ${name} GetSet Ack: ${ack}, state ".$hash->{DevState}) if ($ack);
	Log3($hash, 1, "HMUARTLGW ${name} GetSet NACK: ${ack}, state ".$hash->{DevState}) if ($ack && $ack =~ m/^0400/);

	if ($ack && ($ack eq HMUARTLGW_ACK_EINPROGRESS)) {
		if (defined($hash->{Helper}{GetSetRetry}) &&
		    $hash->{Helper}{GetSetRetry} > 10) {
			delete($hash->{Helper}{GetSetRetry});
			#Reboot device
			HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
			return;
		}
		$hash->{Helper}{GetSetRetry}++;

		#Retry
		InternalTimer(gettimeofday()+0.5, "HMUARTLGW_GetSetParameterReq", $hash, 0);
		return;
	}
	delete($hash->{Helper}{GetSetRetry});

	if ($hash->{DevState} == HMUARTLGW_STATE_GETSET_PARAMETERS) {
		if ($hmId) {
			$hash->{DevState} = HMUARTLGW_STATE_SET_HMID;
		} else {
			$hash->{DevState} = HMUARTLGW_STATE_GET_HMID;
		}

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_HMID) {
		$hash->{DevState} = HMUARTLGW_STATE_GET_HMID;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_HMID) {
		if ($ack eq HMUARTLGW_ACK_WITH_MULTIPART_DATA) {
			readingsSingleUpdate($hash, "D-HMIdAssigned", uc(substr($msg, 8)), 1);
			$hash->{owner} = uc(substr($msg, 8));
		}
		$hash->{DevState} = HMUARTLGW_STATE_GET_DEFAULT_HMID;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_DEFAULT_HMID) {
		if ($ack eq HMUARTLGW_ACK_WITH_MULTIPART_DATA) {
			readingsSingleUpdate($hash, "D-HMIdOriginal", uc(substr($msg, 8)), 1);
		}
		$hash->{DevState} = HMUARTLGW_STATE_SET_TIME;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_TIME) {
		$hash->{DevState} = HMUARTLGW_STATE_GET_FIRMWARE;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_FIRMWARE) {
		if ($ack eq HMUARTLGW_ACK_INFO) {
			my $fw = hex(substr($msg, 10, 2)).".".
			         hex(substr($msg, 12, 2)).".".
			         hex(substr($msg, 14, 2));
			$hash->{Helper}{FW} = hex((substr($msg, 10, 6)));
			$fw .= " (outdated)" if ($hash->{Helper}{FW} < 0x010401);
			readingsSingleUpdate($hash, "D-firmware", $fw, 1);
		}
		$hash->{DevState} = HMUARTLGW_STATE_SET_NORMAL_MODE;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_NORMAL_MODE) {
		$hash->{DevState} = HMUARTLGW_STATE_GET_SERIAL;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_SERIAL) {
		if ($ack eq HMUARTLGW_ACK_INFO && $hash->{DevType} eq "UART") {
			readingsSingleUpdate($hash, "D-serialNr", pack("H*", substr($msg, 4)), 1);
		}
		$hash->{DevState} = HMUARTLGW_STATE_ENABLE_CSMACA;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_ENABLE_CSMACA) {
		$hash->{DevState} = HMUARTLGW_STATE_ENABLE_CREDITS;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_ENABLE_CREDITS) {
		$hash->{DevState} = HMUARTLGW_STATE_GET_INIT_CREDITS;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_INIT_CREDITS) {
		if ($ack eq HMUARTLGW_ACK_INFO) {
			HMUARTLGW_updateMsgLoad($hash, hex(substr($msg, 4)));
		}

		$hash->{DevState} = HMUARTLGW_STATE_SET_CURRENT_KEY;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_CURRENT_KEY) {
		$hash->{DevState} = HMUARTLGW_STATE_SET_PREVIOUS_KEY;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_PREVIOUS_KEY) {
		$hash->{DevState} = HMUARTLGW_STATE_SET_TEMP_KEY;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_TEMP_KEY) {
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_CREDITS) {
		if (defined($recvtime) &&
		    defined($hash->{Helper}{AckPending}{$hash->{DEVCNT}}) &&
		    defined($hash->{Helper}{RoundTrip}{Calc})) {
			delete($hash->{Helper}{RoundTrip}{Calc});
			my $delay = $recvtime - $hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{time};
			$hash->{Helper}{RoundTrip}{Delay} = $delay if ($delay < 0.2);
			Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5), "HMUARTLGW ${name} roundtrip delay: " . sprintf("%.4f", ${delay}));
		}
		if ($ack eq HMUARTLGW_ACK_INFO) {
			HMUARTLGW_updateMsgLoad($hash, hex(substr($msg, 4)));
		}
		delete($hash->{Helper}{CreditFailed});
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SET_UPDATE_MODE) {
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;

	}

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING &&
	    $oldState != HMUARTLGW_STATE_RUNNING &&
	    (!$hash->{Helper}{OneParameterOnly})) {
		#Init sequence over, add known peers
		$hash->{AssignedPeerCnt} = 0;

		foreach my $peer (keys(%{$hash->{Peers}})) {
			if ($modules{CUL_HM}{defptr}{$peer} &&
			    $modules{CUL_HM}{defptr}{$peer}{helper}{io}{newChn}) {
				my ($id, $flags, $kNo, $aesChannels) = split(/,/, $modules{CUL_HM}{defptr}{$peer}{helper}{io}{newChn});
				my $p = {
					id => substr($id, 1),
					operation => substr($id, 0, 1),
					flags => $flags,
					kNo => $kNo,
					aesChannels => $aesChannels,
					config => $modules{CUL_HM}{defptr}{$peer}{helper}{io}{newChn},
				};
				#enqueue for later
				if ($p->{operation} eq "+") {
					$hash->{Peers}{$peer} = "pending";
					push @{$hash->{Helper}{PeerQueue}}, $p;
				} else {
					delete($hash->{Peers}{$peer});
				}
			} else {
				delete($hash->{Peers}{$peer});
			}
		}

		#start credit checker
		RemoveInternalTimer("HMUARTLGW_CheckCredits:$name");
		InternalTimer(gettimeofday()+1, "HMUARTLGW_CheckCredits", "HMUARTLGW_CheckCredits:$name", 0);

		$hash->{Helper}{Initialized} = 1;
		HMUARTLGW_updateCondition($hash);
	}

	if ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER) {
		if ($ack eq HMUARTLGW_ACK_WITH_MULTIPART_DATA) {
			HMUARTLGW_ParsePeer($hash, $msg);
		} else {
			if ($hash->{Helper}{UpdatePeer}{operation} eq "+") {
				Log3($hash, 1, "HMUARTLGW ${name} Adding peer $hash->{Helper}{UpdatePeer}{id} failed! " .
				               "You have probably forced an unknown aesKey for this device.");
			} else {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, $hash->{Helper}{UpdatePeer}{id}, $hash->{Helper}{UpdatePeer}{id}, 4),
				     "HMUARTLGW ${name} Removing peer $hash->{Helper}{UpdatePeer}{id} failed!");
			}
			$hash->{Helper}{UpdatePeer}{operation} = "";
		}

		if ($hash->{Helper}{UpdatePeer}{operation} eq "+") {
			$hash->{DevState} = HMUARTLGW_STATE_UPDATE_PEER_AES1;
		} else {
			delete($hash->{Helper}{UpdatePeer});
			$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		}

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_AES1) {
		$hash->{DevState} = HMUARTLGW_STATE_UPDATE_PEER_AES2;

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_AES2) {
		if ($hash->{Helper}{UpdatePeer}->{operation} eq "+") {
			$hash->{DevState} = HMUARTLGW_STATE_UPDATE_PEER_CFG;
		} else {
			delete($hash->{Helper}{UpdatePeer});
			$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		}

	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_PEER_CFG) {
		if ($ack eq HMUARTLGW_ACK_WITH_MULTIPART_DATA) {
			HMUARTLGW_ParsePeer($hash, $msg);
		}

		delete($hash->{Helper}{UpdatePeer});
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
	}

	#Don't continue in state-machine if only one parameter should be
	#set/queried, SET_HMID is special, as we have to query it again
	#to update readings. SET_CURRENT_KEY is always followed by
	#SET_PREVIOUS_KEY and SET_TEMP_KEY.
	if ($hash->{Helper}{OneParameterOnly} &&
	    $oldState != $hash->{DevState} &&
	    $oldState != HMUARTLGW_STATE_SET_HMID &&
	    $oldState != HMUARTLGW_STATE_SET_CURRENT_KEY &&
	    $oldState != HMUARTLGW_STATE_SET_PREVIOUS_KEY) {
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		delete($hash->{Helper}{OneParameterOnly});
	}

	if ($hash->{DevState} != HMUARTLGW_STATE_RUNNING) {
		HMUARTLGW_GetSetParameterReq($hash);
	} else {
		HMUARTLGW_UpdateQueuedPeer($hash);
		HMUARTLGW_SendPendingCmd($hash);
	}
}

sub HMUARTLGW_Parse($$$$)
{
	my ($hash, $msg, $dst, $recvtime) = @_;
	my $name = $hash->{NAME};

	my $recv;
	my $CULinfo = '';

	$hash->{RAWMSG} = $msg;

	Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
	     "HMUARTLGW ${name} recv: ".sprintf("%02X", $dst)." ${msg}, state ".$hash->{DevState})
	    if ($dst == HMUARTLGW_DST_OS || $dst == HMUARTLGW_DST_DUAL ||
	        $dst == HMUARTLGW_DST_DUAL_ERR || ($msg !~ m/^05/ && $msg !~ m/^040[3C]/));

	#Minimally handle DualCopro-Firmware
	if ($dst == HMUARTLGW_DST_DUAL) {
		if (($msg =~ m/^00(.*)$/ || $msg =~ m/^0501(.*)$/) &&
		    $hash->{DevState} <= HMUARTLGW_STATE_ENTER_APP) {
			if (pack("H*", $1) eq "DualCoPro_App") {
				$hash->{DevState} = HMUARTLGW_STATE_UNSUPPORTED_FW;
				readingsSingleUpdate($hash, "D-firmware", "unsupported", 1);
				HMUARTLGW_updateCondition($hash);
				RemoveInternalTimer($hash);
				Log3($hash, 0, "HMUARTLGW ${name} is running unsupported firmware, please install a supported version");
			}
		}

		return;
	}

	#Re-send commands for DualCopro Firmware
	if ($dst == HMUARTLGW_DST_DUAL_ERR) {
		if ($hash->{DevState} == HMUARTLGW_STATE_QUERY_APP) {
			Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 4),
			     "HMUARTLGW ${name} Re-sending app-query for unsupported firmware");
			HMUARTLGW_send($hash, HMUARTLGW_DUAL_GET_APP, HMUARTLGW_DST_DUAL);
		} elsif (defined($hash->{Helper}{AckPending}{$hash->{DEVCNT}}) &&
		         $hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{dst} == HMUARTLGW_DST_OS &&
		         $hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{cmd} eq HMUARTLGW_OS_CHANGE_APP) {
			Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 4),
			     "HMUARTLGW ${name} Re-sending switch to bootloader for unsupported firmare");
			HMUARTLGW_send($hash, HMUARTLGW_DUAL_CHANGE_APP, HMUARTLGW_DST_DUAL);
		}

		return;
	}

	if ($msg =~ m/^04/ &&
	    $hash->{CNT} != $hash->{DEVCNT}) {
		if (defined($hash->{Helper}{AckPending}{$hash->{DEVCNT}})) {
			Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
			            "HMUARTLGW ${name} got delayed ACK for request " .
			            $hash->{DEVCNT}.": ".$hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{dst} .
			            " " . $hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{cmd} .
			            sprintf(" (%.3f", (gettimeofday() - $hash->{Helper}{AckPending}{$hash->{DEVCNT}}->{time})) .
			            "s late)");

			delete($hash->{Helper}{AckPending}{$hash->{DEVCNT}});

			return;
		}

		#Firmware sometimes send additional ACK when receiving the
		#next frame from a device after a command, even if it has
		#already ACKed the command.
		Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
		               "HMUARTLGW ${name} Ack with invalid/old counter received, dropping. We: $hash->{CNT}, device: $hash->{DEVCNT}, " .
		               "state: $hash->{DevState}, msg: ${dst} ${msg}");

		return;
	}

	if ($msg =~ m/^04/ &&
	    $hash->{DevState} >= HMUARTLGW_STATE_GETSET_PARAMETERS &&
	    $hash->{DevState} < HMUARTLGW_STATE_RUNNING) {
		HMUARTLGW_GetSetParameters($hash, $msg, $recvtime);
		return;
	}

	if (defined($hash->{Helper}{RoundTrip}{Calc})) {
		#We have received another message while calculating delay.
		#This will skew the calculation, so don't do it now
		delete($hash->{Helper}{RoundTrip}{Calc});
	}

	if ($dst == HMUARTLGW_DST_OS) {
		if ($msg =~ m/^00(..)/) {
			my $running = pack("H*", substr($msg, 2));

			if ($hash->{DevState} <= HMUARTLGW_STATE_ENTER_APP) {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 4), "HMUARTLGW ${name} currently running ${running}");

				if ($running eq "Co_CPU_App") {
					$hash->{DevState} = HMUARTLGW_STATE_GETSET_PARAMETERS;
					RemoveInternalTimer($hash);
					InternalTimer(gettimeofday()+1, "HMUARTLGW_GetSetParameters", $hash, 0);
				} else {
					if ($hash->{DevState} == HMUARTLGW_STATE_QUERY_APP) {
						$hash->{DevState} = HMUARTLGW_STATE_ENTER_APP;
						HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
						RemoveInternalTimer($hash);
						InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
					} else {
						Log3($hash, 1, "HMUARTLGW ${name} failed to enter App!");
					}
				}
			} elsif ($hash->{DevState} > HMUARTLGW_STATE_ENTER_APP) {
				Log3($hash, 1, "HMUARTLGW ${name} unexpected info about ${running} received (module crashed?), reopening")
				    if (!defined($hash->{FirmwareFile}));
				HMUARTLGW_Reopen($hash);
				return;
			}
		} elsif ($msg =~ m/^04(..)/) {
			my $ack = $1;

			if ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_COPRO) {
				HMUARTLGW_updateCoPro($hash, $msg);
				return;
			}

			if ($ack eq HMUARTLGW_ACK_INFO && $hash->{DevState} == HMUARTLGW_STATE_QUERY_APP) {
				my $running = pack("H*", substr($msg, 4));

				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 4), "HMUARTLGW ${name} currently running ${running}");

				if ($running eq "Co_CPU_App") {
					#Reset module
					HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
					RemoveInternalTimer($hash);
					InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
				} else {
					if (defined($hash->{FirmwareFile}) && $hash->{FirmwareFile} ne "") {
						Log3($hash, 1, "HMUARTLGW ${name} starting firmware upgrade");

						$hash->{FirmwareBlock} = 0;
						$hash->{DevState} = HMUARTLGW_STATE_UPDATE_COPRO;
						HMUARTLGW_updateCondition($hash);
						HMUARTLGW_updateCoPro($hash, $msg);
						return;
					}
					$hash->{DevState} = HMUARTLGW_STATE_ENTER_APP;
					HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
					RemoveInternalTimer($hash);
					InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
				}
			} elsif ($ack eq HMUARTLGW_ACK_NACK && $hash->{DevState} == HMUARTLGW_STATE_ENTER_APP) {
				Log3($hash, 1, "HMUARTLGW ${name} application switch failed, application-firmware probably corrupted!");
				HMUARTLGW_Reopen($hash);
				return;
			}
		} elsif ($msg =~ m/^05(..)$/) {
			HMUARTLGW_updateMsgLoad($hash, hex($1));
		}
	} elsif ($dst == HMUARTLGW_DST_APP) {

		if ($msg =~ m/^04(..)(.*)$/) {
			my $ack = $1;
			my $oldMsg;

			if ($hash->{DevState} == HMUARTLGW_STATE_SEND ||
			    $hash->{DevState} == HMUARTLGW_STATE_SEND_NOACK) {
				RemoveInternalTimer($hash);
				$hash->{DevState} = HMUARTLGW_STATE_RUNNING;

				$oldMsg = shift @{$hash->{Helper}{PendingCMD}};
			}

			if ($ack eq HMUARTLGW_ACK_WITH_RESPONSE ||
			    $ack eq HMUARTLGW_ACK_WITH_RESPONSE_AES_OK) {
				$recv = $msg;

			} elsif ($ack eq HMUARTLGW_ACK_WITH_RESPONSE_AES_KO) {
				if ($2 =~ m/^FE/) { #challenge msg
					$recv = $msg;
				} elsif ($oldMsg) {
					#Need to produce our own "failed" challenge
					$recv = substr($msg, 0, 6) . "01" .
					        substr($oldMsg->{cmd}, 8, 2) .
					        "A002" .
					        substr($oldMsg->{cmd}, 20, 6) .
					        substr($oldMsg->{cmd}, 14, 6) .
					        "04000000000000" .
					        sprintf("%02X", hex(substr($msg, 4, 2))*2);
				}
				$CULinfo = "AESpending";

			} elsif ($ack eq HMUARTLGW_ACK_EINPROGRESS && $oldMsg) {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
				     "HMUARTLGW ${name} IO currently busy, trying again in a bit");

				if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING) {
					$oldMsg->{RetryStart} = gettimeofday() if (!defined($oldMsg->{RetryStart}));
					RemoveInternalTimer($hash);
					unshift @{$hash->{Helper}{PendingCMD}}, $oldMsg;
					$hash->{DevState} = HMUARTLGW_STATE_SEND_TIMED;
					InternalTimer(gettimeofday()+(HMUARTLGW_BUSY_RETRY_MS / 1000), "HMUARTLGW_SendPendingTimer", $hash, 0);
				}
				return;
			} elsif ($ack eq HMUARTLGW_ACK_ENOCREDITS) {
				Log3($hash, 1, "HMUARTLGW ${name} IO in overload!");
				$hash->{XmitOpen} = 0;
				HMUARTLGW_updateCondition($hash);
			} elsif ($ack eq HMUARTLGW_ACK_ECSMACA && $oldMsg) {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
				     "HMUARTLGW ${name} can't send due to CSMA/CA, trying again in a bit");

				if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING) {
					$oldMsg->{RetryStart} = gettimeofday() if (!defined($oldMsg->{RetryStart}));
					RemoveInternalTimer($hash);
					unshift @{$hash->{Helper}{PendingCMD}}, $oldMsg;
					$hash->{DevState} = HMUARTLGW_STATE_SEND_TIMED;
					InternalTimer(gettimeofday()+(HMUARTLGW_CSMACA_RETRY_MS / 1000), "HMUARTLGW_SendPendingTimer", $hash, 0);
				}
				return;
			} elsif ($ack eq HMUARTLGW_ACK_EUNKNOWN && $oldMsg) {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
				     "HMUARTLGW ${name} can't send due to unknown problem (no response?)");
			} else {
				Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
				     "HMUARTLGW ${name} Ack: ${ack} ".(($2)?$2:""));
				$recv = $msg;
			}
		} elsif ($msg =~ m/^(05.*)$/) {
			$recv = $1;
		}

		if ($recv && $recv =~ m/^(..)(..)(..)(..)(..)(..)(..)(......)(......)(.*)$/) {
			my ($type, $status, $info, $rssi, $mNr, $flags, $cmd, $src, $dst, $payload) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

			Log3($hash, HMUARTLGW_getVerbLvl($hash, $src, $dst, 5),
			     "HMUARTLGW ${name} recv: 01 ${type} ${status} ${info} ${rssi} msg: ${mNr} ${flags} ${cmd} ${src} ${dst} ${payload}");

			return if (!$hash->{Helper}{Initialized});

			$rssi = 0 - hex($rssi);
			my %addvals = (RAWMSG => $msg);
			if ($rssi < -1) {
				$addvals{RSSI} = $rssi;
				$hash->{RSSI} = $rssi;
			} else {
				$rssi = "";
			}

			my $dmsg;
			my $m = $mNr . $flags . $cmd . $src . $dst . $payload;

			if ($type eq HMUARTLGW_APP_ACK && $status eq HMUARTLGW_ACK_WITH_RESPONSE_AES_OK) {
				#Fake AES challenge for CUL_HM
				my $kNo = sprintf("%02X", (hex($info) * 2));
				my $c = "${mNr}A002${src}${dst}04000000000000${kNo}";
				$dmsg = sprintf("A%02X%s:AESpending:${rssi}:${name}", length($c)/2, uc($c));

				$CULinfo = "AESCom-ok";
			} elsif ($type eq HMUARTLGW_APP_RECV && ($status eq HMUARTLGW_RECV_RESP_WITH_AES_OK ||
			                                         $status eq  HMUARTLGW_RECV_TRIG_WITH_AES_OK)) {
				#Fake AES response for CUL_HM
				$dmsg = sprintf("A%02X%s:AESpending:${rssi}:${name}", length($m)/2, uc($m));

				$CULinfo = "AESCom-ok";
			} elsif ($type eq HMUARTLGW_APP_RECV && $status eq HMUARTLGW_RECV_RESP_WITH_AES_KO) {
				#Fake AES response for CUL_HM
				$dmsg = sprintf("A%02X%s:AESpending:${rssi}:${name}", length($m)/2, uc($m));

				$CULinfo = "AESCom-fail";
			}

			if ($dmsg) {
				Log3($hash, 5, "HMUARTLGW ${name} Dispatch: ${dmsg}");
				Dispatch($hash, $dmsg, \%addvals);
			}

			$dmsg = sprintf("A%02X%s:${CULinfo}:${rssi}:${name}", length($m)/2, uc($m));

			Log3($hash, 5, "HMUARTLGW ${name} Dispatch: ${dmsg}");

			my $wait = 0;
			if (!(hex($flags) & (1 << 5))) {
				#!BIDI
				$wait = 0.100;
			} else {
				$wait = 0.300;
			}
			$wait -= $hash->{Helper}{RoundTrip}{Delay} if (defined($hash->{Helper}{RoundTrip}{Delay}));

			$modules{CUL_HM}{defptr}{$src}{helper}{io}{nextSend} = $recvtime + $wait
				if ($modules{CUL_HM}{defptr}{$src} && $wait > 0);

			Dispatch($hash, $dmsg, \%addvals);
		}
	}

	if ($hash->{DevState} == HMUARTLGW_STATE_RUNNING) {
			HMUARTLGW_UpdateQueuedPeer($hash);
			HMUARTLGW_SendPendingCmd($hash);
	}

	return;
}

sub HMUARTLGW_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $recvtime = gettimeofday();

	my $buf = DevIo_SimpleRead($hash);
	return "" if (!defined($buf));

	$buf = HMUARTLGW_decrypt($hash, $buf) if ($hash->{'.crypto'});

	Log3($hash, 5, "HMUARTLGW ${name} read raw (".length($buf)."): ".unpack("H*", $buf));

	my $p = pack("H*", $hash->{PARTIAL}) . $buf;
	$hash->{PARTIAL} .= unpack("H*", $buf);

	return HMUARTLGW_LGW_Init($hash) if ($hash->{LGW_Init});

	return HMUARTLGW_LGW_HandleKeepAlive($hash) if ($hash->{DevType} eq "LGW-KeepAlive");

	#need at least one frame delimiter
	return if (!($p =~ m/\xfd/));

	#garbage in the beginning?
	if (!($p =~ m/^\xfd/)) {
		$p = substr($p, index($p, chr(0xfd)));
	}

	my $unprocessed;

	while (defined($p) && $p =~ m/^\xfd/) {
		$unprocessed = $p;

		(undef, my $frame, $p) = split(/\xfd/, $unprocessed, 3);
		$p = chr(0xfd) . $p if ($p);

		my $unescaped = '';
		my $unescape_next = 0;
		foreach my $byte (split(//, $frame)) {
			if (ord($byte) == 0xfc) {
				$unescape_next = 1;
				next;
			}
			if ($unescape_next) {
				$byte = chr(ord($byte)|0x80);
				$unescape_next = 0;
			}
			$unescaped .= $byte;
		}

		next if (length($unescaped) < 6); #len len dst cnt crc crc

		(my $len) = unpack("n", substr($unescaped, 0, 2));

		if (length($unescaped) > $len + 4) {
			Log3($hash, 1, "HMUARTLGW ${name} frame with wrong length received: ".length($unescaped).", should: ".($len + 4).": FD".uc(unpack("H*", $unescaped)));
			next;
		}

		next if (length($unescaped) < $len + 4); #short read

		my $crc = HMUARTLGW_crc16(chr(0xfd).$unescaped);
		if ($crc != 0x0000 &&
		    $hash->{DevState} != HMUARTLGW_STATE_RUNNING &&
		    defined($hash->{Helper}{LastSendLen})) {
			#When writing to the device while it prepares to write a frame to
			#the host, the device seems to initialize the crc with 0x827f or
			#0x8281 plus the length of the frame being received (firmware bug).
			foreach my $slen (reverse(@{$hash->{Helper}{LastSendLen}})) {
				$crc = HMUARTLGW_crc16(chr(0xfd).$unescaped, 0x827f + $slen);
				Log3($hash, 5, "HMUARTLGW ${name} invalid checksum received, recalculated with slen ${slen}: ${crc}");
				last if ($crc == 0x0000);

				$crc = HMUARTLGW_crc16(chr(0xfd).$unescaped, 0x8281 + $slen);
				Log3($hash, 5, "HMUARTLGW ${name} invalid checksum received, recalculated with slen ${slen}: ${crc}");
				last if ($crc == 0x0000);
			}
		}

		if ($crc != 0x0000) {
			Log3($hash, 1, "HMUARTLGW ${name} invalid checksum received, dropping frame (FD".uc(unpack("H*", $unescaped)).")!");
			undef($unprocessed);
			next;
		}

		Log3($hash, 5, "HMUARTLGW ${name} read (".length($unescaped)."): fd".unpack("H*", $unescaped)." crc OK");

		my $dst = ord(substr($unescaped, 2, 1));
		$hash->{DEVCNT} = ord(substr($unescaped, 3, 1));

		my $msg = uc(unpack("H*", substr($unescaped, 4, -2)));
		HMUARTLGW_Parse($hash, $msg, $dst, $recvtime);

		delete($hash->{Helper}{AckPending}{$hash->{DEVCNT}})
			if (($msg =~ m/^04/) &&
			    defined($hash->{Helper}{AckPending}) &&
			    defined($hash->{Helper}{AckPending}{$hash->{DEVCNT}}));

		undef($unprocessed);
	}

	if (defined($unprocessed)) {
		$hash->{PARTIAL} = unpack("H*", $unprocessed);
	} else {
		$hash->{PARTIAL} = '';
	}
}

sub HMUARTLGW_Write($$$)
{
	my ($hash, $fn, $msg) = @_;
	my $name = $hash->{NAME};

	Log3($hash, 5, "HMUARTLGW ${name} HMUARTLGW_Write: ${msg}");

	if($msg =~ m/init:(......)/) {
		my $dst = $1;
		if ($modules{CUL_HM}{defptr}{$dst} &&
		    $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn}) {
			my ($id, $flags, $kNo, $aesChannels) = split(/,/, $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn});
			my $peer = {
				id => substr($id, 1),
				operation => substr($id, 0, 1),
				flags => $flags,
				kNo => $kNo,
				aesChannels => $aesChannels,
				config => $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn},
			};
			$hash->{Peers}{$peer->{id}} = "pending";
			HMUARTLGW_UpdatePeer($hash, $peer);
		}
		return;
	} elsif ($msg =~ m/remove:(......)/) {
		my $peer = {
			id => $1,
			operation => "-",
		};
		delete($hash->{Peers}{$peer->{id}});
		HMUARTLGW_UpdatePeer($hash, $peer);
	} elsif ($msg =~ m/^([+-])(.*)$/) {
		my ($id, $flags, $kNo, $aesChannels) = split(/,/, $msg);
		my $peer = {
			id => substr($id, 1),
			operation => substr($id, 0, 1),
			flags => $flags,
			kNo => $kNo,
			aesChannels => $aesChannels,
			config => $msg,
		};
		if ($peer->{operation} eq "+") {
			$hash->{Peers}{$peer->{id}} = "pending";
		} else {
			delete($hash->{Peers}{$peer->{id}});
		}
		HMUARTLGW_UpdatePeer($hash, $peer);
		return;
	} elsif ($msg =~ m/^writeAesKey:(.*)$/) {
		HMUARTLGW_writeAesKey($1);
		return;
	} elsif ($msg =~ /^G(..)$/) {
		my $speed = hex($1);

		if ($speed == 100) {
			HMUARTLGW_SendCmd($hash, "UpdateMode");
		} else {
			HMUARTLGW_SendCmd($hash, "NormalMode");
		}
	} elsif (length($msg) > 21) {
		my ($flags, $mtype,$src,$dst) = (substr($msg, 6, 2),
		                                 substr($msg, 8, 2),
		                                 substr($msg, 10, 6),
		                                 substr($msg, 16, 6));

		if (!defined($hash->{owner}) ||
		    !defined($hash->{Helper}{FW})) {
			Log3($hash, 1, "HMUARTLGW ${name}: Device not initialized (state: $hash->{DevState}, " .
			               ReadingsVal($name, "cond", "").") but asked to send data. Dropping: ${msg}");
			return;
		}

		if ($mtype eq "02" && $src eq $hash->{owner} && length($msg) == 24 &&
		    defined($hash->{Peers}{$dst})) {
			# Acks are generally send by HMUARTLGW autonomously
			# Special
			Log3($hash, 5, "HMUARTLGW ${name}: Skip ACK");
			return;
		} elsif ($mtype eq "02" && $src ne $hash->{owner} &&
		    defined($hash->{Peers}{$dst})) {
			Log3($hash, 0, "HMUARTLGW ${name}: Can't send ACK not originating from my hmId (firmware bug), please use a VCCU virtual device!");
			return;
		} elsif ($flags eq "A1" && $mtype eq "12") {
			Log3($hash, 5, "HMUARTLGW ${name}: FIXME: filter out A112 message (it's automatically generated by the device)");
			#return;
		}

		my $qLen = AttrVal($name, "qLen", 60);

		#Queue full?
		if ($hash->{Helper}{PendingCMD} &&
		    scalar(@{$hash->{Helper}{PendingCMD}}) >= $qLen) {
			if ($hash->{XmitOpen} == 2) {
				Log3($hash, 1, "HMUARTLGW ${name}: queue is full, dropping packet");
				return;
			} elsif ($hash->{XmitOpen} == 1) {
				$hash->{XmitOpen} = 2;
			}
		}

		if (!$hash->{Peers}{$dst} && $dst ne "000000"){
			#add id and enqueue command
			my $peer = {
				id => $dst,
				operation => "+",
				flags => "00",
				kNo => "00",
				config => "+${dst}",
			};
			if ($modules{CUL_HM}{defptr}{$dst} &&
			    $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn}) {
				my (undef, $flags, $kNo, $aesChannels) = split(/,/, $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn});
				$peer->{flags} = $flags;
				$peer->{kNo} = $kNo;
				$peer->{aesChannels} = $aesChannels;
				$peer->{config} = $modules{CUL_HM}{defptr}{$dst}{helper}{io}{newChn};
			}
			$hash->{Peers}{$dst} = "pending";
			HMUARTLGW_UpdatePeer($hash, $peer);
		}

		my $cmd = HMUARTLGW_APP_SEND . "0000";

		if ($hash->{Helper}{FW} > 0x010006) { #TODO: Find real version which adds this
			$cmd .= ((hex(substr($msg, 6, 2)) & 0x10) ? "01" : "00");
		}

		$cmd .= substr($msg, 4);

		HMUARTLGW_SendCmd($hash, $cmd);
		HMUARTLGW_SendCmd($hash, "Credits") if ((++$hash->{Helper}{SendCnt} % 10) == 0);

		# Check queue again
		if ($hash->{Helper}{PendingCMD} &&
		    scalar(@{$hash->{Helper}{PendingCMD}}) >= $qLen) {
			$hash->{XmitOpen} = 2 if ($hash->{XmitOpen} == 1);
		}
	} else {
		Log3($hash, 1, "HMUARTLGW ${name} write:${fn} ${msg}");
	}


	return;
}

sub HMUARTLGW_StartInit($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if ($hash->{LGW_Init}) {
		if ($hash->{LGW_Init} >= 10) {
			Log3($hash, 1, "HMUARTLGW ${name} LGW init did not complete after 10s".($hash->{'.crypto'}?", probably wrong password":""));
			HMUARTLGW_Reopen($hash);
			return;
		}

		$hash->{LGW_Init}++;

		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+1, "HMUARTLGW_StartInit", $hash, 0);
		return;
	}

	Log3($hash, 4, "HMUARTLGW ${name} StartInit");

	RemoveInternalTimer($hash);

	InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);

	if ($hash->{DevType} eq "LGW-KeepAlive") {
		$hash->{DevState} = HMUARTLGW_STATE_KEEPALIVE_INIT;
		HMUARTLGW_sendAscii($hash, "L%02x,02,00ff,00\r\n");
		return;
	}

	$hash->{DevState} = HMUARTLGW_STATE_QUERY_APP;
	HMUARTLGW_send($hash, HMUARTLGW_OS_GET_APP, HMUARTLGW_DST_OS);
	HMUARTLGW_updateCondition($hash);

	return;
}

sub HMUARTLGW_CheckCmdResp($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	#The data we wait for might have already been received but never
	#read from the FD. Do a last check now and process new data.
	if (defined($hash->{FD})) {
		my $rin = '';
		vec($rin, $hash->{FD}, 1) = 1;
		my $n = select($rin, undef, undef, 0);
		if ($n > 0) {
			Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
			     "HMUARTLGW ${name} HMUARTLGW_CheckCmdResp: FD is readable, this might be the data we are looking for!");
			#We will be back very soon!
			InternalTimer(gettimeofday()+0, "HMUARTLGW_CheckCmdResp", $hash, 0);
			HMUARTLGW_Read($hash);
			return;
		}
	}

	if ($hash->{DevState} == HMUARTLGW_STATE_SEND) {
		$hash->{Helper}{PendingCMD}->[0]->{RetryStart} = gettimeofday()
		    if (!defined($hash->{Helper}{PendingCMD}->[0]->{RetryStart}));
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		return HMUARTLGW_SendPendingCmd($hash);
	} elsif ($hash->{DevState} == HMUARTLGW_STATE_SEND_NOACK) {
		shift(@{$hash->{Helper}{PendingCMD}});
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		#try next command
		return HMUARTLGW_SendPendingCmd($hash);
	} elsif ($hash->{DevState} == HMUARTLGW_STATE_GET_CREDITS &&
	         (!defined($hash->{Helper}{CreditFailed}) || ($hash->{Helper}{CreditFailed} < 3))) {
		$hash->{Helper}{CreditFailed}++;
		$hash->{DevState} = HMUARTLGW_STATE_RUNNING;
		RemoveInternalTimer("HMUARTLGW_CheckCredits:$name");
		InternalTimer(gettimeofday()+1, "HMUARTLGW_CheckCredits", "HMUARTLGW_CheckCredits:$name", 0);
	} elsif ($hash->{DevState} != HMUARTLGW_STATE_RUNNING) {
		if ((!defined($hash->{Helper}{AckPending}{$hash->{CNT}}{frame})) ||
		    (defined($hash->{Helper}{AckPending}{$hash->{CNT}}{resend}) &&
		     $hash->{Helper}{AckPending}{$hash->{CNT}}{resend} >= HMUARTLGW_CMD_RETRY_CNT)) {
			Log3($hash, 1, "HMUARTLGW ${name} did not respond after all, reopening");
			HMUARTLGW_Reopen($hash);
		} else {
			$hash->{Helper}{AckPending}{$hash->{CNT}}{resend}++;
			Log3($hash, 1, "HMUARTLGW ${name} did not respond for the " .
			     $hash->{Helper}{AckPending}{$hash->{CNT}}{resend} .
			     ". time, resending");
			HMUARTLGW_send_frame($hash, pack("H*", $hash->{Helper}{AckPending}{$hash->{CNT}}{frame}));
			InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
		}
	}

	return;
}

sub HMUARTLGW_Get($@)
{
	my ( $hash, $name, $cmd, @args ) = @_;
	my $ret = "";

	return "Unknown argument ${cmd}, choose one of " if ($hash->{DevType} eq "LGW-KeepAlive");

	if ($cmd eq "assignIDs") {
		foreach my $peer (keys(%{$hash->{Peers}})) {
			next if ($hash->{Peers}{$peer} !~ m/^\+/);
			$ret .= "\n${peer} : " . CUL_HM_id2Name($peer);
		}
		$ret = "assignedIDs: ". ($ret =~ tr/\n//) . $ret;
	} else {
		$ret = "Unknown argument ${cmd}, choose one of " .
		    join(" ",map {"$_" . ($gets{$_} ? ":$gets{$_}" : "")} keys %gets);
	}

	return $ret;
}

sub HMUARTLGW_RemoveHMPair($)
{
	my ($in) = shift;
	my (undef,$name) = split(':',$in);
	my $hash = $defs{$name};
	RemoveInternalTimer("hmPairForSec:$name");
	Log3($hash, 3, "HMUARTLGW ${name} left pairing-mode") if ($hash->{hmPair});
	delete($hash->{hmPair});
	delete($hash->{hmPairSerial});
}

sub HMUARTLGW_Set($@)
{
	my ($hash, $name, $cmd, @a) = @_;

	my $arg = join(" ", @a);

	return "\"set\" needs at least one parameter" if (!$cmd);

	return "Unknown argument ${cmd}, choose one of " if ($hash->{DevType} eq "LGW-KeepAlive");

	if ($cmd eq "hmPairForSec") {
		$arg = 60 if(!$arg || $arg !~ m/^\d+$/);
		HMUARTLGW_RemoveHMPair("hmPairForSec:$name");
		$hash->{hmPair} = 1;
		InternalTimer(gettimeofday()+$arg, "HMUARTLGW_RemoveHMPair", "hmPairForSec:$name", 0);
		Log3($hash, 3, "HMUARTLGW ${name} entered pairing-mode");
	} elsif ($cmd eq "hmPairSerial") {
		return "Usage: set $name hmPairSerial <10-character-serialnumber>"
		    if(!$arg || $arg !~ m/^.{10}$/);

		my $id = InternalVal($hash->{NAME}, "owner", "123456");
		$hash->{HM_CMDNR} = $hash->{HM_CMDNR} ? ($hash->{HM_CMDNR}+1)%256 : 1;

		HMUARTLGW_Write($hash, undef, sprintf("As15%02X8401%s000000010A%s",
					$hash->{HM_CMDNR}, $id, unpack('H*', $arg)));
		HMUARTLGW_RemoveHMPair("hmPairForSec:$name");
		$hash->{hmPair} = 1;
		$hash->{hmPairSerial} = $arg;
		InternalTimer(gettimeofday()+20, "HMUARTLGW_RemoveHMPair", "hmPairForSec:".$name, 0);
	} elsif ($cmd eq "reopen") {
		HMUARTLGW_Reopen($hash);
	} elsif ($cmd eq "close") {
		#switch to bootloader to stop the module from interfering
		HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS)
			if ($hash->{DevState} > HMUARTLGW_STATE_ENTER_APP);
		HMUARTLGW_Undefine($hash, $name);
		readingsSingleUpdate($hash, "state", "closed", 1);
		$hash->{XmitOpen} = 0;
	} elsif ($cmd eq "open") {
		DevIo_OpenDev($hash, 0, "HMUARTLGW_DoInit", \&HMUARTLGW_Connect);
	} elsif ($cmd eq "restart") {
		HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
	} elsif ($cmd eq "updateCoPro") {
		return "Usage: set $name updateCoPro </path/to/firmware.eq3>"
		    if(!$arg);
		
		my $block = HMUARTLGW_firmwareGetBlock($hash, $arg, 0);
		return "${arg} is not a valid firmware file!"
		    if (!defined($block) || $block eq "");

		$hash->{FirmwareFile} = $arg;
		HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS);
	} else {
		return "Unknown argument ${cmd}, choose one of " .
		    join(" ",map {"$_" . ($sets{$_} ? ":$sets{$_}" : "")} keys %sets);
	}

	return undef;
}

sub HMUARTLGW_Attr(@)
{
	my ($cmd, $name, $aName, $aVal) = @_;
	my $hash = $defs{$name};

	my $retVal;

	Log3($hash, 5, "HMUARTLGW ${name} Attr ${cmd} ${aName} ".(($aVal)?$aVal:""));

	return "Attribute ${cmd} not supported on keepAlive-subdevice" if ($hash->{DevType} eq "LGW-KeepAlive");

	if ($aName eq "hmId") {
		if ($cmd eq "set") {
			my $owner_ccu = InternalVal($name, "owner_CCU", undef);
			return "device owned by $owner_ccu" if ($owner_ccu);
			return "wrong syntax: hmId must be 6-digit-hex-code (3 byte)"
			    if ($aVal !~ m/^[A-F0-9]{6}$/i);

			$attr{$name}{$aName} = $aVal;

			if ($init_done) {
				HMUARTLGW_SendCmd($hash, "HMID");
			}
		}
	} elsif ($aName eq "lgwPw") {
		if ($init_done) {
			if ($hash->{DevType} eq "LGW") {
				HMUARTLGW_Reopen($hash);
			}
		}
	} elsif ($aName =~ m/^hmKey(.?)$/) {
		if ($cmd eq "set") {
			my $kNo = 1;
			$kNo = $1 if ($1);
			my ($no,$val) = (sprintf("%02X",$kNo),$aVal);
			if ($aVal =~ m/:/){#number given
				($no,$val) = split ":",$aVal;
				return "illegal number:$no" if (hex($no) < 1 || hex($no) > 255 || length($no) != 2);
			}
			$attr{$name}{$aName} = "$no:".
				(($val =~ m /^[0-9A-Fa-f]{32}$/ )
				 ? $val
				 : unpack('H*', md5($val)));
			$retVal = "$aName set to $attr{$name}{$aName}"
				if($aVal ne $attr{$name}{$aName});
		} else {
			delete $attr{$name}{$aName};
		}
		HMUARTLGW_writeAesKey($name) if ($init_done);
	} elsif ($aName eq "dutyCycle") {
		if ($cmd eq "set") {
			return "wrong syntax: dutyCycle must be 1 or 0"
			    if ($aVal !~ m/^[01]$/);
			$attr{$name}{$aName} = $aVal;
			#$retVal = "Please make sure to be in compliance with local regulations when disabling dutyCycle!"
			#    if (!($aVal));
		} else {
			delete $attr{$name}{$aName};
		}

		if ($init_done) {
			HMUARTLGW_SendCmd($hash, "DutyCycle");
		}
	} elsif ($aName eq "csmaCa") {
		if ($cmd eq "set") {
			return "wrong syntax: csmaCa must be 1 or 0"
			    if ($aVal !~ m/^[01]$/);
			$attr{$name}{$aName} = $aVal;
		} else {
			delete $attr{$name}{$aName};
		}

		if ($init_done) {
			HMUARTLGW_SendCmd($hash, "CSMACA");
		}
	} elsif ($aName eq "qLen") {
		if ($cmd eq "set") {
			return "wrong syntax: qLen must be between 1 and 200"
			    if ($aVal !~ m/^\d+$/ || $aVal < 1 || $aVal > 200);
			$attr{$name}{$aName} = $aVal;
		} else {
			delete $attr{$name}{$aName};
		}
	} elsif ($aName eq "logIDs") {
		if ($cmd eq "set") {
			my @ids = split(/,/, $aVal);

			$hash->{Helper}{Log}{IDs} = \@ids;
			$hash->{Helper}{Log}{Resolve} = 1;
			$attr{$name}{$aName} = $aVal;
		} else {
			delete $attr{$name}{$aName};
			delete $hash->{Helper}{Log};
		}
	} elsif ($aName eq "verbose") {
		if ($hash->{keepAlive}) {
			if ($cmd eq "set") {
				$attr{$hash->{keepAlive}->{NAME}}{$aName} = $aVal;
			} else {
				delete $attr{$hash->{keepAlive}->{NAME}}{$aName};
			}
		}
	} elsif ($aName eq "dummy") {
		if ($cmd eq "set") {
			if (!defined($attr{$name}{$aName})) {
				#switch to bootloader to stop the module from interfering
				HMUARTLGW_send($hash, HMUARTLGW_OS_CHANGE_APP, HMUARTLGW_DST_OS)
					if ($hash->{DevState} > HMUARTLGW_STATE_ENTER_APP);
				HMUARTLGW_Undefine($hash, $name);
				readingsSingleUpdate($hash, "state", "dummy", 1);
				HMUARTLGW_updateCondition($hash);
				$hash->{XmitOpen} = 0;
			}
		} else {
			if (defined($attr{$name}{$aName})) {
				delete $attr{$name}{$aName};
				DevIo_OpenDev($hash, 0, "HMUARTLGW_DoInit", \&HMUARTLGW_Connect);
			}
		}
	} elsif ($aName eq "loadEvents") {
		if ($cmd eq "set") {
			return "wrong syntax: loadEvents must be 1 or 0"
			    if ($aVal !~ m/^[01]$/);
			$attr{$name}{$aName} = $aVal;
		} else {
			delete $attr{$name}{$aName};
		}
	}

	return $retVal;
}

sub HMUARTLGW_getAesKeys($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my @k;

	my %keys = ();
	my $vccu = InternalVal($name,"owner_CCU",$name);
	$vccu = $name if(!AttrVal($vccu,"hmKey",""));
	foreach my $i (1..3){
		my ($kNo,$k) = split(":",AttrVal($vccu,"hmKey".($i== 1?"":$i),""));
		if (defined($kNo) && defined($k)) {
			$keys{$kNo} = $k;
		}
	}

	my @kNos = reverse(sort(keys(%keys)));
	foreach my $kNo (@kNos) {
		Log3($hash, 4, "HMUARTLGW ${name} key: ".$keys{$kNo}.", idx: ".$kNo);
		push @k, $keys{$kNo} . $kNo;
	}

	return @k;
}

sub HMUARTLGW_writeAesKey($) {
	my ($name) = @_;
	return if (!$name || !$defs{$name} || $defs{$name}{TYPE} ne "HMUARTLGW");
	my $hash = $defs{$name};

	HMUARTLGW_SendCmd($hash, "AESkeys");
	HMUARTLGW_SendPendingCmd($hash);
}

sub HMUARTLGW_updateCondition($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $cond = "disconnected";
	my $loadLvl = "suspended";

	my $oldLoad = ReadingsVal($name, "load", -1);
	if (defined($hash->{msgLoadCurrent})) {
		my $load = $hash->{msgLoadCurrent};

		readingsSingleUpdate($hash, "load", $load, AttrVal($name, "loadEvents", 0));

		$cond = "ok";
		#FIXME: Dynamic levels
		if ($load >= 100) {
			$cond = "ERROR-Overload";
			$loadLvl = "suspended";
		} elsif ($oldLoad >= 100) {
			$cond = "Overload-released";
			$loadLvl = "high";
		} elsif ($load >= 90) {
			$cond = "Warning-HighLoad";
			$loadLvl = "high";
		} elsif ($load >= 40) {
			#FIXME: batchLevel != 40 needs to be in {helper}{loadLvl}{bl}
			$loadLvl = "batchLevel";
		} else {
			$loadLvl = "low";
		}
	}

	if ((!defined($hash->{XmitOpen})) || $hash->{XmitOpen} == 0) {
		$cond = "ERROR-Overload";
		$loadLvl = "suspended";
	}

	if (!defined($hash->{Helper}{Initialized})) {
		$cond = "init";
		$loadLvl = "suspended";
	}

	if ($hash->{DevState} == HMUARTLGW_STATE_NONE) {
		$cond = "disconnected";
		$loadLvl = "suspended";
	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UPDATE_COPRO) {
		$cond = "fwupdate";
		$loadLvl = "suspended";
	} elsif ($hash->{DevState} == HMUARTLGW_STATE_UNSUPPORTED_FW) {
		$cond = "unsupported firmware";
		$loadLvl = "suspended";
	}

	if ((defined($cond) && $cond ne ReadingsVal($name, "cond", "")) ||
	    (defined($loadLvl) && $loadLvl ne ReadingsVal($name, "loadLvl", ""))) {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "cond", $cond)
			if (defined($cond) && $cond ne ReadingsVal($name, "cond", ""));
		readingsBulkUpdate($hash, "loadLvl", $loadLvl)
			if (defined($loadLvl) && $loadLvl ne ReadingsVal($name, "loadLvl", ""));
		readingsEndUpdate($hash, 1);

		my $ccu = InternalVal($name,"owner_CCU","");
		CUL_HM_UpdtCentralState($ccu) if ($ccu);
	}
}

sub HMUARTLGW_updateMsgLoad($$) {
	my ($hash, $load) = @_;

	if ($hash->{XmitOpen} != 2) {
		if ($load >= 199) {
			$hash->{XmitOpen} = 0;
		} else {
			$hash->{XmitOpen} = 1;
		}
	}

	my $adjustedLoad = int(($load + 1) / 2);

	my $histSlice = 5 * 60;
	my $histNo = 3600 / $histSlice;

	if ((!defined($hash->{Helper}{loadLvl}{lastHistory})) ||
	    ($hash->{Helper}{loadLvl}{lastHistory} + $histSlice) <= gettimeofday()) {
		my @abshist = ("-") x $histNo;
		unshift @abshist, split("/", $hash->{msgLoadHistoryAbs}) if (defined($hash->{msgLoadHistoryAbs}));
		unshift @abshist, $adjustedLoad;

		my $last;
		my @hist = ("-") x $histNo;
		foreach my $l (reverse(@abshist)) {
			next if ($l eq "-");
			unshift @hist, $l - $last if (defined($last));
			$last = $l;
		}
		$hash->{msgLoadHistory} = join("/", @hist[0..($histNo - 1)]);
		$hash->{msgLoadHistoryAbs} = join("/", @abshist[0..($histNo)]);
		if (!defined($hash->{Helper}{loadLvl}{lastHistory})) {
			$hash->{Helper}{loadLvl}{lastHistory} = gettimeofday();
		} else {
			$hash->{Helper}{loadLvl}{lastHistory} += $histSlice;
		}
	}

	if ((!defined($hash->{msgLoadCurrent})) ||
	    $hash->{msgLoadCurrent} != $adjustedLoad) {
		$hash->{msgLoadCurrent} = $adjustedLoad;
		HMUARTLGW_updateCondition($hash);
	}
}

sub HMUARTLGW_send($$$;$)
{
	my ($hash, $msg, $dst, $peer) = @_;
	my $name = $hash->{NAME};

	my $log;
	my $v;

	if ($dst == HMUARTLGW_DST_APP && uc($msg) =~ m/^(02)(..)(..)(.*)$/) {
		$log = "01 ${1} ${2} ${3} ";

		my $m = $4;

		if ($hash->{Helper}{FW} > 0x010006) {
			$log .= substr($m, 0, 2, '') . " ";
		} else {
			$log .= "XX ";
		}

		if ($m =~ m/^(..)(..)(..)(......)(......)(.*)$/) {
			$log .= "msg: ${1} ${2} ${3} ${4} ${5} ${6}";
		} else {
			$log .= $m;
		}
		$v = HMUARTLGW_getVerbLvl($hash, $4, $5, 5);
	} elsif ($dst == HMUARTLGW_DST_APP && uc($msg) =~ m/^(0[3BF]).*[^0].*(..)$/) {
		#Key, do not log
		$log = sprintf("%02X", $dst). " ${1}" . ("XX"x16) . $2;
		$v = HMUARTLGW_getVerbLvl($hash, undef, undef, 5);
	} else {
		$log = sprintf("%02X", $dst). " ".uc($msg);
		$v = HMUARTLGW_getVerbLvl($hash, $peer, $peer, 5);
	}

	Log3($hash, $v, "HMUARTLGW ${name} send: ${log}");

	$hash->{CNT} = ($hash->{CNT} + 1) & 0xff;

	my $frame = pack("CnCCH*", 0xfd,
	                            (length($msg) / 2) + 2,
	                            $dst,
	                            $hash->{CNT},
	                            $msg);

	$frame .= pack("n", HMUARTLGW_crc16($frame));

	my $sendtime = HMUARTLGW_send_frame($hash, $frame);

	if (defined($hash->{Helper}{AckPending}{$hash->{CNT}})) {
		Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
		            "HMUARTLGW ${name} never got an ACK for request ".
			    $hash->{CNT}.": ".$hash->{Helper}{AckPending}{$hash->{CNT}}->{dst} .
			    " " . $hash->{Helper}{AckPending}{$hash->{CNT}}->{cmd} .
		            sprintf(" (%.3f", ($sendtime - $hash->{Helper}{AckPending}{$hash->{CNT}}->{time})).
		            "s ago)");
	}
	$hash->{Helper}{AckPending}{$hash->{CNT}} = {
		cmd => uc($msg),
		frame => uc(unpack("H*", $frame)),
		dst => $dst,
		time => $sendtime,
	};

	push @{$hash->{Helper}{LastSendLen}}, (length($hash->{Helper}{AckPending}{$hash->{CNT}}->{cmd}) / 2) + 2;
	shift @{$hash->{Helper}{LastSendLen}} if (scalar(@{$hash->{Helper}{LastSendLen}}) > 2);
	delete($hash->{Helper}{Resend});

	return $hash->{CNT};
}

sub HMUARTLGW_send_frame($$)
{
	my ($hash, $frame) = @_;
	my $name = $hash->{NAME};

	Log3($hash, 5, "HMUARTLGW ${name} send: (".length($frame)."): ".unpack("H*", $frame));

	my $escaped = substr($frame, 0, 1);

	foreach my $byte (split(//, substr($frame, 1))) {
		if (ord($byte) != 0xfc && ord($byte) != 0xfd) {
			$escaped .= $byte;
			next;
		}
		$escaped .= chr(0xfc);
		$escaped .= chr(ord($byte) & 0x7f);
	}

	$escaped = HMUARTLGW_encrypt($hash, $escaped) if ($hash->{'.crypto'});

	my $sendtime = scalar(gettimeofday());
	DevIo_SimpleWrite($hash, $escaped, 0);

	$sendtime;
}

sub HMUARTLGW_sendAscii($$)
{
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};

	$msg = sprintf($msg, $hash->{CNT});

	my $logmsg = $msg;
	$logmsg =~ s/\r\n$//;
	Log3($hash, HMUARTLGW_getVerbLvl($hash, undef, undef, 5),
	     "HMUARTLGW ${name} send (".length($logmsg)."): ". $logmsg);
	$msg = HMUARTLGW_encrypt($hash, $msg) if ($hash->{'.crypto'} && !($msg =~ m/^V/));

	$hash->{CNT} = ($hash->{CNT} + 1) & 0xff;

	DevIo_SimpleWrite($hash, $msg, ($hash->{'.crypto'} && !($msg =~ m/^V/))? 0 : 2);
}

sub HMUARTLGW_crc16($;$)
{
	my ($msg, $crc) = @_;
	$crc = 0xd77f if (!defined($crc));

	foreach my $byte (split(//, $msg)) {
		$crc ^= (ord($byte) << 8) & 0xff00;
		for (my $i = 0; $i < 8; $i++) {
			if ($crc & 0x8000) {
				$crc = ($crc << 1) & 0xffff;
				$crc ^= 0x8005;
			} else {
				$crc = ($crc << 1) & 0xffff;
			}
		}
	}

	return $crc;
}

sub HMUARTLGW_encrypt($$)
{
	my ($hash, $plaintext) = @_;
	my $ciphertext = '';

	while(length($plaintext)) {
		if(length($hash->{'.crypto'}{encrypt}{keystream})) {
			my $len = length($plaintext);

			$len = length($hash->{'.crypto'}{encrypt}{keystream})
				if (length($hash->{'.crypto'}{encrypt}{keystream}) < $len);

			my $ppart = substr($plaintext, 0, $len, '');
			my $kpart = substr($hash->{'.crypto'}{encrypt}{keystream}, 0, $len, '');

			$hash->{'.crypto'}{encrypt}{ciphertext} .= $ppart ^ $kpart;

			$ciphertext .= $ppart ^ $kpart;
		} else {
			$hash->{'.crypto'}{encrypt}{keystream} =
				$hash->{'.crypto'}{cipher}->encrypt($hash->{'.crypto'}{encrypt}{ciphertext});
			$hash->{'.crypto'}{encrypt}{ciphertext} = '';
		}
	}

	$ciphertext;
}

sub HMUARTLGW_decrypt($$)
{
	my ($hash, $ciphertext) = @_;
	my $plaintext = '';

	while(length($ciphertext)) {
		if(length($hash->{'.crypto'}{decrypt}{keystream})) {
			my $len = length($ciphertext);

			$len = length($hash->{'.crypto'}{decrypt}{keystream})
				if (length($hash->{'.crypto'}{decrypt}{keystream}) < $len);

			my $cpart = substr($ciphertext, 0, $len, '');
			my $kpart = substr($hash->{'.crypto'}{decrypt}{keystream}, 0, $len, '');

			$hash->{'.crypto'}{decrypt}{ciphertext} .= $cpart;

			$plaintext .= $cpart ^ $kpart;
		} else {
			$hash->{'.crypto'}{decrypt}{keystream} =
				$hash->{'.crypto'}{cipher}->encrypt($hash->{'.crypto'}{decrypt}{ciphertext});
			$hash->{'.crypto'}{decrypt}{ciphertext} = '';
		}
	}

	$plaintext;
}

sub HMUARTLGW_firmwareGetBlock($$$) {
	my ($hash, $file, $id) = @_;
	my $name = $hash->{NAME};
	my $block = "";

	my $ret = open(my $fd, "<", $file);
	if (!$ret) {
		Log3($hash, 1, "HMUARTLGW ${name} can't open firmware file ${file}: $!");
		return undef;
	}

	my $fw = "";
	while(<$fd>) {
		$fw .= $_;
	}

	close($fd);

	my $n = 0;
	while(length($fw)) {
		my $len = unpack('n', pack('H4', $fw));
		if ($n eq $id) {
			$block = substr($fw, 4, $len * 2);
			last;
		}
		$fw = substr($fw, 4 + ($len * 2));
		$n++;
	}

	if ($n != $id) {
		Log3($hash, 1, "HMUARTLGW ${name} invalid block ${id} requested");
		return undef;
	}

	$block;
}

sub HMUARTLGW_updateCoPro($$) {
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	if (($hash->{FirmwareBlock} > 0) && ($msg !~ /^0401$/)) {
		Log3($hash, 1, "HMUARTLGW ${name} firmware flash failed on block " . ($hash->{FirmwareBlock} - 1));
		delete($hash->{FirmwareFile});
		delete($hash->{FirmwareBlock});

		$hash->{DevState} = HMUARTLGW_STATE_QUERY_APP;
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_APP, HMUARTLGW_DST_OS);

		InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);

		return;
	}

	my $block = HMUARTLGW_firmwareGetBlock($hash, $hash->{FirmwareFile}, $hash->{FirmwareBlock});
	if (!defined($block)) {
		Log3($hash, 1, "HMUARTLGW ${name} firmware update aborted");
		delete($hash->{FirmwareFile});
		delete($hash->{FirmwareBlock});

		$hash->{DevState} = HMUARTLGW_STATE_QUERY_APP;
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_APP, HMUARTLGW_DST_OS);

		InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);

		return;
	} elsif ($block eq "") {
		Log3($hash, 1, "HMUARTLGW ${name} firmware update successfull");
		delete($hash->{FirmwareFile});
		delete($hash->{FirmwareBlock});

		$hash->{DevState} = HMUARTLGW_STATE_QUERY_APP;
		HMUARTLGW_send($hash, HMUARTLGW_OS_GET_APP, HMUARTLGW_DST_OS);

		InternalTimer(gettimeofday()+HMUARTLGW_CMD_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);

		return;
	}

	#strip CRC from block
	$block = substr($block, 0, -4);

	HMUARTLGW_send($hash, HMUARTLGW_OS_UPDATE_FIRMWARE . ${block}, HMUARTLGW_DST_OS);
	$hash->{FirmwareBlock}++;

	InternalTimer(gettimeofday()+HMUARTLGW_FIRMWARE_TIMEOUT, "HMUARTLGW_CheckCmdResp", $hash, 0);
}

sub HMUARTLGW_getVerbLvl($$$$) {
	my ($hash, $src, $dst, $def) = @_;

	$hash = $hash->{'.lgwHash'} if (defined($hash->{'.lgwHash'}));

	#Lookup IDs on change
	if (defined($hash->{Helper}{Log}{Resolve}) && $init_done) {
		foreach my $id (@{$hash->{Helper}{Log}{IDs}}) {
			next if ($id =~ /^([\da-f]{6}|sys|all)$/i);

			my $newId = substr(CUL_HM_name2Id($id),0,6);
			next if ($newId !~ /^[\da-f]{6}$/i);

			$id = $newId;
		}
		delete($hash->{Helper}{Log}{Resolve});
	}

	return (grep /^sys$/i, @{$hash->{Helper}{Log}{IDs}}) ? 0 : $def
	    if ((!defined($src)) || (!defined($dst)));

	return (grep /^($src|$dst|all)$/i, @{$hash->{Helper}{Log}{IDs}}) ? 0 : $def;
}

1;

=pod
=item summary    support for the HomeMatic UART module (RPi) and Wireless LAN Gateway
=item summary_DE Anbindung von HomeMatic UART Modul (RPi) und Wireless LAN Gateway
=begin html

<a name="HMUARTLGW"></a>
<h3>HMUARTLGW</h3>
<ul>
  HMUARTLGW provides support for the eQ-3 HomeMatic Wireless LAN Gateway
  (HM-LGW-O-TW-W-EU) and the eQ-3 HomeMatic UART module (HM-MOD-UART), which
  is part of the HomeMatic wireless module for the Raspberry Pi
  (HM-MOD-RPI-PCB).<br>

  <br><br>

  <a name="HMUARTLGHW_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HMUARTLGW &lt;device&gt;</code><br><br>
    The &lt;device&gt;-parameter depends on the device-type:
    <ul>
      <li>HM-MOD-UART: &lt;device&gt; specifies the serial port to communicate
          with. The baud-rate is fixed at 115200 and does not need to be
          specified.<br>
          If the HM-MOD-UART is connected to the network by a serial bridge,
          the connection has to be defined in an URL-like format
          (<code>uart://ip:port</code>).</li>
      <li>HM-LGW-O-TW-W-EU: &lt;device&gt; specifies the IP address or hostname
          of the gateway, optionally followed by : and the port number of the
          BidCoS-port (default when not specified: 2000).</li>
    </ul>
    <br><br>
    Examples:<br>
    <ul>
      <li>Local HM-MOD-UART at <code>/dev/ttyAMA0</code>:<br>
          <code>define myHmUART HMUARTLGW /dev/ttyAMA0</code><br>&nbsp;</li>
      <li>LAN Gateway at <code>192.168.42.23</code>:<br>
          <code>define myHmLGW HMUARTLGW 192.168.42.23</code><br>&nbsp;</li>
      <li>Remote HM-MOD-UART using <code>socat</code> on a Raspberry Pi:<br>
          <code>define myRemoteHmUART HMUARTLGW uart://192.168.42.23:12345</code><br><br>
          Remote Raspberry Pi:<br><code>$ socat TCP4-LISTEN:12345,fork,reuseaddr /dev/ttyAMA0,raw,echo=0,b115200</code></li>
    </ul>
  </ul>
  <br>
  <a name="HMUARTLGW_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>close<br>
        Closes the connection to the device.
        </li>
    <li><a href="#hmPairForSec">hmPairForSec</a></li>
    <li><a href="#hmPairSerial">hmPairSerial</a></li>
    <li>open<br>
        Opens the connection to the device and initializes it.
        </li>
    <li>reopen<br>
        Reopens the connection to the device and reinitializes it.
        </li>
    <li>restart<br>
        Reboots the device.
        </li>
    <li>updateCoPro &lt;/path/to/firmware.eq3&gt;<br>
        Update the coprocessor-firmware (reading D-firmware) from the
        supplied file. Source for firmware-images (version 1.4.1, official
        eQ-3 repository):<br>
        <ul>
            <li>HM-MOD-UART: <a href="https://raw.githubusercontent.com/eq-3/occu/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/HM-MOD-UART/coprocessor_update.eq3">coprocessor_update.eq3</a> (version 1.4.1)</li>
            <li>HM-LGW-O-TW-W-EU: <a href="https://raw.githubusercontent.com/eq-3/occu/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/coprocessor_update_hm_only.eq3">coprocessor_update_hm_only.eq3</a> (version 1.4.1)<br>
            Please also make sure that D-LANfirmware is at least at version
            1.1.5. To update to this version, use the eQ-3 CLI tools (see wiki)
            or use the eQ-3 netfinder with this firmware image: <a href="https://github.com/eq-3/occu/raw/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/hm-lgw-o-tw-w-eu_update.eq3">hm-lgw-o-tw-w-eu_update.eq3</a><br>
            <b>Do not flash hm-lgw-o-tw-w-eu_update.eq3 with updateCoPro!</b></li>
        </ul>
        </li>
  </ul>
  <br>
  <a name="HMUARTLGW_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>assignIDs<br>
        Returns the HomeMatic devices currently assigned to this IO-device.
        </li>
  </ul>
  <br>
  <a name="HMUARTLGW_attr"></a>
  <b>Attributes</b>
  <ul>
    <li>csmaCa<br>
        Enable or disable CSMA/CA (Carrier sense multiple access with collision
        avoidance), also known as listen-before-talk.<br>
        Default: 0 (disabled)
        </li>
    <li>dummy<br>
        Do not interact with the device at all, only define it.<br>
        Default: not set
        </li>
    <li>dutyCycle<br>
        Enable or disable the duty-cycle check (1% rule) performed by the
        wireless module.<br>
        Disabling this might be illegal in your country, please check with local
        regulations!<br>
        Default: 1 (enabled)
        </li>
    <li><a href="#hmId">hmId</a></li>
    <li><a name="HMLANhmKey">hmKey</a></li>
    <li><a name="HMLANhmKey2">hmKey2</a></li>
    <li><a name="HMLANhmKey3">hmKey3</a></li>
    <li>lgwPw<br>
        AES password for the eQ-3 HomeMatic Wireless LAN Gateway. The default
        password is printed on the back of the device (but can be changed by
        the user). If AES communication is enabled on the LAN Gateway (default),
        this attribute has to be set to the correct value or communication will
        not be possible. In addition, the perl-module Crypt::Rijndael (which
        provides the AES cipher) must be installed.
        </li>
    <li>loadEvents<br>
        Enables logging of the wireless load (in percent of the allowed maximum
        sending-time) of the interface.

        Default: 0 (disabled)
        </li>
    <li>logIDs<br>
        Enables selective logging of HMUARTLGW messages. A list of comma separated
        HMIds or HM device names/channel names can be entered which shall be logged.<br>
        <ul>
            <li><i>all</i>: will log raw messages for all HMIds</li>
            <li><i>sys</i>: will log system related messages like keep-alive</li>
        </ul>
        In order to enable all messages set: <i>all,sys</i>
        </li>
    <li>qLen<br>
        Maximum number of commands in the internal queue of the HMUARTLGW module.
        New commands when the queue is full are dropped. Each command has a maximum
        lifetime of 3s when active, so the worst-case delay of a command is qLen * 3s
        (3 minutes with default settings).<br>
        Default: 60
        </li>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="HMUARTLGW"></a>
<h3>HMUARTLGW</h3>
<ul>
  Das Modul HMUARTLGW erm&ouml;glicht die Anbindung des eQ-3 HomeMatic Wireless
  LAN Gateways (HM-LGW-O-TW-W-EU) und des eQ-3 HomeMatic UART Moduls
  (HM-MOD-UART), welches Teil des HomeMatic-Moduls f&uuml;r den Raspberry Pi
  (HM-MOD-RPI-PCB) ist.<br>

  <br><br>

  <a name="HMUARTLGHW_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HMUARTLGW &lt;device&gt;</code><br><br>
    Der Parameter &lt;device&gt; h&auml;ngt vom eingesetzten Ger&auml;tetyp ab:
    <ul>
      <li>HM-MOD-UART: &lt;device&gt; ist die zu benutzende serielle
          Schnittstelle. Die Baudrate ist fest auf 115200 eingestellt und muss
          nicht angegeben werden.<br>
          Falls der HM-MOD-UART &uuml;ber einen Seriell-zu-Ethernet-Konverter
          mit dem Netzwerk verbunden ist, muss die Definition in einem
          an URLs angelehnten Format geschehen
          (<code>uart://ip:port</code>).</li>
      <li>HM-LGW-O-TW-W-EU: &lt;device&gt; gibt die IP-Adresse oder den
          Hostnamen des Gateways an, optional gefolgt von einem Doppelpunkt
          und der Portnummer des BidCos-Ports (Default falls nicht angegeben:
          2000).</li>
    </ul>
    <br><br>
    Beispiele:<br>
    <ul>
      <li>Lokaler HM-MOD-UART an der Schnittstelle <code>/dev/ttyAMA0</code>:<br>
          <code>define myHmUART HMUARTLGW /dev/ttyAMA0</code><br>&nbsp;</li>
      <li>LAN Gateway mit der IP-Adresse <code>192.168.42.23</code>:<br>
          <code>define myHmLGW HMUARTLGW 192.168.42.23</code><br>&nbsp;</li>
      <li>Entfernter HM-MOD-UART unter Verwendung von <code>socat</code> auf einem Raspberry Pi:<br>
          <code>define myRemoteHmUART HMUARTLGW uart://192.168.42.23:12345</code><br><br>
          Entfernter Raspberry Pi:<br><code>$ socat TCP4-LISTEN:12345,fork,reuseaddr /dev/ttyAMA0,raw,echo=0,b115200</code></li>
    </ul>
  </ul>
  <br>
  <a name="HMUARTLGW_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>close<br>
        Schlie&szlig;t die Verbindung zum Ger&auml;t.
        </li>
    <li><a href="#hmPairForSec">hmPairForSec</a></li>
    <li><a href="#hmPairSerial">hmPairSerial</a></li>
    <li>open<br>
        &Ouml;ffnet die Verbindung zum Ger&auml;t und initialisiert es.
        </li>
    <li>reopen<br>
        Schli&szlig;t und &ouml;ffnet die Verbindung zum Ger&auml;t und re-initialisiert es.
        </li>
    <li>restart<br>
        Rebootet das Ger&auml;t.
        </li>
    <li>updateCoPro &lt;/path/to/firmware.eq3&gt;<br>
        Aktualisierung der Koprozessor-Firmware (Reading D-firmware) mit der
        angegebenen Datei. Quelle f&uuml;r Firmware-Images (Version 1.4.1,
        offizielles eQ-3 Repository):<br>
        <ul>
            <li>HM-MOD-UART: <a href="https://raw.githubusercontent.com/eq-3/occu/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/HM-MOD-UART/coprocessor_update.eq3">coprocessor_update.eq3</a> (Version 1.4.1)</li>
            <li>HM-LGW-O-TW-W-EU: <a href="https://raw.githubusercontent.com/eq-3/occu/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/coprocessor_update_hm_only.eq3">coprocessor_update_hm_only.eq3</a> (Version 1.4.1)<br>
            Bitte zus&auml;tzlich sicherstellen, dass die Version der
            D-LANfirmware mindestens 1.1.5 betr&auml;gt. Um auf diese Version
            zu aktualisieren k&ouml;nnen die eQ-3 CLI Tools (siehe Wiki) oder
            der eQ-3 Netfinder genutzt werden. Das passende Image ist:
            <a href="https://github.com/eq-3/occu/raw/28045df83480122f90ab92f7c6e625f9bf3b61aa/firmware/hm-lgw-o-tw-w-eu_update.eq3">hm-lgw-o-tw-w-eu_update.eq3</a><br>
            <b>Die Datei hm-lgw-o-tw-w-eu_update.eq3 nicht mit updateCoPro flashen!</b></li>
        </ul>
        </li>
  </ul>
  <br>
  <a name="HMUARTLGW_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>assignIDs<br>
        Gibt die aktuell diesem IO-Ger&auml;t zugeordneten HomeMatic-Ger&auml;te
        zur&uuml;ck.
        </li>
  </ul>
  <br>
  <a name="HMUARTLGW_attr"></a>
  <b>Attribute</b>
  <ul>
    <li>csmaCa<br>
        Aktiviert oder deaktiviert CSMA/CA (Carrier sense multiple access with
        collision avoidance), auch bekannt als Listen-Before-Talk.<br>
        Default: 0 (deaktiviert)
        </li>
    <li>dummy<br>
        Erm&ouml;glicht die Definition des Ger&auml;ts ohne jegliche Interaktion
        mit einem physikalischen Ger&auml;t.<br>
        Default: nicht gesetzt
        </li>
    <li>dutyCycle<br>
        Aktiviert oder deaktiviert die &Uuml;berpr&uuml;fung des Arbeitszyklus
        (1%-Regel) durch das Sendemodul.<br>
        Die Abschaltung dieser Funktion kann in verschiedenen L&auml;ndern gegen
        das Gesetz verstossen, weshalb zuerst die Situation anhand lokaler
        Richtlinien zu pr&uuml;fen ist!<br>
        Default: 1 (aktiviert)
        </li>
    <li><a href="#hmId">hmId</a></li>
    <li><a name="HMLANhmKey">hmKey</a></li>
    <li><a name="HMLANhmKey2">hmKey2</a></li>
    <li><a name="HMLANhmKey3">hmKey3</a></li>
    <li>lgwPw<br>
        AES-Passwort f&uuml;r das eQ-3 HomeMatic Wireless LAN Gateway. Das initiale
        Passwort befindet sich auf der R&uuml;ckseite des Ger&auml;ts, kann aber
        durch den Benutzer ge&auml;ndert werden. Falls die AES gesicherte
        Kommunikation aktiviert ist (Auslieferungszustand), muss dieses Attribut
        auf den richtigen Wert gesetzt werden, da ansonsten keine Kommunikation
        m&ouml;glich ist. Zus&auml;tzlich muss das Perl-Modul Crypt::Rijndael
        (stellt den AES-Algorithmus bereit) installiert sein.
        </li>
    <li>loadEvents<br>
        Aktiviert die Erzeugung von Log-Nachrichten &uuml;ber die Funklast
        des Interfaces (in Prozent der erlaubten Sendezeit).

        Default: 0 (deaktiviert)
        </li>
    <li>logIDs<br>
        Aktiviert die gezielte Erzeugung von Log-Nachrichten. Der Parameter ist
        eine durch Komma getrennte Liste an HMIds oder HM Ger&auml;te-/Kanalnamen,
        deren Nachrichten aufgezeichnet werden sollen.<br>
        <ul>
            <li><i>all</i>: Zeichnet die Rohnachrichten aller HMIds auf</li>
            <li><i>sys</i>: Zeichnet Systemnachrichten (z.B. Keep-Alive) auf</li>
        </ul>
        Um alle m&ouml;glichen Nachrichten aufzuzeichnen, kann <i>all,sys</i>
        genutzt werden.
        </li>
    <li>qLen<br>
        Maximale Anzahl an Kommandos in der internen Warteschlange des
        HMUARTLGW-Moduls. Neue Kommandos werden verworfen, wenn die Warteschlange
        gef&uuml;llt ist. Jedes Kommando hat eine Lebensdauer von 3s, sobald es
        aktiv verarbeitet wird. Die Verz&ouml;gerung eines Kommandos betr&auml;gt
        im schlechtesten Fall also qLen * 3s (3 Minuten mit den Defaulteinstellungen).<br>
        Default: 60
        </li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
