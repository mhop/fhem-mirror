##############################################
# $Id: 14_SIGNALduino_un.pm 12202 2015-10-17 $
# The file is part of the SIGNALduino project
# see http://www.fhemwiki.de/wiki/SIGNALduino
# to support debugging of unknown signal data
# The purpos is to use it as addition to the SIGNALduino
# S. Butzek, 2015
#

package main;

use strict;
use warnings;
use POSIX;

#####################################
sub
SIGNALduino_un_Initialize($)
{
  my ($hash) = @_;


  $hash->{Match}     = '^[uP]\d+#.*';
  $hash->{DefFn}     = "SIGNALduino_un_Define";
  $hash->{UndefFn}   = "SIGNALduino_un_Undef";
  $hash->{AttrFn}    = "SIGNALduino_un_Attr";
  $hash->{ParseFn}   = "SIGNALduino_un_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 ignore:0,1 ".$readingFnAttributes;
}


#####################################
sub
SIGNALduino_un_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SIGNALduino_un <code> <minsecs> <equalmsg>".int(@a)
		if(int(@a) < 3 || int(@a) > 5);

  $hash->{CODE}    = $a[2];
  $hash->{minsecs} = ((int(@a) > 3) ? $a[3] : 30);
  $hash->{equalMSG} = ((int(@a) > 4) ? $a[4] : 0);
  $hash->{lastMSG} =  "";
  $hash->{bitMSG} =  "";

  $modules{SIGNALduino_un}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";

  AssignIoPort($hash);
  return undef;
}

#####################################
sub
SIGNALduino_un_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{SIGNALduino_un}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  return undef;
}

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
		
	if ($protocol == "7" && length($bitData)>=36)  ## Unknown Proto 7 
	{
		
		
		## Try TX70DTH Decoding
		my $SensorTyp = "TX70DTH";
		my $channel = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,9,3));
		my $bin = substr($bitData,0,8);
		my $id = sprintf('%X', oct("0b$bin"));
		my $bat = int(substr($bitData,8,1)) eq "1" ? "ok" : "critical";
		my $trend = "";
		my $sendMode = "";
		my $temp = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,16,8));
		if (substr($bitData,14,1) eq "1") {
		  $temp = $temp - 1024;
		}
		$temp = $temp / 10;
		my $hum = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,29,7));
		my $val = "T: $temp H: $hum B: $bat";
		Log3 $hash, 4, "$name decoded protocolid: 7 ($SensorTyp) sensor id=$id, channel=$channel, temp=$temp, hum=$hum, bat=$bat\n" ;
		

		# Try Eurochron EAS 800
		  #		        4	 8    12            24    28        36
	      #          0011 0110 1010  000100000010  1111  00111000 0000         	Kanal 3, 25.8 Grad, 56%
	      #          0011 0110 1010  000011110011  1111  00111000 0000     		Kanal 3, 24.3 Grad, 56%
	      #          0011 0001 1001  000100001001  1111  00111101 0000		 	Kanal 2, 26.5 Grad, 61%
	      #          0011 1000 1000  000100000011  1111  01000000 0000         	Kanal 1
	      
	      #                ID?  CHN       TMP        ??     HUM
		$SensorTyp = "EAS800z";
		$id = oct ("0b".substr($bitData,4,4));
		$channel = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,9,3))+1;
		$temp = oct ("0b".substr($bitData,12,12))/10;
		$bat = int(substr($bitData,8,1)) eq "1" ? "ok" : "critical";  # Eventuell falsch!
		$hum = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,28,8));
		$sendMode = int(substr($bitData,4,1)) eq "1" ? "auto" : "manual";  # Eventuell falsch!
		my $type = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,0,4));
		
		Log3 $hash, 4, "$name decoded protocolid: 7 ($SensorTyp / type=$type) mode=$sendMode, sensor id=$id, channel=$channel, temp=$temp, hum=$hum, bat=$bat\n" ;
		
		

	} elsif ($protocol == "6" && length($bitData)>=36)  ## Eurochron 
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
		my $temp = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,25,11));
		if (substr($bitData,24,1) eq "1") {
		  $temp = $temp - 2048
		}
		$temp = $temp / 10.0;
		my $hum = SIGNALduino_SIGNALduino_bin2dec(substr($bitData,17,7));
		my $val = "T: $temp H: $hum B: $bat";
		Log3 $hash, 4, "$name decoded protocolid: 6  $SensorTyp, sensor id=$id, channel=$channel, temp=$temp\n" ;

	} elsif ($protocol == "9" && length($bitData)>=70)  ## Unknown Proto 9 
	{   #http://nupo-artworks.de/media/report.pdf
		
		my $syncpos= index($bitData,"11111110");  #7x1 1x0 preamble
		
		if ($syncpos ==-1 || length($bitData)-$syncpos < 68) 
		{
			Log3 $hash, 4, "$name  ctw600 not found, aborting";
			return undef;
		}
		my $sensdata = substr($bitData,$syncpos+8);

		my $bat = substr($sensdata,0,3);
		my $id = substr($sensdata,4,6);
		my $temp = substr($sensdata,12,10);
		my $hum = substr($sensdata,22,8);
		my $wind = substr($sensdata,30,16);
		my $rain = substr($sensdata,46,16);
		my $winddir = substr($sensdata,66,4);
		
		Log3 $hash, 4, "$name found ctw600 syncpos at $syncpos message is: $sensdata - sensor id:$id, bat:$bat, temp=$temp, hum=$hum, wind=$wind, rain=$rain, winddir=$winddir";

	} elsif ($protocol == "13"  && length($bitData)>=14)  ## RF20 Protocol 
	{  
		my $model=$a[3];
		my $deviceCode = $a[5].$a[6].$a[7].$a[8].$a[9];
		my  $Freq = $a[10].$a[11].$a[12].$a[13].$a[14];

		Log3 $hash, 4, "$name found RF21 protocol. model=$model, devicecode=$deviceCode, freq=$Freq ";
	}
	elsif ($protocol == "14" && length($bitData)>=12)  ## Heidman HX 
	{  

		my $bin = substr($bitData,0,4);
		my $deviceCode = sprintf('%X', oct("0b$bin"));
 	    my $sound = substr($bitData,7,5);

		Log3 $hash, 4, "$name found Heidman HX doorbell. devicecode=$deviceCode, sound=$sound";

	}
	elsif ($protocol == "15" && length($bitData)>=64)  ## TCM 
	{  
		my $deviceCode = $a[4].$a[5].$a[6].$a[7].$a[8];


		Log3 $hash, 4, "$name found TCM doorbell. devicecode=$deviceCode";

	}
	elsif ($protocol == "16" && length($bitData)>=36)  ##Rohrmotor24
	{
		Log3 $hash, 4, "$name / shutter Dooya $bitData received";
		
		
		my $id = oct("0b".substr($bitData,0,29));
		my $channel = oct("0b".substr($bitData,29,3));
		
		my $all = ($channel == 0) ? 1 : 0;
 	    my $commandcode = oct("0b".substr($bitData,33,4));
 	    my $direction="";
 	    
 	    if ($commandcode == 0b001) {$direction="up";}
 	    elsif ($commandcode == 0b011) {$direction="down";}
  	    elsif ($commandcode == 0b101) {$direction="stop";}
		else  { $direction="unknown";}
 	    
		Log3 $hash, 4, "$name found shutter from Dooya. id=$id, channel=$channel, direction=$direction, all_shutters=$all";
	} 
	elsif ($protocol == "21" && length($bitData)>=32)  ##Einhell doorshutter
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
		my $channel = SIGNALduino_bin2dec(substr($bitData,9,3))+1; 
		my $temp = oct ("0b".substr($bitData,20,8))/10; 
		my $bat = int(substr($bitData,8,1)) eq "1" ? "ok" : "critical";  # Eventuell falsch!
		my $sendMode = int(substr($bitData,4,1)) eq "1" ? "auto" : "manual";  # Eventuell falsch!
		my $type = SIGNALduino_bin2dec(substr($bitData,0,4));
		
		Log3 $hash, 4, "$name decoded protocolid: 7 ($SensorTyp / type=$type) mode=$sendMode, sensor id=$id, channel=$channel, temp=$temp, bat=$bat\n" ;


	} else {
		return $dummyreturnvalue;
	}

	
	return $dummyreturnvalue;  # This prevents unkown code Messages in our log
}



sub
SIGNALduino_un_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($modules{SIGNALduino_un}{defptr}{$cde});
  $modules{SIGNALduino_un}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}



sub
SIGNALduino_bin2dec($)
{
  my $h = shift;
  my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
  return sprintf("%d", $int); 
}
sub
SIGNALduino_binflip($)
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
=begin html

<a name="SIGNALduino_un"></a>
<h3>SIGNALduino_un</h3>
<ul>
  The SIGNALduino_un module is a testing and debugging module to decode some devices, it will not create any devices, it will catch only all messages from the signalduino which can't be send to another module
  <br><br>

  <a name="SIGNALduino_undefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIGNALduino_un &lt;code&gt; ]</code> <br>

    <br>
    You can define a Device, but currently you can do nothing with it.
    Autocreate is also not enabled for this module.
    The function of this module is only to output some logging at verbose 4 or higher. May some data is decoded correctly but it's also possible that this does not work.
    The Module will try to process all messages, which where not handled by other modules.
   
  </ul>
  <br>

  <a name="SIGNALduino_unset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#verbose">Verbose</a></li>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="SIGNALduino_un"></a>
<h3>SIGNALduino_un</h3>
<ul>
  Das SIGNALduino_un module ist ein Hilfsmodul um unbekannte Nachrichten debuggen und analysieren zu können.
  Das Modul legt keinerlei Geräte oder ähnliches an.
  <br><br>

  <a name="SIGNALduino_undefine"></a>
  <b>Define</b>
    <code>define &lt;name&gt; SIGNALduino_un &lt;code&gt; </code> <br>

    <br>
    Es ist möglich ein Gerät manuell zu definieren, aber damit passiert überhaupt nichts.
    Autocreate wird auch keinerlei Geräte aus diesem Modul anlegen.
    <br>
    Die einzgeste Funktion dieses Modules ist, ab Verbose 4 Logmeldungen über die Empfangene Nachricht ins Log zu schreiben. Dabei kann man sich leider nicht darauf verlassen, dass die Nachricht korrekt dekodiert wurde.<br>
    Dieses Modul wird alle Nachrichten verarbeiten, welche von anderen Modulen nicht verarbeitet wurden.
  <a name="SIGNALduino_unset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SIGNALduino_unattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#verbose">Verbose</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
