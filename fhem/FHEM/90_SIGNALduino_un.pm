##############################################
# $Id$
#
# The file is part of the SIGNALduino project
# see http://www.fhemwiki.de/wiki/SIGNALduino to support debugging of unknown signal data
# The purpos is to use it as addition to the SIGNALduino
# S. Butzek, 2015 | HomeAuto_User & elektron-bbs - 2018
#

package main;

use strict;
use warnings;
use POSIX;
use List::Util qw(any);				# for any function

my @bitcountlength = (0,0,0);		# array min|default|max

#####################################
sub
SIGNALduino_un_Initialize($)
{
  my ($hash) = @_;


  $hash->{Match}     = '^[u]\d+#.*';
  $hash->{DefFn}     = "SIGNALduino_un_Define";
  $hash->{UndefFn}   = "SIGNALduino_un_Undef";
  $hash->{AttrFn}    = "SIGNALduino_un_Attr";
  $hash->{SetFn}     = "SIGNALduino_un_Set";
  $hash->{ParseFn}   = "SIGNALduino_un_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 stateFormat showtime:0,1 ignore:0,1 ".$readingFnAttributes;
}

#####################################
sub
SIGNALduino_un_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return " wrong syntax: define <name> SIGNALduino_un <code> <optional IODEV> (".int(@a).")" if(int(@a) < 3 || int(@a) > 4);

  $hash->{lastMSG} =  "";
  $hash->{bitMSG} =  "";
  $hash->{STATE} = "Defined";
  my $name = $hash->{NAME};
  
  my $iodevice = $a[3] if($a[3]);
  $modules{SIGNALduino_un}{defptr}{$a[2]} = $hash;
  
  my $ioname = $modules{SIGNALduino_un}{defptr}{ioname} if (exists $modules{SIGNALduino_un}{defptr}{ioname} && not $iodevice);
  $iodevice = $ioname if not $iodevice;
  
  ### Attributes ###
  if ( $init_done == 1 ) {
	$attr{$name}{stateFormat}	= "{ReadingsVal('$name', 'state', '').' | '.ReadingsTimestamp('$name', 'state', '-');}" if( not defined( $attr{$name}{stateformat} ) );
  }
  
  AssignIoPort($hash, $iodevice);
}

#####################################
sub
SIGNALduino_un_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{SIGNALduino_un}{defptr}{$hash->{DEF}}) if($hash && $hash->{DEF});
  delete($modules{SIGNALduino_un}{defptr}{ioname}) if (exists $modules{SIGNALduino_un}{defptr}{ioname});
  return undef;
}

#####################################
sub SIGNALduino_un_hex2bin {
        my $h = shift;
        my $hlen = length($h);
        my $blen = $hlen * 4;
        return unpack("B$blen", pack("H$hlen", $h));
}

#####################################
sub
SIGNALduino_un_Parse($$)
{
	my ($hash,$msg) = @_;
	my @a = split("", $msg);
	my $name = "SIGNALduino_unknown";# $hash->{NAME};
	my $ioname = $hash->{NAME};
	Log3 $hash, 4, "$name incomming msg: $msg";
	#my $rawData=substr($msg,2);

	my ($protocol,$rawData) = split("#",$msg);
	
	my $dummyreturnvalue= "Unknown, please report";
	$protocol=~ s/^[uP](\d+)/$1/; # extract protocol

	Log3 $hash, 4, "$name rawData: $rawData";
	Log3 $hash, 4, "$name Protocol: $protocol";

	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData= unpack("B$blen", pack("H$hlen", $rawData)); 
	Log3 $hash, 4, "$name converted to bits: $bitData";
		
	if ($protocol == "6" && length($bitData)>=36)  ## Eurochron 
	{   

		  # EuroChron / Tchibo
		  #                /--------------------------- Channel, changes after every battery change      
		  #               /        / ------------------ Battery state 0 == Ok      
		  #              /        / /------------------ unknown      
		  #             /        / /  / --------------- forced send      
		  #            /        / /  /  / ------------- unknown      
		  #           /        / /  /  /     / -------- Humidity      
		  #          /        / /  /  /     /       / - neg Temp: if 1 then temp = temp - 2048
		  #         /        / /  /  /     /       /  / Temp
		  #         01100010 1 00 1  00000 0100011 0  00011011101
		  # Bit     0        8 9  11 12    17      24 25        36

		my $SensorTyp = "EuroChron";
		my $channel = "";
		my $bin = substr($bitData,0,8);
		my $id = sprintf('%X', oct("0b$bin"));
		my $bat = int(substr($bitData,8,1)) eq "0" ? "ok" : "critical";
		my $trend = "";
		my $sendMode = int(substr($bitData,11,1)) eq "0" ? "automatic" : "manual";
		my $temp = SIGNALduino_un_bin2dec(substr($bitData,25,11));
		if (substr($bitData,24,1) eq "1") {
		  $temp = $temp - 2048
		}
		$temp = $temp / 10.0;
		my $hum = SIGNALduino_un_bin2dec(substr($bitData,17,7));
		my $val = "T: $temp H: $hum B: $bat";
		Log3 $hash, 4, "$name decoded protocolid: 6  $SensorTyp, sensor id=$id, channel=$channel, temp=$temp\n" ;

	} elsif ($protocol == "15" && length($bitData)>=64)  ## TCM 
	{  
		my $deviceCode = $a[4].$a[5].$a[6].$a[7].$a[8];


		Log3 $hash, 4, "$name found TCM doorbell. devicecode=$deviceCode";

	} elsif ($protocol == "21" && length($bitData)>=32)  ##Einhell doorshutter
	{
		Log3 $hash, 4, "$name / Einhell doorshutter received";
		
		
		my $id = oct("0b".substr($bitData,0,28));
		
		my $dir = oct("0b".substr($bitData,28,2));
		
		my $channel = oct("0b".substr($bitData,30,3));
		
 	    
		Log3 $hash, 4, "$name found doorshutter from Einhell. id=$id, channel=$channel, direction=$dir";
	} elsif ($protocol == "23" && length($bitData)>=32)  ##Perl Sensor
	{
		my $SensorTyp = "perl NC-7367?";
		my $id = oct ("0b".substr($bitData,4,4));  
		my $channel = SIGNALduino_un_bin2dec(substr($bitData,9,3))+1; 
		my $temp = oct ("0b".substr($bitData,20,8))/10; 
		my $bat = int(substr($bitData,8,1)) eq "1" ? "ok" : "critical";  # Eventuell falsch!
		my $sendMode = int(substr($bitData,4,1)) eq "1" ? "auto" : "manual";  # Eventuell falsch!
		my $type = SIGNALduino_un_bin2dec(substr($bitData,0,4));
		
		Log3 $hash, 4, "$name decoded protocolid: 7 ($SensorTyp / type=$type) mode=$sendMode, sensor id=$id, channel=$channel, temp=$temp, bat=$bat\n" ;


	}
	
	##############################################################################################
	# version 1) message with u..# without development y attribut -> Unknown code u..# , help me!
	# version 2) message with u..# and development y attribut -> no message for Unknown code
	##############################################################################################
	
	my $value = AttrVal($ioname, "development", "");
	my @delevopmentargs = split (",",$value);

	if ($value =~ m/([umyp]$protocol|1)/g) {		# check for u|m|y|p|1 development (u|m|y|p downwards compatibility)
		### Help Device + Logfile ###
		Log3 $hash, 5, "$name: $ioname Protocol $1$protocol found in AttrVal development!";
		
		my $def;
		my $devicedef = $name."_".$protocol;
		$def = $modules{SIGNALduino_un}{defptr}{$devicedef} if(!$def);
		$modules{SIGNALduino_un}{defptr}{ioname} = $ioname;
		
		if(!$def) {
			Log3 $ioname, 1, "$ioname: $name UNDEFINED sensor " . $devicedef . " detected";
			return "UNDEFINED $devicedef SIGNALduino_un $devicedef";
		}
	
		my $hash = $def;
		my $name = $hash->{NAME};
	
		$hash->{lastMSG} = $rawData;
		$hash->{bitMSG} =  $bitData;
	
		my $bitcount = length($bitData);
		
		$bitcountlength[1] = $bitcount if ($bitcountlength[1] == 0);	# to first receive
		
		if ($bitcount != $bitcountlength[1]) {							# comparison
			if ($bitcount gt $bitcountlength[1]) { 
				$bitcountlength[2] = $bitcount;
				$bitcountlength[0] = $bitcountlength[1];
			}
			
			if ($bitcount lt $bitcountlength[1]) {
				$bitcountlength[0] = $bitcount;
				$bitcountlength[2] = $bitcountlength[1];
			}

			$bitcountlength[1] = $bitcount;
			readingsSingleUpdate($hash, "bitCountLength", "$bitcountlength[0] to $bitcountlength[2]" ,0);
		}
		
		my $hexcount = length($rawData);
		my $bitDataInvert = $bitData;
		$bitDataInvert =~ tr/01/10/; 			# invert message and check if it is possible to deocde now
		my $rawDataInvert = SIGNALduino_b2h($bitDataInvert);
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", $rawData,0);
		readingsBulkUpdate($hash, "bitMsg", $bitData);
		readingsBulkUpdate($hash, "bitMsg_invert", $bitDataInvert);
		readingsBulkUpdate($hash, "bitCount", $bitcount);
		readingsBulkUpdate($hash, "hexMsg", $rawData);
		readingsBulkUpdate($hash, "hexMsg_invert", $rawDataInvert);
		readingsBulkUpdate($hash, "hexCount_or_nibble", $hexcount);
		readingsBulkUpdate($hash, "lastInputDev", $ioname);
		readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
		
		### Example Logfile ###
		# 2018-09-24_17:32:53 SIGNALduino_unknown_85 UserInfo: Temp 22.4 Hum 52
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 bitMsg: 11110011101110100011100111111110110110111110111110100110001100101000
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 bitMsg_invert: 00001100010001011100011000000001001001000001000001011001110011010111
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 bitCount: 68
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 hexMsg: F3BA39FEDBEFA6328
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 hexMsg_invert: 0C45C601241059CD7
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 hexCount or nibble: 17
		# 2018-09-24_17:34:25 SIGNALduino_unknown_85 lastInputDev: sduino_dummy

		return $name;
	} else {
		### nothing - Info ###
		my $value = AttrVal($ioname, "development", "");	# read attr development from IODev
		
		if ($value ne "") {
			$value .= ","; 					# some definitions already exist, so prepend a new one
		}
        $value .= "u$protocol";		
		Log3 $hash, 4, "$name $ioname Protocol:$protocol | To help decode or debug, please add u$protocol! (attr $ioname development $value)" if ($protocol);	# To help decode or debug, please add u84! (attr sduino_dummy development u84)
	}
	############################
	
	
	Log3 $hash, 4, $dummyreturnvalue;
	return undef;  
}

#####################################
sub
SIGNALduino_un_Set($$$@)
{
  my ( $hash, $name, @a ) = @_;
  my $ret = "UserInfo";

  if ($a[0] ne "?") {
		my $input = join " ", @a[1 .. (scalar(@a)-1)];		# Teile der Eingabe zusammenfassen
		return "wrong argument! please use $ret argument and one comment." if($a[0] ne "UserInfo" || not $a[1]);
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state" , "UserMSG",0);
		readingsBulkUpdate($hash, "UserMSG", $input)  if (defined($input));
		readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
		
		return undef;						# undef because user is in same windows without message, better to use
		#return "Thanks";
  }
  
  return $ret;
}

#####################################
sub
SIGNALduino_un_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{DEF};
  
  #delete($modules{SIGNALduino_un}{defptr}{$cde});
  #$modules{SIGNALduino_un}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}

#####################################
sub
SIGNALduino_un_binaryToNumber
{
	my $binstr=shift;
	my $fbit=shift;
	my $lbit=$fbit;
	$lbit=shift if @_;
	
	
	return oct("0b".substr($binstr,$fbit,($lbit-$fbit)+1));
	
}

#####################################
sub
SIGNALduino_un_binaryToBoolean
{
	return int(SIGNALduino_un_binaryToNumber(@_));
}

#####################################
sub
SIGNALduino_un_bin2dec($)
{
  my $h = shift;
  my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
  return sprintf("%d", $int); 
}

#####################################
sub
SIGNALduino_un_binflip($)
{
  my $h = shift;
  my $hlen = length($h);
  my $i = 0;
  my $flip = "";
  
  for ($i=$hlen-1; $i >= 0; $i--) {
    $flip = $flip.substr($h,$i,1);
  }

  return $flip;
}

1;

=pod
=item summary    Helper module for SIGNALduino
=item summary_DE Unterst&uumltzungsmodul f&uumlr SIGNALduino
=begin html

<a name="SIGNALduino_un"></a>
<h3>SIGNALduino_un</h3>
<ul>
  The SIGNALduino_un module is a testing and debugging module to decode some devices, it will catch only all messages from the signalduino which can't be send to another module.<br>
  It can create one help devices after define development attribute on SIGNALduino device. You get a hint from Verbose 4 in the FHEM Log.<br>
  <u>example:</u> <code>SIGNALduino_unknown sduino_dummy Protocol:40 | To help decode or debug, please add u40! (attr sduino_dummy development u40)</code>
  <br><br>

  <a name="SIGNALduino_undefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIGNALduino_un &lt;code&gt; </code> <br>

    <br>
    You can define a Device, but currently you can do nothing with it.
    The function of this module is only to output some logging at verbose 4 or higher at FHEM-logfile or logging to help device. May some data is decoded correctly but it's also possible that this does not work.
    The Module will try to process all messages, which where not handled by other modules.<br><br>
	Created devices / logfiles must be deleted manually after removing the protocol from the attribute <code> development</code>. (example: u40, y84)
   
  </ul>
  <br>

  <a name="SIGNALduino_unset"></a>
  <b>Set</b>
  <ul>write "comment" - the user can put comments in the logfile which are arranged to his bits of the device<br>
 (example: to write off the digital display of the thermometer at the time of reception or states of switches ...)</ul>
  <br>

  <a name="SIGNALduino_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
	<li><a href="#stateFormat">stateFormat</a></li>
	<li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  <a name="SIGNALduino_un_readings"></a>
  <b>Generated readings</b>
  <ul>
	<li>bitCount (Length of the signal, binary)</li>
	<li>bitCountLength  (Length range of all received signals of the protocol)</li>
	<li>bitMsg</li>
	<li>bitMsg_invert (Message binary, inverted)</li>
	<li>hexCount_or_nibble (Length of the signal, hexadecimal)</li>
	<li>hexMsg</li>
	<li>hexMsg_invert (Message hexadecimal, inverted)</li>
	<li>lastInputDev (Device at the last reception)</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="SIGNALduino_un"></a>
<h3>SIGNALduino_un</h3>
<ul>
  Das SIGNALduino_un Modul ist ein Hilfsmodul um unbekannte Nachrichten zu debuggen und analysieren zu k&ouml;nnen.<br><br>
  Das Modul legt nur eine Hilfsger&aumlt an mit Logfile der Bits sobald man das Attribut <code>development</code> im Empf&auml;nger Device auf das entsprechende unbekannte Protokoll setzt.<br>
  Einen entsprechenden Hinweis erhalten Sie ab Verbose 4 im FHEM Log.<br>
  <u>Beispiel:</u> <code>SIGNALduino_unknown sduino_dummy Protocol:40 | To help decode or debug, please add u40! (attr sduino_dummy development u40)</code>
  <br><br>

  <a name="SIGNALduino_undefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIGNALduino_un &lt;code&gt; </code> <br>

    <br>
    Es ist m&ouml;glich ein Ger&auml;t manuell zu definieren, aber damit passiert &uuml;berhaupt nichts.
    <br>
    Die einzigste Funktion dieses Modules ist, ab Verbose 4 Logmeldungen &uumlber die Empfangene Nachricht ins FHEM-Log zu schreiben oder in das Logfile des Hilfsger&aumltes.<br>
	Dabei kann man sich leider nicht darauf verlassen, dass die Nachricht korrekt dekodiert wurde. Dieses Modul wird alle Nachrichten verarbeiten, welche von anderen Modulen nicht verarbeitet werden.<br>
	<br>
	Angelegte Ger&auml;te / Logfiles m&uuml;ssen manuell gel&ouml;scht werden nachdem aus dem Attribut <code>development</code> des SIGNALduinos das zu untersuchende Protokoll entfernt wurde. (Beispiel: u40,y84)
  </ul>	
  <br>
  <a name="SIGNALduino_unset"></a>
  <b>Set</b>
  <ul>write "Kommentar" - somit kann der User in das Logfile des Hilfsger&aumlt Kommentare setzen welche zeitlich zu seinen Bits des Ger&aumltes eingeordnet werden<br>
 (Beispiel: um die Digitalanzeige des Thermometers abzuschreiben zum Zeitpunkt des Empfangs oder Zustände von Schaltern ...)</ul>
  <br>

  <a name="SIGNALduino_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
	<li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  <a name="SIGNALduino_un_readings"></a>
  <b>Generierte Readings</b>
  <ul>
	<li>bitCount (L&auml;nge des Signals, binär)</li>
	<li>bitCountLength  (L&auml;ngenbereich aller empfangen Signale des Protokolles)</li>
	<li>bitMsg</li>
	<li>bitMsg_invert (Nachricht bin&auml;r, invertiert)</li>
	<li>hexCount_or_nibble (L&auml;nge des Signals, hexadezimal)</li>
	<li>hexMsg</li>
	<li>hexMsg_invert (Nachricht hexadezimal, invertiert)</li>
	<li>lastInputDev (Device beim letzten Empfang)</li>
  </ul>
</ul>

=end html_DE
=cut
