##############################################
# $Id$
# 
# The purpose of this module is to support Maverick sensors
# Sidey79 & Cruizer 2016
#

package main;


use strict;
use warnings;

#use Data::Dumper;


sub
SD_WS_Maverick_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^P47#AA9995[A-Fa-f0-9]+";    
  $hash->{DefFn}     = "SD_WS_Maverick_Define";
  $hash->{UndefFn}   = "SD_WS_Maverick_Undef";
  $hash->{ParseFn}   = "SD_WS_Maverick_Parse";
  $hash->{AttrFn}	 = "SD_WS_Maverick_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                        "$readingFnAttributes ";
  $hash->{AutoCreate} =
        { "SD_WS_Maverick.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME",  autocreateThreshold => "2:180"} };
## Todo: Pruefen der Autocreate Einstellungen

}

#############################
sub
SD_WS_Maverick_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SD_WS_Maverick <model>  ".int(@a)
        if(int(@a) < 3 );

  $hash->{CODE} = $a[2];
  $hash->{lastMSG} =  "";
 # $hash->{bitMSG} =  "";

  $modules{SD_WS_Maverick}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";
  
  my $name= $hash->{NAME};
  return undef;
}

#####################################
sub
SD_WS_Maverick_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{SD_WS_Maverick}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{SD_WS_Maverick}{defptr}{$hash->{CODE}}));
  return undef;
}


###################################
sub
SD_WS_Maverick_Parse($$)
{
  my ($iohash, $msg) = @_;
  #my $rawData = substr($msg, 2);
  my $name = $iohash->{NAME};
  my (undef ,$rawData) = split("#",$msg);
  #$protocol=~ s/^P(\d+)/$1/; # extract protocol

  my $model = "SD_WS_Maverick";
  my $hlen = length($rawData);
  #my $blen = $hlen * 4;
  #my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 

  Log3 $name, 3, "SD_WS_Maverick_Parse  $model ($msg) length: $hlen";
  
  #1      8     13    18       26 
  #AA999559 55555 95999 A9A9A669  Sensor 1 =21 2Grad
  #AA999559 95996 55555 95A65565  Sensor 2 =22 2Grad
  #
  #Header    Sen1  Sens2   
  #my $hashumidity = FALSE;
  
  ## Todo: Change decoding per model into a foreach  
   #foreach $key (keys %models) {
  #   ....
  #}

    #
	my $startup = substr($rawData,6,2);
	my $temp_str1 = substr($rawData,8,5);
	my $temp_str2 = substr($rawData,13,5);
	my $unknown = substr($rawData,18);
  
    Log3 $iohash, 4, "$model decoded protocolid: 47 sensor startup=$startup, temp1=$temp_str1, temp2=$temp_str2, unknown=$unknown";
    
    # Convert 
    $temp_str1 =~ tr/569A/0123/;
    $temp_str2 =~ tr/569A/0123/;
    
    # Calculate temp from data
    my $c;
	my $temp1=-532;
	for ( my $i = 0; $i < length($temp_str1); $i++ ) { 
	    $c = substr( $temp_str1, $i, 1);
	    $temp1 += $c*4**(4-$i);
	}
    
    my $temp2=-532;
	for ( my $i = 0; $i < length($temp_str2); $i++ ) { 
	    $c = substr( $temp_str2, $i, 1);
	    $temp2 += $c*4**(4-$i);
	}
    
    
    Log3 $iohash, 4, "$model decoded protocolid: temp1=$temp1, temp2=$temp2;";
    
    
    
  

    
    #print Dumper($modules{SD_WS_Maverick}{defptr});
    
    my $def = $modules{SD_WS_Maverick}{defptr}{$iohash->{NAME} };
    $def = $modules{SD_WS_Maverick}{defptr}{$model} if(!$def);

    if(!$def) {
		Log3 $iohash, 1, 'SD_WS_Maverick: UNDEFINED sensor ' . $model;
		return "UNDEFINED $model SD_WS_Maverick $model";
    }
        #Log3 $iohash, 3, 'SD_WS_Maverick: ' . $def->{NAME} . ' ' . $id;
	
	my $hash = $def;
	$name = $hash->{NAME};
	Log3 $name, 4, "SD_WS_Maverick: $name ($rawData)";  

	if (!defined(AttrVal($hash->{NAME},"event-min-interval",undef)))
	{
		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
			Log3 $hash, 4, "$model Dropped due to short time. minsecs=$minsecs";
		  	return "";
		}
	}

	$hash->{lastReceive} = time();
	$hash->{lastMSG} = $rawData;
	#$hash->{bitMSG} = $bitData2; 

    my $state = "T: $temp1"." T2: $temp2" ;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $state);
    readingsBulkUpdate($hash, "messageType", $startup);
    
    readingsBulkUpdate($hash, "temp1", $temp1)  if ($temp1 ne"");
    readingsBulkUpdate($hash, "temp2", $temp2)  if ($temp2 ne"");
 
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	return $name;

}

sub SD_WS_Maverick_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return  if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($modules{SD_WS_Maverick}{defptr}{$cde});
  $modules{SD_WS_Maverick}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}


1;


=pod
=item summary    Supports maverick temperature sensors protocl 47 from SIGNALduino
=item summary_DE Unterst&uumltzt Maverick Temperatursensoren mit Protokol 47 vom SIGNALduino
=begin html

<a name="SD_WS_Maverick"></a>
<h3>Wether Sensors protocol #7</h3>
<ul>
  The SD_WS_Maverick module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>Eurochon EAS800z</li>
    <li>Technoline WS6750/TX70DTH</li>
  </ul>
  <br>
  New received device are add in fhem with autocreate.
  <br><br>

  <a name="SD_WS_Maverick_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defice is the cannel or, if the longid attribute is specified, it is a combination of channel and some random generated bits at powering the sensor and the channel.<br>
  If you want to use more sensors, than channels available, you can use the longid option to differentiate them.
  </ul>
  <br>
  <a name="SD_WS_Maverick Events"></a>
  <b>Generated readings:</b>
  <br>Some devices may not support all readings, so they will not be presented<br>
  <ul>
  	 <li>State (T: H:)</li>
     <li>temperature (&deg;C)</li>
     <li>humidity: (The humidity (1-100 if available)</li>
     <li>battery: (low or ok)</li>
     <li>channel: (The Channelnumber (number if)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> ()</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS_Maverick_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Maverick_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="SD_WS_Maverick"></a>
<h3>SD_WS_Maverick</h3>
<ul>
  Das SD_WS_Maverick Module verarbeitet von einem IO Geraet (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b>
  <ul>
    <li>Maverick</li>
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>

  <a name="SD_WS_Maverick_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelegten Sensoren ist entweder der Kanal des Sensors, oder wenn das Attribut longid gesetzt ist, dann wird die ID aus dem Kanal und einer Reihe von Bits erzeugt, welche der Sensor beim Einschalten zuf&aumlllig vergibt.<br>
  </ul>
  <br>
  <a name="SD_WS_Maverick Events"></a>
  <b>Generierte Readings:</b>
  <ul>
  	 <li>State (T: H:)</li>
     <li>temperature (&deg;C)</li>
     <li>humidity: (Luftfeuchte (1-100)</li>
     <li>battery: (low oder ok)</li>
     <li>channel: (Der Sensor Kanal)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> ()</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS_Maverick1_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Maverick_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut
