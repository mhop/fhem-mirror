##############################################
# $Id$
# 
# The purpose of this module is to support Maverick sensors
# Sidey79 & Cruizer 2016
# Ralf9 2018
#
# CHANGED
##############################################################################
# Version 1.1
#  - changed: 14_SD_WS_Maverick: rename Readings for Temperatures
#  - feature: 14_SD_WS_Maverick: added Readings for Sensor-states

package main;


use strict;
use warnings;

#use Data::Dumper;
sub SD_WS_Maverick_Initialize($);
sub SD_WS_Maverick_Define($$);
sub SD_WS_Maverick_Undef($$);
sub SD_WS_Maverick_Parse($$);
sub SD_WS_Maverick_Attr(@);
sub SD_WS_Maverick_SetSensor1Inaktiv($);
sub SD_WS_Maverick_SetSensor2Inaktiv($);
sub SD_WS_Maverick_updateReadings($);

sub
SD_WS_Maverick_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^P47#[A-Fa-f0-9]+";
  $hash->{DefFn}     = "SD_WS_Maverick_Define";
  $hash->{UndefFn}   = "SD_WS_Maverick_Undef";
  $hash->{ParseFn}   = "SD_WS_Maverick_Parse";
  $hash->{AttrFn}	   = "SD_WS_Maverick_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 inactivityinterval " .
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
  # prüfen, ob eine neue Definition angelegt wird 
	if($init_done && !defined($hash->{OLDDEF}))
	{
		# setzen von stateFormat
	 	$attr{$name}{"stateFormat"} = '{
  my $s1=ReadingsVal($name,"Sensor-1-food_state",-1);
  my $s2=ReadingsVal($name,"Sensor-2-bbq_state",-1);
  if ($s1 ne "connected" && $s1 eq $s2 ) {
    return $s1;
  }else{
    my $state="Food: ";
    my $temp_food=ReadingsVal($name,"temp-food","");
    my $temp_bbq=ReadingsVal($name,"temp-bbq","");
    if($s1 eq "connected"){
        $state .=$temp_food;
    }else{
        $state .=$s1;
    }
    $state .=" BBQ: ";
    if($s2 eq "connected"){
        $state .=$temp_bbq;
    }else{
        $state .=$s2;
    }
    return $state;
  }
}';

 	}
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

  Log3 $name, 4, "$name SD_WS_Maverick_Parse  $model ($msg) length: $hlen";
  
  # https://hackaday.io/project/4690-reverse-engineering-the-maverick-et-732/
  # https://forums.adafruit.com/viewtopic.php?f=8&t=25414&sid=e1775df908194d56692c6ad9650fdfb2&start=15#p322178
  #
  #1      8     13    18       26 
  #AA999559 55555 95999 A9A9A669  Sensor 1 =21 2Grad
  #AA999559 95996 55555 95A65565  Sensor 2 =22 2Grad
  #  
  ## Todo: Change decoding per model into a foreach  
  #foreach $key (keys %models) {
  #   ....
  #}
  
  # ohne header:
  # MC;LL=-507;LH=490;SL=-258;SH=239;D=AA9995599599A959996699A969;C=248;L=104;
  # P47#599599A959996699A969
  #
  # 0  2   6 7     12
  # ss 11111 22222 uuuuuuuu
  # 59 9599A 95999 6699A969
  # 

	my $messageType = substr($rawData,0,2);   # 0x6A upon startup, 0x59 otherwise
	my $temp_str1 = substr($rawData,2,5);
	my $temp_str2 = substr($rawData,7,5);
	my $checksum_str = substr($rawData,12);
  
  Log3 $iohash, 4, "$name $model decoded protocolid: 47 sensor messageType=$messageType, temp-f=$temp_str1, temp-b=$temp_str2, checksum-s=$checksum_str";
  
  if ($messageType eq '59'){
    $messageType="normal";
  }elsif ($messageType eq '6A') {
    $messageType="sync";  
  }else{
    Log3 $iohash, 4, "$name $model ERROR: wrong messageType=$messageType (must be 59 or 6A)";
    return '';
  }
  
  # Calculate temp from data
  my $c;
  my $temp_food=-532;
  my $temp_bbq=-532;
  my $sensor_1_state="unknown";
  my $sensor_2_state="unknown";;
  
  if ($temp_str1 ne '55555') {
    $temp_str1 =~ tr/569A/0123/;
    for ( my $i = 0; $i < length($temp_str1); $i++ ) { 
      $c = substr( $temp_str1, $i, 1);
      $temp_food += $c*4**(4-$i);
    }
    if ($temp_food <= 0 || $temp_food > 300) {
      Log3 $iohash, 4, "$name $model ERROR: wrong temp-food=$temp_food";
      $temp_food = "";
    }else{
      $sensor_1_state="connected"; 
    }
  } else {
    $sensor_1_state="disconnected"  if ($temp_str1 eq '55555');
    $temp_food = "";
  }
    
  
  if ($temp_str2 ne '55555') { 
    $temp_str2 =~ tr/569A/0123/;
    for ( my $i = 0; $i < length($temp_str2); $i++ ) { 
      $c = substr( $temp_str2, $i, 1);
      $temp_bbq += $c*4**(4-$i);
    }
    if ($temp_bbq <= 0 || $temp_bbq > 300) {
      Log3 $iohash, 4, "$name $model ERROR: wrong temp-bbq=$temp_bbq";
      $temp_bbq = "";
    }else{
      $sensor_2_state="connected"; 
    }
  } else {
    $sensor_2_state="disconnected"  if ($temp_str2 eq '55555');
    $temp_bbq = "";
  }
  
  #if ($temp_bbq eq "" && $temp_food eq "") {
  #  return '';
  #}
  
  Log3 $iohash, 4, "$name $model decoded protocolid: temp-food=$temp_food, temp-bbq=$temp_bbq;";
  
  #print Dumper($modules{SD_WS_Maverick}{defptr});
    
  my $def = $modules{SD_WS_Maverick}{defptr}{$iohash->{NAME} };
  $def = $modules{SD_WS_Maverick}{defptr}{$model} if(!$def);

  if(!$def) {
    Log3 $iohash, 1, "$name SD_WS_Maverick: UNDEFINED sensor $model";
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
  
  # Den SensorState bei Inaktivität zurücksetzen lassen durch Timer 
  my $inactivityinterval=int(AttrVal($name,"inactivityinterval",360));
  if ($sensor_1_state ne "unknown") {
    $hash->{sensor_1_state}=$sensor_1_state;
    RemoveInternalTimer($hash, 'SD_WS_Maverick_SetSensor1Inaktiv');
    InternalTimer(time()+($inactivityinterval), 'SD_WS_Maverick_SetSensor1Inaktiv', $hash, 0);
  }
  if ( $sensor_2_state ne "unknown") {
    $hash->{sensor_2_state}=$sensor_2_state;
    RemoveInternalTimer($hash, 'SD_WS_Maverick_SetSensor2Inaktiv');
    InternalTimer(time()+($inactivityinterval), 'SD_WS_Maverick_SetSensor2Inaktiv', $hash, 0);
  }
  
  # Checksum auswerten
  $checksum_str =~ tr/569A/0123/;
  my $checksum="";
  $checksum=$checksum_str; 
  # TODO: Die eigentliche Checksum errechnen. Diese ändert sich bei jedem Temperaturwechsel
  # TODO: Evtl. ist in den checksum-bits auch noch eine Info zur Batterie enthalten
  #       ggf. ist es möglich die checksum als ID zu verwenden und so mehrere Mavericks in fhem einbinden zu können.
  $hash->{checksum}=$checksum;
  $hash->{temp_food}=$temp_food if ($temp_food ne"");
  $hash->{temp_bbq}=$temp_bbq if ($temp_bbq ne"");
  $hash->{messageType}=$messageType;
  
  # TODO: Logging kann entfernt werden, wenn checksum entschlüsselt ist. Wird zur Analyse verwendet.
  Log3 $hash, 4, "$name statistic: checksum=$checksum, t1=$temp_str1, temp-food=$temp_food, t2_$temp_str2, temp-bbq=$temp_bbq;";
  
  SD_WS_Maverick_updateReadings($hash);

  return $name;

}

sub SD_WS_Maverick_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash = $defs{$name};
  if($cmd eq "set") {
    if($attr_name eq "IODev") {
      # Make possible to use the same code for different logical devices when they
      # are received through different physical devices.
      my $iohash = $defs{$attr_value};
      my $cde = $hash->{CODE};
      delete($modules{SD_WS_Maverick}{defptr}{$cde});
      $modules{SD_WS_Maverick}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
    }
    elsif($attr_name eq "inactivityinterval") {
      if (!looks_like_number($attr_value) || int($attr_value) < 60 || int($attr_value) > 3600) {
          return "$name: Value \"$attr_value\" is not allowed.\n"
                 ."inactivityinterval must be a number between 60 and 3600."
      }
    }
  }
  return undef;
}

sub SD_WS_Maverick_SetSensor1Inaktiv($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $hash, 5, "$name SD_WS_Maverick_SetSensor1Inaktiv";
  
  $hash->{sensor_1_state}="inactiv";
  SD_WS_Maverick_updateReadings($hash);
}

sub SD_WS_Maverick_SetSensor2Inaktiv($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $hash, 5, "$name SD_WS_Maverick_SetSensor2Inaktiv";

  $hash->{sensor_2_state}="inactiv";
  SD_WS_Maverick_updateReadings($hash);
}

sub SD_WS_Maverick_updateReadings($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $hash, 5, "$name SD_WS_Maverick_updateReadings";
  
  readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "temp-food", $hash->{temp_food});
    readingsBulkUpdate($hash, "temp-bbq", $hash->{temp_bbq});
    readingsBulkUpdate($hash, "messageType ", $hash->{messageType});
    readingsBulkUpdate($hash, "checksum", $hash->{checksum});
    readingsBulkUpdate($hash, "Sensor-1-food_state", $hash->{sensor_1_state});
    readingsBulkUpdate($hash, "Sensor-2-bbq_state", $hash->{sensor_2_state});
  readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  return undef;
}

1;


=pod
=item summary    Supports maverick temperature sensors protocl 47 from SIGNALduino
=item summary_DE Unterst&uumltzt Maverick Temperatursensoren mit Protokol 47 vom SIGNALduino
=begin html

<a name="SD_WS_Maverick"></a>
<h3>BBQ Sensors protocol #47</h3>
<ul>
  The SD_WS_Maverick module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>Maverick 732/733</li>
  </ul>
  <br>
  New received device will be added in fhem with autocreate (if autocreate is globally enabled).
  <br><br>

  <a name="SD_WS_Maverick_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  Maverick generates a random ID each time turned on. So it is not possible to link the hardware with the fhem-device. 
  The consequence is, that only one Maverick can be defined in fhem.
  </ul>
  <br>
  <a name="SD_WS_Maverick Events"></a>
  <b>Generated readings:</b>
  <ul>
  	 <li>State (Food: BBQ: )</li>
     <li>temp-food (&deg;C)</li>
     <li>temp-bbq (&deg;C)</li>
     <li>Sensor-1-food_state (connected, disconnected or inactiv)</li>
     <li>Sensor-2-bbq_state (connected, disconnected or inactiv)</li>
     <li>messageType (sync at startup or resync, otherwise normal)</li>
     <li>checksum (experimental)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li>inactivityinterval <seconds (60-3600)><br>
    The Interval to set Sensor-1-food_state and/or Sensor-2-bbq_state to inactiv after defined minutes. This can help to detect empty batteries or the malfunction of a tempertature-sensor.<br> 
    <code>default: 360</code></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore </a></li>
    <li><a href="#showtime">showtime (see FHEMWEB)</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS_Maverick_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Maverick_Parse"></a>
  <b>Parse</b> <ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="SD_WS_Maverick"></a>
<h3>BBQ Sensors protocol #47</h3>
<ul>
  Das SD_WS_Maverick Module verarbeitet von einem IO Geraet (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b>
  <ul>
    <li>Maverick 732/733</li>
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt (sofern autocreate in global aktiv ist).
  <br><br>

  <a name="SD_WS_Maverick_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Da das Maverick bei jedem Start eine neue zufällige ID erzeugt kann das Ger&aumlt nicht mit dem fhem-device gekoppelt werden. 
  Das bedeutet, dass es nicht m&oumlglich ist in fhem zwei Mavericks parallel zu betreiben.
  </ul>
  <br>
  <a name="SD_WS_Maverick Events"></a>
  <b>Generierte Readings:</b>
  <ul>
  	 <li>State (Food: BBQ: )</li>
     <li>temp-food (&deg;C)</li>
     <li>temp-bbq (&deg;C)</li>
     <li>Sensor-1-food_state (connected, disconnected oder inactiv)</li>
     <li>Sensor-2-bbq_state (connected, disconnected oder inactiv)</li>
     <li>messageType (sync bei Start oder resync, sonst normal)</li>
     <li>checksum (experimentell)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li>inactivityinterval <Sekunden (60-3600)><br>
    Das Interval nach dem Sensor-1-food_state und/oder Sensor-2-bbq_state auf inactiv gesetzt werden, wenn keine Signale mehr empfangen werden.
    Hilfreich zum erkennen einer leeren Batterie oder eines defekten Termperaturf&uumlhlers.<br> 
    <code>default: 360</code></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS_Maverick1_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Maverick_Parse"></a>
  <b>Parse</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut
