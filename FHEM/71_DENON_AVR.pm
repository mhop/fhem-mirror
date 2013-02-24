# $Id$
##############################################################################
#
#     71_DENON_AVR.pm
#     An FHEM Perl module for controlling Denon AV-Receivers
#     via network connection. 
#
#     Copyright by Boris Pruessmann
#     e-mail: boris@pruessmann.org
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
use threads;
use threads::shared;
use Thread::Queue;
use warnings;

use Time::HiRes qw(usleep);
use IO::Socket::INET;
use IO::Select;

###################################
sub DENON_AVR_Get($@);
sub DENON_AVR_Define($$);
sub DENON_AVR_Undefine($$);

###################################
sub
DENON_AVR_Initialize($)
{
    Log 5, "DENON_AVR_Initialize called.";

    my ($hash) = @_;

    $hash->{GetFn}     = "DENON_AVR_Get";
    $hash->{SetFn}     = "DENON_AVR_Set";
    $hash->{DefFn}     = "DENON_AVR_Define";
    $hash->{UndefFn}   = "DENON_AVR_Undefine";

    $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,1,2,3,4,5 power:0,1 ".$readingFnAttributes;
}

###################################
sub
DENON_AVR_Get($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};


    my $what = $a[1];
     
    if($what =~ /^(power|volume_level|mute)$/)
    {
        if (defined($hash->{helper}{STATE}{$what}) && defined($hash->{helper}{STATE}{$what}{VAL}))
        {
            Log 5, "DENON_AVR_Get: ".$what." = ".$hash->{helper}{STATE}{$what}{VAL};
            return $hash->{helper}{STATE}{$what}{VAL};
        }
        else
        {
            return "no such reading: $what";
        }
    }
    else
    {
	return "Unknown argument $what, choose one of param power input volume_level mute get";
    }
}

###################################
sub
DENON_AVR_Set($@)
{
    my ($hash, @a) = @_;

    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on off volume:slider,-80,1,16 mute:on,off rawCommand statusRequest";

    if ($what eq "rawCommand")
    {
        $hash->{helper}{QUEUE}->enqueue($a[2]."\r");
    }
    else
    {
        return $usage;
    }
}

###################################
sub
DENON_AVR_Define($$)
{
    my ($hash, $def) = @_;
    Log 5, "DENON_AVR_Define(".$def.") called.";

    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};

    if (@a != 3)
    {
	my $msg = "wrong syntax: define <name> DENON_AVR <ip-or-hostname>";
	Log 2, $msg;

	return $msg;
    }

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;
    
    $hash->{helper}{QUEUE} = new Thread::Queue();
    $hash->{helper}{QUEUE}->enqueue("PW?\r");
    $hash->{helper}{QUEUE}->enqueue("MV?\r");
    $hash->{helper}{QUEUE}->enqueue("MU?\r");

    $hash->{helper}{STATE} = &share( {} );
    $hash->{helper}{STATE}{"power"} = &share( {} );
    $hash->{helper}{STATE}{"mute"} = &share( {} );
    $hash->{helper}{STATE}{"volume_level"} = &share( {} );

    $hash->{helper}{THREAD} = threads->new(\&DENON_AVR_Thread_Callback, $hash);

    return undef;
}

#############################
sub
DENON_AVR_Undefine($$)
{
    my($hash, $name) = @_;

    $hash->{helper}{QUEUE}->enqueue(undef);
    $hash->{helper}{THREAD}->join();
    $hash->{helper}{THREAD} = undef;

    return undef;
}

#############################
sub
DENON_AVR_Thread_Callback($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log 5, "DENON_AVR_Thread_Callback: called for ".$name;

    return "" if (!defined($hash->{helper}{ADDRESS}));

    my $host = $hash->{helper}{ADDRESS};
    Log 5, "DENON_AVR_ThreadCallback: Address: ".$host;

    my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => 23);
    if (!$sock)
    {
        Log 2, "Failed to create connection to ".$name." on ".$host;

        return undef;
    }

    local $/ = "\r";
      
    my $select = IO::Select->new($sock);

    my $queue = $hash->{helper}{QUEUE};

    my $running = 1;
    while ($running)
    {
        my @ready_clients = $select->can_read(0);
        foreach my $fh (@ready_clients)  
        {
            my $buf = readline($sock);
            chomp($buf);

            if ($buf eq "PWON")
            {
                Log 5, "DENON_AVR_ThreadCallback: Power On";
                $hash->{helper}{STATE}{"power"}{VAL} = "on";
            }
            elsif ($buf eq "PWSTANDBY")
            {
                Log 5, "DENON_AVR_ThreadCallback: Power Standby";
                $hash->{helper}{STATE}{"power"}{VAL} = "off";
            }
            elsif ($buf eq "MUON")
            {
                Log 5, "DENON_AVR_ThreadCallback: Mute On";
                $hash->{helper}{STATE}{"mute"}{VAL} = "on";
            }
            elsif ($buf eq "MUOFF")
            {
                Log 5, "DENON_AVR_ThreadCallback: Mute Off";
                $hash->{helper}{STATE}{"mute"}{VAL} = "off";
            }
            elsif ($buf =~ /MV(.+)/)
            {
                my $volume = $1;
                if ($volume =~/MAX (.+)/)
                {
                }
                else
                {
                    if (length($volume) == 2)
                    {
                        $volume = $volume."0";
                    }

                    Log 5, "DENON_AVR_ThreadCallback: Volume level ".$volume;
                    $hash->{helper}{STATE}{"volume_level"}{VAL} = int($volume);
                }
            }
            else
            {
                Log 5, "DENON_AVR_ThreadCallback: Received ".$buf;
            }
        }

        if ($queue->pending())
        {
           my $command = $queue->dequeue();
           if (!$command)
           {
               Log 5, "DENON_AVR_ThreadCallback: Received shutdown command";
               $running = 0;
           }
           else
           {
               Log 5, "DENON_AVR_ThreadCallback: Sending command ".$command;
               syswrite($sock, $command);
               usleep(100 * 1000);
           }
        }
    }

    $select->remove($sock);
    close $sock;
}

1;

=pod
=begin html
=end html
=cut

