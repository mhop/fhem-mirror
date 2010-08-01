#!/usr/bin/perl
#
# read_ws2000 from device (elv art-Nr. 390-61) and provides socket service (like XPORT),
#  or act as client for this service
# licence GPL2
# Thomas Dressler 2008
# $Id: ws2000_reader.pl,v 1.2 2010-08-01 13:33:13 rudolfkoenig Exp $

use Switch;
use strict;
use IO::Socket;
use IO::Select;

our $PortObj;
my $server;
our $xport;
our $sel;
our $clients;
our %sockets;
my ($datum,$data,$lastdate,$lastdata);
$SIG{INT}=$SIG{TERM}=\&signalhandler;
$|=1;

PortOpen($ARGV[0]);

my $ServerPort=$ARGV[1];
if ($ServerPort) {
    $server=IO::Socket::INET->new(LocalPort=>$ServerPort,
                                 ReuseAddr=>1,
                                 Listen=>10,
                                 timeout=>1,
                                 blocking=>0
                                 );
    die "ServerStart-Error: $@ \n" if !$server;
    $clients=IO::Select->new($server);
}


MAINLOOP:
    for(;;) {
        if($server) {
            #only for server mode
            my %message=undef;
            my $fh;
            while(my @ready=$clients->can_read(1)) {
                foreach $fh (@ready) {
                    if ($fh==$server) {
                        #new connection waiting
                        my $new=$server->accept;
                        $new->autoflush(1);
                        $new->blocking(0);
                        $new->timeout(1);
                        $clients->add($new);
                        my $host=$new->peerhost;
                        $sockets{$new}=$host;
                        print "\nNew Client:".$host."\n";
                    #}else{
                    #    my $out=undef;
                    #    $fh->read($out,1);
                    #    $message{$fh}=$out;
                    }
                }
            }
            #check living connections
            foreach my $fh($clients->handles) {
                   next if $fh==$server;
                   next if ($fh->peerhost);
                   print "Terminate ".$sockets{$fh}. " by Check1\n";
                    Client_disconnect($fh);                
            }
            
        }
        $data=get_data();
        next if ! $data;
        $datum = time();
        next if ($data eq $lastdata) && (($datum - $lastdate) < 30);
        my $result=decode_data($data);
        print scalar localtime().":".$result."\n";
        $lastdata = $data;
        $lastdate = $datum;
    }
PortClose();
exit 0;
#--------SUBs -----------------------------
sub Clientdisconnect{
        my $fh=shift;
        print "\n Client ".$sockets{$fh}." disconnected!\n";
        $clients->remove($fh);
        delete $sockets{$fh};
        $fh->shutdown(2);
        $fh->close;
}
sub PortOpen{
    my $PortName=shift;
    my $quiet=shift ||undef;
    
    if ($PortName=~/^\/dev|^COM/) {
    #normal devices (/dev)
        my $OS=$^O;
	if ($OS eq 'MSWin32') {
		eval ("use Win32::SerialPort;");
		die "$@\n" if ($@);
		$PortObj = new Win32::SerialPort ($PortName, $quiet)
	       || die "Can't open $PortName: $^E\n";    # $quiet is optional
	} else {
		eval ("use Device::SerialPort;");
		die "$@\n" if ($@);
		$PortObj = new Device::SerialPort ($PortName, $quiet)
		|| die "Can't open $PortName: $^E\n";    # $quiet is optional
        
	}
#Parameter 19200,8,2,Odd,None
        $PortObj->baudrate(19200);
	$PortObj->databits(8);
	$PortObj->parity("odd");
	$PortObj->stopbits(2);
	$PortObj->handshake("none");
	if (! $PortObj->write_settings) {
		undef $PortObj;
		die "Write Settings failed!\n";
	}
        $sel=IO::Select->new($PortObj->{FD} );
    }elsif($PortName=~/([\w.]+):(\d{1,5})/){
    #Sockets(hostname:port)
        my $host=$1;
        my $port=$2;
        $xport=IO::Socket::INET->new(PeerAddr=>$host,
                                     PeerPort=>$port,
                                     timeout=>1,
                                     blocking=>0
                                     );
        die "Cannot connect to $PortName -> $@ ( $!) \n" if ! $xport;
        $xport->autoflush(1);
        $sel=IO::Select->new($xport);
    }else{
        die "$PortName is no device and not implemented!\n";
    }
}
sub PortClose {
    $PortObj->close if ($PortObj);
    if ($xport) {
        $clients->remove($xport) if $clients;
        $xport->shutdown(2);
        $xport->close;
    }
    if ($clients) {
        foreach my $socket($clients->handles) {
                Clientdisconnect($socket);
         }
    }
}
sub signalhandler {
    my $signal=shift;
    PortClose();
    print "\nTerminated by Signal $signal!\n";
    exit;
}
    
sub get_data {
    
    my $STX=2;
    my $ETX=3;
    my $retval='';
    my $status='';
    my $out=undef;
    my $message;
    my $byte;
    for(;;) {
        #sleep 1 if(!defined($out) || length($out) == 0);
        $out=undef;
        if ($xport) {
           
          #my @readable=$select->can_read(1);
          #next if $#readable<0;
          
          
          #my $fh;
          #foreach $fh (@readable) {
              
          next if ! $sel->can_read(1);
          $xport->read($out,1);
          #if ($xport->eof) {
          #  print "Xport eof\n";
          #  print "Server disconnected, terminate!\n";
          #  PortClose();
           # exit 1;
            
          #}
            
            
                  
        }elsif($PortObj) {
            $out = $PortObj->read(1);
        }
        next if(!defined($out) || length($out) == 0) ;
          
          
        $byte=ord($out);
        if($byte eq $STX) {
        	#Log 4, "M232: return value \'" . $retval . "\'";
        	$status= "STX";
                $message=$out;
        } elsif($byte eq $ETX) {
                $status= "ETX";
                $message .=$out;
        } elsif ($status eq "STX"){
            $byte=$byte & 0x7F;
            $retval .= chr($byte);
            $message .=$out;
        }
        last if($status eq "ETX");
	
    }
    if ($server) {
        foreach my $client($clients->can_write(1)) {
                next if $client == $server;
                if (!$client->send($message)){
                    Clientdisconnect($client);
                    next;
                 }
            
        }
    }
    return $retval;
}


sub decode_data {
    my ($sensor,$daten1,$einheit1,$daten2,$einheit2,$daten3,$einheit3,$result);
    my $data=shift;
    my ($typ,$w1,$w2,$w3,$w4,$w5)=unpack("U*",$data);
    my $group = ($typ & 0x70)/16 ;#/slash for komodo syntax checker!
    my $snr = $typ % 16;
    
    
    switch ( $group ){
        case 7 {
                $sensor = "Fernbedienung";
                $daten1 = $w1 * 10000 + $w2 * 1000 + $w3 * 100 + $w4 * 10 + $w5;
                $result = $sensor . "=" . $daten1 . $einheit1;
            }
        case 0 {
                if ($snr < 8) {
                        $sensor = "Temperatursensor V1.1(" . $snr . ")";
                }else{
                        $sensor = "Temperatursensor V1.2(" .($snr - 8). ")";
                }
                if ($w1 >= 64) {
                    $daten1 = ((255 - $w1 - $w2) / 10) * (-1);
                }else{
                    $daten1 = (($w1 * 128 + $w2) / 10);
                }
                $einheit1 = " °C";
                $result = $sensor . "=" . $daten1 . $einheit1;
            }
        case 1 {
            if ($snr <8) {
                $sensor = "Temperatursensor mit Feuchte V1.1(" . $snr . ")";
            }else{
                $sensor = "Temperatursensor mit Feuchte V1.2(" . ($snr - 8) . ")";
            }
            if ($w1 >= 64) {
                $daten1 = ((255 - $w1 - $w2) / 10) * (-1);
            }else{
                $daten1 = (($w1 * 128 + $w2) / 10);
            }
      
            $daten2 = $w3;
            $daten3 = 0;
            $einheit1 = " °C";
            $einheit2 = " %";
      
            $result = $sensor . "=" . $daten1 . $einheit1 . " " . $daten2 .$einheit2;
        }
        case 2 {
            if ( $snr < 8 ) {
                $sensor = "Regensensor V1.1(" . $snr . ")";
            }else{
                $sensor = "Regensensor V1.2(" . ($snr - 8) . ")"
            }
            $daten1 = ($w1 * 128 + $w2) * 0.36;
            $einheit1 = " l/m²";
            $result = $sensor . "=" . $daten1 . $einheit1;
        }
        case 3 {
            if ($snr < 8) {
                $sensor = "Windsensor V1.1(" . $snr . ")";
            }else{
                $sensor = "Windsensor V1.2(" & ($snr - 8) . ")";
            }
            switch( $w3) {
                case 0 { $einheit3 = "±0 °";}
                case 1 { $einheit3 = "± 22,5 °";}
                case 2 { $einheit3 = "± 45 °";}
                case 3 { $einheit3 = "± 67,5 °";}
            }
            $daten1 = ($w1 * 128 + $w2) / 10;
            $daten2 = $w4 * 128 + $w5;
            $einheit1 = " km/h";
            $einheit2 = " °";
            $result = $sensor . "=" . $daten1 . $einheit1 . " " . $daten2 . $einheit2 . " " . $einheit3;
        }
        case 4 {
            if ($snr < 8) {
                $sensor = "Innensensor V1.1(" . $snr . ")";
            }else{
                $sensor = "Innensensor V1.2(" . ($snr - 8) . ")";
            }
            if ($w1 >= 64) {
                $daten1 = ((255 - $w1 - $w2) / 10) * (-1);
            }else{
                $daten1 = (($w1 * 128 + $w2) / 10);
            }
            $daten2 = $w3;
            $daten3 = $w4 * 128 + $w5;
            $einheit1 = " °C";
            $einheit2 = " %";
            $einheit3 = " hPa";
            $result = $sensor . "=" . $daten1 . $einheit1 . " " . $daten2 . $einheit2 . " " . $daten3 . $einheit3;
        }
        case 5 {
            $sensor = "Helligkeitssensor V1.2(" . ($snr - 8) . ")";
            switch ($w3) {
                case 0 {$daten1 = 1;}
                case 1 {$daten1 = 10;}
                case 2 {$daten1 = 100;}
                case 3 {$daten1 = 1000;}
            }
            $daten1 = $daten1 * ($w1 * 128 + $w2);
            $einheit1 = "Lux";
            $result = $sensor . "=" . $daten1 . $einheit1;
        }
        case 6 {
            $sensor = "Pyranometer V1.2(" . ($snr - 8) . ")";
            switch ($w3) {
                case 0 {$daten1 = 1;}
                case 1 {$daten1 = 10;}
                case 2 {$daten1 = 100;}
                case 3 {$daten1 = 1000;}
            }
            $daten1 = $daten1 * ($w1 * 128 + $w2);
            $einheit1 = " W/m²";
            $result = $sensor . "=" . $daten1 . $einheit1;
        }
        else {
            $sensor = "Störung";
            $daten1 = $typ;
            $result = $sensor . "(Group:" . $group . "/Typ:" . $typ . ")";
        }#switch else
        
    }#switch
    return $result;
}
