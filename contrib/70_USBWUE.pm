#################################################################################
# 70_USBWUE.pm
# Module for FHEM to receive sensors via ELV USB-WUE
#
# derived from previous 70_USBWX.pm version
#
# Daniel W. from Bern 2012
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##############################################
# 
package main;

use strict;
use warnings;
#use Device::SerialPort;
use Win32::SerialPort;

#####################################
sub
USBWUE_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "USBWUE_Read";
  $hash->{ReadyFn} = "USBWUE_Ready"; 
  # Normal devices 
  $hash->{DefFn}   = "USBWUE_Define";
  $hash->{UndefFn} = "USBWUE_Undef"; 

  $hash->{GetFn} = "USBWUE_Get";
  $hash->{SetFn} = "USBWUE_Set"; 


  $hash->{StateFn} = "USBWUE_SetState";

  #$hash->{Match}     = ".*";

  #$hash->{AttrList}= "model:USB-WDE1 loglevel:0,1,2,3,4,5,6";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6";

  $hash->{ShutdownFn} = "USBWUE_Shutdown";

}

#####################################
sub
USBWUE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
          
  return "wrong syntax: 'define <name> USBWUE <devicename>' or define <name> USBWUE <code> [<corr1>...<corr4>]"
    if(@a < 3);
          
  if ($a[2] =~/^[0-9].*/) {
	# define <name> USBWUE <code> [<corr1>...<corr4>]
 	return "wrong syntax: define <name> USBWUE <code> [corr1...corr4]"
            if(int(@a) < 3 || int(@a) > 7);
  	return "Define $a[0]: wrong CODE format: valid is 0 - 8"
                if($a[2] !~ m/^0+[0-8]$/);

	Log 1,"USBWUE_Define def=$def";

  	my $name = $a[0];
  	my $code = $a[2];

  	$hash->{CODE} = $code;
  	$hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  	$hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  	$hash->{corr3} = ((int(@a) > 5) ? $a[5] : 0);
  	$hash->{corr4} = ((int(@a) > 6) ? $a[6] : 0);
  	$modules{USBWUE}{defptr}{$code} = $hash;


  } else {
  	# define <name> USBWUE <devicename>

  	return "wrong syntax: define <name> USBWUE <devicename>"
    	  if(@a != 3);

  	USBWUE_CloseDev($hash);

  	my $name = $a[0];
  	my $dev = $a[2];
          
	  if($dev eq "none") {
	    Log 1, "USBWUE $name device is none, commands will be echoed only";
    	$attr{$name}{dummy} = 1;
    	return undef;
  	}
	
  	$hash->{DeviceName} = $dev;
  	my $ret = USBWUE_OpenDev($hash, 0);
	return $ret;
  }
  return undef;
} 

#####################################
sub
USBWUE_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;

  #Log 1, "USBWUE opening $name device $dev reopen = $reopen";

  Log 3, "USBWUE opening $name device $dev"
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
   Log(2, "USBWUE Can't open $dev: $!");
   $readyfnlist{"$name.$dev"} = $hash;
   $hash->{STATE} = "disconnected";
   return "";
  }

  $hash->{USBWUE} = $po;

  if( $^O =~ /Win/ ) {
   $readyfnlist{"$name.$dev"} = $hash;
  } else {
   $hash->{FD} = $po->FILENO;
   delete($readyfnlist{"$name.$dev"});
   $selectlist{"$name.$dev"} = $hash;
  } 

  $po->baudrate(4800) || Log 1, "USBWUE could not set baudrate";
  $po->databits(8) || Log 1, "USBWUE could not set databits";
  $po->parity('none') || Log 1, "USBWUE could not set parity";
  $po->stopbits(1) || Log 1, "USBWUE could not set stopbits";
  $po->handshake('none') || Log 1, "USBWUE could not set handshake";

  $po->lookclear || Log 1, "USBWUE could not set lookclear";

  $po->are_match(pack( 'H[18]', '0000000000020ca201' ));

  $po->write_settings || Log 1, "USBWUE could not write_settings $dev";
 
  if($reopen) {
      Log 1, "USBWUE $dev reappeared ($name)";
  } else {
      Log 2, "USBWUE opened device $dev";
  } 

    $hash->{po} = $po;
    $hash->{socket} = 0;

  $hash->{STATE}=""; # Allow InitDev to set the state
  my $ret = USBWUE_DoInit($hash);

  if($ret) {
    # try again
    Log 1, "USBWUE Cannot init $dev, at first try. Trying again.";
    my $ret = USBWUE_DoInit($hash);
    if($ret) {
      USBWUE_CloseDev($hash);
      Log 1, "USBWUE Cannot init $dev, ignoring it";
      return "USBWUE Error Init string.";
    }
  } 

  DoTrigger($name, "CONNECTED") if($reopen);

  #return undef;
  return $ret;
}

########################
sub
USBWUE_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};
	
  return if(!$dev);

  Log 1, "USBWUE: closing $dev";

  $hash->{USBWUE}->close() ;
  delete($hash->{USBWUE});

  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
} 

#####################################
sub
USBWUE_Ready($)
{
  my ($hash) = @_;
	
  return USBWUE_OpenDev($hash, 1) if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBWUE};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;

  
  return ($InBytes>0);
} 

#####################################
sub
USBWUE_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#####################################
sub
USBWUE_Clear($)
{
my $hash = shift;
my $buf;
	
# clear buffer:
if($hash->{USBWUE}) 
   {
   while ($hash->{USBWUE}->lookfor()) 
      {
      $buf = USBWUE_SimpleRead($hash);
      }
   }

return $buf;
} 

#####################################
sub
USBWUE_DoInit($)
{
my $hash = shift;
my $name = $hash->{NAME}; 
my $init;
my $buf;

USBWUE_Clear($hash); 

$init = pack( 'H[08]', '0202fb00' ); #hexmode
USBWUE_SimpleWrite($hash, $init); 
$init = pack( 'H[08]', '0202f201' ); #Wetterdaten sofort ausgeben
USBWUE_SimpleWrite($hash, $init); 

return undef; 
}

#####################################
sub USBWUE_Undef($$)
{
my ($hash, $arg) = @_;
my $name = $hash->{NAME};
delete $hash->{FD};
$hash->{STATE}='close';
$hash->{USBWUE}->close() if($hash->{USBWUE});
Log 2, "$name shutdown complete";
return undef;
} 

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
USBWUE_Read($)           
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log 4, "USBWUE Read State:$hash->{STATE}";
  
  
   my $c = $hash->{USBWUE}->lookfor();

   if (defined($c) && (length($c) > 0 )) {   
     Log 4,  " raw data: " . unpack("H[28]", $c);
   } 
   
   if (defined($c) && (length($c) == 5 )) {
 
     my $addr = unpack("H[2]", substr $c, 0, 1) ;
     my $temperature = unpack('s', pack( 'S', unpack("n", substr $c, 1, 2)))/10;
     my $humidity = unpack("n", substr $c, 3, 2)/10;
     my ($af, $td) = af_td($temperature, $humidity);


	 my $device_name = $addr;	 

	 
	 my $def = $modules{USBWUE}{defptr}{"$device_name"};
	 if(!$def) {
		Log 3, "USBWUE: Unknown device USBWUE_$device_name, please define it";
		#Log 1, "USBWUE: Unknown device USBWUE_$device_name, please define it";
    	my $ret = "UNDEFINED USBWUE_$device_name USBWUE $device_name";
		DoTrigger("global", $ret);
		return undef;
  	}	 

	
	 my $tm = TimeNow();
	 my $sensor = "";
	 my $val = " ";
	 my $current;
	 my $n = 0;
	
	$current = $temperature;
	$val .= " T: ".$current."  ";
	$sensor = "temperature";			
	$def->{READINGS}{$sensor}{TIME} = $tm;
	$def->{READINGS}{$sensor}{VAL} = $current;
	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	$current = $humidity;
	$val .= "H: ".$current."  ";
	$sensor = "humidity";			
	$def->{READINGS}{$sensor}{TIME} = $tm;
	$def->{READINGS}{$sensor}{VAL} = $current;
	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	my $dewpoint = $td;
	$current = $dewpoint;
	$val .= "D: ".$current."  ";
	$sensor = "dewpoint";			
	$def->{READINGS}{$sensor}{TIME} = $tm;
	$def->{READINGS}{$sensor}{VAL} = $current;
	$def->{CHANGED}[$n++] = $sensor . ": " . $current;
		
	my $absolute_humidity = $af;
	$current = $absolute_humidity;
	$val .= "AH: ".$current."  ";
	$sensor = "abs_humidity";			

	$def->{READINGS}{$sensor}{TIME} = $tm;
	$def->{READINGS}{$sensor}{VAL} = $current;
	$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	
	$val .= "A: " . $addr;
	
	
	$def->{STATE} = $val;
    $def->{TIME} = $tm;
    $def->{CHANGED}[$n++] = $val;

    # Log GetLogLevel($name,1), "USBWUE ". $hash->{NAME} . ": $val";
    addEvent($hash, $val);		
		
 	DoTrigger($name, undef); 
  }

} 

#####################################
sub
USBWUE_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
USBWUE_Set($@)
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
USBWUE_Get($@)
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
USBWUE_SimpleRead($)
{
my ($hash) = @_;
my $buf;
	
if($hash->{USBWUE}) 
   {
   $buf = $hash->{USBWUE}->read(1) ;
   if (!defined($buf) || length($buf) == 0) 
      {
      $buf = $hash->{USBWUE}->read(1) ;
      }
#   Log 4, "USBWUE SimpleRead=>$buf";
   return $buf;
   }

return undef; 
}

########################
sub
USBWUE_SimpleWrite(@)
{
my ($hash, $msg) = @_;
return if(!$hash);
$hash->{USBWUE}->write($msg) if($hash->{USBWUE});
Log 4, "USBWUE SimpleWrite $msg";
select(undef, undef, undef, 0.001);
} 





# -----------------------------
# Dewpoint calculation.
sub 
af_td ($$)
{
# Formeln von http://www.wettermail.de/wetter/feuchte.html

# r = relative Luftfeuchte
# T = Temperatur in ?C
        my ($T, $rh) = @_;

# a = 7.5, b = 237.3 f?r T >= 0
# a = 9.5, b = 265.5 f?r T < 0 ?ber Eis (Frostpunkt)  
        my $a = ($T > 0) ? 7.5 : 9.5;
        my $b = ($T > 0) ? 237.3 : 265.5;

# SDD = S?ttigungsdampfdruck in hPa  
# SDD(T) = 6.1078 * 10^((a*T)/(b+T))
  my $SDD = 6.1078 * 10**(($a*$T)/($b+$T));
# DD = Dampfdruck in hPa
# DD(r,T) = r/100 * SDD(T)
  my $DD  = $rh/100 * $SDD;  
# AF(r,TK) = 10^5 * mw/R* * DD(r,T)/TK; AF(TD,TK) = 10^5 * mw/R* * SDD(TD)/TK
# R* = 8314.3 J/(kmol*K) (universelle Gaskonstante)
# mw = 18.016 kg (Molekulargewicht des Wasserdampfes)
# TK = Temperatur in Kelvin (TK = T + 273.15)
  my $AF  = (10**5) * (18.016 / 8314.3) * ($DD / (273.15 + $T));
  my $af  = sprintf( "%.1f",$AF); # Auf eine Nachkommastelle runden

# TD(r,T) = b*v/(a-v) mit v(r,T) = log10(DD(r,T)/6.1078)  
  my $v   =  log10($DD/6.1078);
  my $TD  = $b*$v/($a-$v);
  my $td  = sprintf( "%.1f",$TD); # Auf eine Nachkommastelle runden

# TD = Taupunkttemperatur in ?C 
# AF = absolute Feuchte in g Wasserdampf pro m3 Luft 
        return($af, $td);
  
}

#####################################
sub
USBWUE_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
 	
  return if(!defined($hash->{FD})); # Already deleted
	
  Log 1, "USBWUE dev='$dev' name='$name' disconnected, waiting to reappear";
  USBWUE_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";
	
  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
} 



1;
