##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Device::SMBus;

#my $clientsI2C = ":I2C_PC.*:I2C_SHT21:I2C_MCP23017:I2C_BMP180:";

my @clients = qw(
I2C_LCD
I2C_DS1307
I2C_PC.*
I2C_MCP23017
I2C_BMP180
I2C_SHT21
I2C_TSL2561
);

my $gpioprg = "/usr/local/bin/gpio";		#WiringPi GPIO utility


#my %matchListI2C = (			#kann noch weg?
#    "1:I2C_PCF8574"=> ".*",
#    "2:FHT"       => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
#);

sub RPII2C_Initialize($) {
  my ($hash) = @_;
  
# Provider
	$hash->{Clients} = join (':',@clients);
  #$hash->{WriteFn}  = "RPII2C_Write";    #wird vom client per IOWrite($@) aufgerufen
  $hash->{I2CWrtFn} = "RPII2C_Write";    #zum testen als alternative fuer IOWrite

# Normal devices
  $hash->{DefFn}   = "RPII2C_Define";
  $hash->{UndefFn} = "RPII2C_Undef";
  $hash->{GetFn}   = "RPII2C_Get";
  $hash->{SetFn}   = "RPII2C_Set";
  #$hash->{AttrFn}  = "RPII2C_Attr";
	$hash->{NotifyFn} = "RPII2C_Notify";
  $hash->{AttrList}= "do_not_notify:1,0 ignore:1,0 showtime:1,0 " .
                     "$readingFnAttributes";
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
  if(-e $gpioprg) {							#I2C Devices fuer FHEM User lesbar machen
    if(-x $gpioprg) {
      if(-u $gpioprg) {
        my $exp = $gpioprg.' load i2c';
        $exp = `$exp`;
      } else {
        Log3 $hash, 1, "file $gpioprg is not setuid"; 
      }
    } else {
       Log3 $hash, 1, "file $gpioprg is not executable"; 
    }
  } else {
    Log3 $hash, 1, "file $gpioprg doesnt exist"; 
  }    #system "/usr/local/bin/gpio load i2c";
  
  my $name = $a[0];
  my $dev = $a[2];
	
	$hash->{NOTIFYDEV} = "global";
	
  #$hash->{Clients} = $clientsI2C;
  #$hash->{MatchList} = \%matchListI2C;

  if($dev eq "none") {
    Log3 $name, 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  return $name . ': Error! I2C device not found: /dev/i2c-'.$dev . '. Please check kernelmodules must loaded: i2c_bcm2708, i2c_dev' unless -e "/dev/i2c-".$dev;
	return $name . ': Error! I2C device not readable: /dev/i2c-'.$dev . '. Please install wiringpi or change access rights for fhem user' unless -r "/dev/i2c-".$dev;
	return $name . ': Error! I2C device not writable: /dev/i2c-'.$dev . '. Please install wiringpi or change access rights for fhem user' unless -w "/dev/i2c-".$dev;
	
	$hash->{DeviceName} = "/dev/i2c-".$dev;
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
sub RPII2C_Set($@) {								#writeBlock noch nicht fertig
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $type = shift @a;
	my @sets = ('writeByte', 'writeByteReg', 'writeBlock'); #, 'writeNBlock');
  return "Unknown argument $type, choose one of " . join(" ", @sets) if @a < 2;

	foreach (@a) {																																					#Hexwerte pruefen und in Dezimalwerte wandeln
		return "$name: $_ is no 1byte hexadecimal value" if $_ !~ /^(0x|)[0-9A-F]{1,2}$/xi ;
		$_ = hex;
	}
  my $i2ca = shift @a;
	return "$name: I2C Address not valid" unless ($i2ca > 3 && $i2ca < 128);								#pruefe auf Hexzahl zwischen 4 und 7F

  my $i2chash = { i2caddress => $i2ca, direction => "i2cwrite" };
	my ($reg, $nbyte, $data) = undef;
	if ($type eq "writeByte") {
		$data = join(" ", @a);
	} elsif ($type eq "writeByteReg") {
		$reg = shift @a;
		$data = join(" ", @a);
	} elsif ($type eq "writeBlock") {
		$reg = shift @a;
		$nbyte = int(@a);
		return "$name maximal blocksize (32byte) exeeded" if $nbyte > 32;
		$data = join(" ", @a);
		$i2chash->{direction} = "i2cblockwrite";
#####kommt weg da sinnlos??!!! Achtung $nbyte stimmt derzeit nicht
#	} elsif ($type eq "writeNBlock") {
#		$reg = shift @a;
#		return "$name register address must be a hexvalue" if (!defined($reg) || $reg !~ /^(0x|)[0-9A-F]{1,4}$/xi);
#		$nbyte = shift @a;
#		return "$name number of bytes must be decimal value" if (!defined($nbyte) || $nbyte !~ /^[0-9]{1,2}$/);
#		return "$name data values must be n times number of bytes" if (int(@a) % $nbyte != 0);
#		$data = join(" ", @a);
#########################################################################
	}else {
		return "Unknown argument $type, choose one of " . join(" ", @sets);
	}
	
	$i2chash->{reg}   = $reg if defined($reg);																			#startadresse zum lesen
	$i2chash->{nbyte} = $nbyte if defined($nbyte);
	$i2chash->{data} = $data if defined($data);
	RPII2C_HWACCESS($hash, $i2chash);
	undef $i2chash;																																	#Hash loeschen
	return undef;
}
##################################### fertig?
sub RPII2C_Get($@) {								#
  my ($hash, @a) = @_;
  my $nargs = int(@a);
  my $name = $hash->{NAME};
  my @gets = ('read');
  unless ( exists($a[1]) && $a[1] ne "?" && grep {/^$a[1]$/} @gets ) { 
	return "Unknown argument $a[1], choose one of " . join(" ", @gets);
  }
	if ($a[1] eq "read") {
		return "use: \"get $name $a[1] <i2cAddress> [<RegisterAddress> [<Number od bytes to get>]]\"" if(@a < 3);  
		return "$name: I2C Address not valid"             unless (                  $a[2] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
		return "$name register address must be a hexvalue" 		if (defined($a[3]) && $a[3] !~ /^(0x|)[0-9A-F]{1,4}$/xi);
		return "$name number of bytes must be decimal value"  if (defined($a[4]) && $a[4] !~ /^[0-9]{1,2}$/);
		my $i2chash = { i2caddress => hex($a[2]), direction => "i2cread" };
		$i2chash->{reg}   = hex($a[3]) if defined($a[3]);																			#startadresse zum lesen
		$i2chash->{nbyte} = $a[4] if defined($a[4]);
		#Log3 $hash, 1, "Reg: ". $i2chash->{reg};
	  my $status = RPII2C_HWACCESS($hash, $i2chash);
		#my $received = join(" ", @{$i2chash->{received}});															#als Array
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
		$clientmsg->{$name . "_" . "SENDSTAT"} = RPII2C_HWACCESS($hash, $clientmsg);
	}
	
	foreach my $d ( sort keys %main::defs ) {				#zur Botschaft passenden Clienten ermitteln geht auf Client: I2CRecFn
    #Log3 $hash, 1, "d: $d". ($main::defs{$d}{IODev}? ", IODev: $main::defs{$d}{IODev}":"") . ($main::defs{$d}{I2C_Address} ? ", I2C: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{i2caddress} ? " CI2C: $clientmsg->{i2caddress}" : "");
	  if ( defined( $main::defs{$d} )
				&& defined( $main::defs{$d}{IODev} )    && $main::defs{$d}{IODev} == $hash
				&& defined( $main::defs{$d}{I2C_Address} ) && defined($clientmsg->{i2caddress})
                && $main::defs{$d}{I2C_Address} eq $clientmsg->{i2caddress} ) {
	    my $chash = $main::defs{$d};
			Log3 $hash, 5, "$name ->Client gefunden: $d". ($main::defs{$d}{I2C_Address} ? ", I2Caddress: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{data} ? " Data: $clientmsg->{data}" : "");
	    CallFn($d, "I2CRecFn", $chash, $clientmsg);
			undef $clientmsg														#Hash loeschen nachdem Daten verteilt wurden
    }
	}
  return undef;
}
#####################################
sub RPII2C_HWACCESS($$) {
    my ($hash, $clientmsg) = @_;
		my $status = "error";
		my $inh = undef;
		Log3 $hash, 5, "$hash->{NAME}: HWaccess I2CAddr: " . sprintf("0x%.2X", $clientmsg->{i2caddress});
		my $dev = Device::SMBus->new(
			I2CBusDevicePath => $hash->{DeviceName},
			I2CDeviceAddress => hex( sprintf("%.2X", $clientmsg->{i2caddress}) ),
		);
		if (defined($clientmsg->{nbyte}) && defined($clientmsg->{reg}) && defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cblockwrite") {	#Registerblock beschreiben
		my @data = split(" ", $clientmsg->{data});
			my $dataref = \@data;
			$inh = $dev->writeBlockData( $clientmsg->{reg} , $dataref );
			my $wr = join(" ", @{$dataref});
			Log3 $hash, 5, "$hash->{NAME}: Block schreiben Register: " . sprintf("0x%.2X", $clientmsg->{reg}) . " Inhalt: " . $wr . " N: ". int(@data) ." Returnvar.: $inh";
			$status = "Ok" if $inh == 0;
#kommt wieder weg#################
		} elsif (defined($clientmsg->{nbyte}) && defined($clientmsg->{reg}) && defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cwrite") {	#Registerbereich (mehrfach) beschreiben
		  my @data = split(" ", $clientmsg->{data});
			foreach (0..$#data) {
				my $i =	$_ -( int($_ / $clientmsg->{nbyte}) * $clientmsg->{nbyte} );
				$inh = $dev->writeByteData( ($clientmsg->{reg} + $i ) ,$data[$_]);
				Log3 $hash, 5, "$hash->{NAME} NReg schreiben; Reg: " . ($clientmsg->{reg} + $i) . " Inh: " . $data[$_] . " Returnvar.: $inh";
				last if $inh != 0;
				$status = "Ok" if $inh == 0;
			}
#hier Mehrfachbeschreibung eines Registers noch entfernen und dafuer Bereich mit Registeroperationen beschreiben
		} elsif (defined($clientmsg->{reg}) && defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cwrite") {	#Register beschreiben
		  my @data = split(" ", $clientmsg->{data});
		  foreach (@data) {
				$inh = $dev->writeByteData($clientmsg->{reg},$_);
				Log3 $hash, 5, "$hash->{NAME}; Register ".sprintf("0x%.2X", $clientmsg->{reg})." schreiben - Inhalt: " .sprintf("0x%.2X",$_) . " Returnvar.: $inh";
				last if $inh != 0;
				$status = "Ok" if $inh == 0;
			} 
		} elsif (defined($clientmsg->{data}) && $clientmsg->{direction} eq "i2cwrite") {																#Byte(s) schreiben
		  my @data = split(" ", $clientmsg->{data});
		  foreach (@data) {
				$inh = $dev->writeByte($_);
				Log3 $hash, 5, "$hash->{NAME} Byte schreiben; Inh: " . $_ . " Returnvar.: $inh";
				last if $inh != 0;
				$status = "Ok" if $inh == 0;
			}	
		} elsif (defined($clientmsg->{reg}) && $clientmsg->{direction} eq "i2cread") {																	#Register lesen
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
		} elsif ($clientmsg->{direction} eq "i2cread") {																																#Byte lesen
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

=pod
=begin html

<a name="RPII2C"></a>
<h3>RPII2C</h3>
<ul>
	<a name="RPII2C"></a>
		Provides access to Raspberry Pi's I2C interfaces for some logical modules and also directly.<br>
		This modul will basically work on every linux system that provides <code>/dev/i2c-x</code>.<br><br>	

		<b>preliminary:</b><br>
		<ul>
			<li>
				This module uses gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> library change access rights of I2C-Interface<br>
				WiringPi installation is described here: <a href="#RPI_GPIO">RPI_GPIO</a><br>
				Alternatively for other systems (BeagleBone, etc.) you can manually change access rights for <code>/dev/i2c-x</code>. You will need write-/read access for user that runs FHEM. This can be doen e.g. in etc/init.d/fhem<br>

			</li>
			<li>
				installation of i2c dependencies:<br>
				<code>sudo apt-get install libi2c-dev i2c-tools build-essential</code><br>
			</li>
			<li>
				load I2C kernel modules:<br>
				open /etc/modules<br>
				<code>sudo nano /etc/modules</code><br>
				add theese lines<br>
				<code>
					i2c-dev<br>
					i2c-bcm2708<br>
				</code>
			</li>
			<li>
				To access the I2C-Bus the Device::SMBus module is necessary:<br>
				<code>sudo apt-get install libmoose-perl<br>
				sudo cpan Device::SMBus</code><br>
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
			<code>set &lt;name&gt; writeByte    &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Write one byte (or more bytes sequentially) to the specified register of an I2C device:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt;  &lt;value&gt;</code><br><br>
		</li>
		<li>
			Write n-bytes to an register range, beginning at the specified register:<br>	
			<code>set &lt;name&gt; writeBlock   &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Same as writeBlock but writes register range sequentially. The numbers of byte to write must be a multipe of the number of register.
			<code>set &lt;name&gt; writeNBlock  &lt;I2C Address&gt; &lt;Register Address&gt; &lt;number of registers&gt; &lt;value&gt;</code><br><br>
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
		<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]] </code>
		<br>
		gets value of I2C device's registers<br><br>
		Examples:
		<ul>
			Reads byte from device with I2C address 0x60<br>
			<code>get test1 writeByte 60</code><br>
			Reads register 0x01 of device with I2C address 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Reads register 0x03 to 0x06 of device with I2C address 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="RPII2CAttr"></a>
	<b>Attributes</b>
	<ul>
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
<ul>
	<a name="RPII2C"></a>
		Erm&ouml;glicht den Zugriff auf die I2C Schnittstellen des Raspberry Pi &uuml;ber logische Module. Register von I2C IC's k&ouml;nnen auch direkt gelesen und geschrieben werden.<br><br>
		Dieses Modul funktioniert gruns&auml;tzlich auf allen Linux Systemen, die <code>/dev/i2c-x</code> bereitstellen.<br><br>
		
		<b>Vorbereitung:</b><br>
		<ul>
			<li>
				Dieses Modul nutzt das gpio Utility der <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Bibliothek um FHEM Schreibrechte auf die I2C Schnittstelle zu geben.<br>
				WiringPi Installation ist hier beschrieben: <a href="#RPI_GPIO">RPI_GPIO</a><br>
				F&uuml;r andere Systeme (BeagleBone, etc.) oder auch f&uuml;r das Raspberry kann auf WiringPi verzichtet werden. In diesem Fall m&uuml;ssen die Dateien <code>/dev/i2c-x</code> Schreib-/Leserechte, f&uuml;r den User unter dem FHEM l&auml;uft, gesetzt bekommen. (z.B. in der etc/init.d/fhem)<br>
			</li>
			<li>
				Installation der I2C Abh&auml;ngigkeiten:<br>
				<code>sudo apt-get install libi2c-dev i2c-tools build-essential</code><br>
			</li>
			<li>
				I2C Kernelmodule laden:<br>
				modules Datei &ouml;ffnen<br>
				<code>sudo nano /etc/modules</code><br>
				folgendes einf&uuml;gen<br>
				<code>
					i2c-dev<br>
					i2c-bcm2708<br>
				</code>
			</li>
			<li>
				Desweiteren ist das Perl Modul Device::SMBus f&uuml;r den Zugrff auf den I2C Bus notwendig:<br>
				<code>sudo apt-get install libmoose-perl<br>
				sudo cpan Device::SMBus</code><br>
			</li>
		</ul>
	<a name="RPII2CDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; RPII2C &lt;I2C Bus Number&gt;</code><br>
		Die <code>&lt;I2C Bus Number&gt;</code> ist  die Nummer des I2C Bus an den die I2C IC's angeschlossen werden (0 oder 1)<br><br>
	</ul>

	<a name="RPII2CSet"></a>
	<b>Set</b>
	<ul>
		<li>
			Schreibe ein Byte (oder auch mehrere nacheinander) direkt auf ein I2C device (manche I2C Module sind so einfach, das es nicht einmal mehrere Register gibt):<br>
			<code>set &lt;name&gt; writeByte    &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Schreibe ein Byte (oder auch mehrere nacheinander) direkt auf ein Register des adressierten I2C device:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt;  &lt;value&gt;</code><br><br>
		</li>
		<li>
			Schreibe n-bytes auf einen Registerbereich, beginnend mit dem angegebenen Register:<br>	
			<code>set &lt;name&gt; writeBlock   &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Identisch zu writeBlock nur kann der Registerbereich sequentiell beschrieben werden. Die Anzahl der Byte muss ein vielfaches der &lt;number of registers&gt; sein.
			<code>set &lt;name&gt; writeNBlock  &lt;I2C Address&gt; &lt;Register Address&gt; &lt;number of registers&gt; &lt;value&gt;</code><br><br>
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
			<code>set test1 writeBlock 60 03 A4 00 DA</code><br>
		</ul><br>
	</ul>

	<a name="RPII2CGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]] </code>
		<br>
		Auslesen der Registerinhalte des I2C Moduls<br><br>
		Examples:
		<ul>
			Lese Byte vom Modul mit der I2C Adresse 0x60<br>
			<code>get test1 writeByte 60</code><br>
			Lese den Inhalt des Registers 0x01 vom Modul mit der I2C Adresse 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Lese den Inhalt des Registerbereichs 0x03 bis 0x06 vom Modul mit der I2C Adresse 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="RPII2CAttr"></a>
	<b>Attribute</b>
	<ul>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html_DE

1;
