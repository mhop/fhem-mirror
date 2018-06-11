##############################################
# $Id$
# todo:
# holen von status nach sets nicht wenn ws verbindung
# ao funktioniert nicht

package main;

use strict;
use warnings;

my %sets = (
	'on' => 1,
	'off' => 0,
);

my %rsets = reverse %sets;

sub NeuronPin_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    		= 'NeuronPin_Define';
	$hash->{InitFn}  	 	= 'NeuronPin_Init';
	$hash->{StateFn}        = "NeuronPin_State";
	$hash->{AttrFn}   		= 'NeuronPin_Attr';
	$hash->{SetFn}    		= 'NeuronPin_Set';
	$hash->{GetFn}    		= 'NeuronPin_Get';
	$hash->{UndefFn}  		= 'NeuronPin_Undef';
	$hash->{AttrList} 		= 'IODev do_not_notify:0,1 showtime:0,1 '.
							  'disable:0,1 disabledForIntervals'.
							  'poll_interval:1,2,5,10,20,30 restoreOnStartup:on,off,last '.
							  'aomax skipreadings ownsets autoalias '.
								$readingFnAttributes;
	$hash->{Match} 			= ".*";
	$hash->{ParseFn}   		= "NeuronPin_Parse";
#	$hash->{DbLog_splitFn} 	= "NeuronPin_DbLog_splitFn";
	$hash->{AutoCreate} 	= {"NeuronPin_.*"  => { ATTR   => "room:Neuron" } };
	$hash->{noAutocreatedFilelog} = 1;
}

sub NeuronPin_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
# hier fehlt noch Überprüfung der Attribute
	$modules{NeuronPin}{defptr}{$a[2]." ".$a[3]} = $hash;
	return "$hash->{NAME} Pintype not valid" unless ($a[2] =~ /^(input|relay|ai|ao|led|temp|wd)$/ );
	$hash->{DEV} = $a[2];
	#return "$hash->{NAME} Circuit Name not valid" unless ($a[3] =~ /^[1-9]_((0[1-9])|[1-9][0-9])$/ );
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
	unless (defined $args && int(@$args) == 2)	{
  		return "Define: Wrong syntax. Usage:\n" .
         	   "define <name> NeuronPin <dev> <circuit>";
 	}
	AssignIoPort($hash);
	#$hash->{STATE} = 'Initialized';
	if (ReadingsVal($hash->{NAME}, '.conf', '')) {
		NeuronPin_CreateSets($hash);
		if (AttrVal($hash->{NAME},"restoreOnStartup",'')) {
			my $val = ReadingsVal($hash->{NAME},'state','off');
			Log3 $hash, 5, "$hash->{TYPE} ($hash->{NAME}): im init restoreOnStartup = $val";
			NeuronPin_Set($hash,$hash->{NAME}, (looks_like_number($val) ? dim $val : $val));
		}
	} else {
		return if(IsDisabled($hash->{NAME}));
		IOWrite($hash, split " ", $hash->{DEF});
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
	Log3 (undef, 4, "NeuronPin_Parse von $io_hash->{NAME} empfangen:\n" . encode_json $message);
	if (my $hash = $modules{NeuronPin}{defptr}{$port}) {
		my $value = $message->{value};
		# zusätzliche Daten als Internal
		$hash->{RELAY_TYPE} = 	$message->{relay_type} 	if $message->{relay_type};
		$hash->{TYP} = 			$message->{typ} 		if defined $message->{typ};
		$hash->{GLOB_DEV_ID} = 	$message->{glob_dev_id} if defined $message->{glob_dev_id};
		$value = $rsets{$value} if ($message->{dev} eq 'input' || $message->{dev} eq 'relay' || $message->{dev} eq 'led');
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"state",$value);
		readingsBulkUpdate($hash,"dim",$value) if $message->{dev} eq 'ao';
		
	#	my @readings = ("mode","unit","range","debounce","counter","counter_mode","alias","pwm_freq","pwm_duty","temp","humidity","vdd","vad");
	#	foreach (@readings){
	#		if (exists($message->{$_})) {
	#			readingsBulkUpdate($hash,"Z_".$_,$message->{$_});
	#		} else {
	#			readingsDelete($hash, "Z_".$_);
	#		}
	#	}

		my @skipreadings = split(',', AttrVal($hash->{NAME}, 'skipreadings', "relay_type,typ,dev,circuit,glob_dev_id,value,pending") );
		foreach (keys %{$hash->{READINGS}}) {
			#next if substr($_,0,2) eq "Z_";
			readingsDelete($hash, $_) unless exists($message->{$_}) || $_ eq "state" || $_ eq ".conf" || $_ eq "dim";
		}
		foreach my $key (keys %$message){
			if (ref $message->{$key} eq 'ARRAY') {		# alle Arrays überspringen
			} elsif (grep( /^$key/, @skipreadings )) {	# Wer soll nicht als reading angelegt werden
				readingsDelete($hash, $key);
			} elsif ($key eq 'alias') {					# al_ am Anfang von alias weg
				my $alias = (split '_', $message->{$key})[1];
				readingsBulkUpdate($hash,$key,$alias);
				# autocreate alias attribute
				if (AttrVal($hash->{NAME}, 'alias', '?') ne $alias && defined AttrVal($hash->{NAME}, 'autoalias', '')) {
				   my $msg = CommandAttr(undef, $hash->{NAME} . " alias $alias");
				   Log3 ($hash, 2, "$hash->{TYPE} ($hash->{NAME}): Error creating alias $msg") if ($msg);
				}
			 }else {
				readingsBulkUpdate($hash,$key,$message->{$key});
			}
		}
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
	} 	else {
		Log3 ($hash, 4, "NeuronPin_Parse von $io_hash->{NAME} nix gefunden...anlegen");
		return "UNDEFINED NeuronPin_".$message->{dev}."_".$message->{circuit}." NeuronPin " . $port;
	}
}

sub NeuronPin_RereadPin($) {
	my ($hash) =  @_;
	return if(IsDisabled($hash->{NAME}));
	IOWrite( $hash, split(" ", $hash->{DEF}) );
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
		#	my @stypes = ("modes","range_modes","counter_modes");
		#	my @stype = ("mode","range_mode","counter_mode");
		#	foreach my $i (0 .. $#stypes) {
		#		if ($result->{$stypes[$i]} && scalar keys @{$result->{$stypes[$i]}} > 1) {
		#			foreach (@{$result->{$stypes[$i]}}){
		#				$hash->{HELPER}{SETS}{$stype[$i]}{$_} = 1;
		#			}
		#		}
		#	}
			
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
	
	my @arguments = (split(" ",$hash->{DEF}));
	
	#if(!defined($sets{$cmd})) {
	if(!defined($hash->{HELPER}{SETS}{$cmd})) {
		if (my $setlist = $hash->{HELPER}{SET}) {
			return SetExtensions($hash, $setlist, @a) ;
			#return 'Unknown argument ' . $cmd . ', choose one of ' . $setlist; 
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
	#$hash->{HELPER}{SETREQ} = 1;
	#my @arguments = (split(" ",$hash->{DEF}),$sets{$cmd});
	return if(IsDisabled($hash->{NAME}));
	IOWrite($hash, @arguments);
}

sub NeuronPin_Get($@) {
	my ($hash, $name, $cmd, @args) = @_;
	if ($cmd && $cmd eq "refresh") {
		my @arguments = (split " ", $hash->{DEF});
		return if(IsDisabled($hash->{NAME}));
		IOWrite($hash, @arguments);
	} elsif ($cmd && $cmd eq "config") {
		my @arguments = (split " ", $hash->{DEF});
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

#sub NeuronPin_DbLog_splitFn($) {
#	my ($event) = @_;
#	Log3 undef, 5, "in DbLog_splitFn empfangen: $event"; 
#	my ($reading, $value, $unit) = "";
#	my @parts = split(/ /,$event);
#	$reading = shift @parts;
#	$reading =~ tr/://d;
#	$value = $parts[0];
#	$unit = "V" if(lc($reading) =~ m/spannung/);
#	return ($reading, $value, $unit);
#}

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
		<code>define <name> NeuronPin &lt;dev&gt; &lt;circuit&gt;</code><br><br>
		&lt;dev&gt; is an device type like input, ai (analog input), relay (digital output) etc.<br>
		&lt;circuit&gt; ist the number of the device.
		<br><br>
		
    Example:
    <pre>
      define  NeuronPin_relay_2_01 NeuronPin relay 2_01
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
  </ul>

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
    <li>poll_interval<br>
      Set the polling interval in minutes to query all readings<br>
      Default: -, valid values: decimal number<br><br>
    </li>
    <li>restoreOnStartup<br>
      Restore Readings and sets after reboot<br>
      Default: last, valid values: last, on, off, no<br><br>
    </li>
    <li>aomax<br>
      Maximum value for the slider from the analog output ports<br>
      Default: 10, valid values: decimal number<br><br>
    </li>
	<li>skipreadings<br>
      Values which will be sent from the Device and which shall not be listed as readings<br>
      Default: relay_type,typ,dev,circuit,glob_dev_id,value,pending; valid values: comma separated list<br><br>
    </li>
	<li>ownsets<br>
      Values which will be sent from the Device which can be changed via set. For Values for where the device sends fixed choices, the sets will created automatically<br>
      Default: debounce;counter;interval;pwm_freq;pwm_duty:slider,0,0.1,100 valid values: semicolon separated list<br><br>
    </li>
	<li>autoalias<br>
      If set to 1, reading alias will automatically change the attribute "alias"<br>
      Default: 0, valid values: 0,1<br><br>
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
		Logisches Modul f&uuml; Ger&auml;te auf denen EVOK l&auml;uft.
		Diese werden automatisch vom <a href="#Neuron"> Neuron</a> Modul angelegt.
		<br>
	<a name="NeuronPinDefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> NeuronPin &lt;dev&gt; &lt;circuit&gt;</code><br><br>
		&lt;dev&gt; ist der Typ des Subdevices/Pins z.B. input, ai (analoger Eingang), relay (digitaler Ausgang) etc.<br>
		&lt;circuit&gt; ist die Nummer des Subdevices/Pins.
		<br><br>
		
    Beispiel:
    <pre>
      define  NeuronPin_relay_2_01 NeuronPin relay 2_01
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
  </ul>

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
    <li>poll_interval<br>
      Interval in Minuten in dem alle Werte gelesen werden.<br>
      Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>restoreOnStartup<br>
      Readings nach Neustart wiederherstellen<br>
      Standard: last, g&uuml;ltige Werte: last, on, off<br><br>
    </li>
    <li>aomax<br>
      Maxwert f&uuml;r den Schieberegler beim Analogen Ausgang<br>
      Standard: 10, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
	<li>skipreadings<br>
      Werte, die vom Ger&auml;t gesendet, aber nicht als Reading dargestellt werden sollen.<br>
      Standard: relay_type,typ,dev,circuit,glob_dev_id,value,pending; g&uuml;ltige Werte: kommaseparierte Liste<br><br>
    </li>
	<li>ownsets<br>
      Werte, die vom Ger&auml;t gesendet, und &uuml;ber set ver&auml;ndert werden k&ouml;nnen. Schickt das Ger&auml;t feste Auswahllisten f&uuml;r einen Wert dann werden die sets automatisch angelegt.<br>
      Standard: debounce;counter;interval;pwm_freq;pwm_duty:slider,0,0.1,100; g&uuml;ltige Werte: semikolonseparierte Liste<br><br>
    </li>
	<li>autoalias<br>
      Wenn auf 1 wird das reading alias automatisch als Attribut alias gesetzt.<br>
      Standard: 0, g&uuml;ltige Werte: 0,1<br><br>
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
