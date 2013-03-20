##############################################
#     98_THRESHOLD by Damian Sordyl
#
#     This file is part of fhem.
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
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################


package main;
use strict;
use warnings;

sub THRESHOLD_setValue($$);

##########################
sub
THRESHOLD_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "THRESHOLD_Define";
  $hash->{SetFn}   = "THRESHOLD_Set";
  $hash->{NotifyFn} = "THRESHOLD_Notify";
  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6";
}


##########################
sub
THRESHOLD_Define($$$)
{
  my ($hash, $def) = @_;
  my @b =split (/\|/,$def);
  my @a = split("[ \t][ \t]*", $b[0]);
  my $cmd1="";
  my $cmd2="";
  my $state_cmd1="";
  my $state_cmd2="";
  my $cmd_default=0;
  my $actor;
   
  if (@b > 5 || @a < 3 || @a > 6) {
    my $msg = "wrong syntax: define <name> THRESHOLD " .
               "<sensor>[:[<reading>][:[<hysteresis>][:<init_desired_value>]]] [AND|OR <sensor2>[:[<reading2>][:<state>]]] ".
			   "[<actor>][|[<cmd1>][|[<cmd2>][|[<cmd_default_index>][|[[<state_cmd1>][:<state_cmd2>]]]]]]";
    Log 2, $msg;
    return $msg;
  } 
  my $pn = $a[0];
  # Sensor
  my ($sensor, $reading, $hysteresis,$init_desired_value) = split(":", $a[2], 4);
  
  if(!$defs{$sensor}) {
    my $msg = "$pn: Unknown sensor device $sensor specified";
    Log 2, $msg;
    return $msg;
  }
  
  $hash->{sensor} = $sensor;
  $reading = "temperature" if (!defined($reading));
   
  if (!defined($hysteresis)) {
	if ($reading eq "temperature" or $reading eq "temp") {
	  $hysteresis=1;
	} elsif ($reading eq "humidity") {
	    $hysteresis=10;
	  } else {
	    $hysteresis=0;
	  }
  } elsif ($hysteresis !~ m/^[\d\.]*$/ ) {
	  my $msg = "$pn: value:$hysteresis, hysteresis needs a numeric parameter";
      Log 2, $msg;
      return $msg;
  }	
  if (defined($init_desired_value)) {
	if ($init_desired_value !~ m/^[-\d\.]*$/) {
      my $msg = "$pn: value:$init_desired_value, init_desired_value needs a numeric parameter";
      Log 2, $msg;
      return $msg;  
	}
  }
  $hash->{sensor_reading} = $reading;
  $hash->{hysteresis} = $hysteresis;
  
  # Sensor2
  
  if (defined($a[3])) {
    my $operator=$a[3];
	if (($operator eq "AND") or ($operator eq "OR")) {
	  my ($sensor2, $sensor2_reading, $state) = split(":", $a[4], 3);
	  if (defined ($sensor2)) {
	    if(!$defs{$sensor2}) {
	    my $msg = "$pn: Unknown sensor2 device $sensor2 specified";
	    Log 2, $msg;
	    return $msg;
 	   }
	  } 
	  $sensor2_reading = "state" if (!defined ($sensor2_reading));
	  $state = "open" if (!defined ($state));
	  $hash->{operator} = $operator;
	  $hash->{sensor2} = $sensor2;
	  $hash->{sensor2_reading} = $sensor2_reading;
	  $hash->{sensor2_state} = $state;
	  $actor = $a[5];
	} else {
	  $actor = $a[3];
	}
  }
  if (defined ($actor)) {
    if (!$defs{$actor}) {
       my $msg = "$pn: Unknown actor device $actor specified";
       Log 2, $msg;
       return $msg;
	}
  }
  if (@b == 1) { # no actor parameters
	if (!defined($actor)) {
       my $msg = "$pn: no actor device specified";
       Log 2, $msg;
       return $msg;
	}
  	$cmd1 = "set $actor off";
	$cmd2 = "set $actor on";
	$cmd_default = 2;
  } else { # actor parameters 
    $cmd1 = $b[1] if (defined($b[1]));
	$cmd2 = $b[2] if (defined($b[2]));
	$cmd_default = (!($b[3])) ? 0 : $b[3];
	if ($cmd_default !~ m/^[0-2]$/ ) {
	     my $msg = "$pn: value:$cmd_default, cmd_default_index needs 0,1,2";
         Log 2, $msg;
         return $msg;
	}
    if (defined($b[4])) {
	  my ($st_cmd1, $st_cmd2) = split(":", $b[4], 2);
	  $state_cmd1 = $st_cmd1 if (defined($st_cmd1));
	  $state_cmd2 = $st_cmd2 if (defined($st_cmd2));
	}	
  }
  if (defined($actor)) {
	$cmd1 =~ s/@/$actor/g;
	$cmd2 =~ s/@/$actor/g;
  }

  $hash->{helper}{state_cmd1} = $state_cmd1;
  $hash->{helper}{state_cmd2} = $state_cmd2;
  $hash->{helper}{actor_cmd1} = SemicolonEscape($cmd1);
  $hash->{helper}{actor_cmd2} = SemicolonEscape($cmd2);
  $hash->{helper}{actor_cmd_default} = $cmd_default;
  $hash->{STATE} = 'initialized' if (!ReadingsVal($pn,"desired_value",""));
  
  if (defined ($init_desired_value))
  {
    my $set_state =($state_cmd1 eq "" and $state_cmd2 eq "") ? 1 : 0;
    readingsBeginUpdate  ($hash);
	readingsBulkUpdate   ($hash, "state", "active $init_desired_value") if ($set_state);
	readingsBulkUpdate   ($hash, "threshold_min", $init_desired_value-$hysteresis);
	readingsBulkUpdate   ($hash, "cmd","wait for next cmd");
	readingsBulkUpdate   ($hash, "desired_value", $init_desired_value);
	readingsEndUpdate    ($hash, 1);
  }
  return undef;
}

##########################
sub
THRESHOLD_Set($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $ret="";
  return "$pn, need a parameter for set" if(@a < 2);
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  my $desired_value;
  my $set_state = ($hash->{helper}{state_cmd1} eq "" and $hash->{helper}{state_cmd2} eq "") ? 1 : 0;
 
 
  if ($arg eq "desired" ) {
    return "$pn: set desired value:$value, desired value needs a numeric parameter" if(@a != 3 || $value !~ m/^[-\d\.]*$/);
    Log GetLogLevel($pn,3), "set $pn $arg $value";
	readingsBeginUpdate  ($hash);
	readingsBulkUpdate   ($hash, "state", "active $value") if ($set_state);
	readingsBulkUpdate   ($hash, "threshold_min",$value-$hash->{hysteresis});
	readingsBulkUpdate   ($hash, "cmd","wait for next cmd");
	readingsBulkUpdate   ($hash, "desired_value", $value);
	readingsEndUpdate    ($hash, 1);
  } elsif ($arg eq "deactivated" ) {
      $desired_value = ReadingsVal($pn,"desired_value","");
	  return "$pn: set deactivated, set desired value first" if (!$desired_value);
	  $ret=CommandAttr(undef, "$pn disable 1");   
	  if (!$ret) {
	    readingsSingleUpdate   ($hash, "state", "deactivated $desired_value",1) if ($set_state);
	  }
  } elsif ($arg eq "active" ) {
      $desired_value = ReadingsVal($pn,"desired_value","");
	  return "$pn: set active, set desired value first" if (!$desired_value);
	  $ret=CommandDeleteAttr(undef, "$pn disable");
	  if (!$ret) {
		readingsBeginUpdate  ($hash);
		readingsBulkUpdate ($hash, "state", "active $desired_value") if ($set_state);
		readingsBulkUpdate   ($hash, "cmd","wait for next cmd");
		readingsEndUpdate    ($hash, 1);
	  }
	} elsif ($arg eq "hysteresis" ) {
		return "$pn: set hysteresis value:$value, hysteresis needs a numeric parameter" if (@a != 3  || $value !~ m/^[\d\.]*$/ );
		$hash->{hysteresis} = $value;
		$desired_value = ReadingsVal($pn,"desired_value","");
		if ($desired_value) {
		  readingsBeginUpdate  ($hash);
	      readingsBulkUpdate   ($hash, "threshold_min",$desired_value-$hash->{hysteresis});
          readingsBulkUpdate   ($hash, "cmd","wait for next cmd");
	      readingsEndUpdate    ($hash, 1);
		}
	  } else {
          return "$pn: unknown argument $a[1], choose one of desired active deactivated hysteresis"
        }
  return $ret;
}

##########################
sub
THRESHOLD_Notify($$)
{
  my ($hash, $dev) = @_;
  my $pn = $hash->{NAME};
    
  return "" if(($attr{$pn} && $attr{$pn}{disable}) || !ReadingsVal($pn,"desired_value",""));
  
  my $sensor = $hash->{sensor};
  my $reading = $hash->{sensor_reading};
  my $sensor2 = $hash->{sensor2};
  my $reading2 = $hash->{sensor2_reading};
   
  if ($dev->{NAME} ne $sensor) {
	if ($sensor2) {
	  if ($dev->{NAME} ne $sensor2) {
		return "";
	  }
	} else {
	   return "";
	}  
  } 
  
  if(!($defs{$sensor}{READINGS}{$reading})) {
    my $msg = "$pn: no reading yet for $sensor $reading";
    Log 2, $msg;
    return "";
  } 
  
  my $instr = $defs{$sensor}{READINGS}{$reading}{VAL};
 
  $instr =~  /[^\d^\-^.]*([-\d.]*)/;

  my $s_value = $1;
 
 
  my $sensor_max = ReadingsVal($pn,"desired_value","");
  my $sensor_min = ReadingsVal($pn,"threshold_min","");
  my $cmd_default = $hash->{helper}{actor_cmd_default};
  
  readingsSingleUpdate  ($hash, "sensor_value",$s_value, 1);
  
  if (!$hash->{operator}) {
    if ($s_value > $sensor_max) {
      THRESHOLD_setValue($hash,1);
	} elsif ($s_value < $sensor_min) {
	    THRESHOLD_setValue($hash,2);
    } else {
	    THRESHOLD_setValue($hash,$cmd_default) if (ReadingsVal($pn,"cmd","") eq "wait for next cmd" && $cmd_default != 0);
    }
  } else {
    if (!($defs{$sensor2}{READINGS}{$reading2})) {
       my $msg = "$pn: no reading yet for $sensor2 $reading2";
       Log 2, $msg;
       return "";
	}
	  
    my $s2_state = $defs{$sensor2}{READINGS}{$reading2}{VAL};
	my $sensor2_state = $hash->{sensor2_state};

	readingsSingleUpdate  ($hash, "sensor2_state",$s2_state, 1);  

    if ($hash->{operator} eq "AND") {
      if (($s_value > $sensor_max) && ($s2_state eq $sensor2_state)) {
        THRESHOLD_setValue($hash,1);
      } elsif (($s_value < $sensor_min)  || ($s2_state ne $sensor2_state)){
	      THRESHOLD_setValue($hash,2);
      } else {
	      THRESHOLD_setValue($hash,$cmd_default) if (ReadingsVal($pn,"cmd","") eq "wait for next cmd" && $cmd_default != 0);
      }
    } elsif ($hash->{operator} eq "OR") {
	    if (($s_value > $sensor_max) || ($s2_state eq $sensor2_state)) {
          THRESHOLD_setValue($hash,1);
	    } elsif (($s_value < $sensor_min)  && ($s2_state ne $sensor2_state)){
	        THRESHOLD_setValue($hash,2);
        } else {
		  THRESHOLD_setValue($hash,$cmd_default) if (ReadingsVal($pn,"cmd","") eq "wait for next cmd" && $cmd_default != 0);
		}
	  }
  }
  return "";
}

sub
THRESHOLD_setValue($$)
{
  my ($hash, $cmd_nr) = @_;
  my $pn = $hash->{NAME};
  my @cmd_sym = ("cmd1","cmd2");
  my $cmd_sym_now = $cmd_sym[$cmd_nr-1];

  if (ReadingsVal($pn,"cmd","") ne $cmd_sym_now) {
	my $ret=0;
	my @cmd =($hash->{helper}{actor_cmd1},$hash->{helper}{actor_cmd2});
	my @state_cmd = ($hash->{helper}{state_cmd1},$hash->{helper}{state_cmd2});
	my $cmd_now = $cmd[$cmd_nr-1];
	my $state_cmd_now = $state_cmd[$cmd_nr-1];
  	if ($cmd_now ne "") {
	  if ($ret = AnalyzeCommandChain(undef, $cmd_now)) {
	    Log GetLogLevel($pn,3), "output of $pn $cmd_now: $ret";
		return "";
	  }
	}
	readingsBeginUpdate ($hash);
	readingsBulkUpdate  ($hash, "state",$state_cmd_now) if (($state_cmd_now) ne ""); 
    readingsBulkUpdate  ($hash, "cmd",$cmd_sym_now);
	readingsEndUpdate   ($hash, 1);
  }  
}

1;

=pod
=begin html

<a name="THRESHOLD"></a>
<h3>THRESHOLD</h3>
<ul>
  This module reads any sensor that provides values in decimal and execute FHEM/Perl commands, if the value of the sensor is higher or lower than the threshold value.
  So can be easily implemented a software thermostat, hygrostat and much more.<br> 
  <br>
  It is controlled by setting a desired value with:<br>
  <br>
  <code>set &lt;name&gt; desired &lt;value&gt;</code><br>
  <br>
  The switching behavior can also be influenced by another sensor or sensor group.<br>
  <br>
  </ul>
  <a name="THRESHOLDdefine"></a>
  <b>Define</b>
<ul>
  <br>
  <code>define &lt;name&gt; THRESHOLD &lt;sensor&gt;[:[&lt;reading&gt;][:[&lt;hysteresis&gt;][:&lt;init_desired_value&gt;]]] [AND|OR &lt;sensor2&gt;[:[&lt;reading2&gt;][:&lt;state&gt;]]] [&lt;actor&gt;][|[&lt;cmd1&gt;][|[&lt;cmd2&gt;][|[&lt;cmd_default_index&gt;][|[[&lt;state_cmd1&gt;][:&lt;state_cmd2&gt;]]]]]]</code><br>
  <br>
  <br>
	<li>sensor<br>
	  a defined sensor in FHEM
	</li>
	<li>reading<br>
	  reading of the sensor, which includes a value in decimal<br>
	  default value: temperature
	</li>
	<li>hysteresis<br>
	Hysteresis, this provides the threshold_min = desired_value - hysteresis<br>
	default value: 1 at temperature, 10 at huminity
	</li>
	<li>init_desired_value<br>
	  Initial value, if no value is specified, it must be set with "set desired value".<br>
	  Defaultwert: no value
	</li>
	<br>
	<br>
	<li>AND|OR<br>
	logical operator with an optional second sensor
	</li>
	<li>sensor2<br>
    the second sensor
	</li>
	<li>reading2<br>
    reading of the second sensor<br>
	default value: state
	</li>
	<li>state<br>
	state of the second sensor<br>
	default value: open
	</li><br>
	<li>actor<br>
	actor device defined in FHEM
	</li>
	<li>cmd1<br>
	FHEM/Perl command that is executed, if the value of the sensor is higher than desired value and/or the value of sensor 2 is matchted. @ is a placeholder for the specified actor.<br>
	default value: set actor off, if actor defined
	</li>
	<li>cmd2<br>
	FHEM/Perl command that is executed, if the value of the sensor is lower than threshold_min or the value of sensor 2 is not matchted. @ is a placeholder for the specified actor.<br>
	default value: set actor on, if actor defined
	</li>
	<li>cmd_default_index<br>
	Index of command that is executed after setting the desired value until the desired value or threshold_min value is reached.<br>
	0 - no command<br>
	1 - cmd1<br>
	2 - cmd2<br>
    default value: 2, if actor defined, else 0<br>
    </li>
	<br>
	<li>state_cmd1<br>
	state, which is displayed, if FHEM/Perl-command cmd1 was executed. If state_cmd1 state ist set, other states, such as active or deactivated are suppressed.
	<br>
	default value: none
	</li>
	<li>state_cmd2<br>
	state, which is displayed, if FHEM/Perl-command cmd1 was executed. If state_cmd1 state ist set, other states, such as active or deactivated are suppressed.
	<br>
	default value: none
	</li>
	<br>
	<br>
    Examples:<br>
    <br>
	Example for heating:<br>
	<br>	
	<code>define thermostat THRESHOLD temp_sens heating</code><br>
	<br>
	<code>set thermostat desired 20</code><br>
	<br>
	Description:<br>
	<br>
	It is heated up to the desired value of 20. If the value below the threshold_min value of 19 (20-1)
    the heating is switched on again.<br>
	<br>
	Example for heating with window contact:<br>
	<br>
	<code>define thermostat THRESHOLD temp_sens OR win_sens heating</code><br>
	<br>
	Example for heating with multiple window contacts:<br>
	<br>
	<code>define W_ALL structure <TYPE> W1 W2 W3 ...</code><br>
	<code>attr W_ALL clientstate_behavior relative</code><br>
	<code>attr W_ALL clientstate_priority closed open</code><br>
    <br>
	then: <br>
    <br>
	<code>define thermostat THRESHOLD S1 OR W_ALL heating</code><br>
    <br>
	More examples for dehumidification, air conditioning, watering:<br>
	<br>
	<code>define hygrostat THRESHOLD hym_sens:humidity dehydrator|set @ on|set @ off|1</code><br>
	<code>define hygrostat THRESHOLD hym_sens:humidity AND Sensor2:state:close dehydrator|set @ on|set @ off|1</code><br>
	<code>define thermostat THRESHOLD temp_sens:temperature:1 aircon|set @ on|set @ off|1</code><br>
	<code>define thermostat THRESHOLD temp_sens AND Sensor2:state:close aircon|set @ on|set @ off|1</code><br>
	<code>define hygrostat THRESHOLD hym_sens:humidity:20 watering|set @ off|set @ on|2</code><br>
	<br>
	It can also FHEM/perl command chains are specified:<br>
	<br>
	Examples:<br>
	<br>
	<code>define thermostat THRESHOLD sensor |set Switch1 on;set Switch2 on|set Switch1 off;set Switch2 off|1</code><br>
    <code>define thermostat THRESHOLD sensor alarm|{Log 2,"value is exceeded"}|set @ on;set Switch2 on</code><br>
	<code>define thermostat THRESHOLD sensor ||{Log 2,"value is reached"}|</code><br>
    <br>
	Example for status display on/off:<br>
	<br>
	<code>define thermostat THRESHOLD sensor heating|set @ off|set @ on|2|off:on</code><br>
	<br>
	Example for status display (eg for state evaluation in other modules), if temperature drops below 30 degrees or above:<br>
	<br>
	<code>define thermostat THRESHOLD sensor:temperature:0:30 ||||on:off</code><br>
	<br>
  </ul>
	<a name="THRESHOLDset"></a>
  <b>Set </b>
  <ul>
      <li> <code>set &lt;name&gt; desired &lt;value&gt;<br></code>
	  Set the desired value. If no desired value is set, the module is not active.
	  </li>
	  <br>
      <li> <code>set &lt;name&gt; deactivated &lt;value&gt;<br></code>
	  Module is disabled.
	  </li>
	  <br>
      <li> <code>set &lt;name&gt; active &lt;value&gt;<br></code>
	  Module is activated again.  
	  </li>
	  <br>
      <li> <code>set &lt;name&gt; hysteresis &lt;value&gt;<br></code>
	  Set hysteresis value.  
	  </li>
  </ul>
  <br>

  <a name="THRESHOLDget"></a>
  <b>Get </b>
  <ul>
      N/A
  </ul>
  <br>

  <a name="THRESHOLDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>
	
=end html
=begin html_DE

<a name="THRESHOLD"></a>
<h3>THRESHOLD</h3>
<ul>
  Dieses Modul liest einen beliebigen Sensor aus, der Werte als Dezimalzahlen liefert und führt beim Überschreiten der Schwellen-Obergrenze (Sollwert) bzw. beim Unterschreiten der Schwellen-Untergrenze beliebige FHEM/Perl-Befehle aus. Damit lässt sich leicht z. B. ein Software-Thermostat oder -Hygrostat realisieren.<br>
  <br>
  Nach der Definition eines Moduls vom Typ THRESHOLD erfolgt die eigentliche Steuerung über die Vorgabe eines Sollwertes.<br>
  <br>
  Das geschieht über:<br>
  <br>
  <code>set &lt;name&gt; desired &lt;value&gt;</code><br>
  <br>
  Das Modul beginnt mit der Steuerung erst dann, wenn ein Sollwert gesetzt wird.<br>
  <br>
  Optional kann das Schaltverhalten zusätzlich durch einen weiteren Sensor oder eine Sensorgruppe,
  definiert über structure (z. B. Fensterkontakte), beeinflusst werden.<br>
  <br>
 </ul>
  <a name="THRESHOLDdefine"></a>
  <b>Define</b>
<ul>
  <br>
    <code>define &lt;name&gt; THRESHOLD &lt;sensor&gt;[:[&lt;reading&gt;][:[&lt;hysteresis&gt;][:&lt;init_desired_value&gt;]]] [AND|OR &lt;sensor2&gt;[:[&lt;reading2&gt;][:&lt;state&gt;]]] [&lt;actor&gt;][|[&lt;cmd1&gt;][|[&lt;cmd2&gt;][|[&lt;cmd_default_index&gt;][|[[&lt;state_cmd1&gt;][:&lt;state_cmd2&gt;]]]]]]</code><br>
  <br>
   	<br>
	<li>sensor<br>
	  ein in FHEM definierter Sensor
	</li>
	<li>reading<br>
	  Reading des Sensors, der einen Wert als Dezimalzahl beinhaltet<br>
	  Defaultwert: temperature
	</li>
	<li>hysteresis<br>
	Hysterese, daraus errechnet sich die Untergrenze = Sollwert - hysteresis<br>
	Defaultwert: 1 bei Temperaturen, 10 bei Feuchtigkeit
	</li>
	<li>init_desired_value<br>
	  Initial-Sollwert, wenn kein Wert vorgegeben wird, muss er mit "set desired value" gesetzt werden<br>
	  Defaultwert: kein
	</li>
	<br>
	<br>
	<li>AND|OR<br>
	Verknüpfung mit einem optionalen zweiten Sensor
	</li>
	<li>sensor2<br>
    ein definierter Sensor, dessen Status abgefragt wird
	</li>
	<li>reading2<br>
    Reading, der den Status des Sensors beinhaltet<br>
	Defaultwert: state
	</li>
	<li>state<br>
	Status des Sensors, der zu einer Aktion führt<br>
	Defaultwert: open
	</li><br>
	<li>actor<br>
	ein in FHEM definierter Aktor
	</li>
	<li>cmd1<br>
	FHEM/Perl Befehl, der beim Überschreiten des Sollwertes ausgeführt wird bzw.
	wenn status des sensor2 übereinstimmt. @ ist ein Platzhalter für den angegebenen Aktor.
	<br>
	Defaultwert: set actor off, wenn Aktor angegeben ist
	</li>
	<li>cmd2<br>
	FHEM/Perl Befehl, der beim Unterschreiten der Untergrenze (Sollwert-Hysterese) ausgeführt wird bzw.
	wenn status des sensor2 nicht übereinstimmt. @ ist ein Platzhalter für den angegebenen Aktor.
	<br>
	Defaultwert: set actor on, wenn Aktor angegeben ist
	</li>
	<li>cmd_default_index<br>
	FHEM/Perl Befehl, der nach dem Setzen des Sollwertes ausgeführt wird, bis Sollwert oder die Untergrenze erreicht wird.<br>
	0 - kein Befehl<br>
	1 - cmd1<br>
	2 - cmd2<br>
    Defaultwert: 2, wenn Aktor angegeben ist, sonst 0<br>
	</li>
	<br>
	<li>state_cmd1<br>
	Status, der angezeigt wird, wenn FHEM/Perl-Befehl cmd1 ausgeführt wurde. Wenn state_cmd1 gesetzt ist, werden andere Stati, wie active oder deactivated unterdrückt.
	<br>
	Defaultwert: keiner
	</li>
	<li>state_cmd2<br>
	Status, der angezeigt wird, wenn FHEM/Perl-Befehl cmd2 ausgeführt wurde. Wenn state_cmd2 gesetzt ist, werden andere Stati, wie active oder deactivated unterdrückt.
	<br>
	Defaultwert: keiner
	</li>
	<br>
	<br>
    Beispiele:<br>
    <br>
	Beispiel für Heizung:<br>
	<br>	
	<code>define thermostat THRESHOLD temp_sens heating</code><br>
	<br>
	<code>set thermostat desired 20</code><br>
	<br>
	Beschreibung:<br>
	<br>
	Es wird geheizt bis zum Maximalwert 20. Beim Unterschreiten des Untergrenze von 19 (20-1) wird die Heizung wieder eingeschaltet.<br>
	<br>
	Beispiel für Heizung mit Fensterkontakt:<br>
	<br>
	<code>define thermostat THRESHOLD temp_sens OR win_sens heating</code><br>
	<br>
	Beispiel für Heizung mit mehreren Fensterkontakten:<br>
	<br>
	<code>define W_ALL structure <TYPE-Deiner-Kontakte> W1 W2 W3 ....</code><br>
	<code>attr W_ALL clientstate_behavior relative</code><br>
	<code>attr W_ALL clientstate_priority closed open</code><br>
    <br>
	danach: <br>
    <br>
	<code>define thermostat THRESHOLD S1 OR W_ALL heating</code><br>
    <br>
	Einige weitere Bespiele für Entfeuchtung, Klimatisierung, Bewässerung:<br>
	<br>
	<code>define hygrostat THRESHOLD hym_sens:humidity dehydrator|set @ on|set @ off|1</code><br>
	<code>define hygrostat THRESHOLD hym_sens:humidity AND Sensor2:state:close dehydrator|set @ on|set @ off|1</code><br>
	<code>define thermostat THRESHOLD temp_sens:temperature:1 aircon|set @ on|set @ off|1</code><br>
	<code>define thermostat THRESHOLD temp_sens AND Sensor2:state:close aircon|set @ on|set @ off|1</code><br>
	<code>define hygrostat THRESHOLD hym_sens:humidity:20 watering|set @ off|set @ on|2</code><br>
	<br>
	Es können ebenso FHEM/Perl-Befehlsketten angegeben werden:<br>
	<br>
	Beispiele:<br>
	<br>
	<code>define thermostat THRESHOLD sensor |set Switch1 on;set Switch2 on|set Switch1 off;set Switch2 off|1</code><br>
    <code>define thermostat THRESHOLD sensor alarm|{Log 2,"Wert überschritten"}|set @ on;set Switch2 on</code><br>
	<code>define thermostat THRESHOLD sensor ||{Log 2,"Wert unterschritten"}|</code><br>
    <br>
	Beispiele mit Statusanzeige:<br>
	<br>
	<code>define thermostat THRESHOLD sensor heating|set @ off|set @ on|2|aus:an</code><br>
	<br>
	Beispiel für reine Zustandanzeige (z. B. für Zustandsauswertung in anderen Modulen), wenn Temperatur von 30 Grad über- oder unterschritten wird:<br>
	<br>
	<code>define thermostat THRESHOLD sensor:temperature:0:30 ||||on:off</code><br>
	<br>
</ul>
	<a name="THRESHOLDset"></a>
  <b>Set </b>
  <ul>
      <li><code>set &lt;name&gt; desired &lt;value&gt;<br></code>
	  Setzt den Sollwert. Wenn kein Sollwert gesetzt ist, ist das Modul nicht aktiv.
	  </li>
	  <br>
	  <li><code>set &lt;name&gt; deactivated &lt;value&gt;<br></code>
	  Modul wird deaktiviert.
	  </li>
	  <br>
	  <li><code>set &lt;name&gt; active &lt;value&gt;<br></code>
	  Modul wird wieder aktiviert.
	  </li>
	  <br>
      <li><code>set &lt;name&gt; hysteresis &lt;value&gt;<br></code>
	  Setzt Hysterese-Wert.  
	  </li>
  </ul>
  <br>
  <a name="THRESHOLDget"></a>
  <b>Get </b>
  <ul>
      N/A
  </ul>
  <br>

  <a name="THRESHOLDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>
	
=end html_DE
=cut
