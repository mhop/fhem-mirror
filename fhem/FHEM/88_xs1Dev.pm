#################################################################
# $Id$
#################################################################
# logisches Modul - einzelnes Gerät, über das mit physikalisches
#					Modul kommuniziert werden kann
#
# note / ToDo´s:
# 
# 
#
#
#################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;				
use warnings;					# Warnings
use POSIX;
use Time::Local;
use SetExtensions;


sub xs1Dev_Initialize($) {
	my ($hash) = @_;
	
	$hash->{Match}			= 	"[x][s][1][D][e][v][_][A][k][t][o][r]_[0-6][0-9].*|[x][s][1][D][e][v][_][S][e][n][s][o][r]_[0-6][0-9].*";				## zum testen - https://regex101.com/
	
	$hash->{DefFn}			=	"xs1Dev_Define";
	$hash->{AttrFn}			= 	"xs1Dev_Attr";
	$hash->{ParseFn}		= 	"xs1Dev_Parse";
	$hash->{SetFn}			=	"xs1Dev_Set";
	$hash->{UndefFn}		=	"xs1Dev_Undef";
	$hash->{AttrList}		=	"debug:0,1 ".
								"IODev ".
								"useSetExtensions:0,1 ".
								$readingFnAttributes;

	$hash->{AutoCreate}	= { "xs1Dev_Sensor_.*" => { GPLOT => "temp4hum4:Temp/Hum,", FILTER=>"%NAME",  } };
	
}

sub xs1Dev_Define($$) {
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);

   			#				0		1	  2		3
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong number of arguments" if( @arg != 4 );
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong ID, must be 1-64" if ( $arg[3] <1 || $arg[3] >64);
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong Typ, must be A or S" if ( $arg[2] ne "A" && $arg[2] ne "S");

	splice( @arg, 1, 1 );
	my $iodev;
	my $i = 0;

	######## bisher unbenutzt - Schleife wo IODev= gefiltert wird aus define
	foreach my $param ( @arg ) {
        if( $param =~ m/IODev=([^\s]*)/ ) {
				$iodev = $1;
            splice( @arg, $i, 3 );
            last;
        }
        $i++;
	}
	########################################################################

	my $name = $hash->{NAME};							## Der Definitionsname, mit dem das Gerät angelegt wurde.
	my $typ = $hash->{TYPE};							## Der Modulname, mit welchem die Definition angelegt wurde.
   
	#Log3 $name, 3, "$typ: Define arguments 0:$arg[0] | 1:$arg[1] | 2:$arg[2]";

	# Parameter Define
	my $xs1_ID = $arg[2];			## Zusatzparameter 1 bei Define - ggf. nur in Sub
	my $xs1_typ1 = $arg[1];			## A || S
	
	my $Device = $xs1_typ1.$xs1_ID;						## A02 || S05
	my $Device_count = 0;
	my $Device_exist;
	
	### Check A02 || S05 bereits definiert
	foreach my $d (sort keys %defs) {
		if(defined($defs{$d}) && defined($defs{$d}{ID}) && $defs{$d}{ID} eq $Device) {
			$Device_count++;
			$Device_exist = $d;
			Log3 $name, 3, "$typ: $d $Device_count";
      }
	}
	
	return "The xs1 <ID> $Device is already definded: $Device_exist" if ($Device_count != 0);

	$hash->{ID} = $xs1_typ1.$xs1_ID;						## A02 || S05
	$modules{xs1Dev}{defptr}{$xs1_typ1.$xs1_ID} = $hash;	## !!! Adresse rückwärts dem Hash zuordnen (für ParseFn)

	my $debug = AttrVal($hash->{NAME},"debug",0);
	AttrVal($hash->{NAME},"useSetExtensions",0);
	
	$hash->{STATE}			= "Defined";					## Der Status des Modules nach Initialisierung.
	$hash->{TIME}			= time();						## Zeitstempel, derzeit vom anlegen des Moduls
	$hash->{VERSION}		= "1.12";						## Version
	
	$hash->{xs1_name}		= "undefined";					## Aktor | Sensor Name welcher def. im xs1
	$hash->{xs1_typ}		= "undefined";					## xs1_Typ switch | hygrometer | temperature ...
	
	if ($xs1_typ1 eq "A"){
		$hash->{xs1_function1}	= "undefined";				## xs1_Funktion zugeordnete Funktion 1
		$hash->{xs1_function2}	= "undefined";				## xs1_Funktion zugeordnete Funktion 2
		$hash->{xs1_function3}	= "undefined";				## xs1_Funktion zugeordnete Funktion 3
		$hash->{xs1_function4}	= "undefined";				## xs1_Funktion zugeordnete Funktion 4
	}

	# Attribut gesetzt
	$attr{$name}{room}				= "xs1"	if( not defined( $attr{$name}{room} ) );
	
	AssignIoPort($hash,$iodev) if( !$hash->{IODev} );		## sucht nach einem passenden IO-Gerät (physikalische Definition)

	# if(defined($hash->{IODev}->{NAME})) {
        #Log3 $name, 5, "xs1Dev: $name - I/O device is " . $hash->{IODev}->{NAME};
    # } else {
		  #Log3 $name, 3, "xs1Dev: $name - no I/O device";
    # }

	# if(defined($hash->{IODev}->{xs1_ip})) {				## IP von xs1Bridge - Device aus HASH
        # $hash->{xs1_ip} = $hash->{IODev}->{xs1_ip};
	# }
	return undef;
}

sub xs1Dev_Attr()
{
	my ($cmd,$name,$attrName,$attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	Debug " $name: Attr | Attributes $attrName = $attrValue" if($debug);
}

sub xs1Dev_Set ($$@)
{
	my ( $hash, $name, @args ) = @_;
	my $xs1_ID = $hash->{ID};
	#my $name = $hash->{NAME};
	my $cmd = $args[0];
	
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $xs1_typ = $hash->{xs1_typ};
	my $Aktor_ID = substr($xs1_ID,1,2);			## A01 zu 01
	my $cmd2;											## notwendig für Switch Funktionsplatz xs1
	
	return "no set value specified" if(int(@args) < 1);
	
	if ($xs1_typ ne "temperature" && $xs1_typ ne "hygrometer") {
		my @xs1_function =();		## Funktionen in ARRAY schreiben
		push (@xs1_function, $hash->{xs1_function1});
		push (@xs1_function, $hash->{xs1_function2});
		push (@xs1_function, $hash->{xs1_function3});
		push (@xs1_function, $hash->{xs1_function4});

		my $cmdList = "";
		my $cmdListNew = "";
		my $SetExtensionsReady = 0;
		
		foreach (@xs1_function) {			## cmdList aus ARRAY xs1_function zusammenstellen
			($cmdList)=split(/;/);
			$cmdListNew .= " ".$cmdList if ($cmdList ne "-");
			$SetExtensionsReady++ if ($cmdList eq "on" || $cmdList eq "off");
		}
	
		Debug " -------------- ERROR CHECK - START --------------" if($debug);
		
		$cmdList = $cmdListNew if($xs1_typ eq "switch" || $xs1_typ eq "dimmer");
		#$cmdList .= "dim:slider,0,6.25,100 dimup dimdown" if ($xs1_typ eq "dimmer");
		my $cmdFound = index($cmdListNew, $cmd);	## check cmd in cmdListNew
	
		Debug " $name: Set | SetExtensionsReady=$SetExtensionsReady cmdList=$cmdList" if($debug);
	
		if ($cmdList ne "") {			## Set nur bei definierten Typ
			if(AttrVal($name,"useSetExtensions",undef) || AttrVal($name,"useSetExtensions","0" && $SetExtensionsReady > 0)) {
				$cmd =~ s/([.?*])/\\$1/g;
				if($cmdList !~ m/\b$cmd\b/) {
					unshift @args, $name;
					return SetExtensions($hash, $cmdList, @args);
				}
				SetExtensionsCancel($hash);
			} else {
				if($xs1_typ eq "switch") {	############## Funktion switch ##############
					Debug " $name: Set | xs1_function 1=$xs1_function[0] 2=$xs1_function[1] 3=$xs1_function[2] 4=$xs1_function[3]" if($debug);
					if ($cmdFound >= 0) {	## cmdFound in welchem Funktionsplatz xs1
						for my $i (0 .. 3) {
							if ($xs1_function[$i] eq $cmd) {
								$cmd2 = "function=".($i+1);
								Debug " $name: Set | cmd=$cmd cmd2=$cmd2 on xs1_function place".($i+1) if($debug);
							}
						}
					}
					return "Wrong set argument, choose one of $cmdList" if($cmdFound < 0);
				} elsif ($xs1_typ eq "dimmer") { 	############## Funktion dimmer ##############

					Debug " $name: Set | xs1_typ=$xs1_typ cmd=$cmd" if ( not defined ($args[0]) );
					Debug " $name: Set | xs1_typ=$xs1_typ cmd=$cmd args0=".$args[0] if ( defined ($args[0]) && $cmd ne "?");
	
					#return "Unknown argument ?, choose one of $cmdList" if($args[0] eq "?");			### geht - ALT
					return SetExtensions($hash, $cmdList, $name, $cmd, @args);							### TEST - NEU

					if($cmd eq "dim") {			## dim
						return "Please value between 0 to 100" if($args[0] !~ /^([0-9]{1,2}+$|^[1][0][0]$|[0-9]{1,2}\.[0-9]{1}$)/);	# 0-100 mit einer Kommastelle
		
						$cmd = $cmd.sprintf("%02d", $args[0])."%" if ($args[0] >= 1 && $args[0] <= 9);
						$cmd = $cmd.$args[0]."%" if (length $args[0] != 1);
						$cmd = "off" if ($args[0] == 0);				## dim00% als off
					} elsif ($cmd eq "dimup" || $cmd eq "dimdown") {	## dimup + dimdown
			
						if (defined $args[0]) {
							if ($args[0] >= 0 && $args[0] <= 100) {
								$cmd = $cmd." ".$args[0];
							} else {
								return "value not in range | 0-100";
							}
						} else {						## OLD - NEW State auslesen einbauen mit ReadVal - XS! Kontrollieren !!!
							my $oldState = ReadingsVal($name, "state" , "unknown");
							(my $TempState) = $oldState =~ /[0-9]{1,2}/g ;
							my $newState;
				
							if ($cmd eq "dimdown" && $TempState >= 1) {
								$newState = $TempState - 1 ;
							} elsif ($cmd eq "dimdown" && $TempState <= 99) {
								$newState = $TempState + 1 if ($cmd eq "dimup");
							}

							$cmd = $cmd." $newState";
						}
					
					#} elsif ($cmd eq "dim_down") { # Umsetzung "anderer Befehl"
					
					#} elsif ($cmd eq "dim_up") {  # Umsetzung "anderer Befehl"
					
					}
					
				} elsif ($xs1_typ ne "dimmer" && $xs1_typ ne "switch" && $xs1_typ ne "undefined") {		## alles außer Dimmer || Switch
					Log3 $name, 2, "$name: Set | xs1_typ=$xs1_typ are not supported (loop not dimmer & switch)";
					return "xs1_typ=$xs1_typ are not supported (loop not dimmer & switch)";
				}
			}
		}
	
		if(defined($hash->{IODev}->{NAME})) {
			Debug " $name: Set | xs1_ID=$xs1_ID xs1_typ=$xs1_typ cmd=$cmd cmd2=$cmd2" if($debug && $xs1_typ ne "temperature" && $xs1_typ ne "hygrometer");
			if ($xs1_typ eq "switch" || $xs1_typ eq "dimmer") {
				IOWrite($hash, $xs1_ID, $xs1_typ, $cmd, $cmd2);
				
				readingsSingleUpdate($hash, "state", $cmd , 1);			
			}
		} else {
			return "no IODev define. Please define xs1Bridge.";
		}

		Debug " $name: Set | xs1_ID=$xs1_ID xs1_typ=$xs1_typ" if($debug);
		Debug " -------------- ERROR CHECK - END --------------" if($debug);
	}
	
	return undef;
}

sub xs1Dev_Parse($$)				## Input Bridge
{
	my ( $io_hash, $data) = @_;		## $io_hash = ezControl -> def. Name von xs1Bridge

	my ($xs1Dev,$xs1_readingsname,$xs1_ID,$xs1_typ2,$xs1_value,$xs1_f1,$xs1_f2,$xs1_f3,$xs1_f4,$xs1_name) = split("#", $data);
	my $xs1_typ1 = substr($xs1_readingsname,0,1);		## A || S

	my $def = $modules{xs1Dev}{defptr}{$xs1_typ1.$xs1_ID};
	$def = $modules{xs1Dev}{defptr}{$xs1_typ1.$xs1_ID} if(!$def);		## {xs1Dev}{defptr}{A02}
	
	my $hash = $def;
	$hash->{xs1_typ} = $xs1_typ2;
	$hash->{xs1_name} = $xs1_name;

	my $name = $hash->{NAME};			## xs1Dev_Aktor_01
	my $typ = $hash->{TYPE};			## xs1Dev
	$typ = "xs1Dev" if (!$def);			## Erstanlegung
	
	###### Define and values update ######
	#Log3 $typ, 3, "$io_hash: Parse | Data: $xs1Dev | $xs1_readingsname | $xs1_ID | $xs1_typ2 | $xs1_value | $xs1_typ1" if (!$def);

	if(!$def) {
			# "UNDEFINED xs1Dev_Aktor_12 xs1Dev A 12"
			Log3 $name, 3, "$typ: Unknown device ".$xs1Dev."_".$xs1_readingsname."_"."$xs1_ID $xs1_ID $xs1_typ1, please define it";
			return "UNDEFINED xs1Dev"."_".$xs1_readingsname."_"."$xs1_ID xs1Dev $xs1_typ1 $xs1_ID";
	} else {
		#Log3 $name, 3, "$typ: device $xs1_readingsname"."_"."$xs1_ID xs1_value:$xs1_value xs1_typ2:$xs1_typ2";
		
		AssignIoPort($hash, $io_hash);			## sucht nach einem passenden IO-Gerät (physikalische Definition)
		
		if ($xs1_readingsname eq "Aktor") {		## zugeordnete xs1_Funktionen
			$hash->{xs1_function1} = $xs1_f1;
			$hash->{xs1_function2} = $xs1_f2;
			$hash->{xs1_function3} = $xs1_f3;
			$hash->{xs1_function4} = $xs1_f4;
		}
		
		if ($xs1_typ2 eq "switch") {				# switch on | off mod for FHEM Default
			if ($xs1_value == 0) { $xs1_value = "off"; }
				elsif ($xs1_value == 100) { $xs1_value = "on"; }
			readingsSingleUpdate($hash, "state", $xs1_value ,1);	# Aktor | Sensor Update value
			
			## RegEx devStateIcon da Symbole nicht gleich benannt -> dim_up | dim_down
			if ($hash->{xs1_function1} eq "dim_up" || $hash->{xs1_function2} eq "dim_up" || $hash->{xs1_function3} eq "dim_up" || $hash->{xs1_function4} eq "dim_up" || 
				$hash->{xs1_function1} eq "dim_down" || $hash->{xs1_function2} eq "dim_down" || $hash->{xs1_function3} eq "dim_down" || $hash->{xs1_function4} eq "dim_down" ) {
				$attr{$name}{devStateIcon} = "dim_up:dimup dim_down:dimdown" if( not defined( $attr{$name}{devStateIcon} ) );
			}
			
		} elsif ($xs1_typ2 eq "temperature") {		# temperature typ
			my $xs1_value_new = "T: ".$xs1_value;	# temperature mod for FHEM Default

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $xs1_value_new);
			readingsBulkUpdate($hash, "temperature", $xs1_value);
			readingsEndUpdate($hash, 1);
		} elsif ($xs1_typ2 eq "hygrometer") {		# hygrometer typ
			my $xs1_value_new = "H: ".$xs1_value;	# hygrometer mod for FHEM Default

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $xs1_value_new);
			readingsBulkUpdate($hash, "humidity", $xs1_value);
			readingsEndUpdate($hash, 1);
		} elsif ($xs1_typ2 eq "dimmer") {			# dimmer
			
			## RegEx devStateIcon da Symbole nicht durchweg von 0 - 100 | dim_up | dim_down
			$attr{$name}{devStateIcon} = 	"dim0[1-6]\\D%:dim06% dim[7-9]\\D|dim[1][0-2]%:dim12% dim[1][3-8]%:dim18% \n"
											."dim[1][9]|dim[2][0-5]%:dim25% dim[2][6-9]|dim[3][0-1]%:dim31% dim[3][2-7]%:dim37% \n"
											."dim[3][8-9]|dim[4][0-3]%:dim43% dim[4][4-9]|dim[5][0]%:dim50% dim[5][1-6]%:dim56% \n"
											."dim[5][7-9]|dim[6][0-2]%:dim62% dim[6][3-8]%:dim68% dim[6][9]|dim[7][0-5]%:dim75% \n"
											."dim[7][6-9]|dim[8][0-1]%:dim81% dim[8][2-7]%:dim87% dim[8][8-9]|dim[9][0-3]%:dim93% \n"
											."dim[9][4-9]|dim[1][0][0]%:dim100% dim[_][u][p]:dimup dim[_][d][o]:dimdown" if( not defined( $attr{$name}{devStateIcon} ) );

			if ($xs1_value ne "0.0") {
			$xs1_value = "dim".sprintf("%02d", $xs1_value)."%";
			} elsif ($xs1_value eq "0.0") {
			$xs1_value = "off";
			}
			
			readingsSingleUpdate($hash, "state", $xs1_value ,1);
		}
	}
	
	return $name;
}

sub xs1Dev_Undef($$)    
{                     
	my ( $hash, $name) = @_;
	my $typ = $hash->{TYPE};
	
	delete($modules{xs1Dev}{defptr}{$hash->{ID}});
	Log3 $name, 3, "$typ: Device with Name $name delete";
	return undef;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item summary    Control of the devices which defined in xs1
=item summary_DE Steuerung des Ger&auml;te welche im xs1 definiert sind
=begin html

<a name="xs1Dev"></a>
<h3>xs1Dev</h3>
<ul>
	This module works with the xs1Bridge module. (The <code>xs1_control</code> attribute in the xs1Bridge module must be set to 1!) <br>
	It communicates with this and creates all actuators of the xs1 as a device in FHEM. So you can control the actuators of the xs1 from the FHEM. <br><br>
	The module was developed based on the firmware version v4-Beta of the xs1. There may be errors due to different adjustments within the manufacturer's firmware.
	<br><br>

	<a name="xs1Dev_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Dev &lt;Typ&gt; &lt;ID&gt;</code>
		<br><br>

		It is not possible to create the module without specifying type and ID of xs1.
			<ul>
			<li><code>&lt;ID&gt;</code> is internal id in xs1.</li>
			</ul>
			<ul>
			<li><code>&lt;Typ&gt;</code> is the abbreviation A for actuators or S for sensors.</li>
			</ul><br>
		example:
		<ul>
		define xs1Dev_Aktor_02 xs1Dev A 02
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul><code>set &lt;name&gt; &lt;value&gt; </code></ul><br>
	in which <code>value</code> one of the following values:<br>
	<ul><code>
      dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%<br>
      dimdown<br>
      dimup<br>
      dimupdown<br>
      off<br>
      off-for-timer<br>
      on<br>
      on-for-timer<br>
    </code></ul><br>
	<b>Get</b><br>
	<ul>N/A</ul><br>
	<a name="xs1_attr"></a>
	<b>Attributes</b>
	<ul>
		<li>debug (0,1)<br>
		This brings the module into a very detailed debug output in the logfile. Thus, program parts can be controlled and errors can be checked.<br>
		(Default, debug 0)
		</li>
		<li>useSetExtensions (0,1)<br>
		Toggles the SetExtensions on or off.<br>
		(Default, useSetExtensions 0)
		</li>
	</ul><br>
	<b>Explanation:</b>
	<ul>
		<li>abstract Internals:</li>
		<ul>
		xs1_function(1-4): defined function in the device<br>
		xs1_name: defined name in the device<br>
		xs1_typ: defined type in the device<br>
		</ul>
	</ul>
</ul>
=end html
=begin html_DE

<a name="xs1Dev"></a>
<h3>xs1Dev</h3>
<ul>
	Dieses Modul arbeitet mit dem Modul xs1Bridge zusammen. (Das Attribut <code>xs1_control</code> im Modul xs1Bridge muss auf 1 gestellt sein!) <br>
	Es kommuniziert mit diesem und legt sämtliche Aktoren des xs1 als Device im FHEM an. So kann man vom FHEM aus, die Aktoren der xs1 steuern.
	<br><br>
	Das Modul wurde entwickelt basierend auf dem Firmwarestand v4-Beta des xs1. Es kann aufgrund von unterschiedlichen Anpassungen innerhalb der Firmware des Herstellers zu Fehlern kommen.
	<br><br>

	<a name="xs1Dev_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Dev &lt;Typ&gt; &lt;ID&gt;</code>
		<br><br>

		Ein anlegen des Modules ohne Angabe des Typ und der ID vom xs1 ist nicht möglich.
			<ul>
			<li><code>&lt;ID&gt;</code> ist interne ID im xs1.</li>
			</ul>
			<ul>
			<li><code>&lt;Typ&gt;</code> ist der Kürzel A für Aktoren oder S für Sensoren.</li>
			</ul><br>
		Beispiel:
		<ul>
		define xs1Dev_Aktor_02 xs1Dev A 02
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul><code>set &lt;name&gt; &lt;value&gt; </code></ul><br>
	Wobei <code>value</code> einer der folgenden Werte sein kann:<br>
	<ul><code>
      dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%<br>
      dimdown<br>
      dimup<br>
      dimupdown<br>
      off<br>
      off-for-timer<br>
      on<br>
      on-for-timer<br>
    </code></ul><br>
	<b>Get</b><br>
	<ul>N/A</ul><br>
	<a name="xs1_attr"></a>
	<b>Attribute</b>
	<ul>
		<li>debug (0,1)<br>
		Dies bringt das Modul in eine sehr ausf&uuml;hrliche Debug-Ausgabe im Logfile. Somit lassen sich Programmteile kontrollieren und Fehler &uuml;berpr&uuml;fen.<br>
		(Default, debug 0)
		</li>
		<li>useSetExtensions (0,1)<br>
		Schaltet die SetExtensions ein bzw. aus.<br>
		(Default, useSetExtensions 0)
		</li>
	</ul><br>
	<b>Erl&auml;uterung:</b>
	<ul>
		<li>Auszug Internals:</li>
		<ul>
		xs1_function(1-4): definierte Funktion im Ger&auml;t<br>
		xs1_name: definierter Name im Ger&auml;t<br>
		xs1_typ: definierter Typ im Ger&auml;t<br>
		</ul>
	</ul>
</ul>
=end html_DE
=cut
