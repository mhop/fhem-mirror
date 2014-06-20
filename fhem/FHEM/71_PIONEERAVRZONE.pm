# $Id$
##############################################################################
#
#     71_PIONEERAVRZONE.pm
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub PIONEERAVRZONE_Get($@);
sub PIONEERAVRZONE_Set($@);
sub PIONEERAVRZONE_Attr($@);
sub PIONEERAVRZONE_Define($$);

###################################
sub
PIONEERAVRZONE_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = ".+"; 
  
  $hash->{GetFn}     = "PIONEERAVRZONE_Get";
  $hash->{SetFn}     = "PIONEERAVRZONE_Set";
  $hash->{DefFn}     = "PIONEERAVRZONE_Define";
  $hash->{ParseFn}   = "PIONEERAVRZONE_Parse";

  $hash->{AttrFn}    = "PIONEERAVRZONE_Attr";
  $hash->{AttrList}  = "IODev zone ".
                        $readingFnAttributes;
}


###################################
sub
PIONEERAVRZONE_Changed($$$)
{
        my ($hash, $cmd, $value)= @_;

        readingsBeginUpdate($hash);
        my $state= $cmd;

        if(defined($value) && $value ne "") {
          readingsBulkUpdate($hash, $cmd, $value);
          $state.= " $value";
        }
        readingsBulkUpdate($hash, "state", $state);
        readingsEndUpdate($hash, 1);
        my $name= $hash->{NAME};
        Log3 $hash, 4 , "PIONEERAVRZONE $name $state";
        return $state;
}

###################################

sub
PIONEERAVRZONE_Get($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $zone= $hash->{helper}{ZONE};
		my $expect= ".*";
        return "get $name needs at least one argument" if(int(@a) < 2);
        my $cmdName= $a[1];

        my $IOhash= $hash->{IODev};
		if ($cmdName eq "input" ) {
        } elsif (!defined($IOhash->{helper}{GETS}{$zone}{$cmdName})) {
                my $gets= $IOhash->{helper}{GETS}{$zone};
                return "$name error: unknown argument $cmdName, choose one of " .
                  (join " ", sort keys %$gets);
        }

        my $cmd= $IOhash->{helper}{GETS}{$zone}{$cmdName};

        my $v= IOWrite($hash, $cmd);

#        return PIONEERAVRZONE_Changed($hash, $cmdname, $v);;
		return undef;
}


#############################
sub
PIONEERAVRZONE_Set($@)
{
	my ($hash, @a)= @_;

	my $name= $hash->{NAME};
	my $type= $hash->{TYPE};
	return "set $name needs at least one argument" if(int(@a) < 2);
	my $cmd= $a[1];

	my $IOhash= $hash->{IODev};
	my $zone= $hash->{helper}{ZONE};
	my $vmax = 0;
	my $zahl= 0;
	my $muteStr ="";
	
	my @setsWithoutArg= ("off","toggle","volumeUp","volumeDown","muteOn","muteOff","muteToggle","inputUp","inputDown");
    
	Log3 $name, 5, "PIONEERAVRZONE $name: called function PIONEERAVR_Set()";

	return "No Argument given" if ( !defined( $cmd ) );

	my $inputNames= $IOhash->{helper}{INPUTNAMES};
	
	# get all input names (preferable the aliasName) of the enabled inputs for the drop down list of "set <device> input xxx"  
	my @listInputNames = ();
	foreach my $key ( keys %{$IOhash->{helper}{INPUTNAMES}} ) {
		if (defined($IOhash->{helper}{INPUTNAMES}->{$key}{enabled})) {
			if ( $IOhash->{helper}{INPUTNAMES}->{$key}{enabled} eq "1" ) {
				if ($IOhash->{helper}{INPUTNAMES}{$key}{aliasName}) {
					push(@listInputNames,$IOhash->{helper}{INPUTNAMES}{$key}{aliasName});
				} elsif ($IOhash->{helper}{INPUTNAMES}{$key}{name}) {
					push(@listInputNames,$IOhash->{helper}{INPUTNAMES}{$key}{name});
				}
			}
		}
	}
	if (($zone eq "zone2") || ($zone eq "zone3")) {
		$muteStr = " mute:on,off,toggle";
	}
	my $list =
	"on:noArg off:noArg toggle:noArg input:"
	. join(',', sort @listInputNames)
	. " inputUp:noArg inputDown:noArg"
	. " volumeUp:noArg volumeDown:noArg"
	. $muteStr
	. " statusRequest:noArg volume:slider,0,1,100"
	. " volumeStraight:slider,-80,1,".$vmax;
	
	if ( $cmd eq "?" ) {
		Log3 $name, 5, "PIONEERAVRZONE set $name " . $cmd;
		return SetExtensions($hash, $list, $name, $cmd, @a);
	}


	if(@a == 2) {
		Log3 $name, 5, "PIONEERAVRZONE $name: Set $cmd";

		#### simple set commands without attributes
		#### we just "translate" the human readable command to the PioneerAvr command
		#### lookup in $IOhash->{helper}{SETS}{$zone} if the command exists and what to write to PioneerAvr 
		if ( $cmd  ~~ @setsWithoutArg ) {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd (setsWithoutArg)";
			my $setCmd= $IOhash->{helper}{SETS}{$zone}{$cmd};
			my $v= IOWrite($hash, $setCmd);
			Log3  $hash, 5, "PIONEERAVR $name: Set_IOwrite($zone ... $cmd ): $setCmd";
			return undef;

		### Power on
		### Command: PO
		### according to "Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx" (notice) we need to send <cr> and 
		### wait 100ms before the first command is accepted by the Pioneer AVR
		} elsif ( $cmd  eq "on" ) {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
			my $setCmd= "";
			IOWrite($hash, $setCmd);
			select(undef, undef, undef, 0.1);

			if ( $zone eq "zone2" ) {
				$setCmd = "APO";
			} elsif ( $zone eq "zone3" ) {
				$setCmd =  "BPO";
			} elsif ( $zone eq "hdZone" ) {
				$setCmd =  "ZEO";
			}
			IOWrite($hash, $setCmd);
			select(undef, undef, undef, 0.1);
			Log3  $hash, 5, "PIONEERAVR $name: Set_IOwrite: $setCmd";
			return undef;				
			
		# statusRequest: execute all "get" commands	to update the readings
		} elsif ( $cmd eq "statusRequest") {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
			foreach my $key ( keys %{$IOhash->{helper}{GETS}{$zone}} ) {
				IOWrite($hash, $IOhash->{helper}{GETS}->{$zone}->{$key});
			}
			return undef;
		}
		#### commands with argument(s)
	} elsif(@a > 2) {
		my $arg = $a[2];
		####Input (all available Inputs of the Pioneer Avr -> see 'get $name loadInputNames')
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		if ( $cmd eq "input" ) {
			foreach my $key ( keys %{$IOhash->{helper}{INPUTNAMES}} ) {
				if ( $IOhash->{helper}{INPUTNAMES}->{$key}{name} eq $arg ) {
					IOWrite($hash, sprintf "%02dFN", $key);
					readingsSingleUpdate($hash, "input", $arg, 1 );
				}
			}
			return undef;
		#####VolumeStraight (-80.5 - 12) in dB
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "volumeStraight" ) {
			$zahl = 80.5 + $arg;
			if ( $zone eq "zone2" ) {
				IOWrite($hash, sprintf "%02dZV", $zahl);
			} elsif ( $zone eq "zone3" ) {
				IOWrite($hash, sprintf "%02dYV", $zahl);
			}
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "volumeStraight", $arg );
			readingsBulkUpdate($hash, "volume", sprintf "%d", ($a[2]+80)/0.8 );			
			readingsEndUpdate($hash, 1);
			return undef;
		####Volume (0 - 100) in %
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "volume" ) {
			$zahl = sprintf "%d", $arg*0.8;
		if ( $zone eq "zone2" ) {
			IOWrite($hash, sprintf "%02dZV", $zahl);
		} elsif ( $zone eq "zone3" ) {
			IOWrite($hash, sprintf "%02dYV", $zahl);
		} 			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "volumeStraight", $zahl - 80 );				
			readingsBulkUpdate($hash, "volume", sprintf "%d", $a[2] );				
			readingsEndUpdate($hash, 1); 
			return undef;
		####Mute (on|off|toggle)
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "mute" ) {
			if ($arg eq "on") {
				IOWrite($hash, $IOhash->{helper}{SETS}{$zone}{muteOn});
				readingsSingleUpdate($hash, "mute", "on", 1 );
			}
			elsif ($arg eq "off") {
				IOWrite($hash, $IOhash->{helper}{SETS}{$zone}{muteOff});
				readingsSingleUpdate($hash, "mute", "off", 1 );
			}
			elsif ($arg eq "toggle") {
				IOWrite($hash, $IOhash->{helper}{SETS}{$zone}{muteToggle});
			}
			return undef;
		} else {
		return SetExtensions($hash, $list, $name, $cmd, @a);
		}
	} else {
		return SetExtensions($hash, $list, $name, $cmd, @a);
	}
return undef;

}

#############################
sub
PIONEERAVRZONE_Parse($$)
{
  # we are called from dispatch() from the physical device
  # we never come here if $msg does not match $hash->{MATCH} in the first place
  # NOTE: we will update all matching readings for all (logical) devices, not just the first!
  
  my ($IOhash, $msg) = @_;   # IOhash points to the PIONEERAVR, not to the PIONEERAVRZONE

  my @matches;
  my $name= $IOhash->{NAME};
  my $state = '';

  #Debug "Trying to find a match for \"" . escapeLogLine($msg) ."\"";
  # walk over all clients
    foreach my $d (keys %defs) {
		my $hash= $defs{$d};
		if($hash->{TYPE} eq "PIONEERAVRZONE" && $hash->{IODev} eq $IOhash) {
			my $zone= $hash->{helper}{ZONE};
			readingsBeginUpdate($hash);
			# zone2
			if ($zone eq "zone2") {
				# volume zone2
				# ZVXX
				# XX 00 ... 81 -> -81dB ... 0dB
				if ( $msg =~ m/^ZV(\d\d)$/ ) {
					readingsBulkUpdate($hash, "volumeStraight", $1 - 81 );				
					readingsBulkUpdate($hash, "volume", sprintf "%d", $1/0.8 );
					push @matches, $d;
				# Mute zone2
				# Z2MUTX
				# X = 0: Mute on; X = 1: Mute off
				} elsif ( $msg =~ m/^Z2MUT(\d)$/) {
					if ($1) {
						readingsBulkUpdate($hash, "mute", "off" );
					} 
					else {
						readingsBulkUpdate($hash, "mute", "on" );
					}
					push @matches, $d;
				# Input zone2
				# Z2FXX
				# XX -> input number 00 ... 49
				} elsif ($msg =~ m/^Z2F(\d\d)$/ ) {
					if ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName} );
					} elsif ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{name}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{name} );
					} else {
						readingsBulkUpdate($hash, "input", $msg );
					}
					push @matches, $d;
				# Power zone2
				# APRX
				# X = 0: Power on; X = 1: Power off
				} elsif ( $msg =~ m/^APR(0|1)$/  ) {
					if ($1 == "0") {
						readingsBulkUpdate($hash, "power", "on" );
						$state = "on";
					} elsif ($1 == "1") {
						readingsBulkUpdate($hash, "power", "off" );
						$state = "off";
					}
					# Set reading for state
					#
					if ( !defined( $hash->{READINGS}{state}{VAL} )
						|| $hash->{READINGS}{state}{VAL} ne $state )
					{
						readingsBulkUpdate( $hash, "state", $state );
					}
				}
				push @matches, $d;
			# zone3
			} elsif ($zone eq "zone3") {
				# volume zone3
				# YVXX
				# XX 00 ... 81 -> -81dB ... 0dB
				if ( $msg =~ m/^YV(\d\d)$/ ) {
					readingsBulkUpdate($hash, "volumeStraight", $1 - 81 );				
					readingsBulkUpdate($hash, "volume", sprintf "%d", $1/0.8 );
					push @matches, $d;
				# Mute zone3
				# Z3MUTX
				# X = 0: Mute on; X = 1: Mute off
				} elsif ( $msg =~ m/^Z3MUT(\d)$/) {
					if ($1) {
						readingsBulkUpdate($hash, "mute", "off" );
					} 
					else {
						readingsBulkUpdate($hash, "mute", "on" );
					}
					push @matches, $d;
				# Input zone3
				# Z3FXX
				# XX -> input number 00 ... 49
				} elsif ($msg =~ m/^Z3F(\d\d)$/ ) {
					if ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName} );
					} elsif ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{name}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{name} );
					} else {
						readingsBulkUpdate($hash, "input", $msg );
					}
					push @matches, $d;
				# Power zone3
				# BPRX
				# X = 0: Power on; X = 1: Power off
				} elsif ( $msg =~ m/^BPR(0|1)$/  ) {
					if ($1 == "0") {
						readingsBulkUpdate($hash, "power", "on" );
						$state = "on";
					} elsif ($1 == "1") {
						readingsBulkUpdate($hash, "power", "off" );
						$state = "off";
					}
					# Set reading for state
					#
					if ( !defined( $hash->{READINGS}{state}{VAL} )
						|| $hash->{READINGS}{state}{VAL} ne $state )
					{
						readingsBulkUpdate( $hash, "state", $state );
					}
					push @matches, $d;
				}
			# hdZone	
			} elsif ($zone eq "hdZone") {
				# Input hdZone
				# ZEAXX
				# XX -> input number 00 ... 49
				if ($msg =~ m/^ZEA(\d\d)$/ ) {
					if ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName} );
					} elsif ( defined ( $IOhash->{helper}{INPUTNAMES}->{$1}{name}) ) {
						readingsBulkUpdate($hash, "input", $IOhash->{helper}{INPUTNAMES}->{$1}{name} );
					} else {
						readingsBulkUpdate($hash, "input", $msg );
					}
					push @matches, $d;
				# Power hdZone
				# ZEPX
				# X = 0: Power on; X = 1: Power off
				} elsif ( $msg =~ m/^ZEP(0|1)$/ ) {
					if ($1 == "0") {
						readingsBulkUpdate($hash, "power", "on" );
						$state = "on";
					} elsif ($1 == "1") {
						readingsBulkUpdate($hash, "power", "off" );
						$state = "off";
					}
					# Set reading for state
					#
					if ( !defined( $hash->{READINGS}{state}{VAL} )
						|| $hash->{READINGS}{state}{VAL} ne $state )
					{
						readingsBulkUpdate( $hash, "state", $state );
					}
					push @matches, $d;
				}
			}
			readingsEndUpdate($hash, 1);
			
		}
	}
	return @matches if(@matches);
	return "UNDEFINED PIONEERAVRZONE message1 $msg";  
  
}

#####################################
sub
PIONEERAVRZONE_Attr($@)
{

  my @a = @_;
  my $hash= $defs{$a[1]};

  return undef;
}

#############################
sub
PIONEERAVRZONE_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t]+", $def);

	return "Usage: define <name> PIONEERAVRZONE [<zone> [...]]"    if(int(@a) < 2);
	my $name= $a[0];
	
	AssignIoPort($hash);
	
    my $IOhash= $hash->{IODev};
    if(!defined($IOhash)) {
            my $err= "PIONEERAVRZONE $name error: no I/O device.";
            Log3 $hash, 1, $err;
            return $err;
    }
           
	#2. Parameter (Zone)
	my $zone="";
	if(defined($a[2])) {
		if ($a[2] =~ m/[zone\d]|[hdZone]/) {
			$zone= $a[2];
		}
	} else {
		my $err= "PIONEERAVRZONE define $name error: unknown Zone '$zone' -> must be one of [zone2|zone3hdZone] (I/O device is " 
				  . $IOhash->{NAME} . ").";
		Log3 $hash, 1, $err;
		return $err;
	}
	
    if(!defined($IOhash->{helper}{SETS}{$zone})) {
            my $err= "PIONEERAVRZONE define $name error: unknown Zone $zone (I/O device is " 
                      . $IOhash->{NAME} . ").";
            Log3 $hash, 1, $err;
            return $err;
    }

    $hash->{helper}{ZONE}= $zone;
	
	# set default attributes
    unless ( exists( $attr{$name}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:mute:input';
    }
    unless ( exists( $attr{$name}{devStateIcon} ) ) {
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_STOP:on absent:rc_RED';
    }
	
	return undef;

}

1;

=pod
=begin html

<a name="PIONEERAVRZONE"></a>
<h3>PIONEERAVRZONE</h3>
<ul>
  <br>
  <a name="PIONEERAVRZONEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVRZONE &lt;zone&gt; </code>
    <br><br>

    Defines a Zone (zone2, zone3 or hdZone) of a PioneerAVR device.<p>
    
    Normally, the logical PIONEERAVRZONE is attached to the latest previously defined physical PIONEERAVR device
    for I/O. Use the <code>IODev</code> attribute of the logical PIONEERAVRZONE to attach to any
    physical PioneerAVR device, e.g. <code>attr myPioneerAvrZone2 IODev myPioneerAvr</code>.
    <br><br>

    Examples:
    <ul>
      <code>define myPioneerAvrZone2 PIONEERAVRZONE zone2</code><br>
      <code>attr myPioneerAvrZone2 IODev myPIONEERAVR</code>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRZONEset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of
	<li>reopen</li>
	<li>off <br>turn zone power on</li>
	<li>on <br>turn zone power on</li>
	<li>toggle <br>toggles zone power</li>
	<li>volume <0 ... 100><br>zone volume in % of the maximum volume</li>
	<li>volumeUp<br>increases the zone volume by 0.5dB</li>
	<li>volumeDown<br>decreases the zone volume by 0.5dB</li>
	<li>volumeStraight<-80.5 ... 12><br>same values for zone volume as shown on the display of the Pioneer AV receiver</li>
	<li>mute <on|off|toggle></li>
	<li>input <not on the Pioneer hardware deactivated input><br>the list of possible (i.e. not deactivated)
	inputs is read in during Fhem start and with <code>get <name> statusRequest</code></li>
	<li>inputUp<br>change zone input to next input</li>
	<li>inputDown<br>change zone input to previous input</li>
	
   <br><br>
    Example:
    <ul>
      <code>set VSX923Zone2 on</code><br>
    </ul>
    <br><br>
  </ul>
 <a name="PIONEERAVRZONEget"></a>
  <b>Get</b>
  <ul>
    <li><code>get &lt;name&gt; input</code>
    <br><br>
    Update the reading for the zone input
    </li>
  </ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>IOdev Name of the device which communicates with the phisical Pioneer AV receiver via ethernet or rs232</li>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br> 
</ul>

=end html
=begin html_DE

<a name="PIONEERAVRZONE"></a>
<h3>PIONEERAVRZONE</h3>
<ul>
  <br>
  <a name="PIONEERAVRZONEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVRZONE &lt;zone&gt; </code>
    <br><br>

    Definiert ein PioneerAVR device für eine Zone Zone (zone2, zone3 or hdZone).<p>
    
    Im Allgemeinen verwendet das logische device PIONEERAVRZONE das zuletzt definierte PIONEERAVR device für die Kommunikation mit dem Pioneer AV Receiver.
	Mit dem Atribut <code>IODev</code> kann das PIONEERAVRZONE device jedes PIONEERAVR device zur Kommunikation verwenden,
	z.B. <code>attr myPioneerAvrZone2 IODev myPioneerAvr</code>.
    <br><br>

    Examples:
    <ul>
      <code>define myPioneerAvrZone2 PIONEERAVRZONE zone2</code><br>
      <code>attr myPioneerAvrZone2 IODev myPIONEERAVR</code>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRZONEset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;was&gt; [&lt;value&gt;]</code>
    <br><br>
    wobei &lt;was&gt; eines der folgenden Befehle sein kann:
	<li>reopen</li>
	<li>off <br>Zone Ausschalten</li>
	<li>on <br>Zone Einschalten</li>
	<li>toggle <br>Zone Ein/Ausschalten</li>
	<li>volume <0 ... 100><br>Zonenlautstärkein % der maximalen Lautstärke</li>
	<li>volumeUp<br>Zonenlautstärke um 0.5dB erhöhen</li>
	<li>volumeDown<br>Zonenlautstärke um 0.5dB verringern</li>
	<li>volumeStraight<-80.5 ... 12><br>Einstellen der Zonenlautstärke mit einem Wert, wie er am Display des Pioneer AV Receiver angezeigt wird</li>
	<li>mute <on|off|toggle></li>
	<li>input <nicht am Pioneer AV Receiver deaktivierte Eingangsquelle><br> Die Liste der verfügbaren (also der nicht deaktivierten)
	Eingangsquellen wird beim Start von Fhem und auch mit <code>get <name> statusRequest</code> eingelesen</li>
	<li>inputUp<br>nächste Eingangsquelle für die Zone auswählen</li>
	<li>inputDown<br>vorherige Eingangsquelle für die Zone auswählen</li>
	
   <br><br>
    Beispiel:
    <ul>
      <code>set VSX923Zone2 on</code><br>
    </ul>
    <br><br>
  </ul>
 <a name="PIONEERAVRZONEget"></a>
  <b>Get</b>
  <ul>
    <li><code>get &lt;name&gt; input</code>
    <br><br>
    reading für die Eingangsquelle aktualisieren
    </li>
  </ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>IOdev Name des device welches die Kommunikation mit dem Pioneer AV Receiver zur Verfügung stellt</li>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br> 
</ul>

=end html_DE
=cut
