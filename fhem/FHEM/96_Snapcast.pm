################################################################
#
#  $Id$
#
#  Originally initiated by Sebatian Stuecker / FHEM Forum: unimatrix
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

# This module is used to control a Snapcast Server https://github.com/badaix/snapcast
# This version is tested against https://github.com/badaix/snapcast/tree/98be8a58d945f84af50e40ebcf8a774592dd6e7b
# Future developments beyond this revision are not necessarily supported. 
# The module uses DevIo for communication. There is no blocking communication whatsoever. 
# Communication to Snapcast goes through a TCP Socket, Writing and Reading are managed asynchronously.

package FHEM::Media::Snapcast;    ## no critic 'Package declaration'

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday);
use DevIo;
use JSON ();
use GPUtils qw(GP_Import);
use List::Util qw( max min );


#-- Run before package compilation
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
          readingsDelete
          AttrVal InternalVal
          ReadingsVal ReadingsNum
          Log3
          InternalTimer RemoveInternalTimer
          devspec2array
          FmtDateTime
          DevIo_OpenDev DevIo_CloseDev DevIo_SimpleRead DevIo_SimpleWrite
          trim
          )
    );
}

sub ::Snapcast_Initialize { goto &Initialize }

my %_sets = (
    update  => 0,
    volume  => 2,
    stream  => 2,
    name    => 2,
    mute    => 2,
    latency => 2,
    group   => 2,
);

my %_client_sets = (
    volume  => 1,
    stream  => 1,
    name    => 1,
    mute    => 0,
    latency => 1,
    group   => 1,
);

my %_clientmethods = (
    name    => 'Client.SetName',
    volume  => 'Client.SetVolume',
    mute    => 'Client.SetVolume',
    stream  => 'Group.SetStream',
    latency => 'Client.SetLatency'
);

=pod 
https://github.com/badaix/snapcast/blob/develop/doc/json_rpc_api/control.md (v. 0.26.0)
Requests

    Client
        Client.GetStatus
        Client.SetVolume
        Client.SetLatency
        Client.SetName
    Group
        Group.GetStatus
        Group.SetMute
        Group.SetStream
        Group.SetClients
        Group.SetName
    Server
        Server.GetRPCVersion
        Server.GetStatus
        Server.DeleteClient
    Stream
        Stream.AddStream
        Stream.RemoveStream
        Stream.Control
        Stream.SetProperty

Notifications

    Client
        Client.OnConnect
        Client.OnDisconnect
        Client.OnVolumeChanged
        Client.OnLatencyChanged
        Client.OnNameChanged
    Group
        Group.OnMute
        Group.OnStreamChanged
        Group.OnNameChanged
    Stream
        Stream.OnProperties
        Stream.OnUpdate
    Server
        Server.OnUpdate

=cut

sub Initialize {
    my $hash = shift // return;
    $hash->{DefFn}    = \&Define;
    $hash->{UndefFn}  = \&Undef;
    $hash->{SetFn}    = \&Set;
    $hash->{GetFn}    = \&Get;
    $hash->{ReadyFn}  = \&Ready;
    $hash->{AttrFn}   = \&Attr;
    $hash->{ReadFn}   = \&Read;
    $hash->{AttrList} = "streamnext:all,playing constraintDummy constraints disable:1 volumeStepSize volumeStepSizeSmall volumeStepSizeThreshold $readingFnAttributes";
    return;
}

sub Define {
    my $hash = shift // return;
    my $def  = shift // return;
    my @arr  = split m{\s+}xms, $def;
    my $name = shift @arr;
    if ( defined( $arr[1] ) && $arr[1] eq 'client' ) {
        return 'Usage: define <name> Snapcast client <server> <id>' if !defined $arr[2] || !defined $arr[3];
        return "Server $arr[2] not defined"                         if !defined $defs{ $arr[2] };
        $hash->{MODE}   = 'client';
        $hash->{SERVER} = $arr[2];
        $hash->{ID}     = $arr[3];
        readingsSingleUpdate( $hash, 'state', 'defined', 1 );
        RemoveInternalTimer($hash);
        DevIo_CloseDev($hash);
        return Client_Register_Server($hash);
    }
    $hash->{ip}   = $arr[1] // 'localhost';
    $hash->{port} = $arr[2] // '1705';
    $hash->{MODE} = 'server';
    readingsSingleUpdate( $hash, 'state', 'defined', 1 );
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    $hash->{DeviceName} = "$hash->{ip}:$hash->{port}";
    delete( $hash->{IDLIST} );
    Snapcast_Connect($hash);
    return;
}

sub Snapcast_Connect {
    my $hash = shift // return;
    if ( !$init_done ) {
        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + 5, \&Snapcast_Connect, $hash, 0 );
        return;    # "init not done";
    }
    return DevIo_OpenDev( $hash, 0, \&onConnect, );
}

sub Attr {
    my $cmd   = shift;
    my $name  = shift;
    my $attr  = shift // return;
    my $value = shift;
    my $hash  = $defs{$name} // return;

    if ( $cmd eq 'set' ) {
        if ( $attr eq 'streamnext' ) {
            return 'streamnext needs to be either all or playing' if $value !~ m{\A(?:all|playing)\z}x;
        }
        if ( $attr eq 'volumeStepSize' || $attr eq 'volumeStepSizeSmall' || $attr eq 'volumeStepSizeThreshold' ) {
            return "$attr needs to be a number between 1 and 100" if !looks_like_number($value) || $value < 1 || $value > 100;
        }
    }
    return;
}

sub Undef {
    my $hash = shift // return;
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    Client_Unregister_Server($hash) if $hash->{MODE} eq 'client';
    return;
}

sub Get {
    return 'get is not supported by this module';
}

sub Set {
    my ( $hash, @param ) = @_;
    return '"set Snapcast" needs at least one argument' if int @param < 2;
    my $name = shift @param;
    my $opt  = shift @param;

    #  my $clientmod;
    my %snap_sets = $hash->{MODE} eq 'client' ? %_client_sets : %_sets;
    if ( !defined $snap_sets{$opt} ) {
        my @cList = keys %snap_sets;
        return "Unknown argument $opt, choose one of " . join( q{ }, @cList );
    }
    if ( @param < $snap_sets{$opt} ) {
        return "$opt requires at least $snap_sets{$opt} arguments";
    }
    if ( $opt eq 'update' ) {
        Snapcast_getStatus($hash);
        return;
    }
    if ( defined $_clientmethods{$opt} ) {
        my $client;
        Log3( $hash, 5, "snap: $opt command received" );
        if ( $hash->{MODE} eq 'client' ) {
            my $clientmod = $hash;
            $client = $hash->{NAME};
            $hash   = $hash->{SERVER};
            $hash   = $defs{$hash} // return 'Cannot find Server hash';
            $client = $clientmod->{ID};
        }
        else {
            $client = shift @param;
        }
        Log3( $hash, 5, "Snap: $opt command received for $client" );

        return 'client not found, use unique name, IP, or MAC as client identifier' if !defined $client;

        my $value = join q{ }, @param;

        if ( $client eq 'all' ) {
            for my $i ( 1 .. ReadingsVal( $name, 'clients', 0 ) ) {
                #my $sclient = $hash->{STATUS}->{clients}->{$i}->{host}->{mac};
                #$sclient =~ s/\://g; #$sclient =~ s{:}{}g; $client =~ s{#}{_}g;
                my $sclient = $hash->{STATUS}->{clients}->{$i}->{id};
                my $res = _setClient( $hash, $sclient, $opt, $value );
                readingsSingleUpdate( $hash, 'lastError', $res, 1 ) if defined $res;
            }
            return;
        }
        my @ids = grep {m{\A(?:clients_.+_group)\z}xms}
                keys %{ $hash->{READINGS} };
        my @group;
        for my $sid ( @ids ) {
            #= devspec2array("TYPE=Snapcast:FILTER=group=$client");
            #next if ReadingsVal($name, $_, '') ne $client;
            #clients_84a93e695051#2_group 207ff3bc-5082-789c-c444-29471f4ce57e
            if ( $sid =~ m{\Aclients_(.+)_group\z}xms ) {
                push @group, $1;
            }
        }
        Log3( $hash, 3, "Snap: groups are @group" );
        if ( @group ) {
            if ( $opt eq 'volume' && looks_like_number($value) && $value !~ m{[+-]}x ) {
                #Log3($hash,3,"SNAP: Group absolute volume command, volume: $value");
                my @paramset;
                my $grvol;
                for my $sclient ( @group ) {
                    $grvol += ReadingsNum( $name, "clients_${sclient}_volume", 0);
                }
                $grvol = int $grvol/@group;
                my $change = $value - $grvol;
                for my $sclient ( @group ) {
                    my $sparm->{id} = ReadingsVal( $name, "clients_${sclient}_origid", undef) // next;#_getId( $hash, $sclient) // next;
                    my $vol = ReadingsNum( $name, "clients_${sclient}_volume", 0) + $change;
                    $vol = max( 0, min( 100, $vol ) );
                    my $muteState = ReadingsVal( $name, "clients_${sclient}_muted", 'false' );
                    $muteState = 'false' if $vol && ( $muteState eq 'true' || $muteState eq '1' );
                    $sparm->{volume}->{muted} = $muteState;
                    $sparm->{volume}->{percent} = $vol;
                    my $payload = push @paramset, Snapcast_Encode( $hash, $_clientmethods{volume}, $sparm);
                }
                return if !@paramset;
                my $payload = q{[};
                $payload .= join q{,},@paramset;
                $payload .= "]\r\n";
                #Log3($hash,3,"SNAP: send batch $payload");
                return DevIo_SimpleWrite( $hash, $payload, 2 );
            }
            for my $sclient ( @group ) {
                $sclient =~ s{:}{}gx;
                $sclient =~ s{[#]}{_}gx; 
                my $res = _setClient( $hash, $sclient, $opt, $value );
                readingsSingleUpdate( $hash, 'lastError', $res, 1 ) if defined $res;
            }
            return;
        }
        my $res = _setClient( $hash, $client, $opt, $value );
        readingsSingleUpdate( $hash, 'lastError', $res, 1 ) if defined $res;
        return;
    }
    return "$opt not implemented yet!";
}

sub Read {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    my $buf;
    $buf = DevIo_SimpleRead($hash);
    return '' if !defined $buf;
    $buf = $hash->{PARTIAL} . $buf;
    $buf =~ s{\r}{}gx;
    my $lastchr = substr( $buf, -1, 1 );

    if ( $lastchr ne "\n" ) {
        $hash->{PARTIAL} = $buf;
        #Log3( $hash, 5, "snap: partial command received" );
        return;
    }
    $hash->{PARTIAL} = '';

    ###############################
    # Log3 $name,2, "Buffer: $buf";
    ###############################

    my @lines = split m{\n}x, $buf;
    for my $line (@lines) {
        Log3( $name, 4, "Snapcast single line is: $line" );

        # Hier die Results parsen
        my $update;
        if (!eval {
                $update = JSON->new->decode($line);
                1;
            }
            )
        {
            # Decode JSON died, probably because of incorrect JSON from Snapcast.
            Log3( $name, 1, "Invalid Response from Snapcast,ignoring result: $line" );
            readingsSingleUpdate( $hash, 'lastError', "Invalid JSON: $buf", 1 );
            return;
        }
        if ( ref $update eq 'ARRAY' ) {
            Log3( $name, 4, "Snap JSON array is $line" );
            for my $elem ( @{$update} ) {
                updateClientInGroup($hash,$elem);
            }
            return;
        }
        return if ref $update ne 'HASH';

        my $s = $update->{params}->{data};

        if (  defined $hash->{IDLIST} && $update->{id} && defined $hash->{IDLIST}->{ $update->{id} } ) {
            my $id = $update->{id};

            #Log3 $name,2, "id: $id ";
            if ( $hash->{IDLIST}->{$id}->{method} eq 'Server.GetStatus' ) {
                delete $hash->{IDLIST}->{$id};
                return parseStatus( $hash, $update );
            }
            if ( $hash->{IDLIST}->{$id}->{method} eq 'Server.DeleteClient' ) {
                delete $hash->{IDLIST}->{$id};
                return;
            }
            while ( my ( $key, $value ) = each %_clientmethods ) {
                if ( $value eq $hash->{IDLIST}->{$id}->{method} && $key ne 'mute' ) {    #exclude mute here because muting is now integrated in SetVolume
                    my $client = $hash->{IDLIST}->{$id}->{params}->{id};

                    $client =~ s{:}{}gx;
                    $client =~ s{[#]}{_}gx;
                    Log3( $name, 5, "client: $client, key: $key, value: $value" );

                    if ( $key eq 'volume' ) {
                        my $temp_percent = $update->{result}->{volume}->{percent};

                        #Log3 $name,2, "percent: $temp_percent ";
                        readingsBeginUpdate($hash);
                        readingsBulkUpdateIfChanged( $hash, "clients_${client}_muted",  $update->{result}->{volume}->{muted} );
                        readingsBulkUpdateIfChanged( $hash, "clients_${client}_volume", $update->{result}->{volume}->{percent} );
                        readingsEndUpdate( $hash, 1 );
                        my $clientmodule = $hash->{$client};
                        my $clienthash   = $defs{$clientmodule};
                        my $maxvol       = getVolumeConstraint($clienthash) // 100;

                        if ( defined $clientmodule ) {
                            readingsBeginUpdate($clienthash);
                            readingsBulkUpdateIfChanged( $clienthash, 'muted',  $update->{result}->{volume}->{muted} );
                            readingsBulkUpdateIfChanged( $clienthash, 'volume', $update->{result}->{volume}->{percent} );
                            readingsEndUpdate( $clienthash, 1 );
                        }
                    }
                    elsif ( $key eq 'stream' ) {

                        #Log3 $name,2, "key: $key ";
                        my $group = $hash->{IDLIST}->{$id}->{params}->{id};

                        #Log3 $name,2, "group: $group ";
                        for my $i ( 1 .. ReadingsVal( $name, 'clients', 0 ) ) {
                            $client = $hash->{STATUS}->{clients}->{$i}->{id};
                            my $client_group = ReadingsVal( $name, "clients_${client}_group", '' );
                            next if $group ne $client_group;

                            readingsBeginUpdate($hash);
                            readingsBulkUpdateIfChanged( $hash, "clients_${client}_stream_id", $update->{result}->{stream_id} );
                            readingsEndUpdate( $hash, 1 );
                            my $clienthash   = $defs{$hash->{$client}} // next;
                            readingsBeginUpdate($clienthash);
                            readingsBulkUpdateIfChanged( $clienthash, 'stream_id', $update->{result}->{stream_id} );
                            readingsEndUpdate( $clienthash, 1 );
                        }
                    }
                    else {
                        readingsBeginUpdate($hash);
                        readingsBulkUpdateIfChanged( $hash, "clients_${client}_$key", $update->{result} );
                        readingsEndUpdate( $hash, 1 );
                        my $clienthash   = $defs{$hash->{$client}} // return;
                        readingsBeginUpdate($clienthash);
                        readingsBulkUpdateIfChanged( $clienthash, $key, $update->{result} );
                        readingsEndUpdate( $clienthash, 1 );
                    }
                }
            }
            delete $hash->{IDLIST}->{$id};
            return;
        }

        if ( $update->{method} eq 'Client.OnDelete' ) {

            #fhem "deletereading $name clients.*";
            for my $reading (
                grep {m{\A(?:clients)}xms}
                keys %{ $hash->{READINGS} }
                )
            {
                readingsDelete( $hash, $reading );
            }

            Snapcast_getStatus($hash);
            return;
        }

        if ( $update->{method} =~ m{\AClient\.}x ) {
            updateClient( $hash, $s, 0 );
            return;
        }

        if ( $update->{method} =~ m{\A(?:Stream|Group)\.}x ) {
            updateStream( $hash, $s, 0 );
            return;
        }
#        elsif ( $update->{method} =~ m{\AGroup\.}x ) {
#            updateStream( $hash, $s, 0 );
#            return;
#        }

        if ( $update->{method} eq 'Server.OnUpdate' ) {
            my $serverupdate->{result} = $update->{params};
            parseStatus( $hash, $serverupdate );
            return;
        }

        Log3( $name, 2, "unknown JSON, please contact module maintainer: $buf" );
        readingsSingleUpdate( $hash, 'lastError', "unknown JSON, please contact module maintainer: $buf", 1 );
        return 'unknown JSON received';
    }
    return;
}

sub Ready {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    return if AttrVal( $name, 'disable', 0 );
    return if ReadingsVal( $name, 'state', 'disconnected' ) ne 'disconnected';

    for my $reading (
        grep {m{\A(?:streams|clients)}xms}
        keys %{ $hash->{READINGS} }
        )
    {
        readingsDelete( $hash, $reading );
    }

    DevIo_OpenDev( $hash, 1, \&onConnect, sub() { } );
    return;
}

sub onConnect {
    my $hash = shift // return;
    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
    $hash->{CONNECTS}++;
    $hash->{helper}{PARTIAL} = '';
    Snapcast_getStatus($hash);
    return;
}

sub updateClient {
    my $hash    = shift // return;
    my $c       = shift // return;
    my $cnumber = shift // 0; #return;
    if ( $cnumber == 0 ) {
        $cnumber++;
        #while ( defined $hash->{STATUS}->{clients}->{$cnumber} && $c->{host}->{mac} ne $hash->{STATUS}->{clients}->{$cnumber}->{host}->{mac} ) {
        while ( defined $hash->{STATUS}->{clients}->{$cnumber} && $c->{id} ne $hash->{STATUS}->{clients}->{$cnumber}->{id} ) {
            $cnumber++;
        }
        if ( !defined $hash->{STATUS}->{clients}->{$cnumber} ) {
            Snapcast_getStatus($hash);
            return;
        }
    }
    $hash->{STATUS}->{clients}->{$cnumber} = $c;
    my $id      = $c->{id} ? $c->{id} : $c->{host}->{mac};    # protocol version 2 has no id, but just the MAC, newer versions will have an ID.
    my $orig_id = $id;
    $id =~ s{:}{}gx;
    $id =~ s{[#]}{_}gx;
    $hash->{STATUS}->{clients}->{$cnumber}->{id}     = $id;
    $hash->{STATUS}->{clients}->{$cnumber}->{origid} = $orig_id;

    my $rvs->{online} = defined $c->{connected} ? 
                        $c->{connected} ? 'true' : 'false' : undef;
    $rvs->{name}      = $c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name};
    $rvs->{latency}   = $c->{config}->{latency};
    $rvs->{stream_id} = $c->{config}->{stream_id};
    $rvs->{volume}    = $c->{config}->{volume}->{percent};
    $rvs->{muted}     = defined $c->{config}->{volume}->{muted} ? 
                        $c->{config}->{volume}->{muted} ? 'true' : 'false' : undef;
    $rvs->{ip}        = $c->{host}->{ip};
    $rvs->{mac}       = $c->{host}->{mac};
    $rvs->{id}        = $id;
    $rvs->{origid}    = $orig_id;
    $rvs->{nr}        = $cnumber;
    $rvs->{group}     = $c->{config}->{group_id};

    readingsBeginUpdate($hash);
    for my $kw ( keys %{$rvs} ) {
        next if !defined $rvs->{$kw};
        readingsBulkUpdateIfChanged( $hash, "clients_${id}_${kw}", $rvs->{$kw} ) ;
    }
    readingsEndUpdate( $hash, 1 );

    return if !$hash->{$id};
    my $clienthash = $defs{ $hash->{$id} } // return;

    readingsBeginUpdate($clienthash);
    for my $kw ( keys %{$rvs} ) {
        next if !defined $rvs->{$kw};
        readingsBulkUpdateIfChanged( $clienthash, $kw, $rvs->{$kw} );
    }
    readingsEndUpdate( $clienthash, 1 );

    return if !defined $c->{config} || !defined $c->{config}->{volume} || !defined $c->{config}->{volume}->{percent};

    my $maxvol = getVolumeConstraint($clienthash) // 100;
    _setClient( $hash, $clienthash->{ID}, 'volume', $maxvol ) if $c->{config}->{volume}->{percent} > $maxvol;
    return;
}

sub updateClientInGroup {
    my $hash    = shift // return;
    my $c       = shift // return;

    delete $hash->{IDLIST}->{ $c->{id} } if defined $hash->{IDLIST} && $c->{id} && defined $hash->{IDLIST}->{ $c->{id} };

    my $id      = $c->{params}->{id} // return Snapcast_getStatus($hash);    # recent version uses an ID.

    my $cnumber = 1;
    while ( defined $hash->{STATUS}->{clients}->{$cnumber} && $c->{params}->{id} ne $hash->{STATUS}->{clients}->{$cnumber}->{origid} ) {
        $cnumber++;
    }

    if ( !defined $hash->{STATUS}->{clients}->{$cnumber} ) {
        #Snapcast_getStatus($hash);
        return;
    }

    return if !defined $c->{params};
    $id =~ s{:}{}gx;
    $id =~ s{[#]}{_}gx;

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "clients_${id}_volume",    $c->{params}->{volume}->{percent} ) if defined $c->{params}->{volume}->{percent};
    readingsBulkUpdateIfChanged( $hash, "clients_${id}_muted",     $c->{params}->{volume}->{muted} ? 'true' : 'false' ) if defined $c->{params}->{volume}->{muted};
    readingsEndUpdate( $hash, 1 );

    return if !$hash->{$id};
    my $clienthash = $defs{ $hash->{$id} } // return;

    readingsBeginUpdate($clienthash);
    readingsBulkUpdateIfChanged( $clienthash, 'volume',    $c->{params}->{volume}->{percent} ) if defined $c->{params}->{volume}->{percent};
    readingsBulkUpdateIfChanged( $clienthash, 'muted',     $c->{params}->{volume}->{muted} ? 'true' : 'false' ) if defined $c->{params}->{volume}->{muted};
    readingsEndUpdate( $clienthash, 1 );

    return if !defined $c->{params} || !defined $c->{params}->{volume} || !defined $c->{params}->{volume}->{percent};

    my $maxvol = getVolumeConstraint($clienthash) // 100;
    _setClient( $hash, $clienthash->{ID}, 'volume', $maxvol ) if $c->{params}->{volume}->{percent} > $maxvol;
    return;
}

sub updateStream {
    my $hash    = shift // return;
    my $s       = shift // return;
    my $snumber = shift // return;
    if ( $snumber == 0 ) {
        $snumber++;
        while ( defined $hash->{STATUS}->{streams}->{$snumber} && $s->{id} ne $hash->{STATUS}->{streams}->{$snumber}->{id} ) {
            $snumber++;
        }
        return if !defined $hash->{STATUS}->{streams}->{$snumber};
    }
    $hash->{STATUS}->{streams}->{$snumber} = $s;
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "streams_${snumber}_id",     $s->{id} );
    readingsBulkUpdateIfChanged( $hash, "streams_${snumber}_status", $s->{status} );
    readingsEndUpdate( $hash, 1 );
    return;
}

sub Client_Register_Server {
    my $hash = shift // return;
    return if $hash->{MODE} ne 'client';
    my $name   = $hash->{NAME} // return;
    my $server = $hash->{SERVER};
    if ( !defined $defs{$server} ) {
        InternalTimer( gettimeofday() + 30, \&Client_Register_Server, $hash, 1 );    # if server does not exists maybe it got deleted, recheck every 30 seconds if it reappears
        return;
    }
    $server = $defs{$server};               # get the server hash
    $server->{ $hash->{ID} } = $name;
    Snapcast_getStatus($server);
    return;
}

sub Client_Unregister_Server {
    my $hash = shift // return;
    return if $hash->{MODE} ne 'client';
    my $name   = $hash->{NAME};
    my $server = $hash->{SERVER};
    $server = $defs{$server} // return;      # get the server hash
    readingsSingleUpdate( $server, "clients_$hash->{ID}_module", $name, 1 );
    delete $server->{ $hash->{ID} };
    return;
}

sub Snapcast_getStatus {
    my $hash = shift // return;
    return Snapcast_Do( $hash, 'Server.GetStatus', '' );
}

sub parseStatus {
    my $hash    = shift // return;
    my $status  = shift // return;
    my $streams = $status->{result}->{server}->{streams};
    my $groups  = $status->{result}->{server}->{groups};
    my $server  = $status->{result}->{server}->{server};

    $hash->{STATUS}->{server} = $server;

    #readingsBeginUpdate($hash) if defined $groups || defined $streams;
    if ( defined $groups ) {
        my @groups  = @{$groups};
        my $gnumber = 1;
        my $cnumber = 1;
        for my $g (@groups) {
            my $groupstream = $g->{stream_id};
            my $groupid     = $g->{id};
            my $clients     = $g->{clients};
            if ( defined $clients ) {
                my @clients = @{$clients};
                for my $c (@clients) {
                    $c->{config}->{stream_id} = $groupstream;    # insert "stream" field for every client
                    $c->{config}->{group_id}  = $groupid;        # insert "group_id" field for every client
                    updateClient( $hash, $c, $cnumber );
                    $cnumber++;
                }
                readingsBeginUpdate($hash);
                readingsBulkUpdateIfChanged( $hash, 'clients', $cnumber - 1 );
                readingsEndUpdate( $hash, 1 );
            }
        }
    }
    if ( defined $streams ) {
        my @streams = @{$streams};
        my $snumber = 1;
        for my $s (@streams) {
            updateStream( $hash, $s, $snumber );
            $snumber++;
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, 'streams', $snumber - 1 );
        readingsEndUpdate( $hash, 1 );
    }

    InternalTimer( gettimeofday() + 300, \&Snapcast_getStatus, $hash, 1 );    # every 5 Minutes, get the full update, also to apply changed vol constraints.
    return;
}

sub _setClient {
    my ( $hash, $id, $param, $value ) = @_;
    my $name = $hash->{NAME};
    Log3( $name, 4, "SNAP setClient: $hash->{NAME}, id $id, param $param, val $value" );
    my $cnumber = ReadingsVal( $name, "clients_${id}_nr", undef ) // return;
    my $method  = $_clientmethods{$param}                         // return;

    my $paramset->{id} = _getId( $hash, $id );
    Log3( $name, 4, "SNAP setClient still there: $hash->{NAME}, paramsetid $paramset->{id}" );

    if ( $param eq 'volumeConstraint' ) {
        my @values = split m{ }x, $value;
        return 'not enough parameters for volumeConstraint' if @values < 2;

        #my $match;
        if ( @values % 2 ) {    # there is a match argument given because number is uneven
                                #$match = pop @values;
            pop @values;
        }    #else {
             #$match = '_global_';
             #}
        for ( my $i = 0; $i < @values; $i += 2 ) {
            return 'wrong timeformat 00:00 - 24:00 for time/volume pair' if $values[$i]       !~ m{^(?:(?:[0-1]?[0-9]|2[0-3]):[0-5][0-9])|24:00$}x;
            return 'wrong volumeformat 0 - 100 for time/volume pair'     if $values[ $i + 1 ] !~ m{^(?:0?[0-9]?[0-9]|100)$}x;
        }
        return;
    }

    if ( $param eq 'stream' ) {
        $paramset->{id} = ReadingsVal( $name, "clients_${id}_group", "" );    # for setting stream we now use group id instead of client id in snapcast 0.11 JSON format
        $param = 'stream_id';
        if ( $value eq "next" ) {                                             # just switch to the next stream, if last stream, jump to first one. This way streams can be cycled with a button press
            my $totalstreams  = ReadingsVal( $name, 'streams', 0 );
            my $currentstream = _getStreamNumber( $hash, ReadingsVal( $name, "clients_${id}_stream_id", '' ) );
            my $newstream     = $currentstream + 1;
            $newstream = 1 if $newstream > $totalstreams;                             #unless $newstream <= $totalstreams;
            $value     = ReadingsVal( $name, "streams_" . $newstream . "_id", '' );
        }
    }

    my $muteState             = ReadingsVal( $name, "clients_${id}_muted", 'false' );
    my $volumeobject->{muted} = $muteState;
    my $currentVol            = ReadingsVal( $name, "clients_${id}_volume", 50 );

    if ( $param eq 'volume' ) {

        return if !$value;

        # check if volume was given as increment or decrement, then find out current volume and calculate new volume
        if ( $value =~ m{\A([+-])(\d{1,2})\z}x ) {
            my $direction = $1;
            my $amount    = $2;

            #$value = eval($currentVol. $direction. $amount);
            $value = eval { $currentVol . $direction . $amount };
            $value = max( 0, min( 100, $value ) );
        }

        # if volume is given with up or down argument, then increase or decrease according to volumeStepSize
        if ( $value =~ m{\A(?:up|down)\z}x ) {
            my $step = AttrVal( $name, 'volumeStepSizeThreshold', 5 ) > $currentVol ? AttrVal( $name, 'volumeStepSizeSmall', 1 ) : AttrVal( $name, 'volumeStepSize', 5 );
            if ( $value eq 'up' ) {
                $value = $currentVol + $step;
            }
            else {
                $value = $currentVol - $step;
            }
            $value = max( 0, min( 100, $value ) );
            $muteState = 'false' if $value > 0 && ( $muteState eq 'true' || $muteState == 1 );
        }
        $volumeobject->{percent} = $value + 0;
        $value = $volumeobject;
    }

    if ( $param eq 'mute' ) {
        $volumeobject->{percent} = $currentVol + 0;
        $value = $volumeobject;

        if ( !defined $value->{muted} || $value->{muted} eq '' ) {
            $value                   = $muteState eq 'true' || $muteState == 1 ? 'false' : 'true';
            $volumeobject->{muted}   = $value;
            $volumeobject->{percent} = $currentVol + 0;
            $value                   = $volumeobject;
        }
        $param = 'volume';    # change param to "volume" to match new format
    }

    if ( ref $value ne 'HASH' && looks_like_number($value) ) {
        $paramset->{$param} = $value + 0;
    }
    else {
        $paramset->{$param} = $value;
    }

    Snapcast_Do( $hash, $method, $paramset );
    return;
}

sub Snapcast_Do {
    my $hash    = shift // return;
    my $method  = shift // return;
    my $param   = shift // '';
    my $payload = Snapcast_Encode( $hash, $method, $param );
    $payload .= "\r\n";

    #Log3($hash,3,"SNAP: Do $payload");
    return DevIo_SimpleWrite( $hash, $payload, 2 );
}

sub Snapcast_Encode {
    my $hash   = shift // return;
    my $method = shift // return;
    my $param  = shift // '';

    if   ( defined( $hash->{helper}{REQID} ) ) { $hash->{helper}{REQID}++; }
    else                                       { $hash->{helper}{REQID} = 1; }
    $hash->{helper}{REQID} = 1 if $hash->{helper}{REQID} > 16383;    # not sure if this is needed but we better dont let this grow forever
    my $request;
    my $json;
    $request->{jsonrpc}                 = "2.0";
    $request->{method}                  = $method;
    $request->{id}                      = $hash->{helper}{REQID};
    $request->{params}                  = $param if $param ne '';
    $hash->{IDLIST}->{ $request->{id} } = $request;
    $request->{id}                      = $request->{id} + 0;
    $json                               = JSON->new->encode($request);
    $json =~ s{("(true|false|null)")}{$2}gxms;
    return $json;
}

sub _getStreamNumber {
    my $hash = shift         // return;
    my $id   = shift         // return;
    my $name = $hash->{NAME} // return;
    for my $i ( 1 .. ReadingsVal( $name, 'streams', 1 ) ) {
        return $i if $id eq ReadingsVal( $name, "streams_${i}_id", '' );
    }
    return;
}

sub _getId {
    my $hash   = shift // return;
    my $client = shift // return;

    my $name = $hash->{NAME} // return;

    # client is ID
    if ( $client =~ m/^([0-9a-f]{12}([#_]*\d*|$))$/i ) {
        for my $i ( 1 .. ReadingsVal( $name, 'streams', 1 ) ) {
            return $hash->{STATUS}->{clients}->{$i}->{origid}
                if $client eq $hash->{STATUS}->{clients}->{$i}->{id};
        }
    }

    # client is provided as device name?
    if ( InternalVal($client,'TYPE','') eq 'Snapcast') {
        my $def = InternalVal($client,'ID','');
        return ReadingsVal($name,"clients_${def}_origid",undef);
    }
    return 'unknown client';
}

sub getVolumeConstraint {
    my $hash   = shift // return;
    my $client = shift // return;

    my $name  = $hash->{NAME} // return;
    my $value = 100;

    return $value if $hash->{MODE} ne 'client';
    my @constraints = split m{,}x, AttrVal( $name, 'constraints', '' );
    return $value if !@constraints;
    my $phase = ReadingsVal( AttrVal( $name, 'constraintDummy', undef ), 'state', undef ) // return $value;

    for my $c (@constraints) {
        my ( $cname, $list ) = split m{\|}x, $c;

        #Log3($name,3,"SNAP cname: $cname, list: $list");
        if ( $cname eq $phase ) {
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time + 86400 );
            my $tomorrow = sprintf( "%04d", 1900 + $year ) . "-" . sprintf( "%02d", $mon + 1 ) . "-" . sprintf( "%02d", $mday ) . " ";
            $list = trim($list);    #=~ s/^\s+//; # get rid of whitespaces
                                    #$list =~ s/\s+$//;
            my @listelements = split m{ }x, $list;
            my $mindiff      = time_str2num( $tomorrow . '23:59:00' );    # eine Tageslänge
            for ( my $i = 0; $i < @listelements / 2; $i++ ) {
                my $diff = abstime2rel( $listelements[ $i * 2 ] . ':00' );          # wie lange sind wir weg von der SChaltzeit?
                if ( time_str2num( $tomorrow . $diff ) < $mindiff ) { $mindiff = time_str2num( $tomorrow . $diff ); $value = $listelements[ 1 + ( $i * 2 ) ]; }    # wir suchen die kleinste relative Zeit
            }
        }
    }
    readingsSingleUpdate( $hash, 'maxvol', $value, 1 );
    return $value;    # der aktuelle Auto-Wert wird zurückgegeben
}

1;

__END__

=pod

=encoding utf8
=item device
=item summary    control and monitor Snapcast Servers and Clients
=item summary_DE Steuert und überwacht Snapcast Server und Clients

=begin html

<a id="Snapcast"></a>
<h3>Snapcast</h3>
<ul>
    <i>Snapcast</i> is a module to control a Snapcast Server. Snapcast is a little project to achieve multiroom audio and is a leightweight alternative to such solutions using Pulseaudio.
    Find all information about Snapcast, how to install and configure on the <a href="https://github.com/badaix/snapcast">Snapcast GIT</a>. To use this module, the minimum is to define a snapcast server module
    which defines the connection to the actual snapcast server. See the define section for how to do this. On top of that, it is possible to define virtual client modules, so that each snapcast client that is connected to 
    the Snapcast Server is represented by its own FHEM module. The purpose of that is to provide an interface to the user that enables to integrate Snapcast Clients into existing visualization solutions and to use 
    other FHEM capabilities around it, e.g. Notifies, etc. The server module includes all readings of all snapcast clients, and it allows to control all functions of all snapcast clients. 
    Each virtual client module just gets the reading for the specific client. The client modules is encouraged and also makes it possible to do per-client Attribute settings, e.g. volume step size and volume constraints. 
    <br><br>
    <a di="Snapcast-define"></a>
    <h4>Define</h4>
    <ul>
        <code>define <name> Snapcast [&lt;ip&gt; &lt;port&gt;]</code>
        <br><br>
        Example: <code>define MySnap Snapcast 127.0.0.1 1705</code>
        <br><br>
        This way a snapcast server module is defined. IP defaults to localhost, and Port to 1705, in case you run Snapcast in the default configuration on the same server as FHEM, you dont need to give those parameters.
        <br><br><br>
        <code>define <name> Snapcast client &lt;server&gt; &lt;clientid&gt;</code>
         <br><br>
        Example: <code>define MySnapClient Snapcast client MySnap aabbccddeeff</code>
        <br><br>
        This way a snapcast client module is defined. The keyword client does this. The next argument links the client module to the associated server module. The final argument is the client ID. In Snapcast each client gets a unique ID,
         which is normally made out of the MAC address. Once the server module is initialized it will have all the client IDs in the readings, so you want to use those for the definition of the client modules
    </ul>
    <br>
    <a id="Snapcast-set"></a>
    <h4>Set</h4>
    <ul>
        For a Server module: <code>set &lt;name&gt; &lt;function&gt; &lt;client&gt; &lt;value&gt;</code>
        <br><br>
        For a Client module: <code>set &lt;name&gt; &lt;function&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
              <a id="Snapcast-set-update"></a><li><i>update</i><br>
                  Perform a full update of the Snapcast Status including streams and servers. Only needed if something is not working. Server module only</li>
              <a id="Snapcast-set-volume"></a><li><i>volume</i><br>
                  Set the volume of a client. For this and all the following 4 options, give client as second parameter (only for the server module), either as name, IP , or MAC and the desired value as third parameter. 
                  Client can be given as "all", in that case all clients are changed at once (only for server module)<br>
                  Volume can be given in 3 ways: Range between 0 and 100 to set volume directly. Increment or Decrement given between -100 and +100. Keywords <em>up</em> and <em>down</em> to increase or decrease with a predifined step size. 
                  The step size can be defined in the attribute <em>volumeStepSize</em><br>
                  The step size can be defined smaller for the lower volume range, so that finetuning is possible in this area.
                  See the description of the attributes <em>volumeStepSizeSmall</em> and <em>volumeStepThreshold</em>
                  Setting a volume bigger than 0 also unmutes the client, if muted.</li>
              <a id="Snapcast-set-mute"></a><li><i>mute</i><br>
                  Mute or unmute by giving "true" or "false" as value. If no argument given,  toggle between muted and unmuted.</li>
              <a id="Snapcast-set-latency"></a><li><i>latency</i><br>
                  Change the Latency Setting of the client</li>
              <a id="Snapcast-set-name"></a><li><i>name</i><br>
                  Change the Name of the client</li>
              <a id="Snapcast-set-stream"></a><li><i>stream</i><br>
                  Change the stream that the client is listening to. Snapcast uses one or more streams which can be unterstood as virtual audio channels. Each client/room can subscribe to one of them. 
                  By using next as value, you can cycle through the avaialble streams</li>
        </ul>
</ul>
 <br><br>
  <a id="Snapcast-attr"></a>
  <h4>Attributes</h4>
  <ul>
    All attributes can be set to the master module and the client modules. Using them for client modules enable the setting of different attribute values per client. 
    <a id="Snapcast-attr-streamnext"></a><li>streamnext<br>
    Can be set to <i>all</i> or <i>playing</i>. If set to <i>all</i>, the <i>next</i> function cycles through all streams, if set to <i>playing</i>, the next function cycles only through streams in the playing state.
    </li>
    <a id="Snapcast-attr-volumeStepSize"></a><li>volumeStepSize<br>
      Default: 5. Set this to define, how far the volume is changed when using up/down volume commands. 
    </li>
    <a id="Snapcast-attr-volumeStepThreshold"></a><li>volumeStepThreshold<br>
      Default: 7. When the volume is below this threshold, then the volumeStepSizeSmall setting is used for volume steps, rather than the normal volumeStepSize. 
    </li>
    <a id="Snapcast-attr-volumeStepSizeSmall"></a><li>volumeStepSizeSmall<br>
      Default: 1. This typically smaller step size is used when using "volume up" or "volume down" and the current volume is smaller than the threshold. 
    </li>
    <a id="Snapcast-attr-constraintDummy"></a><li>constraintDummy<br>
    Links the Snapcast module to a dummy. The value of the dummy is then used as a selector for different sets of volumeConstraints. See the description of the volumeConstraint command. 
    </li>
    <a id="Snapcast-attr-constraints"></a><li>constraints<br>Defines a set of volume Constraints for each client and, optionally, based on the value of the dummy as defined with constraintDummy. This way there can be different volume profiles for e.g. weekdays or weekends. volumeConstraints mean, that the maximum volume of snapcast clients can be limited or even set to 0 during certain times, e.g. at night for the childrens room, etc.
    the constraint argument is given in the folling format: <constraintSet>|hh:mm vol hh:mm vol ... [<constraintSet2>|hh:mm vol ... etc. The chain off <hh:mm> <volume> pairs defines a volume profile for 24 hours. It is equivalent to the temeratore setting of the homematic thermostates supported by FHEM.  
    <br>Example: standard|08:00 0 18:00 100 22:00 30 24:00 0,weekend|10:00 0 20:00 100 24:00 30</li>
    <br>In this example, there are two profiles defined. If the value of the associated dummy is "standard", then the standard profile is used. It mutes the client between midnight and 8 am, then allows full volume until 18:00, then limites the volume to 30 until 22:00 and then mutes the client for the rest of the day. The snapcast module does not increase the volume when a limited time is over, it only allows for increasing it manually again. 
  </ul>
</ul>

=end html

=currentstream
