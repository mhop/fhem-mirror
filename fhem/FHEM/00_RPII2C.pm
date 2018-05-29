##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);

my @clients = qw(
I2C_LCD
I2C_DS1307
I2C_PC.*
I2C_MCP.*
I2C_BM.*
I2C_SH.*
I2C_TSL.*
I2C_SUSV
I2C_LM.*
);

my $gpioprg = "/usr/local/bin/gpio";		#WiringPi GPIO utility
my $I2C_SLAVE = 0x0703;						#Variable for IOCTL (set I2C slave address)

my $libcheck_SMBus = 1;
my $check_ioctl_ph = 1;

sub RPII2C_Initialize($) {
	my ($hash) = @_;
	eval "use Device::SMBus;";
	$libcheck_SMBus = 0 if($@);
	eval {require "sys/ioctl.ph"};
	$check_ioctl_ph = 0 if($@);
	
# Provider
	$hash->{Clients} = join (':',@clients);
	$hash->{I2CWrtFn} = "RPII2C_Write";    #alternative fuer IOWrite

# Normal devices
	$hash->{DefFn}   = "RPII2C_Define";
	$hash->{UndefFn} = "RPII2C_Undef";
	$hash->{GetFn}   = "RPII2C_Get";
	$hash->{SetFn}   = "RPII2C_Set";
	$hash->{AttrFn}  = "RPII2C_Attr";
	$hash->{NotifyFn} = "RPII2C_Notify";
	$hash->{AttrList}= "do_not_notify:1,0 ignore:1,0 showtime:1,0 " .
										 "$readingFnAttributes";
	$hash->{AttrList} .= " useHWLib:IOCTL,SMBus " if( $libcheck_SMBus && $check_ioctl_ph);
	$hash->{AttrList} .= " swap_i2c0:off,on";
}
#####################################
sub RPII2C_Define($$) {							#
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	unless(@a == 3) {
		my $msg = "wrong syntax: define <name> RPII2C <0|1>";
		Log3 undef, 2, $msg;
		return $msg;
	}
	$hash->{SMBus_exists}    = $libcheck_SMBus if($libcheck_SMBus);
	$hash->{ioctl_ph_exists} = $check_ioctl_ph if($check_ioctl_ph);

	my $name = $a[0];
	my $dev = $a[2];
	
	if ($check_ioctl_ph) {
		$hash->{hwfn} = \&RPII2C_HWACCESS_ioctl;
	} elsif ($libcheck_SMBus) {
		$hash->{hwfn} = \&RPII2C_HWACCESS;
	} else {
		return $name . ": Error! no library for Hardware access installed";
	}
	my $device = "/dev/i2c-".$dev;
	if ( RPII2C_CHECK_I2C_DEVICE($device) ) {
		Log3 $hash, 3, "$hash->{NAME}: file $device not accessible try to use gpio utility to fix it";
		if ( defined(my $ret = RPII2C_CHECK_GPIO_UTIL($gpioprg)) ) {
			Log3 $hash, 1, "$hash->{NAME}: " . $ret if $ret;
		} else {													#I2C Devices mit gpio utility fuer FHEM User lesbar machen
			my $exp = $gpioprg.' load i2c';
			$exp = `$exp`;
		}
	}
	$hash->{NOTIFYDEV} = "global";

	if($dev eq "none") {
		Log3 $name, 1, "$name device is none, commands will be echoed only";
		$attr{$name}{dummy} = 1;
		return undef;
	}
	my $check = RPII2C_CHECK_I2C_DEVICE($device);
	return $name . $check if $check;
	
	$hash->{DeviceName} = $device;
	$hash->{STATE} = "initialized";
	return undef;
}
#####################################
sub RPII2C_Notify {									#
	my ($hash,$dev) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
		RPII2C_forall_clients($hash,\&RPII2C_Init_Client,undef);;
	} elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
	}
}
#####################################
sub RPII2C_forall_clients($$$) {		#
	my ($hash,$fn,$args) = @_;
	foreach my $d ( sort keys %main::defs ) {
		if ( defined( $main::defs{$d} )
			&& defined( $main::defs{$d}{IODev} )
			&& $main::defs{$d}{IODev} == $hash ) {
			 &$fn($main::defs{$d},$args);
		}
	}
	return undef;
}
#####################################
sub RPII2C_Init_Client($@) {				#
	my ($hash,$args) = @_;
	if (!defined $args and defined $hash->{DEF}) {
		my @a = split("[ \t][ \t]*", $hash->{DEF});
		$args = \@a;
	}
	my $name = $hash->{NAME};
	Log3 $name,5,"im init client fuer $name "; 
	my $ret = CallFn($name,"InitFn",$hash,$args);
	if ($ret) {
		Log3 $name,2,"error initializing '".$hash->{NAME}."': ".$ret;
	}
}
#####################################
sub RPII2C_Undef($$) {			 		   	#
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	foreach my $d (sort keys %defs) {
		if(defined($defs{$d}) &&
			 defined($defs{$d}{IODev}) &&
			 $defs{$d}{IODev} == $hash)
			{
				Log3 $name, 3, "deleting port for $d";
				delete $defs{$d}{IODev};
			}
	}
	return undef;
}
#####################################
sub RPII2C_Attr(@){
	my (undef, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	if ($attr && $attr eq 'useHWLib') {
		$hash->{hwfn} = \&RPII2C_HWACCESS_ioctl if $val eq "IOCTL";
		$hash->{hwfn} = \&RPII2C_HWACCESS if $val eq "SMBus";
	} elsif ($attr && $attr eq 'swap_i2c0' && defined($val)) {
		RPII2C_SWAPI2C0($hash,$val);
	}
	return undef;
}
#####################################
sub RPII2C_Set($@) {								#
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $type = shift @a;
	my @sets = ('writeByte', 'writeByteReg', 'writeBlock', 'writeBlockReg'); #, 'writeNBlock');
	return "Unknown argument $type, choose one of " . join(" ", @sets) if @a < 2;

	foreach (@a) {																																					#Hexwerte pruefen und in Dezimalwerte wandeln
		return "$name: $_ is no 1byte hexadecimal value" if $_ !~ /^(0x|)[0-9A-F]{1,2}$/xi ;
		$_ = hex;
	}
	my $i2ca = shift @a;
	return "$name: I2C Address not valid" unless ($i2ca > 3 && $i2ca < 128);								#pruefe auf Hexzahl zwischen 4 und 7F

	my $i2chash = { i2caddress => $i2ca, direction => "i2cbytewrite", test => "local" };
	my ($reg, $nbyte, $data) = undef;
	if ($type eq "writeByte") {
		$data = join(" ", @a);
	} elsif ($type eq "writeByteReg") {
		$reg = shift @a;
		$data = join(" ", @a);
	} elsif ($type eq "writeBlock") {
		$nbyte = int(@a);
		return "$name maximal blocksize (32byte) exeeded" if $nbyte > 32;
		$data = join(" ", @a);
		$i2chash->{direction} = "i2cwrite";
	} elsif ($type eq "writeBlockReg") {
		$reg = shift @a;
		$nbyte = int(@a);
		return "$name maximal blocksize (32byte) exeeded" if $nbyte > 32;
		$data = join(" ", @a);
		$i2chash->{direction} = "i2cwrite";
	} else {
		return "Unknown argument $type, choose one of " . join(" ", @sets);
	}
	
	$i2chash->{reg}   = $reg if defined($reg);																			#startadresse zum lesen
	$i2chash->{nbyte} = $nbyte if defined($nbyte);
	$i2chash->{data} = $data if defined($data);
	&{$hash->{hwfn}}($hash, $i2chash);
	undef $i2chash;																																	#Hash loeschen
	return undef;
}
#####################################
sub RPII2C_Get($@) {								#
	my ($hash, @a) = @_;
	my $nargs = int(@a);
	my $name = $hash->{NAME};
	my @gets = ('read','readblock','readblockreg');
	unless ( exists($a[1]) && $a[1] ne "?" && grep {/^$a[1]$/} @gets ) { 
	return "Unknown argument $a[1], choose one of " . join(" ", @gets);
	}
	if ($a[1] eq "read") {
		return "use: \"get $name $a[1] <i2cAddress> [<RegisterAddress> [<Number od bytes to get>]]\"" if(@a < 3);
		return "$name: I2C Address not valid"             unless (                  $a[2] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
		return "$name register address must be a hexvalue" 		if (defined($a[3]) && $a[3] !~ /^(0x|)[0-9A-F]{1,4}$/xi);
		return "$name number of bytes must be decimal value"  if (defined($a[4]) && $a[4] !~ /^[0-9]{1,2}$/);
		my $i2chash = { i2caddress => hex($a[2]), direction => "i2cbyteread" };
		$i2chash->{reg}   = hex($a[3]) if defined($a[3]);																			#startadresse zum lesen
		$i2chash->{nbyte} = $a[4] if defined($a[4]);
		my $status  = &{$hash->{hwfn}}($hash, $i2chash);														#als Array
		my $received = $i2chash->{received};																						#als Scalar
		undef $i2chash;																																	#Hash loeschen
		return (defined($received) ? "received : " . $received ." | " : "" ) . " transmission: $status";	
	} elsif ($a[1] eq "readblock") {
		return "use: \"get $name $a[1] <i2cAddress> [<Number od bytes to get>]\"" if(@a < 3);
		return "$name: I2C Address not valid"             unless (                  $a[2] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
		return "$name number of bytes must be decimal value"  if (defined($a[3]) && $a[3] !~ /^[0-9]{1,2}$/);
        my $i2chash = { i2caddress => hex($a[2]), direction => "i2cread" };
        $i2chash->{nbyte} = $a[3] if defined($a[3]);
        my $status  = &{$hash->{hwfn}}($hash, $i2chash);
		my $received = $i2chash->{received};																						#als Scalar
		undef $i2chash;																																	#Hash loeschen
		return (defined($received) ? "received : " . $received ." | " : "" ) . " transmission: $status";        
	} elsif ($a[1] eq "readblockreg") {
		return "use: \"get $name $a[1] <i2cAddress> [<Number od bytes to get>]\"" if(@a < 2);
		return "$name: I2C Address not valid"             unless (                  $a[2] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
		return "$name register address must be a hexvalue" 		if (defined($a[3]) && $a[3] !~ /^(0x|)[0-9A-F]{1,4}$/xi);
		return "$name number of bytes must be decimal value"  if (defined($a[4]) && $a[4] !~ /^[0-9]{1,2}$/);
        my $i2chash = { i2caddress => hex($a[2]), direction => "i2cread" };
				$i2chash->{reg}   = hex($a[3]) if defined($a[3]);
        $i2chash->{nbyte} = $a[4] if defined($a[4]);
        my $status  = &{$hash->{hwfn}}($hash, $i2chash);
		my $received = $i2chash->{received};																						#als Scalar
		undef $i2chash;																																	#Hash loeschen
		return (defined($received) ? "received : " . $received ." | " : "" ) . " transmission: $status";        
	}
	return undef;
}
#####################################
sub RPII2C_Write($$) { 							#wird vom Client aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $ankommen = "$name: vom client empfangen";
	foreach my $av (keys %{$clientmsg}) { $ankommen .= "|" . $av . ": " . $clientmsg->{$av}; }
	Log3 $hash, 5, $ankommen;
	
	if ( $clientmsg->{direction} && $clientmsg->{i2caddress} ) {
		$clientmsg->{$name . "_" . "SENDSTAT"} = &{$hash->{hwfn}}($hash, $clientmsg);
		#$clientmsg->{$name . "_" . "SENDSTAT"} = RPII2C_HWACCESS($hash, $clientmsg);
	}
	
	foreach my $d ( sort keys %main::defs ) {				#zur Botschaft passenden Clienten ermitteln geht auf Client: I2CRecFn
		#Log3 $hash, 1, "d: $d". ($main::defs{$d}{IODev}? ", IODev: $main::defs{$d}{IODev}":"") . ($main::defs{$d}{I2C_Address} ? ", I2C: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{i2caddress} ? " CI2C: $clientmsg->{i2caddress}" : "");
		if ( defined( $main::defs{$d} )
				&& defined( $main::defs{$d}{IODev} )    && $main::defs{$d}{IODev} == $hash
				&& defined( $main::defs{$d}{I2C_Address} ) && defined($clientmsg->{i2caddress})
								&& $main::defs{$d}{I2C_Address} eq $clientmsg->{i2caddress} ) {
			my $chash = $main::defs{$d};
			Log3 $hash, 5, "$name ->Client gefunden: $d". ($main::defs{$d}{I2C_Address} ? ", I2Caddress: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{data} ? " Data: $clientmsg->{data}" : "") . ($clientmsg->{received} ? " Gelesen: $clientmsg->{received}" : "");
			CallFn($d, "I2CRecFn", $chash, $clientmsg);
			undef $clientmsg														#Hash loeschen nachdem Daten verteilt wurden
		}
	}
	return undef;
}

sub RPII2C_CHECK_I2C_DEVICE {	
	my ($dev) = @_;
		my $ret = undef;
	if(-e $dev) {
		if(-r $dev) {
			unless(-w $dev) {
				$ret =  ': Error! I2C device not writable: '.$dev . '. Please install wiringpi or change access rights for fhem user'; 
			}
		} else {
			$ret =    ': Error! I2C device not readable: '.$dev . '. Please install wiringpi or change access rights for fhem user'; 
		}
	} else {
		$ret =      ': Error! I2C device not found: '   .$dev . '. Please check kernelmodules must loaded: i2c_bcm2708, i2c_dev'; 
	}
	return $ret;
}

sub RPII2C_CHECK_GPIO_UTIL {
	my ($gpioprg) = @_;
	my $ret = undef;
	if(-e $gpioprg) {
		if(-x $gpioprg) {
			unless(-u $gpioprg) {
				$ret =  "file $gpioprg is not setuid"; 
			}
		} else {
			$ret =  "file $gpioprg is not executable"; 
		}
	} else {
		$ret = "file $gpioprg doesnt exist"; 
	}
	return $ret;
}

sub RPII2C_SWAPI2C0 {
	my ($hash,$set) = @_;
		unless (defined(my $ret = RPII2C_CHECK_GPIO_UTIL($gpioprg))) {
			if (defined($set) && $set eq "on") {
				system "$gpioprg -g mode 0 in";
				system "$gpioprg -g mode 1 in";
				system "$gpioprg -g mode 28 ALT0";
				system "$gpioprg -g mode 29 ALT0";
			} else {
				system "$gpioprg -g mode 28 in";
				system "$gpioprg -g mode 29 in";
				system "$gpioprg -g mode 0 ALT0";
				system "$gpioprg -g mode 1 ALT0";
			}
		} else {
					Log3 $hash, 1, $hash->{NAME} . ": " . $ret if $ret;
		}
	return
}

sub RPII2C_HWACCESS($$) {
		my ($hash, $clientmsg) = @_;
		my $status = "error";
		my $inh = undef;
		Log3 $hash, 5, "$hash->{NAME}: HWaccess I2CAddr: " . sprintf("0x%.2X", $clientmsg->{i2caddress});
		my $dev = Device::SMBus->new(
			I2CBusDevicePath => $hash->{DeviceName},
			I2CDeviceAddress => hex( sprintf("%.2X", $clientmsg->{i2caddress}) ),
		);
		if ( defined($clientmsg->{reg}) && defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cwrite") {				#blockweise beschreiben (Register)
		my @data = split(" ", $clientmsg->{data});
			my $dataref = \@data;
			$inh = $dev->writeBlockData( $clientmsg->{reg} , $dataref );
			my $wr = join(" ", @{$dataref});
			Log3 $hash, 5, "$hash->{NAME}: Block schreiben Register: " . sprintf("0x%.2X", $clientmsg->{reg}) . " Inhalt: " . $wr . " N: ". int(@data) ." Returnvar.: $inh";
			$status = "Ok" if $inh == 0;
		} elsif (defined($clientmsg->{reg}) && defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cbytewrite") {															#byteweise beschreiben (Register)
			my @data = split(" ", $clientmsg->{data});
			foreach (@data) {
				$inh = $dev->writeByteData($clientmsg->{reg},$_);
				Log3 $hash, 5, "$hash->{NAME}; Register ".sprintf("0x%.2X", $clientmsg->{reg})." schreiben - Inhalt: " .sprintf("0x%.2X",$_) . " Returnvar.: $inh";
				last if $inh != 0;
				$status = "Ok" if $inh == 0;
			} 
		} elsif (defined($clientmsg->{data}) && ( $clientmsg->{direction} eq "i2cwrite" || $clientmsg->{direction} eq "i2cbytewrite" ) ) {							#Byte(s) schreiben
			my @data = split(" ", $clientmsg->{data});
			foreach (@data) {
				$inh = $dev->writeByte($_);
				Log3 $hash, 5, "$hash->{NAME} Byte schreiben; Inh: " . $_ . " Returnvar.: $inh";
				last if $inh != 0;
				$status = "Ok" if $inh == 0;
			}	
		} elsif (defined($clientmsg->{reg}) && ( $clientmsg->{direction} eq "i2cread" || $clientmsg->{direction} eq "i2cbyteread" ) ) {									#byteweise lesen (Register)
			my $nbyte = defined($clientmsg->{nbyte}) ? $clientmsg->{nbyte} : 1;
			my $rmsg = "";
			for (my $n = 0; $n < $nbyte; $n++) {
				$inh = $dev->readByteData($clientmsg->{reg} + $n );
				Log3 $hash, 5, "$hash->{NAME}; Register ".sprintf("0x%.2X", $clientmsg->{reg} + $n )." lesen - Inhalt: ".sprintf("0x%.2X",$inh);
				last if ($inh < 0);
				#$rmsg .= sprintf("%.2X",$inh);
				$rmsg .= $inh;
				$rmsg .= " " if $n <= $nbyte;
				$status = "Ok" if ($n + 1) == $nbyte;
			}
			#@{$clientmsg->{received}} = split(" ", $rmsg) if($rmsg);										#Daten als Array uebertragen
			$clientmsg->{received} = $rmsg if($rmsg);																	#Daten als Scalar uebertragen
		} elsif ($clientmsg->{direction} eq "i2cread"|| $clientmsg->{direction} eq "i2cbyteread") {																											#Byte lesen
			my $nbyte = defined($clientmsg->{nbyte}) ? $clientmsg->{nbyte} : 1;
			my $rmsg = "";
			for (my $n = 0; $n < $nbyte; $n++) {
				$inh = $dev->readByte();
				Log3 $hash, 5, "$hash->{NAME} Byte lesen; Returnvar.: $inh";
				last if ($inh < 0);
				$rmsg .= $inh;
				$rmsg .= " " if $n <= $nbyte;
				$status = "Ok" if ($n + 1) == $nbyte;
			}
			#@{$clientmsg->{received}} = split(" ", $rmsg) if($rmsg);										#Daten als Array uebertragen
			$clientmsg->{received} = $rmsg if($rmsg);																	#Daten als Scalar uebertragen
		}
		$hash->{STATE} = $status;
		$hash->{ERRORCNT} = defined($hash->{ERRORCNT}) ? $hash->{ERRORCNT} += 1 : 1 if $status ne "Ok";
		$clientmsg->{$hash->{NAME} . "_" . "RAWMSG"} = $inh;
	return $status;
}
#####################

sub RPII2C_HWACCESS_ioctl($$) {
	my ($hash, $clientmsg) = @_;
	my $status = "error";
	Log3 $hash, 5, "$hash->{NAME}: HWaccess I2CAddr: " . sprintf("0x%.2X", $clientmsg->{i2caddress});
	my ($fh, $msg) = undef;
	
	my $ankommen = "$hash->{NAME}: vom client empfangen";
	foreach my $av (keys %{$clientmsg}) { $ankommen .= "|" . $av . ": " . $clientmsg->{$av}; }
	Log3 $hash, 5, $ankommen;
	
	my $i2caddr = hex(sprintf "%x", $clientmsg->{i2caddress});
	if ( sysopen(my $fh, $hash->{DeviceName}, O_RDWR) != 1) {																																														#Datei oeffnen
		Log3 $hash, 3, "$hash->{NAME}: HWaccess sysopen failure: $!"
	} elsif( not defined( ioctl($fh,$I2C_SLAVE,$i2caddr) ) ) {																																													#I2C Adresse per ioctl setzen
		Log3 $hash, 3, "$hash->{NAME}: HWaccess (0x".unpack( "H2",pack "C", $clientmsg->{i2caddress}).") ioctl failure: $!"
	} elsif ( defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cwrite") {			#blockweise schreiben
		my $data = defined($clientmsg->{reg}) ? chr($clientmsg->{reg}) : undef;
		foreach (split(" ", $clientmsg->{data})) {
			$data .= chr($_);
		}
		my $retval = syswrite($fh, $data, length($data));
		unless (defined($retval) && $retval == length($data)) {
			Log3 $hash, 3, "$hash->{NAME}: HWaccess blockweise nach 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." schreiben, " . (defined($clientmsg->{reg}) ? "Reg: 0x". unpack( "H2",pack "C", $clientmsg->{reg}) : "") . " Inh: $clientmsg->{data}, laenge: ".length($data)."| -> syswrite failure: $!";
		} else {
			$status = "Ok";
			Log3 $hash, 5, "$hash->{NAME}: HWaccess block schreiben, " . (defined($clientmsg->{reg}) ? "Reg: 0x". unpack( "H2",pack "C", $clientmsg->{reg}) : "") . " Inh(dec):|$clientmsg->{data}|, laenge: |".length($data)."|";
		}

	} elsif (defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cbytewrite") {		#byteweise schreiben
		my $reg = undef;
		$reg = $clientmsg->{reg} if (defined($clientmsg->{reg}));
		$status = "Ok";
		foreach (split(" ", $clientmsg->{data})) {
			my $data = (defined($reg) ? chr($reg++) : "") . chr($_);
			my $retval = syswrite($fh, $data, length($data));
			#Log3 $hash, 1, "retval= $retval" if $clientmsg->{test} eq "local";
			unless (defined($retval) && $retval == length($data)) {
				Log3 $hash, 3, "$hash->{NAME}: HWaccess byteweise nach 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." schreiben, ". (defined($reg) ?	"Reg: 0x". unpack( "H2",pack "C", ($reg - 1)) . " " : "")."Inh: 0x" .  unpack( "H2",pack "C", $_) .", laenge: ".length($data)."| -> syswrite failure: $!";
				$status = "error";
				last;
			}
		Log3 $hash, 5,   "$hash->{NAME}: HWaccess byteweise schreiben, ". (defined($reg) ?  "Reg: 0x". unpack( "H2",pack "C", ($reg - 1)) . " " : "")."Inh: 0x" .  unpack( "H2",pack "C", $_) .", laenge: ".length($data);
		#Log3 $hash, 1, "$hash->{NAME}: HWaccess byteweise zu 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})."  schreiben, ". (defined($reg) ?  "Reg: 0x". unpack( "H2",pack "C", ($reg - 1)) . " " : "")."Inh: 0x" .  unpack( "H2",pack "C", $_) .", laenge: ".length($data) if $clientmsg->{test} eq "local";	
		}
	} elsif ($clientmsg->{direction} eq "i2cbyteread") {										#byteweise lesen
		my $nbyte = defined($clientmsg->{nbyte}) ? $clientmsg->{nbyte} : 1;
		my $rmsg = "";
		foreach (my $n = 0; $n < $nbyte; $n++) {
			if ( defined($clientmsg->{reg}) ) {
				Log3 $hash, 5, "$hash->{NAME}: HWaccess byteweise lesen setze Registerpointer auf " . ($clientmsg->{reg} + $n);
				my $retval = syswrite($fh, chr($clientmsg->{reg} + $n), 1);
				unless (defined($retval) && $retval == 1) {
					Log3 $hash, 3, "$hash->{NAME}: HWaccess byteweise von 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." lesen,". (defined($clientmsg->{reg}) ? " Reg: 0x". unpack( "H2",pack "C", ($clientmsg->{reg} + $n)) : "") . " -> syswrite failure: $!" if $!;
					last;
				}
			}
            if (defined($clientmsg->{usleep})) {
                usleep($clientmsg->{usleep});
            }
            my $buf = undef;
			my $retval = sysread($fh, $buf, 1);
			unless (defined($retval) && $retval == 1) {
				Log3 $hash, 3, "$hash->{NAME}: HWaccess byteweise von 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." lesen,". (defined($clientmsg->{reg}) ? " Reg: 0x". unpack( "H2",pack "C", ($clientmsg->{reg} + $n)) : "") . " -> sysread failure: $!" if $!;
				last;
			}
			$rmsg .= ord($buf);
			$rmsg .= " " if $n <= $nbyte;
			$status = "Ok" if ($n + 1) == $nbyte;
		}
		$clientmsg->{received} = $rmsg if($rmsg);			#Daten als Scalar uebertragen
	} elsif ($clientmsg->{direction} eq "i2cread") {											#blockweise lesen
		my $nbyte = defined($clientmsg->{nbyte}) ? $clientmsg->{nbyte} : 1;
		my $rmsg = "";
		if ( defined($clientmsg->{reg}) ) {
			Log3 $hash, 4, "$hash->{NAME}: HWaccess blockweise lesen setze Registerpointer auf " . ($clientmsg->{reg});
			my $retval = syswrite($fh, chr($clientmsg->{reg}), 1);
			unless (defined($retval) && $retval == 1) {
				Log3 $hash, 3, "$hash->{NAME}: HWaccess blockweise von 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." lesen,". (defined($clientmsg->{reg}) ? " Reg: 0x". unpack( "H2",pack "C", ($clientmsg->{reg})) : "") . " -> syswrite failure: $!" if $!;
				$status = "regerror";
			}
		}
		unless ($status eq "regerror") {
			usleep($clientmsg->{usleep}) if defined $clientmsg->{usleep};       
			my $buf = undef;
			my $retval = sysread($fh, $buf, $nbyte);
			unless (defined($retval) && $retval == $nbyte) {
				Log3 $hash, 3, "$hash->{NAME}: HWaccess blockweise von 0x".unpack( "H2",pack "C", $clientmsg->{i2caddress})." lesen,". (defined($clientmsg->{reg}) ? " Reg: 0x". unpack( "H2",pack "C", ($clientmsg->{reg})) : "") . " -> sysread failure: $!" if $!;
			} else {
				$rmsg = $buf;
				$rmsg =~ s/(.|\n)/sprintf("%u ",ord($1))/eg;
				#Log3 $hash, 1, "test Blockweise lesen menge: |$nbyte|, inh: |$buf|, ergebnis: |$rmsg|";
				$clientmsg->{received} = $rmsg if($rmsg);												#Daten als Scalar uebertragen
				$status = "Ok"
			}
		}
	}
	$hash->{STATE} = $status;
	$hash->{ERRORCNT} = defined($hash->{ERRORCNT}) ? $hash->{ERRORCNT} += 1 : 1 if $status ne "Ok";
	#$clientmsg->{$hash->{NAME} . "_" . "RAWMSG"} = $inh;
	return $status;
}


=pod
=item device
=item summary accesses I2C interface via sysfs on linux
=item summary_DE Zugriff auf das I2C-Interface &uuml;ber sysfs auf Linux Systemen
=begin html

<a name="RPII2C"></a>
<h3>RPII2C</h3>
(en | <a href="commandref_DE.html#RPII2C">de</a>)
<ul>
	<a name="RPII2C"></a>
		Provides access to Raspberry Pi's I2C interfaces for some logical modules and also directly.<br>
		This modul will basically work on every linux system that provides <code>/dev/i2c-x</code>.<br><br>	

		<b>preliminary:</b><br>
		<ul>
			<li>
				load I2C kernel modules (choose <b>one</b> of the following options):<br>
				<ul>
				<li>
          open /etc/modules<br>
          <ul><code>sudo nano /etc/modules</code></ul><br>
          add these lines<br>
          <ul><code>
            i2c-dev<br>
            i2c-bcm2708<br>
          </code></ul>
				</li>
				<li>
          Since Kernel 3.18.x on raspberry pi and maybe on other boards too, device tree support was implemented and enabled by default.
          To enable I2C support just add
          <ul><code>device_tree_param=i2c0=on,i2c1=on</code></ul> to /boot/config.txt
          You can also enable just one of the I2C. In this case remove the unwantet one from the line.
				</li>
				<li>
          On Raspbian images since 2015 just start <code>sudo raspi-config</code> and enable I2C there. Parameters will be added automaticly to /boot/config.txt
				</li>
				reboot
				</ul>
			</li><br>
			<li>Choose <b>only one</b> of the three follwing methodes do grant access to <code>/dev/i2c-*</code> for FHEM user:
				<ul>
				<li>
					<code>sudo apt-get install i2c-tools<br>
					sudo adduser fhem i2c<br>
					sudo reboot</code><br>
				</li><br>
				<li>
					Add following lines into <code>/etc/init.d/fhem</code> before <code>perl fhem.pl</code> line in start or into <code>/etc/rc.local</code>:<br>
					<code>
						sudo chown fhem /dev/i2c-*<br>
						sudo chgrp dialout /dev/i2c-*<br>
						sudo chmod +t /dev/i2c-*<br>
						sudo chmod 660 /dev/i2c-*<br>
					</code>
				</li><br>
				<li>
					Alternatively for Raspberry Pi you can install the gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> library change access rights of I2C-Interface<br>
					WiringPi installation is described here: <a href="#RPI_GPIO">RPI_GPIO.</a><br>
					gpio utility will be automaticly used, if installed.<br>
					Important: to use I2C-0 at P5 connector you must use attribute <code>swap_i2c0</code>.<br>
				</li>
				</ul>
			</li><br>
			<li>
				<b>Optional</b>: access via IOCTL will be used (RECOMMENDED) if Device::SMBus is not present.<br>
				To access the I2C-Bus via the Device::SMBus module, following steps are necessary:<br>
				<ul><code>sudo apt-get install libmoose-perl<br>
				sudo cpan Device::SMBus</code></ul><br>
			</li>
			<li>
				<b>For Raspbian users only</b><br>
				If you are using I2C-0 at P5 connector on Raspberry Pi model B with newer raspbian versions, including support for Raspberry Pi model B+, you must add following line to <code>/boot/cmdline.txt</code>:<br>
				<ul><code>bcm2708.vc_i2c_override=1</code></ul><br>
			</li>
		</ul>
	<a name="RPII2CDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; RPII2C &lt;I2C Bus Number&gt;</code><br>
		where <code>&lt;I2C Bus Number&gt;</code> is the number of the I2C bus that should be used (0 or 1)<br><br>
	</ul>

	<a name="RPII2CSet"></a>
	<b>Set</b>
	<ul>
		<li>
			Write one byte (or more bytes sequentially) directly to an I2C device (for devices that have only one register to write):<br>
			<code>set &lt;name&gt; writeByte &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Write n-bytes to an register range (as an series of single register write operations), beginning at the specified register:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li>
		<li>
			Write n-bytes directly to an I2C device (as an block write operation):<br>	
			<code>set &lt;name&gt; writeBlock &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li>
		<li>
			Write n-bytes to an register range (as an block write operation), beginning at the specified register:<br>	
			<code>set &lt;name&gt; writeBlockReg &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li><br>
		Examples:
		<ul>
			Write 0xAA to device with I2C address 0x60<br>
			<code>set test1 writeByte 60 AA</code><br>
			Write 0xAA to register 0x01 of device with I2C address 0x6E<br>
			<code>set test1 writeByteReg 6E 01 AA</code><br>
			Write 0xAA to register 0x01 of device with I2C address 0x6E, after it write 0x55 to 0x02 as two separate commands<br>
			<code>set test1 writeByteReg 6E 01 AA 55</code><br>
			Write 0xA4 to register 0x03, 0x00 to register 0x04 and 0xDA to register 0x05 of device with I2C address 0x60 as an block command<br>
			<code>set test1 writeBlock 60 03 A4 00 DA</code><br>

		</ul><br>
	</ul>

	<a name="RPII2CGet"></a>
	<b>Get</b>
	<ul>
		<li>
			Gets value of I2C device's registers:<br>
			<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]]</code><br><br>
		</li>
		<li>
			Gets value of I2C device in blockwise mode:<br>
			<code>get &lt;name&gt; readblock &lt;I2C Address&gt; [&lt;number of registers&gt;]</code><br><br>
		</li>
		<li>
			Gets value of I2C device's registers in blockwise mode:<br>
			<code>get &lt;name&gt; readblockreg &lt;I2C Address&gt; &lt;Register Address&gt; [&lt;number of registers&gt;]</code><br><br>
		</li><br>
		Examples:
		<ul>
			Reads byte from device with I2C address 0x60<br>
			<code>get test1 read 60</code><br>
			Reads register 0x01 of device with I2C address 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Reads register 0x03 to 0x06 of device with I2C address 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="RPII2CAttr"></a>
	<b>Attributes</b>
	<ul>
		<li>swap_i2c0<br>
			Swap Raspberry Pi's I2C-0 from J5 to P5 rev. B<br>
			This attribute is for Raspberry Pi only and needs gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> library.<br>
			Default: none, valid values: on, off<br><br>
		</li>
		<li>useHWLib<br>
		Change hardware access method.<br>
		Attribute exists only if both access methods are usable<br>
		Default: IOCTL, valid values: IOCTL, SMBus<br><br>
		</li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html

=begin html_DE

<a name="RPII2C"></a>
<h3>RPII2C</h3>
(<a href="commandref.html#RPII2C">en</a> | de)
<ul>
	<a name="RPII2C"></a>
		Erm&ouml;glicht den Zugriff auf die I2C Schnittstellen des Raspberry Pi, BBB, Cubie &uuml;ber logische Module. Register von I2C IC's k&ouml;nnen auch direkt gelesen und geschrieben werden.<br><br>
		Dieses Modul funktioniert gruns&auml;tzlich auf allen Linux Systemen, die <code>/dev/i2c-x</code> bereitstellen.<br><br>
		
		<b>Vorbereitung:</b><br>
      <ul>
			<li>
				I2C Kernelmodule laden (chose <b>one</b> of the following options):<br>
				<ul>
				<li>
          I2C Kernelmodule laden:<br>
          modules Datei &ouml;ffnen<br>
          <ul><code>sudo nano /etc/modules</code></ul><br>
          folgendes einf&uuml;gen<br>
          <ul><code>
            i2c-dev<br>
            i2c-bcm2708<br>
				</code></ul>
				</li>
				<li>
          Seit Kernel 3.18.x auf dem Raspberry Pi und evtl. auch auf anderen Systemen ist der "Device tree support" implementiert und standardm&auml;&szlig;ig aktiviert.
          Um I2C Unterst&uuml;tzung zu aktivieren mu&szlig;
          <ul><code>device_tree_param=i2c0=on,i2c1=on</code></ul> zur /boot/config.txt hinzu gef&uuml;gt werden.
          Wenn nur einer der Busse genutzt wird, kann der andere einfach aus der Zeile entfernt werden.
				</li>
				<li>
          Bei Raspbian Images seit 2015 kann der I2C Bus einfach &uuml;ber <code>sudo raspi-config</code> aktiviert werden. Die Parameter werden automatisch in die /boot/config.txt eingetragen.
				</li>
				Neustart
				</ul>
			</li><br>
			<li><b>Eine</b> der folgenden drei M&ouml;glichkeiten w&auml;hlen um dem FHEM User Zugriff auf <code>/dev/i2c-*</code> zu geben:
				<ul>
				<li>
					<code>
						sudo apt-get install i2c-tools<br>
						sudo adduser fhem i2c</code><br>
				</li><br>
				<li>
					Folgende Zeilen entweder in die Datei <code>/etc/init.d/fhem</code> vor <code>perl fhem.pl</code> in start, oder in die Datei <code>/etc/rc.local</code> eingef&uuml;gen:<br>
					<code>
						sudo chown fhem /dev/i2c-*<br>
						sudo chgrp dialout /dev/i2c-*<br>
						sudo chmod +t /dev/i2c-*<br>
						sudo chmod 660 /dev/i2c-*<br>
					</code>
				</li><br>
				<li>
					F&uumlr das Raspberry Pi kann alternativ das gpio Utility der <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Bibliothek benutzt werden um FHEM Schreibrechte auf die I2C Schnittstelle zu bekommen.<br>
					WiringPi Installation ist hier beschrieben: <a href="#RPI_GPIO">RPI_GPIO</a><br>
					Das gpio Utility wird, wenn vorhanden, automatisch verwendet<br>
					Wichtig: um den I2C-0 am P5 Stecker des Raspberry nutzen zu k&ouml;nnen muss das Attribut <code>swap_i2c0</code> verwendet werden.<br>
				</li>
				</ul>
			</li><br>
			<li>
				<b>Optional</b>: Hardwarezugriff via IOCTL wird standardm&auml;&szlig;ig genutzt (EMPFOHLEN), wenn Device::SMBus nicht installiert ist<br>
				Soll der Hardwarezugriff &uuml;ber das Perl Modul Device::SMBus erfolgen sind diese Schritte notwendig:<br>
				<ul><code>sudo apt-get install libmoose-perl<br>
				sudo cpan Device::SMBus</code></ul><br>
			</li>
			<li>
				<b>Nur f&uuml;r Raspbian Nutzer</b><br>
				Um I2C-0 am P5 Stecker auf Raspberry Pi modell B mit neueren Raspbian Versionen zu nutzen, welche auch das Raspberry Pi model B+ unterst&uuml;tzen, muss folgende Zeile in die <code>/boot/cmdline.txt</code> eingef&uuml;gt werden:<br>
				<ul><code>bcm2708.vc_i2c_override=1</code></ul><br>
			</li>
		</ul>
	<a name="RPII2CDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; RPII2C &lt;I2C Bus Number&gt;</code><br>
		Die <code>&lt;I2C Bus Number&gt;</code> ist die Nummer des I2C Bus an den die I2C IC's angeschlossen werden<br><br>
	</ul>

	<a name="RPII2CSet"></a>
	<b>Set</b>
	<ul>
		<li>
			Schreibe ein Byte (oder auch mehrere nacheinander) direkt auf ein I2C device (manche I2C Module sind so einfach, das es nicht einmal mehrere Register gibt):<br>
			<code>set &lt;name&gt; writeByte &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Schreibe n-bytes auf einen Registerbereich (als Folge von Einzelbefehlen), beginnend mit dem angegebenen Register:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li>
		<li>
			Schreibe n-bytes auf ein I2C device (als Blockoperation):<br>	
			<code>set &lt;name&gt; writeBlock &lt;I2C Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li>		
		<li>
			Schreibe n-bytes auf einen Registerbereich (als Blockoperation), beginnend mit dem angegebenen Register:<br>	
			<code>set &lt;name&gt; writeBlockReg &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt; [&lt;value&gt; [..]]</code><br><br>
		</li><br>
		Beispiele:
		<ul>
			Schreibe 0xAA zu Modul mit I2C Addresse 0x60<br>
			<code>set test1 writeByte 60 AA</code><br>
			Schreibe 0xAA zu Register 0x01 des Moduls mit der I2C Adresse 0x6E<br>
			<code>set test1 writeByteReg 6E 01 AA</code><br>
			Schreibe 0xAA zu Register 0x01 des Moduls mit der I2C Adresse 0x6E, schreibe danach 0x55 in das Register 0x02 als einzelne Befehle<br>
			<code>set test1 writeByteReg 6E 01 AA 55</code><br>
			Schreibe 0xA4 zu Register 0x03, 0x00 zu Register 0x04 und 0xDA zu Register 0x05 des Moduls mit der I2C Adresse 0x60 zusammen als ein Blockbefehl<br>
			<code>set test1 writeBlockReg 60 03 A4 00 DA</code><br>
		</ul><br>
	</ul>

	<a name="RPII2CGet"></a>
	<b>Get</b>
	<ul>
		<li>
			Auslesen der Registerinhalte des I2C Moduls:<br>
			<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]]</code><br><br>
		</li>
		<li>
			Blockweises Auslesen des I2C Moduls (ohne separate Register):<br>
			<code>get &lt;name&gt; readblock &lt;I2C Address&gt; [&lt;number of registers&gt;]</code><br><br>
		</li>
		<li>
			Blockweises Auslesen der Registerinhalte des I2C Moduls:<br>
			<code>get &lt;name&gt; readblockreg &lt;I2C Address&gt; &lt;Register Address&gt; [&lt;number of registers&gt;]</code><br><br>
		</li><br>
		Beispiele:
		<ul>
			Lese Byte vom Modul mit der I2C Adresse 0x60<br>
			<code>get test1 read 60</code><br>
			Lese den Inhalt des Registers 0x01 vom Modul mit der I2C Adresse 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Lese den Inhalt des Registerbereichs 0x03 bis 0x06 vom Modul mit der I2C Adresse 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="RPII2CAttr"></a>
	<b>Attribute</b>
	<ul>
		<li>swap_i2c0<br>
			Umschalten von I2C-0 des Raspberry Pi Rev. B von J5 auf P5<br>
			Dieses Attribut ist nur f&uuml;r das Raspberry Pi vorgesehen und ben&ouml;tigt das gpio utility wie unter dem Punkt Vorbereitung beschrieben.<br>
			Standard: keiner, g&uuml;ltige Werte: on, off<br><br>
		</li>
		<li>useHWLib<br>
			&Auml;ndern der Methode des Hardwarezugriffs.<br>
			Dieses Attribut existiert nur, wenn beide Zugriffsmethoden verf&uuml;gbar sind<br>
			Standard: IOCTL, g&uuml;ltige Werte: IOCTL, SMBus<br><br>
		</li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html_DE

1;