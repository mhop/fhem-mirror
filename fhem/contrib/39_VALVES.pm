# $Id$
####################################################################################################
#
#   39_VALVES.pm
#
#   originally developed by Florian Duesterwald 
#
#   heating valves average, with some adjust and ignore options
#   http://forum.fhem.de/index.php/topic,24658.0.html
#   refer to mail a.T. duesterwald do T info if necessary
#
#   thanks to cwagner for testing and a great documentation of the module:
#   http://www.fhemwiki.de/wiki/Raumbedarfsabh%C3%A4ngige_Heizungssteuerung
#   http://www.fhemwiki.de/wiki/VALVES
#   thanks to stromer-12 for fixing attr probs
#
#   This file is free contribution and not part of fhem.
#
#   Fhem is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 2 of the License, or
#   (at your option) any later version.
#
#   Fhem is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package FHEM::Automation::VALVES;    ## no critic 'Package declaration'

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use List::Util qw(sum);
use Scalar::Util qw(looks_like_number);

use GPUtils qw(GP_Import);

BEGIN {

    # Import from main context
    GP_Import(
        qw(
            defs
            init_done
            readingFnAttributes
            readingsSingleUpdate
            readingsBeginUpdate readingsEndUpdate
            readingsBulkUpdate readingsBulkUpdateIfChanged
            setReadingsVal
            AttrVal InternalVal
            ReadingsVal ReadingsTimestamp
            Log3
            addToDevAttrList
            parseParams
            InternalTimer RemoveInternalTimer
            CommandSet CommandDeleteReading CommandDeleteAttr
            devspec2array
            IsDisabled
        )
    );
}

sub ::VALVES_Initialize { goto &Initialize }

sub Initialize {
    my $hash = shift // return;
    $hash->{DefFn}   = \&Define;
    $hash->{UndefFn} = \&Undefine;
    $hash->{SetFn}   = \&Set;
    $hash->{GetFn}   = \&Get;
    $hash->{AttrFn}  = \&Attr;
    my $attrList = "valvesPollInterval:1,2,3,4,5,6,7,8,9,10,11,15,20,25,30,45,60,90,120,240,480,900" . " valvesDeviceList valvesDeviceReading valvesIgnoreLowest valvesIgnoreHighest valvesIgnoreDeviceList" . " valvesPriorityDeviceList valvesInitialDelay";

    #my $i = 0;
    $hash->{AttrList} = "disable:0,1 disabledForIntervals $readingFnAttributes $attrList";
    return;
}

sub Define {
    my $hash = shift // return;
    my $def  = shift // return;
    my ( $name, $TYPE, $tomuch ) = split m{\s+}xms, $def;

    return 'Wrong syntax: use define <name> VALVES' if defined $tomuch || !defined $TYPE;
    Log3( $name, 4, "VALVES $name has been defined" );
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'state', 'initialized' );
    readingsBulkUpdate( $hash, 'busy',  0 + gettimeofday() );    #waiting for attr check
    readingsEndUpdate( $hash, $init_done );

    #first run after 61 seconds, wait for other devices
    InternalTimer( gettimeofday() + AttrVal( $name, 'valvesInitialDelay', 61 ), \&VALVES_GetUpdate, $hash, 0 ) if !$init_done;
    VALVES_GetUpdate($hash)                                                                                    if $init_done && !AttrVal( $name, 'disable', 0 );
    return;
}

sub Undefine {
    my $hash = shift // return;
    RemoveInternalTimer($hash);
    return;
}

sub Get {
    my ( $hash, @arr ) = @_;
    my $name = $hash->{NAME};
    my $get  = $arr[1];

    if ( $get eq 'attrHelp' ) { return _valvesAttribs( 'help', $arr[2] ); }

    my @stmgets = keys %{ $hash->{READINGS} };
    $get = '?' if $get ne '?' && !( grep {m{$get}x} ( @stmgets, 'attrHelp', 'state', 'html' ) );

    if ( $get ne '?' ) {
        return $get . ': ' . ReadingsVal( $name, $get, 'Unknown at line ' . __LINE__ );
    }
    my $usage = "Unknown argument $get, choose one of";
    for (@stmgets) {
        $usage .= " " . $_ . ":noArg";
    }
    $usage .= " attrHelp:";
    for ( _valvesAttribs( 'keys', '' ) ) {
        $usage .= ",$_";
    }
    return $usage;
}

sub Set {
    my ( $hash, @arr ) = @_;
    my $name = shift @arr;
    return 'no set value specified' if !@arr;
    if ( $arr[0] eq 'reset' ) {
        Log3( $name, 4, "VALVES set $name " . join( q{ }, @arr ) );
        for ( keys( %{ $hash->{READINGS} } ) ) {
            CommandDeleteReading( undef, "$name $_" );
        }
        return;
    }

    my $setList = 'reset:noArg';
    return "Unknown argument $arr[0], choose one of $setList";
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    #special attr valvesDeviceList #valvesDeviceList: addToAttrList
    if ( $attrName eq 'valvesDeviceList' ) {
        if ( length($attrVal) > 2 ) {
            Log3( $name, 4, "VALVES $name attribute-value [$attrName] = $attrVal changed" );
            for ( devspec2array($attrVal) ) {    # split m{,}x,$attrVal ) {
                                                 #addToDevAttrList("$name","valves".$_."Gewichtung",'VALVES');
                addToDevAttrList( "$name", "valves" . $_ . "Weighting", 'VALVES' );
            }
            VALVES_GetUpdate($hash) if $init_done && !IsDisabled($name);
        }
        else {
            Log3( $name, 3, "VALVES $name attribute-value [$attrName] = $attrVal wrong, string min length 2" ) if $attrVal;
        }
        return;
    }

    #validate special attr valvesPollInterval
    if ( $attrName eq 'valvesPollInterval' ) {
        if ( $attrVal >= 1 && $attrVal <= 900 ) {
            Log3( $name, 4, "VALVES $name attribute-value [$attrName] = $attrVal changed" );
            VALVES_GetUpdate($hash) if $init_done && !AttrVal( $name, 'disable', 0 );
        }
        else {
            Log3( $name, 3, "VALVES $name attribute-value [$attrName] = $attrVal wrong, use seconds >1 as float (max 900)" );
            return "$attrVal is not a number or within allowed range!" if $init_done;
        }
        return;
    }

    if ( $attrName eq 'valvesDeviceReading' ) {
        delete $hash->{helper}->{valvesDeviceReading};
        if ( length($attrVal) > 2 ) {
            my ( $unnamedParams, $namedParams ) = parseParams($attrVal);
            $hash->{helper}->{valvesDeviceReading} = $namedParams;
            $hash->{helper}->{valvesDeviceReading}->{valvesDeviceReading} = $unnamedParams->[0] if defined $unnamedParams->[0];
            Log3( $name, 4, "VALVES $name attribute-value [$attrName] = $attrVal changed" );
            VALVES_GetUpdate($hash) if $init_done;
        }
        else {
            Log3( $name, 3, "VALVES $name attribute-value [$attrName] = $attrVal wrong, string min length 2" ) if $attrVal;
        }
        return;
    }

    if ( $attrName eq 'disable' ) {
        RemoveInternalTimer($hash)                                    if $cmd ne 'del';
        InternalTimer( gettimeofday(), \&VALVES_GetUpdate, $hash, 0 ) if $cmd eq 'del' || !$attrVal && $init_done;
        return;
    }

    if ( $attrName eq 'valvesInitialDelay' ) {
        RemoveInternalTimer($hash) if !$init_done;
        return                     if AttrVal( $name, 'disable', 0 );
        if ( !looks_like_number($attrVal) ) {
            return "$attrVal is not a number!" if $init_done;
            $attrVal = 61;
        }
        InternalTimer( gettimeofday() + $attrVal, \&VALVES_GetUpdate, $hash, 0 ) if !$init_done;
    }

    #other attribs
    if ( $attrName =~ m{\Avalves\d+}x ) {
        if ( !defined $attrVal ) {
            CommandDeleteAttr( undef, "$name attrName" );
            Log3( $name, 4, "VALVES $name: attribute [$attrName] deleted" );
        }
    }
    else {
        Log3( $name, 4, "VALVES $name: attribute-value [$attrName] = $attrVal changed" ) if $attrVal;
    }
    return;
}

sub VALVES_GetUpdate {
    my $hash               = shift // return;
    my $name               = $hash->{NAME};
    my $valvesPollInterval = AttrVal( $name, 'valvesPollInterval', 10 );
    if ( $valvesPollInterval ne 'off' ) {
        RemoveInternalTimer($hash);
        $valvesPollInterval = 10                                                            if !looks_like_number($valvesPollInterval);
        InternalTimer( gettimeofday() + $valvesPollInterval, \&VALVES_GetUpdate, $hash, 0 ) if !AttrVal( $name, 'disable', 0 );
    }
    return if IsDisabled($name);

    if ( AttrVal( $name, 'valvesDeviceList', 'none' ) eq 'none' ) {
        readingsSingleUpdate( $hash, 'state', 'missing attr valvesDeviceList', 1 );
        RemoveInternalTimer($hash);
        return;
    }

    #check all attr at first loop
    if ( ReadingsVal( $name, 'busy', 'done' ) ne 'done' ) {    #"waiting for attr check"
        if ( ( gettimeofday() - AttrVal( $name, 'valvesInitialDelay', 61 ) ) > ReadingsVal( $name, 'busy', 0 ) ) {
            for ( devspec2array( AttrVal( $name, 'valvesDeviceList', '' ) ) ) {    # split m{,}x, AttrVal($name,'valvesDeviceList','') ) {
                                                                                   #addToDevAttrList("$name",'valves'.$_.'Gewichtung','VALVES');
                addToDevAttrList( "$name", 'valves' . $_ . 'Weighting', 'VALVES' );
            }
            CommandDeleteReading( undef, "$name busy" );
        }
    }
    my ( %valveDetail, %valveShort, @raw_average, $pos, $prio, @prios );
    my $valvesIgnoreDeviceList = AttrVal( $name, 'valvesIgnoreDeviceList', '0' );
    for my $dev ( devspec2array( AttrVal( $name, 'valvesDeviceList', '' ) ) ) {

        #check ignorelist
        next if $valvesIgnoreDeviceList =~ m/$dev/x;

        #get val
        my $posRead = $hash->{helper}->{valvesDeviceReading}->{ InternalVal( $dev, 'TYPE', 'none' ) } // $hash->{helper}->{valvesDeviceReading}->{valvesDeviceReading} // 'valveposition';
        $pos = ReadingsVal( $dev, $posRead, 'err' );
        if ( !defined $pos || $pos eq 'err' || $pos eq 'lime-protection' ) {
            Log3( $name, 4, "VALVES $name " . $_ . " [$pos] DeviceReading not present" );
            next;
        }

        #$pos =~ s/%//x;
        $pos = $pos =~ m{(-?\d+(\.\d+)?)}x ? $1 : -1;
        push @raw_average, $pos;

        #calc prio
        $prio = AttrVal( $name, 'valves' . $dev . 'Weighting', AttrVal( $name, 'valves' . $dev . 'Gewichtung', 1 ) );

        #fill hash
        $valveDetail{$dev} = [ ( $pos, ReadingsTimestamp( $dev, $posRead, 0 ) ) ];
        $valveShort{$dev}  = $pos * $prio;
    }

    #ignore highest/lowest N values
    my @sorted = sort { $valveShort{$a} <=> $valveShort{$b} } keys %valveShort;

    if ( !@sorted ) {
        readingsSingleUpdate( $hash, 'state', 'attr valvesDeviceList is empty', 1 );
        return;
    }
    my $valvesIgnoreLowest = AttrVal( $name, 'valvesIgnoreLowest', 0 );
    while ( $valvesIgnoreLowest > 0 ) {
        shift @sorted;
        $valvesIgnoreLowest--;
    }
    my $valvesIgnoreHighest = AttrVal( $name, 'valvesIgnoreHighest', 0 );
    while ( $valvesIgnoreHighest > 0 ) {
        pop @sorted;
        $valvesIgnoreHighest--;
    }

    return if !@sorted;

    #fill readings, bypass usual way to conserve valveposition timestamps
    for (@sorted) {
        setReadingsVal( $hash, 'valve_' . $_, $valveShort{$_}, $valveDetail{$_}[1] );
        push @prios, AttrVal( $name, 'valves' . $_ . 'Weighting', AttrVal( $name, 'valves' . $_ . 'Gewichtung', 1 ) );
    }

    #set min and max from sorted
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, 'valve_min', $valveShort{ $sorted[0] },  1 );
    readingsBulkUpdateIfChanged( $hash, 'valve_max', $valveShort{ $sorted[-1] }, 1 );

    my $valvesPriorityDeviceList = AttrVal( $name, 'valvesPriorityDeviceList', '0' );
    for my $dev ( keys %valveDetail ) {
        if ( !exists $valveShort{$dev} ) {
            $valveShort{$dev} = 'ignored';
        }

        #create double hash entry for prio dev
        if ( $valvesPriorityDeviceList =~ m/$dev/x ) {
            $valveShort{ $dev . 'P' } = $valveShort{$dev};
            push @sorted, $dev . 'P';
            push @prios,  AttrVal( $name, 'valves' . $dev . 'Weighting', AttrVal( $name, 'valves' . $dev . 'Gewichtung', 1 ) );
        }
        readingsBulkUpdate( $hash, 'valveDetail_' . $dev, 'pos:' . $valveDetail{$dev}[0] . ' calc:' . $valveShort{$dev} . ( $valvesPriorityDeviceList =~ m/$dev/x ? '-priority' : '' ) . ' time:' . $valveDetail{$dev}[1], 0 );
    }
    my $state;
    for (@sorted) {
        $state += $valveShort{$_};
    }
    my $corr = sum(@prios) / @prios;
    $state = sprintf "%.0f", $state / @sorted / $corr;
    if ( ReadingsVal( $name, 'state', 'err' ) ne $state ) {
        readingsBulkUpdate( $hash, 'valve_average', $state, 1 );
        readingsBulkUpdate( $hash, 'state',         $state, 1 );
    }
    $state = 0;
    for (@raw_average) {
        $state += $_;
    }
    $state = sprintf "%.0f", $state / @raw_average;
    readingsBulkUpdateIfChanged( $hash, 'raw_average', $state, 1 );

    readingsEndUpdate( $hash, 1 );

    return;
}

sub _valvesAttribs {

    #usage: _valvesAttribs("type","stmVarName")
    # "keys" || "default" || "type" || "help"  ,<keyname>
    my ( $type, $reqKey ) = @_;
    my %attribs = (
        "valvesInitialDelay"           => [ ( "61",            "int",    "Waiting time after FHEM start (or Define) before first calculation will be started",                                         "Zeitintervall nach FHEM-Start oder Dev.-Define bevor die Berechnung gestartet wird" ) ],
        "valvesPollInterval"           => [ ( "10",            "int",    "Zeitintervall nach dem FHEM die Daten versucht zu aktualisieren",                                                            "Zeitintervall nach dem FHEM die Daten versucht zu aktualisieren" ) ],
        "valvesDeviceList"             => [ ( "none",          "string", "Liste aller Heizungsthermostate mit Komma getrennt ohne Leerzeichen",                                                        "Liste aller Heizungsthermostate mit Komma getrennt ohne Leerzeichen" ) ],
        "valvesDeviceReading"          => [ ( "valveposition", "string", "Reading das die Ventilposition zeigt, default: valveposition",                                                               "Reading das die Ventilposition zeigt, default: valveposition" ) ],
        "valvesIgnoreLowest"           => [ ( "0",             "int",    "ignoriere die niedrigsten N Thermostate",                                                                                    "ignoriere die niedrigsten N Thermostate" ) ],
        "valvesIgnoreHighest"          => [ ( "0",             "int",    "ignoriere die höchsten N Thermostate",                                                                                       "ignoriere die höchsten N Thermostate" ) ],
        "valvesIgnoreDeviceList"       => [ ( "0",             "string", "Ignoriere diese Devicenamen",                                                                                                "Ignoriere diese Devicenamen" ) ],
        "valvesPriorityDeviceList"     => [ ( "0",             "string", "Thermostate in dieser Liste werden doppelt gezählt",                                                                         "Thermostate in dieser Liste werden doppelt gezählt" ) ],
        "valves<Devicename>Gewichtung" => [ ( "1",             "float",  'Individual weighting factor for each thermostate. May e.g. be used to compensate hydraulic problems in the heating system.', "Für jedes Thermostat kann ein individueller Gewichtungsfaktor multipliziert werden. So kann zB ein schlechter hydraulischer Abgleich berücksichtigt werden" ) ],
        "valves<Devicename>Weighting"  => [ ( '1',             'float',  'Individual weighting factor for each thermostate. May e.g. be used to compensate hydraulic problems in the heating system.', "Für jedes Thermostat kann ein individueller Gewichtungsfaktor multipliziert werden. So kann zB ein schlechter hydraulischer Abgleich berücksichtigt werden" ) ],
        disable                        => [ ( "0",             "int",    'Stop calculations and freeze values',                                                                                        "Berechnung anhalten und einfrieren" ) ],
    );
    return keys %attribs        if $type eq 'keys';
    return $attribs{$reqKey}[0] if $type eq 'default';
    return $attribs{$reqKey}[1] if $type eq 'type';
    if ( $type eq 'description' ) {
        return $attribs{$reqKey}[2] if AttrVal( 'global', 'language', 'EN' ) ne 'DE';
        return $attribs{$reqKey}[3];
    }
    if ( $type eq 'help' ) {
        return "attrHelp for " . $reqKey . ":\n default:" . $attribs{$reqKey}[0] . " type:" . $attribs{$reqKey}[1] . " \ndescription:" . $attribs{$reqKey}[2];
    }
    return '_ attribs?';
}

1;

__END__

=pod
=encoding utf8
=item helper
=item summary generate a virtual valve position based on multiple thermostat devices
=item summary_DE Generiert eine virtuelle Ventilöffnung aus eine Mehrzahl von Heizungsventilen
=begin html

<a id="VALVES"></a>
<h3>VALVES</h3>
<ul>
  German docu is available in <a href="http://www.fhemwiki.de/wiki/VALVES">FHEM Wiki</a>.<br>
  <a id="VALVES-define"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; VALVES</code><br>
    <br>
    Defines a virtual device for VALVES calculations based on multiple thermostat devices<br>
  </ul>
  <ul>
    How to use VALVES after define:
    <li>First tell VALVES, which real valve devices shall be used for calculation as described in <a href="#VALVES-attr-valvesDeviceList">valvesDeviceList</a> (mandatory!).</li>
    If that works you should be able to (optionally) set additional <a href="#VALVES-attr-valvesDevicenameWeighting">valves&lt;Devicename&gt;Weighting</a> values.
    <li>Set appropriate <a href="#VALVES-attr-valvesDeviceReading">valvesDeviceReading</a> (most likely will be necessary)</li>
    <li>(Optionally) exclude not needed devices using <a href="#VALVES-attr-valvesIgnoreDeviceList">valvesIgnoreDeviceList</a></li>
    <li>(Optionally) set values in <a href="#VALVES-attr-valvesIgnoreLowest">valvesIgnoreLowest</a> and/or <a href="#VALVES-attr-valvesIgnoreHighest">valvesIgnoreHighest</a></li>
    <li>(Optionally) set emphasis on single devices by setting individual <a href="#VALVES-attr-valvesDevicenameWeighting">valves&lt;Devicename&gt;Weighting</a> and/or including them in <a href="#VALVES-attr-valvesIgnoreLowest">valvesPriorityDeviceList</a> values</li>
  </ul>
  <a id="VALVES-readings"></a>
  <ul>
    How VALVE calculates and handles readings:
    <li>After FHEM startup, VALVES will wait <a href="#VALVES-attr-valvesInitialDelay">valvesInitialDelay</a> and then will do a calculation every <a href="#VALVES-attr-valvesPollInterval">valvesPollInterval</a> seconds using the follwoing scheme:
    <ul>
      <li>Get a list of valve value and timestamp for each device (not ignored by name)</li>
      <li>Delete lowest and highest valves/devices from this list</li>
      <li>recalculate valve positions according to weighting settings</li>
      <li>Double priority devices in the list</li>
      <li>Derive readings (main and debug)</li>
    </ul>
    </li>
    <li>Main readings (triggering when changed) are <i>valve_min</i>, <i>valve_max</i>, <i>valve_average</i>, <i>raw_average</i> and <i>state</i>.</li>
    <li>Debug readings <i>valve&lt;Devicename&gt</i> shows the calculated virtual valve position, <i>valveDetail_&lt;Devicename&gt</i> the real and calculated position and the timestamp of the original reading.</li>
  </ul>
  <a id="VALVES-set"></a>
  <h4>Set </h4>
  <ul>
    <a id="VALVES-set-reset"></a>
    <li><b>reset</b></li>
    deletes already calculated readings and starts from the scratch
  </ul>
  <a id="VALVES-get"></a>
  <h4>Get</h4>
  <ul>
    <a id="VALVES-get-reading"></a>
    <li><b>&lt;reading&gt;</b></li>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br>
    Any of the actual reading values.<br><br>
    <a id="VALVES-get-attrHelp"></a>
    <li><b>attrHelp &lt;attribute&gt;</b></li>
    <code>get &lt;name&gt; attrHelp &lt;attribute&gt;</code><br>
    Get help text to named attribute.<br>
  </ul>
  <a id="VALVES-attr"></a>
  <h4>Attributes</h4>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="VALVES-attr-valvesInitialDelay"></a>
    <li><b>valvesInitialDelay &lt;delay&gt;</b><br>
        Waiting time after FHEM start (or define) before first calculation will be started. Defaults to 61.</li>
    <a id="VALVES-attr-valvesPollInterval"></a>
    <li><b>valvesPollInterval &lt;interval&gt;</b><br>
        Polling interval (in seconds, between 1 to 900) between each attempt to update values. Defaults for compability reasons to 10.</li>
    <a id="VALVES-attr-valvesDeviceList"></a>
    <li><b>valvesDeviceList &lt;devspec&gt;</b><br>
        <a href="#devspec">devspec</a> is as usual, e.g. use a comma-separated list (no spaces allowed!) of all thermostate devices to make part of calculations</li>
    <a id="VALVES-attr-valvesDeviceReading"></a>
    <li><b>valvesDeviceReading [&lt;positionreading&gt]  ;</b><br>
        Reading to base calculations upon, default: valveposition. You may set a key value list as follows as well with device-TYPE and reading name pairs like e.g.:<br>
        <code>attr &lt;device&gt valvesDeviceReading CUL_HM=ValvePosition ZWave=reportedState</code></li>
    <a id="VALVES-attr-valvesIgnoreLowest"></a>
    <li><b>valvesIgnoreLowest &lt;number&gt;</b><br>
        ignore the &lt;number&gt; of the thermostate devices with (actual) lowest valve values.</li>
    <a id="VALVES-attr-valvesIgnoreHighest"></a>
    <li><b>valvesIgnoreHighest &lt;number&gt;</b><br>
        ignore the &lt;number&gt; of the thermostate devices with (actual) highest valve values.</li>
    <a id="VALVES-attr-valvesIgnoreDeviceList"></a>
    <li><b>valvesIgnoreDeviceList &lt;deviceA,deviceB,[....]&gt;</b><br>
        ignore the listed thermostate devices (comma separated).</li>
    <a id="VALVES-attr-valvesPriorityDeviceList"></a>
    <li><b>valvesPriorityDeviceList &lt;regex&gt;</b><br>
        Thermostates matching the regex will be doubled in the calculation process</li>
    <a id="VALVES-attr-valvesDevicenameWeighting" data-pattern="valves.*Weighting"></a>
    <li><b>valves&lt;Devicename&gtWeighting &lt;float value&gt;</b><br>
        Individual weighting factor (lfoat value) for each thermostate. May e.g. be used to compensate hydraulic problems in the heating system</li>
  </ul>
</ul>

=end html
