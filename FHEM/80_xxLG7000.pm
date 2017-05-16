#
# 80_xxLG7000.pm; an FHEM module for interfacing
# with LG's Scarlet Series of LCDs (e. g. LG 47LG7000)
#
# Written by Kai 'wusel' Siering <wusel+fhem@uu.org> around 2010-01-20
# $Id$
#
# re-using code of 80_M232.pm by Dr. Boris Neubert
##############################################
package main;

use strict;
use warnings;


sub xxLG7000Write($$);
sub xxLG7000GetData($$);
sub Log($$);
use vars qw {%attr %defs};

my %commands = (
  "power state"      => "ka %x FF\r",
  "power on"         => "ka %x 01\r",
  "power off"        => "ka %x 00\r",
  "input AV1"        => "xb %x 20\r",
  "input AV2"        => "xb %x 21\r",
  "input AV3"        => "xb %x 22\r",
  "input AV4"        => "xb %x 23\r",
  "input Component"  => "xb %x 40\r",
  "input RGB-PC"     => "xb %x 50\r",
  "input HDMI1"      => "xb %x 90\r",
  "input HDMI2"      => "xb %x 91\r",
  "input HDMI3"      => "xb %x 92\r",
  "input HDMI4"      => "xb %x 93\r",
  "input DVB-T"      => "xb %x 00\r",
  "input PAL"        => "xb %x 10\r",
  "selected input"   => "xb %x FF\r",
  "audio mute"       => "ke %x 00\r",
  "audio normal"     => "ke %x 01\r",
  "audio state"      => "ke %x FF\r",
);

my %responses = (
  "a OK00"    => "power off",
  "a OK01"    => "power on",
  "b OK20"    => "input AV1",
  "b OK21"    => "input AV2",
  "b OK22"    => "input AV3",
  "b OK23"    => "input AV4",
  "b OK90"    => "input HDMI1",
  "b OK91"    => "input HDMI2",
  "b OK92"    => "input HDMI3",
  "b OK93"    => "input HDMI4",
  "b OKa0"    => "input HDMI1-no_link", # At least 47LG7000 returns 10100001 instead of 10010001 when
  "b OKa1"    => "input HDMI2-no_link", # there is no link/signal connected to the corresponding
  "b OKa2"    => "input HDMI3-no_link", # HDMI input. -wusel, 2010-01-20
  "b OKa3"    => "input HDMI4-no_link",
  "b OK40"    => "input Components",
  "b OK50"    => "input RGB-PC",
  "b OK10"    => "input PAL",           # Selecting analogue (dubbed PAL here) input does not work for
  "b OK00"    => "input DVB-T",         # me; well, there's nothing to see anymore anyway, at least
  "e OK00"    => "audio muted",         # in Germany ;) (Ack, I don't have CATV.) -wusel, 2010-01-20
  "e OK01"    => "audio normal",
);



#####################################
sub
xxLG7000_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn} = "xxLG7000_Write";
  $hash->{Clients} = ":LGTV:";
# No ReadFn as this is a purely command->response interface, in contrast
# to e. g. CUL which send's data on it's own. -wusel

# Consumer
  $hash->{DefFn}   = "xxLG7000_Define";
  $hash->{UndefFn} = "xxLG7000_Undef";
  $hash->{AttrList}= "SetID:1,2,... loglevel:0,1,2,3,4,5";
}


#####################################
sub
xxLG7000_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE} = "Initialized";

  my $dev = $a[2];
  if($dev eq "none") {
    Log 1, "xxLG7000 device is none, commands will be echoed only";
    return undef;
  }

  Log 3, "xxLG7000 opening device $dev";
  my $po;
	if ($^O eq 'MSWin32') {
		eval ("use Win32::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Win32::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't use Win32::SerialPort $@\n";
                }
                $po = new Win32::SerialPort ($dev, 1);
                
	} else {
		eval ("use Device::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Device::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't Device::SerialPort $@\n";
                }
		$po = new Device::SerialPort ($dev, 1);
	}
	if (!$po) {
                   $hash->{STATE} = "error opening device";
                   Log 1,"Error opening Serial Device $dev";
                   return "Can't open Device $dev: $^E\n";
	}
  
  Log 3, "xxLG7000 opened device $dev";
  $po->close();

  $hash->{DeviceName} = $dev;
  $attr{$a[0]}{SetID}=1;
  return undef;
}


#####################################
sub
xxLG7000_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  return undef;
}


#####################################
# implement ReadyFn, only used for Win32
sub
xxLG7000_Ready($$)
{
  my ($hash, $dev) = @_;
  my $po=$dev||$hash->{po};
  return 0 if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}


#####################################
sub
xxLG7000_Write($$)
{
  my ($hash,$msg) = @_;
  my $dev = $hash->{DeviceName};
  my $UnitNo=1;
  my $ret;
  my $retmsg="error occured";
  my $myname=$hash->{NAME};


  if(defined($attr{$myname}{SetID})) {
      $UnitNo=$attr{$myname}{SetID};
      Log $UnitNo==1?5:4, "xxLG7000_Write: Using SetID $UnitNo for $myname.";
  }

  my $sendstring=$commands{$msg};

  if(!defined($sendstring)) {
      return "error unknown command $msg, choose one of " . join(" ", sort keys %commands);
  }

  $sendstring=sprintf($sendstring, $UnitNo);
  Log 5, "xxLG7000_Write: sending $sendstring";
  $ret=xxLG7000GetData($hash, $sendstring);
  if(!defined($ret) || length($ret)<=6) {
      Log 2, "xxLG7000_Write: error, got too short answer ($ret).";
  } else {
      Log 5, "xxLG7000_Write: wrote $msg, received $ret";

      $retmsg=sprintf("%s %s", substr($ret, 0, 1), substr($ret, 5));
      $retmsg=$responses{$retmsg};
      if(!defined($retmsg)) {
	  if(substr($ret, 5, 2) eq "NG") {
	      $retmsg="error message";
	      Log 5, "xxLG7000_Write: error message: $ret";
	  } else {
	      Log 2, "xxLG7000_Write: Unknown response $ret, help me!";
	      $retmsg=sprintf("error message_unknown:%s", $ret =~ s/ /_/);
	  }
      } else {
	  Log 5, "xxLG7000_Write: returns $retmsg";
      }
  }

  return $retmsg;
}


#####################################
sub
xxLG7000GetData($$)
{
    my ($hash, $data) = @_;
    my $dev=$hash->{DeviceName};
    my $serport;
    my $d = $data;
    my $MSGACK= 'x';
    
    if ($^O eq 'MSWin32') {
	$serport=new Win32::SerialPort ($dev, 1);
    } else {
	$serport=new Device::SerialPort ($dev, 1);
    }
    if(!$serport) {
	Log 3, "xxLG7000: Can't open $dev: $!";
	return undef;
    }
    $serport->reset_error();
    $serport->baudrate(9800);
    $serport->databits(8);
    $serport->parity('none');
    $serport->stopbits(1);
    $serport->handshake('none');
    $serport->write_settings;
    $hash->{po}=$serport;
    Log 4, "xxLG7000: Sending $d";
    
    my $rm = "xxLG7000: ?";
    
    $serport->lookclear;
    $serport->write($d);
    
    my $retval = "";
    my $status = "";
    my $nfound=0;
    my $ret=undef;
    sleep(1);
    for(;;) {
	if ($^O eq 'MSWin32') {
	    $nfound=xxLG7000_Ready($hash,undef);
	} else {
	    my ($rout, $rin) = ('', '');
	    vec($rin, $serport->FILENO, 1) = 1;
	    $nfound = select($rin, undef, undef, 1.0); # 3 seconds timeout
	    if($nfound < 0) {
		next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
		$rm="xxLG7000:Select error $nfound / $!";
		last;
	    }
	}
	
	last if($nfound == 0);
	
	my $out = $serport->read(1);
	if(!defined($out) || length($out) == 0) {
	    $rm = "xxLG7000 EOF on $dev";
	    last;
	}
	
	if($out eq $MSGACK) {
	    $rm= "xxLG7000: acknowledged";
	    Log 4, "xxLG7000: return value \'" . $retval . "\'";
	    $status= "ACK";
	} else {
	    $retval .= $out;
	}
	
	if($status) {
	    $ret=$retval;
	    last;
	}
	
    }
    
  DONE:
    $serport->close();
    undef $serport;
    delete $hash->{po} if exists($hash->{po});
    Log 4, $rm;
    return $ret;
}

1;

=pod
=begin html

<a name="xxLG7000"></a>
<h3>xxLG7000</h3>
<ul>
  <br>

  <a name="xxLG7000define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; xxLG7000 &lt;serial-device&gt;</code>
    <br><br>

    Defines a serial link to a TV set of LG's xxLG70yy (e. g. 47LG7000) series
    and similar TV sets from <a href="http://www.lge.com/">LG</a>. As of January 2010, the following TV sets should
    be compatible:<br><br>
    <ul>
    <li><code>xxLG7000</code>, e. g. 47LG7000 (tested)</li>
    <li><code>xxPG7000</code>, e. g. 50PG7000 (same Manual as 47LG7000 ;))</li>
    <li><code>PS3000/6000/7000/8000 series</code> (according to <a href="http://www.lge.com/uk/products/documents/LGSV09-LR.pdf">LG brochure</a>; no liabilities assumed)</li>
    <li><code>PQ3000/6000 series</code> (see PS3000)</li>
    <li><code>LU4000/5000 series</code> (<i>not LU7000</i>; see PS3000)</li>
    <li><code>LH2000/3000/4000/5000 series</code> (see PS3000)</li>
    <li><code>SL9500/9000/8000 series</code> (see PS3000)</li>
    </ul><br>
    These TV sets feature a serial connector which can officially be used to control
    the TV set (see your Onwer's Manual, there's an Appendix labelled "External Control
    Device setup", referening to cabling and command set). The xxLG7000 module is
    the FHEM module to actually utilize this. (BTW, those TVs run Linux internally ;))<br><br>
    To exercise control over your TV set, use the <a href="#LGTV">LGTV</a> module and
    bind it ("attr &lt;LGTV-name&gt; IODev &lt;xxLG7000-name&gt;") to xxLG7000.<br><br>

    Examples:
    <ul>
      <code>define myLG7k xxLG7000 /dev/ttyUSB1</code><br>
    </ul>
    <br>
    </ul>

  <a name="xxLG7000set"></a>
  <b>Set </b>
  <ul> Not used, nothing to set directly. </ul>

  <a name="xxLG7000get"></a>
  <b>Get</b>
  <ul> Not used, nothing to get directly. </ul>

  <a name="xxLG7000attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li>SetID (1, 2, ...; see your TV's Owner's Manual how to set it. Defaults to 1 if unset.)</li>
  </ul>
  <br>
</ul>


=end html
=cut
