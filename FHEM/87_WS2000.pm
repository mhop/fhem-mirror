package main;
###########################
# 87_ws2000.pm
# Modul for FHEM
#
# contributed by thomas dressler 2008
# $Id$
# corr. negativ temps / peterp
###########################
use strict;
use Switch;
use warnings;

#prototypes to make komodo happy
use vars qw{%attr %defs};
sub Log($$);
our $FH;
####################################
# WS2000_Initialize
# Implements Initialize function
# 
sub WS2000_Initialize($)
{
  my ($hash) = @_;

# Provider
  #$hash->{WriteFn} = "ws2000_Write";
# $hash->{Clients} = ":WS2000Rain:WS2000Wind:WS2000Indoor:WS2000Lux:WS2000Pyro:WS2000Temp:WS2000TempHum";

# Consumer
  $hash->{DefFn}   = "WS2000_Define";
  $hash->{UndefFn} = "WS2000_Undef";
  $hash->{GetFn}   = "WS2000_Get";
  $hash->{SetFn}   = "WS2000_Set";
  $hash->{ReadyFn} = "WS2000_Ready";
  $hash->{ReadFn}   ="WS2000_Read";
  $hash->{ListFn}   ="WS2000_List";
  $hash->{AttrList}= "model:WS2000 rain altitude loglevel:0,1,2,3,4,5";
}

#####################################
# WS2000_Define
# Implements DefFn function
#
sub
WS2000_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  delete $hash->{po};
  delete $hash->{socket};
  delete $hash->{FD};
  my $ws2000_cfg='ws2000.cfg';
   my $quiet=1;
   my $name=$hash->{NAME};
  my $PortName = $a[2];
  my $PortObj;

  if($PortName eq "none") {
    Log 1, "WS2000 device is none, commands will be echoed only";
    return undef;
  }

  Log 4, "WS2000 opening device $PortName";
  
  #switch serial/socket device
  if ($PortName=~/^\/dev|^COM/) {
    #normal devices (/dev), on windows COMx
      my $OS=$^O;
	if ($OS eq 'MSWin32') {
		eval ("use Win32::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Win32::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't use Win32::SerialPort $@\n";
                }
                $PortObj = new Win32::SerialPort ($PortName, $quiet);
                if (!$PortObj) {
                   $hash->{STATE} = "error opening device";
                   Log 1,"Error opening Serial Device $PortName";
                   return "Can't open Device $PortName: $^E\n";
                }
		 #$hash->{FD}=$PortObj->{_HANDLE};
                $readyfnlist{"$a[0].$a[2]"} = $hash;
	} else {
		eval ("use Device::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Device::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't Device::SerialPort $@\n";
                }
		$PortObj = new Device::SerialPort ($PortName, $quiet);
                if (!$PortObj) {
                   $hash->{STATE} = "error opening device";
                   Log 1,"Error opening Serial Device $PortName";
                   return "Can't open Device $PortName: $^E\n";
                }
		$hash->{FD}=$PortObj->FILENO;
               $selectlist{"$a[0].$a[2]"} = $hash;
	}
        #Parameter 19200,8,2,Odd,None
        $PortObj->baudrate(19200);
	$PortObj->databits(8);
	$PortObj->parity("odd");
	$PortObj->stopbits(2);
	$PortObj->handshake("none");
	if (! $PortObj->write_settings) {
		undef $PortObj;
		return "Serial write Settings failed!\n";
	}
        $hash->{po}=$PortObj;
        $hash->{socket}=0;
        
    }elsif($PortName=~/([\w.]+):(\d{1,5})/){
    #Sockets(hostname:port)
        my $host=$1;
        my $port=$2;
        my $xport=IO::Socket::INET->new(PeerAddr=>$host,
                                     PeerPort=>$port,
                                     timeout=>1,
                                     blocking=>0
                                     );
        if (!$xport) {
                   $hash->{STATE} = "error opening device"; 
                   Log 1,"Error opening Connection to $PortName";
                   return "Can't Connect to $PortName -> $@ ( $!)\n";
                }
        $xport->autoflush(1);
        $hash->{FD}=$xport->fileno;
        $selectlist{"$a[0].$a[2]"} = $hash;
        $hash->{socket}=$xport;
        
        
    }else{
        $hash->{STATE} = "$PortName is no device and not implemented";
        Log 1,"$PortName is no device and not implemented";
        return "$PortName is no device and not implemented\n";
    }
  Log 4, "$name connected to device $PortName";
  $hash->{STATE} = "open";
  $hash->{DeviceName}=$PortName;
  return undef;
}

#####################################
# WS2000_Undef
# implements UnDef-Function
#
sub
WS2000_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  delete $hash->{FD};
  $hash->{STATE}='close';
  if ($hash->{socket}) {
    $hash->{socket}->shutdown(2);
    $hash->{socket}->close();
  }elsif ($hash->{po}) {
    $hash->{po}->close();
  }
  Log 5, "$name shutdown complete";
  return undef;
}

#####################################
# WS2000_Set
# implement SetFn
# currently nothing to set
#
sub
WS2000_Ready($$)
{
  my ($hash, $dev) = @_;
  my $po=$hash->{po};
  return undef if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}

#####################################
# WS2000_Set
# implement SetFn
# currently nothing to set
#
sub
WS2000_Set($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];
  $msg="$name => No Set function ($reading) implemented";
    Log 1,$msg;
    return $msg;
  
}

#####################################
# WS2000_Get
# implement GetFn
#
sub
WS2000_Get($@)
{

  my ($hash, @a) = @_;
  my $u1 = "Usage: get <name> [TH0..TH7, T0..T7, I0..I7, R0..R7, W0..W7, L0..L7, P0..P7, LAST, RAW]\n" .
                  "get <name> list\n";
                  

  return $u1 if(int(@a) != 2);

  my $name= $a[0];
  my $reading= $a[1];
  my $msg;
  my $retval;
  my $time;
  my $sensor=$hash->{READINGS};
  if ($reading =~/list/i) {
    $msg='';
    foreach my $s (keys %$sensor) {
      next if !$s;
      $msg.="ID:$s, Last Update ".$sensor->{$s}{TIME}."\n";
    }
  }else {
    if(!defined($sensor->{$reading})) {
      $msg="Sensor ($reading)not defined, try 'get <n<me> list'";  
    }else {
      $retval=$sensor->{$reading}{VAL};
      $time=$sensor->{$reading}{TIME};
      $retval=unpack("H*",$retval) if ($reading eq 'RAW');
      $msg= "$name $reading ($time) => $retval";
    }
  }
  return $msg;
}

#####################################
# WS2000_Write
# currently dummy
#
sub
WS2000_Write($$)
{
  my ($hash,$msg) = @_;


}


#####################################
# WS2000_Read
# Implements ReadFn, called from global select
#
sub
WS2000_Read($$) {
    
my ($hash) = @_;

    my $STX=2;
    my $ETX=3;
    my $retval='';
    my $out=undef;
    my $byte;
    my $name=$hash->{NAME};
    my $xport=$hash->{socket};
    my $PortObj=$hash->{po};
    my $message=$hash->{PARTIAL}||'';
    my $status=$hash->{STEP};
    #read data(1 byte), because fhem select flagged data available
    if ($xport) {
          $xport->read($out,1);              
    }elsif($PortObj) {
            $out = $PortObj->read(1);
    }
    return if(!defined($out) || length($out) == 0) ;
    Log 5, "$name => WS2000/RAW: " . unpack('H*',$out);
    
    #check for frame: STX TYP W1 W2 W3 W4 W5 ETX
        $byte=ord($out);
        if($byte eq $STX) {
        	#Log 4, "M232: return value \'" . $retval . "\'";
        	$status= "STX";
                $message=$out;
                Log 5, "WS2000 STX received";
        } elsif($byte eq $ETX) {
                $status= "ETX";
                $message .=$out;
                Log 5, "WS2000 ETX received";
        } elsif ($status eq "STX"){
            $message .=$out;
        }
        $hash->{STEP}=$status;
        $hash->{PARTIAL}=$message;
        if($status eq "ETX") {
            WS2000_Parse($hash,$message);
        }
}
#####################################
# WS2000_Parse
# decodes complete frame
# called directly from WS2000_Read
sub
WS2000_Parse($$) {
    my ($hash,$msg) = @_;
    my ($stx,$typ,$w1,$w2,$w3,$w4,$w5,$etx)=map {$_ & 0x7F} unpack("U*",$msg);
    my $tm=TimeNow();
    my $name=$hash->{NAME};
    my $factor=$attr{$name}{rain}||366;
    my $altitude=$attr{$name}{altitude}||0;
    if ($etx != 3) {
      Log 4, "$name:Frame Error!";
      return undef;
    }
    my ($sensor,$daten1,$einheit1,$daten2,$einheit2,$daten3,$einheit3,$result,$shortname,$val, $unit);  
    my $group = ($typ & 0x70)/16 ;#/slash for komodo syntax checker!
    my $snr = $typ % 16;
    
    
    #duplicate check (repeater?)
    my $prevmsg=$hash->{READINGS}{RAW}{VAL}||'';
    my $prevtime=$hash->{READINGS}{RAW}{TIME}||0;
    if (($prevmsg eq $msg) && ((time() - $prevtime) <10)) {
      Log 4,"$name check: Duplicate detected";
      return undef;
    }
    my $rawtext="Typ:$typ,W1:$w1,W2:$w2,W3:$w3,W4:$w4,W5:$w5";
    Log 4, "$name parsing: $rawtext";
    
    #break into sensor specs
    switch ( $group ){
        case 7 {
                $sensor = "Fernbedienung";
                $shortname='FB';
                $einheit1='(CODE)';
                $daten1 = $w1 * 10000 + $w2 * 1000 + $w3 * 100 + $w4 * 10 + $w5;
                $result = $shortname . " => D=" . $daten1 . $einheit1;
            }
        case 0 {
                if ($snr < 8) {
                        $sensor = "Temperatursensor V1.1(" . $snr . ")";
                }else{
			$snr -= 8;
                        $sensor = "Temperatursensor V1.2(" .$snr. ")";
                }
             $daten1 = (($w1 * 128 + $w2) );
             if ($daten1 >= 16085) 
                {
                $daten1 = $daten1 - 16384; 
                }
             $daten1 = $daten1 / 10;
		$shortname='TX'.$snr;
                $einheit1 = " C";
                $result = $shortname . " => T:" . $daten1 . $einheit1;
                
            }
        case 1 {
            if ($snr <8) {
                $sensor = "Temperatursensor mit Feuchte V1.1(" . $snr . ")";
            }else{
		$snr -= 8;
                $sensor = "Temperatursensor mit Feuchte V1.2(" . $snr . ")";
            }
             $daten1 = (($w1 * 128 + $w2) );
             if ($daten1 >= 16085) 
                {
                $daten1 = $daten1 - 16384; 
                }
             $daten1 = $daten1 / 10;
	    $shortname='TH'.$snr;
            $einheit1 = " C";
            $daten2 = $w3;
            $daten3 = 0;
            $einheit2 = " %";
            
	    $result = $shortname . " => T:" . $daten1 . $einheit1 . ", H:" . $daten2 .$einheit2;
            
            
        }
        case 2 {
            if ( $snr < 8 ) {
                $sensor = "Regensensor V1.1(" . $snr . ")";
            }else{
		$snr -= 8;
                $sensor = "Regensensor V1.2(" . $snr . ")"
            }
            $shortname='R'.$snr;
            $daten1 = ($w1 * 128 + $w2);
            $einheit1= ' Imp';
            my $prev=$hash->{READINGS}{$shortname}{VAL};
	    if ($prev && $prev=~/C=(\d+)/i) {
	      $prev=$1;
	    }else {
	      $prev=0;
	    }
            my $diff=$daten1-$prev;
            $daten2= $diff * $factor/1000;
            $einheit2 = " l/m2";
            $result = $shortname 
		 . " => M:".$daten2. $einheit2."(". $diff . $einheit1 ." x Faktor $factor)"
		 . ", C:$daten1, P:$prev" ;
            
        }
        case 3 {
            if ($snr < 8) {
                $sensor = "Windsensor V1.1(" . $snr . ")";
            }else{
		$snr -= 8;
                $sensor = "Windsensor V1.2(" . $snr . ")";
            }
            switch( $w3) {
                case 0 { $daten3 = 0;}
                case 1 { $daten3 = 22.5;}
                case 2 { $daten3 = 45;}
                case 3 { $daten3 = 67.5;}
            }
            $einheit3 = " +/-";
            $daten1 = ($w1 * 128 + $w2) / 10;
            $daten2 = $w4 * 128 + $w5;
            $einheit1 = " km/h";
            $einheit2 = " Grad";
	    $shortname='W'.$snr;
	    my @wr=("N","NNO","NO","ONO","O","OSO","SO","SSO","S","SSW","SW","WSW","W","WNW","NW","NNW");
	    my @bf=(0,0.7,5.4,11.9,19.4,38.7,49.8,61.7,74.6,88.9,102.4,117.4);
	    my @bfn=("Windstille","leiser Zug","leichte Brise","schwache Brise","maessige Brise","frische Brise",
                "starker Wind","steifer Wind","stuermischer Wind","Sturm","schwerer Sturm","orkanartiger Sturm","Orkan");
	    my $i=1;
	    foreach  (1..$#bf) {
	          if ($daten1<$bf[$i]) {
                        last;
	          }
                $i++;
	    }
	    $i--;
	    #windrichtung
	    my $w=int($daten2/22.5+0.5);
	    if ($w ==16) {$w=0;}
	    $result = $shortname 
		.  " => S:" . $daten1 . $einheit1 
		.  ", BF:$i($bfn[$i])"
		.  " ,R:" . $daten2 . $einheit2 
		.  "($wr[$w])".$einheit3. $daten3;
          
        }
        case 4 {
            if ($snr < 8) {
                $sensor = "Innensensor V1.1(" . $snr . ")";
            }else{
		$snr -= 8;
                $sensor = "Innensensor V1.2(" . $snr . ")";
            }
             $daten1 = (($w1 * 128 + $w2) );
             if ($daten1 >= 16085) 
                {
                $daten1 = $daten1 - 16384; 
                }
             $daten1 = $daten1 / 10;
	    $shortname='I'.$snr;
            $daten2 = $w3;
            $daten3 = $w4 * 128 + $w5;
            $einheit1 = " C";
            $einheit2 = " %";
            $einheit3 = " hPa";
            $result = $shortname 
		. " => T:" . $daten1 . $einheit1 
		. ", H:" . $daten2 . $einheit2 
		. ", D:" . $daten3 . $einheit3;
            
        }
        case 5 {
	    $snr -= 8 if $snr>7;; #only V1.2 sensors exists
            $sensor = "Helligkeitssensor V1.2(" . $snr . ")";
            $shortname='L'.$snr;
	    switch ($w3) {
                case 0 {$daten1 = 1;}
                case 1 {$daten1 = 10;}
                case 2 {$daten1 = 100;}
                case 3 {$daten1 = 1000;}
            }
            $daten1 = $daten1 * ($w1 * 128 + $w2);
            $einheit1 = "Lux";
            $result = $shortname . " => L:" . $daten1 . $einheit1;
            
        }
        case 6 {
	    #Sensor has been never produced, but maybe there are personal implementations
	    $snr -= 8 if $snr>7;
            $sensor = "Pyranometer V1.2(" . $snr  . ")";
            $shortname='P'.$snr;
	    switch ($w3) {
                case 0 {$daten1 = 1;}
                case 1 {$daten1 = 10;}
                case 2 {$daten1 = 100;}
                case 3 {$daten1 = 1000;}
            }
            $daten1 = $daten1 * ($w1 * 128 + $w2);
            $einheit1 = " W/m2";
            $result = $shortname . " => P:" . $daten1 . $einheit1;
            
        }
        else {
            $shortname="U";
            $sensor = "unknown";
            $daten1 = $typ;
            $result = "(Group:" . $group . "/Typ:" . $typ . ")";
            Log 1, "$name => Unknown sensor detected". $result
        }#switch else
        
    }#switch
    
    #store result
    Log 4, $name." result:".$result;
    $rawtext='RAW => '.$rawtext;
    $hash->{READINGS}{LAST}{VAL}=$result;
    $hash->{READINGS}{LAST}{TIME}=$tm;
    $hash->{READINGS}{RAW}{TIME}=time();
    $hash->{READINGS}{RAW}{VAL}=$msg;
    $hash->{READINGS}{$shortname}{VAL}=$result;
    $hash->{READINGS}{$shortname}{TIME}=$tm;
    $hash->{STATE}=$result;
    $hash->{CHANGED}[0] = $result;
    $hash->{CHANGETIME}[0]=$tm;
    $hash->{CHANGED}[1] = $rawtext;
    $hash->{CHANGETIME}[1]=$tm;
    #notify system
    DoTrigger($name, undef);
    return $result;
}
#####################################
sub
WS2000_List($$)
{
  my ($hash,$msg) = @_;
  $msg=WS2000_Get($hash,$hash->{NAME},'list');
  return $msg;
}


1;

=pod
=begin html

<a name="WS2000"></a>
<h3>WS2000</h3>
<ul>
  <br>

  <a name="WS2000define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WS2000 &lt;device_to_connect&gt;</code>
    <br><br>

    Define a WS2000 series raw receiver device sold by ELV. Details see <a
    href="http://www.elv.de/output/controller.aspx?cid=74&detail=10&detail2=6724">here</a>.
    Unlike 86_FS10.pm it will handle the complete device communication itself
    and doesnt require an external program.  For this reason you can now use
    this also on windows.
    <br>
      This Device will be usually connect to a serial port, but you can also
      define a raw network redirector like lantronix XPORT(TM).
    <br>Note: Currently this device does not support a "set" function
    <br><br>

    Attributes:
    <ul>
      <li><code>rain</code>: factor for calculating amount of rain in ml/count</li>
      <li><code>altitude</code>: height in meters to calculate pressure for NN (not used yet)</li>
    </ul>
    <br>
    Example:
    <ul>
      <code>define WS2000 WS2000 /dev/ttyS0</code><br>
    </ul>
      <ul>
      <code>define WS2000 WS2000 xport:10001</code><br>
    </ul>
      <ul>
      <code>attr WS2000 rain 366</code> : use factor 366 ml/count for rain sensor S2000R<br>
    </ul>
    <br>
  </ul>

  <b>Set</b> <ul>N/A</ul><br>

  <a name="WS2000get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; list</code>
    <br>
    Gets the last reading of all received sensord
    <br><br>
    <code>get &lt;name&gt; [TH0..TH7, T0..T7, I0..I7, R0..R7, W0..W7, L0..L7, P0..P7,LAST,RAW]</code><br>
    get the last reading for the name sensor, <br>
    <code>LAST</code>: Last received Sensor
    <br><br>
    <code>RAW</code>: original Data from interface
    <br><br>
  </ul>


  <a name="WS2000attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (ws2000)</li>
    <li><a href="#loglevel">loglevel</a></li>
    <li>rain</li>
    <li>altitude</li>
  </ul>
  <br>

</ul>

=end html
=cut
