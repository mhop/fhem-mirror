#################################################################################
# 70_USBWX.pm
# Module for FHEM to receive sensors via ELV USB-WDE1
#
# derived from previous 70_USBWX.pm version written by "Peter from Vienna"
#
# Willi Herzig, 2011
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##############################################
# $Id$
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
  $hash->{ParseFn}   = "USBWX_Parse";

  $hash->{StateFn} = "USBWX_SetState";

  $hash->{Match}     = ".*";

  #$hash->{AttrList}= "model:USB-WDE1 loglevel:0,1,2,3,4,5,6";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6";

  $hash->{ShutdownFn} = "USBWX_Shutdown";

}

#####################################
sub
USBWX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
          
  return "wrong syntax: 'define <name> USBWX <devicename>' or define <name> USBWX <code> [<corr1>...<corr4>]"
    if(@a < 3);
          
  if ($a[2] =~/^[0-9].*/) {
	# define <name> USBWX <code> [<corr1>...<corr4>]
 	return "wrong syntax: define <name> USBWX <code> [corr1...corr4]"
            if(int(@a) < 3 || int(@a) > 7);
  	return "Define $a[0]: wrong CODE format: valid is 1-8"
                if($a[2] !~ m/^[1-9]$/);

	#Log 1,"USBWX_Define def=$def";

  	my $name = $a[0];
  	my $code = $a[2];

  	$hash->{CODE} = $code;
  	$hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  	$hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  	$hash->{corr3} = ((int(@a) > 5) ? $a[5] : 0);
  	$hash->{corr4} = ((int(@a) > 6) ? $a[6] : 0);
  	$modules{USBWX}{defptr}{$code} = $hash;
  	#AssignIoPort($hash);

  } else {
  	# define <name> USBWX <devicename>

  	return "wrong syntax: define <name> USBWX <devicename>"
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
  return undef;
} 

#####################################
sub
USBWX_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;

#Log 1, "USBWX opening $name device $dev reopen = $reopen";

  $hash->{PARTIAL} = "";
  Log 3, "USBWX opening $name device $dev"
   	if(!$reopen); 

  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else {
     require Device::SerialPort;
     $po = new Device::SerialPort ($dev);
  } 

  if(!$po) {
   return undef if($reopen);
   Log(2, "USBWX Can't open $dev: $!");
   $readyfnlist{"$name.$dev"} = $hash;
   $hash->{STATE} = "disconnected";
   return "";
  }

  $hash->{USBWX} = $po;

  if( $^O =~ /Win/ ) {
   $readyfnlist{"$name.$dev"} = $hash;
  } else {
   $hash->{FD} = $po->FILENO;
   delete($readyfnlist{"$name.$dev"});
   $selectlist{"$name.$dev"} = $hash;
  } 

  $po->baudrate(9600) || Log 1, "USBWX could not set baudrate";
  $po->databits(8) || Log 1, "USBWX could not set databits";
  $po->parity('none') || Log 1, "USBWX could not set parity";
  $po->stopbits(1) || Log 1, "USBWX could not set stopbits";
  $po->handshake('none') || Log 1, "USBWX could not set handshake";
  #$po->reset_error() || Log 1, "USBWX reset_error";
  $po->lookclear || Log 1, "USBWX could not set lookclear";

  $po->write_settings || Log 1, "USBWX could not write_settings $dev";
 
  if($reopen) {
      Log 1, "USBWX $dev reappeared ($name)";
  } else {
      Log 2, "USBWX opened device $dev";
  } 

    $hash->{po} = $po;
    $hash->{socket} = 0;

  $hash->{STATE}=""; # Allow InitDev to set the state
  my $ret = USBWX_DoInit($hash);

  if($ret) {
    # try again
    Log 1, "USBWX Cannot init $dev, at first try. Trying again.";
    my $ret = USBWX_DoInit($hash);
    if($ret) {
      USBWX_CloseDev($hash);
      Log 1, "USBWX Cannot init $dev, ignoring it";
      return "USBWX Error Init string.";
    }
  } 

  DoTrigger($name, "CONNECTED") if($reopen);

  #return undef;
  return $ret;
}

########################
sub
USBWX_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};
	
  return if(!$dev);

  Log 1, "USBWX: closing $dev";

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
USBWX_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
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
  #Log 1, "USBWX usbwxdata='$usbwx_data' $mybuf='$mybuf'";

  if(!defined($mybuf) || length($mybuf) == 0) {
  	USBWX_Disconnected($hash);
   	return "";
  }

  if ( ( length($usbwx_data) > 1) && ($mybuf eq "\n") ) {
   	Log 4, "USBWX/RAW line: '$usbwx_data'";
   	#Log 1, "USBWX/RAW line='$usbwx_data'";
  }

  if ($mybuf eq "\n") {
   	USBWX_Parse($hash, $usbwx_data);
   	$hash->{PARTIAL} = "";
  } else {
  	$usbwx_data .= $mybuf;
   	$hash->{PARTIAL} = $usbwx_data; 
  }

} 

#####################################
sub
USBWX_Shutdown($)
{
  my ($hash) = @_;
  return undef;
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
   if (!defined($buf) || length($buf) == 0) 
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

# -----------------------------
# Dewpoint calculation.
# see http://www.faqs.org/faqs/meteorology/temp-dewpoint/ "5. EXAMPLE"
sub
dewpoint($$)
{
        my ($temperature, $humidity) = @_;

        my $dp;

        my $A = 17.2694;
        my $B = ($temperature > 0) ? 237.3 : 265.5;
        my $es = 610.78 * exp( $A * $temperature / ($temperature + $B) );
        my $e = $humidity/ 100 * $es;
        if ($e == 0) {
                Log 1, "Error: dewpoint() e==0: temp=$temperature, hum=$humidity";
                return 0;
        }
        my $e1 = $e / 610.78;
        my $f = log( $e1 ) / $A;
        my $f1 = 1 - $f;
        if ($f1 == 0) {
                Log 1, "Error: dewpoint() (1-f)==0: temp=$temperature, hum=$humidity";
                return 0;
        }
        $dp = $B * $f / $f1  ;
        return($dp);
}

#####################################
sub
USBWX_Parse($$)
{
  my ($hash,$rmsg) = @_;

  $rmsg =~ s/[\r\n]//g;

  #Log 4, "USBWX Parse Msg:$rmsg, State:$hash->{STATE}";

  # Testmessages
  #$rmsg = "\$1;1;;;;;;;23,5;21,0;24,2;;;;;;36;42;;16,8;39;6,1;5;0;0";

  if ($rmsg =~ /^\$1;.*/) {
  	#$1;1;;23,9;;23,6;24,3;;;26,0;;56;;59;58;;;54;;;;;;;0
  	#$1;1;;;;;;;;;;;;;;;;;;;;;;;0

	Log 4, "USBWX Parse Msg:'$rmsg', State:$hash->{STATE}";

	# Reset to clear data already read. Otherwise data will be read multiple times.
	USBWX_SimpleWrite($hash, "RESET"); 

  	my @c = split(";", $rmsg);
   	#Log 4, "USBWX T1:$c[3] T2:$c[4] T3:$c[5] T4:$c[6] T5:$c[7] T6:$c[8] T7:$c[9] T8:$c[10]";

   	$rmsg =~ s/,/./g; # format for FHEM 
   	my @data = split(";", $rmsg);
   	my @names = ("1", "2", "3", "4", "5", "6", "7", "8");
   	my $tm = TimeNow();
	# perform sensors with ID 1 up to 8
   	for(my $i = 0; $i < int(@names); $i++) {
		my $sensor = "";
		my $val = "";
		my $current;

      		if ($data[$i+3] ne "") { # only for existing sensors

   			my $n = 0;

  			my $device_name = $names[$i];
			my $code = $i+1;
  			#Log 1, "i=$i, device_name=$device_name code=$code";

  			my $def = $modules{USBWX}{defptr}{"$device_name"};

  			if(!$def) {
				Log 3, "USBWX: Unknown device USBWX_$device_name, please define it";
				#Log 1, "USBWX: Unknown device USBWX_$device_name, please define it";
    				my $ret = "UNDEFINED USBWX_$device_name USBWX $device_name";
				DoTrigger("global", $ret);
				return undef;
  			}

  			my $name = $def->{NAME};

  			my $temperature = $data[$i+3] + $def->{corr1};;
			$current = $temperature;
			$val .= "T: ".$current."  ";
			$sensor = "temperature";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $current;
			$def->{CHANGED}[$n++] = $sensor . ": " . $current;

			if ($data[$i+11] ne "") {
  				my $humidity = $data[$i+11] + $def->{corr2};;
				$current = $humidity;
				$val .= "H: ".$current."  ";
				$sensor = "humidity";			
				$def->{READINGS}{$sensor}{TIME} = $tm;
				$def->{READINGS}{$sensor}{VAL} = $current;
				$def->{CHANGED}[$n++] = $sensor . ": " . $current;

				my $dewpoint = sprintf("%.1f", dewpoint($temperature,$humidity));
				$current = $dewpoint;
				$sensor = "dewpoint";			
				$def->{READINGS}{$sensor}{TIME} = $tm;
				$def->{READINGS}{$sensor}{VAL} = $current;
				$def->{CHANGED}[$n++] = $sensor . ": " . $current;
			}

  			#Log 1, "i=$i, device_name=$device_name temp=$temperature, hum=$humidity";
  			if ("$val" ne "") {
    				$def->{STATE} = $val;
    				$def->{TIME} = $tm;
    				$def->{CHANGED}[$n++] = $val;
			}

 	  		DoTrigger($name, undef); 
  		}
  	} 
	# Look for KS300 data:
	if ($data[19] ne "") {
		my $n = 0;
		my $sensor = "";
		my $val = "";
		my $current;

		my $ks300_temperature = $data[19]; # KS300 temperature
		my $ks300_humidity = $data[20]; # KS300 humidity
		my $ks300_windspeed = $data[21]; # KS300 windspeed km/h
		my $ks300_rain = $data[22]; # KS300 rain (units)
		my $ks300_israining = $data[23]; # KS300 rain indicator 1=yes, 0=no

		Log 4, "USBWX Parse KS300 data found $ks300_temperature, $ks300_humidity, $ks300_windspeed, $ks300_rain, $ks300_israining ";

 		my $device_name = "9";

		my $def = $modules{USBWX}{defptr}{"$device_name"};

		if(!$def) {
			Log 3, "USBWX: Unknown device USBWX_ks300, please define it";
			#Log 1, "USBWX: Unknown device USBWX_ks300, please define it";
			my $ret = "UNDEFINED USBWX_ks300 USBWX $device_name";
			DoTrigger("global", $ret);
			return undef;
		}

		my $name = $def->{NAME};

		$current = $ks300_temperature;
		$val .= "T: ".$current."  ";
		$sensor = "temperature";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$current = $ks300_humidity;
		$val .= "H: ".$current."  ";
		$sensor = "humidity";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		my $dewpoint = sprintf("%.1f", dewpoint($ks300_temperature,$ks300_humidity));
		$current = $dewpoint;
		$sensor = "dewpoint";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$current = $ks300_windspeed;
		$val .= "W: ".$current."  ";
		$sensor = "wind";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$current = $ks300_rain;
		$sensor = "rain_raw";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$current = $ks300_rain * 255 / 1000;
		$val .= "R: ".$current."  ";
		$sensor = "rain";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$current = $ks300_israining ? "yes" : "no";
		$val .= "IR: ".$current."  ";
		$sensor = "israining";			
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;

		$def->{STATE} = $val;
		$def->{TIME} = $tm;
		$def->{CHANGED}[$n++] = $val;

  		DoTrigger($name, undef); 
	}

  } elsif ($rmsg =~ /^ELV.*/) {
  	#ELV USB-WDE1 v1.1
  	#Baud:9600bit/s
  	#Mode:LogView
   	Log 4, "USBWX Parse ID";
   	my @c = split(" ", $rmsg);
   	if ($c[1] eq "USB-WDE1") {
      		Log 4, "USBWX $c[1] $c[2] found";
      		$rmsg =~ s/[\r\n]/ /g;
      		$hash->{READINGS}{"status"}{VAL} = $rmsg;
      		$hash->{READINGS}{"status"}{TIME} = TimeNow();
   	} 
  } elsif ($rmsg =~ /^Mod.*/) {
   	Log 4, "USBWX Parse mode $rmsg";
   	my @c = split(":", $rmsg);
   	my @d = split("\n", $c[1]);
   	$d[0] =~ s/[\r\n]//g; # Delete the NewLine 
   	Log 4, "USBWX Parse mode >$d[0]<";
   	if ($d[0] eq "LogView") {
      		Log 2, "USBWX in $c[0] $d[0] found. rmsg=$rmsg";
      		#Log 2, "USBWX in $c[0] $d[0] found";
      		$hash->{STATE} = "Initialized";

      		$hash->{READINGS}{"mode"}{VAL} = $d[0];
      		$hash->{READINGS}{"mode"}{TIME} = TimeNow();
      	} 
  } elsif ($rmsg =~ /^Baud.*/) {
   	Log 4, "USBWX BAUD rmsg='$rmsg'";
  } elsif ($rmsg =~ /^OK.*/) {
   	Log 4, "USBWX EMPTY rmsg='$rmsg'";
  } elsif ($rmsg =~ /^FullBuff/) {
   	Log 1, "USBWX Fullbuf-Error rmsg='$rmsg'";
   	Log 1, "USBWX closing device";
	USBWX_Disconnected($hash);
   	Log 1, "USBWX opening device";
	my $ret = USBWX_OpenDev($hash, 0);
  } elsif ($rmsg eq "") {
   	Log 4, "USBWX OK rmsg='$rmsg'";
  } else {
   	Log 2, "USBWX unknown: '$rmsg'";
  }
  return undef;
}

#####################################
sub
USBWX_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
 	
  return if(!defined($hash->{FD})); # Already deleted
	
  Log 1, "USBWX dev='$dev' name='$name' disconnected, waiting to reappear";
  USBWX_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";
	
  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
} 



1;

=pod
=begin html

<a name="USBWX"></a>
<h3>USBWX</h3>
<ul>
  The USBWX module interprets the messages received by the ELV <a
href="http://www.elv.de/output/controller.aspx?cid=74&detail=10&detail2=29870">USB-WDE1</a>
  weather receiver. This receiver is compaptible with the following ELV sensors:
  KS200/KS300, S300IA, S300TH, ASH2200, PS50. It also known to work with Conrad
  weather sensors KS555, S555TH and ASH555.<br> This module was tested with ELV
  S300TH, ELV ASH2200, ELV KS300, Conrad S555TH and Conrad KS555. <br> Readings
  and STATE of temperature/humidity sensors are compatible with the CUL_WS
  module. For KS300/KS555 sensors STATE is compatible with the KS300 module. The
  module is integrated into autocreate to generate the appropriate filelogs and
  weblinks automatically.
  <br><br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the devices is connected via USB or a serial port.
  <br><br>

  <a name="USBWXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; USBWX &lt;serial device&gt;</code>
    <br>
    <br>Defines USB-WDE1 attached via usb.<br>
    <br>
    <code>define &lt;name&gt; USBWX &lt;code&gt; [corr1...corr4]</code> <br>
    <br>
    &lt;code&gt; is the code which must be set on the sensor. Valid values
    are 1 through 8. <br> 9 is used as the sensor id of the ks300 sensor.<br>
    corr1..corr4 are up to 4 numerical correction factors, which will be added
    to the respective value to calibrate the device. Note: rain-values will be
    multiplied and not added to the correction factor.
    <br>
    <br>
    Example:<pre>
    define USBWDE1 USBWX /dev/ttyUSB0
    define USBWX_1 USBWX 1
    define USBWX_livingroom USBWX 2
    define USBWX_ks300 USBWX 9
    </pre>
  </ul>

  <a name="USBWXset"></a>
  <b>Set</b> <ul>N/A</ul><br>
  <a name="USBWXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="USBWXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a></li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>
</ul>

=end html
=cut
