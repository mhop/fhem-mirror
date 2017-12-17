##############################################
# $Id$
# Written by Markus Feist, 2017
package main;

use strict;
use warnings;
use TcpServerUtils;
use HttpUtils;
use IO::Socket;

use constant MA_PACKAGE_LENGTH => 64;

my $MA_wname;
my $MA_chash;
my $MA_cname;
my @MA_httpheader;
my %MA_httpheader;

sub MOBILEALERTSGW_Initialize($) {
    my ($hash) = @_;

    $hash->{ReadFn}        = "MOBILEALERTSGW_Read";
    $hash->{GetFn}         = "MOBILEALERTSGW_Get";
    $hash->{SetFn}         = "MOBILEALERTSGW_Set";
    $hash->{AttrFn}        = "MOBILEALERTSGW_Attr";
    $hash->{DefFn}         = "MOBILEALERTSGW_Define";
    $hash->{UndefFn}       = "MOBILEALERTSGW_Undef";
    $hash->{Clients}       = "MOBILEALERTS";
    $hash->{MatchList}     = { "1:MOBILEALERTS" => "^.*" };
    $hash->{Write}         = "MOBILEALERTSGW_Write";
    $hash->{FingerprintFn} = "MOBILEALERTSGW_Fingerprint";

    #$hash->{NotifyFn}= ($init_done ? "FW_Notify" : "FW_SecurityCheck");
    #$hash->{AsyncOutputFn} = "MOBILEALERTSGW_AsyncOutput";
    #$hash->{ActivateInformFn} = "MOBILEALERTSGW_ActivateInform";
    $hash->{AttrList} = "forward:0,1 " . $readingFnAttributes;
    Log3 "MOBILEALERTSGW", 5, "MOBILEALERTSGW_Initialize finished.";
}

sub MOBILEALERTSGW_Define($$) {
    my ( $hash, $def ) = @_;
    my ( $name, $type, $port ) = split( "[ \t]+", $def );
    return "Usage: define <name> MOBILEALERTSGW <tcp-portnr>"
      if ( $port !~ m/^\d+$/ );

    my $ret = TcpServer_Open( $hash, $port, "global" );

    return $ret;
}

sub MOBILEALERTSGW_GetUDPSocket($$) {
    my ( $hash, $name ) = @_;
    my $socket;
    if ( defined( $hash->{UDPHASH} ) ) {
        $socket = $hash->{UDPHASH}->{UDPSOCKET};
    }
    else {
        #IO::Socket::INET geht leider nicht
        Log3 $name, 3, "$name MOBILEALERTSGW: Create UDP Socket.";
        unless ( socket( $socket, AF_INET, SOCK_DGRAM, getprotobyname('udp') ) )
        {
            Log3 $name, 1, "$name MOBILEALERTSGW: Could not create socket: $!";
            return undef;
        }
        unless ( setsockopt( $socket, SOL_SOCKET, SO_BROADCAST, 1 ) ) {
            Log3 $name, 1, "$name MOBILEALERTSGW: Could not setsockopt: $!";
            return undef;
        }
        my $cname = "${name}_UDPPORT";
        my %nhash;
        $nhash{NR}                  = $devcount++;
        $nhash{NAME}                = $cname;
        $nhash{FD}                  = fileno($socket);
        $nhash{UDPSOCKET}           = $socket;
        $nhash{TYPE}                = $hash->{TYPE};
        $nhash{STATE}               = "Connected";
        $nhash{SNAME}               = $name;
        $nhash{TEMPORARY}           = 1;                 # Don't want to save it
        $nhash{HASH}                = $hash;
        $attr{$cname}{room}         = "hidden";
        $defs{$cname}               = \%nhash;
        $selectlist{ $nhash{NAME} } = \%nhash;
        $hash->{UDPHASH}            = \%nhash;
    }
    return $socket;
}

sub MOBILEALERTSGW_Get ($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    return "\"get $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "config" ) {
        my @gateways = split( ",", ReadingsVal( $name, "Gateways", "" ) );
        my $gateway = $args[0];
        my $destpaddr;
        my $command;

        if ( $gateway =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) {
            $destpaddr = sockaddr_in( 8003, inet_aton($gateway) );
            $gateway   = "000000000000";
            $command   = 1;
        }
        elsif ( $gateway =~ /([0-9A-F]{12})/ ) {
            if ( @gateways == 0 ) {
                $destpaddr = sockaddr_in( 8003, INADDR_BROADCAST );
                $command = 2;
            }
            elsif ( !grep( /^$gateway$/, @gateways ) ) {
                $destpaddr = sockaddr_in( 8003, INADDR_BROADCAST );
                $command = 2;
            }
            else {
                my $ip = ReadingsVal( $name, "GW_" . $gateway . "_ip", "" );
                if ( length($ip) == 0 ) {
                    $destpaddr = sockaddr_in( 8003, INADDR_BROADCAST );
                }
                else {
                    $destpaddr = sockaddr_in( 8003, inet_aton($ip) );
                }
                $command = 2;
            }
        }
        else {
            $gateway   = "000000000000";
            $destpaddr = sockaddr_in( 8003, INADDR_BROADCAST );
            $command   = 1;
        }
        my $socket = MOBILEALERTSGW_GetUDPSocket( $hash, $name );
        if ( !defined($socket) ) {
            return "Could not create socket.";
        }
        my $data = pack( "nH[12]n", $command, $gateway, 10 );
        Log3 $name, 5,
          "$name MOBILEALERTSGW: Send GetConfig " . unpack( "H*", $data );
        send( $socket, $data, 0, $destpaddr );
        return undef;
    }
    else {
        return "Unknown argument $cmd, choose one of config";
    }
}

sub MOBILEALERTSGW_Set ($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "clear" ) {
        if ( $args[0] eq "readings" ) {
            for ( keys %{ $hash->{READINGS} } ) {
                delete $hash->{READINGS}->{$_} if ( $_ ne 'state' );
            }
            return undef;
        }
        else {
            return "Unknown value $args[0] for $cmd, choose one of readings";
        }
    }
    elsif ( $cmd eq "initgateway" ) {
        my @gateways = split( ",", ReadingsVal( $name, "Gateways", "" ) );
        my $gateway = $args[0];

        if ( @gateways == 0 ) {
            return
              "No gateway known. Find with 'get $name findgateways' first.";
        }
        if ( !grep( /^$gateway$/, @gateways ) ) {
            return "Unknown $gateway for $cmd, choose one of "
              . join( ",", @gateways );
        }
        my $ip     = ReadingsVal( $name, "GW_" . $gateway . "_ip",     "" );
        my $config = ReadingsVal( $name, "GW_" . $gateway . "_config", "" );
        if ( length($ip) == 0 ) {
            return
"IP of gateway unknown. Find with 'get $name findgateways' first.";
        }
        if ( length($config) == 0 ) {
            return
"Config of gateway unknown. Find with 'get $name findgateways' first.";
        }
        my $sock = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerPort => 8003,
            PeerAddr => $ip
        ) or return "Could not create socket: $!\n";
        my $myip   = $sock->sockhost;
        my $myport = $hash->{PORT};

        Log3 $name, 4,
"$name MOBILEALERTSGW: Config gateway $gateway $ip Proxy auf $myip:$myport";
        $config = pack( "H*", $config );
        $config =
            "\0\x04"
          . substr( $config, 2, 6 )
          . "\0\xB5"
          . substr( $config, 15, 1 + 4 + 4 + 4 + 21 + 65 ) . "\x01"
          . pack( "a65n", $myip, $myport )
          . substr( $config, 182, 4 );
        Log3 $name, 5, "$name MOBILEALERTSGW: Send " . unpack( "H*", $config );
        $sock->send($config) or return "Could not send $!";
        $sock->close();
        return undef;
    }
    elsif ( $cmd eq "rebootgateway" ) {
        my @gateways = split( ",", ReadingsVal( $name, "Gateways", "" ) );
        my $gateway = $args[0];

        if ( @gateways == 0 ) {
            return
              "No gateway known. Find with 'get $name findgateways' first.";
        }
        if ( !grep( /^$gateway$/, @gateways ) ) {
            return "Unknown $gateway for $cmd, choose one of "
              . join( ",", @gateways );
        }
        my $ip = ReadingsVal( $name, "GW_" . $gateway . "_ip", "" );
        if ( length($ip) == 0 ) {
            return
"IP of gateway unknown. Find with 'get $name findgateways' first.";
        }
        my $sock = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerPort => 8003,
            PeerAddr => $ip
        ) or return "Could not create socket: $!\n";
        Log3 $name, 4,
          "$name MOBILEALERTSGW: Reboot gateway $gateway auf $ip:8003";
        my $data = pack( "nH[12]n", 5, $gateway, 10 );
        Log3 $name, 5, "$name MOBILEALERTSGW: Send " . unpack( "H*", $data );
        $sock->send($data) or return "Could not send $!";
        $sock->close();
        return undef;
    }
    elsif ( $cmd eq "debuginsert" ) {
        my $data = pack( "H*", $args[0] );
        my ( $packageHeader, $timeStamp, $packageLength, $deviceID ) =
          unpack( "CNCH12", $data );
        Log3 $name, 4,
            "$name MOBILEALERTSGW: Debuginsert PackageHeader: "
          . $packageHeader
          . " Timestamp: "
          . scalar( FmtDateTimeRFC1123($timeStamp) )
          . " PackageLength: "
          . $packageLength
          . " DeviceID: "
          . $deviceID;
        Log3 $name, 5, "$name MOBILEALERTSGW: Debuginsert for $deviceID: "
          . unpack( "H*", $data );
        Dispatch( $hash, $data, undef );
        return undef;
    }
    else {
        my $gateways = ReadingsVal( $name, "Gateways", "" );
        return
            "Unknown argument $cmd, choose one of clear:readings rebootgateway:"
          . $gateways
          . " initgateway:"
          . $gateways;
    }
}

sub MOBILEALERTSGW_Undef($$) {
    my ( $hash, $name ) = @_;

    if ( defined( $hash->{UDPHASH} ) ) {
        my $cname = "${name}_UDPPORT";
        delete( $selectlist{$cname} );
        delete $attr{$cname};
        delete $defs{$cname};
        close( $hash->{UDPHASH}->{UDPSOCKET} );
        delete $hash->{UDPHASH};
    }

    my $ret = TcpServer_Close($hash);
    return $ret;
}

sub MOBILEALERTSGW_Attr($$$$) {
    my ( $cmd, $name, $attrName, $attrValue ) = @_;

    if ( $cmd eq "set" ) {
        if ( $attrName eq "forward" ) {
            if ( $attrValue !~ /^[01]$/ ) {
                Log3 $name, 3,
"$name MOBILEALERTSGW: Invalid parameter attr $name $attrName $attrValue";
                return "Invalid value $attrValue allowed 0,1";
            }
        }
    }
    return undef;
}

sub MOBILEALERTSGW_Fingerprint($$$) {
    my ( $io_name, $message ) = @_;

#PackageHeader + UTC Timestamp + Package Length + Device ID + tx counter (3 bytes)
    my $fingerprint = unpack( "H30", $message );
    return ( $io_name, $fingerprint );
}

sub MOBILEALERTSGW_Write ($$) {

    #Dummy, because it is not possible to send to device.
    my ( $hash, @arguments ) = @_;
    return undef;
}

sub MOBILEALERTSGW_Read($$);

sub MOBILEALERTSGW_Read($$) {
    my ( $hash, $reread ) = @_;
    my $name    = $hash->{NAME};
    my $verbose = GetVerbose($name);

    if ( exists $hash->{UDPSOCKET} ) {
        my $phash = $hash->{HASH};
        $name = $phash->{NAME};
        Log3 $name, 5, "$name MOBILEALERTSGW: Data from UDP received";
        my $srcpaddr = recv( $hash->{UDPSOCKET}, my $udpdata, 186, 0 );
        MOBILEALERTSGW_DecodeUDP( $phash, $udpdata, $srcpaddr );
        return;
    }

    if ( $hash->{SERVERSOCKET} ) {    # Accept and create a child
        my $nhash = TcpServer_Accept( $hash, "MOBILEALERTSGW" );
        return if ( !$nhash );
        my $wt = AttrVal( $name, "alarmTimeout", undef );
        $nhash->{ALARMTIMEOUT} = $wt if ($wt);
        $nhash->{CD}->blocking(0);
        return;
    }

    $MA_chash = $hash;
    $MA_wname = $hash->{SNAME};
    $MA_cname = $name;
    $verbose  = GetVerbose($MA_wname);

    #$FW_subdir = "";

    my $c = $hash->{CD};

    if ( !$reread ) {

        # Data from HTTP Client
        my $buf;
        my $ret = sysread( $c, $buf, 1024 );

        if ( !defined($ret) && $! == EWOULDBLOCK ) {
            $hash->{wantWrite} = 1
              if ( TcpServer_WantWrite($hash) );
            return;
        }
        elsif ( !$ret ) {    # 0==EOF, undef=error
            CommandDelete( undef, $name );
            Log3 $MA_wname, 4,
              "$MA_wname MOBILEALERTSGW: Connection closed for $name: "
              . ( defined($ret) ? 'EOF' : $! );
            return;
        }
        $hash->{BUF} .= $buf;
    }

    if ( !$hash->{HDR} ) {
        return if ( $hash->{BUF} !~ m/^(.*?)(\n\n|\r\n\r\n)(.*)$/s );
        $hash->{HDR} = $1;
        $hash->{BUF} = $3;
        if ( $hash->{HDR} =~ m/Content-Length:\s*([^\r\n]*)/si ) {
            $hash->{CONTENT_LENGTH} = $1;
        }
    }

    @MA_httpheader = split( /[\r\n]+/, $hash->{HDR} );
    %MA_httpheader = map {
        my ( $k, $v ) = split( /: */, $_, 2 );
        $k =~ s/(\w+)/\u$1/g;    # Forum #39203
        $k => ( defined($v) ? $v : 1 );
    } @MA_httpheader;

    my $POSTdata = "";
    if ( $hash->{CONTENT_LENGTH} ) {
        return if ( length( $hash->{BUF} ) < $hash->{CONTENT_LENGTH} );
        $POSTdata = substr( $hash->{BUF}, 0, $hash->{CONTENT_LENGTH} );
        $hash->{BUF} = substr( $hash->{BUF}, $hash->{CONTENT_LENGTH} );
    }
    delete( $hash->{HDR} );
    if ( $verbose >= 5 ) {
        Log3 $MA_wname, 5,
          "$MA_wname MOBILEALERTSGW: Headers: " . join( ", ", @MA_httpheader );
        Log3 $MA_wname, 5, "$MA_wname MOBILEALERTSGW: Receivebuffer: "
          . unpack( "H*", $POSTdata );
    }

    my ( $method, $url, $httpvers ) = split( " ", $MA_httpheader[0], 3 )
      if ( $MA_httpheader[0] );
    $method = "" if ( !$method );

    #if($method !~ m/^(GET|POST)$/i){
    if ( $method !~ m/^(PUT|POST)$/i ) {
        TcpServer_WriteBlocking( $MA_chash,
                "HTTP/1.1 405 Method Not Allowed\r\n"
              . "Content-Length: 0\r\n\r\n" );
        delete $hash->{CONTENT_LENGTH};
        MOBILEALERTSGW_Read( $hash, 1 ) if ( $hash->{BUF} );
        Log3 $MA_wname, 3,
"$MA_wname MOBILEALERTSGW: $MA_cname: unsupported HTTP method $method, rejecting it.";
        MOBILEALERTSGW_closeConn($hash);
        return;
    }

    if ( $url !~ m/.*\/gateway\/put$/i ) {
        TcpServer_WriteBlocking( $MA_chash,
            "HTTP/1.1 400 Bad Request\r\n" . "Content-Length: 0\r\n\r\n" );
        delete $hash->{CONTENT_LENGTH};
        MOBILEALERTSGW_Read( $hash, 1 ) if ( $hash->{BUF} );
        Log3 $MA_wname, 3,
"$MA_wname MOBILEALERTSGW: $MA_cname: unsupported URL $url, rejecting it.";
        MOBILEALERTSGW_closeConn($hash);
        return;
    }
    if ( !exists $MA_httpheader{"HTTP_IDENTIFY"} ) {
        TcpServer_WriteBlocking( $MA_chash,
            "HTTP/1.1 400 Bad Request\r\n" . "Content-Length: 0\r\n\r\n" );
        delete $hash->{CONTENT_LENGTH};
        MOBILEALERTSGW_Read( $hash, 1 ) if ( $hash->{BUF} );
        Log3 $MA_wname, 3,
"$MA_wname MOBILEALERTSGW: $MA_cname: not Header http_identify, rejecting it.";
        MOBILEALERTSGW_closeConn($hash);
        return;
    }
    Log3 $MA_wname, 5, "Header HTTP_IDENTIFY" . $MA_httpheader{"HTTP_IDENTIFY"};
    my ( $gwserial, $gwmac, $actioncode ) =
      split( /:/, $MA_httpheader{"HTTP_IDENTIFY"} );
    my @gateways = split( ",", ReadingsVal( $MA_wname, "Gateways", "" ) );
    readingsBeginUpdate( $defs{$MA_wname} );
    if ( !grep( /^$gwmac$/, @gateways ) ) {
        push( @gateways, $gwmac );
        readingsBulkUpdate( $defs{$MA_wname}, "Gateways",
            join( ",", @gateways ) );
    }
    readingsBulkUpdate( $defs{$MA_wname}, "GW_" . $gwmac . "_lastSeen",
        TimeNow() );
    readingsBulkUpdateIfChanged( $defs{$MA_wname}, "GW_" . $gwmac . "_ip",
        $hash->{PEER} );
    readingsBulkUpdateIfChanged( $defs{$MA_wname}, "GW_" . $gwmac . "_serial",
        $gwserial );
    readingsEndUpdate( $defs{$MA_wname}, 1 );
    if ( $actioncode eq "00" ) {
        Log3 $MA_wname, 4,
"$MA_wname MOBILEALERTSGW: $MA_cname: Initrequest from $gwserial $gwmac";
        MOBILEALERTSGW_DecodeInit( $hash, $POSTdata );
        MOBILEALERTSGW_DefaultAnswer($hash);
    }
    elsif ( $actioncode eq "C0" ) {
        Log3 $MA_wname, 4,
          "$MA_wname MOBILEALERTSGW: $MA_cname: Data from $gwserial $gwmac";
        MOBILEALERTSGW_DecodeData( $hash, $POSTdata );
        MOBILEALERTSGW_DefaultAnswer($hash);
    }
    else {
        TcpServer_WriteBlocking( $MA_chash,
            "HTTP/1.1 400 Bad Request\r\n" . "Content-Length: 0\r\n\r\n" );
        delete $hash->{CONTENT_LENGTH};
        MOBILEALERTSGW_Read( $hash, 1 ) if ( $hash->{BUF} );
        Log3 $MA_wname, 3,
          "$MA_wname MOBILEALERTSGW: $MA_cname: unknown Actioncode $actioncode";
        Log3 $MA_wname, 4,
"$MA_wname MOBILEALERTSGW: $MA_cname: unknown Actioncode $actioncode Postdata: "
          . unpack( "H*", $POSTdata );
        MOBILEALERTSGW_closeConn($hash);
        return;
    }
    MOBILEALERTSGW_closeConn($hash);    #No Keep-Alive

    #Send to Server
    if ( AttrVal( $MA_wname, "forward", 0 ) == 1 ) {
        my $httpparam = {
            url         => "http://www.data199.com/gateway/put",
            timeout     => 20,
            httpversion => "1.1",
            hash        => $hash,
            method      => "PUT",
            header      => "HTTP_IDENTIFY: "
              . $MA_httpheader{"HTTP_IDENTIFY"}
              . "\r\nContent-Type: application/octet-stream",
            data     => $POSTdata,
            callback => \&MOBILEALERTSGW_NonblockingGet_Callback
        };
        HttpUtils_NonblockingGet($httpparam);
    }
    return;
}

sub MOBILEALERTSGW_NonblockingGet_Callback($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $code = $param->{code};
    Log3 $name, 4, "$name MOBILEALERTSGW: Callback";
    if ( $err ne "" ) {
        Log3 $name, 3,
            "$name MOBILEALERTSGW: error while forward request to "
          . $param->{url}
          . " - $err";
    }
    elsif ( $code != 200 ) {
        Log3 $name, 3,
            "$name MOBILEALERTSGW: http-error while forward request to "
          . $param->{url} . " - "
          . $param->{code};
        Log3 $name, 5,
          "$name MOBILEALERTSGW: http-header: " . $param->{httpheader};
        Log3 $name, 5, "$name MOBILEALERTSGW: http-data: " . $data;
    }
    else {
        Log3 $name, 5, "$name MOBILEALERTSGW: forward successfull";
        Log3 $name, 5,
          "$name MOBILEALERTSGW: http-header: " . $param->{httpheader};
        Log3 $name, 5,
          "$name MOBILEALERTSGW: http-data: " . unpack( "H*", $data );
    }
    HttpUtils_Close($param);
}

sub MOBILEALERTSGW_closeConn($) {
    my ($hash) = @_;

    # Kein Keep-Alive noetig
    TcpServer_Close( $hash, 1 );
}

sub MOBILEALERTSGW_DefaultAnswer($) {
    my ($hash) = @_;
    my $buf;

    $buf = pack( "NxxxxNxxxxNN", 420, time, 0x1761D480, 15 );

    TcpServer_WriteBlocking( $MA_chash,
            "HTTP/1.1 200 OK\r\n"
          . "Content-Type: application/octet-stream\r\n"
          . "Content-Length: 24\r\n\r\n"
          . $buf );
}

sub MOBILEALERTSGW_DecodeInit($$) {
    my ( $hash, $POSTdata ) = @_;
    my ( $packageLength, $upTime, $ID, $unknown1, $unknown50 ) =
      unpack( "CNH12nn", $POSTdata );

    Log3 $MA_wname, 4,
      "$MA_wname MOBILEALERTSGW: Uptime (s): " . $upTime . " ID: " . $ID;
}

sub MOBILEALERTSGW_DecodeData($$) {
    my ( $hash, $POSTdata ) = @_;
    my $verbose = GetVerbose($MA_wname);

    for ( my $pos = 0 ; $pos < length($POSTdata) ; $pos += MA_PACKAGE_LENGTH ) {
        my $data = substr $POSTdata, $pos, MA_PACKAGE_LENGTH;
        my ( $packageHeader, $timeStamp, $packageLength, $deviceID ) =
          unpack( "CNCH12", $data );
        Log3 $MA_wname, 4,
            "$MA_wname MOBILEALERTSGW: PackageHeader: "
          . $packageHeader
          . " Timestamp: "
          . scalar( FmtDateTimeRFC1123($timeStamp) )
          . " PackageLength: "
          . $packageLength
          . " DeviceID: "
          . $deviceID
          if ( $verbose >= 4 );
        Log3 $MA_wname, 5,
          "$MA_wname MOBILEALERTSGW: Data for $deviceID: "
          . unpack( "H*", $data )
          if ( $verbose >= 5 );
        my $found = Dispatch( $defs{$MA_wname}, $data, undef );
    }
}

sub MOBILEALERTSGW_DecodeUDP($$$) {
    my ( $hash, $udpdata, $srcpaddr ) = @_;
    my ( $port, $ipaddr ) = sockaddr_in($srcpaddr);
    my $name = $hash->{NAME};
    Log3 $name, 4,
      "$name MOBILEALERTSGW: Data from " . inet_ntoa($ipaddr) . ":" . $port;
    Log3 $name, 5, "$name MOBILEALERTSGW: Data: " . unpack( "H*", $udpdata );

    if ( length $udpdata == 186 ) {
        my @ip;
        my @fip;
        my @netmask;
        my @gateway;
        my @dnsip;
        (
            my $command,
            my $gatewayid,
            my $length,
            @ip[ 0 .. 3 ],
            my $dhcp,
            @fip[ 0 .. 3 ],
            @netmask[ 0 .. 3 ],
            @gateway[ 0 .. 3 ],
            my $devicename,
            my $dataserver,
            my $proxy,
            my $proxyname,
            my $proxyport,
            @dnsip[ 0 .. 3 ]
        ) = unpack( "nH12nxCCCCCCCCCCCCCCCCCa21a65Ca65nCCCC", $udpdata );

        if ( $command != 3 ) {
            Log3 $name, 3,
              "$name MOBILEALERTSGW: Unknown Command $command: "
              . unpack( "H*", $udpdata );
            return;
        }
        Log3 $name, 4,
            "$name MOBILEALERTSGW: Command: "
          . $command
          . " Gatewayid: "
          . $gatewayid
          . " length: "
          . $length . " IP: "
          . join( ".", @ip )
          . " DHCP: "
          . $dhcp
          . " fixedIP: "
          . join( ".", @fip )
          . " netmask: "
          . join( ".", @netmask )
          . " gateway: "
          . join( ".", @gateway )
          . " devicename: "
          . $devicename
          . " dataserver: "
          . $dataserver
          . " proxy: "
          . $proxy
          . " proxyname: "
          . $proxyname
          . " proxyport: "
          . $proxyport
          . " dnsip: "
          . join( ".", @dnsip );
        $gatewayid = uc $gatewayid;
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "GW_" . $gatewayid . "_lastSeen",
            TimeNow() );
        readingsBulkUpdateIfChanged( $hash, "GW_" . $gatewayid . "_ip",
            inet_ntoa($ipaddr) );
        readingsBulkUpdateIfChanged(
            $hash,
            "GW_" . $gatewayid . "_config",
            unpack( "H*", $udpdata )
        );
        readingsBulkUpdateIfChanged(
            $hash,
            "GW_" . $gatewayid . "_proxy",
            $proxy == 1 ? "on" : "off"
        );
        readingsBulkUpdateIfChanged( $hash, "GW_" . $gatewayid . "_proxyname",
            $proxyname );
        readingsBulkUpdateIfChanged( $hash, "GW_" . $gatewayid . "_proxyport",
            $proxyport );
        my @gateways = split( ",", ReadingsVal( $name, "Gateways", "" ) );

        if ( !grep( /^$gatewayid$/, @gateways ) ) {
            push( @gateways, $gatewayid );
            readingsBulkUpdate( $hash, "Gateways", join( ",", @gateways ) );
        }
        readingsEndUpdate( $hash, 1 );
    }
    elsif ( length $udpdata == 118 ) {
        Log3 $name, 5,
          "$name MOBILEALERTSGW: Package was defect, this seems to be normal.";
    }
    else {
        Log3 $name, 3,
          "$name MOBILEALERTSGW: Unknown Data: " . unpack( "H*", $udpdata );
    }
    return;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;

=pod
=item device
=item summary    IO device for german MobileAlerts
=item summary_DE IO device für deutsche MobileAlets
=begin html

<a name="MOBILEALERTSGW"></a>
<h3>MOBILEALERTSGW</h3>
<ul>
  The MOBILEALERTSGW is a fhem module for the german MobileAlerts Gateway and TFA WEATHERHUB.
  <br><br>
  The fhem module makes simulates as http-proxy to intercept messages from the gateway.
  In order to use this module you need to configure the gateway to use the fhem-server with the defined port as proxy.
  You can do so with the command initgateway or by app.
  It automatically detects devices. The other devices are handled by the <a href="#MOBILEALERTS">MOBILELAERTS</a> module,
  which uses this module as its backend.<br>
  <br>

  <a name="MOBILEALERTSGWdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MOBILEALERTSGW &lt;port&gt;</code><br>
    <br>
    port is the port where the proxy server listens. The port must be free.
  </ul>
  <br>

  <a name="MOBILEALERTSGWreadings"></a>
  <b>Readings</b>
  <ul>
    <li>Gateways<br>List of known gateways</li>
    <li>GW_&lt;Gateway-MAC&gt;_lastSeen<br>Time when last message was received from gateway</li>
    <li>GW_&lt;Gateway-MAC&gt;_ip<br>IP-Adresse of gateway</li>
    <li>GW_&lt;Gateway-MAC&gt;_serial<br>Serialnumber of gateway</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxy<br>on, off: setting of proxy (only after get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxyname<br>Name/IP of proxy (only after get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxyport<br>Port of proxy (only after get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_config<br>Complete configuration as hex-values (only after get config)</li>
  </ul>
  <br>     

  <a name="MOBILEALERTSGWset"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; clear &lt;readings&gt;</code><br>
    Clears the readings. </li>
    <li><code>set &lt;name&gt; initgateway &lt;gatewayid&gt;</code><br>
    Sets the proxy in the gateway to the fhem-server. A reboot of the gateway may be needed in order to take effect.</li>    
    <li><code>set &lt;name&gt; rebootgateway &lt;gatewayid&gt;</code><br>
    Reboots the gateway.</li>        
  </ul>
  <br>

  <a name="MOBILEALERTSGWget"></a>
  <b>Get</b>
  <ul>
    <li><code>get &lt;name&gt; config &lt;IP or gatewayid&gt; </code><br>
    Gets the config of a gateway or all gateways. IP or gatewayid are optional. 
    If not specified it will search for alle Gateways in the local lan (Broadcast).</li>
  </ul>
  <br>
  <br>

  <a name="MOBILEALERTSGWattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#MOBILEALERTSGWforward">forward</a><br>
      If value 1 is set, the data will be forwarded to the MobileAlerts Server http://www.data199.com/gateway/put .
    </li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="MOBILEALERTSGW"></a>
<h3>MOBILEALERTSGW</h3>
<ul>
  MOBILEALERTSGW ist ein FHEM-Modul f&uuml;r das deutsche MobileAlerts Gateway und TFA WEATHERHUB.
  <br><br>
  Dieses FHEM-Modul simuliert einen http-proxy, um Nachrichten vom Gateway abzufangen.
  Um dies zu erreichen, muss das Gateway so konfiguriert werden, dass es den FHEM-Server mit dem definierten Port als
  Proxy nutzt. Sie k&ouml;nnen dies entweder mit der App oder dem Kommando initgateway erreichen.
  Es erkennt automatisch Ger&auml;te. Die Ger&auml; werden durch das <a href="#MOBILEALERTS">MOBILELAERTS</a> Modul
  bereitgestellt. MOBILEALERTS nutzt dieses Modul als Backend.<br>
  <br>

  <a name="MOBILEALERTSGWdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MOBILEALERTSGW &lt;port&gt;</code><br>
    <br>
    port ist der Port auf dem der Proxy-Server h&ouml;rt. Der Port muss frei sein.
  </ul>
  <br>

  <a name="MOBILEALERTSGWreadings"></a>
  <b>Readings</b>
  <ul>
    <li>Gateways<br>Liste der bekannten Gateways</li>
    <li>GW_&lt;Gateway-MAC&gt;_lastSeen<br>Zeitpunkt when zuletzt eine Nachricht empfangen wurde</li>
    <li>GW_&lt;Gateway-MAC&gt;_ip<br>IP-Adresse des Gateways</li>
    <li>GW_&lt;Gateway-MAC&gt;_serial<br>Seriennummer des Gateways</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxy<br>on, off: Einstellung des Proxies (nur verf&uuml;nach einem get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxyname<br>Name/IP der Proxy (nur verf&uuml;nach einem get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_proxyport<br>Port der Proxy (nur verf&uuml;nach einem get config)</li>
    <li>GW_&lt;Gateway-MAC&gt;_config<br>Komplette Konfiguration als HEX-Wert (nur verf&uuml;nach einem get config)</li>
  </ul>
  <br>   

  <a name="MOBILEALERTSGWset"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; clear &lt;readings&gt;</code><br>
    L&ouml;scht die Readings. </li>
    <li><code>set &lt;name&gt; initgateway &lt;gatewayid&gt;</code><br>
    Setzt den Proxy im Gateway auf dem FHEM-Server. Es kann ein Neustart (reboot) des Gateways n&ouml;tig sein, damit die
    Einstellung wirksam wird.</li>    
    <li><code>set &lt;name&gt; rebootgateway &lt;gatewayid&gt;</code><br>
    Startet das Gateway neu.</li>        
  </ul>
  <br>

  <a name="MOBILEALERTSGWget"></a>
  <b>Get</b>
  <ul>
    <li><code>get &lt;name&gt; config &lt;IP or gatewayid&gt; </code><br>
    Holt die Konfiguration eines oder aller Gateways im lokalen Netz. IP bzw. die GatewayId sind optional. 
    Wenn keines von beiden angegeben ist, werden alle Gateways im lokalen Netz gesucht (Broadcast).</li>
  </ul>
  <br>
  <br>

  <a name="MOBILEALERTSGWattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#MOBILEALERTSGWforward">forward</a><br>
      Wenn dieser Wert auf 1 gesetzt ist, werden die Daten zus&auml;tzlich zum MobileAlerts Server http://www.data199.com/gateway/put gesendet.
    </li>
  </ul>
</ul>

=end html_DE
=cut
