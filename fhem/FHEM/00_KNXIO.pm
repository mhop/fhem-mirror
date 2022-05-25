##############################################
# $Id$
# new base module for KNX-communication
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
#
##############################################
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


package FHEM::KNXIO; ## no critic 'package'

use strict;
use warnings;
use IO::Socket;
use TcpServerUtils;
use English qw(-no_match_vars);
use Time::HiRes qw(gettimeofday);
use DevIo qw(DevIo_OpenDev DevIo_SimpleWrite DevIo_SimpleRead DevIo_CloseDev DevIo_Disconnected DevIo_IsOpen);
use English qw(-no_match_vars);
use GPUtils qw(GP_Import GP_Export); # Package Helper Fn

### perlcritic parameters
# these ones are NOT used! (constants,Policy::Modules::RequireFilenameMatchesPackage,Modules::RequireVersionVar,NamingConventions::Capitalization)
### the following percritic items will be ignored global ###
## no critic (ValuesAndExpressions::RequireNumberSeparators,ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (RegularExpressions::RequireDotMatchAnything,RegularExpressions::RequireLineBoundaryMatching)
## no critic (ControlStructures::ProhibitPostfixControls)
### no critic (ControlStructures::ProhibitCascadingIfElse)
## no critic (Documentation::RequirePodSections)

### import FHEM functions / global vars
### run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate readingsBulkUpdate readingsBulkUpdateIfChanged readingsBeginUpdate readingsEndUpdate
          Log3
          AttrVal ReadingsVal ReadingsNum setReadingsVal
          AssignIoPort IOWrite
          CommandDefine CommandDelete CommandModify CommandDefMod
          DevIo_OpenDev DevIo_SimpleWrite DevIo_SimpleRead DevIo_CloseDev DevIo_Disconnected DevIo_IsOpen
          TcpServer_Open TcpServer_SetLoopbackMode TcpServer_MCastAdd TcpServer_MCastRemove TcpServer_MCastSend TcpServer_MCastRecv TcpServer_Close
          DoTrigger
          Dispatch
          defs modules attr
          HttpUtils_gethostbyname ip2str
          readingFnAttributes
          selectlist readyfnlist 
          InternalTimer RemoveInternalTimer
          init_done
          IsDisabled IsDummy IsDevice
          deviceEvents devspec2array
          AnalyzePerlCommand EvalSpecials
          TimeNow)
    );

# export to main context
GP_Export(qw(Initialize 
             KNXIO_openDev KNXIO_init KNXIO_callback
       )
    );
}


#####################################
# global vars/constants
my $PAT_IP   = '[\d]{1,3}(\.[\d]{1,3}){3}';
my $PAT_PORT = '[\d]{4,5}';
my $TULID    = 'C';
my $reconnectTO = 30; #01.70 Waittime after disconnect

#####################################
sub Initialize {
	my $hash = shift;
	$hash->{DefFn}      = \&KNXIO_Define;
#	$hash->{SetFn}      = "KNXIO_Set";
#	$hash->{GetFn}      = "KNXIO_Get";
	$hash->{AttrFn}     = \&KNXIO_Attr;
	$hash->{ReadFn}     = \&KNXIO_Read;
	$hash->{ReadyFn}    = \&KNXIO_Ready;
#	$hash->{NotifyFn}   = \&KNXIO_Notify; # no need for... 
	$hash->{WriteFn}    = \&KNXIO_Write;
	$hash->{UndefFn}    = \&KNXIO_Undef;
	$hash->{ShutdownFn} = \&KNXIO_Shutdown;
#	$hash->{DeleteFn}   = "KNXIO_Delete";
#	$hash->{DelayedShutdownFn} = "KNXIO_DelayedShutdown;
#	$hash->{FingerprintFn}     = \&KNXIO_FingerPrint; # temp disabled

	$hash->{AttrList}   = "disable:1 verbose:1,2,3,4,5";
	$hash->{Clients}    = "KNX";
	$hash->{MatchList}  = { "1:KNX" => "^C.*" };

	return;
}

#####################################
### syntax: define <name> KNXIO <mode one of: M|S|H|T)> <hostip or hostname>:<port> <phy-address>
sub KNXIO_Define {
	my $hash = shift;
	my $def  = shift;
	my @arg = split(/[\s\t\n]+/x,$def);
	my $name = $arg[0] // return "KNXIO: no name specified";

	if (scalar(@arg >=3) && $arg[2] eq 'X') { #01.70 dummy for FHEM2FHEM configs
		$hash->{NAME}  = $name;
		$hash->{model} = $arg[2];
		return;
	}

	return q{KNXIO-define syntax: "define <name> KNXIO <H|M|T> <ip-address|hostname>:<port> <phy-adress>" } . "\n" . 
               q{         or          "define <name> KNXIO S <pathToUnixSocket> <phy-adress>" } if (scalar(@arg < 5));

	my $mode = $arg[2];

	return q{KNXIO-define: invalid mode specified, valid modes are one of: H M S T} if ($mode !~ /[MSHT]/ix);
	$hash->{model} = $mode; # use it also for fheminfo statistics

	my ($host,$port) = split(/[:]/ix,$arg[3]);

	return q{KNXIO-define: invalid ip-address or port, correct syntax is: "define <name> KNXIO <H|M|T> <ip-address|name>:<port> <phy-adress>"} if ($mode =~ /[MHT]/ix && $port !~ /$PAT_PORT/ix);

	if (exists($hash->{OLDDEF})) { # modify definition....
		KNXIO_closeDev($hash);
	}

	if ($mode eq q{M}) { # multicast
		my $host1 = (split(/\./ix,$host))[0];
		return q{KNXIO-define: Multicast address is not in the range of  224.0.0.0 and 239.255.255.255 (default is 224.0.23.12:3671) } if ($host1 < 224 || $host1 > 239);
		$hash->{DeviceName} = $host . q{:} . $port;
	}
	elsif ($mode eq q{S}) {
		$hash->{DeviceName} = 'UNIX:STREAM:' . $host; # $host= path to socket 
	}
	elsif ($mode =~ m/[HT]/ix) {
		if ($host !~ /$PAT_IP/ix) { # not an ip-address, lookup name
=pod
			# blocking variant !
			my $phost = inet_aton($host);
			return "KNXIO_define: host name $host could not be resolved" if (! defined($phost));
			$host = inet_ntoa($phost);
			return "KNXIO_define: host name could not be resolved" if (! defined($host));
=cut
			# do it non blocking! - use HttpUtils to resolve hostname
			$hash->{PORT} = $port; # save port...
			$hash->{timeout} = 5; # TO for DNS req.
			$hash->{DNSWAIT} = 1;
			my $KNXIO_DnsQ = HttpUtils_gethostbyname($hash,$host,1,\&KNXIO_gethostbyname_Cb);
		}

		else {
			$hash->{DeviceName} = $host . q{:} . $port; # for DevIo
		}
	}

	$hash->{NAME}      = $name;
	my $phyaddr        = (defined($arg[4]))?$arg[4]:'0.0.0'; 
	$hash->{PhyAddr}   = sprintf('%05x',KNXIO_hex2addr($phyaddr));

	KNXIO_closeDev($hash) if ($init_done);

	$hash->{PARTIAL} = q{};
	# define helpers
	$hash->{KNXIOhelper}->{FIFO}      = q{}; # read fifo
	$hash->{KNXIOhelper}->{FIFOTIMER} = 0;
	$hash->{KNXIOhelper}->{FIFOMSG}   = q{};

	# Devio-parameters
	$hash->{nextOpenDelay} = $reconnectTO;

	delete $hash->{NEXT_OPEN};
	RemoveInternalTimer($hash);

	Log3($name, 3, "KNXIO_define: opening device $name mode=$mode");

	return InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash);
}

#####################################
sub KNXIO_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	if ($aName eq 'disable') {
		if ($cmd eq 'set' && defined($aVal) && $aVal == 1) {
			KNXIO_closeDev($hash);
		} else {
			CommandModify(undef, "-silent $name $hash->{DEF}"); # do a defmod ...
		}
	}
	return;
}

#####################################
sub KNXIO_Read {
	my $hash = shift;
#	my $local = shift; #?

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	return if IsDisabled($name);

	my $buf = undef;
	if ($mode eq 'M') {
		my ($rhost,$rport) = TcpServer_MCastRecv($hash, $buf, 1024);
	} else {
		$buf = DevIo_SimpleRead($hash);
	}
	if (!defined($buf) || length($buf) == 0) {
		Log3($name,1, 'KNXIO_Read: no data - disconnect');
		KNXIO_disconnect($hash);
		return;
	}

	Log3( $name, 5, 'KNXIO_Read: buf= ' . unpack('H*',$buf));

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

	Log3 $name, 2,"KNXIO_Read failed - invalid mode $mode specified";
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
	my @que = ();
	@que = @{$hash->{KNXIOhelper}->{FIFO}} if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{})); #get que from hash
	while (length($hash->{PARTIAL}) >= $msglen) {
		$buf = substr($hash->{PARTIAL},0,$msglen); # get one msg from partial
		$hash->{PARTIAL} = substr($hash->{PARTIAL}, $msglen); # put rest to partial

		Log3($name, 5,'KNXIO_Read Rawbuf: ' . unpack('H*',$buf));

		my $outbuf = KNXIO_decodeEMI($hash,$buf);
		if ( defined($outbuf) ) {
			push(@que,$outbuf); # only valid packets!
		}
		if (length($hash->{PARTIAL}) >= 2) {
			$msglen = unpack('n',$hash->{PARTIAL}) + 2;
		}
	} # /while
	$hash->{KNXIOhelper}->{FIFO} = \@que; # push que to fifo
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
	my ($header, $header_routing, $total_length) = unpack("nnn",$buf);

	Log3 $name, 5, 'KNXIO_Read: -header=' . sprintf("%04x",$header) . ', -routing=' . sprintf("%04x",$header_routing) . ", TotalLength= $total_length \(dezimal\)" ;

	if ($header != 0x0610 ) {
		Log3($name, 1, 'KNXIO_Read: invalid header size or version');
		$hash->{PARTIAL} = undef; # delete all we have so far
#		KNXIO_disconnect($hash); #?
		return;
	}
	if (length($buf) < $total_length) {  #  6 Byte header + min 11 Byte data
		Log3($name,4, 'KNXIO_Read: still waiting for complete packet (short packet length)');
		$hash->{PARTIAL} = $buf; # still not enough
		return;
	}
	else {
		$hash->{PARTIAL} = substr($buf,$total_length);
		$buf = substr($buf,0,$total_length);
	}

###temp disabled		$buf = KNXIO_chkDupl2($hash,$buf);

	##### now, the buf is complete check if routing-Frame
	if (($header_routing == 0x0530) && ($total_length >= 17)) {  #  6 Byte header + min 11 Byte data
		# this is the correct frame type, process it now
		Log3($name, 5,'KNXIO_Read Rawbuf: ' . unpack('H*',$buf));

		$buf = substr($buf,6); # strip off header
		my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
		return if (! defined($cemiRes));
		return KNXIO_dispatch($hash,$cemiRes);
	}
	elsif ($header_routing == 0x0531) { # routing Lost Message
		Log3 $name, 3, 'KNXIO_Read: a routing-lost packet was received !!! - Problems with bus or KNX-router ???';
		return;
	}
	elsif ($header_routing == 0x0201) { # search request
		return; # ignore with silence
	}
	else {
		Log3 $name, 4, 'KNXIO_Read: a packet with unsupported service type ' . sprintf("%04x",$header_routing) . ' was received. - discarded';
		return;
	}

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
		Log3($name, 3, 'KNXIO_Read: invalid Frame Header received - discarded');
		return;
	}

	my $msg = undef; # holds data to send
	my $ccid = 0;
	my $rxseqcntr = 0;
	my $txseqcntr = 0;
	my $errcode = 0;
	my $responseID = unpack('x2n',$buf);

	# handle most frequent id's first
	if ( $responseID == 0x0420) { # Tunnel request 
		($ccid,$rxseqcntr) = unpack('x7CC',$buf);

		my $discardFrame = undef;
		if ($rxseqcntr == ($hash->{KNXIOhelper}->{SEQUENCECNTR} - 1)) {
			Log3($name, 3, 'KNXIO_Read: TunnelRequest received: duplicate message received (seqcntr=' . $rxseqcntr .') - ack it');
			$hash->{KNXIOhelper}->{SEQUENCECNTR}--; # one packet duplicate... we ack ist but do not process
			$discardFrame = 1;
		}
		if ($rxseqcntr != $hash->{KNXIOhelper}->{SEQUENCECNTR}) { # really out of sequence
			Log3($name, 3, 'KNXIO_Read: TunnelRequest received: out of sequence, (seqcntrRx=' . $rxseqcntr . ' (seqcntrTx=' . $hash->{KNXIOhelper}->{SEQUENCECNTR} . '- no ack & discard');
			return;
		}
		Log3($name, 4, 'KNXIO_Read: TunnelRequest received - send Ack and decode. seqcntrRx=' . $hash->{KNXIOhelper}->{SEQUENCECNTR} ) if (! defined($discardFrame));
		my $tacksend = pack('nnnCCCC',0x0610,0x0421,10,4,$ccid,$hash->{KNXIOhelper}->{SEQUENCECNTR},0); # send ack
		$hash->{KNXIOhelper}->{SEQUENCECNTR}++;
		$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0 if ($hash->{KNXIOhelper}->{SEQUENCECNTR} > 255);
		DevIo_SimpleWrite($hash,$tacksend,0);

		return if ($discardFrame); # duplicate frame

		#now decode & send to clients 
		Log3($name, 5,'KNXIO_Read Rawbuf: ' . unpack('H*',$buf));

		$buf = substr($buf,10); # strip off header (10 bytes)
		my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
		return if (! defined($cemiRes));

		return KNXIO_dispatch($hash,$cemiRes);
	}
	elsif ( $responseID == 0x0421) { # Tunneling Ack
		($ccid,$txseqcntr,$errcode) = unpack('x7CCC',$buf);
		if ($errcode > 0) {
			Log3($name, 3, 'KNXIO_Read: Tunneling Ack received ' . 'CCID=' . $ccid . ' txseq=' . $txseqcntr . (($errcode)?' - Status= ' . KNXIO_errCodes($errcode):q{}));
#what next ?
		}

		$hash->{KNXIOhelper}->{SEQUENCECNTR_W}++;
		$hash->{KNXIOhelper}->{SEQUENCECNTR_W} = 0 if ($hash->{KNXIOhelper}->{SEQUENCECNTR_W} > 255);
		RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO); # all ok, stop timer
	}
	elsif ( $responseID == 0x0202) { # Search response
		Log3($name, 4, 'KNXIO_Read: SearchResponse received');
		my (@contolpointIp, $controlpointPort) = unpack('x6CCCn',$buf);
#Log3 $name, 5, "H-read cpIP= $contolpointIp[0]\.$contolpointIp[1]\.$contolpointIp[2]\.$contolpointIp[3] port= $controlpointPort";
	}
	elsif ( $responseID == 0x0204) { # Decription response
		Log3($name, 4, 'KNXIO_Read: DescriptionResponse received');
	}
	elsif ( $responseID == 0x0206) { # Connection response
		($hash->{KNXIOhelper}->{CCID},$errcode) = unpack('x6CC',$buf); # save Comm Channel ID,errcode

		RemoveInternalTimer($hash,\&KNXIO_keepAlive);
		if ($errcode > 0) {
			Log3($name, 3, 'KNXIO_Read: ConnectionResponse received ' . 'CCID=' . $hash->{KNXIOhelper}->{CCID} . ' Status=' . KNXIO_errCodes($errcode));
			KNXIO_disconnect($hash);
			return;
		}
		my $phyaddr = unpack('x18n',$buf);
		$hash->{PhyAddr}       = sprintf('%05x',$phyaddr); # correct Phyaddr.

		readingsSingleUpdate($hash, "state", "connected", 1);

		InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash); # start keepalive

		$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0;
	}
	elsif ( $responseID == 0x0208) { # ConnectionState response
		($hash->{KNXIOhelper}->{CCID}, $errcode) = unpack('x6CC',$buf); 
		RemoveInternalTimer($hash,\&KNXIO_keepAlive);
		RemoveInternalTimer($hash,\&KNXIO_keepAliveTO); # reset timeout timer
		if ($errcode > 0) {
			Log3($name, 3, 'KNXIO_Read: ConnectionStateResponse received ' . 'CCID=' . $hash->{KNXIOhelper}->{CCID}  . ' Status=' . KNXIO_errCodes($errcode));
			KNXIO_disconnect($hash);
			return;
		}
		InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash);
	}
	elsif ( $responseID == 0x0209) { # Disconnect request
		Log3($name, 4, 'KNXIO_Read: DisconnectRequest received, restarting connenction');

		$ccid = unpack('x6C',$buf); 
		$msg = pack('nnnCC',(0x0610,0x020A,8,$ccid,0));
		DevIo_SimpleWrite($hash,$msg,0); # send disco response 

		$msg = KNXIO_prepareConnRequ($hash);
	}
	elsif ( $responseID == 0x020A) { # Disconnect response
		Log3($name, 4, 'KNXIO_Read: DisconnectResponse received - sending connrequ');
#$attr{$name}{verbose} = 3; # temp
		$msg = KNXIO_prepareConnRequ($hash);
	}
	else {
		Log3 $name, 3, 'KNXIO_Read: invalid response received: ' . unpack('H*',$buf);
		return;
	}

	DevIo_SimpleWrite($hash,$msg,0) if(defined($msg)); # send msg
	return;
}

#####################################
sub KNXIO_Ready {
	my $hash = shift;
	my $name = $hash->{NAME};

	return if (! $init_done || exists($hash->{DNSWAIT}) || IsDisabled($name) == 1);
	return if (exists($hash->{NEXT_OPEN}) && $hash->{NEXT_OPEN} > gettimeofday()); #01.70 avoid open loop 
#	return KNXIO_openDev($hash) if(ReadingsVal($hash, 'state', q{}) ne 'connected');
	return KNXIO_openDev($hash) if(ReadingsVal($hash, 'state', 'disconnected') eq 'disconnected');
	return;
}

#####################################
sub KNXIO_Write {
	my $hash = shift;
	my $fn   = shift;
	my $msg  = shift;

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	Log3 $name, 5, 'KNXIO_write: started';
	return if(!defined($fn) && $fn ne $TULID);
	if ($hash->{STATE} ne 'connected') {
		Log3 $name, 3, "KNXIO_write called while not connected! Msg: $msg lost";
		return;
	}
#	return if( ReadingsVal($name,'state','connected') eq 'disconnected');

	Log3 $name, 5, "KNXIO_write: sending $msg";

	my $acpivalues = {r => 0x00, p => 0x01, w => 0x02};

	if ($msg =~ /^([rwp])([0-9a-f]{5})(.*)$/ix) { # msg format: <rwp><grpaddr><message>

		my $acpi = $acpivalues->{$1}<<6;
		my $tcf  = ($acpivalues->{$1}>>2 & 0x03);
		my $dst = KNXIO_hex2addr($2);
		my $str = $3;
		my $src = KNXIO_hex2addr($hash->{PhyAddr});

		#convert hex-string to array with dezimal values
		my @data =  map {hex()} $str =~ /(..)/xg; # PBP 9/2021
		$data[0] = 0 if (scalar(@data) == 0); # in case of read !!
		my $datasize =  scalar(@data);

		if ($datasize == 1) {
			$data[0] = ($data[0] & 0x3F) | $acpi;
		}
		else {
			$data[0] = $acpi;
		}

		Log3 $name, 5, q{KNXIO_Write: str/size/acpi/src/dst= } . unpack('H*',@data) . q{/} . $datasize . q{/} .  $acpi . q{/} . unpack("H*",$src) . q{/} . unpack("H*",$dst);
		my $completemsg = q{};
		my $ret = 0;

		if ($mode =~ /^[ST]$/ix ) {  #format: size | 0x0027 | dst | 0 | data
			$completemsg = pack('nnnCC*',$datasize + 5,0x0027,$dst,0,@data);
		}
		elsif ($mode eq 'M') {
			$completemsg = pack('nnnnnnnCCC*',0x0610,0x0530,$datasize + 16,0x2900,0xBCE0,0,$dst,$datasize,0,@data);
			$ret = TcpServer_MCastSend($hash,$completemsg); # new TcpServerUtils
		}
		else { # $mode eq 'H'
			# total length= $size+20 - include 2900BCEO,src,dst,size,0
			$completemsg = pack('nnnCCCCnnnnCCC*',0x0610,0x0420,$datasize + 20,4,$hash->{KNXIOhelper}->{CCID},$hash->{KNXIOhelper}->{SEQUENCECNTR_W},0,0x1100,0xBCE0,0,$dst,$datasize,0,@data); # send TunnelInd

			# Timeout function - expect TunnelAck within 1 sec! - but if fhem has a delay....
			$hash->{KNXIOhelper}->{LASTSENTMSG} = $completemsg; # save msg for resend in case of TO
			InternalTimer(gettimeofday() + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		}

		$ret = DevIo_SimpleWrite($hash,$completemsg,0) if ($mode ne 'M');
		Log3 $name, 4, 'KNXIO_Write: Mode=' . $mode . ' buf=' . unpack('H*',$completemsg)  . " rc=$ret";
		return;
	}
	Log3 $name, 2, 'KNXIO_write: Could not send message ' . $msg;
	return;
}

#####################################
sub KNXIO_Undef {
	my $hash = shift;
	my $name = shift;

	return KNXIO_Shutdown($hash);
}

###################################
sub KNXIO_Shutdown {
	my $hash = shift;

	my $mode = $hash->{model};
	if ($mode eq 'M') {
		TcpServer_Close($hash);
	} else {
		KNXIO_closeDev($hash);
	}
	RemoveInternalTimer($hash);
	return;
}

###################################
### check for duplicate msgs
# not used !
sub KNXIO_FingerPrint {
	my $ioname = shift;
	my $buf  = shift;
	my $mode = $defs{$ioname}->{model};

	substr( $buf, 1, 5, "-----" ); # ignore src addr
#	Log3 $ioname, 5, 'KNXIO_Fingerprint: ' . $buf;
#	return ( $ioname, $buf ); # ignore src addr
	return ( q{}, $buf ); # ignore ioname & src addr
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
		Log3 $hash, 2, "KNXIO_callback: device open $hash->{NAME} failed with: $err" if ($err);
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
		Log3($name, 1, "KNXIO_define: hostname could not be resolved: $error");
		return  "KNXIO_define: hostname could not be resolved: $error";
	}
	my $host = ip2str($dhost);
	Log3($name, 3, "KNXIO_define: DNS query result= $host");
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

	if (exists $hash->{DNSWAIT}) {
		$hash->{DNSWAIT} += 1;
		if ($hash->{DNSWAIT} > 5) {
			Log3 ($name, 2, "KNXIO_openDev: $name - DNS failed, check ip/hostname");
			return; #  "KNXIO_openDev: $name - DNS failed, check ip/hostname";
		} 
		InternalTimer(gettimeofday() + 1,\&KNXIO_openDev,$hash);
		Log3 ($name, 2, "KNXIO_openDev: waiting for DNS");
		return; # waiting for DNS
	}
	return if (! exists($hash->{DeviceName})); # DNS failed !

	my $reopen = (exists($hash->{NEXT_OPEN}))?1:0; # 
	my $param = $hash->{DeviceName}; # (connection-code):ip:port or socket param
	my ($ccode, $host, $port) = split(/[:]/ix,$param);
	if (! defined($port)) {
		$port = $host;
		$host = $ccode;
		$ccode = undef;
	}
	$host = $port if ($param =~ /UNIX:STREAM:/ix); 

	Log3 ($name, 5, "KNXIO_openDev: $mode, $host, $port, reopen=$reopen");

	my $ret = undef; # result

	### multicast support via TcpServerUtils ...
	if ($mode eq 'M') {
		delete $hash->{TCPDev}; # devio ?
		$ret = TcpServer_Open($hash, $port, $host, 1);
		if (defined($ret)) { # error
			Log3 ($name, 2, "KNXIO_openDev: $name Can't connect: $ret") if(!$reopen); 
		} 
		$ret = TcpServer_MCastAdd($hash,$host);
		if (defined($ret)) { # error
			Log3 ($name, 2, "KNXIO_openDev: $name MC add failed: $ret") if(!$reopen);
		}

		delete $hash->{NEXT_OPEN};
		delete $readyfnlist{"$name.$param"};
		$ret = KNXIO_init($hash);
	}

	### socket mode
	elsif ($mode eq 'S') {
		if (!(-S -r -w $host) && $init_done) {
			Log3 ($name, 2, q{KNXIO_openDev: Socket not available - (knxd running?)});
			return;
		}
		$ret = DevIo_OpenDev($hash,$reopen,\&KNXIO_init); # no callback
	}

	### host udp
	elsif ($mode eq 'H') {
		my $conn = 0;
		$conn = IO::Socket::INET->new(PeerAddr => "$host:$port", Type => SOCK_DGRAM, Proto => 'udp', Reuse => 1);
		if (!($conn)) {
			Log3 ($name, 2, "KNXIO_openDev: device $name Can't connect: $ERRNO") if(!$reopen); # PBP
			$readyfnlist{"$name.$param"} = $hash;
			readingsSingleUpdate($hash, "state", "disconnected", 0);
			$hash->{NEXT_OPEN} = gettimeofday() + $reconnectTO;
			return;
		}
		delete $hash->{NEXT_OPEN};
		delete $hash->{DevIoJustClosed}; # DevIo
		$conn->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1); #01.70
		$hash->{TCPDev} = $conn;
		$hash->{FD} = $conn->fileno();
		delete $readyfnlist{"$name.$param"};
		$selectlist{"$name.$param"} = $hash;
		if($reopen) {
			Log3 ($name, 3, "KNXIO_openDev: device $name reappeared");
		}
		else {
			Log3 ($name, 3, "KNXIO_openDev: device $name opened");
		}
		$ret = KNXIO_init($hash);
	}

	### tunneling TCP
	else { # $mode eq 'T'
		$ret = DevIo_OpenDev($hash,$reopen,\&KNXIO_init,\&KNXIO_callback);
	}

	if(defined($ret) && $ret) {
		Log3 ($name, 1, "KNXIO_openDev: Cannot open KNXIO-Device $name, ignoring it");
		KNXIO_closeDev($hash);
	}

	return $ret;
}

### called from DevIo_open or KNXIO_openDev after sucessful open
sub KNXIO_init {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	if ($mode =~ m/[ST]/ix) {
		my $opengrpcon = pack("nnnC",(5,0x26,0,0)); # KNX_OPEN_GROUPCON
		DevIo_SimpleWrite($hash,$opengrpcon,0); 
	}

	elsif ($mode eq 'H') {
		my $connreq = KNXIO_prepareConnRequ($hash);
		DevIo_SimpleWrite($hash,$connreq,0);
	}

#	elsif ($mode eq 'M') {
#	}

	# state 'connected' is set in decode_EMI (model ST) or in readH (model H)?  
	else {

#		DoTrigger($name, 'CONNECTED');
		readingsSingleUpdate($hash, "state", "connected", 1);
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

	my @que = ();
	push (@que,$buf);
	$hash->{KNXIOhelper}->{FIFO} = \@que;

	return KNXIO_processFIFO($hash);
}

### called from FIFO TIMER or direct if FIFO disabled
sub KNXIO_dispatch2 { 
#	my ($hash, $outbuf ) = ($_[0]->{h}, $_[0]->{m});
	my $hash = shift;

	my $buf = $hash->{KNXIOhelper}->{FIFOMSG};
	my $name = $hash->{NAME};
	$hash->{KNXIOhelper}->{FIFOTIMER} = 0;

	$hash->{"${name}_MSGCNT"}++;
	$hash->{"${name}_TIME"} = TimeNow();

	Dispatch($hash, $buf);

	KNXIO_processFIFO($hash) if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{}));
	return;
}

### fetch msgs from FIFO and call dispatch
sub KNXIO_processFIFO {
	my $hash = shift;
	my $name = $hash->{NAME};

	if ($hash->{KNXIOhelper}->{FIFOTIMER} != 0) { # dispatch still running, do a wait loop
		Log3 $hash->{NAME}, 4, 'KNXIO_processFIFO: dispatch not complete, waiting';
		InternalTimer(gettimeofday() + 0.1, \&KNXIO_processFIFO, $hash);
		return;
	}
	my @que = @{$hash->{KNXIOhelper}->{FIFO}};
	my $queentries = scalar(@que);
	if ($queentries > 0) { # process timer is not running & fifo not empty
		$hash->{KNXIOhelper}->{FIFOMSG} = shift (@que);
		$hash->{KNXIOhelper}->{FIFO} = \@que;
		$hash->{KNXIOhelper}->{FIFOTIMER} = 1;
		Log3($name, 4, 'KNXIO_processFIFO: ' . $hash->{KNXIOhelper}->{FIFOMSG} . ' Nr_msgs: '  . $queentries);
#		InternalTimer(gettimeofday() + 1.0, \&KNXIO_dispatch2, $hash); # testing delay
		InternalTimer(0, \&KNXIO_dispatch2, $hash);

		# delete duplicates from queue
		while ($queentries > 1) {
			my $nextbuf = shift (@que);
			if ($hash->{KNXIOhelper}->{FIFOMSG} eq $nextbuf) {
				$hash->{KNXIOhelper}->{FIFO} = \@que; # discard it 
				Log3($name, 4, "KNXIO_processFIFO: - deleted duplicate msg from queue");
			}
			$queentries--;
		}
	}
	return;
}

###
sub KNXIO_disconnect {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	DevIo_Disconnected($hash);

	Log3 ($name, 1, "KNXIO_disconnect: device $name disconnected, waiting to reappear");

	$readyfnlist{"$name.$param"} = $hash;               # Start polling
	$hash->{NEXT_OPEN} = gettimeofday() + $reconnectTO; #01.70

	# Without the following sleep the open of the device causes a SIGSEGV,
        # and following opens block infinitely. Only a reboot helps.
#        sleep(5);

	return;
}

###
sub KNXIO_closeDev {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	if ($hash->{model} eq 'M') {
		TcpServer_Close($hash);
	}
	else {
		DevIo_CloseDev($hash);
		$hash->{TCPDev}->close() if($hash->{FD});
	}

	delete $hash->{nextOpenDelay};
	delete $hash->{"${name}_MSGCNT"};
	delete $hash->{"${name}_TIME"};

#NO!	delete $hash->{'.CCID'};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR_W};

	RemoveInternalTimer($hash);

	Log3 ($name, 5, "KNXIO_closeDev: device $name closed");

	readingsSingleUpdate($hash, "state", "disconnected", 1);
	DoTrigger($name, "DISCONNECTED");

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

	my ($len, $id, $src, $dst, $acpi, @data) = unpack("nnnnCC*",$buf);
	if (($len + 2) != length($buf)) {
		Log3 $name, 4, 'KNXIO_decodeEMI: buffer length mismatch ' . $len . q{ } . (length($buf) - 2); 
		return;
	}
	if ($id != 0x0027) {
		if ($id == 0x0026) {
			Log3($name, 4, 'KNXIO_decdeEMI: OpenGrpCon response received');
			readingsSingleUpdate($hash, 'state', 'connected', 1);
		}
		else {
			Log3($name, 3, 'KNXIO_decodeEMI: invalid message code' . sprintf("04x",$id));
		}
		return;
	}
	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,1); # always a Group addr

	Log3($name, 4, "KNXIO_decodeEMI: src=$src - dst=$dst - leng=" . scalar(@data) . " - data=" . sprintf('%02x' x scalar(@data),@data));

	# acpi ref: KNX System Specs 03.03.07
	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) {
		Log3($name, 4, 'KNXIO_decodeEMI: no valid acpi-code (read/reply/write) received, discard packet');
		Log3($name, 4, "discarded packet: src=$src - dst=$dst - acpi=" . sprintf('%02x',$acpi) . " - leng=" . scalar(@data) . " - data=" . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1
	
	my $outbuf = $TULID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	Log3($name, 5, 'KNXIO_decodeEMI: ' . $outbuf);

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
		Log3($name, 4, 'KNXIO_decodeCEMI: wrong MessageCode ' . sprintf("%02x",$mc) . ', discard packet');
		return;
	}

	$addlen += 2;
	my ($ctrlbyte1, $ctrlbyte2, $src, $dst, $tcf, $acpi, @data) = unpack("x" . $addlen .  "CCnnCCC*",$buf);

	if (($ctrlbyte1 & 0xF0) != 0xB0) { # standard frame/no repeat/broadcast - see 03_06_03 EMI_IMI specs
		Log3 $name, 4, 'KNXIO_decodeCEMI: wrong ctrlbyte1' . sprintf("%02x",$ctrlbyte1)  . ', discard packet';
		return;
	}
	my $prio = ($ctrlbyte1 & 0x0C) >>2; # priority
	my $dest_addrType = ($ctrlbyte2 & 0x80) >> 7; # MSB  0 = indiv / 1 = group
	my $hop_count = ($ctrlbyte2 & 0x70) >> 4; # bits 6-4

	if ($tcf != scalar(@data)) { # $tcf: number of NPDU octets, TPCI octet not included!
		Log3 $name, 4, 'KNXIO_decodeCEMI: Datalength not consistent';
		return;
	}

	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,$dest_addrType);

	Log3($name, 4, "KNXIO_decodeCEMI: src=$src - dst=$dst - destaddrType=$dest_addrType  - prio=$prio - hop_count=$hop_count - leng=" . scalar(@data) . " - data=" . sprintf('%02x' x scalar(@data),@data));

	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) { # not a groupvalue-read/write/reply
		Log3($name, 4, 'KNXIO_decodeCEMI: no valid acpi-code (read/reply/write) received, discard packet');
		Log3($name, 4, "discarded packet: src=$src - dst=$dst - destaddrType=$dest_addrType  - prio=$prio - hop_count=$hop_count - leng=" . scalar(@data) . " - data=" . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1

	my $outbuf = $TULID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	Log3($name, 5, "KNXIO_decodeCEMI: $outbuf");

	return $outbuf;
}


### convert address from number to hex-string or display name ($type=2) 
sub KNXIO_addr2hex {
	my $adr = shift;
	my $type = shift;  # 1 if GA-address, else physical address

	return sprintf('%02x%01x%02x', ($adr >> 11) & 0x1f, ($adr >> 8) & 0x7, $adr & 0xff) if ($type == 1);
	return sprintf('%d.%d.%d', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff) if ($type == 2); # for display
	return sprintf('%02x%01x%02x', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff);
}

### convert address from hex-string (5 digits) to number
sub KNXIO_hex2addr {
	my $str = shift;

	if ($str =~ m/([0-9a-f]{2})([0-9a-f])([0-9a-f]{2})/ix) {
		return (hex($1) << 11) | (hex($2) << 8) | hex($3); # GA Addr
	}
	elsif ($str =~ m/([\d]+)\.([\d]+)\.([\d]+)/ix) {
		return ($1 << 12) + ($2 << 8) + $3; # phy Addr
	}
	return 0;
}

### check for duplicate messages
#   check the first msg in PARTIAL against all msgs in PARTIAL,
#   if match, returns last matched msg (=the most recent) and delete all other msgs.
#   if no match, return first msg from PARTIAL
#
#   return: buf for further processing (last matched message)
sub KNXIO_chkDupl2 {
	my $hash = shift;
	my $buf  = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};
	my $lenpar = length($hash->{PARTIAL});
	my $outbuf = $buf; # copy for return

	Log3 $name, 5, 'KNXIO_chkDupl- msglen: ' .  length($buf) . " LENPART= " . length($hash->{PARTIAL});

 	return $buf if (length($hash->{PARTIAL}) == 0); 
	$hash->{helper}{BUFFER} = unpack('H*',$hash->{PARTIAL}); # debugging partial

	if ($mode =~ /[ST]/x) {
		# msgformat: 0008 0027 00c8 1c0c 00 80
		substr( $buf, 4, 2, q{..} ); # prepare reqex for duplicate test (ignore src addr)
		my $bufrepl = substr(q{..................},0,length($buf) - 9); # ignore data-values in PARTIAL
		substr( $buf, 9 ,(length($buf) - 9),$bufrepl);  # ignore data-values in PARTIAL
	}
	elsif ($mode eq 'M') {
		# msgformat: 0610 0530 0011 2900 bcc0 00c8 1c0c 01 00 81
		substr( $buf, 9, 3, '...' ); # prepare reqex for duplicate test (ignore hop count & src addr)
	}
	else {
		return $outbuf; # unchanged
	}
	$buf =~ s/([)]|[(])/./gx; # mask )(
	my $re = qr{$buf}; ## no critic 'RegularExpressions'

	Log3 $name, 1, 'KNXIO_chkDupl: regex-r= ' . unpack('H*', $buf);
	Log3 $name, 1, 'KNXIO_chkDupl: PARTIAL= ' . unpack('H*', $hash->{PARTIAL});

	my (@match) = ($hash->{PARTIAL} =~ m/${re}/gix);
	my $nrmatches = scalar(@match);
	if ($nrmatches > 0) { # we have duplicates
		$outbuf = $match[scalar(@match)-1]; # use the last one
		$hash->{PARTIAL} =~ s/${re}//gx; # delete duplicate packets
	}
	Log3 $name, 4, 'KNXIO_chkDupl: nrDuplicates= ' . $nrmatches . ' LengthPartial= ' . length($hash->{PARTIAL}) . ' Buf-in(masked)= ' . unpack('H*', $buf) . ' Buf-out= ' . unpack('H*', $outbuf);
	return $outbuf;
}


### keep alive for mode H - every minute
# triggered on conn-response & 
sub KNXIO_keepAlive {
	my $hash = shift;
	my $name = $hash->{NAME};

	Log3($name, 4, 'KNXIO_keepalive - expect ConnectionStateResponse');

	my $msg = pack('nnnCCnnnn',(0x0610,0x0207,16,$hash->{KNXIOhelper}->{CCID},0, 0x0801,0,0,0));
	RemoveInternalTimer($hash,\&KNXIO_keepAlive);
	DevIo_SimpleWrite($hash,$msg,0); #  send conn state requ
	InternalTimer(gettimeofday() + 2,\&KNXIO_keepAliveTO,$hash); # set timeout timer - reset by ConnectionStateResponse
	return;
}

### keep alive timeout
sub KNXIO_keepAliveTO {
	my $hash = shift;
	my $name = $hash->{NAME};

	Log3($name, 4, 'KNXIO_keepAlive timeout - retry');
	
	return KNXIO_keepAlive($hash);
}

### TO hit while sending...
sub KNXIO_TunnelRequestTO {
	my $hash = shift;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO);
#$attr{$name}{verbose} = 4; # temp
	# try resend...but only once
	if (exists($hash->{KNXIOhelper}->{LASTSENTMSG})) {
		Log3($name, 3, 'KNXIO_TunnelRequestTO hit - attempt resend');
		my $msg = $hash->{KNXIOhelper}->{LASTSENTMSG};
		DevIo_SimpleWrite($hash,$msg,0);
		delete $hash->{KNXIOhelper}->{LASTSENTMSG};
		InternalTimer(gettimeofday() + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		return;
	}

	Log3($name, 3, 'KNXIO_TunnelRequestTO hit - sending disconnect request');

	# send disco request
	my $hpai = pack('nCCCCn',(0x0801,0,0,0,0,0));
	my $msg = pack('nnnCC',(0x0610,0x0209,16,$hash->{KNXIOhelper}->{CCID},0)) . $hpai;
	DevIo_SimpleWrite($hash,$msg,0); #  send disconn requ
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

=pod

=encoding utf8

=item [device]
=item summary IO-module for KNX-devices supporting UDP, TCP & socket connections
=item summary_DE IO-Modul f&uuml;r KNX-devices. Unterst&uuml;tzt UDP, TCP & Socket Verbindungen

=begin html

<a id="KNXIO"></a>
<h3>KNXIO</h3>
<ul>
<p>This is a IO-module for KNX-devices. It provides an interface between FHEM and a KNX-Gateway. The Gateway can be either a KNX-Router/KNX-GW or the KNXD-daemon.
   FHEM KNX-devices use this module as IO-Device. This Module does <b>NOT</b> support the deprecated EIB-Module!
</p>

<a id="KNXIO-define"></a>
<p><strong>Define</strong></p>
<p><code>define &lt;name&gt; KNXIO (H|M|T) &lt;(ip-address|hostname):port&gt; &lt;phy-adress&gt;</code> <br/>or<br/>
<code>define &lt;name&gt; KNXIO S &lt;UNIX socket-path&gt; &lt;phy-adress&gt;</code></p>
<ul>
<b>Connection Types</b> (first parameter):
<ul>
<li><b>H</b> Host Mode - connect to a KNX-router with UDP point-point protocol.<br/>
  This is the mode also used by ETS when you specify KNXNET/IP as protocol. You do not need a KNXD installation. The protocol is complex and timing critical! 
  If you have delays in FHEM processing close to 1 sec, the protocol may disconnect. It should recover automatically, 
  however KNX-messages could have been lost! </li>
<li><b>M</b> Multicast mode - connect to KNXD's or KNX-router's multicast-tree.<br/>
  This is the mode also used by ETS when you specify KNXNET/IP Routing as protocol. 
  If you have a KNX-router that supports multicast, you do not need a KNXD installation. Default address:port is 224.0.23.12:3671<br/>
  Pls. ensure that you have only <b>one</b> GW/KNXD in your LAN that feed the multicast tree!<br/>
  <del>This mode requires the <code>IO::Socket::Multicast</code> perl-module to be installed on yr. system. 
  On Debian systems this can be achieved by <code>apt-get install libio-socket-multicast-perl</code>.</del></li>
<li><b>T</b> TCP Mode - uses a TCP-connection to KNXD (default port: 6720).<br/>
  This mode is the successor of the TUL-modul, but does not support direct Serial/USB connection to a TPUart-USB Stick.
  If you want to use a TPUart-USB Stick or any other serial KNX-GW, use either the TUL Module, or connect the USB-Stick to KNXD and in turn use modes M,S or T to connect to KNXD.</li>
<li><b>S</b> Socket mode - communicate via KNXD's UNIX-socket on localhost. default Socket-path: <code>/var/run/knx</code><br/> 
  Path might be different, depending on knxd-version or -config specification! This mode is tested ok with KNXD version 0.14.30. It does NOT work with ver. 0.10.0!</li>
</ul>
<br/>
<b>ip-address:port</b> or <b>hostname:port</b>
<ul>
<li>Hostname is supported for mode H and T. Port definition is mandatory.</li>
</ul>
<br/>
<b>phy-address</b>
<ul>
<li>The physical address is used as the source address of messages sent to KNX network. This address should be one of the defined client pool-addresses of KNXD or Router.</li>
</ul>
</ul>
<p>All parameters are mandatory. Pls. ensure that you only have <b>one path</b> between your KNX-Installation and FHEM! 
  Do not define multiple KNXIO- or KNXTUL- or TUL-definitions at the same time. </p>

<ul>
Examples:<br/>
<code>define myKNXGW KNXIO H 192.168.1.201:3671 0.0.51</code><br/>
<code>define myKNXGW KNXIO M 224.0.23.12:3671 0.0.51</code><br/> 
<code>define myKNXGW KNXIO S /var/run/knx 0.0.51</code><br/>
<code>define myKNXGW KNXIO T 192.168.1.200:6720 0.0.51</code><br/>
</ul>
<br/>
<ul>
  Suggested parameters for KNXD (with systemd, Version >= 0.14.30):
  <br/><code>
    KNXD_OPTS="-e 0.0.50 -E 0.0.51:8 -D -T -S -b ip:" # knxd acts as multicast client<br/>
    KNXD_OPTS="-e 0.0.50 -E 0.0.51:8 -D -T -R -S -b ipt:192.168.xx.yy" # connect to a knx-router with ip-addr<br/>
    KNXD_OPTS="-e 0.0.50 -E 0.0.51:8 -D -T -R -S -single -b tpuarts:/dev/ttyxxx" # connect to a serial/USB KNX GW <br/>
  </code>
</ul>

<a id="KNXIO-set"></a>
<p><strong>Set</strong> - No Set cmd implemented</p>

<a id="KNXIO-get"></a>
<p><strong>Get</strong> - No Get cmd impemented</p>

<a id="KNXIO-attr"></a>
<p><strong>Attributes</strong></p>
<ul>
<!--
<a id="KNXIO-attr-KNX_FIFO"></a><li><b>KNX_FIFO</b> - 
  Set this attr to 1 to enable a receive buffer for incoming messages. The KNX-messages will not processed faster, 
  but the overall responsiveness and latency of FHEM benefit from this setting.</li>
-->
<a id="KNXIO-attr-disable"></a><li><b>disable</b> - 
  Disable the device if set to <b>1</b>. No send/receive from bus possible. Delete this attr to enable device again.</li>
<a id="KNXIO-attr-verbose"></a><li><b>verbose</b> - 
  increase verbosity of Log-Messages, system-wide default is set in "global" device. For a detailed description see: <a href="#verbose">global-attr verbose</a> </li> 
</ul>
<br/>
</ul>

=end html

=cut
