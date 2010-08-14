##############################################
package main;

use strict;
use warnings;
use Device::SerialPort;

#####################################
sub
USBWX_Initialize($)
{
my ($hash) = @_;

$hash->{ReadFn}  = "USBWX_Read";
$hash->{ReadyFn} = "USBWX_Ready"; 
# Normal devices 
$hash->{DefFn}   = "USBWX_Define";
$hash->{UndefFn} = "USBWX_Undef"; 

$hash->{GetFn} = "USBWX_Get";
$hash->{SetFn} = "USBWX_Set"; 
$hash->{AttrList}= "model:USB-WDE1 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
USBWX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
          
  return "wrong syntax: define <name> USBWX devicename"
    if(@a != 3);
          
  USBWX_CloseDev($hash);
	
  my $name = $a[0];
  my $dev = $a[2];
          
  if($dev eq "none") {
    Log 1, "USBWX $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
	
  $hash->{DeviceName} = $dev;
  my $ret = USBWX_OpenDev($hash, 0);
  return $ret;
} 

#####################################
sub
USBWX_OpenDev($$)
{
my ($hash, $reopen) = @_;
my $dev = $hash->{DeviceName};
my $name = $hash->{NAME};
my $po;

$hash->{PARTIAL} = "";
Log 3, "USBWX opening $name device $dev"
   if(!$reopen); 

if ($^O=~/Win/) 
   {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
   } 
else 
   {
   require Device::SerialPort;
   $po = Device::SerialPort->new($dev);
   } 

if(!$po) 
   {
   return undef if($reopen);
   Log(2, "USBWX Can't open $dev: $!");
   $readyfnlist{"$name.$dev"} = $hash;
   $hash->{STATE} = "disconnected";
   return "";
   }

$hash->{USBWX} = $po;
if( $^O =~ /Win/ ) 
   {
   $readyfnlist{"$name.$dev"} = $hash;
   } 
else 
   {
   $hash->{FD} = $po->FILENO;
   delete($readyfnlist{"$name.$dev"});
   $selectlist{"$name.$dev"} = $hash;
   } 

$po->baudrate(9600);
$po->databits(8);
$po->parity('none');
$po->stopbits(1);
$po->handshake('none');
$po->reset_error();
$po->lookclear; # clear buffers 
 
if($reopen) 
      {
      Log 1, "USBWX $dev reappeared ($name)";
      } 
else 
      {
      Log 2, "USBWX opened device $dev";
      } 

$hash->{STATE}=""; # Allow InitDev to set the state
my $ret = USBWX_DoInit($hash);

if($ret) 
   {
# try again
      Log 1, "USBWX Cannot init $dev, at first try. Trying again.";
      my $ret = USBWX_DoInit($hash);
      if($ret) 
         {
         USBWX_CloseDev($hash);
         Log 1, "USBWX Cannot init $dev, ignoring it";
#         return "USBWX Error Init string.";
         }
   } 
DoTrigger($name, "CONNECTED") if($reopen);

return undef;
}

########################
sub
USBWX_CloseDev($)
{
my ($hash) = @_;
my $name = $hash->{NAME};
my $dev = $hash->{DeviceName};
	
return if(!$dev);

$hash->{USBWX}->close() ;
delete($hash->{USBWX});
delete($selectlist{"$name.$dev"});
delete($readyfnlist{"$name.$dev"});
delete($hash->{FD});
} 

#####################################
sub
USBWX_Ready($)
{
my ($hash) = @_;
	
return USBWX_OpenDev($hash, 1)
if($hash->{STATE} eq "disconnected");

# This is relevant for windows/USB only
my $po = $hash->{USBWX};
my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
return ($InBytes>0);
} 

#####################################
sub
USBWX_Clear($)
{
my $hash = shift;
my $buf;
	
# clear buffer:
if($hash->{USBWX}) 
   {
   while ($hash->{USBWX}->lookfor()) 
      {
      $buf = USBWX_SimpleRead($hash);
      }
   }

return $buf;
} 

#####################################
sub
USBWX_DoInit($)
{
my $hash = shift;
my $name = $hash->{NAME}; 
my $init ="?";
my $buf;

USBWX_Clear($hash); 
USBWX_SimpleWrite($hash, $init); 

return undef; 
}

#####################################
sub USBWX_Undef($$)
{
my ($hash, $arg) = @_;
my $name = $hash->{NAME};
delete $hash->{FD};
$hash->{STATE}='close';
$hash->{USBWX}->close() if($hash->{USBWX});
Log 2, "$name shutdown complete";
return undef;
} 

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
USBWX_Read($)
{
my ($hash) = @_;
my $name = $hash->{NAME};
my $char;

#Log 4, "USBWX Read State:$hash->{STATE}";

my $mybuf = USBWX_SimpleRead($hash);
my $usbwx_data = $hash->{PARTIAL};
if ( ( length($usbwx_data) > 1) && ($mybuf eq "\n") )
   {
   Log 4, "USBWX/RAW Satz: $usbwx_data !!";
   }
	
if(!defined($mybuf) || length($mybuf) == 0) 
   {
   USBWX_Disconnected($hash);
   return "";
   }

$usbwx_data .= $mybuf;

if ( ( length($usbwx_data) > 27) && ($mybuf eq "\n") )
   {
   USBWX_Parse($hash, $usbwx_data);
   $hash->{PARTIAL} = "";
   }
else
   {
   $hash->{PARTIAL} = $usbwx_data; 
   }
} 


#####################################
sub
USBWX_Set($@)
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
sub
USBWX_Get($@)
{
my ($hash, @a) = @_;
	
my $msg;
my $name=$a[0];
my $reading= $a[1];
$msg="$name => No Get function ($reading) implemented";
Log 1,$msg;
return $msg;
} 

########################
sub
USBWX_SimpleRead($)
{
my ($hash) = @_;
my $buf;
	
if($hash->{USBWX}) 
   {
   $buf = $hash->{USBWX}->read(1) ;
   if (length($buf) == 0) 
      {
      $buf = $hash->{USBWX}->read(1) ;
      }
#   Log 4, "USBWX SimpleRead=>$buf";
   return $buf;
   }

return undef; 
}

########################
sub
USBWX_SimpleWrite(@)
{
my ($hash, $msg) = @_;
return if(!$hash);
$hash->{USBWX}->write($msg) if($hash->{USBWX});
Log 4, "USBWX SimpleWrite $msg";
select(undef, undef, undef, 0.001);
} 

#####################################
sub
USBWX_Parse($$)
{
my ($hash,$rmsg) = @_;
my $name = $hash->{NAME};

Log 4, "USBWX Parse Msg:$rmsg, State:$hash->{STATE}";

my $wxmsg = substr($rmsg, 0, 3); 
my $stmsg = substr($rmsg, 2, 3); 

Log 4, "USBWX Parse >$wxmsg<";
#$1;1;;23,9;;23,6;24,3;;;26,0;;56;;59;58;;;54;;;;;;;0

#$1;1;;;;;;;;;;;;;;;;;;;;;;;0
#1234567890123456789012345678901234567890

if ($wxmsg eq "\$1;")
   {
   my @c = split(";", $rmsg);

   Log 3, "USBWX T1:$c[3] T2:$c[4] T3:$c[5] T4:$c[6] T5:$c[7] T6:$c[8] T7:$c[9] T8:$c[10]";

   $rmsg =~ s/[\r\n]//g; # Delete the NewLine 
   $hash->{READINGS}{$name}{VAL} = $rmsg;
   $hash->{READINGS}{$name}{TIME} = TimeNow();
   $hash->{STATE}=$rmsg;
   $rmsg =~ s/,/./g; # format for FHEM 
   my @data = split(";", $rmsg);
#add WS300 handler here
   my @names = ("T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8");
   my $tn = TimeNow();
   for(my $i = 0; $i < int(@names); $i++)
      {
      if ($data[$i+2] ne "") # only for existing sensors
         {      
 	  $hash->{CHANGED}[$i] = "$names[$i]: $data[$i+2] H: $data[$i+10]";
 	  $hash->{READINGS}{$names[$i]}{TIME} = $tn;
	  $hash->{READINGS}{$names[$i]}{VAL} = $data[$i+2];
         }
	} 
   DoTrigger($name, undef); 
   }
#ELV USB-WDE1 v1.1
#Baud:9600bit/s
#Mode:LogView
elsif ($stmsg eq "ELV")
   {
   Log 4, "USBWX Parse ID";
   my @c = split(" ", $rmsg);
   if ($c[1] eq "USB-WDE1")
      {
      Log 3, "USBWX $c[1] $c[2] found";
      $rmsg =~ s/[\r\n]/ /g;
      $hash->{READINGS}{"status"}{VAL} = $rmsg;
      $hash->{READINGS}{"status"}{TIME} = TimeNow();
      } 
   }
elsif ($wxmsg eq "Mod")
   {
   Log 4, "USBWX Parse mode $rmsg";
   my @c = split(":", $rmsg);
   my @d = split("\n", $c[1]);
   $d[0] =~ s/[\r\n]//g; # Delete the NewLine 
   Log 4, "USBWX Parse mode >$d[0]<";
   if ($d[0] eq "LogView")
      {
      Log 2, "USBWX in $c[0] $d[0] found";
      $hash->{STATE} = "Initialized";

      $hash->{READINGS}{"mode"}{VAL} = $d[0];
      $hash->{READINGS}{"mode"}{TIME} = TimeNow();
      } 
   }
else
   {
   Log 2, "USBWX unknown:$rmsg";
   }
}

#####################################
sub
USBWX_Disconnected($)
{
my $hash = shift;
my $dev = $hash->{DeviceName};
my $name = $hash->{NAME};
 	
return if(!defined($hash->{FD})); # Already deleted
	
Log 1, "USBWX $dev disconnected, waiting to reappear";
USBWX_CloseDev($hash);
$readyfnlist{"$name.$dev"} = $hash; # Start polling
$hash->{STATE} = "disconnected";
	
# Without the following sleep the open of the device causes a SIGSEGV,
# and following opens block infinitely. Only a reboot helps.
sleep(5);

DoTrigger($name, "DISCONNECTED");
} 



1;
