############################################################################
# fhem Modul für Impulszähler auf Basis von Arduino mit ArduCounter Sketch
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
#   Changelog:
#
#   2014-2-4    initial version
#   2014-3-12   added documentation
#	2015-02-08	renamed ACNT to ArduCounter
#

package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    

my %ArduCounter_sets = (  
    "raw"   =>  ""
);

my %ArduCounter_gets = (  
    "info"  =>  ""
);


#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub ArduCounter_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}  = "ArduCounter_Read";
    $hash->{ReadyFn} = "ArduCounter_Ready";
    $hash->{DefFn}   = "ArduCounter_Define";
    $hash->{UndefFn} = "ArduCounter_Undef";
    $hash->{GetFn}   = "ArduCounter_Get";
    $hash->{SetFn}   = "ArduCounter_Set";
    $hash->{AttrFn}  = "ArduCounter_Attr";
    $hash->{AttrList} =
        'pin.* ' .
        "interval " .
        "factor " .
        "do_not_notify:1,0 " . $readingFnAttributes;
}

#
# Define command
#########################################################################                                   #
sub ArduCounter_Define($$)
{
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "wrong syntax: define <name> ArduCounter devicename\@speed"
      if ( @a < 3 );

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    
    $hash->{buffer}     = "";
    $hash->{DeviceName} = $dev;

    my $ret = DevIo_OpenDev( $hash, 0, 0);
    return $ret;
}


sub ArduCounter_InitDev($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    $hash->{STATE} = "Initialized";
    # now talking to Arduino device is possible
    DevIo_SimpleWrite( $hash, "int 60 300\n", 0 ); # default 1 to 5 minutes

    # now that the Arduino device reported "setup done"
    # send attributes to arduino device. Just call ArduCounter_Attr again,
    # now with state "Initialized"
    while (my ($attr, $val) = each(%{$attr{$name}})) {
		if ($attr =~ "pin|del|interval") {
			Log3 $name, 3, "$name: InitDev calls Attr with $attr $val";
			ArduCounter_Attr("set", $name, $attr, $val); 
		}
    }
}


#
# undefine command when device is deleted
#########################################################################
sub ArduCounter_Undef($$)    
{                     
    my ( $hash, $arg ) = @_;       
    DevIo_CloseDev($hash);         
    return undef;                  
}    

# Wrap write to IODEV in case device is not initialized yet
#########################################################################
sub
ArduCounter_Write($$)
{
    my ( $hash, $line ) = @_;
    my $name = $hash->{NAME};
    if ($line) {
        Log3 $name, 4, "$name: Write called with $line";
    } else {
        Log3 $name, 5, "$name: Write called from timer, State = $hash->{STATE}";
        delete $hash->{TimerSet};
    }
    if ($hash->{STATE} eq "Initialized") {
        if ($hash->{WriteWaiting}) {
            DevIo_SimpleWrite( $hash, $hash->{WriteWaiting}, 0 );
            Log3 $name, 4, "$name: Write: wrote waiting commands to device";
            delete $hash->{WriteWaiting};
        }
        DevIo_SimpleWrite( $hash, "$line\n", 0 ) if ($line);
    } else {
        # Device not initialized yet - add to WaitingBuffer
        if ($line) {
            if ($hash->{WriteWaiting}) {
                $hash->{WriteWaiting} .= "$line\n";
            } else {
                $hash->{WriteWaiting} = "$line\n";
            }
        }
        if (!$hash->{TimerSet}) {
            InternalTimer(gettimeofday()+1, "ArduCounter_Write", $hash, 0);    
        }
        $hash->{TimerSet} = 1;
    }
}


# Attr command 
#########################################################################
sub
ArduCounter_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    my $hash = $defs{$name};
    Log3 $name, 4, "$name: Attr called with @_";
    if ($cmd eq "set") {
        if ($aName =~ 'pin.*') {
            if ($aName !~ 'pin([dD]?\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;
            if ($aVal =~ '(rising|falling|change)( pullup)?') {
                my $opt = "";
                if ($aVal =~ 'rising') {$opt = "r"}
                elsif ($aVal =~ 'falling') {$opt = "f"}
                elsif ($aVal =~ 'change') {$opt = "c"}
                if ($aVal =~ 'pull') {$opt .= " p"}
                ArduCounter_Write( $hash, "add $pin $opt") 
                  if ($hash->{STATE} eq "Initialized");
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }
        } elsif ($aName eq "interval") {
            if ($aVal =~ '^(\d+) (\d+)$') {
                my $min = $1;
                my $max = $2;
                if ($min < 1 || $min > 3600 || $max < $min || $max > 3600) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                ArduCounter_Write( $hash, "int $aVal")
                  if ($hash->{STATE} eq "Initialized");
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq "factor") {
            if ($aVal =~ '^(\d+)$') {
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        }
    } elsif ($cmd eq "del") {
        if ($aName =~ 'pin.*') {
            if ($aName !~ 'pin([dD]?\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;
            ArduCounter_Write( $hash, "rem $pin")
              if ($hash->{STATE} eq "Initialized");
        }
    }
    return undef;
}


# SET command
#########################################################################
sub ArduCounter_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, SetName, Rest of Set Line
    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join("", @a);
    
    if(!defined($ArduCounter_sets{$attr})) {
        my @cList = keys %ArduCounter_sets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if ($attr eq "raw") {
        DevIo_SimpleWrite( $hash, "$arg\n", 0 );
    }
        
    return undef;
}

# GET command
#########################################################################
sub ArduCounter_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, GetName
    my $name = shift @a;
    my $attr = shift @a;
    
    if(!defined($ArduCounter_gets{$attr})) {
        my @cList = keys %ArduCounter_gets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if ($attr eq "info") {
        DevIo_SimpleWrite( $hash, "show\n", 0 );
        return "sent show command to get info - watch fhem log";
    }
        
    return undef;
}


#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub ArduCounter_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my ($pin, $count, $diff, $power, $time, $factor);
    
    # read from serial device
    my $buf = DevIo_SimpleRead($hash);      
    return "" if ( !defined($buf) );

    $hash->{buffer} .= $buf;    
    my $end = chop $buf;
    Log3 $name, 5, "$name: Current buffer content: " . $hash->{buffer};

    # did we already get a full frame?
    return if ($end ne "\n");
    
    readingsBeginUpdate($hash);
    
    my @lines = split /\n/, $hash->{buffer};
    foreach my $line (@lines) {
        if ($line =~ 'R([\d]+) C([\d]+) D([\d]+) T([\d]+)')
        {
            $pin   = $1;
            $count = $2;
            $diff  = $3;
            $time  = $4;
            if (defined ($attr{$name}{factor})) {
                $factor = $attr{$name}{factor};
            } else {
                $factor = 1000;
            }
            Log3 $name, 4, "$name: Read match msg: Pin $pin count $count (diff $diff) in $time Millis";
            readingsBulkUpdate($hash, "pin$pin", sprintf ("%.3f", $count) );
			if ($time) {
				readingsBulkUpdate($hash, "power$pin", sprintf ("%.3f", $diff/$time/1000*3600*$factor) );
			}
        } elsif ($line =~ '(ArduCounter V[\d\.]+.?) Setup done') {
            readingsBulkUpdate($hash, "version", $1);
            Log3 $name, 3, "$name: Arduino reported setup done - sending init cmds";
            ArduCounter_InitDev($hash);
        } else {
            Log3 $name, 3, "$name: " . $line;
        }
    }
    readingsEndUpdate( $hash, 1 );
    $hash->{buffer} = "";
    return "";
}

#
# copied from other FHEM modules
#########################################################################
sub ArduCounter_Ready($)
{
    my ($hash) = @_;

    # try to reopen if state is disconnected
    return DevIo_OpenDev( $hash, 1, undef )
      if ( $hash->{STATE} eq "disconnected" );

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    return ( $InBytes > 0 );
}


1;


=pod
=begin html

<a name="ArduCounter"></a>
<h3>ArduCounter</h3>

<ul>
    This module implements an Interface to an Arduino based counter for pulses on any input pin of an Arduino Uno, 
	Nano or similar device like a Jeenode. The typical use case is an S0-Interface on an energy meter<br>
    Counters are configured with attributes that define which Arduino pins should count pulses and in which intervals 
    the Arduino board should report the current counts.<br>
	The Arduino sketch that works with this module uses pin change interrupts so it can efficiently count pulses 
	on all available input pins.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This module requires an Arduino uno, nano, Jeenode or similar device running the ArduCounter sketch provided with this module
        </li>
    </ul>
    <br>

    <a name="ArduCounterdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; ArduCounter &lt;device&gt;</code>
        <br>
	    &lt;device&gt; specifies the serial port to communicate with the Arduino.<br>
		
        The name of the serial-device depends on your distribution.
        You can also specify a baudrate if the device name contains the @
        character, e.g.: /dev/ttyUSB0@9600<br>
        <br>
        Example:<br>
        <br>
        <ul><code>define AC ArduCounter /dev/ttyUSB2@9600</code></ul>
    </ul>
    <br>

    <a name="ArduCounterconfiguration"></a>
    <b>Configuration of ArduCounter counters</b><br><br>
    <ul>
        Specify the pins where S0 interfaces are connected to as <code>attr AC pinX rising pullup</code> <br>
        The X in pinX can be an Arduino pin number with or without the letter D e.g. pin4, pin5, pinD4, pinD6 ...<br>
        After the pin ypu can define if rising or falling edges of the signals should be counted. The optional keyword pullup 
        activates the pullup resistor for the given Arduino Pin.
        <br><br>
        Example:<br>
        <pre>
        define AC ArduCounter /dev/ttyUSB2@9600
        attr AC factor 1000
        attr AC interval 60 300
        attr AC pinD4 rising pullup
        attr AC pinD5 rising pullup
        </pre>
        this defines two counters connected to the pins D4 and D5, each with the pullup resistor activated. 
        Impulses will be counted when the signal changes from 0 to 1.
        The ArduCounter sketch which must be loaded on the Arduino implements this using pin change interrupts,
		so all avilable input pins can be used.
    </ul>
    <br>

    <a name="ArduCounterset"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>raw</b></li> 
            send the value to the Arduino board so you can directly talk to the sketch using its commands<br>
            this is not needed for normal operation but might be useful sometimes for debugging<br>
    </ul>
    <br>
    <a name="ArduCounterget"></a>
    <b>Get-Commands</b><br>
    <ul>
        <li><b>info</b></li> 
            send the internal command <code>show</code> to the Arduino board to get current counts<br>
            this is not needed for normal operation but might be useful sometimes for debugging<br>
    </ul>
    <br>
    <a name="ArduCounterattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>pin.*</b></li> 
            Define a pin of the Arduino board as input. This attribute expects either 
            <code>rising</code>, <code>falling</code> or <code>change</code> as value, followed by 
            on optional <code>pullup</code>.<br>
        <li><b>interval</b></li> 
            Define the reporting interval after which the Arduino board should hand over the count and the time from first to last impulse per pin<br>
            This Attribute expects two numbers as value. The first is the minimal interval, the second the maximal interval. 
            Nothing is reported during the minimal interval. The Arduino board just counts and reemembers the time between the first impulse and the last impulse for each pin.
            After the minimal interval the Arduino board reports count and time for those pins where impulses were encountered. 
            If no impulses were encountered, the pin is not reported until the second interval is over. 
            The default intervals are 60 seconds as minimal time and 5 minutes as maximum interval.
        <li><b>factor</b></li> 
            Define a multiplicator for calculating the power from the impulse count and the time between the first and the last impulse
    </ul>
    <br>
    <b>Readings / Events</b><br>
    <ul>
        The module creates the following readings and events for each defined pin:
        <li><b>pin.*</b></li> 
            the current count at this pin
        <li><b>power.*</b></li> 
            the current calculated power at this pin
    </ul>
    <br>
</ul>

=end html
=cut

