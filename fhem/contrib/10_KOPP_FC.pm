######################################################################################################################
# $Id: 10_KOPP_FC.pm 6183 2014-09-01 	Claus.M (RaspII)
#
# Kopp Free Control protocol module for FHEM
# (c) Claus M.
#
# This modul is currenly under construction and will only work if you flashed your CCD device with hexfile from: 
# svn+ssh://raspii@svn.code.sf.net/p/culfw/code/branches/raspii/culfw/Devices/CCD/CCD.hex
# which includes support for "K" command
#
# Published under GNU GPL License, v2
#
# Date		   Who				Comment																												   
# ----------  -------------   	-------------------------------------------------------------------------------------------------------------------------------
# 2014-12-21  Claus M.			V6 (fits to my FHEM.cfg V6) Removed timeout from define command, will add later to set command (best guess yet). 
# 2014-12-13  Claus M.			first version with command set: "on, off, toggle, dim, stop". Added new Parameter ("N" for do not print) 
# 2014-12-08  Claus M.			direct usage of set command @ FHEM.cfg works fine, but buttoms on/off do not appear, seems to be a setup/initialize issue in this routine 
# 2014-09-01  Claus M.			first Version
#
######################################################################################################################

package main;

use strict;
use warnings;
#use SetExtensions;

my %codes = (
	"10" => "on"       #
);

my %sets = (
	"on" => ""
);


#############################

sub KOPP_FC_Initialize($) 
{
	my ($hash) = @_;


	#  $hash->{Match}     = "^YsA..0..........\$";
	$hash->{SetFn}   = "KOPP_FC_Set";
	$hash->{DefFn}   = "KOPP_FC_Define";

	#  $hash->{ParseFn}   = "SOMFY_Parse";
    $hash->{AttrList} = "IODev";

#	  . " symbol-length"
#	  . " enc-key"
#	  . " rolling-code"
#	  . " repetition"
#	  . " switch_rfmode:1,0"
#	  . " do_not_notify:1,0"
#	  . " ignore:0,1"
#	  . " dummy:1,0"
#	  . " model:somfyblinds"
#	  . " loglevel:0,1,2,3,4,5,6";

}


#############################
sub KOPP_FC_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my $u = "wrong syntax: define <name> KOPP_FC keycode(Byte) transmittercode1(2Byte) transmittercode2(Byte)";

	# fail early and display syntax help
	if ( int(@a) < 4 ) {
		return $u;
	}

	# check keycode format (2 hex digits)
	if ( ( $a[2] !~ m/^[a-fA-F0-9]{2}$/i ) ) {
		return "Define $a[0]: wrong keycode format: specify a 2 digit hex value "
	}

	my $keycode = $a[2];
	$hash->{KEYCODE} = uc($keycode);

	# check transmittercode1 format (4 hex digits)
	if ( ( $a[3] !~ m/^[a-fA-F0-9]{4}$/i ) ) {
		return "Define $a[0]: wrong transmittercode1 format: specify a 4 digit hex value "
	}

	my $transmittercode1 = $a[3];
	$hash->{TRANSMITTERCODE1} = uc($transmittercode1);

	# check transmittercode2 format (2 hex digits)
	if ( ( $a[4] !~ m/^[a-fA-F0-9]{2}$/i ) ) {
		return "Define $a[0]: wrong transmittercode2 format: specify a 2 digit hex value "
	}
	my $transmittercode2 = $a[4];
	$hash->{TRANSMITTERCODE2} = uc($transmittercode2);

#Remove check for timeout
	# check timeout (5 dec digits)
#	if ( ( $a[5] !~ m/^[0-9]{5}$/i ) ) {
#		return "Define $a[0]: wrong timeout format: specify a 5 digits decimal value"
#	}
	
#   removed next lines, may be will move timeout to set command (on-for-timer) or something like that
#	my $timeout = $a[5];
#	$hash->{TIMEOUT} = uc($timeout);
	$hash->{TIMEOUT} = "00000";						#Default timeout = 0
	

# group devices by their address
#	my $code  = uc($keycode);
#	my $ncode = 1;
#	my $name  = $a[0];

#	$hash->{CODE}{ $ncode++ } = $code;
#	$modules{KOPP_FC}{defptr}{$code}{$name} = $hash;
#	$hash->{move} = 'on';
	
# ohne die folgende Zeile gibts beim Speichern von FHEM.cfg die Fehlermeldung Dimmer2 (wenn Dimmer2 als Name festgelegt werden soll)	
	AssignIoPort($hash);
}


#####################################
sub KOPP_FC_SendCommand($@)
{
	my ($hash, @args) = @_;
	my $ret = undef;
	my $keycodehex = $args[0];
	my $cmd = $args[1];
	my $message;
	my $name = $hash->{NAME};
	my $numberOfArgs  = int(@args);

	my $io = $hash->{IODev};

#	return $keycodehex
	
	$message = "s"
	  . $keycodehex				
	  . $hash->{TRANSMITTERCODE1}
	  . $hash->{TRANSMITTERCODE2}
	  . $hash->{TIMEOUT}
	  . "N";								# N for do not print messages (FHEM will write error messages to log files if CCD/CUL sends status info

    ## Send Message to IODev using IOWrite
	IOWrite( $hash, "K", $message );

	return $ret;
} 
# end sub KOPP_FC_SendCommand
#############################


#############################
sub KOPP_FC_Set($@)
{
	my ( $hash, $name, @args ) = @_;
	my $numberOfArgs  = int(@args);
	my $keycodedez;
	my $keycodehex;
#	my $message;

	if ( $numberOfArgs < 1 ) 
	{
	 return "no set value specified" ;
	}
	my $cmd = lc($args[0]);

	$keycodehex = $hash->{KEYCODE};							# Default Key Code was given by definition of device

	if($cmd eq 'on')  										# nothing to be done, yet (just use KeyCode)
	{
#	return "## Claus ##  Command = on" ;
 	}

	elsif($cmd eq 'toggle')  								# nothing to be done, yet (just use KeyCode)
	{
#	return "## Claus ##  Command = toggle" ;
	}
	
	
	elsif($cmd eq 'dimm')  									#+0x80 for long key pressure = dimmer up/down
	{
#	$keycodehex = $hash->{KEYCODE};							#without moving to $keycodehex and addition in second line it does not work !?
	$keycodedez = hex $keycodehex ;							
	$keycodedez = $keycodedez + 128;						
	$keycodehex = uc sprintf "%x", $keycodedez;

#    $hash->{KEYCODE} = sprintf "%x", $keycodehex;

#   return $keycodehex
#	return "## Claus ##  Command = dimm" ;
	}

	elsif($cmd eq 'stop')  									# Off means F7 will be sent several times
	{
	$keycodehex = "F7";										

#	return $keycodehex
#	return "## Claus ##  Command = off" ;
	}

	elsif($cmd eq 'off')  									# Off means F7 will be sent several times
	{
	$keycodehex = "F7";										

#	return $keycodehex
#	return "## Claus ##  Command = off" ;
	}

	else 
	{
	return "unknown command" ;
	}  


	
	KOPP_FC_SendCommand($hash, $keycodehex, @args);		
#	KOPP_FC_SendCommand($hash, @args);		


#	$hash->{STATE} = 'on';	
#	$hash->{STATE} = 'off';	

#return SetExtensions($hash,'toggle', @a);
return undef;

} 
# end sub Kopp_FC_setFN
###############################







1;

=pod
=begin html

<a name="KOPP_FC"></a>
<h3>Kopp Free Control protocol</h3>
<ul>
  <b>Please take into account: this protocol is under construction. Commands may change till first official "10_KOPP_FC.pm" version is released</b>
  <br><br>

  The Kopp Free Control protocol is used by Kopp receivers/actuators and senders.
  As we right now are only able to send Kopp commands but can't receive them, this module currently only
  supports devices like dimmers, switches and in futue also blinds through a <a href="#CUL">CUL</a> or compatible device (e.g. CCD...). 
  This devices must be defined before using this protocol (e.g. "define CUL_0 CUL /dev/ttyAMA0@38400 1234" ).

  <br><br>
  <a name="KOPP_FCdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; KOPP_FC &lt;Keycode&gt; &lt;Transmittercode1&gt; &lt;Transmittercode2&gt;</code>
 
  <br>
   <br><li><code>&lt;name&gt;</code></li>
   name is the identifier (name) you plan to assign to your specific device (actor) as done for any other FHEM device
   
   <br><br><li><code>&lt;Keycode&gt;</code></li>
   Keycode is a 2 digit hex code (1Byte) which reflects the transmitters key
  
   <br><br><li><code>&lt;Transmittercode1&gt;</code></li>
   Transmittercode1 is a 4 digit hex code. This code is specific for the transmitter itself.
   
   <br><br><li><code>&lt;Transmittercode2&gt;</code></li>
   Transmittercode2 is a 2 digit hex code and also specific for the transmitter, but I didn't see any difference while modifying this code.
   (seems this code don't matter the receiver). 
   
   <br><br>Both codes (Transmittercode1/2) are also used to pair the transmitter with the receivers
   <br>(remote switch, dimmer, blind..)
   <br>
   Pairing is done by setting the receiver in programming mode by pressing the program button at the receiver<br>
   (small buttom, typically inside a hole).<br>
   Once the receiver is in programming mode send a command from within FHEM to complete the pairing.
   For more details take a look to the data sheet of the corresponding receiver type.
   <br>
   You are now able to control teh receiver from FHEM, the receiver thinks it is just another remote control.
              
     
   
   <br><br>Examples:
   <ul>
      <code>define DimmerDevice KOPP_FC 65 FA5E 02</code><br>
      <code>define DimmerDevice KOPP_FC 30 FA5E 02</code><br>
    </ul>
  </ul>
  <br>

  <a name="KOPP_FCset"></a>
  <b>Set</b>
  <ul>

    <code>set &lt;name&gt; &lt;value&gt</code>
    <br>
 
   <br><li><code>&lt;value&gt;</code></li>
	value is one of:
    <ul>
    <code>on</code><br>
	<code>off</code><br>
	<code>stop</code><br>
	<code>toggle</code><br>
	<code>dimm</code><br>
	</ul>    
	
    <pre>Examples:
    <code>set DimmerDevice toggle</code> 		# will switch dimmer device (e.g. lamp) on/off
    <code>set DimmerDevice dimm</code> 		# will start dimming process
    <code>set DimmerDevice stopp</code>       	# will stop dimming process
   	</pre>
  </ul>
  <br>
  
 </ul>
  
 
=end html
=cut
