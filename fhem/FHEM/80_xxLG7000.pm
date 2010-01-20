#
# 80_xxLG7000.pm; an FHEM module for interfacing
# with LG's Scarlet Series of LCDs (e. g. LG 47LG7000)
#
# Written by Kai 'wusel' Siering <wusel+fhem@uu.org> around 2010-01-20
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
  "power state"      => "ka %d FF\r",
  "power on"         => "ka %d 01\r",
  "power off"        => "ka %d 00\r",
  "input AV1"        => "xb %d 20\r",
  "input AV2"        => "xb %d 21\r",
  "input AV3"        => "xb %d 22\r",
  "input AV4"        => "xb %d 23\r",
  "input Component"  => "xb %d 40\r",
  "input RGB-PC"     => "xb %d 50\r",
  "input HDMI1"      => "xb %d 90\r",
  "input HDMI2"      => "xb %d 91\r",
  "input HDMI3"      => "xb %d 92\r",
  "input HDMI4"      => "xb %d 93\r",
  "input DVBT"       => "xb %d 00\r",
  "input PAL"        => "xb %d 10\r",
  "selected input"   => "xb %d FF\r",
  "audio mute"       => "ke %d 00\r",
  "audio normal"     => "ke %d 01\r",
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
  "b OK40"    => "input Components",
  "b OK50"    => "input RGB-PC",
  "b OK10"    => "input PAL",
  "b OK00"    => "input DVB-T",
  "e OK00"    => "audio muted",
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
#  $hash->{GetFn}   = "xxLG7000_Get";
#  $hash->{SetFn}   = "xxLG7000_Set";
  $hash->{AttrList}= "SetID:01,02, loglevel:0,1,2,3,4,5";
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
xxLG7000_Set($@)
{
  my ($hash, @a) = @_;
  my $u1 = "Usage: see commandref.html for details\n";

  return $u1 if(int(@a) < 2);
  my $msg;
  my $reading= $a[1];
  my $value;
  my @legal;

  if($reading eq "auto") {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
        @legal= (0..5,"none");
        if(!grep($value eq $_, @legal)) {
                return "Illegal value $value, possible values: @legal";
        }
        if($value eq "none") { $value= 0; } else { $value+=1; }
	$msg= "M" . $value;
  }
  
  elsif($reading eq "start") {
        return $u1 if(int(@a) !=2);
	$msg= "Z1";
  }

  elsif($reading eq "stop") {
        return $u1 if(int(@a) !=2);
	$msg= "Z0";
  }

  elsif($reading eq "octet") {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
        @legal= (0..255);
        if(!grep($value eq $_, @legal)) {
                return "Illegal value $value, possible values: 0..255";
        }
	$msg= sprintf("W%02X", $value);
  }

  elsif($reading =~ /^io[0-7]$/) {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
	return $u1 unless($value eq "0" || $value eq "1");
        $msg= "D" . substr($reading,2,1) . $value;
  }

  else { return $u1; }
		
  my $d = xxLG7000GetData($hash, $msg);
  return "Read error" if(!defined($d));
  return $d;
}


#####################################
sub
xxLG7000_Get($@)
{

  my ($hash, @a) = @_;
  my $u1 = "Usage: get <name> [an0..an5]\n" .
                  "get <name> [io0..io7]\n" .
                  "get <name> octet\n" .
                  "get <name> counter";

  return $u1 if(int(@a) != 2);

  my $name= $a[0];
  my $reading= $a[1];
  my $msg;
  my $retval;
  my ($count,$d,$state,$iscurrent,$voltage);


  if($reading eq "counter") {
	$msg= "z";
  	$d = xxLG7000GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$count= hex $d;
	$retval= $count;
  } 

  elsif($reading =~  /^an[0-5]$/) {
	$msg= "a" . substr($reading,2,1);
  	$d = xxLG7000GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$voltage= (hex substr($d,0,3))*5.00/1024.0;
	$iscurrent= substr($d,3,1);
	$retval= $voltage; # . " " . $iscurrent;
  } 
  
  elsif($reading =~ /^io[0-7]$/) {
	$msg= "d" . substr($reading,2,1);
  	$d = xxLG7000GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$state= hex $d;
	$retval= $state;
  } 

  elsif($reading eq "octet") {
	$msg= "w"; 
  	$d = xxLG7000GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$state= hex $d;
	$retval= $state;
  } 

  else { return $u1; }

  $hash->{READINGS}{$reading}{VAL}= $retval;
  $hash->{READINGS}{$reading}{TIME}= TimeNow();

  return "$name $reading => $retval";
		
}


#####################################
sub
xxLG7000_Write($$)
{
  my ($hash,$msg) = @_;
  my $dev = $hash->{DeviceName};
  my $UnitNo=1;
  my $ret;
  my $retmsg;

  my $sendstring=$commands{$msg};

  if(!defined($sendstring)) {
      return "Unknown command $msg, choose one of " . join(" ", sort keys %commands);
  }

  $sendstring=sprintf($sendstring, $UnitNo); # FIXME! This needs to become a settable attribut!
  $ret=xxLG7000GetData($hash, $sendstring);

  Log 3, "xxLG7000_Write: wrote $msg, received $ret";

  $retmsg=sprintf("%s %s", substr($ret, 0, 1), substr($ret, 5));
  $retmsg=$responses{$retmsg};
  if(!defined($retmsg)) {
      if(substr($ret, 5, 2) eq "NG") {
	  $retmsg="error message";
	  Log 3, "xxLG7000_Write: error message: $ret";
    } else {
	  $retmsg=sprintf("Unknown response %s, help me!");
	  Log 3, "xxLG7000_Write: $retmsg";
      }
  } else {
      Log 3, "xxLG7000_Write: returns $retmsg";
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
