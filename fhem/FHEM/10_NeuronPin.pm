##############################################
# $Id$
# todo:

package main;

use strict;
use warnings;
use SetExtensions;
use Encode qw(decode encode);

my %sets = (
	'on' => 1,
	'off' => 0,
);

my %rsets = reverse %sets;

sub NeuronPin_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}			= 'NeuronPin_Define';
	$hash->{InitFn}		 	= 'NeuronPin_Init';
	$hash->{StateFn}		= 'NeuronPin_State';
	$hash->{AttrFn}			= 'NeuronPin_Attr';
	$hash->{SetFn}	 		= 'NeuronPin_Set';
	$hash->{GetFn}			= 'NeuronPin_Get';
	$hash->{UndefFn}		= 'NeuronPin_Undef';
	$hash->{AttrList}		= 'IODev do_not_notify:0,1 showtime:0,1 '.
					  'disable:0,1 disabledForIntervals '.
					  'poll_interval:1,2,5,10,20,30 restoreOnStartup:on,off,last '.
					  'aomax skipreadings ownsets autoalias '.
								$readingFnAttributes;
	$hash->{Match}			= ".*";
	$hash->{ParseFn}		= "NeuronPin_Parse";
#	$hash->{DbLog_splitFn} 	= "NeuronPin_DbLog_splitFn";
	$hash->{AutoCreate} 	= {"NeuronPin_.*"  => { ATTR   => "room:Neuron" } };
	$hash->{noAutocreatedFilelog} = 1;
}

sub NeuronPin_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	if (scalar(@a) == 4) {
		#altes Define (enthält noch nicht den Namen vom IODev), untauglich für mehrere Neurons
		$modules{NeuronPin}{defptr}{$a[2]." ".$a[3]} = $hash;
		#Log3 $hash, 1, "$hash->{TYPE} ($hash->{NAME}) Define: $a[2] $a[3]";
		my @EVOKS = devspec2array("TYPE=Neuron");
		if (scalar(@EVOKS) == 1) {
			Log3 ($hash, 1, "$hash->{TYPE} ($hash->{NAME}) one Neuron Device defined. Try to correct define." );
			$hash->{DEF} = $hash->{DEF} . " " . $EVOKS[0];
			$modules{NeuronPin}{defptr}{$a[2]." ".$a[3]." ".$EVOKS[0]} = $hash;
		} elsif (scalar(@EVOKS) >> 1) {
			Log3 ($hash, 0, "$hash->{TYPE} ($hash->{NAME}) more than one Neuron Device defined. Unable to autocorrect define." );
			$modules{NeuronPin}{defptr}{$a[2]." ".$a[3]} = $hash;
		}	
	} elsif (scalar(@a) == 5) {
		$modules{NeuronPin}{defptr}{$a[2]." ".$a[3]." ".$a[4]} = $hash;
	} else {
		return "Define: Wrong syntax. Usage:\n" .
         	   "define <name> NeuronPin <dev> <circuit> <Neuron IODev>";
	}
	AssignIoPort($hash, AttrVal($hash->{NAME},"IODev", (split " ", $hash->{DEF})[2] ) );	
	#return "$hash->{NAME} Pintype not valid" unless ($a[2] =~ /^(input|relay|ai|ao|led|temp|wd)$/ );
	$hash->{DEV} = $a[2];
	$hash->{CIRCUIT} = $a[3];
	$hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { NeuronPin_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return NeuronPin_Catch($@) if $@;
  }
  return undef;
}

sub NeuronPin_Init($$) {
	my ( $hash, $args ) = @_;
	unless (defined $args && int(@$args) >= 2)	{
  		return "Define: Wrong syntax. Usage:\n" .
         	   "define <name> NeuronPin <dev> <circuit> <Neuron IODev>";
 	}
	if (ReadingsVal($hash->{NAME}, '.conf', '')) {
		NeuronPin_CreateSets($hash);
		if (AttrVal($hash->{NAME},"restoreOnStartup",'')) {
			my $val = ReadingsVal($hash->{NAME},'state','off');
			Log3 $hash, 5, "$hash->{TYPE} ($hash->{NAME}): im init restoreOnStartup = $val";
			NeuronPin_Set($hash,$hash->{NAME}, (looks_like_number($val) ? dim $val : $val));
		}
	} else {
		return if(IsDisabled($hash->{NAME}));
		#IOWrite($hash, split " ", $hash->{DEF});
		IOWrite($hash, $hash->{DEV}, $hash->{CIRCUIT});
	}
	$hash->{STATE} = ReadingsVal($hash->{NAME},'state','') if ReadingsVal($hash->{NAME},'state','');
	return undef;
}

sub NeuronPin_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub NeuronPin_State($$$$) {	#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	#Log3 $hash, 5, "$hash->{TYPE} ($hash->{NAME}): $sname kann auf $sval wiederhergestellt werden $tim";
	if ( $sname ne "STATE" && (my $pval = AttrVal($hash->{NAME},"restoreOnStartup",'')) && $hash->{DEV} =~ /relay|ao/ ) {
		if ($sname eq "state") {
			if ($pval eq 'on' || $pval eq 'off' || looks_like_number($pval)) {
				readingsSingleUpdate($hash, "state", $pval, 1);
				Log3 $hash, 5, "$hash->{TYPE} ($hash->{NAME}): $sname wiederhergestellt auf $pval";
			} else {
				$hash->{READINGS}{$sname}{VAL} = $sval;
				$hash->{READINGS}{$sname}{TIME} = $tim;
				Log3 $hash, 5, "$hash->{TYPE} ($hash->{NAME}): $sname wiederhergestellt auf $sval";
			}
		}
	}
	return;
}

sub NeuronPin_Parse ($$) {
	my ( $io_hash, $message) = @_;	
	my $port = $message->{dev}." ".$message->{circuit};
	
	Log3 (undef, 4, "NeuronPin_Parse von $io_hash->{NAME} empfangen: " . encode_json $message);
	if (my $hash = $modules{NeuronPin}{defptr}{$port}) {
		foreach my $dev (devspec2array("TYPE=Neuron")) {
			Log3 (undef, 1, "NeuronPin_Parse Neuron Device gefunden: " . InternalVal($dev,"NAME","") );
		 }
	}
	if (my $hash = $modules{NeuronPin}{defptr}{$port ." ". $io_hash->{NAME}}) {
		NeuronPin_TransferVals ($hash, $message);
	} elsif (my $hash = $modules{NeuronPin}{defptr}{$port}) {
		Log3 (undef, 1, "NeuronPin_Parse from $io_hash->{NAME} to $hash->{NAME} : incomplete Define");	
		NeuronPin_TransferVals ($hash, $message);
	} 	else {
		Log3 ($hash, 4, "NeuronPin_Parse von $io_hash->{NAME} nothing found...create logical device");
		return "UNDEFINED $io_hash->{NAME}_".$message->{dev}."_".$message->{circuit}." NeuronPin " . $port . " " . $io_hash->{NAME};
	}
}

sub NeuronPin_TransferVals ($$) {
my ( $hash, $message) = @_;
	my @skipreadings = split(',', AttrVal($hash->{NAME}, 'skipreadings', "relay_type,typ,dev,circuit,glob_dev_id,pending") );
	my @uichreadings = split(',', "mode,unit,range,address,address,name");
	# zusätzliche Daten als Internal
	$hash->{RELAY_TYPE} = 	$message->{relay_type} 	if $message->{relay_type};
	$hash->{TYP} = 			$message->{typ} 		if defined $message->{typ};
	$hash->{GLOB_DEV_ID} = 	$message->{glob_dev_id} if defined $message->{glob_dev_id};
	my $value = $message->{value};
	my $basequantity = "";
	my $unit = defined $message->{unit} ? encode("UTF-8", " " . $message->{unit}) : "";
	if ($message->{dev} eq 'input' || $message->{dev} eq 'relay' || $message->{dev} eq 'led') {
		$value = $rsets{$value}
	} else {
		#$value = sprintf('%.2f', $value);	#nur 2 Nachkommastellen
		#$value =~ s/\.(?:|.*[^0]\K)0*\z//;	#keine 0 am Ende nach dem Komma
		#$value =~ s/^-0$/0/;				#kein -0
		$value = round($value,2);
		if ($message->{mode}) {
			$basequantity = lc($message->{mode});
		} elsif ( $message->{dev} eq 'temp' ) {
			$basequantity = "temperature";
			$unit = " °C";
		} elsif ( $message->{dev} eq 'unit_register' ) {
			$basequantity = $message->{name};
		}
	}
	
#	$value = $rsets{$value} if ($message->{dev} eq 'input' || $message->{dev} eq 'relay' || $message->{dev} eq 'led');
#	unless ( $value == 0 || $value == 1 ) {
#		$value = sprintf('%.2f', $value); 
#		$value =~ s/\.(?:|.*[^0]\K)0*\z//;
#		$value =~ s/^-0$/0/;
#	}

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"state", $value . $unit );
	readingsBulkUpdate($hash,"dim",$value) if $message->{dev} eq 'ao';

	foreach (keys %{$hash->{READINGS}}) {
		#next if substr($_,0,2) eq "Z_";
		readingsDelete($hash, $_) unless exists($message->{$_}) || $_ eq "state" || $_ eq ".conf" || $_ eq "dim";
	}
	foreach my $key (keys %$message){
		if (ref $message->{$key} eq 'ARRAY') {		# alle Arrays überspringen
		} elsif (grep( /^$key/, @skipreadings )) {	# Wer soll nicht als reading angelegt werden
			readingsDelete($hash, $key);
		} elsif ($key eq 'alias') {					# al_ am Anfang von alias weg
			my @aliases = (split '_', $message->{$key});
			my $alias = join(" ",@aliases[1 .. $#aliases]);
			readingsBulkUpdate($hash,$key,$alias);
			# autocreate alias attribute
			if (AttrVal($hash->{NAME}, 'alias', '?') ne $alias && defined AttrVal($hash->{NAME}, 'autoalias', '')) {
			   my $msg = CommandAttr(undef, $hash->{NAME} . " alias $alias");
			   Log3 ($hash, 2, "$hash->{TYPE} ($hash->{NAME}): Error creating alias $msg") if ($msg);
			}
		 } else {
		 	if (grep( /^$key/, @uichreadings )) {
				readingsBulkUpdateIfChanged($hash,$key,encode("UTF-8",$message->{$key}));
			} else {
				readingsBulkUpdate($hash,$key,$message->{$key});
			}
		}
	}
	readingsBulkUpdate($hash, $basequantity, $message->{value} . $unit ) if $basequantity;
	delete $message->{value};
	readingsBulkUpdateIfChanged($hash,".conf",encode_json $message,0);
	readingsEndUpdate($hash,1);

	NeuronPin_CreateSets($hash);

	if ($hash->{HELPER}{SETREQ} && not $hash->{IODev}->{HELPER}{WESOCKETS}) {		# workaround because neuron sends old value after set
		RemoveInternalTimer($hash,'NeuronPin_RereadPin');
		InternalTimer(gettimeofday() + 1, 'NeuronPin_RereadPin', $hash);
		delete $hash->{HELPER}{SETREQ};
	}
	asyncOutput($hash->{HELPER}{CL}, encode_json $message) if $hash->{HELPER}{CL};	# show conf after get
	delete $hash->{HELPER}{CL};
	return $hash->{NAME}; 
}

sub NeuronPin_RereadPin($) {
	my ($hash) =  @_;
	return if(IsDisabled($hash->{NAME}));
	IOWrite($hash, $hash->{DEV}, $hash->{CIRCUIT});
}

sub NeuronPin_Attr (@) {
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				NeuronPin_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
		};
		return NeuronPin_Catch($@) if $@;
	} elsif ($attr eq 'poll_interval') {
		if ( defined($val) ) {
			if ( looks_like_number($val) && $val > 0) {
				RemoveInternalTimer($hash);
				NeuronPin_Poll($hash)
			} else {
			$msg = "$hash->{TYPE} ($hash->{NAME}): Wrong poll intervall defined. poll_interval must be a number > 0";
			}
		} else {
			RemoveInternalTimer($hash);
		}
	}
	return ($msg) ? $msg : undef;
}

sub NeuronPin_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	NeuronPin_Get($hash, $name, 'refresh');
	my $pollInterval = AttrVal($name, 'poll_interval', 0);
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'NeuronPin_Poll', $hash, 0) if ($pollInterval > 0);
}

sub NeuronPin_CreateSets($) {
	my ($hash) = @_;
	my $result;
	eval {
			$result = JSON->new->utf8(1)->decode(ReadingsVal($hash->{NAME}, '.conf', 'nix'));
	};
	if ($@) {
		Log3 ($hash, 3, "$hash->{TYPE} ($hash->{NAME}) reading .conf is no JSON: $@");
	} else {
		eval {
			delete $hash->{HELPER}{SETS};
			foreach my $key (keys %$result){
				if (ref $result->{$key} eq 'ARRAY') {									# wenn Array dann zur set->Dropdonwmenüerzeugung verwenden
					if ( exists($result->{substr($key,0,-1)}) ) {						# z.B. zu "modes":["Simple","PWM"] passt "mode":"Simple"
						if ($result->{$key} && scalar keys @{$result->{$key}} > 1) {	# und mehr als eine Option verfügbar
							foreach (@{$result->{$key}}){
								$hash->{HELPER}{SETS}{substr($key,0,-1)}{$_} = 1;
							}
						}
					} elsif (exists($result->{(split "_", $key)[0]})) {					# z.B. "range_modes":["10.0","1.0"]
						if ($result->{$key} && scalar keys @{$result->{$key}} > 1) {	# und mehr als eine Option verfügbar
							foreach (@{$result->{$key}}){
								$hash->{HELPER}{SETS}{(split "_", $key)[0]}{$_} = 1;
							}
						}						
					} else {
						Log3 ($hash, 5, "NeuronPin_CreateSets unbekanntes Array: $key");
					}
				}
			}
			
			my @freesets = split(';', AttrVal($hash->{NAME}, 'ownsets', "debounce;counter;interval;pwm_freq;pwm_duty:slider,0,0.1,100") );
			foreach (@freesets) {
				my $args = (defined((split ':', $_)[1]) ? (split ':', $_)[1] : "free");
				my $setname = (split ':', $_)[0];
				$hash->{HELPER}{SETS}{$setname} = $args if exists($result->{$setname});
				#$hash->{HELPER}{SETS}{$_} = "free" if exists($result->{$_});
			}
			#$hash->{HELPER}{SETS}{pwm_duty} = "slider,0,0.1,100" if exists($result->{pwm_duty});
			$hash->{HELPER}{SETS}{alias} 	= "free";
			
			if ($hash->{DEV} eq 'led' || $hash->{DEV} eq 'relay') {
				$hash->{HELPER}{SETS}{on} = "noArg";
				$hash->{HELPER}{SETS}{off} = "noArg";
			} elsif ($hash->{DEV} eq 'ao') {
				$hash->{HELPER}{SETS}{on} = "noArg";
				$hash->{HELPER}{SETS}{off} = "noArg";
				$hash->{HELPER}{SETS}{dim} = "slider,0,0.1," . AttrVal($hash->{NAME},"aomax",'10');
			}

			my $str = join(" ", map { "$_".( 	ref($hash->{HELPER}{SETS}{$_}) eq 'HASH' ? 
												':' . join (",", sort keys %{$hash->{HELPER}{SETS}{$_}} ) : 
												($hash->{HELPER}{SETS}{$_} eq "free" ? '' : ':'.$hash->{HELPER}{SETS}{$_})) 
									} keys %{$hash->{HELPER}{SETS}}
						  );
			$hash->{HELPER}{SET} = $str;
		};
		if ($@) {
			Log3 ($hash, 1, "$hash->{TYPE} ($hash->{NAME}) Sortierung fehlgeschlagen:\n$@");
		}	
	}
	return undef
}

sub NeuronPin_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd = $a[1];
	my $arg = $a[2];
	
	my @arguments = ($hash->{DEV}, $hash->{CIRCUIT});
	
	if(!defined($hash->{HELPER}{SETS}{$cmd})) {
		if (my $setlist = $hash->{HELPER}{SET}) {
			return SetExtensions($hash, $setlist, @a) ;
		}
		return undef
	} elsif ($cmd eq "dim") {
		$arguments[2] = $arg;
		$hash->{HELPER}{SETREQ} = 1;
	} elsif ( $hash->{HELPER}{SETS}{$cmd} eq "noArg") {
		$arguments[2] = $sets{$cmd};
		if ($hash->{DEV} eq 'ao') {
			if ($cmd eq 'on') {
				$arguments[2] = AttrVal($hash->{NAME},"aomax",'10');
			} elsif ($arguments[2] eq 'off') {
				$arguments[2] = "0";
			}
		}
		$hash->{HELPER}{SETREQ} = 1;
	} elsif ($cmd eq "alias") {
		$arguments[2] = $cmd;
		$arguments[3] = "al_".$arg;
	} else {
		$arguments[2] = $cmd;
		$arguments[3] = $arg;
	}
	return if(IsDisabled($hash->{NAME}));
	IOWrite($hash, @arguments);
}

sub NeuronPin_Get($@) {
	my ($hash, $name, $cmd, @args) = @_;
	my @arguments = ($hash->{DEV}, $hash->{CIRCUIT});
	if ($cmd && $cmd eq "refresh") {
		return if(IsDisabled($hash->{NAME}));
		IOWrite($hash, @arguments);
	} elsif ($cmd && $cmd eq "config") {
		$hash->{HELPER}{CL} = $hash->{CL};
		return if(IsDisabled($hash->{NAME}));
		IOWrite($hash, @arguments);
	} else {
		return 'Unknown argument ' . $cmd . ', choose one of refresh:noArg config:noArg'
	}
}

sub NeuronPin_Undef($$) {
	my ($hash, $arg) = @_;
	my $def = $hash->{DEF};
	RemoveInternalTimer($hash);
	delete $modules{NeuronPin}{defptr}{$hash->{DEF}};
	return undef;
}

sub NeuronPin_DbLog_splitFn($) {
	my ($event) = @_;
	Log3 undef, 5, "in NeuronPin DbLog_splitFn empfangen: $event"; 
	my ($reading, $value, $unit) = "";
	my @parts = split(/ /,$event);
	$reading = shift @parts;
	$reading =~ tr/://d;
	$unit = ''; # ReadingsVal($hash->{NAME},'unit','');
	if ($reading eq "value" && $unit) {
		$value = $parts[0];
		Log3 undef, 3, "in NeuronPin DbLog_splitFn empfangen: $event, return: |$reading|$value|$unit|";
		return ($reading, $value, $unit);
	}
}

1;

=pod
=item device
=item summary Logical Module for subdevices of EVOK driven devices.
=item summary_DE Logisches Modul f&uuml; Subdevices von Ger&auml;ten auf denen EVOK l&auml;uft.
=begin html

<a name="NeuronPin"></a>
<h3>NeuronPin</h3>
<ul>
	<a name="NeuronPin"></a>
		Logical Module for EVOK driven devices.
		Defines will be automatically created by the <a href="#Neuron"> Neuron</a> module.
		<br>
	<a name="NeuronPinDefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> NeuronPin &lt;dev&gt; &lt;circuit&gt; &lt;Neuron IODev&gt;</code><br><br>
		&lt;dev&gt; is an device type like input, ai (analog input), relay (digital output) etc.<br>
		&lt;circuit&gt; is the number of the device.<br>
		&lt;Neuron IODev&gt; is the EVOK device where this subdevice is connected
		<br><br>
		
    Example:
    <pre>
      define  NeuronPin_relay_2_01 NeuronPin relay 2_01 Neuron1
    </pre>
  </ul>

  <a name="NeuronPinSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> can be e.g.:<br>
    <ul><li>for relay
      <ul><code>
        off<br>
        on<br>	
        </code>
        The <a href="#setExtensions"> set extensions</a> are also supported for output devices.<br>
	  </ul>
      </li>
	</ul>
	Other set values depending on the options of the device function.
	Details can be found in the UniPi Evok documentation.
  </ul><br>

  <a name="NeuronPinGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
	where <code>value</code> can be<br>
	<ul>
		<li>refresh: uptates all readings</li>
		<li>config: returns the configuration JSON</li>
	</ul>
  </ul><br>

  <a name="NeuronPinAttr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="poll_interval">poll_interval</a><br>
      Set the polling interval in minutes to query all readings<br>
      Default: -<br>
	  valid values: decimal number<br><br>
    </li>
    <li><a name="restoreOnStartup">restoreOnStartup</a><br>
      Restore Readings and sets after reboot<br>
      Default: last<br>
	  valid values: last, on, off, no<br><br>
    </li>
    <li><a name="aomax">aomax</a><br>
      Maximum value for the slider from the analog output ports<br>
      Default: 10<br>
	  valid values: decimal number<br><br>
    </li>
	<li><a name="skipreadings">skipreadings</a><br>
      Values which will be sent from the Device and which shall not be listed as readings<br>
      Default: relay_type,typ,dev,circuit,glob_dev_id,value,pending<br>
	  valid values: comma separated list<br><br>
    </li>
	<li><a name="ownsets">ownsets</a><br>
      Values which will be sent from the Device which can be changed via set. For Values for where the device sends fixed choices, the sets will created automatically<br>
      Default: debounce;counter;interval;pwm_freq;pwm_duty:slider,0,0.1,100<br>
	  valid values: semicolon separated list<br><br>
    </li>
	<li><a name="autoalias">autoalias</a><br>
      If set to 1, reading alias will automatically change the attribute "alias"<br>
      Default: 1<br>
	  valid values: 0,1<br><br>
    </li>
	<li><a href="#IODev">IODev</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul>
  <br>
</ul>
=end html

=begin html_DE

<a name="NeuronPin"></a>
<h3>NeuronPin</h3>
<ul>
	<a name="NeuronPin"></a>
		Logisches Modul f&uuml;r Ger&auml;te auf denen EVOK l&auml;uft.
		Diese werden automatisch vom <a href="#Neuron"> Neuron</a> Modul angelegt.
		<br>
	<a name="NeuronPinDefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> NeuronPin &lt;dev&gt; &lt;circuit&gt; &lt;Neuron IODev&gt;</code><br><br>
		&lt;dev&gt; ist der Typ des Subdevices/Pins z.B. input, ai (analoger Eingang), relay (digitaler Ausgang) etc.<br>
		&lt;circuit&gt; ist die Nummer des Subdevices/Pins.<br>
		&lt;Neuron IODev&gt; ist der Name des EVOK Devices zu dem dieses Subdevice geh&ouml;rt.
		<br><br>
		
    Beispiel:
    <pre>
      define  NeuronPin_relay_2_01 NeuronPin relay 2_01 Neuron1
    </pre>
  </ul>

  <a name="NeuronPinSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> can be e.g.:<br>
    <ul><li>f&uuml;r Subdevice Typ relay
      <ul><code>
        off<br>
        on<br>	
        </code>
      </ul>
      <a href="#setExtensions"> set extensions</a> werden f&uuml;r Ausg&auml;nge ebenso unterst&uuml;tzt.<br>
	  </li>
	</ul>
	Weitere set values sind abh&auml;ngig von den jeweiligen Subdevice Funktionen.
	Details dazu sind in der UniPi Evok Dokumentation zu finden.
  </ul><br>

  <a name="NeuronPinGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
	<code>value</code>:<br>
	<ul>
		<li>refresh: aktualisiert alle readings</li>
		<li>config: gibt das Konfigurations JSON zur&uuml;ck</li>
	</ul>
  </ul><br>

  <a name="NeuronPinAttr"></a>
  <b>Attribute</b>
  <ul>
    <li><a name="poll_interval">poll_interval</a><br>
      Interval in Minuten in dem alle Werte gelesen werden.<br>
      Standard: -<br>
	  g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li><a name="restoreOnStartup">restoreOnStartup</a><br>
      Readings nach Neustart wiederherstellen<br>
      Standard: last<br>
	  g&uuml;ltige Werte: last, on, off<br><br>
    </li>
    <li><a name="aomax">aomax</a><br>
      Maxwert f&uuml;r den Schieberegler beim Analogen Ausgang<br>
      Standard: 10<br>
	  g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
	<li><a name="skipreadings">skipreadings</a><br>
      Werte, die vom Ger&auml;t gesendet, aber nicht als Reading dargestellt werden sollen.<br>
      Standard: relay_type,typ,dev,circuit,glob_dev_id,value,pending<br>
	  g&uuml;ltige Werte: kommaseparierte Liste<br><br>
    </li>
	<li><a name="ownsets">ownsets</a><br>
      Werte, die vom Ger&auml;t gesendet, und &uuml;ber set ver&auml;ndert werden k&ouml;nnen. Schickt das Ger&auml;t feste Auswahllisten f&uuml;r einen Wert dann werden die sets automatisch angelegt.<br>
      Standard: debounce;counter;interval;pwm_freq;pwm_duty:slider,0,0.1,100<br>
	  g&uuml;ltige Werte: semikolonseparierte Liste<br><br>
    </li>
	<li><a name="autoalias">autoalias</a><br>
      Wenn auf 1 wird das reading alias automatisch als Attribut alias gesetzt.<br>
      Standard: 1<br>
	  g&uuml;ltige Werte: 0,1<br><br>
    </li>
	<li><a href="#IODev">IODev</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul>
  <br>
</ul>
=end html_DE

=cut
