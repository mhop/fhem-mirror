## no critic (Modules::RequireVersionVar,Policy::CodeLayout::RequireTidyCode) ##
# $Id$
# base module for KNX-communication
# idea: merge some functions of TUL- & KNXTUL-module into one and add more connectivity 
# function: M - multicast support (like in KNXTUL) - connect to knxd or KNX-router
#           T - tunnel (like TCP-mode of TUL) - connect to knxd
#           S - Socket mode - connect to unix-socket of knxd on localhost
#           H - unicast udp - connect to knxd or KNX-router
#           X - dummy mode as placeholder for FHEM2FHEM-IO 
# will never be supported: direct USB-connection to a TUL-USB-stick ( use TUL-Modul or use KNXD->USBstick)
# features: use DevIo where possible
#           use TcpServerUtils for multicast
#           FIFO - queing of incoming messages (less latency for fhem-system) read= ~4ms vs ~34ms with KNXTUL/TUL
#           discard duplicate incoming messages
#           more robust parser of incoming messages
################################################################################
### changelog:
# 19/10/2021 01.60 initial beta version
#            enable hostnames for mode H & T
# 05/11/2021 fix 'x' outside of string in unpack at ./FHEM/00_KNXIO.pm line 420 (Connection response)
# 30/11/2021 add long text to errorlist
#            add Log msg on invalid/discarded frames
# 15/12/2021 01.70 changed acpi decoding in cemi
#            add keepalive for mode-H
#            add support for FHEM2FHEM (mode X)
#            fix reopen on knxd crash/restart
# 28/02/2022 change MC support to TcpServerUtils - no need for IO::Socket::Multicast Module!
#            modified phyaddr internal- removed phyaddrnum
#            moved all hidden internals to $hash->{KNXIOhelpers}->{...}
# 31/03/2022 fixed typo on line 1106 (exits -> exists)
# 25/04/2022 changed 'state connected' logic (issue after handshake complete...)
# 25/05/2022 first SVN version
# 07/07/2022 cleanup, no functional changes
# 09/07/2022 fix IOdevice ready check on set-cmd (KNXIO_write)
# 01/09/2022 cleanup, simplify duplicate detection, perf improvements
#            unify Log msgs
# 13/11/2022 modify fifo logic
#            improve cmd-ref
# 05/12/2022 change parameter parsing in define
#            add renameFn - correct reading & attr IODev in KNX-devices after rename of KNXIO-device
#            change disabled handling
#            fix src-addr for Mode M,H
#            change internal PhyAddr to reabable format + range checking on define.
# 19/12/2022 cleanup
# 23/01/2023 cleanup, simplify _openDev
# 13/03/2023 PBP changes
#            replace cascading if..elsif with given
#            replace GP_Import: Devio,Tcpserver,HttpUtils with use stmts   
# 28/03/2023 cleanup
#            rework Logging, duplicate msg detection
# 04/04/2023 limit retries for keepalive timeouts
#            rework Logging
# 15/05/2023 new "<device>:INITIALIZED" event after sucessful start
#            change (shorten) timeout parameters on disconnect
#            cmd-ref: correct wiki links, W3C conformance
# 15/06/2023 move cmd KNX_scan from KNX- to KNXIO-Module
#            extra delay on KNX_scan after each 10th request
#            new attr enableKNXscan - trigger KNX_scan on startup and/or on every connect
#            update cmd-ref
# 13/07/2023 cleanup
#            moved KNX_scan function to KNX-Module, KNX_scan cmdline cmd into new Module 98_KNX_scan.pm
# 25/08/2023 reorg opendev for mode X
# 02/10/2023 Rate limit for write (set/get-cmd) from KNX-Modul
#            remove unused imports...
#            add $readingFnAttributes to AttrList
# 25/11/2023 performance tuning KNXIO_write
#            replace GP_export function
#            PBP cleanup -1
#            change regex's (unnecessary i)
# 22/12/2023 modify KNXIO_Ready fn
#            fix high load problem in _write2
#            add recovery on open Timeout - mode H
#            modify dipatch2/ processFIFO
#            new Attr KNXIOdebug - special debugging on Loglvl 1
# 26/12/2023 optimize write queue handling - high load
#            new: write flooding detection
# 20/01/2024 cmdref: KNXIOdebug attribute
#            feature add set cmds: connect, disconnect, restart
#            modify INITIALIZED logic
# 05/02/2024 modify write queing (mode H)
#            add a few debug msgs
# 25/04/2024 changed _open for mode S
#            replaced/removed experimental given/when
# 19/08/2024 fix error-msg when mode S fails to open


package KNXIO; ## no critic 'package'

use strict;
use warnings;
use IO::Socket;
use English qw(-no_match_vars);
use Time::HiRes qw(gettimeofday);
use DevIo qw(DevIo_OpenDev DevIo_SimpleWrite DevIo_SimpleRead DevIo_CloseDev DevIo_Disconnected DevIo_IsOpen);
use TcpServerUtils qw(TcpServer_Open TcpServer_SetLoopbackMode TcpServer_MCastAdd TcpServer_MCastRemove 
    TcpServer_MCastSend TcpServer_MCastRecv TcpServer_Close);
use HttpUtils qw(HttpUtils_gethostbyname ip2str);
use GPUtils qw(GP_Import); # Package Helper Fn

### perlcritic parameters
# these ones are NOT used! (constants,Policy::Modules::RequireFilenameMatchesPackage,NamingConventions::Capitalization)
# these ones are NOT used! (RegularExpressions::RequireDotMatchAnything,RegularExpressions::RequireLineBoundaryMatching)
# these ones are NOT used! (ControlStructures::ProhibitCascadingIfElse)
### the following percritic items will be ignored global ###
## no critic (NamingConventions::Capitalization)
## no critic (Policy::CodeLayout::ProhibitParensWithBuiltins)
## no critic (ValuesAndExpressions::RequireNumberSeparators,ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (ControlStructures::ProhibitPostfixControls)
## no critic (Documentation::RequirePodSections)

### import FHEM functions / global vars
### run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate readingsBeginUpdate readingsEndUpdate
          readingsBulkUpdate readingsBulkUpdateIfChanged
          Log3
          AttrVal AttrNum ReadingsVal ReadingsNum
          readingFnAttributes
          AssignIoPort IOWrite
          DoTrigger
          Dispatch
          defs attr
          selectlist readyfnlist 
          InternalTimer RemoveInternalTimer
          init_done
          IsDisabled IsDummy IsDevice
          devspec2array
          TimeNow)
    );
}

#####################################
# global vars/constants
my $PAT_IP   = '[\d]{1,3}(\.[\d]{1,3}){3}';
my $PAT_PORT = '[\d]{4,5}';
my $KNXID    = 'C';
my $reconnectTO = 10; # Waittime after disconnect
my $setcmds  = q{restart:noArg connect:noArg disconnect:noArg};
my $SVNID    = '$Id$'; ## no critic (Policy::ValuesAndExpressions::RequireInterpolationOfMetachars)

#####################################
sub main::KNXIO_Initialize {
	goto &Initialize;
}

sub Initialize {
	my $hash = shift;
	$hash->{DefFn}      = \&KNXIO_Define;
	$hash->{AttrFn}     = \&KNXIO_Attr;
	$hash->{ReadFn}     = \&KNXIO_Read;
	$hash->{ReadyFn}    = \&KNXIO_Ready;
	$hash->{WriteFn}    = \&KNXIO_Write;
	$hash->{RenameFn}   = \&KNXIO_Rename;
	$hash->{UndefFn}    = \&KNXIO_Undef;
	$hash->{ShutdownFn} = \&KNXIO_Shutdown;
	$hash->{SetFn}      = \&KNXIO_Set;

	$hash->{AttrList}   = 'disable:1 verbose:1,2,3,4,5 enableKNXscan:0,1,2 KNXIOdebug:1,2,3,4,5,6,7,8,9 ' . $readingFnAttributes;
	$hash->{Clients}    = 'KNX';
	$hash->{MatchList}  = { '1:KNX' => '^C.*' };

	return;
}

#####################################
### syntax: define <name> KNXIO <mode one of: M|S|H|T|X)> <hostip or hostname>:<port> <phy-address>
sub KNXIO_Define {
	my $hash = shift;
	my $def  = shift;

	my @arg = split(/[\s\t\n]+/xms,$def);
	my $name = $arg[0] // return 'KNXIO-define: no name specified';
	$hash->{NAME} = $name;
	$SVNID =~ s/.+[.]pm\s(\S+\s\S+).+/$1/ixms;
	$hash->{SVN} = $SVNID; # store svn info in dev hash

	if ((scalar(@arg) >= 3) && $arg[2] !~ /[HMSTX]/xms) {
		return q{KNXIO-define: invalid mode specified, valid modes are one of: H M S T X};
	}
	my $mode = uc($arg[2]);
	$hash->{model} = $mode; # use it also for fheminfo statistics

	# handle mode X for FHEM2FHEM configs
	return InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash) if ($mode eq q{X});

	return q{KNXIO-define syntax: "define <name> KNXIO <H|M|T> <ip-address|hostname>:<port> <phy-adress>" } . "\n" .
	       q{         or          "define <name> KNXIO S <pathToUnixSocket> <phy-address>" } if (scalar(@arg) < 5);

	my ($host,$port) = split(/[:]/xms,$arg[3]);

	if ($mode =~ /[MHT]/xms && $port !~ /$PAT_PORT/xms) {
		return q{KNXIO-define: invalid ip-address or port, correct syntax is: } .
		       q{"define <name> KNXIO <H|M|T> <ip-address|hostname>:<port> <phy-address>"};
	}

	if ($mode eq q{M}) { # multicast
		my $host1 = (split(/[.]/xms,$host))[0];
		return q{KNXIO-define: Multicast address is not in the range of 224.0.0.0 and 239.255.255.255 } .
		       q{(default is 224.0.23.12:3671) } if ($host1 < 224 || $host1 > 239);
		$hash->{DeviceName} = $host . q{:} . $port;
	}
	elsif ($mode eq q{S}) {
		$hash->{DeviceName} = 'UNIX:STREAM:' . $host; # $host= path to socket 
	}
	elsif ($mode =~ m/[HT]/xms) {
		if ($host !~ /$PAT_IP/xms) { # not an ip-address, lookup name
=begin comment
			# blocking variant !
			my $phost = inet_aton($host);
			return "KNXIO-define: host name $host could not be resolved" if (! defined($phost));
			$host = inet_ntoa($phost);
			return "KNXIO-define: host name could not be resolved" if (! defined($host));
=end comment
=cut
			# do it non blocking! - use HttpUtils to resolve hostname
			$hash->{PORT} = $port; # save port...
			$hash->{timeout} = 5; # TO for DNS req.
			$hash->{DNSWAIT} = 1;
			my $KNXIO_DnsQ = ::HttpUtils_gethostbyname($hash,$host,1,\&KNXIO_gethostbyname_Cb);
		}

		else {
			$hash->{DeviceName} = $host . q{:} . $port; # for DevIo
		}
	}

	my $phyaddr = (defined($arg[4]))?$arg[4]:'0.0.0';
	my $phytemp = KNXIO_hex2addr($phyaddr);
	$hash->{PhyAddr} = KNXIO_addr2hex($phytemp,2); #convert 2 times for correcting input!

	KNXIO_closeDev($hash) if ($init_done && exists($hash->{OLDDEF})); # modify definition....

	$hash->{devioLoglevel} = 4; #032023
	$hash->{devioNoSTATE}  = 1;

	$hash->{PARTIAL} = q{};
	# define helpers
	$hash->{KNXIOhelper}->{FIFO}      = []; # read fifo array
	$hash->{KNXIOhelper}->{FIFOW}     = []; # write fifo array

	# Devio-parameters
	$hash->{nextOpenDelay} = $reconnectTO;

	delete $hash->{NEXT_OPEN};
	RemoveInternalTimer($hash);

	KNXIO_Log ($name, 3, qq{opening mode=$mode});

	if (! $init_done) {
		return InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash);
	}
	return KNXIO_openDev($hash);
}

#####################################
sub KNXIO_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	if ($aName eq 'disable') {
		if ($cmd eq 'set' && defined($aVal) && $aVal == 1) {
			KNXIO_closeDev($hash);
		} elsif ($cmd eq 'del') {
			InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash);
		}
	}
	elsif ($cmd eq 'set' && $aName eq 'enableKNXscan' && defined($aVal) && $aVal !~ /[0-2]/xms) {
		return 'Allowed values: 0-2';
	}
	return;
}

#####################################
sub KNXIO_Read {
	my $hash = shift;
#	my $local = shift; #?

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	my $buf = undef;
	if ($mode eq 'M') {
		my ($rhost,$rport) = ::TcpServer_MCastRecv($hash, $buf, 1024);
	} else {
		$buf = ::DevIo_SimpleRead($hash);
	}
	if (!defined($buf) || length($buf) == 0) {
		KNXIO_Log ($name, 1, q{no data - disconnect});
		KNXIO_disconnect($hash);
		return;
	}

	return if IsDisabled($name); # moved after read function 8/2023

	KNXIO_Log ($name, 5, 'buf=' . unpack('H*',$buf));

	### process in indiv. subs
	my $readmodes = {
               H => \&KNXIO_ReadH,
               S => \&KNXIO_ReadST,
               T => \&KNXIO_ReadST,
               M => \&KNXIO_ReadM,
	};

	if (ref $readmodes->{$mode} eq 'CODE') {
		$readmodes->{$mode}->($hash, $buf);
		return;
	}

	KNXIO_Log ($name, 2, qq{failed - invalid mode $mode specified});
	return;
}

### Socket & Tunnel read
sub KNXIO_ReadST {
	my $hash = shift;
	my $buf  = shift;
	my $name = $hash->{NAME};

	$hash->{PARTIAL} .= $buf;
	my $msglen = unpack('n',$hash->{PARTIAL}) + 2;

	return if (length($hash->{PARTIAL}) < $msglen); # not enough data

	# buf complete, continue
	my @que = [];
	if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{})) { #get que from hash
		@que = @{$hash->{KNXIOhelper}->{FIFO}};
	}
	while (length($hash->{PARTIAL}) >= $msglen) {
		$buf = substr($hash->{PARTIAL},0,$msglen); # get one msg from partial
		$hash->{PARTIAL} = substr($hash->{PARTIAL}, $msglen); # put rest to partial

		my $outbuf = KNXIO_decodeEMI($hash,$buf);
		if ( defined($outbuf) ) {
			push(@que,$outbuf); # only valid packets!
		}
		if (length($hash->{PARTIAL}) >= 2) {
			$msglen = unpack('n',$hash->{PARTIAL}) + 2;
		}
	} # /while
	@{$hash->{KNXIOhelper}->{FIFO}} = @que; # push que to fifo
	return KNXIO_processFIFO($hash);
}

### multicast read
sub KNXIO_ReadM {
	my $hash = shift;
	my $buf  = shift;
	my $name = $hash->{NAME};

	$buf = $hash->{PARTIAL} . $buf if (defined($hash->{PARTIAL}));
	if (length($buf) < 6) { # min required for first unpack
		$hash->{PARTIAL} = $buf;
		return;
	}

	# header format: 0x06 - header size / 0x10 - KNXNET-IPVersion / 0x0530 - Routing Indicator / 0xYYYY - Header size + size of cEMIFrame
	my ($header, $header_routing, $total_length) = unpack('nnn',$buf);

	KNXIO_Log ($name, 5, 'header=' . sprintf('%04x',$header) . ' routing=' . sprintf('%04x',$header_routing) .
	          qq{ TotalLength= $total_length (dezimal)});

	if ($header != 0x0610 ) {
		KNXIO_Log ($name, 1, 'invalid header size or version');
		$hash->{PARTIAL} = undef; # delete all we have so far
#		KNXIO_disconnect($hash); #?
		return;
	}
	if (length($buf) < $total_length) {  #  6 Byte header + min 11 Byte data
		KNXIO_Log ($name,4, 'still waiting for complete packet (short packet length)');
		$hash->{PARTIAL} = $buf; # still not enough
		return;
	}
	else {
		$hash->{PARTIAL} = substr($buf,$total_length);
		$buf = substr($buf,0,$total_length);
	}

	##### now, the buf is complete check if routing-Frame
	if (($header_routing == 0x0530) && ($total_length >= 17)) {  #  6 Byte header + min 11 Byte data
		# this is the correct frame type, process it now
		$buf = substr($buf,6); # strip off header
		my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
		return KNXIO_dispatch($hash,$cemiRes) if (defined($cemiRes));
		return;
	}
	elsif ($header_routing == 0x0531) { # routing Lost Message
		KNXIO_Log ($name, 3, 'a routing-lost packet was received !!! - Problems with bus or KNX-router ???');
	}
	elsif ($header_routing == 0x0201) { # search request
		KNXIO_Log ($name, 4, 'a search-request packet was received');
	}
	else {
		KNXIO_Log ($name, 4, q{a packet with unsupported service type } .
		          sprintf('%04x',$header_routing) . q{ was received. - discarded});
	}
	return;
} # /multicast

#####################################
### host mode read
# packet 06 10 0206 0014 02 00 08 01 c0a8 0ae8 0e 57 04 04 00f7 - conn response: 0014 - total len / 02 - commchannel / 00 - statusoode / 08 - struc-len / 01 protocol=UDP IPV4 / xxxx xxxx - IP & port /
# packet 06 10 0209 0010 02 01 08 01 c0a8 0ae8 0e 57 - disconn requ!
# header format: 0x06 - header size / 0x10 - KNXNET-IPVersion / 0x0201 - type / 08 - struct length / 01 - protocol=UDP IPV4 / size of cEMIFrame
sub KNXIO_ReadH {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};

	if ( unpack('n',$buf) != 0x0610) {
		KNXIO_Log ($name, 3, 'invalid Frame Header received - discarded');
		return;
	}

	my $msg = undef; # holds data to send
	my $ccid = 0;
	my $rxseqcntr = 0;
	my $txseqcntr = 0;
	my $errcode = 0;
	my $responseID = unpack('x2n',$buf);

	my %resIDs = (
	   0x0202 => sub { # Search response
		KNXIO_Log ($name, 4, 'SearchResponse received');
		my (@contolpointIp, $controlpointPort) =  unpack('x6CCCn',$buf);
		return;
	   },
	   0x0204 => sub {  # Decription response
		KNXIO_Log ($name, 4, 'DescriptionResponse received');
		return;
	   },
	   0x0206 => sub { # Connection response
		($hash->{KNXIOhelper}->{CCID},$errcode) = unpack('x6CC',$buf); # save Comm Channel ID,errcode
		RemoveInternalTimer($hash,\&KNXIO_keepAlive);
		if ($errcode > 0) {
			KNXIO_Log ($name, 3, q{ConnectionResponse received } .
				qq{CCID= $hash->{KNXIOhelper}->{CCID} Status=} . KNXIO_errCodes($errcode));
			KNXIO_disconnect($hash,2);
			return;
		}
		my $phyaddr = unpack('x18n',$buf);
		$hash->{PhyAddr} = KNXIO_addr2hex($phyaddr,2); # correct Phyaddr.

		KNXIO_handleConn($hash);
		$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0;
		InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash); # start keepalive
		return;
	   },
	   0x0208 => sub { # ConnectionState response
		($hash->{KNXIOhelper}->{CCID}, $errcode) = unpack('x6CC',$buf);
		RemoveInternalTimer($hash,\&KNXIO_keepAlive);
		RemoveInternalTimer($hash,\&KNXIO_keepAliveTO); # reset timeout timer
		if ($errcode > 0) {
			KNXIO_Log ($name, 3, q{ConnectionStateResponse received } .
				qq{CCID= $hash->{KNXIOhelper}->{CCID} Status= } . KNXIO_errCodes($errcode));
			KNXIO_disconnect($hash,2);
			return;
		}
		InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash);
		return;
	   },
	   0x0209 => sub { # Disconnect request
		KNXIO_Log ($name, 4, ' DisconnectRequest received, restarting connection');
		$ccid = unpack('x6C',$buf);
		$msg = pack('nnnCC',(0x0610,0x020A,8,$ccid,0));
		::DevIo_SimpleWrite($hash,$msg,0); # send disco response
		$msg = KNXIO_prepareConnRequ($hash);
		return $msg;
	   },
	   0x020A => sub { # Disconnect response
		 KNXIO_Log ($name, 4, 'DisconnectResponse received - sending connrequ');
		$msg = KNXIO_prepareConnRequ($hash);
		return $msg;
	   },
	   0x0420 => sub { # Tunnel request
		($ccid,$rxseqcntr) = unpack('x7CC',$buf);

		my $discardFrame = undef;
		my $cntrdiff = $rxseqcntr - $hash->{KNXIOhelper}->{SEQUENCECNTR};
		if ($cntrdiff == -1) {
			KNXIO_Log ($name, 3, q{TunnelRequest duplicate message received: } .
				qq{(seqcntr= $rxseqcntr ) - ack it});
			$discardFrame = 1; # one packet duplicate... we ack it but do not process
		}
		elsif ($cntrdiff != 0) { # really out of sequence
			KNXIO_Log ($name, 3, q{TunnelRequest messaage out of sequence received: } .
				qq{(seqcntrRx= $rxseqcntr seqcntrTx= $hash->{KNXIOhelper}->{SEQUENCECNTR} ) - no ack & discard});
			return;
		}
		KNXIO_Log ($name, 4, q{TunnelRequest received - send Ack and decode. } .
			qq{seqcntrRx= $hash->{KNXIOhelper}->{SEQUENCECNTR}} ) if (! defined($discardFrame));
		my $tacksend = pack('nnnCCCC',0x0610,0x0421,10,4,$ccid,$rxseqcntr,0); # send ack
		$hash->{KNXIOhelper}->{SEQUENCECNTR} =  ($rxseqcntr + 1) % 256;
		::DevIo_SimpleWrite($hash,$tacksend,0);
		return if ($discardFrame); # duplicate frame

		#now decode & send to clients
		$buf = substr($buf,10); # strip off header (10 bytes)
		my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
		return if (! defined($cemiRes));
		KNXIO_dispatch($hash,$cemiRes);
		return;
	   },
	   0x0421 => sub { # Tunneling Ack
		($ccid,$txseqcntr,$errcode) = unpack('x7CCC',$buf);
		if ($errcode > 0) {
			KNXIO_Log ($name, 3, qq{Tunneling Ack received CCID= $ccid txseq= $txseqcntr Status= } . KNXIO_errCodes($errcode));
#what next ?
		}
		$hash->{KNXIOhelper}->{SEQUENCECNTR_W} = ($txseqcntr + 1) % 256;
		KNXIO_Debug ($name, 1, q{Tunnel ack received } . sprintf('%02x', $txseqcntr));
		RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO); # all ok, stop timer
		return;
	   },
	); # %resIDs

	if (exists($resIDs{$responseID})) {
		$msg = &{$resIDs{$responseID}} ($buf);
	} else {
		KNXIO_Log ($name, 3, 'invalid response received: ' . unpack('H*',$buf));
		return;
	}

	::DevIo_SimpleWrite($hash,$msg,0) if(defined($msg)); # send msg
	return;
}

#####################################
sub KNXIO_Ready {
	my $hash = shift;
	my $name = $hash->{NAME};

	return if (! $init_done || exists($hash->{DNSWAIT}) || IsDisabled($name) == 1);
	return if (ReadingsVal($name, 'state', q{}) eq 'connected' );
	if (exists($hash->{NEXT_OPEN}) ) { # avoid open loop
		InternalTimer($hash->{NEXT_OPEN},\&KNXIO_openDev,$hash);
	} else {
		KNXIO_openDev($hash);
	}
	return;
}

#####################################
sub KNXIO_Write {
	my $hash = shift;
	my $fn   = shift;
	my $msg  = shift;

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	KNXIO_Log ($name, 5, 'started');
	return if(!defined($fn) && $fn ne $KNXID);
	if (ReadingsVal($name, 'state', 'disconnected') ne 'connected') {
		KNXIO_Log ($name, 3, qq{called while not connected! Msg: $msg lost});
		return;
	}

	KNXIO_Log ($name, 5, qq{sending $msg});

	my $acpivalues = {r => 0x00, p => 0x01, w => 0x02};

	if ($msg =~ /^([rwp])([\da-f]{5})(.*)$/ixms) { # msg format: <rwp><grpaddr><message>
		my $acpi = $acpivalues->{$1}<<6;
#		my $tcf  = ($acpivalues->{$1}>>2 & 0x03); # not needed!
		my $dst = KNXIO_hex2addr($2);
		my $str = $3 // '00'; # undef on read requ
		my $src = KNXIO_hex2addr($hash->{PhyAddr});

		my $data = 0;
		if (length($str) > 2) {
			$data = pack ('CH*',$acpi,substr($str,2)); # multi byte write/reply
		}
		else {
			$data = pack('C',$acpi + (hex($str) & 0x3f)); # single byte write/reply or read
		}

		my $datasize = length($data);

		KNXIO_Log ($name, 5, q{data=} . unpack('H*', $data) .
		          sprintf(' size=%d acpi=%02x src=%s dst=%s', $datasize, $acpi,
 		          KNXIO_addr2hex($src,2), KNXIO_addr2hex($dst,3)));

		my $completemsg = q{};

		if ($mode =~ /^[ST]$/xms ) {  #format: size | 0x0027 | dst | 0 | data
			$completemsg = pack('nnnC',$datasize + 5,0x0027,$dst,0) . $data;
		}
		elsif ($mode eq 'M') {
			$completemsg = pack('nnnnnnnCC',0x0610,0x0530,$datasize + 16,0x2900,0xBCE0,
			               $src,$dst,$datasize,0) . $data; # use src addr
		}
		else { # $mode eq 'H'
			# total length= $size+20 - include 2900BCEO,src,dst,size,0
			$completemsg = pack('nnnCCCCnnnnCC',0x0610,0x0420,$datasize + 20,4,
			               $hash->{KNXIOhelper}->{CCID},$hash->{KNXIOhelper}->{SEQUENCECNTR_W},
			               0,0x1100,0xBCE0,$src,$dst,$datasize,0) . $data; # send TunnelInd
		}

		## rate limit
		push(@{$hash->{KNXIOhelper}->{FIFOW}}, $completemsg);
		return KNXIO_Write2($hash);
	}
	KNXIO_Log ($name, 2, qq{Could not send message $msg});
	return;
}

### handle send que and send control msg-rate
sub KNXIO_Write2 {
	my $hash = shift;

	my $count = scalar(@{$hash->{KNXIOhelper}->{FIFOW}});
	RemoveInternalTimer($hash, \&KNXIO_Write2);
	return if($count == 0);

	my $name = $hash->{NAME};
	my $timenow = gettimeofday();
	my $nextwrite = $hash->{KNXIOhelper}->{nextWrite} // $timenow;
	my $adddelay = 0.07;

	if ($nextwrite > $timenow) {
		KNXIO_Log ($name, 3, qq{frequent IO-write - msg-count= $count}) if ($count % 10 == 0);
		KNXIO_Debug ($name, 1, qq{frequent IO-write - msg-count= $count});
		InternalTimer($nextwrite + $adddelay, \&KNXIO_Write2,$hash);
		InternalTimer($timenow + 30.0, \&KNXIO_Flooding,$hash) if ($count == 1);
		return;
	}

	$hash->{KNXIOhelper}->{nextWrite} = $timenow + $adddelay;
	my $msg = shift(@{$hash->{KNXIOhelper}->{FIFOW}});

	my $ret = 0;
	my $mode = $hash->{model};
	my $gadoffset; # offset to gad in msg - debug only
	my $dataoffset; # offset to data in msg - debug only
	if ($mode eq 'H') {
		# replace sequence counterW
		substr($msg,8,1) = pack('C',$hash->{KNXIOhelper}->{SEQUENCECNTR_W}); ##no critic (BuiltinFunctions::ProhibitLvalueSubstr)
#		$msg = substr($msg,0,8) . pack('C',$hash->{KNXIOhelper}->{SEQUENCECNTR_W}) . substr($msg,9); # w.o. LvalueSubstr PBP !

		$ret = ::DevIo_SimpleWrite($hash,$msg,0);

		# Timeout function - expect TunnelAck within 1 sec! - but if fhem has a delay....
		$hash->{KNXIOhelper}->{LASTSENTMSG} = unpack('H*',$msg); # save msg for resend in case of TO
		InternalTimer($timenow + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		$gadoffset = 16;
		$dataoffset = $gadoffset + 4;
	}
	elsif ($mode eq 'M') {
		$ret = ::TcpServer_MCastSend($hash,$msg);
		$gadoffset = 12;
		$dataoffset = $gadoffset + 4;
	}
	else { # mode ST
		$ret = ::DevIo_SimpleWrite($hash,$msg,0);
		$gadoffset = 4;
		$dataoffset = $gadoffset + 3;
	}

	$count--;
	if ($count > 0) {
		InternalTimer($timenow + $adddelay, \&KNXIO_Write2,$hash);
	}
	else {
		RemoveInternalTimer($hash, \&KNXIO_Flooding);
	}
	KNXIO_Log ($name, 5, qq{Mode= $mode buf=} . unpack('H*',$msg) . qq{ rc= $ret});
	KNXIO_Debug ($name, 1, q{IO-write processed- gad= } . KNXIO_addr2hex(unpack('n',substr($msg,$gadoffset,2)),3) .
	                       q{ msg= } . unpack('H*',substr($msg,$dataoffset)) . qq{ msg-remain= $count});
	return;
}

## called by _write2 via timer when number of write cmds exceed limits 
sub KNXIO_Flooding {
	my $hash = shift;

	my $name = $hash->{NAME};
	my $count = scalar(@{$hash->{KNXIOhelper}->{FIFOW}});
	KNXIO_Log ($name, 1, q{number of write cmds exceed limits of KNX-Bus});
# consequence ?
#	KNXIO_Log ($name, 1, q{number of write cmds exceed limits of KNX-Bus: } . qq{$count messages deleted});
#	$hash->{KNXIOhelper}->{FIFOW} = []; # ?
	return;
}

#####################################
## a FHEM-rename changes the internal IODev of KNX-dev's,
## but NOT the reading IODev & attr IODev
## both reading and attr will be changed here!
sub KNXIO_Rename {
	my $newname = shift;
	my $oldname = shift;

	if (! IsDevice($newname,'KNXIO')) {
		KNXIO_Log ($oldname, 1, qq{$newname is not a KNXIO device!});
		return;
	}
	KNXIO_Log ($oldname, 3, qq{device $oldname renamed to $newname});

	#check if any reading IODev has still the old KNXIO name...
	my @KNXdevs = devspec2array('TYPE=KNX:FILTER=r:IODev=' . $oldname);
	foreach my $KNXdev (@KNXdevs) {
		next if (! IsDevice($KNXdev)); # devspec error!
		readingsSingleUpdate($defs{$KNXdev},'IODev',$newname,0);
		my $logtxt = qq{reading IODev -> $newname};
		if (AttrVal($KNXdev,'IODev',q{}) eq $oldname) {
			delete ($attr{$KNXdev}->{IODev});
			$logtxt .= q{, attr IODev -> deleted!};
		}
		KNXIO_Log ($KNXdev, 3, qq{device change: $logtxt});
	}
	return;
}

#####################################
sub KNXIO_Undef {
	my $hash = shift;

	return KNXIO_Shutdown($hash);
}

###################################
sub KNXIO_Shutdown {
	my $hash = shift;

	return KNXIO_closeDev($hash);
}

###################################
## connect, disconnect, restart
sub KNXIO_Set {
	my $hash = shift;
	my $name = shift;
	my $cmd  = shift;

	my $adddelay = 1.0;

	if (!defined($cmd)) { return q{no arg specified for set cmd}; }
	if ($cmd eq q{?}) { return qq{unknown argument $cmd choose one of $setcmds}; }
	if ($cmd eq q{disconnect}) { return KNXIO_closeDev($hash); }
	if ($cmd eq q{connect}) {
		if (ReadingsVal($name,'state','disconnected') eq 'connected') {
			return qq{$name is connected, no action taken};
		}
		elsif (AttrVal($name,'disable',0) == 1) {
			return qq{$name is disabled, no action taken};
		}
	}
	elsif ($cmd eq q{restart}) {
		KNXIO_closeDev($hash);
		$adddelay = 5.0;
	}
	else {
		return qq{invalid set cmd $cmd};
	}

	InternalTimer(gettimeofday() + $adddelay, \&KNXIO_openDev, $hash);
	return;
}

###################################
### functions called from DevIo ###
###################################

### return from open (sucess/failure)
sub KNXIO_callback {
	my $hash = shift;
	my $err = shift;

	$hash->{nextOpenDelay} = $reconnectTO;
	if (defined($err)) {
		KNXIO_Log ($hash, 2, qq{device open $hash->{NAME} failed with: $err}) if ($err);
		$hash->{NEXT_OPEN} = gettimeofday() + $hash->{nextOpenDelay};
	}
	return;
}

###################################
######## private functions ########
###################################

### called from define-HttpUtils_gethostbynam when hostname needs to be resolved
### process callback from HttpUtils_gethostbyname
sub KNXIO_gethostbyname_Cb {
	my $hash  = shift;
	my $error = shift;
	my $dhost = shift;

	my $name  = $hash->{NAME};
	delete $hash->{timeout};
	delete $hash->{DNSWAIT};
	if ($error) {
		delete $hash->{DeviceName};
		delete $hash->{PORT};
		KNXIO_Log ($name, 1, qq{hostname could not be resolved: $error});
		return  qq{KNXIO-define: hostname could not be resolved: $error};
	}
	my $host = ::ip2str($dhost);
	KNXIO_Log ($name, 3, qq{DNS query result= $host});
	$hash->{DeviceName} = $host . q{:} . $hash->{PORT};
	delete $hash->{PORT};
	return;
}

### called from define - after init_complete
### return undef on success
sub KNXIO_openDev {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	return if (IsDisabled($name) == 1);

	return KNXIO_openDevX($hash) if ($mode eq q{X});

	if (exists $hash->{DNSWAIT}) {
		$hash->{DNSWAIT} += 1;
		if ($hash->{DNSWAIT} > 5) {
			KNXIO_Log ($name, 2, q{DNS failed, check ip/hostname});
			return;
		}
		InternalTimer(gettimeofday() + 1,\&KNXIO_openDev,$hash);
		KNXIO_Log ($name, 2, q{waiting for DNS});
		return; # waiting for DNS
	}
	return if (! exists($hash->{DeviceName})); # DNS failed !

	my $reopen = (exists($hash->{NEXT_OPEN}))?1:0;
	my $param = $hash->{DeviceName}; # ip:port or UNIX:STREAM:<socket param>
	my ($host, $port, $spath) = split(/[:]/xms,$param);

	KNXIO_Log ($name, 5, qq{$mode , $host , $port , reopen= $reopen});

	my $ret = undef; # result
	delete $hash->{stacktrace}; # clean start

	if ($mode eq q{M}) { ### multicast support via TcpServerUtils
		delete $hash->{TCPDev}; # devio ?
		$ret = ::TcpServer_Open($hash, $port, $host, 1);
		if (defined($ret)) { # error
			KNXIO_Log ($name, 2, qq{can't connect: $ret}) if(!$reopen);
			return qq{KNXIO_openDev ($name): can't connect: $ret};
		}
		$ret = ::TcpServer_MCastAdd($hash,$host);
		if (defined($ret)) { # error
			KNXIO_Log ($name, 2, qq{MC add failed: $ret});
			return qq{KNXIO_openDev ($name): MC add failed: $ret};
		}

		::TcpServer_SetLoopbackMode($hash,0); # disable loopback

		delete $hash->{NEXT_OPEN};
		delete $readyfnlist{"$name.$param"};
		$ret = KNXIO_init($hash);
	}

	if ($mode eq q{S}) { ### socket mode
		if (!(-S -r -w $spath) ) {
			KNXIO_Log ($name, 2, q{Socket not available - (knxd running?)});
			$ret = qq{KNXIO_openDev ($name): Socket not available - (knxd running?)};
		}
		else {
			$ret = ::DevIo_OpenDev($hash,$reopen,\&KNXIO_init); # no callback
		}
	}

	if ($mode eq q{H}) { ### host udp
		my $conn = 0;
		$conn = IO::Socket::INET->new(PeerAddr => "$host:$port", Type => SOCK_DGRAM, Proto => 'udp', Reuse => 1);
		if (!($conn)) {
			KNXIO_Log ($name, 2, qq{can't connect: $ERRNO}) if(!$reopen);
			KNXIO_disconnect($hash);
			readingsSingleUpdate($hash, 'state', 'disconnected', 1);
			return;
		}
		delete $hash->{NEXT_OPEN};
		delete $hash->{DevIoJustClosed}; # DevIo
		$conn->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);
		$hash->{TCPDev} = $conn;
		$hash->{FD} = $conn->fileno();
		delete $readyfnlist{"$name.$param"};
		$selectlist{"$name.$param"} = $hash;

		readingsSingleUpdate($hash, 'state', 'opened', 1);
		KNXIO_Log ($name, 3, ($reopen)?'reappeared':'opened');
		$ret = KNXIO_init($hash);
	}

	if ($mode eq q{T}) { ### tunneling TCP
		$ret = ::DevIo_OpenDev($hash,$reopen,\&KNXIO_init,\&KNXIO_callback);
	}

	if(defined($ret) && $ret) {
		KNXIO_Log ($name, 1, q{Cannot open device - ignoring it});
		KNXIO_closeDev($hash);
	}

	return $ret;
}

### called from define - after init_complete for mode X
### return undef on success
sub KNXIO_openDevX {
	my $hash = shift;
	my $name = $hash->{NAME};

	my @f2flist = devspec2array('TYPE=FHEM2FHEM'); # get F2F devices
	foreach my $f2fdev (@f2flist) {
		next if (IsDevice($f2fdev) == 0); # no F2Fdevice found
		my $rawdev = $defs{$f2fdev}->{rawDevice};
		next if (IsDevice($rawdev,'KNXIO') == 0);
		next if ($rawdev ne $name);
		KNXIO_init($hash);
		return;
	}
	readingsSingleUpdate($hash, 'state', 'disconnected', 1);
	return qq{KNXIO_openDevX ($name): open failed};
}

### called from DevIo_open or KNXIO_openDev after sucessful open
sub KNXIO_init {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	$hash->{KNXIOhelper}->{FIFO}  = []; # read fifo array
	$hash->{KNXIOhelper}->{FIFOW} = []; # write fifo array

	if ($mode =~ m/[ST]/xms) {
		my $opengrpcon = pack('nnnC',(5,0x26,0,0)); # KNX_OPEN_GROUPCON
		::DevIo_SimpleWrite($hash,$opengrpcon,0);
	}

	elsif ($mode eq 'H') {
		my $connreq = KNXIO_prepareConnRequ($hash);
		::DevIo_SimpleWrite($hash,$connreq,0);
		InternalTimer(gettimeofday() + 2, \&KNXIO_openTO, $hash);
	}

	# state 'connected' is set in decode_EMI (model ST) or in readH (model H)  
	else {
		KNXIO_handleConn($hash);
	}

	return;
}

### handle 'connected event' & state: connected
###
sub KNXIO_handleConn {
	my $hash = shift;

	my $name = $hash->{NAME};
	RemoveInternalTimer($hash, \&KNXIO_openTO) if ($hash->{model} eq q{H});

	if (exists($hash->{KNXIOhelper}->{startdone})) {
		KNXIO_Log ($name, 3, q{connected});
		readingsSingleUpdate($hash, 'state', 'connected', 1);
		main::KNX_scan('TYPE=KNX:FILTER=IODev=' . $name) if (AttrNum($name,'enableKNXscan',0) >= 2); # on every connect
	}
	else { # fhem start
		KNXIO_Log ($name, 3, q{initial-connect});
		readingsSingleUpdate($hash, 'state', 'connected', 0); # no event
		InternalTimer(gettimeofday() + 30, \&KNXIO_initcomplete, $hash);
	}
	return;
}

### provide <device> INITIALIZED event
### called for KNXIO_define ONLY on FHEM start!
### by Internaltimer with significant delay
sub KNXIO_initcomplete {
	my $hash = shift;

	RemoveInternalTimer($hash,\&KNXIO_initcomplete);
	my $name = $hash->{NAME};
	if (ReadingsVal($name,'state','disconnected') eq 'connected') {
		main::KNX_scan('TYPE=KNX:FILTER=IODev=' . $name) if (AttrNum($name,'enableKNXscan',0) >= 1); # on 1st connect only
		$hash->{KNXIOhelper}->{startdone} = 1;
		DoTrigger($name,'INITIALIZED');
		readingsSingleUpdate($hash, 'state', 'connected', 1); # now do event
	}
	elsif (AttrVal($name,'disable', 0) != 1) {
		 KNXIO_Log ($name, 3, q{failed});
	}
	return;
}

### prepare connection request
### called from init, disconn response, disconn request
### returns packed string, ready for sending with DevIo
sub KNXIO_prepareConnRequ {
	my $hash = shift;

	### host protocol address information see 3.8.2 core docu
	###  hdr-size | Host Prococol code (01=udp/02=TCP) | Dest-IPAddr (4bytes) | IP port (2bytes) | hpais (8) | hpaid (8) | ctype (4) 
#	my $hpais = pack('nC4n',(0x0801,@srchost,$srcport)); # source - can be 0 (for NAT translation !
	my $hpais = pack('nCCCCn',(0x0801,0,0,0,0,0)); # source - can be 0 (for NAT translation !
#	my $hpaid = pack('nC4n',(0x0801,@desthost,$destport)); # dest we can use port 3671 for data endpoint too!
	my $hpaid = pack('nCCCCn',(0x0801,0,0,0,0,0)); # dest can be 0,0
	my $ctype = pack('CCCC',(4,4,2,0)); # 04040200 for udp tunnel_connection/Tunnel_linklayer

	my $connreq = pack('nnn',0x0610,0x0205,0x1A) . $hpais . $hpaid . $ctype;
	$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0; # read requests
	$hash->{KNXIOhelper}->{SEQUENCECNTR_W} = 0; # write requests
	RemoveInternalTimer($hash,\&KNXIO_keepAliveTO); # reset timeout timer
	RemoveInternalTimer($hash,\&KNXIO_keepAlive);

	return $connreq;
}

### handle fifo and send to KNX-Module via dispatch
# all decoding already done in decode_CEMI / decode_EMI
sub KNXIO_dispatch {
	my $hash = shift;
	my $buf = shift;

	my @que = [];
	@que = @{$hash->{KNXIOhelper}->{FIFO}} if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{}));
	push (@que,$buf);
	@{$hash->{KNXIOhelper}->{FIFO}} = @que;

	return KNXIO_processFIFO($hash);
}

### called from FIFO TIMER
sub KNXIO_dispatch2 {
##	my ($hash, $outbuf ) = ($_[0]->{h}, $_[0]->{m});
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};

	$hash->{'msg_count'}++;
	$hash->{'msg_time'} = TimeNow();

	Dispatch($hash, $buf);

	KNXIO_processFIFO($hash);
	return;
}

### fetch msgs from FIFO and call dispatch
sub KNXIO_processFIFO {
	my $hash = shift;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash,\&KNXIO_processFIFO);

	my @que = @{$hash->{KNXIOhelper}->{FIFO}};
	my $queentries = scalar(@que);
	if ($queentries > 1) { # delete any duplicates
		my $queentriesOld = $queentries;
		@que = KNXIO_deldupes(@que);
		$queentries = scalar(@que);
		my $qdiff = $queentriesOld - $queentries;
		KNXIO_Log ($name, 3, qq{deleted $qdiff duplicate msgs from queue, $queentries remain}) if ($qdiff > 0);;
	}

	if ($queentries > 0) { # process timer is not running & fifo not empty
		my $msg = shift (@que);
		@{$hash->{KNXIOhelper}->{FIFO}} = @que;
		KNXIO_Log ($name, 4, qq{dispatching buf=$msg Nr_msgs=$queentries});
		KNXIO_dispatch2($hash, $msg);
		if ($queentries > 1) {
			InternalTimer(gettimeofday() + 0.05, \&KNXIO_processFIFO, $hash); # allow time for new/duplicate msgs to be read
		}
		return;
	}
	KNXIO_Log ($name, 5, q{finished});
	return;
}

### delete any duplicates in an array
### ref: https://perlmaven.com/unique-values-in-an-array-in-perl
### input: array, return: array
sub KNXIO_deldupes {
	my @arr = @_;

	my %seen;
	return grep { !$seen{substr($_,6) }++ } @arr; # ignore C<src-addr>
}

### disconnect and wait for nxt open
## second param specifies optional open delay (sec)
sub KNXIO_disconnect {
	my $hash = shift;
	my $opendelay = shift // $reconnectTO;

	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	::DevIo_Disconnected($hash);

	KNXIO_Log ($name, 1, q{disconnected, waiting to reappear});

	$readyfnlist{"$name.$param"} = $hash; # Start polling
	$hash->{NEXT_OPEN} = gettimeofday() + $opendelay;

	return;
}

###
sub KNXIO_closeDev {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	if ($hash->{model} eq 'M') {
		::TcpServer_Close($hash,0);
	}
	else {
		::DevIo_CloseDev($hash);
		$hash->{TCPDev}->close() if($hash->{FD});
	}

	delete $hash->{stacktrace}; # clean
	delete $hash->{nextOpenDelay};
	delete $hash->{'msg_count'};
	delete $hash->{'msg_time'};

#NO!	delete $hash->{'.CCID'};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR_W};

	RemoveInternalTimer($hash);

	KNXIO_Log ($name, 3, q{closed}) if ($init_done);;

	readingsSingleUpdate($hash, 'state', 'disconnected', 1);

	return;
}


###################################
######## Helper functions  ########
###################################

### format: length(2) | id(2) | srcaddr(2) |  dstaddr(2) | acpi(1) | data(n) |
### input: $hash, $buf(packed)
### ret: buf - format for dispatch / undef on error
sub KNXIO_decodeEMI {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};

	my ($len, $id, $src, $dst, $acpi, @data) = unpack('nnnnCC*',$buf);
	if (($len + 2) != length($buf)) {
		KNXIO_Log ($name, 4, qq{buffer length mismatch $len } . length($buf) - 2);
		return;
	}
	if ($id != 0x0027) {
		if ($id == 0x0026) {
			KNXIO_Log ($name, 4, 'OpenGrpCon response received');
			KNXIO_handleConn($hash);
		}
		else {
			KNXIO_Log ($name, 3, 'invalid message code ' . sprintf('%04x',$id));
		}
		return;
	}

	KNXIO_Log ($name, 4, q{src=} . KNXIO_addr2hex($src,2) . q{ - dst=} . KNXIO_addr2hex($dst,3) . q{ - leng=} .
	          scalar(@data) . q{ - data=} . sprintf('%02x' x scalar(@data),@data));

	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,1); # always a Group addr

	# acpi ref: KNX System Specs 03.03.07
	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) {
		KNXIO_Log ($name, 3, 'no valid acpi-code (read/reply/write) received, discard packet');
		KNXIO_Log ($name, 4, qq{discarded packet: src=$src dst=$dst acpi=} . sprintf('%02x',$acpi) .
		          q{ length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1

	my $outbuf = $KNXID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	KNXIO_Log ($name, 5, qq{outbuf=$outbuf});

	return $outbuf;
}

### CEMI decode
# format: message code(1) | AddInfoLen(1) | [Addinfo(x)] | ctrl1(1) | ctrl2[1) | srcaddr(2) |  dstaddr(2) | datalen(1) | tpci(1) | acpi/data(1) | [data(n) |
# input: $hash, $buf(packed) (w.o length) 
# ret: buf - format for dispatch / undef on error
sub KNXIO_decodeCEMI {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};
	my ($mc, $addlen) = unpack('CC',$buf);
	if ($mc != 0x29 && $mc != 0x2e) {
		KNXIO_Log ($name, 4, 'wrong MessageCode ' . sprintf('%02x',$mc) . ', discard packet');
		return;
	}

	$addlen += 2;
	my ($ctrlbyte1, $ctrlbyte2, $src, $dst, $tcf, $acpi, @data) = unpack('x' . $addlen . 'CCnnCCC*',$buf);

	if (($ctrlbyte1 & 0xF0) != 0xB0) { # standard frame/no repeat/broadcast - see 03_06_03 EMI_IMI specs
		KNXIO_Log ($name, 4, 'wrong ctrlbyte1 ' . sprintf('%02x',$ctrlbyte1) . ', discard packet');
		return;
	}
	my $prio = ($ctrlbyte1 & 0x0C) >>2; # priority
	my $dest_addrType = ($ctrlbyte2 & 0x80) >> 7; # MSB  0 = indiv / 1 = group
	my $hop_count = ($ctrlbyte2 & 0x70) >> 4; # bits 6-4

	if ($tcf != scalar(@data)) { # $tcf: number of NPDU octets, TPCI octet not included!
		KNXIO_Log ($name, 4, 'Datalength not consistent');
		return;
	}

	my $srcd = KNXIO_addr2hex($src,2); # always a phy-address
	my $dstd = KNXIO_addr2hex($dst,$dest_addrType + 2);

	KNXIO_Log ($name, 4, qq{src=$srcd dst=$dstd destaddrType=$dest_addrType prio=$prio hop_count=$hop_count } .
              q{length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));

	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) { # not a groupvalue-read/write/reply
		KNXIO_Log ($name, 3, 'no valid acpi-code (read/reply/write) received - discard packet - programming?');
		KNXIO_Log ($name, 4, qq{discarded packet: src=$srcd dst=$dstd destaddrType=$dest_addrType prio=$prio hop_count=} .
		          qq{$hop_count length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,$dest_addrType);

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1

	my $outbuf = $KNXID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	KNXIO_Log ($name, 5, qq{outbuf=$outbuf});

	return $outbuf;
}

### convert address from number to hex-string or display name ($type=2 & 3) 
sub KNXIO_addr2hex {
	my $adr = shift;
	my $type = shift // 0;  # 1 & 3 if GA-address, else physical address

	return sprintf('%02x%01x%02x', ($adr >> 11) & 0x1f, ($adr >> 8) & 0x7, $adr & 0xff) if ($type == 1);
	return sprintf('%d/%d/%d',($adr >> 11) & 0x1f, ($adr >> 8) & 0x7, $adr & 0xff) if ($type == 3);
	return sprintf('%d.%d.%d', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff) if ($type == 2); # for display
	return sprintf('%02x%01x%02x', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff);
}

### convert address from hex-string (5 digits) to number
sub KNXIO_hex2addr {
	my $str = shift;
	my $isphy = shift // 0;

	if ($str =~ m/([\da-f]{2})([\da-f])([\da-f]{2})/ixms) {
		return (hex($1) << 12) + (hex($2) << 8) + hex($3) if ($isphy == 1); # Phy addr
		return (hex($1) << 11) | (hex($2) << 8) | hex($3); # GA Addr
	}
	elsif ($str =~ m/([\d]+)[.]([\d]+)[.]([\d]+)/xms) {
		return (($1 << 12) & 0x00F000) + (($2 << 8) & 0x0F00) + ($3 & 0x00FF); # phy Addr - limit values!
	}
	return 0;
}

### keep alive for mode H - every minute
# triggered on conn-response & connstate response
# 2nd param is undef unless called from KNXIO_keepAliveTO
sub KNXIO_keepAlive {
	my $hash = shift;
	my $cntrTO = shift // 0; #retry counter

	my $name = $hash->{NAME};
	$hash->{KNXIOhelper}->{CNTRTO} = $cntrTO;

	KNXIO_Log ($name, 5, q{send conn state request - expect connection state response});

	my $msg = pack('nnnCCnnnn',(0x0610,0x0207,16,$hash->{KNXIOhelper}->{CCID},0, 0x0801,0,0,0));
	RemoveInternalTimer($hash,\&KNXIO_keepAlive);
	::DevIo_SimpleWrite($hash,$msg,0); #  send conn state requ
	InternalTimer(gettimeofday() + 2,\&KNXIO_keepAliveTO,$hash); # set timeout timer - reset by ConnectionStateResponse
	return;
}

### keep alive timeout
sub KNXIO_keepAliveTO {
	my $hash = shift;

	my $name = $hash->{NAME};
	my $cntrTO = $hash->{KNXIOhelper}->{CNTRTO};

	return KNXIO_disconnect($hash,3) if ($cntrTO >= 2); # nr of timeouts exceeded

	$cntrTO++;
	KNXIO_Log ($name, 3, qq{timeout - retry $cntrTO});
	KNXIO_keepAlive($hash,$cntrTO);
	return;
}

### TO hit while sending...
sub KNXIO_TunnelRequestTO {
	my $hash = shift;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO);
	# try resend...but only once
	if (exists($hash->{KNXIOhelper}->{LASTSENTMSG})) {
		KNXIO_Log ($name, 3, 'timeout - attempt resend');
		my $msg = pack('H*',$hash->{KNXIOhelper}->{LASTSENTMSG});
		::DevIo_SimpleWrite($hash,$msg,0);
		delete $hash->{KNXIOhelper}->{LASTSENTMSG};
		InternalTimer(gettimeofday() + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		return;
	}

	KNXIO_Log ($name, 3, 'timeout - sending disconnect request');

	# send disco request
	my $hpai = pack('nCCCCn',(0x0801,0,0,0,0,0));
	my $msg = pack('nnnCC',(0x0610,0x0209,16,$hash->{KNXIOhelper}->{CCID},0)) . $hpai;
	::DevIo_SimpleWrite($hash,$msg,0);
	return;
}

### handle opentimeout for mode H
sub KNXIO_openTO {
	my $hash = shift;

	KNXIO_Log ($hash, 3, q{open timeout occured, attempt retry});
	KNXIO_closeDev($hash);
	InternalTimer(gettimeofday() + $reconnectTO,\&KNXIO_openDev,$hash);
	return;
}

### unified Log handling
### calling param: same as Log3: hash/name/undef, loglevel, logtext
### prependes device, subroutine, linenr. to Log msg
### return undef
sub KNXIO_Log {
	my $dev    = shift // 'global';
	my $loglvl = shift // 5;
	my $logtxt = shift;

	my $name = ( ref($dev) eq 'HASH' ) ? $dev->{NAME} : $dev;
	my $dloglvl = AttrNum($name,'verbose',undef) // AttrNum('global','verbose',3);
	return if ($loglvl > $dloglvl); # shortcut performance

	my $sub  = (caller(1))[3] // 'main';
	$sub = (caller(2))[3] if ($sub =~ /ANON/xms); # anonymous sub
	my $line = (caller(0))[2];
	$sub =~ s/^.+[:]+//xms;

	Log3 ($name, $loglvl, qq{$name [$sub $line]: $logtxt});
	return;
}

### Logging in debug mode
### attr KNXIOdebug triggered
### calling param: same as Log3: hash/name/undef, loglevel, logtext but loglvl is debug lvl
### return undef
sub KNXIO_Debug {
	my $dev    = shift // 'global';
	my $loglvl = shift // 0;
	my $logtxt = shift;

	my $name = ( ref($dev) eq 'HASH' ) ? $dev->{NAME} : $dev;
	return if ($loglvl != AttrNum($name,'KNXIOdebug',99));

	Log3 ($name, 0, qq{$name DEBUG$loglvl>> $logtxt});
	return;
}

### translate Error-codes to text
### copied from 03_08_01 & 03_08_02_Core document
### all i know...
sub KNXIO_errCodes {
	my $errcode = shift;

	my $errlist = {0=>'NO_ERROR',1=>'E_HOST_PROTCOL',2=>'E_VERSION_NOT_SUPPORTED',4=>'E_SEQUENCE_NUMBER',33=>'E_CONNECTION_ID',
            34=>'E_CONNECT_TYPE',35=>'E_CONNECTION_OPTION',36=>'E_NO_MORE_CONNECTIONS',38=>'E_DATA_CONNECTION',39=>'E_KNX_CONNECTION',
            41=>'E_TUNNELLING_LAYER',
        };
	# full text
	my $errlistfull = {0=>'OK',
             1=>'The requested host protocol is not supported by the KNXnet/IP device',
             2=>'The requested protocol version is not supported by the KNXnet/IP device',
             4=>'The received sequence number is out of order',
            33=>'The KNXnet/IP Server device cannot find an active data connection with the specified ID',
            34=>'The requested connection type is not supported by the KNXnet/IP Server device',
            35=>'One or more requested connection options are not supported by the KNXnet/IP Server device',
            36=>'The KNXnet/IP Server device cannot accept the new data connection because its maximum amount of concurrent connections is already occupied',
            38=>'The KNXnet/IP Server device detects an error concerning the data connection with the specified ID',
            39=>'The KNXnet/IP Server device detects an error concerning the KNX subnetwork connection with the specified ID',
            41=>'The KNXnet/IP Server device does not support the requested KNXnet/IP Tunnelling layer',
        };

	my $errtxt = $errlist->{$errcode};
	return 'E_UNDEFINED_ERROR ' . $errcode if (! defined($errtxt));
	$errtxt .= q{: } . $errlistfull->{$errcode}; # concatenate both textsegments
	return $errtxt;
}


1;
__END__

=pod

=encoding utf8

=item [device]
=item summary IO-module for KNX-devices supporting UDP, TCP & socket connections
=item summary_DE IO-Modul f&uuml;r KNX-devices. Unterst&uuml;tzt UDP, TCP & Socket Verbindungen

=begin html

<a id="KNXIO"></a>
<h3>KNXIO</h3>
<ul>
<li><p>This is a IO-module for KNX-devices. It provides an interface between FHEM and a KNX-Gateway. 
   The Gateway can be either a KNX-Router/KNX-GW or the KNXD-daemon.
   FHEM KNX-devices use this module as IO-Device. This Module does <b>NOT</b> support the deprecated EIB-Module!
</p>
<p>A (german) wiki page is avaliable here&colon; <a href="https://wiki.fhem.de/wiki/KNXIO">FHEM Wiki</a></p>
</li>
<li><a id="KNXIO-define"></a><strong>Define</strong>
<pre><code>define &lt;name&gt; KNXIO (H|M|T) &lt;(ip-address|hostname)&colon;port&gt; &lt;phy-adress&gt;</code>
<code>define &lt;name&gt; KNXIO S &lt;UNIX socket-path&gt; &lt;phy-adress&gt;</code>
<code>define &lt;name&gt; KNXIO X</code></pre>

<b>Connection Type (mode)</b> (first parameter)&colon;
<ul>
<li><b>H</b> Host Mode - connect to a KNX-router with UDP point-point protocol.<br/>
  This is the mode also used by ETS when you specify <b>KNXNET/IP</b> as protocol. You do not need a KNXD installation. 
  The protocol is complex and timing critical! 
  If you have delays in FHEM processing close to 1 sec, the protocol may disconnect. It should recover automatically, 
  however KNX-messages could have been lost! 
  <br>The benefit of this protocol&colon; every sent and received msg has to be acknowledged within 1 second by the 
  communication partner, msg delivery is verified!
</li>
<li><b>M</b> Multicast mode - connect to KNXD's or KNX-router's multicast-tree.<br/>
  This is the mode also used by ETS when you specify <b>KNXNET/IP Routing</b> as protocol. 
  If you have a KNX-router that supports multicast, you do not need a KNXD installation. 
  Default address&colon;port is 224.0.23.12&colon;3671<br/>
  Pls. ensure that you have only <b>one</b> GW/KNXD in your LAN that feed the multicast tree!<br/>
  If you run FHEM in Docker, note that multicast is not supported in network-mode bridge, but macvlan supports multicast.
</li>
<li><b>T</b> TCP mode - uses a TCP-connection to KNXD (default port&colon; 6720).<br/>
  This mode is the successor of the TUL-modul, but does not support direct Serial/USB connection to a TPUart-USB Stick.
  If you want to use a TPUart-USB Stick or any other serial KNX-GW, 
  connect the USB-Stick to KNXD and use modes M,S or T to connect to KNXD.
</li>
<li><b>S</b> Socket mode - communicate via KNXD's UNIX-socket on localhost. default Socket-path&colon; 
  <code>/var/run/knx</code><br/> 
  Path might be different, depending on knxd-version or -config specification! 
  This mode is tested ok with KNXD version 0.14.30. It does NOT work with ver. 0.10.0!
</li>
<li><b>X</b> Special mode - for details see KNXIO-wiki!
</li>
</ul>
<br/>
<b>ip-address&colon;port</b> or <b>hostname&colon;port</b>
<ul>
<li>Hostname is supported for mode H and T. Port definition is mandatory.</li>
</ul>
<br/>
<b>phy-address</b>
<ul>
<li>The physical address is used as the source address of messages sent to KNX network. 
  Valid range: &lt;0-15.0-15.0-255&gt;. 15.15.255 should not be used, is used as mfg-default for "non-configured".
  This address should be one of the defined client pool-addresses of KNXD (-E parameter) or Router.</li>
</ul>

<br/>All parameters are mandatory. Pls. ensure that you only have <b>one path</b> between your KNX-Installation and FHEM! 
  Do not define multiple KNXIO- or KNXTUL- or TUL-definitions at the same time.
<pre>Examples&colon;
<code>    define myKNXGW KNXIO H 192.168.1.201&colon;3671 0.0.51
    define myKNXGW KNXIO M 224.0.23.12&colon;3671 0.0.51 
    define myKNXGW KNXIO S /var/run/knx 0.0.51
    define myKNXGW KNXIO T 192.168.1.200&colon;6720 0.0.51

Suggested parameters for KNXD (Version &gt;= 0.14.30), with systemd&colon;
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -S -b ip&colon;"                 # knxd acts as multicast client - do NOT use -R !
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -R -S -b ipt&colon;192.168.xx.yy"           # connect to a knx-router with ip-addr
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -R -S -single -b tpuarts&colon;/dev/ttyxxx" # connect to a serial/USB KNX GW  
  The -e and -E parameters must match the definitions in the KNX-router (set by ETS)!
</code></pre> 
</li>

<li><a id="KNXIO-set"></a><strong>Set</strong><br/>
<ul>
<li><a id="KNXIO-set-disconnect"></a><b>disconnect</b> - Stop any communication with KNX-bus.<br/>
  Difference to <code>attr &lt;device&gt; disable 1</code>: set cmds are volatile, attributes are saved in config!</li> 
<li><a id="KNXIO-set-connect"></a><a id="KNXIO-set-restart"></a>
  <b>connect</b> or <b>restart</b> - Start or Stop-&gt;5 seconds delay-&gt;Start KNX-bus communication.<br/></li>
</ul><br/></li>

<li><a id="KNXIO-get"></a><strong>Get</strong> - No Get command implemented<br/><br/></li>

<li><a id="KNXIO-attr"></a><strong>Attributes</strong><br/>
<ul>
<li><a id="KNXIO-attr-disable"></a><b>disable</b> - 
  Disable the device if set to <b>1</b>. No send/receive from bus possible. Delete this attr to enable device again.</li>
<li><a id="KNXIO-attr-verbose"></a><b>verbose</b> - 
  increase verbosity of Log-Messages, system-wide default is set in "global" device. 
  For a detailed description see&colon; <a href="#verbose">global-attr verbose</a> <br/></li> 
<li><a id="KNXIO-attr-enableKNXscan"></a><b>enableKNXscan</b> -
  trigger a KNX_scan cmd at fhemstart or at every connected event. A detailed description of the 
  <a href="#KNX-utilities">KNX_scan cmd</a> is here!
<pre><code>   0 - never         (default if Attr not defined)
   1 - on fhem start (after &lt;device&gt;&colon;INITIALIZED event)
   2 - on fhem start and on every &lt;device&gt;&colon;connected event</code></pre></li>  
<li><a id="KNXIO-attr-KNXIOdebug"></a><b>KNXIOdebug</b> -
  Log specific events/conditions independent of verbose Level. - use only on developer advice. 
  Parameters are numeric (1-9), usage may change with every new version!<br/></li>
</ul>
<br/></li>

<li><a id="KNXIO-events"></a><strong>Events</strong><br/>
<ul>
<li><b>&lt;device&gt;&colon;INITIALIZED</b> -
  The first &lt;device&gt;&colon;connected event after fhem start is suppressed and replaced (after 30 sec delay) 
  with this event.
  It can be used (in a notify,doif,...) to syncronize the status of FHEM-KNX-devices with the KNX-Hardware.
  Do not use the <code>global&colon;INITIALIZED</code> event for this purpose, the KNX-GW is not ready for 
  communication at that time!<br/>
  Example&colon;<br/>
  <code>defmod KNXinit_nf notify &lt;device&gt;&colon;INITIALIZED get &lt;KNX-device&gt; &lt;gadName&gt;</code> 
  # or even simpler, just use Attribute&colon; <br/>
  <code>attr &lt;device&gt; enableKNXscan 1</code> # to scan all KNX-devices which have this device defined 
  as their IO-device.</li>
<li><b>&lt;device&gt;&colon;connected</b> -
  triggered if connection to KNX-GW/KNXD is established.</li>
<li><b>&lt;device&gt;&colon;disconnected</b> -
  triggered if connection to KNX-GW/KNXD failed.</li>
</ul>
</li>
</ul>

=end html

=cut
