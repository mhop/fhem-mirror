#################################################################
# $Id$
#################################################################
# logisches Modul - einzelnes Gerät, über das mit physikalisches
#					Modul kommuniziert werden kann
# 
# note / ToDo´s:
# - PERL WARNING: Use of uninitialized value $_
# - PERL WARNING: Use of uninitialized value $cmdList in string
# - PERL WARNING: Use of uninitialized value $cmdList in concatenation
#################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;				
use warnings;					# Warnings
use POSIX;
use Time::Local;
#use SetExtensions;


sub xs1Dev_Initialize($) {
	my ($hash) = @_;

	$hash->{Match}			= 	"[x][s][1][D][e][v][_][A][k][t][o][r]_[0-6][0-9].*|[x][s][1][D][e][v][_][S][e][n][s][o][r]_[0-6][0-9].*";				## zum testen - https://regex101.com/
	$hash->{DefFn}			=	"xs1Dev_Define";
	$hash->{AttrFn}		= 	"xs1Dev_Attr";
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
	# $def --> Definition des Module
	# $hash --> ARRAY des Module
	
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);

							#-----0------1------2----3----4
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong number of arguments" if( @arg != 4);
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong ID, must be 1-64" if ( $arg[3] <1 || $arg[3] >64);
	return "Usage: define <NAME> xs1Dev <Typ> <ID>  |  wrong Typ, must be A or S" if ( $arg[2] ne "A" && $arg[2] ne "S");

	splice( @arg, 1, 1 );
	my $iodev;
	my $i = 0;

	############## !! ################ nicht genutzt derzeit ############# !! #################
	#### Schleife (Durchlauf der Argumente @arg) wo IODev= gefiltert wird aus define | Dispatch
	foreach my $param ( @arg ) {
		if( $param =~ m/IODev=([^\s]*)/ ) {
				$iodev = $1;
            splice( @arg, $i, 3 );
            last;
        }
        $i++;
	}
	###########################################################################################

	my $name = $hash->{NAME};							## Der Definitionsname, mit dem das Gerät angelegt wurde.
	my $typ = $hash->{TYPE};							## Der Modulname, mit welchem die Definition angelegt wurde.
   
	#Log3 $name, 3, "$typ: Define arguments 0:$arg[0] | 1:$arg[1] | 2:$arg[2] | 3:$arg[3]";

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
	#$hash->{VERSION}		= "1.17";						## Version
		
	$hash->{xs1_name}		= "undefined";					## Aktor | Sensor Name welcher def. im xs1
	$hash->{xs1_typ}		= "undefined";					## xs1_Typ switch | hygrometer | temperature ...
	
	if ($xs1_typ1 eq "A"){
		$hash->{xs1_function1}	= "undefined";			## xs1_Funktion zugeordnete Funktion 1
		$hash->{xs1_function2}	= "undefined";			## xs1_Funktion zugeordnete Funktion 2
		$hash->{xs1_function3}	= "undefined";			## xs1_Funktion zugeordnete Funktion 3
		$hash->{xs1_function4}	= "undefined";			## xs1_Funktion zugeordnete Funktion 4
	}

	# Attribut gesetzt
	$attr{$name}{room}			= "xs1"	if( not defined( $attr{$name}{room} ) );

	AssignIoPort($hash,$iodev) if( !$hash->{IODev} );		## sucht nach einem passenden IO-Gerät (physikalische Definition)

	# alles mit IODev erst NACH AssignIoPort nutzbar !!!
	$hash->{VERSION} = $hash->{IODev}->{VERSION};		## Version
	
	if(defined($hash->{IODev}->{NAME})) {
		Log3 $name, 4, "xs1Dev: $name - I/O Device is " . $hash->{IODev}->{NAME};
    } else {
		Log3 $name, 3, "xs1Dev: $name - no I/O Device, Please delete and restart FHEM.";
   }

	#$iodev = $hash->{IODev}->{NAME};

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
	
	#Debug " $name: Attr | Attributes $attrName = $attrValue" if($debug);
}

sub xs1Dev_Set ($$@)
{
	my ( $hash, $name, @args ) = @_;
	my $xs1_ID = $hash->{ID};
	my $typ = $hash->{TYPE};			## xs1Dev
	my $cmd = $args[0];
	
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $xs1_typ = $hash->{xs1_typ};
	my $Aktor_ID = substr($xs1_ID,1,2);			## A01 zu 01
	my $cmd2;											## notwendig für Switch Funktionsplatz xs1
	my $cmdFound;
	
	return "no set value specified" if(int(@args) < 1);
	my %xs1_function = ();	## Funktionen in ARRAY schreiben
	my %setList = ();		## Funktionen als Liste
	my %setListPos = ();	## Funktionen als Position|Funktion
	
	Debug " -------------- ERROR CHECK - START --------------" if($debug && $cmd ne "?");
	# http://192.168.2.5/control?callback=cname&cmd=set_state_actuator&number=7&function=1
	
	if (substr($xs1_ID,0,1) eq "A" && $xs1_typ ne "undefined") {		## nur bei Aktoren und nicht "undefined"
		for (my $d = 0; $d < 4; $d++) {
			if ($hash->{"xs1_function".($d+1)} ne "-") {
				if ($hash->{"xs1_function".($d+1)} eq "dim_up") {			## FHEM Mod xs1 dim_up -> FHEM dimup
					$xs1_function{"dimup:noArg"} = ($d+1);
				} elsif ($hash->{"xs1_function".($d+1)} eq "dim_down") {	## FHEM Mod xs1 dim_down -> FHEM dimdown
					$xs1_function{"dimdown:noArg"} = ($d+1);
				} elsif (exists $xs1_function{$hash->{"xs1_function".($d+1)}.":noArg"}){	## CHECK ob Funktion bereits exists
					$xs1_function{$hash->{"xs1_function".($d+1)}."_".($d+1).":noArg"} = ($d+1);
				} else {
					$xs1_function{$hash->{"xs1_function".($d+1)}.":noArg"} = ($d+1);		## xs1 Standardbezeichnung Funktion
				}
			}
		}
		
		if ($xs1_typ eq "dimmer"){ 		#bei dimmer Typ, dim hinzufügen FHEM
			$xs1_function{"dim"} = (5);
		}
		
		while ( (my $k,my $v) = each %xs1_function ) {
			if ($v > 0 && $v < 7) {
				$setListPos{$v."|".$k} = $k;
				#Debug " $name: Set | $k|$v" if($debug && $cmd ne "?");
			}
		}
	
		my $setList = join(" ", keys %xs1_function);
		my $setListAll = join(" ", keys %setListPos);
		
		my $cmdFound = index($setListAll, $cmd.":");	## check cmd in setListAll - Zuordnung Platz
		my $cmdFound2 = "";
		
		if ($cmdFound >= 0) {				#$cmd für Sendebefehl anpassen
			$cmdFound2 = substr($setListAll,$cmdFound-2,1);
			$cmd2 = "function=".$cmdFound2;
		} else {
			$cmd2 = $cmd.$args[1] if (defined $args[1]);
		}
		
		### dimmer - spezifisch dim hinzufügen FHEM + value Check
		if ($xs1_typ eq "dimmer" && $cmd eq "dim") {
			if (not defined $args[1]) {
				return "dim value arguments failed";
			} elsif ($args[1] !~ /[a-zA-Z]/ && $args[1] <= 1 || $args[1] !~ /[a-zA-Z]/ && $args[1] >= 99) {
				return "dim value must be 1 to 99";
			} elsif ($args[1] =~ /[a-zA-Z]/) {
				return "wrong dim value format! only value from 1 to 99";
			} else { 
				$cmd = $cmd.$args[1]."%";		## FHEM state mod --> anstatt nur dim --> dim47%
			}
		}

		Debug " $name: Set | xs1_typ=$xs1_typ cmd=$cmd setListAll=$setListAll cmdFound=$cmdFound cmdFound2=$cmdFound2" if($debug && $cmd ne "?");
	
		if(AttrVal($name,"useSetExtensions",undef) || AttrVal($name,"useSetExtensions","0")) {
			$cmd =~ s/([.?*])/\\$1/g;
			if($setList !~ m/\b$cmd\b/) {			
				Debug " $name: Set | useSetExtensions check" if($debug && $cmd ne "?");
				unshift @args, $name;
				return SetExtensions($hash, $setList, $name, @args);
			}
			SetExtensionsCancel($hash);
			} else {
				return "Unknown argument ?, choose one of $setList" if($args[0] eq "?");
			}

		#Debug " $name: Set | xs1_typ=$xs1_typ (after mod) cmd=$cmd" if($debug && $cmd ne "?");

		if(defined($hash->{IODev}->{NAME})) {
			if ($xs1_typ eq "switch" || $xs1_typ eq "dimmer" || $xs1_typ eq "shutter" || $xs1_typ eq "timerswitch" && $cmd ne "?") {
				Debug " $name: Set IOWrite | xs1_ID=$xs1_ID xs1_typ=$xs1_typ cmd=$cmd cmd2=$cmd2" if($debug && $xs1_typ ne "temperature" && $xs1_typ ne "hygrometer");
				#Log3 $name, 3, "$name: Set IOWrite | xs1_ID=$xs1_ID xs1_typ=$xs1_typ cmd=$cmd cmd2=$cmd2 IODev=$hash->{IODev}->{NAME}";
				Log3 $name, 3, "$typ set $name $cmd";
				
				IOWrite($hash, $xs1_ID, $xs1_typ, $cmd, $cmd2);
				readingsSingleUpdate($hash, "state", $cmd , 1);			
			}
			#else { 
			#Log3 $name, 2, "$name: Device NOT SUPPORTED for Dispatch. In xs1 disabled.";
			#}
		} else {
			return "no IODev define. Please define xs1Bridge.";
		}

		#Debug " $name: Set | xs1_ID=$xs1_ID xs1_typ=$xs1_typ" if($debug);
		Debug " -------------- ERROR CHECK - END --------------" if($debug);
	}

	return undef;
}
	
sub xs1Dev_Parse($$)				## Input Data from 88_xs1Bridge
{
	my ( $io_hash, $data) = @_;		## $io_hash = ezControl -> def. Name von xs1Bridge

	my ($xs1Dev,$xs1_readingsname,$xs1_ID,$xs1_typ2,$xs1_value,$xs1_f1,$xs1_f2,$xs1_f3,$xs1_f4,$xs1_name) = split("#", $data);
	my $xs1_typ1 = substr($xs1_readingsname,0,1);		## A || S

	my $def = $modules{xs1Dev}{defptr}{$xs1_typ1.$xs1_ID};
	$def = $modules{xs1Dev}{defptr}{$xs1_typ1.$xs1_ID} if(!$def);		## {xs1Dev}{defptr}{A02}
	
	my $hash = $def;
	$hash->{xs1_typ} = $xs1_typ2;
	$hash->{xs1_name} = $xs1_name;
	my $IODev = $io_hash->{NAME};

	my $name = $hash->{NAME};			## xs1Dev_Aktor_01
	my $typ = $hash->{TYPE};			## xs1Dev
	$typ = "xs1Dev" if (!$def);			## Erstanlegung
	
	###### Define and values update ######
	#Log3 $typ, 3, "$typ: Parse | Data: $xs1Dev | $xs1_readingsname | $xs1_ID | $xs1_typ2 | $xs1_value | $xs1_typ1" if (!$def);
	#Log3 $typ, 3, "$typ: Parse | Data: $xs1Dev | $xs1_readingsname | $xs1_ID | $xs1_typ2 | $xs1_value | $xs1_typ1";

	if(!$def) {
			# "UNDEFINED xs1Dev_Aktor_12 xs1Dev A 12"
			Log3 $name, 3, "$typ: Unknown device ".$xs1Dev."_".$xs1_readingsname."_"."$xs1_ID $xs1_ID $xs1_typ1 , please define it";
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
		
		#### Typ switch  | on | off mod for FHEM Default
		if ($xs1_typ2 eq "switch") {
			if ($xs1_value == 0) { $xs1_value = "off"; }
				elsif ($xs1_value == 100) { $xs1_value = "on"; }
			readingsSingleUpdate($hash, "state", $xs1_value ,1);	# Aktor | Sensor Update value
			
			## RegEx devStateIcon da Symbole nicht gleich benannt -> dim_up | dim_down
			if ($hash->{xs1_function1} eq "dim_up" || $hash->{xs1_function2} eq "dim_up" || $hash->{xs1_function3} eq "dim_up" || $hash->{xs1_function4} eq "dim_up" || 
				$hash->{xs1_function1} eq "dim_down" || $hash->{xs1_function2} eq "dim_down" || $hash->{xs1_function3} eq "dim_down" || $hash->{xs1_function4} eq "dim_down" ) {
				$attr{$name}{devStateIcon} = "dim_up:dimup dim_down:dimdown" if( not defined( $attr{$name}{devStateIcon} ) );
			}
			
		} 
		#### Typ temperature
		elsif ($xs1_typ2 eq "temperature") {
			my $xs1_value_new = "T: ".$xs1_value;	## temperature mod for FHEM Default

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $xs1_value_new);
			readingsBulkUpdate($hash, "temperature", $xs1_value);
			readingsEndUpdate($hash, 1);
		} 
		#### Typ hygrometer
		elsif ($xs1_typ2 eq "hygrometer") {
			my $xs1_value_new = "H: ".$xs1_value;	## hygrometer mod for FHEM Default

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $xs1_value_new);
			readingsBulkUpdate($hash, "humidity", $xs1_value);
			readingsEndUpdate($hash, 1);
		} 
		#### Typ dimmer
		elsif ($xs1_typ2 eq "dimmer") {
			
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
		#### Typ shutter | on | off mod for FHEM Default
		elsif ($xs1_typ2 eq "shutter") {
			if ($xs1_value == 0) { $xs1_value = "off"; }
				elsif ($xs1_value == 100) { $xs1_value = "on"; }
			readingsSingleUpdate($hash, "state", $xs1_value ,1);
		}
		#### Typ timerswitch | on | off mod for FHEM Default
		elsif ($xs1_typ2 eq "timerswitch") {
			if ($xs1_value == 0) { $xs1_value = "off"; }
				elsif ($xs1_value == 100) { $xs1_value = "on"; }
			readingsSingleUpdate($hash, "state", $xs1_value ,1);
		}
		elsif ($xs1_typ2 eq "barometer") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "pressure", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "P: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "rain") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "rain", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "R: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "rain_1h") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "rain_calc_h", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "R: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "rain_24h") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "rain_calc_d", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "R: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "winddirection") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "Winddirection", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "D: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "windspeed") {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "Windspeed", $xs1_value ,1);
			readingsSingleUpdate($hash, "state", "W: ".$xs1_value ,1);
			readingsEndUpdate($hash, 1);
		}
		elsif ($xs1_typ2 eq "counter" || $xs1_typ2 eq "counterdiff" || $xs1_typ2 eq "fencedetector" || $xs1_typ2 eq "gas_consump" || $xs1_typ2 eq "gas_peak" || 
			$xs1_typ2 eq "light" || $xs1_typ2 eq "motion" || $xs1_typ2 eq "other" || $xs1_typ2 eq "rainintensity" || $xs1_typ2 eq "remotecontrol" || 
			$xs1_typ2 eq "uv_index" || $xs1_typ2 eq "waterdetector" || $xs1_typ2 eq "waterlevel" || $xs1_typ2 eq "windgust" || $xs1_typ2 eq "windvariance" || 
			$xs1_typ2 eq "wtr_consump" || $xs1_typ2 eq "wtr_peak") {
				readingsSingleUpdate($hash, "state", $xs1_value ,1);
		}
		### Fenstermelder = windowopen | Tuermelder = dooropen --> 0 zu / 100 offen | mod for FHEM Default
		elsif ($xs1_typ2 eq "dooropen" || $xs1_typ2 eq "windowopen") {
			if ($xs1_value == 0.0) { $xs1_value = "closed";} elsif ($xs1_value == 100.0) { $xs1_value = "Open"; }
			readingsBeginUpdate($hash);
			if ($xs1_typ2 eq "windowopen") {
					readingsSingleUpdate($hash, "Window", $xs1_value ,1);
				}
			if ($xs1_typ2 eq "dooropen") {
					readingsSingleUpdate($hash, "Door", $xs1_value ,1);
				}
			my $value = Value($name);
			my $OldValue = OldValue($name);
			if ($value ne $OldValue) {
				readingsSingleUpdate($hash, "Previous", $xs1_value ,0);
			}
			readingsSingleUpdate($hash, "state", $xs1_value ,0);
			readingsEndUpdate($hash, 1);
		### alles andere ...
		} else {
			readingsBeginUpdate($hash);
			readingsSingleUpdate($hash, "state", $xs1_value ,0);
			readingsEndUpdate($hash, 1);
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
	<br>
	
	<br><ul>
	<u>Currently implemented types of xs1 for processing: </u><br>
	<li>Aktor: dimmer, switch, shutter, timerswitch</li>
	<li>Sensor: barometer, counter, counterdiff, light, motion, other, rain, rain_1h, rain_24h, rainintensity, remotecontrol, uv_index, waterdetector, winddirection, windgust, windspeed, windvariance</li>
	</ul><br><br>

	<a name="xs1Dev_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Dev &lt;Typ&gt; &lt;ID&gt; IODev=&lt;NAME&gt;</code>
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
		define xs1Dev_Aktor_02 xs1Dev A 02 IODev=ezControl
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul><code>set &lt;name&gt; &lt;value&gt; </code></ul><br>
	in which <code>value</code> one of the following values:<br>
	<ul><code>
      on<br>
      off<br>
      dimup<br>
      dimupdown<br>
      toggle<br>
      on, wait, off<br>
      absolut<br>
      wait<br>
	  long on<br>
	  long off<br>
	  Stopp<br>
	  on, wait, on<br>
	  off, wait, off<br>
	  impuls<br>
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
		</ul><br>
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
	Das Modul wurde entwickelt basierend auf dem Firmwarestand v4-Beta des xs1. Es kann aufgrund von unterschiedlichen Anpassungen innerhalb der Firmware des Herstellers zu Fehlern kommen.<br>
	
	<br><ul>
	<u>Derzeit implementierte Typen des xs1 zur Verarbeitung: </u><br>
	<li>Aktor: dimmer, switch, shutter, timerswitch</li>
	<li>Sensor: barometer, counter, counterdiff, light, motion, other, rain, rain_1h, rain_24h, rainintensity, remotecontrol, uv_index, waterdetector, winddirection, windgust, windspeed, windvariance</li>
	</ul><br><br>

	<a name="xs1Dev_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Dev &lt;Typ&gt; &lt;ID&gt; IODev=&lt;NAME&gt;</code>
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
		define xs1Dev_Aktor_02 xs1Dev A 02 IODev=ezControl
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul><code>set &lt;name&gt; &lt;value&gt; </code></ul><br>
	Wobei <code>value</code> der in der xs1 definierten Funktion entspricht. Bsp:<br>
	<ul><code>
      an<br>
      aus<br>
      dimup<br>
      dimupdown<br>
      umschalten<br>
      an, warten, aus<br>
      absolut<br>
      warten<br>
	  langes AN<br>
	  langes AUS<br>
	  Stopp<br>
	  an, warten, an<br>
	  aus, warten, aus<br>
	  Impuls<br>
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
		</ul><br>
	</ul>
		
</ul>
=end html_DE
=cut
