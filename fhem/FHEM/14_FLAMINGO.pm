#################################################################
# $Id$
#################################################################
# The module was taken over by an unknown maintainer!
# It is part of the SIGNALduinos project.
# https://github.com/RFD-FHEM/RFFHEM/tree/dev-r33
# 
# 2018 - HomeAuto_User & elektron-bbs
#################################################################
# FLAMINGO FA20RF
# get sduino_dummy raw MU;;P0=-1384;;P1=815;;P2=-2725;;P3=-20001;;P4=8159;;P5=-891;;D=01010121212121010101210101345101210101210101212101010101012121212101010121010134510121010121010121210101010101212121210101012101013451012101012101012121010101010121212121010101210101345101210101210101212101010101012121212101010121010134510121010121010121;;CP=1;;O;;
# FLAMINGO FA21RF
# get sduino_dummy raw MS;;P0=-1413;;P1=757;;P2=-2779;;P3=-16079;;P4=8093;;P5=-954;;D=1345121210101212101210101012121012121210121210101010;;CP=1;;SP=3;;R=33;;O;;
# FLAMINGO FA22RF
# get sduino_dummy raw MU;;P0=-5684;;P1=8149;;P2=-887;;P3=798;;P4=-1393;;P5=-2746;;P6=-19956;;D=0123434353534353434343434343435343534343534353534353612343435353435343434343434343534353434353435353435361234343535343534343434343434353435343435343535343536123434353534353434343434343435343534343534353534353612343435353435343434343434343534353434353435;;CP=3;;R=0;;
# LM-101LD
# get sduino_dummy raw MS;;P1=-2708;;P2=796;;P3=-1387;;P4=-8477;;P5=8136;;P6=-904;;D=2456212321212323232321212121212121212123212321212121;;CP=2;;SP=4;;
#################################################################
# note / ToDo´s / Bugs:
# - 
#################################################################

package main;

use strict;
use warnings;


my %sets = (
	"Testalarm:noArg",
	"Counterreset:noArg",
);

my %models = (
	"FA20RF",
	"FA21RF",
	"FA22RF",
	"KD-101LA",
	"LM-101LD",
	"unknown",
);


#####################################
sub
FLAMINGO_Initialize($)
{
  my ($hash) = @_;
  
  $hash->{Match}     = "^P13\.?1?#[A-Fa-f0-9]+";
  $hash->{SetFn}     = "FLAMINGO_Set";
  $hash->{DefFn}     = "FLAMINGO_Define";
  $hash->{UndefFn}   = "FLAMINGO_Undef";
  $hash->{ParseFn}   = "FLAMINGO_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 ignore:0,1 ".
						"model:".join(",", sort %models)." " .
						"room:FLAMINGO ".
						$readingFnAttributes;
   $hash->{AutoCreate}=
    { 
		"FLAMINGO.*" => { ATTR => "event-on-change-reading:.* event-min-interval:.*:300 room:FLAMINGO", FILTER => "%NAME", GPLOT => ""},
    };
}

#####################################
sub FLAMINGO_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	# Argument					    0      1       2       3         4
	return "wrong syntax: define <name> FLAMINGO <code> <model> <optional IODev>" if(int(@a) < 3 || int(@a) > 5);
	### check code ###
	return "wrong hex value: ".$a[2] if not ($a[2] =~ /^[0-9a-fA-F]{6}$/m);
	### check model ###
	return "wrong model: ".$a[3] . "\n\n(allowed modelvalues: " . join(" | ", sort %models).")" if $a[3] && ( !grep { $_ eq $a[3] } %models );
	
	$hash->{CODE} = $a[2];
	$hash->{lastMSG} =  "no data";
	$hash->{bitMSG} =  "no data";

	$modules{FLAMINGO}{defptr}{$a[2]} = $hash;
	$hash->{STATE} = "Defined";

	my $name= $hash->{NAME};
	my $iodev = $a[3] if($a[3]);
	$iodev = $modules{FLAMINGO}{defptr}{ioname} if (exists $modules{FLAMINGO}{defptr}{ioname} && not $iodev);

	### Attributes ###
	if ( $init_done == 1 ) {
		$attr{$name}{model}	= $a[3] if $a[3];
		$attr{$name}{model}	= "unknown" if not $a[3];
		
		$attr{$name}{room}	= "FLAMINGO";
		#$attr{$name}{stateFormat} = "{ReadingsVal($name, "state", "")." | ".ReadingsTimestamp($name, "state", "")}";
	}
	
	AssignIoPort($hash,$iodev);		## sucht nach einem passenden IO-Gerät (physikalische Definition)

	return undef;
}

#####################################
sub FLAMINGO_Undef($$) {
  my ($hash, $name) = @_;

  RemoveInternalTimer($hash, "FLAMINGO_UpdateState");
  delete($modules{FLAMINGO}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  delete($modules{FLAMINGO}{defptr}{testrunning}) if exists ($modules{FLAMINGO}{defptr}{testrunning});
  return undef;
}

#####################################
sub FLAMINGO_Set($$@) {
	my ( $hash, $name, @args ) = @_;

	my $ret = undef;
	my $message;
	my $list;
	my $model = AttrVal($name, "model", "unknown");
	my $iodev = $hash->{IODev}{NAME};
	
	$list = join (" ", %sets);
	return "ERROR: wrong command! (only $list)"  if ($args[0] ne "?" && $args[0] ne "Testalarm" && $args[0] ne "Counterreset");
	
	if ($args[0] eq "?") {
		if ($model eq "unknown") {
			$ret = "";		# no set if model unknown or no model attribut
		} else {
			$ret = $list;
		}
	}
	
	my $hlen = length($hash->{CODE});
	my $blen = $hlen * 4;
	my $bitData= unpack("B$blen", pack("H$hlen", $hash->{CODE}));
	
	my $bitAdd = substr($bitData,23,1);							# for last bit, is needed to send
	
	## use the protocol ID how receive last message
	my $sendID = ReadingsVal($name, "lastReceive_ID", "");		# for send command, because ID´s can vary / MU / MS message
	
	$message = "P".$sendID."#".$bitData.$bitAdd."P#R55";

	## Send Message to IODev and wait for correct answer	
	Log3 $hash, 3, "FLAMINGO set $name $args[0]" if ($args[0] ne "?");
	Log3 $hash, 4, "$iodev: FLAMINGO send raw Message: $message" if ($args[0] eq "Testalarm");

	## Counterreset ##
	if ($args[0] eq "Counterreset") {
		readingsSingleUpdate($hash, "alarmcounter", 0, 1);
	}

	## Testarlarm ##	
	if ($args[0] ne "?" and $args[0] ne "Counterreset") {

		# remove InternalTimer
		RemoveInternalTimer($hash, "FLAMINGO_UpdateState");
		
		$modules{FLAMINGO}{defptr}{testrunning} = "yes";						# marker, device send Testalarm to NOT register this alarm with other receivers in FHEM
		Log3 $hash, 4, "FLAMINGO set marker TESTALARM is running";
		
		readingsSingleUpdate($hash, "state", "Testalarm", 1);
		IOWrite($hash, 'sendMsg', $message);
		
		InternalTimer(gettimeofday()+15, "FLAMINGO_UpdateState", $hash, 0);		# set timer to Update status
	}
  
	return $ret;
}

#####################################
sub FLAMINGO_Parse($$) {
 	my ($iohash, $msg) = @_;
	#my $name = $iohash->{NAME};
	my ($protocol,$rawData) = split("#",$msg);
	$protocol=~ s/^[P](\d+)/$1/; # extract protocol

	my $iodev = $iohash->{NAME};
	$modules{FLAMINGO}{defptr}{ioname} = $iodev;	

	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData= unpack("B$blen", pack("H$hlen", $rawData));

	my $deviceCode = $rawData;  	# Message is in hex "4d4efd"
	
	my $def = $modules{FLAMINGO}{defptr}{$deviceCode};
	$def = $modules{FLAMINGO}{defptr}{$deviceCode} if(!$def);
	my $hash = $def;

	#my $model = AttrVal($name, "model", "unknown");
	
	if(!$def) {
		Log3 $iohash, 1, "FLAMINGO UNDEFINED sensor detected, code $deviceCode, protocol $protocol";
		return "UNDEFINED FLAMINGO_$deviceCode FLAMINGO $deviceCode";
	}
  
	my $name = $hash->{NAME};
	return "" if(IsIgnored($name));
	
	$hash->{bitMSG} = $bitData;
	$hash->{lastMSG} = $rawData;
	$hash->{lastReceive} = time();
	
	readingsSingleUpdate($hash, "lastReceive_ID", $protocol, 0);		# to save lastReceive_ID for send command
	
	## check if Testalarm received from a other transmitter in FHEM ##
	my $testalarmcheck = "";
	$testalarmcheck = $modules{FLAMINGO}{defptr}{testrunning} if exists ($modules{FLAMINGO}{defptr}{testrunning});
	
	if ($testalarmcheck eq "yes") {
		return "";
	}
	
	my $alarmcounter = ReadingsVal($name, "alarmcounter", 0);
	
	if (ReadingsVal($name, "state", "") ne "Alarm") {
		$alarmcounter = $alarmcounter+1;	
	}

	Log3 $name, 5, "$iodev: FLAMINGO actioncode: $deviceCode";
	Log3 $name, 4, "$iodev: FLAMINGO $name: is receiving Alarm (Counter $alarmcounter)";
	
	# remove InternalTimer
	RemoveInternalTimer($hash, "FLAMINGO_UpdateState");
	
 	readingsBeginUpdate($hash);
 	readingsBulkUpdate($hash, "state", "Alarm");
	readingsBulkUpdate($hash, "alarmcounter", $alarmcounter);				# register non testalarms how user can set via FHEM
	readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	InternalTimer(gettimeofday()+15, "FLAMINGO_UpdateState", $hash, 0);		# set timer to Update status
	
	return $name;
}

#####################################
sub FLAMINGO_UpdateState($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	readingsBeginUpdate($hash);
 	readingsBulkUpdate($hash, "state", "no Alarm");
	readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	## delete marker device Testalarm ##
	Log3 $hash, 4, "FLAMINGO delete marker TESTALARM was running" if exists ($modules{FLAMINGO}{defptr}{testrunning});
	delete($modules{FLAMINGO}{defptr}{testrunning}) if exists ($modules{FLAMINGO}{defptr}{testrunning});
	
	Log3 $name, 4, "FLAMINGO: $name: Alarm stopped";
}


1;

=pod
=item summary    Supports flamingo fa20rf/fa21 smoke detectors
=item summary_DE Unterst&uumltzt Flamingo FA20RF/FA21/FA22RF/LM-101LD Rauchmelder
=begin html

<a name="FLAMINGO"></a>
<h3>FLAMINGO</h3>
<ul>
  The FLAMINGO module interprets FLAMINGO FA20RF/FA21/FA22RF type of messages received by the SIGNALduino.<br>
  Of this smoke detector, there are identical types profitec KD101LA, POLLIN KD101LA or renkforce LM-101LD.
  <br><br>

  <a name="FLAMINGOdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FLAMINGO &lt;code&gt;</code> <br>

    <br>
    <li>&lt;code&gt; is the unic code of the autogenerated address of the FLAMINGO device. This changes, after pairing to the master</li>
	<li>&lt;model&gt; is the model name</li><br>
	- if autocreate, the defined model is <code>unknown</code>.<br>
	- with manual <code>define</code> you can choose the model which is available as attribute.
  </ul>
  <br><br>

  <a name="FLAMINGOset"></a>
  <b>Set</b>
  <ul>
  <li>Counterreset<br>
  - set alarmcounter to 0</li>
  <li>Testalarm<br>
  - trigger a test alarm (The testalarm does not increase the alarm ounter!)</li>
  </ul><br>

  <a name="FLAMINGOget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="FLAMINGOattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev (!)</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
	<a name="model"></a>
	<li>model<br>
	FA20RF, FA21RF, FA22RF, KD-101LA, LM-101LD, unknown</li>
    <a name="showtime"></a>
	<li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  <b><u>Generated readings</u></b><br>
  - alarmcounter | counter started with 0<br>
  - lastReceive_ID | the protocol ID from SIGNALduino<br>
  - state | (no Alarm, Alarm, Testalaram)<br>
  <br><br>
  <u><b>manual<br></b></u>
  <b>Pairing (Master-Slave)</b>  
  <ul>
    <li>Determine master<br>
  LEARN button push until the green LED lights on</li>
    <li>Determine slave<br>
  LEARN button push until the red LED lights on</li>
    <li>Master, hold down the TEST button until an alarm signal generated at all "Slaves"</li>
  </ul><br>
  <b>Standalone</b>
  <ul>
    <li>LEARN button push until the green LED lights on</li>
    <li>TEST button hold down until an alarm signal generated</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="FLAMINGO"></a>
<h3>FLAMINGO</h3>
<ul>
  Das FLAMINGO module dekodiert vom SIGNALduino empfangene Nachrichten des FLAMINGO FA20RF / FA21 / FA22RF Rauchmelders.<br>
  Von diesem Rauchmelder gibt es baugleiche Typen wie profitec KD101LA, POLLIN KD101LA oder renkforce LM-101LD.
  <br><br>

  <a name="FLAMINGOdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FLAMINGO &lt;code&gt;  &lt;model&gt; </code> <br>

    <br>
    <li>&lt;code&gt; ist der automatisch angelegte eindeutige code  des FLAMINGO Rauchmelders. Dieser &auml;ndern sich nach
	dem Pairing mit einem Master.</li>
	<li>&lt;model&gt; ist die Modelbezeichnung</li><br>
	- Bei einem Autocreate wird als Model <code>unknown</code> definiert.<br>
	- Bei einem manuellen <code>define</code> kann man das Model frei w&auml;hlen welche als Attribut verf&uuml;gbar sind .
  </ul>
  <br><br>

  <a name="FLAMINGOset"></a>
  <b>Set</b>
  <ul>
  <li>Counterreset<br>
  - Alarmz&auml;hler auf 0 setzen</li>
  <li>Testalarm<br>
  - ausl&ouml;sen eines Testalarmes. (Der Testalarm erh&ouml;ht nicht den Alarmz&auml;hler!)</li>
  </ul><br>

  <a name="FLAMINGOget"></a>
  <b>Get</b> <ul>N/A</ul><br><br>

  <a name="FLAMINGOattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev (!)</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
	<a name="model"></a>
	<li>model<br>
	FA20RF, FA21RF, FA22RF, KD-101LA, LM-101LD, unknown</li>
	<a name="showtime"></a>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  <b><u>Generierte Readings</u></b><br>
  - alarmcounter | Alarmz&auml;hler beginnend mit 0<br>
  - lastReceive_ID | Protokoll ID vom SIGNALduino<br>
  - state | (no Alarm, Alarm, Testalaram)<br>
  <br><br>
  <u><b>Anleitung<br></b></u>
  <b>Melder paaren (Master-Slave Prinzip)</b>
  <ul>
  <li>Master bestimmen<br>
  LEARN-Taste bis gr&uuml;ne Anzeige LED leuchtet</li>
  <li>Slave bestimmen<br>
  LEARN-Taste bis rote Anzeige LED leuchtet</li>
  <li>Master, TEST-Taste gedr&uuml;ckt halten, bevor LEDś abschalten und alles "Slaves" ein Alarmsignal erzeugen</li>
  </ul><br>
  <b>Paarung aufheben / Standalone Betrieb</b>
  <ul>
  <li>LEARN-Taste bis gr&uuml;ne Anzeige LED leuchtet</li>
  <li>TEST-Taste gedr&uuml;ckt halten bis ein Alarmsignal erzeugt wird</li>
  </ul>
</ul>

=end html_DE
=cut
