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
use SetExtensions;

sub PIONEERAVRZONE_Get;
sub PIONEERAVRZONE_Set;
sub PIONEERAVRZONE_Attr;
sub PIONEERAVRZONE_Define;


###################################
sub PIONEERAVRZONE_Initialize {
    my ($hash) = @_;

    $hash->{Match} = ".+";

    $hash->{GetFn}   = "PIONEERAVRZONE_Get";
    $hash->{SetFn}   = "PIONEERAVRZONE_Set";
    $hash->{DefFn}   = "PIONEERAVRZONE_Define";
    $hash->{ParseFn} = "PIONEERAVRZONE_Parse";

    $hash->{AttrFn}   = "PIONEERAVRZONE_Attr";
    $hash->{AttrList} = "IODev " . $readingFnAttributes;
	return;
}

###################################
sub PIONEERAVRZONE_Changed {
    my ( $hash, $cmd, $value ) = @_;

    readingsBeginUpdate($hash);
    my $state = $cmd;

    if ( defined($value) && $value ne "" ) {
        readingsBulkUpdate( $hash, $cmd, $value );
        $state .= " $value";
    }
    readingsBulkUpdate( $hash, "state", $state );
    readingsEndUpdate( $hash, 1 );
    my $name = $hash->{NAME};
    Log3 $hash, 4, "PIONEERAVRZONE $name $state";
    return $state;
}

###################################

sub PIONEERAVRZONE_Get {
    my ( $hash, @a ) = @_;

    my $name   = $hash->{NAME};
    my $zone   = $hash->{helper}{ZONE};
    my $expect = ".*";
    return "get $name needs at least one argument" if ( int(@a) < 2 );
    my $cmdName = $a[1];

    my $IOhash = $hash->{IODev};
    if ( $cmdName eq "input" ) {
    }
    elsif ( !defined( $IOhash->{helper}{GETS}{$zone}{$cmdName} ) ) {
        my $gets = $IOhash->{helper}{GETS}{$zone};
        return "$name error: unknown argument $cmdName, choose one of "
          . ( join " ", sort keys %$gets );
    }

    return "Parent receiver is disabled; cached readings remain available."
      if ( PIONEERAVR_IsDisabled($IOhash) );

    my $cmd = $IOhash->{helper}{GETS}{$zone}{$cmdName};

    my $v = IOWrite( $hash, $cmd );

    return;
}

#############################
sub PIONEERAVRZONE_Set {
    my ( $hash, @a ) = @_;
    my @args = @a;
    shift @args;
    shift @args;
    my $name = $hash->{NAME};
    my $type = $hash->{TYPE};
    return "set $name needs at least one argument" if ( int(@a) < 2 );
    my $cmd = $a[1];

    my $IOhash  = $hash->{IODev};
    return "Parent receiver is disabled; set its attribute disable to 0 first."
      if ( $IOhash && PIONEERAVR_IsDisabled($IOhash) && $cmd ne "?" );
    my $zone    = $hash->{helper}{ZONE};
    my $vmax    = 0;
    my $zahl    = 0;
    my $muteStr = "";

    my @setsWithoutArg = (
        "off",    "toggle",  "volumeUp",   "volumeDown",
        "muteOn", "muteOff", "muteToggle", "inputUp",
        "inputDown"
    );

    Log3 $name, 5, "PIONEERAVRZONE $name: called function PIONEERAVR_Set($cmd)";

    return "No Argument given" if ( !defined($cmd) );

    my $inputNames = $IOhash->{helper}{INPUTNAMES};

# get all input names (preferable the aliasName) of the enabled inputs for the drop down list of "set <device> input xxx"
    my @listInputNames = ();
    for my $key ( keys %{ $IOhash->{helper}{INPUTNAMES} } ) {
        if ( defined( $IOhash->{helper}{INPUTNAMES}->{$key}{enabled} ) ) {
            if ( $IOhash->{helper}{INPUTNAMES}->{$key}{enabled} eq "1" ) {
                if ( $IOhash->{helper}{INPUTNAMES}{$key}{aliasName} ) {
                    push( @listInputNames,
                        $IOhash->{helper}{INPUTNAMES}{$key}{aliasName} );
                }
                elsif ( $IOhash->{helper}{INPUTNAMES}{$key}{name} ) {
                    push( @listInputNames,
                        $IOhash->{helper}{INPUTNAMES}{$key}{name} );
                }
            }
        }
    }
    if ( ( $zone eq "zone2" ) || ( $zone eq "zone3" ) ) {
        $muteStr = " mute:on,off,toggle";
    }
    my $list =
        "on:noArg off:noArg toggle:noArg input:"
      . join( ',', sort @listInputNames )
      . " inputUp:noArg inputDown:noArg"
      . " volumeUp:noArg volumeDown:noArg"
      . $muteStr
      . " statusRequest:noArg volume:slider,0,1,100"
      . " volumeStraight:slider,-80,1,"
      . $vmax;

    if ( $cmd eq "?" ) {
        Log3 $name, 5, "PIONEERAVRZONE set $name " . $cmd;
        return SetExtensions( $hash, $list, $name, $cmd, @args );
    }

    if ( @a == 2 ) {
        Log3 $name, 5, "PIONEERAVRZONE $name: Set $cmd";

        #### simple set commands without attributes
        #### we just "translate" the human readable command to the PioneerAvr command
        #### lookup in $IOhash->{helper}{SETS}{$zone} if the command exists and what to write to PioneerAvr
        if ( grep { $_ eq $cmd } @setsWithoutArg ) {
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd (setsWithoutArg)";
            my $setCmd = $IOhash->{helper}{SETS}{$zone}{$cmd};
            my $v      = IOWrite( $hash, $setCmd );
            Log3 $hash, 5,
              "PIONEERAVR $name: Set_IOwrite($zone ... $cmd ): $setCmd";
            return;

            ### Power on
            ### Command: PO
            ### according to "Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx" (notice) we need to send <cr> and
            ### wait 100ms before the first command is accepted by the Pioneer AVR
        }
        elsif ( $cmd eq "on" ) {
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
            my $setCmd = "";
            IOWrite( $hash, $setCmd );

            # PIONEERAVR's shared send timer preserves the wake-up interval
            # without blocking other devices in the FHEM main loop.

            if ( $zone eq "zone2" ) {
                $setCmd = "APO";
            }
            elsif ( $zone eq "zone3" ) {
                $setCmd = "BPO";
            }
            elsif ( $zone eq "hdZone" ) {
                $setCmd = "ZEO";
            }
            IOWrite( $hash, $setCmd );
            Log3 $hash, 5, "PIONEERAVR $name: Set_IOwrite: $setCmd";
            return;

            # statusRequest: execute all "get" commands	to update the readings
        }
        elsif ( $cmd eq "statusRequest" ) {
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
            for my $key ( keys %{ $IOhash->{helper}{GETS}{$zone} } ) {
                IOWrite( $hash, $IOhash->{helper}{GETS}->{$zone}->{$key} );
            }
            return;
        }
        #### commands with argument(s)
    }
    elsif ( @a > 2 ) {
        my $arg = $a[2];
        ####Input (all available Inputs of the Pioneer Avr -> see 'get $name loadInputNames')
        ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        if ( $cmd eq "input" ) {

            Log3 $name, 5, "PIONEERAVRZONE $name: set $cmd " . dq($arg);
            for my $key ( keys %{ $IOhash->{helper}{INPUTNAMES} } ) {
                if ( $IOhash->{helper}{INPUTNAMES}->{$key}{aliasName} eq $arg )
                {
                    if ( $zone eq "zone2" ) {
                        IOWrite( $hash, sprintf "%02dZS", $key );
                    }
                    elsif ( $zone eq "zone3" ) {
                        IOWrite( $hash, sprintf "%02dZT", $key );
                    }
                    elsif ( $zone eq "hdZone" ) {
                        IOWrite( $hash, sprintf "%02dZEA", $key );
                    }
                }
                elsif ( $IOhash->{helper}{INPUTNAMES}->{$key}{name} eq $arg ) {
                    if ( $zone eq "zone2" ) {
                        IOWrite( $hash, sprintf "%02dZS", $key );
                    }
                    elsif ( $zone eq "zone3" ) {
                        IOWrite( $hash, sprintf "%02dZT", $key );
                    }
                    elsif ( $zone eq "hdZone" ) {
                        IOWrite( $hash, sprintf "%02dZEA", $key );
                    }
                }
            }

            return;
            #####VolumeStraight (-80.5 - 12) in dB
            ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        }
        elsif ( $cmd eq "volumeStraight" ) {
            $zahl = 80.5 + $arg;
            if ( $zone eq "zone2" ) {
                IOWrite( $hash, sprintf "%02dZV", $zahl );
            }
            elsif ( $zone eq "zone3" ) {
                IOWrite( $hash, sprintf "%02dYV", $zahl );
            }
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "volumeStraight", $arg );
            readingsBulkUpdate( $hash, "volume", sprintf "%.0f",
                ( $a[2] + 80 ) / 0.81 );
            readingsEndUpdate( $hash, 1 );
            return;
            ####Volume (0 - 100) in %
            ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        }
        elsif ( $cmd eq "volume" ) {
            $zahl = sprintf "%.0f", $arg * 0.81;
            if ( $zone eq "zone2" ) {
                IOWrite( $hash, sprintf "%02dZV", $zahl );
            }
            elsif ( $zone eq "zone3" ) {
                IOWrite( $hash, sprintf "%02dYV", $zahl );
            }
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "volumeStraight", $zahl - 80 );
            readingsBulkUpdate( $hash, "volume", sprintf "%.0f", $a[2] );
            readingsEndUpdate( $hash, 1 );
            return;
            ####Mute (on|off|toggle)
            ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        }
        elsif ( $cmd eq "mute" ) {
            if ( $arg eq "on" ) {
                IOWrite( $hash, $IOhash->{helper}{SETS}{$zone}{muteOn} );
                readingsSingleUpdate( $hash, "mute", "on", 1 );
            }
            elsif ( $arg eq "off" ) {
                IOWrite( $hash, $IOhash->{helper}{SETS}{$zone}{muteOff} );
                readingsSingleUpdate( $hash, "mute", "off", 1 );
            }
            elsif ( $arg eq "toggle" ) {
                IOWrite( $hash, $IOhash->{helper}{SETS}{$zone}{muteToggle} );
            }
            return;
        }
        else {
            return SetExtensions( $hash, $list, $name, $cmd, @args );
        }
    }
    else {
        return SetExtensions( $hash, $list, $name, $cmd, @args );
    }
    return;
}

#############################
sub PIONEERAVRZONE_Parse {

# we are called from dispatch() from the PIONEERAVR device
# we never come here if $msg does not match $hash->{MATCH} in the first place
# NOTE: we will update all matching readings for all (logical) devices, not just the first!

    my ( $IOhash, $msg ) =
      @_;    # IOhash points to the PIONEERAVR, not to the PIONEERAVRZONE

    my @matches;
    my $name  = $IOhash->{NAME};
    my $state = '';

    #Debug "Trying to find a match for \"" . escapeLogLine($msg) ."\"";
    # walk over all clients
    for my $d ( keys %defs ) {
        my $hash = $defs{$d};
        if ( $hash->{TYPE} eq "PIONEERAVRZONE" && $hash->{IODev} eq $IOhash ) {
            my $zone = $hash->{helper}{ZONE};
            readingsBeginUpdate($hash);

            # zone2
            if ( $zone eq "zone2" ) {

                # volume zone2
                # ZVXX
                # XX 00 ... 81 -> -81dB ... 0dB
                if ( $msg =~ m/^ZV(\d\d)$/ ) {
                    Log3 $name, 5,
                        "PIONEERAVRZONE $name: "
                      . dq($msg)
                      . " interpreted as: Zone2 - New volume = "
                      . $1
                      . " (raw volume data).";
                    readingsBulkUpdate( $hash, "volumeStraight", $1 - 81 );
                    readingsBulkUpdate( $hash, "volume", sprintf "%.0f",
                        $1 / 0.81 );
                    push @matches, $d;

                    # Mute zone2
                    # Z2MUTX
                    # X = 0: Mute on; X = 1: Mute off
                }
                elsif ( $msg =~ m/^Z2MUT(\d)$/ ) {
                    if ($1) {
                        readingsBulkUpdate( $hash, "mute", "off" );
                        Log3 $name, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone2 - Mute off.";
                    }
                    else {
                        readingsBulkUpdate( $hash, "mute", "on" );
                        Log3 $name, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone2 - Mute on.";
                    }
                    push @matches, $d;

                    # Input zone2
                    # Z2FXX
                    # XX -> input number 00 ... 49
                }
                elsif ( $msg =~ m/^Z2F(\d\d)$/ ) {
                    my $inputNr = $1;
                    Log3 $hash, 5,
                        "PIONEERAVRZONE $name: "
                      . dq($msg)
                      . " interpreted as: Zone2 - Input is set to inputNr: $inputNr ";

                    if ( $IOhash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} ne
                        "" )
                    {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone2 - Input aliasName for input $inputNr is "
                          . $IOhash->{helper}{INPUTNAMES}{$inputNr}{aliasName};
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{aliasName}
                        );
                    }
                    elsif (
                        $IOhash->{helper}{INPUTNAMES}->{$inputNr}{name} ne "" )
                    {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone2 - Input Name for input $inputNr is "
                          . $IOhash->{helper}{INPUTNAMES}{$inputNr}{name};
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{name} );
                    }
                    else {
                        readingsBulkUpdate( $hash, "input", $msg );
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone2 - InputName: can't find Name for input $inputNr";
                    }
                    push @matches, $d;

                    # Power zone2
                    # APRX
                    # X = 0: Power on; X = 1: Power off
                }
                elsif ( $msg =~ m/^APR(0|1)$/ ) {
                    if ( $1 eq '0' ) {
                        readingsBulkUpdate( $hash, "power", "on" );
                        $state = "on";
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone2 - Power: on";
                    }
                    elsif ( $1 eq '1' ) {
                        readingsBulkUpdate( $hash, "power", "off" );
                        $state = "off";
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone2 - Power: off";
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
            }
            elsif ( $zone eq "zone3" ) {

                # volume zone3
                # YVXX
                # XX 00 ... 81 -> -81dB ... 0dB
                if ( $msg =~ m/^YV(\d\d)$/ ) {
                    Log3 $name, 5,
                        "PIONEERAVRZONE $name: "
                      . dq($msg)
                      . " interpreted as: Zone3 - New volume = "
                      . $1
                      . " (raw volume data).";
                    readingsBulkUpdate( $hash, "volumeStraight", $1 - 81 );
                    readingsBulkUpdate( $hash, "volume", sprintf "%.0f",
                        $1 / 0.81 );
                    push @matches, $d;

                    # Mute zone3
                    # Z3MUTX
                    # X = 0: Mute on; X = 1: Mute off
                }
                elsif ( $msg =~ m/^Z3MUT(\d)$/ ) {
                    if ($1) {
                        readingsBulkUpdate( $hash, "mute", "off" );
                        Log3 $name, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone3 - Mute off.";
                    }
                    else {
                        readingsBulkUpdate( $hash, "mute", "on" );
                        Log3 $name, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone3 - Mute on.";
                    }
                    push @matches, $d;

                    # Input zone3
                    # Z3FXX
                    # XX -> input number 00 ... 49
                }
                elsif ( $msg =~ m/^Z3F(\d\d)$/ ) {
                    my $inputNr = $1;
                    Log3 $hash, 5,
                        "PIONEERAVRZONE $name: "
                      . dq($msg)
                      . " interpreted as: Zone3 - Input is set to inputNr: $inputNr ";
                    if (
                        defined(
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{aliasName}
                        )
                      )
                    {
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{aliasName}
                        );
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone3 - Input aliasName for input $inputNr is "
                          . $hash->{helper}{INPUTNAMES}{$inputNr}{aliasName};
                    }
                    elsif (
                        defined(
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{name}
                        )
                      )
                    {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone3 - Input Name for input $inputNr is "
                          . $hash->{helper}{INPUTNAMES}{$inputNr}{name};
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$inputNr}{name} );
                    }
                    else {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone3 - InputName: can't find Name for input $inputNr";
                        readingsBulkUpdate( $hash, "input", $msg );
                    }
                    push @matches, $d;

                    # Power zone3
                    # BPRX
                    # X = 0: Power on; X = 1: Power off
                }
                elsif ( $msg =~ m/^BPR(0|1)$/ ) {
                    if ( $1 eq '0' ) {
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone3 - Power: on";
                        readingsBulkUpdate( $hash, "power", "on" );
                        $state = "on";
                    }
                    elsif ( $1 eq '1' ) {
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: Zone3 - Power: off";
                        readingsBulkUpdate( $hash, "power", "off" );
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
            }
            elsif ( $zone eq "hdZone" ) {

                # Input hdZone
                # ZEAXX
                # XX -> input number 00 ... 49
                if ( $msg =~ m/^ZEA(\d\d)$/ ) {
                    my $inputNr = $1;
                    Log3 $hash, 5,
                        "PIONEERAVRZONE $name: "
                      . dq($msg)
                      . " interpreted as: hdZone - Input is set to inputNr: $inputNr ";
                    if (
                        defined(
                            $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName}
                        )
                      )
                    {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: hdZone - Input aliasName for input $inputNr is "
                          . $IOhash->{helper}{INPUTNAMES}{$inputNr}{aliasName};
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$1}{aliasName} );
                    }
                    elsif (
                        defined( $IOhash->{helper}{INPUTNAMES}->{$1}{name} ) )
                    {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: hdZone - Input Name for input $inputNr is "
                          . $IOhash->{helper}{INPUTNAMES}{$inputNr}{name};
                        readingsBulkUpdate( $hash, "input",
                            $IOhash->{helper}{INPUTNAMES}->{$1}{name} );
                    }
                    else {
                        Log3 $hash, 5,
"PIONEERAVRZONE $name: Zone3 - InputName: can't find Name for input $inputNr";
                        readingsBulkUpdate( $hash, "input", $msg );
                    }
                    push @matches, $d;

                    # Power hdZone
                    # ZEPX
                    # X = 0: Power on; X = 1: Power off
                }
                elsif ( $msg =~ m/^ZEP(0|1)$/ ) {
                    if ( $1 eq '0' ) {
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: hdZone - Power: on";
                        readingsBulkUpdate( $hash, "power", "on" );
                        $state = "on";
                    }
                    elsif ( $1 eq '1' ) {
                        Log3 $hash, 5,
                            "PIONEERAVRZONE $name: "
                          . dq($msg)
                          . " interpreted as: hdZone - Power: off";
                        readingsBulkUpdate( $hash, "power", "off" );
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
            readingsEndUpdate( $hash, 1 );

        }
    }
    return @matches if (@matches);
    return "UNDEFINED PIONEERAVRZONE message1 $msg";
}

#####################################
sub PIONEERAVRZONE_Attr {

    my @a    = @_;
    my $hash = $defs{ $a[1] };

    return;
}

#############################
sub PIONEERAVRZONE_Define {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );

    return
      "Usage: define <name> PIONEERAVRZONE <zone>  ... wrong paramter count: "
      . int(@a)
      if ( int(@a) != 3 );
    my $name = $a[0];

    AssignIoPort($hash);

    my $IOhash = $hash->{IODev};
    if ( !defined($IOhash) ) {
        my $err = "PIONEERAVRZONE $name error: no I/O device.";
        Log3 $hash, 1, $err;
        return $err;
    }

    #Parameter (Zone)
    my $zone = "";
    if ( $a[2] =~ m/^(zone\d|hdZone)$/ ) {
        $zone = $a[2];
    }
    else {
        my $err =
            "PIONEERAVRZONE define $name error: unknown Zone "
          . dq( $a[2] )
          . " -> must be one of [zone2|zone3|hdZone] (I/O device is "
          . $IOhash->{NAME}
          . "). Usage: define <name> PIONEERAVRZONE <zone>";
        Log3 $hash, 1, $err;
        return $err;
    }

    # for autocreate: we store here a pointer of defined devices
    # so we can check if the device exists
    $modules{PIONEERAVRZONE}{defptr}{$zone} = $hash;

    if ( !defined( $IOhash->{helper}{SETS}{$zone} ) ) {
        my $err =
"PIONEERAVRZONE define $name error: unknown Zone $zone (I/O device is "
          . $IOhash->{NAME} . ").";
        Log3 $hash, 1, $err;
        return $err;
    }

    $hash->{helper}{ZONE} = $zone;

    # set default attributes
    unless ( exists( $attr{$name}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:mute:input';
    }
    unless ( exists( $attr{$name}{devStateIcon} ) ) {
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_STOP:on absent:rc_RED';
    }
    return;
}
#####################################
#Function to show special chars (e.g. \n\r) in logs
#sub
#dq($)
#{
#	my ($s)= @_;
#	$s= "<nothing>" unless(defined($s));
#	return "\"" . escapeLogLine($s) . "\"";
#}

1;

=pod
=encoding utf8
=item device
=item summary control of zones on PIONEER AV receivers via network or serial connection
=item summary_DE Steuerung der Zonen eines PIONEER AV-Receivers über Netzwerk oder seriell
=begin html

<a id="PIONEERAVRZONE" name="PIONEERAVRZONE"></a>
<h3>PIONEERAVRZONE</h3>
<ul>
  PIONEERAVRZONE controls an additional zone of a receiver through a
  <a href="#PIONEERAVR">PIONEERAVR</a> I/O device. Supported zone identifiers
  are <code>zone2</code>, <code>zone3</code> and <code>hdZone</code>. Available
  commands depend on the selected zone and on the receiver model.
  <br><br>

  <a id="PIONEERAVRZONE-define" name="PIONEERAVRZONEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVRZONE &lt;zone2|zone3|hdZone&gt;</code>
    <br><br>
    The device normally uses the most recently defined PIONEERAVR device as
    its I/O device. Set <code>IODev</code> explicitly if more than one receiver
    exists. Zone devices may also be created automatically when PIONEERAVR
    receives the first message for a previously undefined zone.
    <br><br>
    Example:
    <ul>
      <code>define VSX923Zone2 PIONEERAVRZONE zone2</code><br>
      <code>attr VSX923Zone2 IODev VSX923</code>
    </ul>
  </ul>
  <br>

  <p>When the parent PIONEERAVR device has <code>disable=1</code>,
zone controls and fresh queries are rejected. Cached readings retain their
last-known values. Configure disable on the parent receiver.</p>

  <a id="PIONEERAVRZONE-set" name="PIONEERAVRZONEset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;value&gt;]</code>
    <br><br>
    <a id="PIONEERAVRZONE-set-off"></a>
    <li><b>off</b> - Switches the zone to standby.</li>
    <a id="PIONEERAVRZONE-set-on"></a>
    <li><b>on</b> - Switches the zone on.</li>
    <a id="PIONEERAVRZONE-set-toggle"></a>
    <li><b>toggle</b> - Toggles the zone power state.</li>
    <a id="PIONEERAVRZONE-set-input"></a>
    <li><b>input &lt;input name&gt;</b> - Selects an enabled input. The list uses receiver input aliases when available and is refreshed by <code>set &lt;PIONEERAVR&gt; statusRequest</code> or <code>get &lt;PIONEERAVR&gt; loadInputNames</code>.</li>
    <a id="PIONEERAVRZONE-set-inputUp"></a>
    <li><b>inputUp</b> - Selects the next zone input.</li>
    <a id="PIONEERAVRZONE-set-inputDown"></a>
    <li><b>inputDown</b> - Selects the previous zone input.</li>
    <a id="PIONEERAVRZONE-set-statusRequest"></a>
    <li><b>statusRequest</b> - Requests all status values supported for this zone and updates the corresponding readings.</li>
    <a id="PIONEERAVRZONE-set-volume"></a>
    <li><b>volume &lt;0 ... 100&gt;</b> - Sets the zone volume as a percentage. Implemented for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-set-volumeUp"></a>
    <li><b>volumeUp</b> - Raises the zone volume by 1 dB. Implemented for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-set-volumeDown"></a>
    <li><b>volumeDown</b> - Lowers the zone volume by 1 dB. Implemented for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-set-volumeStraight"></a>
    <li><b>volumeStraight &lt;-80 ... 0&gt;</b> - Sets the zone volume in dB using the receiver display scale. Implemented for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-set-mute"></a>
    <li><b>mute &lt;on|off|toggle&gt;</b> - Controls zone muting. Available for <code>zone2</code> and <code>zone3</code>.</li>
    <li><a href="#setExtensions">SetExtensions</a> are supported.</li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-get" name="PIONEERAVRZONEget"></a>
  <b>Get</b>
  <ul>
    Get commands send an asynchronous status request. The result appears in
    the corresponding reading after the receiver replies.
    <br><br>
    <a id="PIONEERAVRZONE-get-input"></a>
    <li><b>input</b> - Available for <code>zone2</code>, <code>zone3</code> and <code>hdZone</code>.</li>
    <a id="PIONEERAVRZONE-get-power"></a>
    <li><b>power</b> - Available for <code>zone2</code>, <code>zone3</code> and <code>hdZone</code>.</li>
    <a id="PIONEERAVRZONE-get-volume"></a>
    <li><b>volume</b> - Available for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-get-mute"></a>
    <li><b>mute</b> - Available for <code>zone2</code> and <code>zone3</code>.</li>
    <a id="PIONEERAVRZONE-get-bass"></a>
    <li><b>bass</b> - Available for <code>zone2</code>.</li>
    <a id="PIONEERAVRZONE-get-treble"></a>
    <li><b>treble</b> - Available for <code>zone2</code>.</li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-attr" name="PIONEERAVRZONEattr"></a>
  <b>Attributes</b>
  <ul>
    <a id="PIONEERAVRZONE-attr-IODev"></a>
    <li><b>IODev</b> - PIONEERAVR device used to communicate with the physical receiver. Example: <code>attr VSX923Zone2 IODev VSX923</code>.</li>
    <a id="PIONEERAVRZONE-attr-verbose"></a>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-readings"></a>
  <b>Readings</b>
<p>The current implementation uses different conversions when setting and receiving zone volume. Reported values may therefore differ from the requested value. Received raw values 00...81 map to -81...0 in volumeStraight; raw 00 denotes MIN on the receiver.</p>
  <ul>
    <li><b>power</b> - Zone power state.</li>
    <li><b>input</b> - Selected zone input.</li>
    <li><b>volume</b> - Zone volume as a percentage, where supported.</li>
    <li><b>volumeStraight</b> - Zone volume on the receiver display scale, where supported.</li>
    <li><b>mute</b> - Zone mute state, where supported.</li>
    <li><b>bass</b>, <b>treble</b> - Requests exist for zone2, but their replies are currently not parsed into zone readings.</li>
    <li><b>state</b> - Last parsed zone state or command value.</li>
  </ul>
</ul>

=end html
=begin html_DE

<a id="PIONEERAVRZONE" name="PIONEERAVRZONE"></a>
<h3>PIONEERAVRZONE</h3>
<ul>
  PIONEERAVRZONE steuert eine zusätzliche Zone eines Receivers über ein
  <a href="#PIONEERAVR">PIONEERAVR</a>-I/O-Device. Unterstützte
  Zonenbezeichnungen sind <code>zone2</code>, <code>zone3</code> und
  <code>hdZone</code>. Die verfügbaren Befehle hängen von der gewählten Zone
  und vom Receiver-Modell ab.
  <br><br>

  <a id="PIONEERAVRZONE-define" name="PIONEERAVRZONEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVRZONE &lt;zone2|zone3|hdZone&gt;</code>
    <br><br>
    Das Device verwendet normalerweise das zuletzt definierte PIONEERAVR-Device
    als I/O-Device. Wenn mehrere Receiver existieren, sollte <code>IODev</code>
    ausdrücklich gesetzt werden. Ein Zonen-Device kann auch automatisch
    entstehen, wenn PIONEERAVR erstmals eine Nachricht einer noch nicht
    definierten Zone empfängt.
    <br><br>
    Beispiel:
    <ul>
      <code>define VSX923Zone2 PIONEERAVRZONE zone2</code><br>
      <code>attr VSX923Zone2 IODev VSX923</code>
    </ul>
  </ul>
  <br>

  <p>Ist am übergeordneten PIONEERAVR-Gerät <code>disable=1</code> gesetzt,
werden Zonenbefehle und neue Abfragen abgewiesen. Gespeicherte Readings behalten
ihre zuletzt bekannten Werte. disable wird am übergeordneten Receiver gesetzt.</p>

  <a id="PIONEERAVRZONE-set" name="PIONEERAVRZONEset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;Befehl&gt; [&lt;Wert&gt;]</code>
    <br><br>
    <a id="PIONEERAVRZONE-set-off"></a>
    <li><b>off</b> - Schaltet die Zone in den Standby-Modus.</li>
    <a id="PIONEERAVRZONE-set-on"></a>
    <li><b>on</b> - Schaltet die Zone ein.</li>
    <a id="PIONEERAVRZONE-set-toggle"></a>
    <li><b>toggle</b> - Wechselt den Ein-/Aus-Zustand der Zone.</li>
    <a id="PIONEERAVRZONE-set-input"></a>
    <li><b>input &lt;Eingangsname&gt;</b> - Wählt einen aktivierten Eingang. Die Liste verwendet vorhandene Eingangsaliasnamen und wird mit <code>set &lt;PIONEERAVR&gt; statusRequest</code> oder <code>get &lt;PIONEERAVR&gt; loadInputNames</code> aktualisiert.</li>
    <a id="PIONEERAVRZONE-set-inputUp"></a>
    <li><b>inputUp</b> - Wählt den nächsten Eingang der Zone.</li>
    <a id="PIONEERAVRZONE-set-inputDown"></a>
    <li><b>inputDown</b> - Wählt den vorherigen Eingang der Zone.</li>
    <a id="PIONEERAVRZONE-set-statusRequest"></a>
    <li><b>statusRequest</b> - Fragt alle für diese Zone unterstützten Statuswerte ab und aktualisiert die zugehörigen Readings.</li>
    <a id="PIONEERAVRZONE-set-volume"></a>
    <li><b>volume &lt;0 ... 100&gt;</b> - Stellt die Zonenlautstärke in Prozent ein. Für <code>zone2</code> und <code>zone3</code> implementiert.</li>
    <a id="PIONEERAVRZONE-set-volumeUp"></a>
    <li><b>volumeUp</b> - Erhöht die Zonenlautstärke um 1 dB. Für <code>zone2</code> und <code>zone3</code> implementiert.</li>
    <a id="PIONEERAVRZONE-set-volumeDown"></a>
    <li><b>volumeDown</b> - Verringert die Zonenlautstärke um 1 dB. Für <code>zone2</code> und <code>zone3</code> implementiert.</li>
    <a id="PIONEERAVRZONE-set-volumeStraight"></a>
    <li><b>volumeStraight &lt;-80 ... 0&gt;</b> - Stellt die Zonenlautstärke in dB auf der am Receiver-Display verwendeten Skala ein. Für <code>zone2</code> und <code>zone3</code> implementiert.</li>
    <a id="PIONEERAVRZONE-set-mute"></a>
    <li><b>mute &lt;on|off|toggle&gt;</b> - Steuert die Stummschaltung. Für <code>zone2</code> und <code>zone3</code> verfügbar.</li>
    <li><a href="#setExtensions">SetExtensions</a> werden unterstützt.</li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-get" name="PIONEERAVRZONEget"></a>
  <b>Get</b>
  <ul>
    Get-Befehle senden eine asynchrone Statusabfrage. Das Ergebnis erscheint
    nach der Antwort des Receivers im entsprechenden Reading.
    <br><br>
    <a id="PIONEERAVRZONE-get-input"></a>
    <li><b>input</b> - Für <code>zone2</code>, <code>zone3</code> und <code>hdZone</code> verfügbar.</li>
    <a id="PIONEERAVRZONE-get-power"></a>
    <li><b>power</b> - Für <code>zone2</code>, <code>zone3</code> und <code>hdZone</code> verfügbar.</li>
    <a id="PIONEERAVRZONE-get-volume"></a>
    <li><b>volume</b> - Für <code>zone2</code> und <code>zone3</code> verfügbar.</li>
    <a id="PIONEERAVRZONE-get-mute"></a>
    <li><b>mute</b> - Für <code>zone2</code> und <code>zone3</code> verfügbar.</li>
    <a id="PIONEERAVRZONE-get-bass"></a>
    <li><b>bass</b> - Für <code>zone2</code> verfügbar.</li>
    <a id="PIONEERAVRZONE-get-treble"></a>
    <li><b>treble</b> - Für <code>zone2</code> verfügbar.</li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-attr" name="PIONEERAVRZONEattr"></a>
  <b>Attribute</b>
  <ul>
    <a id="PIONEERAVRZONE-attr-IODev"></a>
    <li><b>IODev</b> - PIONEERAVR-Device für die Kommunikation mit dem physischen Receiver. Beispiel: <code>attr VSX923Zone2 IODev VSX923</code>.</li>
    <a id="PIONEERAVRZONE-attr-verbose"></a>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br>

  <a id="PIONEERAVRZONE-readings"></a>
  <b>Readings</b>
<p>Die aktuelle Implementierung verwendet beim Setzen und Empfangen der Zonenlautstärke unterschiedliche Umrechnungen. Zurückgemeldete Werte können daher vom Sollwert abweichen. Empfangene Rohwerte 00...81 werden in volumeStraight auf -81...0 abgebildet; Rohwert 00 bedeutet am Receiver MIN.</p>
  <ul>
    <li><b>power</b> - Ein-/Aus-Zustand der Zone.</li>
    <li><b>input</b> - Gewählter Eingang der Zone.</li>
    <li><b>volume</b> - Zonenlautstärke in Prozent, soweit unterstützt.</li>
    <li><b>volumeStraight</b> - Zonenlautstärke auf der Display-Skala des Receivers, soweit unterstützt.</li>
    <li><b>mute</b> - Stummschaltung der Zone, soweit unterstützt.</li>
    <li><b>bass</b>, <b>treble</b> - Für zone2 abfragbar; die Antworten werden derzeit nicht in Zonen-Readings umgesetzt.</li>
    <li><b>state</b> - Zuletzt ausgewerteter Zustand oder Befehlswert der Zone.</li>
  </ul>
</ul>

=end html_DE
=cut
