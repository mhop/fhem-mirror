#
#	kaihs@FHEM_Forum (forum.fhem.de)
#
# $Id$
#
# 

package main;

use strict;
use warnings;
use SetExtensions;
use WMBus;


#my %defaultAttrs = (
#	# manufacturer
#	FFD => { # FastForward AG, EnergyCam
#		# type
#		  2 => [ # electricity
#		  # fhem commands to execute
#			'attr %D% userreading energy:1:value { ReadingsVal("%D%","1:value",0)/1000 . " kWh";; }',
#			'attr %D% stateformat {ReadingsVal("%D%","energy","") . " " . ReadingsTimestamp("%D%","energy","");;}',
#			],
#			3 => [ # gas
#		  # fhem commands to execute
#			'attr %D% userreading volume:1:value { ReadingsVal("%D%","1:value",0) . " " . ReadingsVal("%D%","1:unit","");; }',
#			'attr %D% stateformat {ReadingsVal("%D%","volume","") . " " . ReadingsTimestamp("%D%","volume","");;}',
#			],
#			7 => [ # water
#		  # fhem commands to execute
#			'attr %D% userreading volume:1:value { ReadingsVal("%D%","1:value",0) . " " . ReadingsVal("%D%","1:unit","");; }',
#			'attr %D% stateformat {ReadingsVal("%D%","volume","") . " " . ReadingsTimestamp("%D%","volume","");;}',
#			],
#		
#		}
#);
			

sub WMBUS_Parse($$);
sub WMBUS_SetReadings($$$);
sub WMBUS_SetRSSI($$$);

sub WMBUS_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}     = "^b.*";
  #$hash->{SetFn}     = "WMBUS_Set";
  #$hash->{GetFn}     = "WMBUS_Get";
  $hash->{DefFn}     = "WMBUS_Define";
  $hash->{UndefFn}   = "WMBUS_Undef";
  #$hash->{FingerprintFn}   = "WMBUS_Fingerprint";
  $hash->{ParseFn}   = "WMBUS_Parse";
  $hash->{AttrFn}    = "WMBUS_Attr";
  $hash->{AttrList}  = "IODev".
                       " AESkey".
                       " ignore:0,1".
                       " $readingFnAttributes";
}

sub
WMBUS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
	my $mb;
	my $rssi;

  if(@a != 6 && @a != 3) {
    my $msg = "wrong syntax: define <name> WMBUS [<ManufacturerID> <SerialNo> <Version> <Type>]|b<HexMessage>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $name = $a[0];

  if (@a == 3) {
		# unparsed message
		my $msg = $a[2];
		
		($msg, $rssi) = split(/::/,$msg);
		
		return "a WMBus message must be a least 12 bytes long" if $msg !~ m/b[a-zA-Z0-9]{24,}/;
		
		$mb = new WMBus;
		if ($mb->parseLinkLayer(pack('H*',substr($msg,1)))) {
			$hash->{Manufacturer} = $mb->{manufacturer};
			$hash->{IdentNumber} = $mb->{afield_id};
			$hash->{Version} = $mb->{afield_ver};
			$hash->{DeviceType} = $mb->{afield_type};
			if ($mb->{errormsg}) {
				$hash->{Error} = $mb->{errormsg};
			} else {
				delete $hash->{Error};
			}
			WMBUS_SetRSSI($hash, $mb, $rssi);
		} else {
			return "failed to parse msg: $mb->{errormsg}";
		}

	} else {
	  # manual specification
    if ($a[2] !~ m/[A-Z]{3}/) {
			return "$a[2] is not a valid WMBUS manufacturer id";
		}

    if ($a[3] !~ m/[0-9]{1,8}/) {
			return "$a[3] is not a valid WMBUS serial number";
		}

    if ($a[4] !~ m/[0-9]{1,2}/) {
			return "$a[4] is not a valid WMBUS version";
		}

    if ($a[5] !~ m/[0-9]{1,2}/) {
			return "$a[5] is not a valid WMBUS type";
		}

		$hash->{Manufacturer} = $a[2];
		$hash->{IdentNumber} = sprintf("%08d",$a[3]);
		$hash->{Version} = $a[4];
		$hash->{DeviceType} = $a[5];
		
  }
  my $addr = join("_", $hash->{Manufacturer},$hash->{IdentNumber},$hash->{Version},$hash->{DeviceType}) ;
  
  return "WMBUS device $addr already used for $modules{WMBUS}{defptr}{$addr}->{NAME}." if( $modules{WMBUS}{defptr}{$addr}
                                                                                             && $modules{WMBUS}{defptr}{$addr}->{NAME} ne $name );
  $hash->{addr} = $addr;
  $modules{WMBUS}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  $hash->{DEF} = join(" ", $hash->{Manufacturer},$hash->{IdentNumber},$hash->{Version},$hash->{DeviceType});
	
	$hash->{DeviceMedium} = WMBus::->type2string($hash->{DeviceType}); 
	if (defined($mb)) {
	
		if ($mb->parseApplicationLayer()) {
			if ($mb->{cifield} == WMBus::CI_RESP_12) { 
				$hash->{Meter_Id} = $mb->{meter_id};
				$hash->{Meter_Manufacturer} = $mb->{meter_manufacturer};
				$hash->{Meter_Version} = $mb->{meter_vers};
				$hash->{Meter_Dev} = $mb->{meter_devtypestring};
				$hash->{Access_No} = $mb->{access_no};
				$hash->{Status} = $mb->{status};
			}
			WMBUS_SetReadings($hash, $name, $mb);
		} else {
			$hash->{Error} = $mb->{errormsg};
		}
	}
  return undef;
}

#####################################
sub
WMBUS_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{WMBUS}{defptr}{$addr} );

  return undef;
}

#####################################
sub
WMBUS_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
WMBUS_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}


sub
WMBUS_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  my $addr;
  my $rhash;
  my $rssi;
  
  # $hash is the hash of the IODev!
 
  if( $msg =~ m/^b/ ) {
		# WMBus message received
		
		Log3 $name, 5, "WMBUS raw msg " . $msg;
		
		my $mb = new WMBus;
		
		($msg, $rssi) = split(/::/,$msg);
		
		if ($mb->parseLinkLayer(pack('H*',substr($msg,1)))) {
			$addr = join("_", $mb->{manufacturer}, $mb->{afield_id}, $mb->{afield_ver}, $mb->{afield_type});  

			$rhash = $modules{WMBUS}{defptr}{$addr};

			if( !$rhash ) {
					Log3 $name, 3, "WMBUS Unknown device $msg, please define it";
			
					return "UNDEFINED WMBUS_$addr WMBUS $msg";
			}
			WMBUS_SetRSSI($rhash, $mb, $rssi);

			my $rname = $rhash->{NAME};
			my $aeskey;

			if ($aeskey = AttrVal($rname, 'AESkey', undef)) {
				$mb->{aeskey} = pack("H*",$aeskey);
			} else {
				$mb->{aeskey} = undef; 
			}
			if ($mb->parseApplicationLayer()) {
				return WMBUS_SetReadings($rhash, $rname, $mb);
			} else {
				Log3 $rname, 2, "WMBUS $rname Error during ApplicationLayer parse:" . $mb->{errormsg};
				readingsSingleUpdate($rhash, "state", 	$mb->{errormsg}, 1);
				return $rname;
			}
		} else {
			# error
			Log3 $name, 2, "WMBUS Error during LinkLayer parse:" . $mb->{errormsg};
			return undef;
		}
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }
}

sub WMBUS_SetRSSI($$$) {
	my ($hash, $mb, $rssi) = @_;
	
	readingsBeginUpdate($hash);
	# RSSI is decoded by 00_CUL.pm from the last byte of the message
	readingsBulkUpdate($hash, "RSSI", $rssi ? $rssi : 'unknown');
	if (defined $mb->{remainingData} && length($mb->{remainingData}) >= 1) {
		# if there is a trailing byte after the WMBUS message it is the LQI
		readingsBulkUpdate($hash, "LQI", unpack("C", $mb->{remainingData}));
	}	
	readingsEndUpdate($hash,1);
}

sub WMBUS_SetReadings($$$$)
{
	my ($hash, $name, $mb) = @_;
	
	my @list;
	push(@list, $name);

	readingsBeginUpdate($hash);
	
	if ($mb->{decrypted}) {
		my $dataBlocks = $mb->{datablocks};
		my $dataBlock;
		
		for $dataBlock ( @$dataBlocks ) {
			readingsBulkUpdate($hash, "$dataBlock->{number}:storage_no", $dataBlock->{storageNo});
			readingsBulkUpdate($hash, "$dataBlock->{number}:type", $dataBlock->{type}); 
			readingsBulkUpdate($hash, "$dataBlock->{number}:value", $dataBlock->{value}); 
			readingsBulkUpdate($hash, "$dataBlock->{number}:unit", $dataBlock->{unit});
			if ($dataBlock->{errormsg}) {
				readingsBulkUpdate($hash, "$dataBlock->{number}:errormsg", $dataBlock->{errormsg});
			}
		}
	}
	readingsBulkUpdate($hash, "is_encrypted", $mb->{isEncrypted});
	readingsBulkUpdate($hash, "decryption_ok", $mb->{decrypted});
	
	if ($mb->{decrypted}) {
		readingsBulkUpdate($hash, "state", $mb->{statusstring});
	} else {
		readingsBulkUpdate($hash, "state", 'decryption failed');
	}
	
	readingsEndUpdate($hash,1);

	return @list;
  
}

#####################################
sub
WMBUS_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);


  my $list = "resetAccumulatedPower";
  return $list if( $cmd eq '?' || $cmd eq '');


  if($cmd eq "resetAccumulatedPower") {
    CommandAttr(undef, "$name accumulatedPowerOffset " . $hash->{READINGS}{accumulatedPowerMeasured}{VAL});
  } 
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
WMBUS_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};
	my $msg = '';

	if ($attrName eq 'AESkey') {
			if ($attrVal =~ /^[0-9A-Fa-f]{32}$/) {
				$hash->{wmbus}->{aeskey} = $attrVal;
			} else {
				$msg = "AESkey must be a 32 digit hexadecimal value";
			}
			
	}
	return ($msg) ? $msg : undef;
}

1;

=pod
=begin html

<a name="WMBUS"></a>
<h3>WMBUS - Wireless M-Bus</h3>
<ul>
  This module supports Wireless M-Bus meters for e.g. water, heat, gas or electricity.
  Wireless M-Bus is a standard protocol supported by various manufacturers.
  
  It uses the 868 MHz band for radio transmissions.
  Therefore you need a device which can receive Wireless M-Bus messages, e.g. a <a href="#CUL">CUL</a> with culfw >= 1.59.
  <br>
  WMBus uses two different radio protocols, T-Mode and S-Mode. The receiver must be configured to use the same protocol as the sender.
  In case of a CUL this can be done by setting <a href="#rfmode">rfmode</a> to WMBus_T or WMBus_S respectively.
  <br>
  WMBus devices send data periodically depending on their configuration. It can take days between individual messages or they might be sent
  every minute.
  <br>
  WMBus messages can be optionally encrypted. In that case the matching AESkey must be specified with attr AESkey. Otherwise the decryption
  will fail and no relevant data will be available.
  <br><br>
  <b>Prerequisites</b><br>
  This module requires the perl modules Crypt::CBC, Digest::CRC and Crypt::OpenSSL::AES (AES only if encrypted messages should be processed).<br>
  On a debian based system these can be installed with<br>
  <code>
  sudo apt-get install libcrypt-cbc-perl libdigest-crc-perl libssl-dev<br>
  sudo cpan -i Crypt::OpenSSL::AES
  </code>
  <br><br>
  <a name="WMBUSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WMBUS [&lt;manufacturer id&gt; &lt;identification number&gt; &lt;version&gt; &lt;type&gt;]|&lt;bHexCode&gt;</code> <br>
    <br>
    Normally a WMBus device isn't defined manually but automatically through the <a href="#autocreate">autocreate</a> mechanism upon the first reception of a message.
    <br>
    For a manual definition there are two ways.
    <ul>
			<li>
			By specifying a raw WMBus message as received by a CUL. Such a message starts with a lower case 'b' and contains at least 24 hexadecimal digits.
			The WMBUS module extracts all relevant information from such a message.
			</li>
			<li>
      Explictly specify the information that uniquely identifies a WMBus device. <br>
      The manufacturer code, which is is a three letter shortcut of the manufacturer name. See 
      <a href="http://dlms.com/organization/flagmanufacturesids/index.html">dlms.com</a> for a list of registered ids.<br>
      The identification number is the serial no of the meter.<br>
      version is the version code of the meter<br>
      type is the type of the meter, e.g. water or electricity encoded as a number.
      </li>
      <br>
    </ul>
  </ul>
  <br>

  <a name="WMBUSset"></a>
  <b>Set</b> <ul>N/A</ul><br>
  <a name="WMBUSget"></a>
  <b>Get</b> <ul>N/A</ul><br>
  
  <a name="WMBUSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a><br>
        Set the IO or physical device which should be used for receiving signals
        for this "logical" device. An example for the physical device is a CUL.
	 </li><br>
	 <li>AESKey<br>
			A 16 byte AES-Key in hexadecimal digits. Used to decrypt messages from meters which have encryption enabled.
	</li>
  <li>
    <a href="#ignore">ignore</a>
  </li>
  </ul>
	<br>
  <a name="WMBUSreadings"></a>
  <b>Readings</b><br>
  <ul>
  Meters can send a lot of different information depending on their type. An electricity meter will send other data than a water meter.
  The information also depends on the manufacturer of the meter. See the WMBus specification on <a href="http://www.oms-group.org">oms-group.org</a> for details.
  <br><br>
  The readings are generated in blocks starting with block 1. A meter can send several data blocks.
  Each block has at least a type, a value and a unit, e.g. for an electricity meter it might look like<br>
  <ul>
  <code>1:type VIF_ELECTRIC_ENERGY</code><br>
  <code>1:unit Wh</code><br>
  <code>1:value 2948787</code><br>
	</ul>
	<br>
  There is also a fixed set of readings.
  <ul>
  <li><code>is_encrypted</code> is 1 if the received message is encrypted.</li>
  <li><code>decryption_ok</code> is 1 if a message has either been successfully decrypted or if it is unencrypted.</li>
  <li><code>state</code> contains the state of the meter and may contain error message like battery low. Normally it contains 'no error'.</li>
  </ul>
  </ul>
  
  
</ul>

=end html

=begin html_DE

<a name="WMBUS"></a>
<h3>WMBUS - Wireless M-Bus</h3>
<ul>
  Dieses Modul unterst&uuml;tzt Z&auml;hler mit Wireless M-Bus, z. B. f&uuml;r Wasser, Gas oder Elektrizit&auml;t.
  Wireless M-Bus ist ein standardisiertes Protokoll das von unterschiedlichen Herstellern unterst&uuml;tzt wird.

	Es verwendet das 868 MHz Band f&uuml;r Radio&uuml;bertragungen.
	Daher wird ein Ger&auml;t ben&ouml;tigt das die Wireless M-Bus Nachrichten empfangen kann, z. B. ein <a href="#CUL">CUL</a> mit culfw >= 1.59.
  <br>
  WMBus verwendet zwei unterschiedliche Radioprotokolle, T-Mode und S-Mode. Der Empf&auml;nger muss daher so konfiguriert werden, dass er das selbe Protokoll
  verwendet wie der Sender. Im Falle eines CUL kann das erreicht werden, in dem das Attribut <a href="#rfmode">rfmode</a> auf WMBus_T bzw. WMBus_S gesetzt wird.
  <br>
  WMBus Ger&auml;te senden Daten periodisch abh&auml;ngig von ihrer Konfiguration. Es k&ouml;nnen u. U. Tage zwischen einzelnen Nachrichten vergehen oder sie k&ouml;nnen im 
  Minutentakt gesendet werden.
  <br>
  WMBus Nachrichten k&ouml;nnen optional verschl&uuml;sselt werden. Bei verschl&uuml;sselten Nachrichten muss der passende Schl&uuml;ssel mit dem Attribut AESkey angegeben werden. 
  Andernfalls wird die Entschl&uuml;sselung fehlschlagen und es k&ouml;nnen keine relevanten Daten ausgelesen werden.
  <br><br>
  <b>Voraussetzungen</b><br>
  Dieses Modul ben&ouml;tigt die perl Module Crypt::CBC, Digest::CRC and Crypt::OpenSSL::AES (AES wird nur ben&ouml;tigt wenn verschl&uuml;sselte Nachrichten verarbeitet werden sollen).<br>
  Bei einem Debian basierten System k&ouml;nnen diese so installiert werden<br>
  <code>
  sudo apt-get install libcrypt-cbc-perl libdigest-crc-perl libssl-dev<br>
  sudo cpan -i Crypt::OpenSSL::AES
  </code>
  <br><br>
  <a name="WMBUSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WMBUS [&lt;manufacturer id&gt; &lt;identification number&gt; &lt;version&gt; &lt;type&gt;]|&lt;bHexCode&gt;</code> <br>
    <br>
    Normalerweise wird ein WMBus Device nicht manuell angelegt. Dies geschieht automatisch bem Empfang der ersten Nachrichten eines Ger&auml;tes &uuml;ber den 
    fhem <a href="#autocreate">autocreate</a> Mechanismus.
    <br>
    F&uuml;r eine manuelle Definition gibt es zwei Wege.
    <ul>
			<li>
			Durch Verwendung einer WMBus Rohnachricht wie sie vom CUL empfangen wurde. So eine Nachricht beginnt mit einem kleinen 'b' und enth&auml;lt mindestens
			24 hexadezimale Zeichen.
			Das WMBUS Modul extrahiert daraus alle ben&ouml;tigten Informationen.
			</li>
			<li>
			Durch explizite Angabe der Informationen die ein WMBus Ger&auml;t eindeutig identfizieren.<br>
			Der Hersteller Code, besteht aus drei Buchstaben als Abk&uuml;rzung des Herstellernamens. Eine Liste der Abk&uuml;rzungen findet sich unter
      <a href="http://dlms.com/organization/flagmanufacturesids/index.html">dlms.com</a><br>
      Die Idenitfikationsnummer ist die Seriennummer des Z&auml;hlers.<br>
      Version ist ein Versionscode des Z&auml;hlers.<br>
      Typ ist die Art des Z&auml;hlers, z. B. Wasser oder Elektrizit&auml;t, kodiert als Zahl.
      </li>
      <br>
    </ul>
  </ul>
  <br>

  <a name="WMBUSset"></a>
  <b>Set</b> <ul>N/A</ul><br>
  <a name="WMBUSget"></a>
  <b>Get</b> <ul>N/A</ul><br>
  
  <a name="WMBUSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a><br>
				Setzt den IO oder physisches Ger&auml;t welches f&uuml;r den Empfang der Signale f&uuml;r dieses 'logische' Ger&auml;t verwendet werden soll.
				Ein Beispiel f&uuml;r ein solches Ger&auml;t ist ein CUL.
	 </li><br>
	 <li>AESKey<br>
			Ein 16 Bytes langer AES-Schl&uuml;ssel in hexadezimaler Schreibweise. Wird verwendet um Nachrichten von Z&auml;hlern zu entschl&uuml;sseln bei denen
			die Verschl&uuml;sselung aktiviert ist.
	</li>
  <li>
    <a href="#ignore">ignore</a>
  </li>
	</ul>
	<br>
  <a name="WMBUSreadings"></a>
  <b>Readings</b><br>
  <ul>
  Z&auml;hler k&ouml;nnen sehr viele unterschiedliche Informationen senden, abh&auml;ngig von ihrem Typ. Ein Elektrizit&auml;tsz&auml;hler wird andere Daten senden als ein
  Wasserz&auml;hler. Die Information h&auml;ngt auch vom Hersteller des Z&auml;hlers ab. F&uuml;r weitere Informationen siehe die WMBus Spezifikation unter
  <a href="http://www.oms-group.org">oms-group.org</a>.
  <br><br>
  Die Readings werden als Block dargestellt, beginnend mit Block 1. Ein Z&auml;hler kann mehrere Bl&ouml;cke senden.
  Jeder Block enth&auml;lt zumindest einen Typ, einen Wert und eine Einheit. F&uuml;r einen Elektrizit&auml;tsz&auml;hler k&ouml;nnte das z. B. so aussehen<br>
  <ul>
  <code>1:type VIF_ELECTRIC_ENERGY</code><br>
  <code>1:unit Wh</code><br>
  <code>1:value 2948787</code><br>
	</ul>
	<br>
	Es gibt auch eine Anzahl von festen Readings.
  <ul>
  <li><code>is_encrypted</code> ist 1 wenn die empfangene Nachricht verschl&uuml;sselt ist.</li>
  <li><code>decryption_ok</code> ist 1 wenn die Nachricht entweder erfolgreich entschl&uuml;sselt wurde oder gar nicht verschl&uuml;sselt war.</li>
  <li><code>state</code> enth&auml;lt den Status des Z&auml;hlers und kann Fehlermeldungen wie 'battery low' enthalten. Normalerweise ist der Wert 'no error'.</li>
  </ul>
  </ul>
  
  
</ul>
=end html_DE

=cut
