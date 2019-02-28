# $Id$
##############################################################################
#
#     98_FreezeMon.pm
#     An FHEM Perl module that tries to combine some features of PERFMON and apptime
#
#     Copyright by KernSani
#     based on 99_PERFMON and apptime
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
# 	  Changelog:
#		0.0.28:	Fixed minor bug in regex for statistics
#				Added Commandref for getFreezes
#		0.0.27:	Slightly improved device detection
#				added set Command getFreezes to enable usage of webCmd
#				fixed some commandref typos
#		0.0.26:	Get command for Statistics
#				remove trailing/leading whitespace for ignored devices
#		0.0.25:	Further improved statistics function and clear statistics
#		0.0.24:	Optimized statistics function
#				Added clear statistics command
#		0.0.23:	Fixed few minor bugs
#				Added experimental statistics function
#		0.0.22: Fixed a weird bug when CatchFnCalls was enabled
#		0.0.21: Added direct help for set, get and attr commands
#		0.0.20: Internal changes
#				improved handling of blocking calls
#				fm_extraSeconds not used anymore
#				aligned disable/active/inactive to other modules (at)
#		0.0.19:	unwrap Log3 function when set inactive
#				suppress warnings when redefining subs
#				Monitoring callFn (fm_CatchFnCalls)
#				Monitoring Commands (fm_CatchCmds)
#				adjusted log levels
#		0.0.18:	fixed unnecessary call of blocking function
#		0.0.17:	fixed Warning when fm_logFile is not maintained
#				Freeze-Handling non-blocking
#				New attribute fm_whitelistSub
#		0.0.16:	Minor Logging changes
#				Auto-delete Logfiles via fm_logKeep
#		0.0.15:	New InternalTimer Handling (#81365) - Thanks to Ansgar (noansi)
#				New logging function (fm_logFile, fm_logExtraSeconds) incl. get function - Thanks Andy (gandy)
#				Fixed unescaped characters in commandref (helmut, #84992)
#		0.0.14:	Issue with prioQueues (#769427)
#				Fixed German Umlauts in German Commandref
#		0.0.13:	added extended Details attribute
#				optimization of logging
#		0.0.12:	problem with older perl versions (Forum #764462)
#				Small improvement in device detection
#				added ignoreDev and ignorMode attribute
#		0.0.11:	added date to "get freeze" popup
#				fixed readingsbulkupdate behaviour
#				fixed that freezemon is inactive after restart
#				removed gplots
#		0.0.10:	added set commands active, inactive and clear
#				added gplot files
#				minor bug fixes
#		0.0.09:	fixed incomplete renaming of Attribute fm_freezeThreshold
#		0.0.08:	trimming of very long lines in "get freeze"
#				start freezemon only after INITIALIZED|REREADCFG (and as late as possible)
#		0.0.07:	just for fun - added some color to "get freeze"
#				Fixed bug with uninitialized value (Thanks Micheal.Winkler)
#		0.0.06:	Code cleanup
#				Fixed bug with dayLast reading
#		0.0.05:	Experimental coding to improve bad guy detection
#				German and English documentation added
#		0.0.04:	Added Get function to get last 20 freezes
#		0.0.03:	Added dynamic loglevel attribute fm_log
#				Added missing "isDisabled" check in define function
#				Do some checks not every second
#				Fixed PERL WARNING "uninitialized value" if no Device found
#				minor adjustments and bugfixes
#		0.0.02:	Fixed logical issue with freezetime Attribute
#				Renamed Attributes
#				added dayLast readings
#				fixed delete attribute "disable"
#				fixed issue with missing svref_2object
#				minor adjustments and bugfixes
#	  	0.0.01:	initial version
##############################################################################
##############################################################################
# 	  Todo:
#
#
##############################################################################

package main;

use strict;
use warnings;

#use Data::Dumper;

use POSIX;
use Time::HiRes qw(gettimeofday);
use Time::HiRes qw(tv_interval);
use B qw(svref_2object);
use Blocking;
use vars qw($FW_CSRF);

my $version = "0.0.28";

my @logqueue = ();
my @fmCmd    = ();
my @fmFn     = ();
my $fmName;
my $fmCmdLog;
my $fmFnLog;

###################################
sub freezemon_Initialize($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Module specific attributes
    my @freezemon_attr =
      (
"fm_forceApptime:0,1 fm_freezeThreshold disable:0,1 fm_log fm_ignoreDev fm_ignoreMode:off,single,all fm_extDetail:0,1 fm_logExtraSeconds fm_logFile fm_logKeep fm_whitelistSub fm_CatchFnCalls:0,1,2,3,4,5 fm_CatchCmds:0,1,2,3,4,5 fm_statistics:0,1 fm_statistics_low"
      );

    $hash->{GetFn}             = "freezemon_Get";
    $hash->{SetFn}             = "freezemon_Set";
    $hash->{DefFn}             = "freezemon_Define";
    $hash->{UndefFn}           = "freezemon_Undefine";
    $hash->{NotifyFn}          = "freezemon_Notify";
    $hash->{NotifyDev}         = "global";
    $hash->{NotifyOrderPrefix} = "99-";                  # we want to be notified late.
    $hash->{AttrFn}            = "freezemon_Attr";
    $hash->{AttrList} = join( " ", @freezemon_attr ) . " " . $readingFnAttributes;

    #map new Attribute names
    $hash->{AttrRenameMap} = {
        "fmForceApptime" => "fm_forceApptime:",
        "fmFreezeTime"   => "fm_freezeThreshold"
    };

}

###################################
sub freezemon_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    RemoveInternalTimer($hash);

    my $usage = "syntax: define <name> freezemon";

    my ( $name, $type ) = @a;
    if ( int(@a) != 2 ) {
        return $usage;
    }

    Log3 $name, 3, "freezemon defined $name $type";

    $hash->{VERSION} = $version;
    $hash->{NAME}    = $name;

    # start the timer
    Log3 $name, 5, "[$name] => Define IsDisabled:" . IsDisabled($name) . " init_done:$init_done";
    if ( !IsDisabled($name) && $init_done ) {
        freezemon_start($hash);
    }
    elsif ( IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "inactive", 1 );
        $hash->{helper}{DISABLED} = 1;
    }

    return undef;
}
###################################
sub freezemon_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{blocking}{pid} ) if ( defined( $hash->{helper}{blocking}{pid} ) );
    freezemon_unwrap_all($hash);
    return undef;
}
###################################
sub freezemon_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};               # own name / hash
    my $events = deviceEvents( $dev, 1 );

    return ""
      if ( IsDisabled($name) );             # Return without any further action if the module is disabled
    return if ( !grep( m/^INITIALIZED|REREADCFG$/, @{$events} ) );

    freezemon_start($hash);
}
###################################
sub freezemon_processFreeze($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $pid    = $hash->{helper}{blocking}{pid};
    my $log = freezemon_dump_log( $hash, $hash->{helper}{TIMER}, $hash->{helper}{msg} );

    return $name;
}
###################################
sub freezemon_freezeDone($) {
    my ($name) = @_;
    my $hash = $defs{$name};
    Log3 $name, 5, "[Freezemon] $name: Blocking Call with PID $hash->{helper}{blocking}{pid} ended";
    delete( $hash->{helper}{blocking} );
}

###################################
sub freezemon_freezeAbort($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 1, "[Freezemon] $name: Blocking Call with PID $hash->{helper}{blocking}{pid} aborted due to timeout";
    delete( $hash->{helper}{blocking} );
    return $name;
}

###################################
sub freezemon_processBlocking($) {

    my ($e) = @_;
    my $name = $e->{NAME};

    my $log = freezemon_dump_log2( $name, $e->{msg}, $e->{logfile}, $e->{logqueue} );

    return $name;
}

###################################
sub freezemon_ProcessTimer($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    #RemoveInternalTimer($hash);

    my $now    = gettimeofday();
    my $freeze = $now - $hash->{helper}{TIMER};

    #Check Freezes
    if ( $freeze > AttrVal( $name, "fm_freezeThreshold", 1 ) ) {
        delete $hash->{helper}{logqueue};
        $hash->{helper}{logqueue} = \@logqueue;
        $hash->{helper}{now}      = $now;
        $hash->{helper}{freeze}   = $freeze;
        my $now    = $hash->{helper}{now};
        my $freeze = $hash->{helper}{freeze};
        my ( $seconds, $microseconds ) = gettimeofday();
        my $t0  = [gettimeofday];
        my @t   = localtime($seconds);
        my $tim = sprintf(
            "%04d.%02d.%02d %02d:%02d:%02d.%03d",
            $t[5] + 1900,
            $t[4] + 1,
            $t[3], $t[2], $t[1], $t[0], $microseconds / 1000
        );
        Log3 $name, 5, "[Freezemon] $name: ----------- Starting Freeze handling at $tim ---------------------";

        my $dev       = "";
        my $guys      = "";
        my $idevFlag  = "";
        my $nidevFlag = "";
        my $found     = 0;
        my $start     = strftime( "%H:%M:%S", localtime( $hash->{helper}{TIMER} ) );
        my $end       = strftime( "%H:%M:%S", localtime($now) );
        my @rlist;

        $freeze = int( $freeze * 1000 ) / 1000;

        #Build a hash of devices to ignore
        my @idevs = split( ",", AttrVal( $name, "fm_ignoreDev", "" ) );
        @idevs = grep( s/\s*$//g, @idevs )
          ;    #remove leading/trailing whitespace https://forum.fhem.de/index.php/topic,83909.msg898431.html#msg898431

        my %id = map { $_ => 1 } @idevs;

        my %blacklist = map { $_ => 1 } split( ",", AttrVal( $name, "fm_whitelistSub", "" ) );

        # Commands
        foreach my $entry (@fmCmd) {
            if ( exists( $id{ @$entry[1] } ) ) {
                $idevFlag = @$entry[1];
            }
            else {
                $nidevFlag = @$entry[1];
            }
            if ( exists( $blacklist{ @$entry[0] } ) ) {
                Log3 $name, 5, "[Freezemon] $name whitelisted: " . @$entry[0];
                next;
            }
            $dev .= "cmd-" . @$entry[0] . "(" . @$entry[1] . ") ";
            push @rlist, @$entry[1];
        }

        #Functions
        foreach my $entry (@fmFn) {
            if ( exists( $id{ @$entry[1] } ) ) {
                $idevFlag = @$entry[1];
            }
            else {
                $nidevFlag = @$entry[1];
            }
            if ( exists( $blacklist{ @$entry[0] } ) ) {
                Log3 $name, 5, "[Freezemon] $name whitelisted: " . @$entry[0];
                next;
            }
            $dev .= "fn-" . @$entry[0] . "(" . @$entry[1] . ") ";
            push @rlist, @$entry[1];
        }

        #get the timers that were executed in last cycle
        my $first = $intAtA[0]->{TRIGGERTIME};
        foreach my $c ( $hash->{helper}{inAt} ) {
            foreach my $d (@$c) {
                last if ( $d->{TRIGGERTIME} >= $first );
                my $devname = freezemon_getDevice( $hash, $d );
                if ( exists( $id{$devname} ) ) {
                    $idevFlag = $devname;
                }
                else {
                    $nidevFlag = $devname;
                }
                if ( exists( $blacklist{ $d->{FN} } ) ) {
                    Log3 $name, 5, "[Freezemon] $name whitelisted: " . $d->{FN};
                    next;
                }
                $dev .= "tmr-" . $d->{FN} . "(" . $devname . ") ";
                push @rlist, $devname;

            }
        }

        # prioQueues are not unique, so we are using the old way...
        if ( exists( $hash->{helper}{apptime} ) && $hash->{helper}{apptime} ne "" ) {
            my @olddev = split( " ", $hash->{helper}{apptime} );
            my @newdev = split( " ", freezemon_apptime($hash) );

            my %nd = map { $_ => 1 } @newdev;
            foreach my $d (@olddev) {
                if ( !exists( $nd{$d} ) ) {

                    my @a = split( ":", $d );
                    if ( exists( $id{ $a[1] } ) ) {
                        $idevFlag = $a[1];
                    }
                    else {
                        $nidevFlag = $a[1];
                    }
                    if ( exists( $blacklist{ $a[0] } ) ) {
                        Log3 $name, 5, "[Freezemon] $name whitelisted: " . $a[0];
                        next;
                    }
                    $dev .= "prio-" . $a[0] . "(" . $a[1] . ") ";
                    push @rlist, $a[1];
                }
            }
        }

        my $exists = undef;

        if ( $dev eq "" ) {
            $dev = "no bad guy found :-(";
        }

        #check ignorDev
        my $imode = "off";

        if ( AttrVal( $name, "fm_ignoreDev", undef ) ) {
            $imode = AttrVal( $name, "fm_ignoreMode", "all" );
        }

        #In "all" mode all found devices have to be in ignoreDevs (i.e. we're done if one is not in ignoreDev
        if ( $imode eq "all" and $nidevFlag ne "" ) {
            Log3 $name, 5, "[Freezemon] $name logging: $dev in $imode mode, because $nidevFlag is not ignored";
            $exists = 1;
        }

        #In "single" mode a single found device has to be in ignoreDevs (i.e. we're done if one is in ignoreDev
        elsif ( $imode eq "single" and $idevFlag ne "" ) {
            Log3 $name, 5, "[Freezemon] $name: ignoring $dev in $imode mode, because $idevFlag is ignored";
            $exists = undef;
        }
        else {
            $exists = 1;
        }

        if ($exists) {

            # determine relevant loglevel
            my $loglevel = 1;
            my %params = map { split /\:/, $_ } ( split /\ /, AttrVal( $name, "fm_log", "" ) );
            foreach my $param ( reverse sort { $a <=> $b } keys %params ) {
                if ( $freeze > $param ) {
                    $loglevel = $params{$param};
                    last;
                }
            }

            #  Create Log(
            $hash->{helper}{msg} =
              strftime(
                "[Freezemon] $name: possible freeze starting at %H:%M:%S, delay is $freeze possibly caused by: $dev",
                localtime( $hash->{helper}{TIMER} ) );

            my @t = localtime($seconds);
            my $log = ResolveDateWildcards( AttrVal( $name, "fm_logFile", undef ), @t );

            # BlockingCall for Logfile creation /create a queue
            if ( AttrVal( $name, "fm_logFile", "" ) ne "" ) {

                my @cqueue = @logqueue;
                my %lqueue = (
                    logqueue => \@cqueue,
                    msg      => $hash->{helper}{msg},
                    logfile  => $log
                );

                my @aqueue;
                if ( defined( $hash->{helper}{logfilequeue} ) ) {
                    @aqueue = @{ $hash->{helper}{logfilequeue} };
                }

                push @aqueue, \%lqueue;

                $hash->{helper}{logfilequeue} = \@aqueue;

            }

            Log3 $name, $loglevel, $hash->{helper}{msg};

            # Build hash with 20 last freezes
            my @freezes = ();
            my $dev2    = $dev =~ s/,/#&%/rg;
            push @freezes, split( ",", ReadingsVal( $name, ".fm_freezes", "" ) );
            push @freezes,
                strftime( "%Y-%m-%d", localtime )
              . freezemon_logLink( $name, $log )
              . ": s:$start e:$end f:$freeze d:$dev2";

            #while (keys @freezes > 20) {       #problem with older Perl versions
            while ( scalar(@freezes) > 20 ) {
                shift @freezes;
            }

            my $freezelist = join( ",", @freezes );

            my $fcDay = ReadingsVal( $name, "fcDay", 0 ) + 1;
            my $ftDay = ReadingsVal( $name, "ftDay", 0 ) + $freeze;
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, ".fm_freezes", $freezelist, 0 );
            readingsBulkUpdate( $hash, "state",       "s:$start e:$end f:$freeze d:$dev" );
            readingsBulkUpdate( $hash, "freezeTime",  $freeze );
            readingsBulkUpdate( $hash, "fcDay",       $fcDay );
            readingsBulkUpdate( $hash, "ftDay",       $ftDay );
            readingsBulkUpdate( $hash, "freezeDevice", $dev );

            #update statistics
            if ( AttrVal( $name, "fm_statistics", 0 ) == 1 ) {

                #some substitution
                s/(_\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}.*)// for @rlist;

                #make unique
                my %hash = map { $_, 1 } @rlist;
                my @unique = keys %hash;
                foreach my $r (@unique) {
                    next if $r eq "";

                    my $rname  = makeReadingName( "fs_" . $r . "_c" );
                    my $rtname = makeReadingName( "fs_" . $r . "_t" );
                    my $rval   = ReadingsNum( $name, $rname, 0 ) + 1;
                    readingsBulkUpdate( $hash, $rname, $rval );
                    my $rtime = ReadingsNum( $name, $rtname, 0 ) + $freeze;
                    readingsBulkUpdate( $hash, $rtname, $rtime );
                }

            }
            readingsEndUpdate( $hash, 1 );
        }
        else {
            Log3 $name, 5, "[Freezemon] $name - $dev was ignored";
        }
        ( $seconds, $microseconds ) = gettimeofday();
        @t   = localtime($seconds);
        $tim = sprintf(
            "%04d.%02d.%02d %02d:%02d:%02d.%03d",
            $t[5] + 1900,
            $t[4] + 1,
            $t[3], $t[2], $t[1], $t[0], $microseconds / 1000
        );
        my $ms = tv_interval($t0);
        Log3 $name, 5, "[Freezemon] $name: ----------- Ending Freeze handling at $tim after $ms --------";
    }

    #freezemon_purge_log_before( $hash, $hash->{helper}{TIMER} - AttrVal( $name, "fm_logExtraSeconds", 0 ) )
    # if ( AttrVal( $name, "fm_logFile", "" ) ne "" );
    undef(@logqueue);
    undef(@fmCmd);
    undef(@fmFn);

    # ---- Some stuff not required every second
    $hash->{helper}{intCount} //= 0;
    $hash->{helper}{intCount} += 1;
    if ( $hash->{helper}{intCount} >= 60 ) {
        $hash->{helper}{intCount} = 0;

        #Update dayLast readings if we have a new day
        my $last = ReadingsVal( $name, ".lastDay", "" );
        my $dnow = strftime( "%Y-%m-%d", localtime );
        if ( $last eq "" ) {
            readingsSingleUpdate( $hash, ".lastDay", $dnow, 0 );
        }
        elsif ( $dnow gt $last ) {
            my $fcDay = ReadingsVal( $name, "fcDay", 0 );
            my $ftDay = ReadingsVal( $name, "ftDay", 0 );
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "fcDayLast", $fcDay );
            readingsBulkUpdate( $hash, "ftDayLast", $ftDay );
            readingsBulkUpdate( $hash, "fcDay",     0 );
            readingsBulkUpdate( $hash, "ftDay",     0 );
            readingsBulkUpdate( $hash, ".lastDay",  $dnow, 0 );
            readingsEndUpdate( $hash, 1 );
        }

        # check if apptime is active
        if ( AttrVal( $name, "fm_forceApptime", 0 ) == 1
            and !defined( $cmds{"apptime"} ) )
        {
            no warnings;
            fhem( "apptime", 1 );
        }

        # check apptime overwrote freezemon CallFn
        freezemon_install_callFn_wrapper( $hash, 1 ) if AttrVal( $name, "fm_CatchFnCalls", 0 ) == 1;

        # let's get rid of old logs
        if ( my $keep = AttrVal( $name, "fm_logKeep", undef ) ) {
            my @fl   = freezemon_getLogFiles( $name, 1 );
            my $path = freezemon_getLogPath($name);
            my $max  = scalar(@fl) - $keep;
            for ( my $i = 0 ; $i < $max ; $i++ ) {
                Log3 $name, 4, "[Freezemon] $name: Deleting $fl[$i]";
                unlink("$path/$fl[$i]");
            }
        }

    }

    # process logqueue non-blocking every 5 seconds
    if ( $hash->{helper}{intCount} % 5 == 0 ) {
        if ( !defined( $hash->{helper}{blocking} ) ) {
            my $e = shift @{ $hash->{helper}{logfilequeue} };
            if ( defined($e) ) {

                #$hash->{helper}{logentry} = $e;
                $e->{NAME} = $name;
                $hash->{helper}{blocking} =
                  BlockingCall( "freezemon_processBlocking", $e, "freezemon_freezeDone", 120, "freezemon_freezeAbort",
                    $hash );
                Log3 $name, 5, "[Freezemon] $name: Blocking Call started with PID $hash->{helper}{blocking}{pid}";
            }
        }
    }

    # start next timer
    $hash->{helper}{fn} = "";

    $hash->{helper}{apptime} = freezemon_apptime($hash);
    $hash->{helper}{inAt}    = [@intAtA];
    $hash->{helper}{TIMER}   = int($now) + 1;
    InternalTimer( $hash->{helper}{TIMER}, 'freezemon_ProcessTimer', $hash, 0 );
}
###################################
sub freezemon_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    my $usage =
"Unknown argument $cmd, choose one of getFreezes:noArg active:noArg inactive:noArg clear:statistics_all,statistics_low,all";

    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "inactive" ) {
        RemoveInternalTimer($hash);
        readingsSingleUpdate( $hash, "state", "inactive", 1 );
        $hash->{helper}{DISABLED} = 1;
        freezemon_unwrap_all($hash);
    }
    elsif ( $cmd eq "active" ) {
        if ( IsDisabled($name) ) {    #&& !AttrVal( $name, "disable", undef ) ) {
            freezemon_start($hash);
        }
        else {
            return "Freezemon $name is already active";
        }
    }
    elsif ( $cmd eq "clear" ) {
        if ( $args[0] eq "all" ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "fcDayLast",   0,  1 );
            readingsBulkUpdate( $hash, "ftDayLast",   0,  1 );
            readingsBulkUpdate( $hash, "fcDay",       0,  1 );
            readingsBulkUpdate( $hash, "ftDay",       0,  1 );
            readingsBulkUpdate( $hash, ".lastDay",    "", 1 );
            readingsBulkUpdate( $hash, ".fm_freezes", "", 1 );
            if ( !IsDisabled($name) ) {
                readingsBulkUpdate( $hash, "state", "initialized", 1 );
            }
            readingsBulkUpdate( $hash, "freezeTime",   0,  1 );
            readingsBulkUpdate( $hash, "freezeDevice", "", 1 );
            readingsEndUpdate( $hash, 1 );
        }
        elsif ( $args[0] eq "statistics_all" ) {
            CommandDeleteReading( undef, "$name fs_.*" );
        }
        elsif ( $args[0] eq "statistics_low" ) {
            my ( $lowc, $lowt ) = split( ":", AttrVal( $name, "fm_statistics_low", "0:0" ) );
            foreach my $r ( keys %{ $hash->{READINGS} } ) {
                next unless ( $r =~ /fs_.*_c/ );
                my $rc = ReadingsNum( $name, $r, 0 );
                my $t  = $r =~ s/_c/_t/r;
                my $rt = ReadingsNum( $name, $t, 0 );
                if ( $rc <= $lowc && $rt <= $lowt ) {
                    Log3 $name, 4, "[Freezemon] $name: Deleting readings $r, $t: $rc < $lowc && $rt < $lowt";
                    CommandDeleteReading( undef, "$name " . $r );
                    CommandDeleteReading( undef, "$name " . $t );
                }
            }
        }
        else {
            return "unknown argument $args[0]";
        }
    }
    elsif ( $cmd eq "getFreezes" ) {
        my $ret     = "";
        my @colors  = ( "red", "yellow", "green", "white", "gray" );
        my @freezes = split( ",", ReadingsVal( $name, ".fm_freezes", "" ) );
        foreach (@freezes) {
            my $loglevel = 1;
            my $freeze   = $_;
            if ( $freeze =~ /f:(.*)d:/ ) {
                $freeze = $1;
            }
            my %params = map { split /\:/, $_ } ( split /\ /, AttrVal( $name, "fm_log", "" ) );
            foreach my $param ( reverse sort { $a <=> $b } keys %params ) {
                if ( $freeze > $param ) {
                    $loglevel = $params{$param};
                    last;
                }
            }
            $_ =~ s/(?<=.{240}).{1,}$/.../;
            $_ =~ s/&%%CSRF%%/$FW_CSRF/;
            $_ =~ s/#&%/,/g;
            $ret .= "<font color='$colors[$loglevel-1]'><b>" . $loglevel . "</b></font> - " . $_ . "<br>";

        }

        return "<html>" . $ret . "</html>";

    }

    else {
        return $usage;
    }
    return undef;
}

###################################
sub freezemon_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};
    my $ret   = "";
    my $usage = 'Unknown argument $a[1], choose one of statistic:noArg freeze:noArg log:';

    return "\"get $name\" needs at least one argument" unless ( defined( $a[1] ) );

    #get the logfiles
    my @fl = freezemon_getLogFiles($name);

    my $sfl = join( ",", @fl );
    $usage .= $sfl;

    # Get freeze entries
    if ( $a[1] eq "freeze" ) {

        my @colors = ( "red", "yellow", "green", "white", "gray" );
        my @freezes = split( ",", ReadingsVal( $name, ".fm_freezes", "" ) );
        foreach (@freezes) {
            my $loglevel = 1;
            my $freeze   = $_;
            if ( $freeze =~ /f:(.*)d:/ ) {
                $freeze = $1;
            }
            my %params = map { split /\:/, $_ } ( split /\ /, AttrVal( $name, "fm_log", "" ) );
            foreach my $param ( reverse sort { $a <=> $b } keys %params ) {
                if ( $freeze > $param ) {
                    $loglevel = $params{$param};
                    last;
                }
            }
            $_ =~ s/(?<=.{240}).{1,}$/.../;
            $_ =~ s/&%%CSRF%%/$FW_CSRF/;
            $_ =~ s/#&%/,/g;
            $ret .= "<font color='$colors[$loglevel-1]'><b>" . $loglevel . "</b></font> - " . $_ . "<br>";

        }

        return "<html>" . $ret . "</html>";
    }
    elsif ( $a[1] eq "statistic" ) {
        my %stats;
        foreach my $r ( keys %{ $hash->{READINGS} } ) {
            next unless ( $r =~ /^fs_(.*)_c$/ );
            my $dev = $1;
            my $rc  = ReadingsNum( $name, $r, 0 );
            my $t   = $r =~ s/_c/_t/r;
            my $rt  = ReadingsNum( $name, $t, 0 );

            $stats{"$dev"}{cnt}  = $rc;
            $stats{"$dev"}{time} = $rt;
        }

        my @positioned =
          sort { $stats{$b}{cnt} <=> $stats{$a}{cnt} or $stats{$b}{time} <=> $stats{$a}{time} } keys %stats;
        my $ret = "<html>";
        $ret .= "<table><tr><th>Device</th><th>Count</th><th>Time</th></tr>";
        my $i;
        foreach my $p (@positioned) {
            last if $i > 20;
            $i++;
            $ret .= "<tr><td>$p</td><td>" . $stats{"$p"}{cnt} . "</td><td>" . $stats{"$p"}{time} . "</td></tr>";
        }
        $ret .= "</table></html>";
        return $ret;

    }
    elsif ( $a[1] eq "log" ) {
        return "No Filename given" if ( !defined( $a[2] ) );

        # extract the filename from given argument (in case it comes with path)
        my $gf = $a[2];
        if ( $gf =~ m,^(.*)/([^/]*)$, ) {
            $gf = $2;
        }
        my $path = freezemon_getLogPath($name);

        # Build the complete path (using global logfile parameter if necessary)
        $path = "$path/$gf";

        if ( !open( my $fh, $path ) ) {
            return "Couldn't open $path";
        }
        else {
            my $ret = "<html><br><a name='top'></a><a href='#end_of_file'>jump to the end</a><br><br>";
            while ( my $row = <$fh> ) {
                $ret .= $row . "<br>";
            }
            $ret .= "<br><a name='end_of_file'></a><a href='#top'>jump to the top</a><br/><br/></html>";
            return $ret;
        }

    }

    # return usage hint
    else {

        return $usage;
    }
    return undef;
}
###################################
sub freezemon_Attr($) {

    my ( $cmd, $name, $aName, $aVal ) = @_;
    my $hash = $defs{$name};

    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    #Log3 $name, 3, "$cmd $aName $aVal";
    if ( $cmd eq "set" ) {

        if ( $aName eq "fm_forceApptime" ) {
            if ( $aVal > 1 or $aVal < 0 ) {
                Log3 $name, 3, "$name: $aName is either 0 or 1: $aVal";
                return "Attribute " . $aName . " is either 0 or 1";
            }
        }
        elsif ( $aName eq "fm_freezeThreshold" ) {
            if ( !looks_like_number($aVal) ) {
                return "Attribute " . $aName . " has to be a number (seconds) ";
            }
        }
        elsif ( $aName eq "fm_logKeep" ) {
            if ( !looks_like_number($aVal) or $aVal <= 0 ) {
                return "Attribute " . $aName . " has to be a number > 0";
            }

        }
        elsif ( $aName eq "fm_logFile" ) {

            if ( $aVal ne "" ) {
                $aVal =~ m,^(.*)/([^/]*)$,;
                my $path = $1;
                $path =~ s/%L/$attr{global}{logdir}/g if ( $path =~ m/%/ && $attr{global}{logdir} );
                if ( opendir( DH, $path ) ) {
                    freezemon_install_log_wrapper($hash);
                    closedir(DH);
                }
                else {
                    return "Attribute " . $aName . ": $path is not a valid directory";
                }
            }
            else {
                return "Attribute " . $aName . ": Enter a valid path or delete the attribute to disable.";
            }
        }
        elsif ( $aName eq "fm_CatchFnCalls" ) {

            if ( $aVal ne 0 ) {
                freezemon_install_callFn_wrapper($hash);
                $fmFnLog = $aVal;
                $fmName  = $name;

            }
            elsif ( defined( $hash->{helper}{mycallFn} ) ) {
                Log3( "", 0, "[Freezemon] $name: Unwrapping CallFn" );
                {
                    no warnings;
                    *main::CallFn = $hash->{helper}{mycallFn};
                    $hash->{helper}{mycallFn} = undef;
                }
            }
            else {
                Log3( "", 0, "[Freezemon] $name: Unwrapping CallFn - nothing to do" );
            }
        }
        elsif ( $aName eq "fm_CatchCmds" ) {

            if ( $aVal ne 0 ) {
                freezemon_install_AnalyzeCommand_wrapper($hash);
                $fmCmdLog = $aVal;
                $fmName   = $name;
            }
            elsif ( defined( $hash->{helper}{AnalyzeCommand} ) ) {
                Log3( "", 0, "[Freezemon] $name: Unwrapping AnalyzeCommand" );
                {
                    no warnings;
                    *main::AnalyzeCommand = $hash->{helper}{AnalyzeCommand};
                    $hash->{helper}{AnalyzeCommand} = undef;
                }
            }
            else {
                Log3( "", 0, "[Freezemon] $name: Unwrapping AnalyzeCommand - nothing to do" );
            }
        }

        elsif ( $aName eq "disable" ) {
            if ( $aVal == 1 ) {
                RemoveInternalTimer($hash);
                readingsSingleUpdate( $hash, "state", "inactive", 1 );
                $hash->{helper}{DISABLED} = 1;
                freezemon_unwrap_all($hash);
            }
            elsif ( $aVal == 0 ) {
                freezemon_start($hash);
            }
            elsif ( $aName eq "fm_statistics" ) {
                if ( $aVal == 1 ) {
                    $hash->{helper}{statistics} = 1;
                }
                elsif ( $aVal == 0 ) {
                    $hash->{helper}{statistics} = 0;
                }
            }

        }
        elsif ( $aName eq "fm_statistics_low" ) {
            if ( !( $aVal =~ /\d+\:\d+/ ) ) {
                return "Attribute " . $aName . " has to be in the format 1:2 (meaning count 1:seconds 2)";
            }

        }
    }
    elsif ( $cmd eq "del" ) {
        if ( $aName eq "disable" ) {
            freezemon_start($hash);
        }
        elsif ( $aName eq "fm_logFile" ) {
            my $status = Log3( "", 100, "" );
            Log3( "", 0, "[Freezemon] $name: Unwrapping Log3" );
            *main::Log3 = $hash->{helper}{Log3};
            $hash->{helper}{Log3} = undef;
        }
        elsif ( $aName eq "fm_CatchFnCalls" ) {
            Log3( "", 0, "[Freezemon] $name: Unwrapping CallFn" );
            {
                no warnings;
                *main::CallFn = $hash->{helper}{mycallFn};
                $hash->{helper}{mycallFn} = undef;
            }
        }
        elsif ( $aName eq "fm_CatchCmds" ) {
            Log3( "", 0, "[Freezemon] $name: Unwrapping AnalyzeCommand" );
            {
                no warnings;
                *main::AnalyzeCommand = $hash->{helper}{AnalyzeCommand};
                $hash->{helper}{AnalyzeCommand} = undef;
            }
        }
        elsif ( $aName eq "fm_statistics" ) {
            $hash->{helper}{statistics} = 0;
        }

    }

    return undef;

}

###################################
# Helper Functions                #
###################################

###################################
sub freezemon_start($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( exists( $hash->{helper}{DISABLED} )
        and $hash->{helper}{DISABLED} == 1 )
    {
        readingsSingleUpdate( $hash, "state", "initialized", 0 );
        freezemon_install_log_wrapper($hash)            if AttrVal( $name, "fm_logFile",      "" ) ne "";
        freezemon_install_callFn_wrapper($hash)         if AttrVal( $name, "fm_CatchFnCalls", 0 ) > 0;
        freezemon_install_AnalyzeCommand_wrapper($hash) if AttrVal( $name, "fm_CatchCmds",    0 ) > 0;

    }
    $fmName   = $name;
    $fmCmdLog = AttrVal( $name, "fm_CatchCmds", 0 );
    $fmFnLog  = AttrVal( $name, "fm_CatchFnCalls", 0 );

    $hash->{helper}{DISABLED} = 0;
    my $next = int( gettimeofday() ) + 1;
    $hash->{helper}{TIMER} = $next;

    InternalTimer( $next, 'freezemon_ProcessTimer', $hash, 0 );
    Log3 $name, 2,
        "[Freezemon] $name: ready to watch out for delays greater than "
      . AttrVal( $name, "fm_freezeThreshold", 1 )
      . " second(s)";
    if ( AttrVal( $name, "fm_logExtraSeconds", undef ) ) {
        Log3 $name, 1,
"[Freezemon] $name: Attribute fm_logExtraSeconds is deprecated and not considered anymore by Freezemon. Please delete the attribute.";
    }
}

###################################
sub freezemon_apptime($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $ret    = "";
    my ( $fn, $tim, $cv, $fnname, $arg, $shortarg );
    if (%prioQueues) {

        foreach my $prio ( keys %prioQueues ) {
            foreach my $entry ( @{ $prioQueues{$prio} } ) {

                #Log3 $name, 5, "Freezemon: entry is ".Dumper($entry);
                $cv     = svref_2object( $entry->{fn} );
                $fnname = $cv->GV->NAME;
                $ret .= $fnname;

                #$shortarg = ( defined( $entry->{arg} ) ? $entry->{arg} : "" );
                if ( defined( $entry->{arg} ) ) {
                    $shortarg = $entry->{arg};

                    #Log3 $name, 5, "Freezemon: found a prioQueue arg ".ref($shortarg);
                    if ( ref($shortarg) eq "HASH" ) {
                        if ( !defined( $shortarg->{NAME} ) ) {
                            $shortarg = "N/A";
                        }
                        else {
                            $shortarg = $shortarg->{NAME};
                        }
                    }
                    elsif ( ref($shortarg) eq "ARRAY" ) {
                        $shortarg = $entry->{arg};
                    }

                    ( $shortarg, undef ) = split( /:|;/, $shortarg, 2 );
                }

                $shortarg = "N/A" unless defined($shortarg);
                $ret .= ":" . $shortarg . " ";

                #Log3 $name, 5, "Freezemon: found a prioQueue, returning $ret";
            }
        }
    }

    return $ret;
}
###################################
sub freezemon_getDevice($$) {
    my ( $hash, $d ) = @_;
    my $name = $hash->{NAME};

    my $fn = $d->{FN};

    if ( ref($fn) ne "" ) {
        my $cv     = svref_2object($fn);
        my $fnname = $cv->GV->NAME;
        return $fnname;
    }
    my $arg = $d->{ARG};

    my $shortarg = ( defined($arg) ? $arg : "" );
    if ( ref($shortarg) eq "HASH" ) {
        if ( !defined( $shortarg->{NAME} ) ) {
            if ( AttrVal( $name, "fm_extDetail", 0 ) == 1 ) {
                if ( $fn eq "BlockingKill" or $fn eq "BlockingStart" ) {
                    $shortarg = $shortarg->{abortArg}{NAME} if defined( $shortarg->{abortArg}{NAME} );
                }
                elsif ( $fn eq "HttpUtils_Err" ) {

                    #Log3 $name, 5, "[Freezemon] HttpUtils_Err found" . Dumper($shortarg);
                    if ( defined( $shortarg->{hash}{hash}{NAME} ) ) {
                        $shortarg = $shortarg->{hash}{hash}{NAME};

                    }
                }
                elsif ( $fn = "FileLog_dailySwitch" ) {
                    $shortarg = $shortarg->{NotifyFn};
                }
                else {
                    #Log3 $name, 5, "[Freezemon] $name found something without a name $fn" . Dumper($shortarg);
                    $shortarg = "N/A";
                }
            }
            else {
                $shortarg = "N/A";
            }
        }
        else {
            $shortarg = $shortarg->{NAME};
        }
    }
    elsif ( ref($shortarg) eq "REF" ) {
        if ( $fn eq "DOIF_TimerTrigger" ) {
            my $deref = ${$arg};    #seems like $arg is a reference to a scalar which in turm is a reference to a hash
            $shortarg = $deref->{'hash'}{NAME};    #at least in DOIF_TimerTrigger
        }
        else {
            #Log3 $name, 5, "[Freezemon] $name  found a REF $fn " . Dumper( ${$arg} );
        }
    }
    elsif ( ref($shortarg) eq "" ) {
        Log3 $name, 5,
          "[Freezemon] $name found something that's not a REF $fn " . ref($shortarg) . " " . Dumper($shortarg);

        ( undef, $shortarg ) = split( /:|;/, $shortarg, 2 );
    }

    else {
        Log3 $name, 5,
            "[Freezemon] $name found something that's a REF but not a HASH $fn "
          . ref($shortarg) . " "
          . Dumper($shortarg);

        $shortarg = "N/A";
    }
    if ( !defined($shortarg) ) {

        Log3 $name, 5, "Freezemon: something went wrong $fn " . Dumper($arg);
        $shortarg = "N/A";
    }
    else {
        ( $shortarg, undef ) = split( /:|;/, $shortarg, 2 );
    }
    return $shortarg;
}
###################################
sub freezemon_unwrap_all($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3( "", 0, "[Freezemon] $name: Unwrapping CallFn" );
    {
        no warnings;
        *main::CallFn = $hash->{helper}{mycallFn} if defined( $hash->{helper}{mycallFn} );
        $hash->{helper}{mycallFn} = undef;
    }
    Log3( "", 0, "[Freezemon] $name: Unwrapping AnalyzeCommand" );
    {
        no warnings;
        *main::AnalyzeCommand = $hash->{helper}{AnalyzeCommand} if defined( $hash->{helper}{AnalyzeCommand} );
        $hash->{helper}{AnalyzeCommand} = undef;
    }
    my $status = Log3( "", 100, "" );
    Log3( "", 0, "[Freezemon] $name: Unwrapping Log3" );
    {
        no warnings;
        *main::Log3 = $hash->{helper}{Log3} if defined( $hash->{helper}{Log3} );
        $hash->{helper}{Log3} = undef;
    }
}

###################################
sub freezemon_callFn($@) {
    my ( $lfn, @args ) = @_;

    # take current time, then immediately call the original  function
    my $t0 = [gettimeofday];
    my ( $result, $p ) = $lfn->(@args);
    my $ms = tv_interval($t0);
    my $d  = $args[0];
    my $n  = $args[1];

    if ( $ms >= 0.5 ) {
        push @fmFn, [ $n, $d ];

        #$fm_fn .= "$n:$d ";
        Log3 $fmName, $fmFnLog, "[Freezemon] $fmName: Long function call detected $n:$d - $ms seconds";
    }
    return ( $result, $p ) if ($p);
    return $result;
}
###################################
sub freezemon_AnalyzeCommand($$$;$) {
    my ( $lfn, $cl, $cmd, $cfc ) = @_;

    # take current time, then immediately call the original  function
    my $t0     = [gettimeofday];
    my $result = $lfn->( $cl, $cmd, $cfc );
    my $ms     = tv_interval($t0);
    my $d      = "";
    my $n      = $cmd;
    if ( exists( $cl->{SNAME} ) ) {
        $d = $cl->{SNAME};
    }
    else {
        $d = "N/A";
    }

    if ( $ms >= 0.5 ) {
        push @fmCmd, [ $n, $d ];

        #$fm_fn .= "$n:$d ";
        Log3 $fmName, $fmCmdLog, "[Freezemon] $fmName: Long running Command detected $n:$d - $ms seconds";
    }

    #return ($result,$p) if ($p) ;
    return $result;
}

###################################
sub freezemon_checkCallFnWrap() {
    return "freezemon called";
}

###################################
sub freezemon_Log3($$$$) {
    my ( $lfn, $dev, $loglevel, $text ) = @_;

    # take current time, then immediately call the original log function
    my ( $seconds, $microseconds ) = gettimeofday();
    my $result = $lfn->( $dev, $loglevel, $text );

    my @entry = ( $seconds + $microseconds * 1e-6, $dev, $loglevel, $text );
    push( @logqueue, \@entry ) unless ( $loglevel > 5 );

    # print LOG "logqueue has now ".(scalar @logqueue)." entries";

    return $result;
}
###################################
sub freezemon_wrap_callFn($) {
    my ($fn) = @_;
    return sub(@) {
        my @a = @_;
        return "already wrapped" if $a[1] eq "freezemon_checkCallFnWrap";
        return freezemon_callFn( $fn, @a );
      }
}

###################################
sub freezemon_wrap_AnalyzeCommand($) {
    my ($fn) = @_;
    return sub($$;$) {
        my ( $cl, $cmd, $cfc ) = @_;
        return "already wrapped" if ( defined($cl) && $cl eq "freezemon" );
        return freezemon_AnalyzeCommand( $fn, $cl, $cmd, $cfc );
      }
}

###################################
sub freezemon_wrap_Log3($) {
    my ($fn) = @_;
    return sub($$$) {
        my ( $a, $b, $c ) = @_;
        return "already wrapped" if ( $b == 99 );
        return $fn if ( $b == 100 );
        return freezemon_Log3( $fn, $a, $b, $c );
      }
}
###################################
#AnalyzeCommand($$;$)
sub freezemon_install_AnalyzeCommand_wrapper($;$) {
    my ( $hash, $nolog ) = @_;
    my $name = $hash->{NAME};
    $name = "FreezeMon" unless defined($name);
    my $status = AnalyzeCommand( "freezemon", "" );
    if ( !defined($status) || $status ne "already wrapped" ) {
        $hash->{helper}{AnalyzeCommand} = \&AnalyzeCommand;
        Log3( "", 3, "[Freezemon] $name: Wrapping AnalyzeCommand" );
        {
            no warnings;
            *main::AnalyzeCommand = freezemon_wrap_AnalyzeCommand( \&AnalyzeCommand );
        }
    }
    elsif ( !defined($nolog) ) {
        Log3 $name, 3, "[Freezemon] $name: AnalyzeCommand already wrapped";
    }
}

###################################
sub freezemon_install_callFn_wrapper($;$) {
    my ( $hash, $nolog ) = @_;
    my $name = $hash->{NAME};
    $name = "FreezeMon" unless defined($name);
    my $status = CallFn( $name, "freezemon_checkCallFnWrap" );
    if ( !defined($status) || $status ne "already wrapped" ) {
        $hash->{helper}{mycallFn} = \&CallFn;
        Log3( "", 3, "[Freezemon] $name: Wrapping CallFn" );
        {
            no warnings;
            *main::CallFn = freezemon_wrap_callFn( \&CallFn );
        }
    }
    elsif ( !defined($nolog) ) {
        Log3 $name, 3, "[Freezemon] $name: CallFn already wrapped";
    }
}

###################################
sub freezemon_install_log_wrapper($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $name = "FreezeMon" unless defined($name);
    my $status = Log3( "", 99, "" );
    if ( !defined($status) || $status ne "already wrapped" ) {
        Log3( "", 3, "[Freezemon] $name: Wrapping Log3" );
        $hash->{helper}{Log3} = \&Log3;
        {
            no warnings;
            *main::Log3 = freezemon_wrap_Log3( \&Log3 );
        }
    }
    else {
        Log3 $name, 5, "[Freezemon] $name: Log3 is already wrapped";
    }
}
###################################
sub freezemon_purge_log_before($$) {
    my ( $hash, $before ) = @_;
    my $name = $hash->{NAME};
    my @t    = localtime($before);
    my $tim  = sprintf( "%04d.%02d.%02d %02d:%02d:%02d.%03d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], 0 );

    #Log3 $hash, 5, "[Freezemon] $name: purging log entries before $tim.";
    my $cnt = 0;
    while ( scalar @logqueue > 0 && $logqueue[0]->[0] < $before ) {
        shift @logqueue;
        $cnt += 1;
    }

    #Log3 $hash, 5, "[Freezemon] $name: $cnt entries purged from logqueue, size is now ".(scalar @logqueue);
}
###################################
sub freezemon_dump_log2($$$$) {
    my ( $name, $msg, $logfile, $queue ) = @_;

    #my $name = $hash->{NAME};

    #my @queue = @{ $hash->{helper}{logqueue} };

    return unless scalar @$queue;

    my ( $seconds, $microseconds ) = gettimeofday();

    my $currlogfile = $logfile;

    return unless defined($currlogfile) && $currlogfile ne "";
    Log3 $name, 4, "[Freezemon] $name: dumping " . ( scalar @$queue ) . " log entries to $currlogfile";

    open( fm_LOG, ">>$currlogfile" ) || return ("Can't open $currlogfile: $!");

    print fm_LOG "=========================================================\n";
    print fm_LOG $msg . "\n";
    my $last_ts;
    foreach my $entry (@$queue) {
        my ( $ts, $dev, $loglevel, $text ) = @$entry;
        my $seconds = int($ts);
        my $microseconds = int( 1e6 * ( $ts - $seconds ) );
        $dev = $dev->{NAME} if ( defined($dev) && ref($dev) eq "HASH" );

        #next if ( defined($dev) && ( $dev eq $name ) );

        my @t   = localtime($seconds);
        my $tim = sprintf(
            "%04d.%02d.%02d %02d:%02d:%02d.%03d",
            $t[5] + 1900,
            $t[4] + 1,
            $t[3], $t[2], $t[1], $t[0], $microseconds / 1000
        );

        printf fm_LOG "--- log skips %9.3f secs.\n", $ts - $last_ts if ( defined($last_ts) && $ts - $last_ts > 1 );
        print fm_LOG "$tim $loglevel: $text\n";
        $last_ts = $ts;
    }

    print fm_LOG $msg . "\n";
    close(fm_LOG);

    return $currlogfile;
}

###################################
sub freezemon_dump_log($$$) {
    my ( $hash, $start, $msg ) = @_;
    my $name  = $hash->{NAME};
    my @queue = @{ $hash->{helper}{logqueue} };

    return unless scalar @queue;

    my ( $seconds, $microseconds ) = gettimeofday();

    my $currlogfile = $hash->{helper}{logfile};

    return unless defined($currlogfile) && $currlogfile ne "";
    Log3 $name, 4, "[Freezemon] $name: dumping " . ( scalar @queue ) . " log entries to $currlogfile";

    open( fm_LOG, ">>$currlogfile" ) || return ("Can't open $currlogfile: $!");

    print fm_LOG "=========================================================\n";
    print fm_LOG $msg . "\n";
    my $last_ts;
    foreach my $entry (@queue) {
        my ( $ts, $dev, $loglevel, $text ) = @$entry;
        my $seconds = int($ts);
        my $microseconds = int( 1e6 * ( $ts - $seconds ) );
        $dev = $dev->{NAME} if ( defined($dev) && ref($dev) eq "HASH" );

        #next if ( defined($dev) && ( $dev eq $name ) );

        my @t   = localtime($seconds);
        my $tim = sprintf(
            "%04d.%02d.%02d %02d:%02d:%02d.%03d",
            $t[5] + 1900,
            $t[4] + 1,
            $t[3], $t[2], $t[1], $t[0], $microseconds / 1000
        );

        printf fm_LOG "--- log skips %9.3f secs.\n", $ts - $last_ts if ( defined($last_ts) && $ts - $last_ts > 1 );
        print fm_LOG "$tim $loglevel: $text\n";
        $last_ts = $ts;
    }

    print fm_LOG $msg . "\n";
    close(fm_LOG);

    return $currlogfile;
}
###################################
sub freezemon_logLink($$) {
    my ( $name, $link ) = @_;
    return "" if !$link;
    my $me;
    if ( defined($FW_ME) ) {
        $me = $FW_ME;
    }
    else {
        $me = "fhem";
    }

    my $ret = "<a href='$me?cmd=" . urlEncode("get $name log $link") . "&%%CSRF%%'> [Log]</a>";
    return $ret;
}
###################################
sub freezemon_getLogFiles($;$) {
    my ( $name, $reverse ) = @_;
    my @fl;

    my $path = freezemon_getLogPath($name);
    return @fl if ( !$path );
    my $lf = AttrVal( $name, "fm_logFile", "" );
    $lf =~ m,^(.*)/([^/%]*).*$,;
    my $pattern = $2;

    if ( opendir( DH, $path ) ) {
        while ( my $f = readdir(DH) ) {
            push( @fl, $f ) if ( $f =~ /$pattern.*/ );
        }
        closedir(DH);
        if ( !$reverse ) {
            @fl = sort { ( CORE::stat("$path/$b") )[9] <=> ( CORE::stat("$path/$a") )[9] } @fl;
        }
        else {
            @fl = sort { ( CORE::stat("$path/$a") )[9] <=> ( CORE::stat("$path/$b") )[9] } @fl;
        }
    }
    return @fl;
}
###################################
sub freezemon_getLogPath($) {
    my ($name) = @_;
    my $lf = AttrVal( $name, "fm_logFile", "" );
    return undef if $lf eq "";
    $lf =~ m,^(.*)/([^/%]*).*$,;
    my $path = $1;
    $path =~ s/%L/$attr{global}{logdir}/g if ( $path =~ m/%/ && $attr{global}{logdir} );
    return $path;
}

1;

=pod
=item helper
=item summary An adjusted version of PERFMON that helps detecting freezes
=item summary_DE Eine angepasste Version von PERFMON, die beim Erkennen von freezes hilft
=begin html

<a name="freezemon"></a>
<h3>freezemon</h3>
<div>
	<ul>
		FREEZEMON monitors - similar to PERFMON possible freezes, however FREEZEMON is a real module, hence it has:<br><br>
		<ul>
			<li>Readings - which might be logged for easier analysis</li>
			<li>Attributes - to influence the behaviour of the module</li>
			<li>additional functionality - which tries to identify the device causing the freeze</li>
		</ul>
		It's recommended to deactivate PERFMON once FREEZEMON is active. They anyways detect the same freezes thus everything would be duplicated.<br><br>
		<b>Please note!</b> FREEZEMON just does an educated guess, which device could have caused the freeze based on timers that were supposed to run. There might be a lot of other factors (internal or external) causing freezes. FREEZEMON doesn't replace a more detailed analysis. The module just tries to give you some hints what could be optimized.<br><br>
<a name="freezemonDefine"></a>
  <b>Define</b>
  <ul>
	FREEZEMON will be defined without Parameters.
	<br><br>
	<code>define &lt;devicename&gt; freezemon</code><br><br>
	With that freezemon is active (and you should see a message in the log) <br><br>
  </ul>
  <a name="freezemonSet"></a>
  <b>Set</b>
  <ul>
	<ul>
		<li><a name="inactive">inactive</a>: disables the device (similar to attribute "disable", however without the need to save</li>
		<li><a name="active">active</a>: reactivates the device after it was set inactive</li>
		<li><a name="clear">clear</a>: 
			<ul><li>statistics_all: clears the statistics (i.e. deletes all the readings created for statistics)</li>
			<li>statistics_low: clears the statistics with low significance (see attribute fm_statistics_low)</li>
			<li>all: clears all readings (including the list of the last 20 freezes.)</li>
			<li><a name="getFreezes">getFreezes</a>: similar to "get freeze", however as a set command it can be used e.g. in webCmd Attribute</li>
			</ul></li>
	</ul>
  </ul>	
<a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
	<ul>
		<li><a name="freeze">freeze</a>: returns the last 20 freezes (in compact view, like in state) - This is for a quick overview. For detailed analysis the data should be logged.</li>
		<li><a name="log">log</a>: provides direct access to the logfiles written when fm_logFile is active</li>
		<li><a name="statistic">statistic</a>: Provides a nicer formatted overview of the top 20 devices from freeze statistics</li>
	</ul>
  </ul>
  
 <a name="freezemonReadings"></a>
  <b>Readings</b>
		<ul>
			<ul>
				<li><a name="freezeTime">freezeTime</a>: Duration of the freeze</li>
				<li>freezeDevice: List of functions(Devices) that possibly caused the freeze</li>
				<li>fcDay: cumulated no. of freezes per day</li>
				<li>ftDay: cumulated duration of freezes per day</li>
				<li>fcDayLast: stores cumulated no. of freezes of the last day (for daily plots). Due to technical reasons, freezes that occur shortly after midnight might still be taken into account  for previous day.</li>
				<li>ftDayLast: stores cumulated duration of freezes of the last day (for daily plots). Due to technical reasons, freezes that occur shortly after midnight might still be taken into account  for previous day.</li>
				<li>fs_.*_c: freeze statistics - count of freezes where the device was probably involved</li>
				<li>fs_.*_t: freeze statistics - cumulated time of freezes where the device was probably involved</li>
				<li>state: s:&lt;startTime&gt; e:&lt;endTime&gt; f:&lt;Duration&gt; d:&lt;Devices&gt;</li>;
				
			</ul>
		</ul>

<a name="freezemonattr"></a>
  <b>Attributes</b>
		<ul>
			<ul>
				<li><a name="fm_CatchFnCalls">fm_CatchFnCalls</a>: if enabled FHEM internal function calls are monitored additionally, 
				in some cases this might give additional hints on who's causing the freeze. 0 means disabled, numbers >= 1 describe the loglevel for logging long running function calls.</li>
				<li><a name="fm_CatchCmds">fm_CatchCmds</a>: if enabled FHEM commands are monitored additionally, 
				in some cases this might give additional hints on who's causing the freeze, 0 means disabled, numbers >= 1 describe the loglevel for logging long running commands. </li>
				<li><a name="fm_extDetail">fm_extDetail</a>: provides in some cases extended details for recognized freezes. In some cases it was reported that FHEM crashes, so please be careful.</li>
				<li><a name="fm_freezeThreshold">fm_freezeThreshold</a>: Value in seconds (Default: 1) - Only freezes longer than fm_freezeThreshold will be considered as a freeze</li>
				<li><a name="fm_forceApptime">fm_forceApptime</a>: When FREEZEMON is active, apptime will automatically be started (if not yet active)</li>
				<li><a name="fm_ignoreDev">fm_ignoreDev</a>: list of comma separated Device names. If all devices possibly causing a freeze are in the list, the freeze will be ignored (not logged)</li>
				<li><a name="fm_ignoreMode">fm_ignoreMode</a>: takes the values off,single or all. If you have added devices to fm_ignoreDev then ignoreMode acts as follows: <br>
				all: A freeze will only be ignored, if all devices probably causing the freeze are part of the ignore list. This might result in more freezes being logged than expected.<br>
				single: A freeze will be ignored as soon as one device possibly causing the freeze is listed in the ignore list. With this setting you might miss freezes.<br>
				off: All freezes will be logged.<br>
				If the attribute is not set, while the ignore list is maintained, mode "all" will be used.</li>
				<li><a name="fm_log">fm_log</a>: dynamic loglevel, takes a string like 10:1 5:2 1:3 , which means: freezes > 10 seconds will be logged with loglevel 1 , >5 seconds with loglevel 2 etc...</li>
				<li><a name="fm_logFile">fm_logFile</a>: takes a valid file name (like e.g. ./log/freeze-%Y%m%d-%H%M%S.log). If set, logs messages of loglevel 5 (even if global loglevel is < 5) before a freeze in separate file.</li>
				<li><a name="fm_logExtraSeconds">fm_logExtraSeconds</a>: obsolete attribute, not used anymore and should be deleted.</li>
				<li><a name="fm_logKeep">fm_logKeep</a>: A number that defines how many logFiles should be kept. If set all logfiles except the latest n freezemon logfiles will be deleted regularly.</li>
				<li><a name="fm_statistics">fm_statistics</a>: EXPERIMENTAL! Creates a reading for each device probably causing a freeze and counts how often it probably caused a freeze. </li>
				<li><a name="fm_whitelistSub">fm_whitelistSub</a>: Comma-separated list of subroutines that you're sure that don't cause a freeze. Whitelisted Subs do not appear in the  "possibly caused by" list. Typically you would list subroutines here that frequently appear in the "possibly caused by" list, but you're really sure they are NOT the issue. Note: The subroutine is the initial part (before the devicename in brackets) in freezemon log messages.  </li>
				<li><a name="fm_statistics">fm_statistics</a>: activate/deactivate freeze statistics. Creates readings for each device that possibly caused a freeze and sums up occurences and duration of those freezes</li>
				<li><a name="fm_statistics_low">fm_statistics_low</a>: Parametrization of clear statistics_low set command, format is c:t. With clear statistics_low all statistics-readings will be deleted where count is less or equal "c" AND cumulated duration is less or equal "t"</li>

				<li><a name="disable">disable</a>: activate/deactivate freeze detection</li>
			</ul>
		</ul>

</ul>


</div>

=end html

=begin html_DE

<a name="freezemon"></a>
	<h3>freezemon</h3>
	<div>
	<ul>
		FREEZEMON &uuml;berwacht - &auml;hnlich wie PERFMON m&ouml;gliche Freezes, allerdings ist FREEZEMON ein echtes Modul und hat daher:<br>
		<ul>
		<li>Readings - die geloggt werden k&ouml;nnen und damit viel einfacher ausgewertet werden k&ouml;nnen</li>
		<li>Attribute - mit denen das Verhalten von freezemon beeinflusst werden kann</li>
		<li>zusÃ¤tzliche Funktionalit&auml;t - die versucht das den Freeze verursachende Device zu identifizieren</li>
		</ul>
		Ich w&uuml;rde empfehlen, PERFMON zu deaktivieren, wenn FREEZEMON aktiv ist, da beide auf die selbe Art Freezes erkennen und dann nur alles doppelt kommt.
		<b>Bitte beachten!</b> FREEZEMON versucht nur intelligent zu erraten, welches Device einen freeze verursacht haben k&ouml;nnte (basierend auf den Timern die laufen sollten). Es gibt eine Menge anderer Faktoren (intern oder extern) die einen Freeze verursachen k&ouml;nnen. FREEZEMON ersetzt keine detaillierte Analyse. Das Modul versucht nur Hinweise zu geben, was optimiert werden k&ouml;nnte.<br><br>
		<br>
		<br>
	<a name="freezemonDefine"></a>
	<b>Define</b>
	<ul>
		FREEZEMON wird ohne Parameter definiert.<br><br>
		<code>define &lt;devicename&gt; freezemon</code><br><br>
		damit ist der Freezemon aktiv (im Log sollte eine entsprechende Meldung geschrieben werden)
		<br><br>
	</ul>
  <a name="freezemonSet"></a>
  <b>Set</b>
	<ul>
		<ul>
		<li><a name="inactive">inactive</a>: deaktiviert das Device (identisch zum Attribut "disable", aber ohne die Notwendigkeit zu "saven".</li>
		<li><a name="active">active</a>: reaktiviert das Device nachdem es auf inactive gesetzt wurde</li>
		<li><a name="clear">clear</a>: 
					<ul><li>statistics_all: l&ouml;scht die Statistik (d.h. l&ouml;scht alle readings die f&uuml;r die statistics erzeugt wurden)</li>
					<li>statistics_low: l&ouml;scht Statistiken mit geringer Bedeutung (siehe Attribut fm_statistics_low)</li>
					<li>all: L&ouml;scht alle readings (inklusive der Liste der letzten 20 Freezes).</li>
		<li><a name="getFreezes">getFreezes</a>: identisch zum "get freeze" Befehl, kann als set-Befehl aber als z.B. im webCmd Attribut genutzt werden</li>
		</ul></li>
		
	</ul>

  </ul>	
  <a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
	<ul>
		<li><a name="freeze">freeze</a>: gibt die letzten 20 freezes zur&uuml;ck (in Kompakter Darstellung, wie im state) - Dies dient einem schnellen &uuml;berblick, f&uuml;r detailliertere Auswertungen empfehle ich die Daten zu loggen.</li>
		<li><a name="log">log</a>: gibt Zugriff auf die Logfiles die geschrieben werden, wenn fm_logFile aktiv ist</li>
		<li><a name="statistic">statistic</a>: Stellt eine sch&ouml;ner formatierte &uuml;bersicht der top 20 Freeze Devices aus der Freeze Statistik zur Verf&uuml;gung</li>
	</ul>
  </ul>
  
  <a name="freezemonReadings"></a>
  <b>Readings</b>
  <ul>
		<ul>
			<li>freezeTime: Dauer des Freezes</li>
			<li>freezeDevice: Liste von m&ouml;glicherweise den Freeze ausl&ouml;senden Funktionen(Devices)</li>
			<li>fcDay: kumulierte Anzahl der Freezes pro Tag</li>
			<li>ftDay: kumulierte Dauer der Freezes pro Tag </li>
			<li>fcDayLast: speichert die kumulierte Anzahl der Freezes des vergangenen Tages (um tageweise plots zu erstellen). Aus technischen gr&uuml;nden werden Freezes, die sehr kurz nach Mitternacht auftreten m&ouml;glicherweise noch zum Vortag gez&auml;hlt.</li>
			<li>ftDayLast: speichert die kumulierte Dauer der Freezes des vergangenen Tages (um tageweise plots zu erstellen). Aus technischen gr&uuml;nden werden Freezes, die sehr kurz nach Mitternacht auftreten m&ouml;glicherweise noch zum Vortag gez&auml;hlt.</li>
			<li>fs_.*_c: freeze Statistik - Anzahl der freezes bei denen das Device m&ouml;glicherweise beteiligt war</li>
			<li>fs_.*_t: freeze Statistik - kumulierte Dauer der freezes bei denen das Device m&ouml;glicherweise beteiligt war</li>

			<li>state: s:&lt;StartZeit&gt; e:&lt;EndeZeit&gt; f:&lt;Dauer&gt; d:&lt;Devices&gt;</li>
		</ul>
  </ul>
 
<a name="freezemonattr"></a>
  <b>Attribute</b>
  <ul>
		<ul>
			<li><a name="fm_CatchFnCalls">fm_CatchFnCalls</a>fm_CatchFnCalls: wenn aktiviert, werden zus&auml;tzlich FHEM-interne Funktionsaufrufe &uuml;berwacht, in einigen F&auml;llen kann das zus&auml;tzliche Hinweise auf den Freeze-Verursacher geben, 0 bedeuted disabled, Zahlen >= 1 geben den Loglevel f&uuml;r des logging lang laufender Funktionsaufrufe an.</li>
			<li><a name="fm_CatchCmds">fm_CatchCmds</a>: wenn aktiviert, werden zus&auml;tzlich FHEM-Kommandos &uuml;berwacht, in einigen F&auml;llen kann das zus&auml;tzliche Hinweise auf den Freeze-Verursacher geben,  0 bedeuted disabled, Zahlen >= 1 geben den Loglevel f&uuml;r des logging lang laufender Kommandos an.</li>
			<li><a name="fm_extDetail">fm_extDetail</a>: stellt in einigen F&auml;llen zus&auml;tzliche Details bei erkannten Freezes zur Verf&uuml;gung. In wenigen F&auml;llen wurde berichtet, dass FHEM crasht, also vorsichtig verwenden.</li>
			<li><a name="fm_freezeThreshold">fm_freezeThreshold</a>: Wert in Sekunden (Default: 1) - Nur Freezes l&auml;nger als fm_freezeThreshold werden als Freeze betrachtet </li>
			<li><a name="fm_forceApptime">fm_forceApptime</a>: Wenn FREEZEMON aktiv ist wird automatisch apptime gestartet (falls nicht aktiv)</li>
			<li><a name="fm_ignoreDev">fm_ignoreDev</a>: Liste von Komma-getrennten Devices. Wenn einzelne m&ouml;glicherweise einen Freeze verursachenden Device in dieser Liste sind, wird der Freeze ignoriert (nicht geloggt). Bitte das Attribut fm_ignoreMode beachten</li>
			<li><a name="fm_ignoreMode">fm_ignoreMode</a>: Kann die Werte off,single oder all annehmen. Wenn in fm_ignoreDev Devices angegeben sind wirken sich der ignoreMode wie folgt aus: <br>
					all: Ein Freeze wird nur dann ignoriert, wenn alle m&ouml;glicherweise den Freeze verursachenden Devices in der Ignore-Liste enthalten sind. Dies f&uuml;hrt unter Umst&auml;nden dazu, dass mehr Freezes geloggt werden als erwartet.<br>
					single: Ein Freeze wird ignoriert, sobald ein m&ouml;glicher Verursacher in der Ignorierliste enthalten ist. Dies f&uuml;hrt m&ouml;glicherweise dazu, dass Freezes &uuml;bersehen werden.<br>
					off: Alle Freezes werden geloggt.<br>
					Sofern das Attribut nicht gesetzt ist, aber Ignore-Devices angegeben sind, wird im Modus "all" ignoriert.</li>
			<li><a name="fm_log">fm_log</a>: dynamischer Loglevel, nimmt einen String der Form 10:1 5:2 1:3 entgegen, was bedeutet: Freezes > 10 Sekunden werden mit Loglevel 1 geloggt, >5 Sekunden mit Loglevel 2 usw...</li>
			<li><a name="fm_logFile">fm_logFile</a>: ist ein g&uuml;ltiger Filename (wie z.B. ./log/freeze-%Y%m%d-%H%M%S.log). Wenn gesetzt, werdn Meldungen auf Loglevel 5 (auch wenn global Loglevel < 5 ist) vor einem Freeze in einem seperaten File geloggt.</li>
			<li><a name="fm_logExtraSeconds">fm_logExtraSeconds</a>: dobsoletes Attribut, wird nicht mehr genutzt und sollte gel&ouml;scht werden</li>
			<li><a name="fm_logKeep">fm_logKeep</a>: Eine Zahl, die angibt wieviele Logfiles behalten werden sollen. Wenn gesetzt, werden alle Logfiles ausser den letzten n Freezemon Logfiles regelm&auml;ßig gel&ouml;scht.</li>
			<li><a name="fm_statistics">fm_statistics</a>: EXPERIMENTELL! Erstellt ein reading f&uuml;r jedes Device, das "probably" einen Freeze verursacht hat und z&auml;hlt, wie oft es m&ouml;glicherweise an einem Freeze beteiligt war.</li>
			<li><a name="fm_whitelistSub">fm_whitelistSub</a>: Komma-getrennte Liste von Subroutinen wo du sicher bist, dass sie keinen Freeze verursachen. Whitelisted Subs erscheinen nicht in der "possibly caused by" Liste. Typischerweise listet man hier Subroutinen,  die regelm&auml;ßig in der "possibly caused by" Liste auftauchen, wo du aber wirklich sicher bist, dass sie nicht die Ursache sind. Anmerkung: Die Subroutine ist der initiale Teil (vor dem devicename in Klammern) in Freezemon Logmeldungen.</li>
			<li><a name="fm_statistics">fm_statistics</a>: aktivieren/deaktivieren der Freeze Statistik. Erzeugt Readings f&uuml;r jedes Device, das m&ouml;glicherweise an einem Freeze beteiligt war und Summiert die H&auml;ufigkeit und Dauer dieser Freezes</li>
			<li><a name="fm_statistics_low">fm_statistics_low</a>: Parametrisierung des clear statistics_low set Kommandos, im Format c:t. Bei clear statistics_low werden alle Statistics-Readings gel&ouml;scht deren Count kleiner oder gleich "c" ist UND deren kumulierte Dauer kleiner oder gleich "t" ist</li>
			<li><a name="disable">disable</a>: aktivieren/deaktivieren der Freeze-Erkennung</li>
		</ul>
  </ul>

</ul>
</div> 

=end html_DE
=cut

