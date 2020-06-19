# $Id$
##############################################################################
#
#     70_HYDRAWISE.pm
#     An FHEM Perl module for controlling a Hunter Hydrawise irigation controller.
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

use 5.012;
use strict;
use warnings;

use Time::HiRes     qw(gettimeofday);
use JSON            qw(decode_json encode_json);
use Encode          qw(encode_utf8 decode_utf8);
use Time::Piece;
use Time::Local;

# use Data::Dumper;
use HttpUtils;

my %sets = (
    stop         => "",
    stopall      => "noArg",
    run          => "",
    runall       => "",
    suspend      => "",
    suspendall   => "",
    renewContext => "noArg",
    renewRelays  => "noArg",
);

my %gets = ( "help" => "noArg", );

###################################
sub HYDRAWISE_Initialize {
    my $hash = shift;

    Log3 $hash, 5, 'HYDRAWISE_Initialize: Entering';

    %{$hash} = (
        GetFn    => 'HYDRAWISE_Get',
        SetFn    => 'HYDRAWISE_Set',
        DefFn    => 'HYDRAWISE_Define',
        UndefFn  => 'HYDRAWISE_Undefine',
        AttrList => "disable:0,1 $readingFnAttributes",
    );

    return;
}

###################################
sub HYDRAWISE_Define {
    my ( $hash, $def ) = @_;

    my @a    = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_Define()";

    if ( @a < 3 ) {
        my $msg =
          "Wrong syntax: define <name> HYDRAWISE <api_key> [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "HYDRAWISE";

    my $api_key = $a[2];
    $hash->{helper}{APIKEY} = $api_key;

    # use interval of 300 sec if not defined
    my $interval = $a[3] || 300;
    $hash->{INTERVAL} = $interval;

    unless ( defined( AttrVal( $name, "webCmd", undef ) ) ) {
        $attr{$name}{webCmd} = 'stopall renewContext renewRelays';
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "HYDRAWISE_GetStatus", $hash, 1 );

    return;
}

###################################
sub HYDRAWISE_Undefine {
    my ( $hash, $arg ) = @_;

    my $name = $hash->{NAME};

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_Undefine()";

    # De-Authenticate
    HYDRAWISE_SendCommand( $hash, "deauthenticate" );

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

#####################################
sub HYDRAWISE_GetStatus {
    my ( $hash, $update ) = @_;

    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "HYDRAWISE_GetStatus", $hash,
        0 );

    return if ( AttrVal( $name, "disable", 0 ) == 1 );

    # check device availability
    if ( !$update ) {
        HYDRAWISE_SendCommand( $hash, "state" );
    }

    return;
}

###################################
sub HYDRAWISE_Get {
    my ( $hash, @a ) = @_;

    my $name = $hash->{NAME};
    my $what;

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_Get()";

    return "argument is missing" if ( @a < 2 );

    $what = $a[1];

    return _HYDRAWISE_help() if ( $what =~ /^(help)$/ );        
    return "Unknown argument $what, choose one of help:noArg";
}

sub _HYDRAWISE_help {
    return << 'EOT';
-----------------------------------------------------------------------------------------------------
|renewcontext | Refresh readings customerdetail                                                     |
-----------------------------------------------------------------------------------------------------
|renewRelays  | Refresh readings statusdetails                                                      |
-----------------------------------------------------------------------------------------------------
|run          | Run zone for a period of time. 2 Parameters: "relay_id" "time_in_seconds"           |
-----------------------------------------------------------------------------------------------------
|runall       | Run all zones for a period of time. 1 Parameter: "time_in_seconds"                  |
-----------------------------------------------------------------------------------------------------
|stop         | Stop zone. 1 Parameter: "relay_id"                                                  |
-----------------------------------------------------------------------------------------------------
|stopall      | Stop all currently running zones.                                                   |
-----------------------------------------------------------------------------------------------------
|suspend      | Suspend zone for a period of time. 3 Parameters: "relay_id" "DD.MM.YYYY" "HH24:MI"  |
-----------------------------------------------------------------------------------------------------
|suspendall   | Suspend all zones for a period of time. 2 Parameters: "DD.MM.YYYY" "HH24:MI"        |
-----------------------------------------------------------------------------------------------------
EOT
}

###################################
sub HYDRAWISE_Set {
    my ( $hash, $name, $cmd, @a ) = @_;

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_Set()";

    return "\"sets\" needs at least one parameter" if ( !$cmd );

    # stopall ()
    if ( $cmd eq "stopall" ) {
        Log3 $name, 2, "HYDRAWISE set $name " . $cmd . $a[0];

        HYDRAWISE_SendCommand( $hash, "stopall" );
        readingsSingleUpdate( $hash, "state", "Set_stopall", 1 );
    }

    # stop (relay_id)
    elsif ( $cmd eq "stop" ) {
        Log3 $name, 2, "HYDRAWISE set $name " . $cmd . " " . $a[0];

        return "Expected: \"<relay_id>\"" if ( !defined( $a[0] ) );

        HYDRAWISE_SendCommand( $hash, "stop", $a[0] );
        readingsSingleUpdate( $hash, "state", "Set_stop", 1 );
    }

    # runall (custom)
    elsif ( $cmd eq "runall" ) {
        Log3 $name, 2, "HYDRAWISE set $name " . $cmd . " " . $a[0];

        return "Expected: \"<time_in_seconds>\"" if ( !defined( $a[0] ) );

        HYDRAWISE_SendCommand( $hash, "runall", "$a[0]" );
        readingsSingleUpdate( $hash, "state", "Set_runall", 1 );
    }

    # run (relay_id, custom)
    elsif ( $cmd eq "run" ) {
        Log3 $name, 2,
          "HYDRAWISE set $name " . $cmd . " " . $a[0] . " " . $a[1];

        return "Expected: \"<relay_id> <time_in_seconds>\""
          if ( !defined( $a[0] ) || !defined( $a[1] ) );

        HYDRAWISE_SendCommand( $hash, "run", "$a[0] $a[1]" );
        readingsSingleUpdate( $hash, "state", "Set_run", 1 );
    }

    # suspendall (date time)
    elsif ( $cmd eq "suspendall" ) {
        Log3 $name, 2,
          "HYDRAWISE set $name " . $cmd . " " . $a[0] . " " . $a[1];
        return "Expected: \"<DD.MM.YYYY> <HH24:MI>\""
          if ( !defined( $a[0] ) || !defined( $a[1] ) );

        my ( $day, $month, $year ) = split /\./, $a[0];
        my ( $hour, $min ) = split /\:/, $a[1];
        my $time = timelocal( 00, $min, $hour, $day, $month - 1, $year - 1900 );

        HYDRAWISE_SendCommand( $hash, "suspendall", $time );
        readingsSingleUpdate( $hash, "state", "Set_suspendall", 1 );
    }

    # suspend (relay_id, date, time)
    elsif ( $cmd eq "suspend" ) {
        Log3 $name, 2,
          "HYDRAWISE set $name " . $cmd . $a[0] . " " . $a[1] . " " . $a[2];
        return "Expected: \"<relay_id> <DD.MM.YYYY> <HH24:MI>\""
          if ( !defined( $a[0] ) || !defined( $a[1] ) || !defined( $a[2] ) );

        my ( $day, $month, $year ) = split /\./, $a[1];
        my ( $hour, $min ) = split /\:/, $a[2];
        my $time = timelocal( 00, $min, $hour, $day, $month - 1, $year - 1900 );

        HYDRAWISE_SendCommand( $hash, "suspend", "$a[0] $time" );
        readingsSingleUpdate( $hash, "state", "Set_suspend", 1 );
    }

    # renewContext
    elsif ( $cmd eq "renewContext" ) {
        Log3 $name, 2, "HYDRAWISE set $name " . $cmd;

        HYDRAWISE_SendCommand( $hash, "authenticate" );
    }

    # relays
    elsif ( $cmd eq "renewRelays" ) {
        Log3 $name, 2, "HYDRAWISE set $name " . $cmd;

        HYDRAWISE_SendCommand( $hash, "relays" );
    }

    # return usage hint
    else {
        return "Unknown argument $cmd, choose one of "
          . join( " ",
            map { "$_" . ( $sets{$_} ? ":$sets{$_}" : "" ) } keys %sets );
    }

    return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub HYDRAWISE_SendCommand {
    my ( $hash, $service, $type ) = @_;

    my $name      = $hash->{NAME};
    my $api_key   = $hash->{helper}{APIKEY};
    my $timestamp = gettimeofday();
    my $timeout   = 30;
    my $data;
    my $method = "GET";

    Log3 $name, 5, "HYDRAWISE $name: called function HYDRAWISE_SendCommand()";

    my $URL_STATUSSCHEDULE =
      "https://api.hydrawise.com/api/v1/statusschedule.php?api_key=" . $api_key;
    my $URL_CUSTOMERDETAILS =
      "https://api.hydrawise.com/api/v1/customerdetails.php?api_key="
      . $api_key;
    my $URL_SETZONE =
      "https://api.hydrawise.com/api/v1/setzone.php?api_key=$api_key";
    my $URL    = "";
    my $ACTION = "";

    Log3 $name, 4, "HYDRAWISE $name: REQ $service";

    if ( $service eq "authenticate" ) {
        $ACTION = 1;
        $URL    = $URL_CUSTOMERDETAILS;
    }
    elsif ( $service eq "relays" ) {
        $ACTION = 1;
        $URL    = $URL_STATUSSCHEDULE;
    }
    elsif ( $service eq "stopall" ) {
        $ACTION = 2;
        $URL    = $URL_SETZONE . "&action=stopall";
    }
    elsif ( $service eq "stop" ) {
        $ACTION = 2;
        $URL    = $URL_SETZONE . "&action=stop&relay_id=$type";
    }
    elsif ( $service eq "runall" ) {
        $ACTION = 2;
        $URL    = $URL_SETZONE . "&action=runall&period_id=999&custom=$type";
    }
    elsif ( $service eq "run" ) {
        $ACTION = 2;
        my @a = split( "[ \t][ \t]*", $type );
        $URL = $URL_SETZONE
          . "&action=run&period_id=999&relay_id=$a[0]&custom=$a[1]";
    }
    elsif ( $service eq "suspendall" ) {
        $ACTION = 2;
        $URL = $URL_SETZONE . "&action=suspendall&period_id=999&custom=$type";
    }
    elsif ( $service eq "suspend" ) {
        $ACTION = 2;
        my @a = split( "[ \t][ \t]*", $type );
        $URL = $URL_SETZONE
          . "&action=suspend&period_id=999&relay_id=$a[0]&custom=$a[1]";
    }
    elsif ( $service eq "state" ) {
        $ACTION = 3;
    }
    else {
        # $URL .= $api_key;
    }

    # send request via HTTP-GET method
    Log3 $name, 5, "HYDRAWISE $name: $method $URL (" . urlDecode($data) . ")"
      if ( defined($data) );
    Log3 $name, 5, "HYDRAWISE $name: $method $URL"
      if ( !defined($data) );

    if ( defined($type) && $type eq "blocking" ) {
        my ( $err, $data ) = HttpUtils_BlockingGet(
            {
                url        => $URL,
                timeout    => 15,
                noshutdown => 1,
                data       => $data,
                method     => $method,
                hash       => $hash,
                service    => $service,
                timestamp  => $timestamp,
            }
        );
        return $data;
    }
    else {
        if ( $ACTION eq "3" ) {
            HttpUtils_NonblockingGet(
                {
                    url        => $URL_STATUSSCHEDULE,
                    timeout    => $timeout,
                    noshutdown => 1,
                    data       => $data,
                    method     => $method,
                    hash       => $hash,
                    service    => $service,
                    timestamp  => $timestamp,
                    callback   => \&HYDRAWISE_ReceiveCommand,
                }
            );
            HttpUtils_NonblockingGet(
                {
                    url        => $URL_CUSTOMERDETAILS,
                    timeout    => $timeout,
                    noshutdown => 1,
                    data       => $data,
                    method     => $method,
                    hash       => $hash,
                    service    => $service,
                    timestamp  => $timestamp,
                    callback   => \&HYDRAWISE_ReceiveCommand,
                }
            );
        }
        elsif ( $ACTION eq "2" ) {
            HttpUtils_NonblockingGet(
                {
                    url        => $URL,
                    timeout    => $timeout,
                    noshutdown => 1,
                    data       => $data,
                    method     => $method,
                    hash       => $hash,
                    service    => $service,
                    timestamp  => $timestamp,
                }
            );
        }
        elsif ( $ACTION eq "1" ) {
            HttpUtils_NonblockingGet(
                {
                    url        => $URL,
                    timeout    => $timeout,
                    noshutdown => 1,
                    data       => $data,
                    method     => $method,
                    hash       => $hash,
                    service    => $service,
                    timestamp  => $timestamp,
                    callback   => \&HYDRAWISE_ReceiveCommand,
                }
            );
        }
    }

    return;
}

###################################
sub HYDRAWISE_ReceiveCommand {
    my ( $param, $err, $data, $do_trigger ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $state    = ReadingsVal( $name, "state", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );

    my $rc = ( $param->{buf} ) ? $param->{buf} : $param;
    my $return;

    Log3 $name, 5,
"HYDRAWISE $name: called function HYDRAWISE_ReceiveCommand() rc: $rc err: $err data: $data ";

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {
        $presence = "absent";
        $state    = "off";

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "HYDRAWISE $name:$service RCV $err";
        }
        else {
            Log3 $name, 4, "HYDRAWISE $name:$service/$cmd RCV $err";
        }

        readingsBulkUpdateIfChanged( $hash, "presence", $presence );
        readingsBulkUpdateIfChanged( $hash, "state",    $state );

        # keep last state
        #HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "state", "Error" );
    }

    # data received
    elsif ($data) {
        $presence = "present";
        $state    = "on";

        # Set reading for presence
        #
        readingsSingleUpdate( $hash, "presence", $presence, 1 );
        #HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "presence", "$presence" );

        # Set reading for state
        #
        readingsSingleUpdate( $hash, "state", $state, 1 );
        #HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "state", "$state" );

        if ( !defined($cmd) ) {
            Log3 $name, 4, "HYDRAWISE $name: RCV $service";
        }
        else {
            Log3 $name, 4, "HYDRAWISE $name: RCV $service/$cmd";
        }

        if ( $data ne "" ) {
            if ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 4,
                      "HYDRAWISE $name: RES $service - DATA: $data";
                }
                else {
                    Log3 $name, 4, "HYDRAWISE $name: RES $service/$cmd - $data";
                }
                $return = decode_json( encode_utf8($data) );

                #print "Decoded return: ".Dumper($return);
                #Debug $return;
            }
            else {
                Log3 $name, 4, "HYDRAWISE $name: RES ERROR $service\n" . $data;
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5, "HYDRAWISE $name: RES ERROR $service\n$data";
                }
                else {
                    Log3 $name, 5,
                      "HYDRAWISE $name: RES ERROR $service/$cmd\n$data";
                }
                return;
            }
        }

        #######################
        # process return data
        #

        # state

        if ( $service eq "state" or $service eq "longpollState" ) {
            if ( ref($return) eq "HASH" && !defined($cmd) ) {

                # controllers
                if ($return->{customer_id}){
                  HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "customer_id", $return->{customer_id} );
                }
                
                if ($return->{controller_id}){
                  HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "cur_controller_id", $return->{controller_id} );
                }
                
                if ($return->{current_controller}){
                  HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "cur_controller_name", $return->{current_controller} );
                }

                if ( ref( $return->{controllers} ) eq "ARRAY"
                    && scalar( @{ $return->{controllers} } ) > 0 )
                {
                    my $lnnumer = 1;
                    my $last_contact;
                    HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                        "controller_counts",
                        scalar( @{ $return->{controllers} } ) );
                    for my $controllers ( @{ $return->{controllers} } ) {
                        HYDRAWISE_ReadingsBulkUpdateIfChanged(
                            $hash,
                            "ct" . $lnnumer . "_controller_id",
                            $controllers->{controller_id}
                        );
                        $last_contact =
                          localtime( $controllers->{last_contact} )
                          ->strftime('%F %T');
                        HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                            "ct" . $lnnumer . "_last_contact",
                            $last_contact );
                        HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                            "ct" . $lnnumer . "_controller_name",
                            $controllers->{name} );
                        HYDRAWISE_ReadingsBulkUpdateIfChanged(
                            $hash,
                            "ct" . $lnnumer . "_controller_message",
                            $controllers->{status}
                        );
                        HYDRAWISE_ReadingsBulkUpdateIfChanged(
                            $hash,
                            "ct" . $lnnumer . "_serial_number",
                            $controllers->{serial_number}
                        );
                        $lnnumer++;
                    }
                }

                # relays

                if ( ref( $return->{relays} ) eq "ARRAY"
                    and scalar( @{ $return->{relays} } ) > 0 )
                {
                    HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                        "relay_counts", scalar( @{ $return->{relays} } ) );
                    for my $relays ( @{ $return->{relays} } ) {
                        Log3 $name, 5,"HYDRAWISE $name: $relays->{relay} $relays->{relay_id}";


#readingsSingleUpdate( $hash, "rl" . $relays->{relay} . "_relay", $relays->{relay}, $do_trigger );
#readingsSingleUpdate( $hash, "rl" . $relays->{relay} . "_relay_id", $relays->{relay_id}, $do_trigger );
#readingsSingleUpdate( $hash, "rl" . $relays->{relay} . "_name", $relays->{name}, $do_trigger );
#readingsSingleUpdate( $hash, "rl" . $relays->{relay} . "_next", $relays->{timestr}, $do_trigger );
#readingsSingleUpdate( $hash, "rl" . $relays->{relay} . "_run_minutes", $relays->{run}, $do_trigger );


                        HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                            "rl" . $relays->{relay} . "_relay",
                            $relays->{relay} );
                        HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                            "rl" . $relays->{relay} . "_relay_id",
                            $relays->{relay_id} );
                        HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                            "rl" . $relays->{relay} . "_name",
                            $relays->{name} );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_time",  			$relays->{time});
                        HYDRAWISE_ReadingsBulkUpdateIfChanged(
                            $hash,
                            "rl" . $relays->{relay} . "_next",
                            HYDRAWISE_GetDay( $hash, $relays->{timestr} )
                        );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_period",  		HYDRAWISE_GetDuration($hash,$relays->{period}));
                        HYDRAWISE_ReadingsBulkUpdateIfChanged(
                            $hash,
                            "rl" . $relays->{relay} . "_run_minutes",
                            $relays->{run} / 60
                        );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_nicetime",   		$relays->{nicetime});
                    }
                }
            }

            readingsEndUpdate( $hash, 1 );

            HYDRAWISE_CheckLongpoll($hash) if ( $service eq "state" );

            HYDRAWISE_SendCommand( $hash, "longpollState" )
              if ( $service eq "longpollState" );

        }

        # relays
        elsif ( $service eq "relays" ) {

            if ( ref( $return->{relays} ) eq "ARRAY"
                and scalar( @{ $return->{relays} } ) > 0 )
            {
                readingsBeginUpdate ($hash);
                HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "relay_counts",
                    scalar( @{ $return->{relays} } ) );
                for my $relays ( @{ $return->{relays} } ) {
                    Log3 $name, 5,
                      "HYDRAWISE $name: $relays->{relay} $relays->{relay_id}";

                    HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                        "rl" . $relays->{relay} . "_relay",
                        $relays->{relay} );
                    HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                        "rl" . $relays->{relay} . "_relay_id",
                        $relays->{relay_id} );
                    HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash,
                        "rl" . $relays->{relay} . "_name",
                        $relays->{name} );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_time",  			$relays->{time});
                    HYDRAWISE_ReadingsBulkUpdateIfChanged(
                        $hash,
                        "rl" . $relays->{relay} . "_next",
                        HYDRAWISE_GetDay( $hash, $relays->{timestr} )
                    );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_period",  		HYDRAWISE_GetDuration($hash,$relays->{period}));
                    HYDRAWISE_ReadingsBulkUpdateIfChanged(
                        $hash,
                        "rl" . $relays->{relay} . "_run_minutes",
                        $relays->{run} / 60
                    );

#HYDRAWISE_ReadingsBulkUpdateIfChanged($hash, "rl".$relays->{relay}."_nicetime",   		$relays->{nicetime});
                }
            }
            readingsEndUpdate( $hash, 1 );
        }

        # authenticate
        elsif ( $service eq "authenticate" ) {
            if ( ref($return) eq "HASH" ) {
                HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "controller_id",
                    $return->{controller_id} );
                HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "customer_id",
                    $return->{customer_id} );
                HYDRAWISE_ReadingsBulkUpdateIfChanged( $hash, "user_id",
                    $return->{user_id} );

                readingsEndUpdate( $hash, 1 );

                # new context received - reload state
                HYDRAWISE_SendCommand( $hash, "state" );
                HYDRAWISE_TriggerFullDataUpdate($hash);

                # re-execute previous command
                if ( defined($cmd) ) {
                    if ( $cmd =~ /(\w+)\/(\w+)/ ) {
                        HYDRAWISE_SendCommand( $hash, $1, $2 );
                    }
                    else {
                        HYDRAWISE_SendCommand( $hash, $cmd );
                    }
                }
            }
        }

        # all other command results
        else {
            Log3 $name, 2,
"HYDRAWISE $name: ERROR: method to handle response of $service not implemented";
        }

    }
    else {
        if ( $rc =~ /401/ ) {
            Log3 $name, 4,
              "HYDRAWISE $name: authentication context invalidated";
            if ( $service =~ /deleteAlert|setCalendar/ ) {
                HYDRAWISE_SendCommand( $hash, "authenticate", "$service" );
            }
            elsif ( $service eq "state" and defined($cmd) ) {
                HYDRAWISE_SendCommand( $hash, "authenticate", "$service/$cmd" );
            }
            else {
                readingsSingleUpdate( $hash, "contextId", "", 1 );
            }
            $hash->{LONGPOLL} = 0 if ( $service eq "longpollState" );
        }

    }

    return;
}

sub HYDRAWISE_CheckLongpoll {
    my $hash = shift;
    my $name = $hash->{NAME};

    return if ( AttrVal( $name, "disable", 0 ) == 1 );

    if ( !defined( $hash->{LONGPOLL} ) || time() - $hash->{LONGPOLL} > 3600 ) {
        Log3 $name, 4, "HYDRAWISE $name: Request GET state (longPoll)";
        HYDRAWISE_SendCommand( $hash, "longpollState" );
    }

    return;
}

sub HYDRAWISE_TriggerFullDataUpdate {
    my $hash = shift;

    #  HYDRAWISE_SendCommand($hash, "firmware");
    #  HYDRAWISE_SendCommand($hash, "automaticUpdate");
    #  HYDRAWISE_SendCommand($hash, "calendar");
    #  HYDRAWISE_SendCommand($hash, "updates");
    #  HYDRAWISE_SendCommand($hash, "security");
    #  HYDRAWISE_SendCommand($hash, "predictive/location");
    #  HYDRAWISE_SendCommand($hash, "predictive/weather");

    return;
}

sub HYDRAWISE_ReadingsBulkUpdateIfChanged {
    my ( $hash, $reading, $value, $do_trigger) = @_;
    my $name = $hash->{NAME};
    # print "hydrawise READING: $reading -> $value \n";
    if($value){
      readingsBeginUpdate ($hash);
      readingsBulkUpdate( $hash, $reading, $value);
      readingsEndUpdate($hash, 1);
    }else{
      readingsBeginUpdate ($hash);
      readingsDelete( $hash, $reading );
      readingsEndUpdate($hash, 1);
    }
    return;
}

sub HYDRAWISE_GetDuration {
    my ( $hash, $duration ) = @_;

    return sprintf( "%d:%02d",
        int( $duration / 60 ),
        $duration - int( $duration / 60 ) * 60 );
}

sub HYDRAWISE_GetDay {
    my ( $hash, $day ) = @_;
    my $days = {
        'Mon' => "Montag",
        'Tue' => "Dienstag",
        'Wed' => "Mittwoch",
        'Thu' => "Donnerstag",
        'Fri' => "Freitag",
        'Sat' => "Samstag",
        'Sun' => "Sonntag",
        'Now' => "Running",
    };

    if ( defined( $days->{$day} ) ) {
        return $days->{$day}; # Wochentag
    }

    return $day;   # Uhrzeit bei heutigem Tag
}

1;

=pod
=item device
=item summary    controlling Hydrawise irrigation
=item summary_DE Steuerung der Hydrawise-Bewässerung

=begin html

<a name="HYDRAWISE"></a>
<h3>Hunter Hydrawise</h3>
<ul>
  The module receives data and sends commands via the Hunter Hydrawise API.<br>
  All zones are identified by a unique ID - this ID is used to modify zone watering schedules,
  including running a zone, stopping a zone and suspending a zone for a period of time.
  Status information on all zones associated with an account can also be queried.
  <br>

  <br>
  <b>Prerequisits</b>
  <ul>
    <br/>
    API keys can be obtained from your Hydrawise account under My Account -> Generate API Key.
    This has the format XXXX-XXXX-XXXX-XXXX.
    <br>
    

  </ul>
  <br/>

  <a name="Hydrawisedefine"></a>
  <b>Definition and usage</b>
  <ul>
    <br>
    The module is defined using the API key and the refresh interval!
  </ul>
  <br>
  <ul>
    <b> Definition of the module </b>
    <br>

    <ul>
    <br>
        <code>define &lt;name&gt; HYDRAWISE &lt;API-KEY&gt; &lt;Interval&gt;</code><br>
    <br>
    </ul>
  </ul>
   <br>
    <b>Example of a definition: </b><br>

    <ul>
    <br>
        <code>define myHydrawise HYDRAWISE 1234-5678-90AB-CDEF 60</code><br>
    <br>
    </ul>


  <a name="HydrawiseSet"></a>
  <b>Set</b>
    <br>

    <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><b>renewcontext</b>	</td><td> Returns details of all controllers associated with the customer account. </td></tr>
      <tr><td><b>renewRelays</b>	</td><td> Return of irrigation plans for control units </td></tr>
      <tr><td><b>run</b>			</td><td> Execute a zone for a certain period of time. 2 Parameters: "relay_id" "time_in_seconds</td></tr>
      <tr><td><b>runall</b>			</td><td> Execute all zones for a certain period of time. 1 Parameter: "time_in_seconds"  </td></tr>
      <tr><td><b>stop</b>			</td><td> Stops a zone. 1 Parameter: "relay_id"</td></tr>
      <tr><td><b>stopall</b>		</td><td> Stops all running zones.</td></tr>
      <tr><td><b>suspend</b>		</td><td> Suspends a zone for a certain time. 3 Parameters: "relay_id" "DD.MM.YYYY" "HH24:MI". </td></tr>
      <tr><td><b>suspendall</b>		</td><td> Suspends all zones for a certain time. 2 Parameters: "DD.MM.YYYY" "HH24:MI" </td></tr>
    </table>
    </ul>
    <br>

  <b>Get</b>
    <br>

    <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><b>help</b>					</td><td> Displays help for the SET commands </td></tr>
    </table>
    </ul>
    <br>

  <a name="Hydrawisereadings"></a>
  <b>Readings</b>
  <ul>
  <br>

    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td><b>controller_counts</b>		</td><td> Number of available controllers</td></tr>
      <tr><td><b>controller_id</b>			</td><td> Controller ID </td></tr>
      <tr><td><b>ct1_controller_id</b>		</td><td> Controler 1: ID</td></tr>
      <tr><td><b>ct1_controller_message</b>	</td><td> Controler 1: Status message from  Hydrawise</td></tr>
      <tr><td><b>ct1_controller_name</b>	</td><td> Controler 1: Defined name in Hydrawise</td></tr>
      <tr><td><b>ct1_last_contact</b>		</td><td> Controler 1: Last contact from Hydrawise to the controller</td></tr>
      <tr><td><b>ct1_serial_number</b>		</td><td> Controler 1: Serial number of the controller</td></tr>
      <tr><td><b>cur_controller_id</b>		</td><td> Current Controller (ID)</td></tr>
      <tr><td><b>cur_controller_name</b>	</td><td> Current Controller name</td></tr>
      <tr><td><b>customer_id</b>			</td><td> Customer ID of Hydrawise</td></tr>
      <tr><td><b>presence</b>				</td><td> Status of the module: presence or absent</td></tr>
      <tr><td><b>relay_counts</b>			</td><td> Number of relays</td></tr>
      <tr><td><b>rl1_name</b>				</td><td> Relay 1: Name </td></tr>
      <tr><td><b>rl1_next</b>				</td><td> Relay 1: Next time this zone will water</td></tr>
      <tr><td><b>rl1_relay</b>				</td><td> Relay 1: Physical zone number</td></tr>
      <tr><td><b>rl1_relay_id</b>			</td><td> Relay 1: Unique ID for this zone</td></tr>
      <tr><td><b>rl1_run_minutes</b>		</td><td> Relay 1: Length of next run time. If a run is in progress value will indicate number of seconds remaining.</td></tr>
    </table>
    <br>
  </ul>
</ul>
=end html

=begin html_DE

<a name="HYDRAWISE"></a>
<h3>Hunter Hydrawise</h3>
<ul>
  Das Modul empf&auml;ngt Daten und sendet Befehle &uuml;ber die Hunter Hydrawise API.<br>
  Alle Zonen werden durch eine eindeutige ID identifiziert - diese ID wird verwendet, um die Bew&auml;sserungspl&auml;ne der Zonen zu modifizieren,
  einschlie&szlig;lich des Betreibens einer Zone, des Anhaltens einer Zone und des Aussetzens einer Zone f&uuml;r eine bestimmte Zeit.
  Statusinformationen zu allen Zonen, die mit einem Konto verbunden sind, k&ouml;nnen ebenfalls abgefragt werden.
  <br>
  <br>
  <b>Voraussetzungen</b>
  <ul>
    <br/>
    Einen API-Schl&uuml;ssel k&ouml;nnen Sie von Ihrem Hydrawise-Konto unter Mein Konto generieren lassen.
    Dieser hat das Format XXXX-XXXX-XXXX-XXXX.
    <br>
  </ul>
  <br/>

  <a name="Hydrawisedefine"></a>
  <b>Definition und Verwendung</b>
  <ul>
    <br>
    Das Modul wird mithilfe des API-Keys und des Refreshintervals definiert!
  </ul>
  <br>
  <ul>
    <b> Definition des Moduls </b>
    <br>

    <ul>
    <br>
        <code>define &lt;name&gt; HYDRAWISE &lt;API-KEY&gt; &lt;Intervall&gt;</code><br>
    <br>
    </ul>
   </ul>
   <br>
    <b>Beispiel f&uuml;r eine Moduldefinition: </b><br>

    <ul>
    <br>
        <code>define myHydrawise HYDRAWISE 1234-5678-90AB-CDEF 60</code><br>
    <br>
    </ul>


  <a name="HydrawiseSet"></a>
  <b>Set</b>
    <br>

    <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><b>renewcontext</b>	</td><td> Gibt Details zu allen Controllern zur&uuml;ck, die mit dem Kundenkonto verbunden sind. </td></tr>
      <tr><td><b>renewRelays</b>	</td><td> R&uuml;ckgabe von Bew&auml;sserungspl&auml;nen f&uuml;r Steuerger&auml;te </td></tr>
      <tr><td><b>run</b>			</td><td> Eine Zone f&uuml;r eine bestimmte Zeitspanne ausf&uuml;hren. 2 Parameter: "relay_id" "zeit_in_sekunden"</td></tr>
      <tr><td><b>runall</b>			</td><td> Alle Zonen f&uuml;r eine bestimmte Zeitspanne ausf&uuml;hren. 1 Parameter: "zeit_in_sekunden"  </td></tr>
      <tr><td><b>stop</b>			</td><td> Stoppt eine Zone. 1 Parameter: "relay_id"</td></tr>
      <tr><td><b>stopall</b>		</td><td> Stoppt alle laufenden Zonen.</td></tr>
      <tr><td><b>suspend</b>		</td><td> Setzt eine Zone f&uuml;r eine bestimmte Zeit aus. 3 Parameter: "relay_id" "DD.MM.YYYY" "HH24:MI" </td></tr>
      <tr><td><b>suspendall</b>		</td><td> Setzt alle Zonen f&uuml;r eine bestimmte Zeit aus. 2 Parameter: "DD.MM.YYYY" "HH24:MI" </td></tr>
    </table>
    </ul>
    <br>

  <b>Get</b>
    <br>

    <ul>
    <table>
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><b>help</b>					</td><td> Zeigt die Hilfe f&uuml;r die SET Befehle an </td></tr>
    </table>
    </ul>
    <br>

  <a name="Hydrawisereadings"></a>
  <b>Readings</b>
  <ul>
  <br>

    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td><b>controller_counts</b>		</td><td> Anzahl der vorhandenen Controller</td></tr>
      <tr><td><b>controller_id</b>			</td><td> Controller ID </td></tr>
      <tr><td><b>ct1_controller_id</b>		</td><td> Controler 1: ID</td></tr>
      <tr><td><b>ct1_controller_message</b>	</td><td> Controler 1: Statusnachricht von Hydrawise</td></tr>
      <tr><td><b>ct1_controller_name</b>	</td><td> Controler 1: Definierter Name in Hydrawise</td></tr>
      <tr><td><b>ct1_last_contact</b>		</td><td> Controler 1: Letzter Kontakt von Hydrawise zum Controller</td></tr>
      <tr><td><b>ct1_serial_number</b>		</td><td> Controler 1: Seriennummer des Controllers</td></tr>
      <tr><td><b>cur_controller_id</b>		</td><td> Aktiver Controller (ID)</td></tr>
      <tr><td><b>cur_controller_name</b>	</td><td> Aktiver Controllername</td></tr>
      <tr><td><b>customer_id</b>			</td><td> KundenID von Hydrawise</td></tr>
      <tr><td><b>presence</b>				</td><td> Status des Moduls: presence oder absent</td></tr>
      <tr><td><b>relay_counts</b>			</td><td> Anzahl der Relays</td></tr>
      <tr><td><b>rl1_name</b>				</td><td> Relay 1: Name </td></tr>
      <tr><td><b>rl1_next</b>				</td><td> Relay 1: N&auml;chste Ausf&uuml;hrung der Zone</td></tr>
      <tr><td><b>rl1_relay</b>				</td><td> Relay 1: Physikalische Zonennummer</td></tr>
      <tr><td><b>rl1_relay_id</b>			</td><td> Relay 1: Eindeutige ID f&uuml;r diese Zone</td></tr>
      <tr><td><b>rl1_run_minutes</b>		</td><td> Relay 1: L&auml;nge der n&auml;chsten Laufzeit. Wenn ein Lauf im Gange ist, gibt der Wert die Anzahl der verbleibenden Sekunden an.</td></tr>
    </table>
    <br>
  </ul>
</ul>
=end html_DE
=cut
