##########################################################################################################################################################################################

##############################################################################################################################
# $Id: 10_KOPP_FC.pm 10511 2016-01-15 09:09:04Z betateilchen $
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
# 2016-01-30  RaspII			Now also Blinds and Switches are implemented (all actuators I have). 
# 2016-01-12  RaspII			Implemented Dimmer Commands for 1&3 key remote, removed toggle	
# 2015-06-02  RaspII			Now can also Handle multiple devices with same code, next step: implement all commands (on, off, toggle... for KOPP_FC_Parse)
#								Missing is also 2 key commands (e.g. key1=on Key2=off for Dimmmers, key1=up key2=down for blinds)
# 2015-05-21  RaspII			Beim FS20 Modul sind die möglichen Set Commands abhängig vom "model" Attribute !! hier weitersuchen
#								Seit die Return SerExtensions eingebaut ist, lässt sich bei Taste2Rad4 dass Commando Off nicht mehr absetzen (hat was mit dem Modul SerExtensions zu tun)
# 2015-05-02  RaspII			Try now to receive Kopp Messages, also
# 2015-04-13  RaspII 			Modified some typos (help section)
# 2015-02-01  RaspII			use small "k" to start Kopp FW, "K" was already used for raw data
# 2014-12-21  RaspII			V6 (fits to my FHEM.cfg V6) Removed timeout from define command, will add later to set command (best guess yet). 
# 2014-12-13  RaspII			first version with command set: "on, off, toggle, dim, stop". Added new Parameter ("N" for do not print) 
# 2014-12-08  RaspII			direct usage of set command @ FHEM.cfg works fine, but buttoms on/off do not appear, seems to be a setup/initialize issue in this routine 
# 2014-09-01  RaspII			first Version
#
##########################################################################################################################################################################################

package main;

use strict;
use warnings;
use SetExtensions;				# 2015-05-21  Wird vermutlich benötig um später die möglichen "Set" Commandos zu definieren

sub KOPP_FC_Initialize($);		##### Claus evt. nicht nötig
sub KOPP_FC_Parse($$);			##### Claus evt. nicht nötig

my %codes = (					# This Sheet contains all allowed codes, indevpendtly from Model type
    "01" => "on",
 	"02" => "off",
    "03" => "toggle",
	"04" => "dimm",
	"05" => "stop",
	"06" => "up",
	"07" => "down",
	"08" => "top",
	"09" => "bottom",
);

my %sets = (					# Do not know whether this list is needed (guess: no)
	"on" => "",
	"off" => "",
	"stop" => "",
	"toggle" => "",
	"dimm" => "",
	"up" => "",
	"down" => "",
	"top" => "",
	"bottom" => ""
);
my %models = (
    Switch_8080_01  	=> 'Switch',
    Switch_8080_01_2Key => 'Switch_2KeyMode',
    Blind_8080_02  		=> 'Blind',
    Timer_8080_04  		=> 'TimerSwitch',
    Dimm_8011_00  		=> 'Dimmer',
	Dimm_8011_00_3Key  	=> 'Dimmer_3KeyMode',
);

my %kopp_fc_c2b;        # DEVICE_TYPE->hash (reverse of device_codes), ##Claus what does that mean?


#############################

sub KOPP_FC_Initialize($) 
{
	my ($hash) = @_;
	
	foreach my $k (keys %codes) {				## Claus needed if we wanna have the codes via commands
    $kopp_fc_c2b{$codes{$k}} = $k;				# both lines not needed yet
  }

#	$hash->{Match}   = "^kr..................";  # evt. später nehmen, damit nur genau 19 Zeichen akzeptiert werden
	$hash->{Match}   = "^kr.*";  
	$hash->{SetFn}   = "KOPP_FC_Set";
	$hash->{DefFn}   = "KOPP_FC_Define";
	$hash->{UndefFn}   = "KOPP_FC_Undef";
    $hash->{ParseFn}   = "KOPP_FC_Parse";
	$hash->{AttrFn}  	= "KOPP_FC_Attr";		  # aus SOMFY Beispiel abgeleitet			

    $hash->{AttrList} = "IODev ".
	"model:".join(",", sort keys %models);

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
sub KOPP_FC_Define($$) 
{
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );
	
    my $name = $hash->{NAME};## neu 14.5.
	
	my $u = "wrong syntax: define <name> KOPP_FC keycode(Byte) transmittercode1(2Byte) transmittercode2(Byte)";
	my $keycode2 = "";
	my $keycode3 = "";
	
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

	# check keycode2 (optional) format (2 hex digits)
	if (defined $a[5]){ 
	 if ( ( $a[5] !~ m/^[a-fA-F0-9]{2}$/i ) ) {			#Default: Keycode2 is empty
	 }
	 else {
	 $keycode2 = $a[5];
	 $hash->{KEYCODE2} = uc($keycode2);	
	 }
	}
	
	# check keycode3 (optional) format (2 hex digits)
	if (defined $a[6]){ 
	 if ( ( $a[5] !~ m/^[a-fA-F0-9]{2}$/i ) ) {			#Default: Keycode3 is empty
	 }
	 else {
	 $keycode3 = $a[6];
	 $hash->{KEYCODE3} = uc($keycode3);	
	 }
	}
#Remove check for timeout
	# check timeout (5 dec digits)
#	if ( ( $a[5] !~ m/^[0-9]{5}$/i ) ) {
#		return "Define $a[0]: wrong timeout format: specify a 5 digits decimal value"
#	}
	
#   removed next lines, may be will move timeout to set command (on-for-timer) or something like that
#	my $timeout = $a[5];
#	$hash->{TIMEOUT} = uc($timeout);
	$hash->{TIMEOUT} = "00000";												#Default timeout = 0
	

# group devices by their address
	my $code  = uc("$transmittercode1 $keycode");
	my $ncode = 1;
#	my $name  = $a[0];			# see above, already defined

	$hash->{CODE}{ $ncode++ } = $code;										## 6.1.2016: Code jetzt mit Referenz verlinken
#	$hash->{CODE} = $code;													## dafür diese Zeile raus
	$modules{KOPP_FC}{defptr}{$code}{$name} = $hash;						## neu 30.5. mit name vermutlich wird hierüber das Device eindeutig identifiziert 


# Noch die 2te Taste definieren, falls vorhanden
	if ( $keycode2 ne "") {
	my $code  = uc("$transmittercode1 $keycode2");
	$hash->{CODE}{ $ncode++ } = $code;
	$modules{KOPP_FC}{defptr}{$code}{$name} = $hash;						## neu 30.5. mit name vermutlich wird hierüber das Device eindeutig identifiziert 
		
	}

# Noch die 3te Taste definieren, falls vorhanden
	if ( $keycode3 ne "") {
	my $code  = uc("$transmittercode1 $keycode3");
	$hash->{CODE}{ $ncode++ } = $code;
	$modules{KOPP_FC}{defptr}{$code}{$name} = $hash;						## neu 30.5. mit name vermutlich wird hierüber das Device eindeutig identifiziert 
		
	}

# Noch so, der "Stop Code" = "F7" nach langem Tastendruck bekommt auch noch einen Eintrag
	$code  = uc("$transmittercode1 F7");
	$hash->{CODE}{"stop"} = $code;
	$modules{KOPP_FC}{defptr}{$code}{$name} = $hash;						## neu 30.5. mit name vermutlich wird hierüber das Device eindeutig identifiziert 
		

	Log3 $name, 2, "KOPP_FC_Define: Modules: $modules{KOPP_FC}{defptr}{$code}{$name} Name: $name a[0]: $a[0] Transmittercode1: $transmittercode1 Keycode: $keycode Keycode2: $keycode2  $keycode Keycode3: $keycode3 Hash: $hash";  # kann wieder Raus !!!! ### Claus



#	$hash->{move} = 'on';
	
# ohne die folgende Zeile gibts beim Speichern von FHEM.cfg die Fehlermeldung Dimmer2 (wenn Dimmer2 als Name festgelegt werden soll)	
	AssignIoPort($hash);
}


#############################
sub KOPP_FC_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) 
  {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{KOPP_FC}{defptr}{$c} }) 
	{
	
	 if($modules{KOPP_FC}{defptr}{$c}{$dname} == $hash)
     {
	  my $m=$modules{KOPP_FC}{defptr}{$c}{$dname}; 
      Log3 $name, 3, "KOPP_FC_Undef: Name: $name, Device: $m deleted"; 
     } 
      delete($modules{KOPP_FC}{defptr}{$c}{$dname}) if($modules{KOPP_FC}{defptr}{$c}{$dname} == $hash);

    }
  }
  return undef;
}

##############################
sub KOPP_FC_Attr(@) {
# write new Attributes to global $attr variable if attribute name is model

    my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

	return "\"KOPP_FC Attr: \" $name does not exist" if (!defined($hash));

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value

	if ($cmd eq "set") {
		if ($aName eq 'model') {
  	        $attr{$name}{$aName} = $aVal;
		}
    }
return undef;	
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
	IOWrite( $hash, "k", $message );

	return $ret;
} 
# end sub KOPP_FC_SendCommand
#############################


#############################
sub KOPP_FC_Set($@)
{
	my ( $hash, $name, @args ) = @_;							# Aufbau hash: Name, Command
	my $numberOfArgs  = int(@args);
	my $keycodedez;
	my $keycodehex;
	my $lh;
	my $modl;
	
#	my $message;

	if ( $numberOfArgs < 1 ) 
	{
	 return "no set value specified" ;
	}
	my $cmd = lc($args[0]);
	



	my $c = $kopp_fc_c2b{$args[0]};
    if(!defined($c)) 																		# if set command was not yet defined in %codes provide command list
																							# $c contains the first argument of %codes, "01" for "on", "02" for "off" ..
     {														
     my $list;
     if(defined($attr{$name}) && defined($attr{$name}{"model"})) 
	  {
       my $mt = $models{$attr{$name}{"model"}};												# Model specific set arguments will be defined here (maybe move later to variable above)
       $list = "dimm stop on off" if($mt && $mt eq "Dimmer"); 								# --------------------------------------------------------------------------------------
	   $list = "dimm stop on off" if($mt && $mt eq "Dimmer_3KeyMode");						# "$mt &&...", damit wird Inhalt von $mt nur geprüft wenn $mt initialisiert ist
       $list = "on off short" if($mt && $mt eq "TimerSwitch"); 								# on means long key presure
       $list = "top bottom up down stop" if($mt && $mt eq "Blind"); 						# up/down means long key presure
       $list = "on off" if($mt && $mt eq "Switch"); 										# (no difference between long/short preasure)
       $list = "on off" if($mt && $mt eq "Switch_2KeyMode");								# (no difference between long/short preasure)
      }
	   
	 $list = (join(" ", sort keys %kopp_fc_c2b) . " Claus") if(!defined($list));			# if list not defined model specific, allow whole default list

	 return "[Kopp_FC_Set] unknown command <$cmd>, choose one of " . join(" ", $list);		# no more text after "choose one of  " allowed


    }
																	
	if(defined($attr{$name}) && defined($attr{$name}{"model"})) 							# Falls Model spezifiziert ist, Model ermitteln -> $mt
	  {																						# ----------------------------------------------------
       $modl = $models{$attr{$name}{"model"}};								 
#	   Log3 $name, 2, "KOPP_FC_Set: Device Name: $name Index auf codes: $c Model: $modl"; 						# kann wieder Raus !!!! ### Claus  	
      }



#	readingsSingleUpdate($hash, "state","$cmd", 1);		# update also Readings
#	$hash->{STATE} = $cmd;								# update device state


# Look for all devices with the same code, and update readings (state), (timestamp, not yet)
# ------------------------------------------------------------------------------------------------------
# some hints: if same code is used within config file for differen models update of state makes no sense
# and may fail because command is not available for a different model. So we only update devices which are 
# of the same model as the original one.
#
#	my $tn = TimeNow();
#	my $defptr = $modules{KOPP_FC}{defptr}{transmittercode1}{keycode};
#	foreach my $n (keys %{ $defptr }) 
#	{
#    readingsSingleUpdate($defptr->{$n}, "state","$cmd", 1);
#	}


	my $code  = $hash->{CODE}{1};																# Load Devices code1 (typically key code short preasure)
	my $rhash = $modules{KOPP_FC}{defptr}{$code};												# Load Hash of Devices with same code 

#	my @list;																					# Do (Why) I need this @lists (incl. return @list)? 
	foreach my $n (keys %{ $rhash }) 
    {
     $lh = $rhash->{$n};
     $n = $lh->{NAME};        																	# It may be renamed, n now contains name of defined device, e.g. Dimmer....  
#    return "" if(IsIgnored($n));   															# Little strange.


	if(defined ($modl) && defined($attr{$n}) && defined($attr{$n}{"model"})) 					 
	{
	 my $m=$models{$attr{$n}{"model"}};															
     Log3 $name, 3, "KOPP_FC_Set: Device Name: $n, command: $cmd, Model: $m, Transm.-/KeyCode: $code"; 
	 
																								# Falls auch dieses Model spezifiziert ist und Modell identisch dem Model aus Originalaufruf,
	 if($m eq $modl) 																			# ------------------------------------------------------------------------------------------
     {																							# dann den Status dieses Devices ebenfalls updaten	
#	 Log3 $name, 2, "KOPP_FC_Set: Orig Model: $modl, Status Update also for Model: $m"; 		# kann wieder Raus !!!! ### Claus  	
	 $lh->{STATE} = $cmd;																		# update device state
     readingsSingleUpdate($lh, "state", $cmd, 1);												# update also Readings
     }
	 else
	 {
#	  Log3 $name, 2, "KOPP_FC_Set: Orig Model: $modl, wrong model: $m  no Status Update done"; 	# kann wieder Raus !!!! ### Claus  	
#	  Log3 $name, 2, "             dont define same remote key for different actuators models"; # kann wieder Raus !!!! ### Claus  	
	 }
    }

#	 push(@list, $n);
	 
	}
 #	return @list;
#	return"";		
    		

 
	if($cmd eq 'stop')  																		# command = stop
	{																							# --------------
	  $keycodehex = "F7";																		# Stop means F7 will be sent several times										
	}																							# (e.g. to end  "dimm" end or "up" / "down" )


 	elsif($cmd eq 'dimm')																		# independent of Dimmer Type  									
	{																							# ---------------------------
	  $keycodehex = $hash->{KEYCODE};															# use Keycode+0x80 for long key pressure = dimmer up/down
	  $keycodedez = hex $keycodehex ;															# without moving to $keycodehex and addition in second line it does not work !?	
	  $keycodedez = $keycodedez + 128;															#
	  $keycodehex = uc sprintf "%x", $keycodedez;												# 
	}

    elsif($modl && $modl eq "Dimmer")															# if model defined and equal Dimmer
	{																							# ---------------------------------
	  if($cmd eq 'on'||$cmd eq 'off')															# 														
   	  {																							#
	    $keycodehex = $hash->{KEYCODE};				    										# -> use Keycode to send "on" or "off" command (=toggle)
	  }
 	}

															
															
    elsif($modl && $modl eq "Dimmer_3KeyMode")													# if model defined and equal 3-key Dimmer
	{																							# ---------------------------------------
	  if($cmd eq 'on' && $hash->{KEYCODE2} ne "")												# Command = on
	  {																							#
   	    $keycodehex = $hash->{KEYCODE2};				    									# -> use Keycode 2 to send "on" command
	  }																							#
	  if($cmd eq 'off' && $hash->{KEYCODE3} ne "") 												# Command = off
	  {																							#														
   	    $keycodehex = $hash->{KEYCODE3};				    									# -> use Keycode 3 to send "on" command
	  }
									
 	}

    elsif($modl && $modl eq "Switch")															# if model defined and equal Switch
	{																							# ---------------------------------
	  if($cmd eq 'on' || $cmd eq 'off')															# 														
   	  {																							#
	    $keycodehex = $hash->{KEYCODE};				    										# -> use Keycode to send "on" or "off" command (=toggle)
	  }																							#
 	}

    elsif($modl && $modl eq "Switch_2KeyMode") 													# if model defined and equal Switch controlled by 2 Keys
	{																							# ------------------------------------------------------
	  if($cmd eq 'on')																			# 														
   	  {																							#
	    $keycodehex = $hash->{KEYCODE};				    										# -> use Keycode to send "on" or "off" command (=toggle)
	  }																							#
	  elsif($cmd eq 'off' && $hash->{KEYCODE2} ne "")											# 														
   	  {																							#
	    $keycodehex = $hash->{KEYCODE2};				   										# -> use Keycode to send "on" or "off" command (=toggle)
	  }			
 	}

	elsif($modl && $modl eq "Blind")															# if model defined and equal  Blind:  									# 
	{																							# ----------------------------------------	
	  if($cmd eq 'top')																			#
	  {																							# -> use Keycode to send "top" command
   	    $keycodehex = $hash->{KEYCODE};					    									#
	  }																							#
	  elsif($cmd eq 'bottom' && $hash->{KEYCODE2} ne "")										# 
	  {																							# -> use Keycode2 to send "bottom" command
   	    $keycodehex = $hash->{KEYCODE2};				    									# 
	  }																							#
	  elsif($cmd eq 'up')																		# 
	  {																							#
   	    $keycodehex = $hash->{KEYCODE};					    									#
  	    $keycodedez = hex $keycodehex ;															# -> use Keycode+0x80 to send "up" command	
	    $keycodedez = $keycodedez + 128;														#	
	    $keycodehex = uc sprintf "%x", $keycodedez;												# 
																								# 
	  }																							#
	  elsif($cmd eq 'down' && $hash->{KEYCODE2} ne "")											# 
	  {																							# -> use Keycode2+0x80 to send "dowm" command	
	    $keycodehex = $hash->{KEYCODE2};														#
        $keycodedez = hex $keycodehex ;															#	
        $keycodedez = $keycodedez + 128;														#	
	    $keycodehex = uc sprintf "%x", $keycodedez;												# 
	  }
	}      

	elsif($cmd eq 'on'|| 'off' || 'toggle')														# If model not known just allow on, off, toggle
	{																							# ---------------------------------------------
	  $keycodehex = $hash->{KEYCODE};															# -> use Keycode
	}



	
	else																						# should never happen :-) 
	{																							# -----------------------
	return "unknown command" ;
	}  


	
	KOPP_FC_SendCommand($hash, $keycodehex, @args);		
#	KOPP_FC_SendCommand($hash, @args);		




	




#	$hash->{STATE} = 'off';	

#return SetExtensions($hash,'toggle', @a);
return undef;

} 
# end sub Kopp_FC_setFN
###############################


#############################
# 
sub KOPP_FC_Parse($$) {																			# wird von fhem.pl dispatch getriggert
																								# Example receive Message: kr07FA5E7114CC0F02AD
																								# 07: block length; FA5E: Transmitter Code 1; 71: Key counter(next key pressed); 14: Key Code;
																								# CC0F: unknown, but always the same; 
																								# 02: Transmiter Code 2; (content depends on transmitter, changed value seems not to change anything; AD: Checksum)
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};																	# Here: Device Hash (e.g. to CUL), e.g. $name = "CUL_0" 
	my $state;																					# means receive command = new state
	my $keycodedez;
	my $specialkey	= "short";																	# Default: short key
	my $code;
	my $devicefound;


if( $msg =~ m/^kr/ ) {																			# if first two char's are "kr" then we are right here (KOPP Message received)

	# Msg format:
	# kr.. rest to be defined later
#	if (substr($msg, 0, 16) eq "krS-ReceiveStart" || substr($msg, 0, 14) eq "krE-ReceiveEnd") 
	if (substr($msg, 0, 2) eq "kr") 
	  { 

        # get Transtmitter Code 1
	    my $transmittercode1 = uc(substr($msg, 4, 4));											# Example above: FA5E

        # get Transtmitter Code 2
	    my $transmittercode2 = uc(substr($msg, 16, 2));											# Example above: 02

        # get Key Code
	    my $keycode = uc(substr($msg, 10, 2));													# Example above: 14
		$keycodedez = hex $keycode ;															# If Keycode > 128 and not equal "long key end" (F7) then Long Key pressure



		if ($keycode eq "F7")																	# If end of long keypressure (stop) we need special handling 
		{																						# ----------------------------------------------------------
	    $code  = uc("$transmittercode1 F7");
		$specialkey = "stop";

		}
		
		else
		{										
		  if ($keycodedez >= 128 && $keycode ne "F7")									
		  {																						# If long key pressure:
		    $keycodedez = ($keycodedez - 128);													# ---------------------
		    $specialkey = "long";
		    $keycode = uc sprintf "%02x", $keycodedez;											# %02 damit auch eine "0"... zweistellig wird
		  }

	    $code  = uc("$transmittercode1 $keycode");
		}

		my $rhash = $modules{KOPP_FC}{defptr}{$code};											# neu 30.5. rhash war nicht eindeutig 

#		my $rname = $rhash->{NAME};																# $rhash is hash to corresponding device as calculated from receive data

		Log3 $name, 2, "KOPP_FC_Parse: name: $name code: $code Specialkey:$specialkey"; 		# kann wieder Raus !!!! ### Claus rname wird müll, da Hash mehrere Namen verlinkt?
																								# rname funktioniert nur wenn $name in Zeile 149/150 nicht angehängt ist



#		my $tn = TimeNow();
# Look for all devices with the same code, and set state, (timestamp, not yet) 
# ----------------------------------------------------------------------------
      if($rhash) 
      {
 
		my @list;
		foreach my $n (keys %{ $rhash }) 
	    {
        my $lh = $rhash->{$n};
        $n = $lh->{NAME};        																# It may be renamed, n now contains name of defined device, e.g. Dimmer....  
        return "" if(IsIgnored($n));   															# Little strange.


		my $oldstate = ReadingsVal($n, "state","");											    #

# Je nach Model die Aktion triggern.

# 3 Key Dimmer:
#==============
		
		$devicefound=1;																			# Default: wir kennen das Device
		
		if ($attr{$n}{model} && ($attr{$n}{model} eq 'Dimm_8011_00_3Key')) 						# Wenn Device = 3 Key Dimmer
		{																						# ==========================
			
			
			 if ($specialkey eq 'short' && $keycode eq $lh->{KEYCODE}) 							# Taste 1 kurz gedrückt: dann toggeln
			 {																					# -----------------------------------
			   if($oldstate eq 'off') {$state = "on";}			 							 	 # off -> on	
			   elsif($oldstate eq 'on') {$state = "off";}		 							 	 # on -> off
			   elsif($oldstate eq 'stop') {$state = "off";}						 				 # stop -> off	
			   else {$state = "on";}							 							 	 # Weder noch? dann Neuer Zustand = on (wird dann wohl aus gewesen sein)	
			 }
			 elsif ($specialkey eq "long" && $keycode eq $lh->{KEYCODE}) 						# Taste 1 lang gedrückt: dann dimmen
			 {																					# ----------------------------------
			   $state = "dimm";	
			 }
			 elsif ($specialkey eq "stop") 														# Ende der lang gedrückten Taste dann dimmen stoppen
			 {																					# --------------------------------------------------
			   $state = "stop" if($oldstate eq 'dimm' || $oldstate eq 'stop');					# falls dimmen aktiv war oder bereits gestoppt wurde  
			 }
			 
			 elsif ($keycode eq $lh->{KEYCODE2}) {$state = "on";}								# Taste 2: (kurz oder lang) -> On  
			 elsif ($keycode eq $lh->{KEYCODE3}) {$state = "off";}								# Taste 3: (kurz oder lang) -> Off 
			 else {}
			  																	
			
		}
# 1 Key Dimmer:
#==============
		elsif ($attr{$n}{model} && ($attr{$n}{model} eq 'Dimm_8011_00')) 						# Wenn Device = 1 Key Dimmer
		{																						# ==========================
			
			
			 if ($specialkey eq 'short' && $keycode eq $lh->{KEYCODE}) 							# Taste 1 kurz gedrückt: dann toggeln
			 {																					# -----------------------------------
			   if($oldstate eq 'off') {$state = "on";}			 							 	 # off -> on	
			   elsif($oldstate eq 'on') {$state = "off";}		 							 	 # on -> off
			   elsif($oldstate eq 'stop') {$state = "off";}						 				 # stop -> off	
			   else {$state = "on";}							 							 	 # Weder noch? dann Neuer Zustand = on (wird dann wohl aus gewesen sein)	
			 }
			 elsif ($specialkey eq "long" && $keycode eq $lh->{KEYCODE}) 						# Taste 1 lang gedrückt: dann dimmen
			 {																					# ----------------------------------
			   $state = "dimm";	
			 }
			 elsif ($specialkey eq "stop") 														# Ende der lang gedrückten Taste dann dimmen stoppen
			 {																					# --------------------------------------------------
			   $state = "stop" if($oldstate eq 'dimm' || $oldstate eq 'stop');					# falls dimmen aktiv war oder bereits gestoppt wurde  
			 }
			 
			 
		}
# Blind:
#=======
		elsif ($attr{$n}{model} && ($attr{$n}{model} eq 'Blind_8080_02'))		 				# Wenn Device = Blind/Rolladen
		{																						# ============================
			
			
			 if ($specialkey eq 'short' && $keycode eq $lh->{KEYCODE}) 							# Taste 1 kurz gedrückt: dann Endzustand top/oben anfahren
			 {																					# --------------------------------------------------------
			   $state = "top";									 							 	# 	
			 }
			 elsif ($specialkey eq "long" && $keycode eq $lh->{KEYCODE}) 						# Taste 1 lang gedrückt: dann nach oben fahren (bis zu stop)
			 {																					# ----------------------------------------------------------
			   $state = "up";	
			 }
			 if ($specialkey eq 'short' && $keycode eq $lh->{KEYCODE2}) 						# Taste 2 kurz gedrückt: dann Endzustand bottom/unten anfahren
			 {																					# ------------------------------------------------------------
			   $state = "bottom";									 							 	# 	
			 }
			 elsif ($specialkey eq "long" && $keycode eq $lh->{KEYCODE2}) 						# Taste 2 lang gedrückt: dann nach runter fahren (bis zu stop)
			 {																					# -----------------------------------------------------------
			   $state = "down";	
			 }
			 elsif ($specialkey eq "stop") 														# Ende der lang gedrückten Taste dann Fahrt stoppen
			 {																					# --------------------------------------------------
			   $state = "stop" if($oldstate eq 'up' || $oldstate eq 'down' || $oldstate eq 'stop');	# falls fahrt aktiv war oder bereits gestoppt wurde  
			 }
			 
			 else {}
			  																	
			
		}		

# 2 Key Switch:
#==============
		elsif ($attr{$n}{model} && ($attr{$n}{model} eq 'Switch_8080_01_2Key'))		 			# Wenn Device = 2 Key Switch
		{																						# ==============================
			
			
			 if ($keycode eq $lh->{KEYCODE}) 													# Taste 1 gedrückt (no matter if short or long) -> State = on
			 {																					# -----------------------------------------------------------
			   $state = "on";									 							 	# 	
			 }
			 elsif ($keycode eq $lh->{KEYCODE2}) 												# Taste 2 gedrückt (no matter if short or long) -> State = off
			 {																					# ------------------------------------------------------------
			   $state = "off";									 								# 	
			 }
			 else {}
		}		
# Für 1 Key Switch und alle anderen Modelle gilt: egal ob kurz oder langer Tastendruck: toggeln zwischen on und off !
# =================================================================================================================== 
	    elsif ($specialkey ne 'stop') 															# Bei Ende der lang gedrückten Taste: nothing to do in this case 
		{
			if($oldstate eq 'off') {$state = "on";}												# off -> on	
			elsif($oldstate eq 'on') {$state = "off";}											# on -> off
			else {$state = "on";}																# Weder noch? dann Neuer Zustand = on (wird dann wohl aus gewesen sein)
		}
		else 						 															# Bei unbekanntem Device/Aktion keine weitere Aktion
		{
		$devicefound=0;																			# das Device ist nicht bekannt
		}

		if ($devicefound == 1)																	# Update Readings if Device/Action found
		  {
#			Log3 $name, 2, "KOPP_FC_Parse: Model $attr{$n}{model} gefunden ";  					# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: Code1: $lh->{CODE}{1} "; 	 						# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: Code2: $lh->{CODE}{2} ";  							# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: Code3: $lh->{CODE}{3} "; 							# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: KeyCode1: $lh->{KEYCODE} ";  						# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: KeyCode2: $lh->{KEYCODE2} ";  						# kann wieder Raus !!!! ### Claus  	    
#			Log3 $name, 2, "KOPP_FC_Parse: KeyCode3: $lh->{KEYCODE3} ";  						# kann wieder Raus !!!! ### Claus  	    


			
           readingsSingleUpdate($lh, "state", $state, 1);										# $state mit "" oder ohne?

		
#		   Log3 $name, 2, "KOPP_FC_Parse lh: $lh n: $n  oldstate: $oldstate state: $state"; 	 # kann wieder Raus !!!! ### Claus

		   push(@list, $n);
		  }   
        }
		return @list;
	   }
	   else 
	   {
	   	Log3 $name, 2, "KOPP_FC_Parse: Device not defined for message $msg";  
	   }


	  }

    else 
	  {
   	   Log3 $name, 2, "$name: KOPP_FC_Parse: nicht gefunden 01 $msg";   # kann wieder Raus !!!! ### Claus
	   return "KOPP_Parse: Command not known";
      }
} else {
    DoTrigger($name, "UNKNOWNCODE $msg");
  	Log3 $name, 2, "$name: KOPP_FC.PM Kopp nicht gefunden 02 $msg";   # kann wieder Raus !!!! ### Claus
    Log3 $name, 3, "$name: Unknown code $msg, help me [KOPP_FC]!";
    return undef;
  }
}

# end sub Kopp_FC_Parse
###############################


1;

=pod
=begin html

<a name="KOPP_FC"></a>
<h3>Kopp Free Control protocol</h3>
<ul>
  <b>Please take into account: this protocol is under construction. Commands may change </b>
  <br><br>

  The Kopp Free Control protocol is used by Kopp receivers/actuators and senders.
  This module is able to send commands to Kopp actuators and receive commands from Kopp transmitters. Currently supports devices: dimmers, switches and blinds.
  The communication is done via a <a href="#CUL">CUL</a> or compatible device (e.g. CCD...). 
  This devices must be defined before using this protocol (e.g. "define CUL_0 CUL /dev/ttyAMA0@38400 1234" and "attr CUL_0 rfmode KOPP_FC" ).

  <br><br>
  <a name="KOPP_FCdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; KOPP_FC &lt;Keycode&gt; &lt;Transmittercode1&gt; &lt;Transmittercode2&gt; [&lt;Keycode2&gt] [&lt;Keycode3&gt]</code>
 
  <br>
   <br><li><code>&lt;name&gt;</code></li>
   name is the identifier (name) you plan to assign to your specific device (actuator) as done for any other FHEM device
   
   <br><br><li><code>&lt;Keycode&gt;</code></li>
   Keycode is a 2 digit hex code (1Byte) which reflects the transmitters key
  
   <br><br><li><code>&lt;Transmittercode1&gt;</code></li>
   Transmittercode1 is a 4 digit hex code. This code is specific for the transmitter itself.
   
   <br><br><li><code>&lt;Transmittercode2&gt;</code></li>
   Transmittercode2 is a 2 digit hex code and also specific for the transmitter, but I didn't see any difference while modifying this code.
   (seems this code don't matter the receiver). 
   
   <br>Both codes (Transmittercode1/2) are also used to pair the transmitter with the receivers (remote switch, dimmer, blind..)
  
   <br><br><li><code>[&lt;Keycode2&gt;]</code></li>
   Keycode2 is an opional 2 digit hex code (1Byte) which reflects a second transmitters key
  
   <br><br><li><code>[&lt;Keycode3&gt;]</code></li>
   Keycode3 is an opional 2 digit hex code (1Byte) which reflects a third transmitters key
   <br>
   Some receivers like dimmers can be paired with two addional keys, which allow to switch the dimmer directly on or off.
   That means FHEM will always know the current state, which is not the case in one key mode (toggling between on and off)
   
   <br><br>
   Pairing is done by setting the receiver in programming mode by pressing the program button at the receiver<br>
   (small buttom, typically inside a hole).<br>
   Once the receiver is in programming mode send a command (or two, see dimmer above) from within FHEM to complete the pairing.
   For more details take a look to the data sheet of the corresponding receiver type.
   <br>
   You are now able to control the receiver from FHEM, the receiver handles FHEM just linke another remote control.
</ul>         

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
	<code>dimm</code><br>
	<code>stop</code><br>
	</ul>    
	
    <pre>Examples:
    <code>set DimmerDevice on</code> 		# will toggle dimmer device (e.g. lamp) on/off
    <code>set DimmerDevice dimm</code> 		# will start dimming process
    <code>set DimmerDevice stop</code>       	# will stop dimming process
   	</pre>
  </ul>
  <br> 

  <a name="KOPP_FCattrib"></a>
  <b>Attributes</b>
  <ul>
    <code>attr CUL_0 rfmode KOPP_FC</code> 
    <br>
  	
	This attribute will switch the Kopp protocol on for device CUL_0<br>
	You can not use a second protocol on this device
    
  </ul>
  <br>
  
  <br><br>Example: FHEM Config for Dimmer via 1 Key remote control:
  <ul>
      <code>define Dimmer KOPP_FC 65 FA5E 02</code><br>
	  <code>attr Dimmer IODev CCD</code><br>
	  <code>attr Dimmer devStateIcon OnOff:toggle:dimm dimm:dim50%:stop stop:on:dimm off:toggle:dimm</code><br>
	  <code>attr Dimmer eventMap on:OnOff dimm:dimm stop:stop</code><br>
	  <code>attr Dimmer group Dimmer_1KeyMode</code><br>
  	  <code>attr Dimmer model Dimm_8011_00</code><br>
	  <code>attr Dimmer room Test</code><br>
	  <code>attr Dimmer webCmd OnOff:dimm:stop</code><br>
  </ul>
 
  <br><br>Example: FHEM Config for Dimmer via 3 Key remote control:

  <br>

 </ul>
  
 
=end html
=cut
