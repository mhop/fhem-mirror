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
use Data::Dumper;
use POSIX;
use Time::HiRes qw(gettimeofday);
use B qw(svref_2object);

my $version  = "0.0.15";
my @logqueue = ();

###################################
sub freezemon_Initialize($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Module specific attributes
    my @freezemon_attr =
      (
"fm_forceApptime:0,1 fm_freezeThreshold disable:0,1 fm_log fm_ignoreDev fm_ignoreMode:off,single,all fm_extDetail:0,1 fm_logExtraSeconds fm_logFile"
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
        $hash->{STATE} = "inactive";
        $hash->{helper}{DISABLED} = 1;
    }
    $hash->{VERSION} = $version;

    return undef;
}
###################################
sub freezemon_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);

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
sub freezemon_ProcessTimer($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    #RemoveInternalTimer($hash);

    my $now    = gettimeofday();
    my $freeze = $now - $hash->{helper}{TIMER};

    #Check Freezes
    if ( $freeze > AttrVal( $name, "fm_freezeThreshold", 1 ) ) {

        my $dev  = $hash->{helper}{apptime};
        my $guys = "";
        $dev //= "";
        my $start = strftime( "%H:%M:%S", localtime( $hash->{helper}{TIMER} ) );
        my $end   = strftime( "%H:%M:%S", localtime($now) );
        $freeze = int( $freeze * 1000 ) / 1000;

        # Find the internal timers that are still in the hash
        my @olddev = split( " ", $dev );

        #Log3 $name, 5, "FreezeMon $name passing olddevs: $dev";

        my @newdev = split( " ", freezemon_apptime($hash) );

        #Log3 $name, 5, "FreezeMon $name passing newdevs: ".join(" ",@newdev);

        my %nd = map { $_ => 1 } @newdev;
        foreach my $d (@olddev) {
            if ( !exists( $nd{$d} ) ) {
                my @a = split( "-", $d );
                $guys .= $a[1] . " ";
            }
        }

        $dev = $guys;
        $dev =~ s/^\s+|\s+$//g;
        my $exists = undef;

        if ( $dev eq "" ) {
            $dev    = "no bad guy found :-(";
            $exists = 1;
        }
        else {
            #check ignorDev
            my $imode = "off";
            my %devs  = map { split /\:/, $_ } ( split /\ /, $dev );
            my @idevs = split( ",", AttrVal( $name, "fm_ignoreDev", "" ) );
            my %id    = map { $_ => 1 } @idevs;

            if ( AttrVal( $name, "fm_ignoreDev", undef ) ) {
                $imode = AttrVal( $name, "fm_ignoreMode", "all" );
            }

            #In "all" mode all found devices have to be in ignoreDevs (i.e. we're done if one is not in ignoreDev
            if ( $imode eq "all" ) {
                foreach my $d ( values %devs ) {
                    if ( !exists( $id{$d} ) ) {
                        Log3 $name, 5, "[Freezemon] $name logging $dev in $imode mode, because $d is not ignored";
                        $exists = 1;
                        last;
                    }
                }
            }

            #In "single" mode a single found device has to be in ignoreDevs (i.e. we're done if one is in ignoreDev
            elsif ( $imode eq "single" ) {
                $exists = 1;
                foreach my $d ( values %devs ) {
                    if ( exists( $id{$d} ) ) {
                        Log3 $name, 5, "[Freezemon] $name ignoring $dev in $imode mode, because $d is ignored";
                        $exists = undef;
                        last;
                    }
                }
            }
            else {
                $exists = 1;
            }

            #format output
            $dev =~ s/\:/\(/g;
            $dev =~ s/\s/\) /g;
            $dev .= ")";
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
            my $msg = strftime(
                "[Freezemon] $name possible freeze starting at %H:%M:%S, delay is $freeze possibly caused by $dev",
                localtime( $hash->{helper}{TIMER} ) );

            my $log = freezemon_dump_log( $hash, $hash->{helper}{TIMER}, $msg );
            Log3 $name, $loglevel, $msg;

            # Build hash with 20 last freezes
            my @freezes = ();
            push @freezes, split( ",", ReadingsVal( $name, ".fm_freezes", "" ) );
            push @freezes,
                strftime( "%Y-%m-%d", localtime )
              . freezemon_logLink( $name, $log )
              . ": s:$start e:$end f:$freeze d:$dev";

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
            readingsEndUpdate( $hash, 1 );
        }
        else {
            Log3 $name, 5, "[Freezemon] $name - $dev was ignored";
        }
    }
    freezemon_purge_log_before( $hash, $hash->{helper}{TIMER} - AttrVal( $name, "fm_logExtraSeconds", 0 ) )
      if ( AttrVal( $name, "fm_logFile", "" ) ne "" );

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

        if ( AttrVal( $name, "fm_forceApptime", 0 ) == 1
            and !defined( $cmds{"apptime"} ) )
        {
            fhem( "apptime", 1 );
        }
    }

    # start next timer
    $hash->{helper}{fn}      = "";
    $hash->{helper}{apptime} = freezemon_apptime($hash);
    $hash->{helper}{TIMER}   = int($now) + 1;
    InternalTimer( $hash->{helper}{TIMER}, 'freezemon_ProcessTimer', $hash, 0 );
}
###################################
sub freezemon_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    #my $usage         = 'Unknown argument $args[1], choose one of freeze:noArg log:abc,cde';

    #return $usage if ( !defined( $args[1] ) );

    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "inactive" ) {
        RemoveInternalTimer($hash);
        readingsSingleUpdate( $hash, "state", "inactive", 1 );
        $hash->{helper}{DISABLED} = 1;
    }
    elsif ( $cmd eq "active" ) {
        if ( IsDisabled($name) ) {
            freezemon_start($hash);
        }
        else {
            return "Freezemon $name is already active";
        }
    }
    elsif ( $cmd eq "clear" ) {
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
    else {
        return "Unknown argument $cmd, choose one of active:noArg inactive:noArg clear:noArg";
    }
    return undef;
}

###################################
sub freezemon_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};
    my $ret   = "";
    my $usage = 'Unknown argument $a[1], choose one of freeze:noArg log:';

    return $usage if ( !defined( $a[1] ) );

    #get the logfiles
    my $lf = AttrVal( $name, "fm_logFile", "" );
    $lf =~ m,^(.*)/([^/%]*).*$,;
    my $p       = $1;
    my $pattern = $2;
    my @fl;

    my $sfl;
    if ( opendir( DH, $p ) ) {
        while ( my $f = readdir(DH) ) {
            push( @fl, $f ) if ( $f =~ /$pattern.*/ );
        }
        closedir(DH);
        @fl = sort { ( CORE::stat("$p/$b") )[9] <=> ( CORE::stat("$p/$a") )[9] } @fl;
    }
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
            $ret .= "<font color='$colors[$loglevel-1]'><b>" . $loglevel . "</b></font> - " . $_ . "<br>";

        }
        Log3 $name, 5, "Get entries: $ret";
        return "<html>" . $ret . "</html>";
    }
    elsif ( $a[1] eq "log" ) {
        return "No Filename given" if ( !defined( $a[2] ) );

        # extract the filename from given argument (in case it comes with path)
        my $gf = $a[2];
        if ( $gf =~ m,^(.*)/([^/]*)$, ) {
            $gf = $2;
        }

        # Build the complete path (using global logfile parameter if necessary)
        my $path = "$p/$gf";
        $path =~ s/%L/$attr{global}{logdir}/g if ( $path =~ m/%/ && $attr{global}{logdir} );

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
        if ( $aName eq "fm_freezeThreshold" ) {
            if ( !looks_like_number($aVal) ) {
                return "Attribute " . $aName . " has to be a number (seconds) ";
            }
        }
        if ( $aName eq "fm_freezeThreshold" ) {

        }
        if ( $aName eq "fm_logFile" ) {
            if ( $aVal ne "" ) {
                freezemon_install_log_wrapper($hash);
            }
            else {
                return "Attribute " . $aName . ": Enter a valid path or delete the attribute to disable.";
            }
        }

        if ( $aName eq "disable" ) {
            if ( $aVal == 1 ) {
                RemoveInternalTimer($hash);
                readingsSingleUpdate( $hash, "state", "inactive", 1 );
                $hash->{helper}{DISABLED} = 1;
            }
            elsif ( $aVal == 0 ) {
                freezemon_start($hash);
            }

        }
    }
    elsif ( $cmd eq "del" ) {
        if ( $aName eq "disable" ) {
            freezemon_start($hash);
        }
        if ( $aName eq "fm_logFile" ) {
            my $status = Log3( "", 100, "" );
            Log3( "", 0, "[FREEZEMON] $name: Unwrapping Log3" );
            *main::Log3 = $hash->{helper}{Log3};
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

    readingsSingleUpdate( $hash, "state", "initialized", 0 )
      if ( exists( $hash->{helper}{DISABLED} )
        and $hash->{helper}{DISABLED} == 1 );
    $hash->{helper}{DISABLED} = 0;
    my $next = int( gettimeofday() ) + 1;
    $hash->{helper}{TIMER} = $next;

    freezemon_install_log_wrapper($hash) if AttrVal( $name, "fm_logFile", "" ) ne "";

    InternalTimer( $next, 'freezemon_ProcessTimer', $hash, 0 );
    Log3 $name, 2,
        "[Freezemon] $name ready to watch out for delays greater than "
      . AttrVal( $name, "fm_freezeThreshold", 1 )
      . " second(s)";

}

###################################
sub freezemon_apptime($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    #    my @intAtKeys    = keys(%intAt);
    my $now          = gettimeofday();
    my $minCoverExec = 10;               # Let's see if we can find more if we look ahead further
    my $minCoverWait = 0.00;
    my $ret          = "";

    # my @intAtSort =
    # ( sort { $intAt{$a}{TRIGGERTIME} <=> $intAt{$b}{TRIGGERTIME} }
    # ( grep { ( $intAt{$_}->{TRIGGERTIME} - $now ) <= $minCoverExec } @intAtKeys ) )
    # ;                                  # get the timers to execute due to timeout and sort ascending by time
    my ( $fn, $tim, $cv, $fnname, $arg, $shortarg );

    my $n = int(@intAtA);    # @intAtA is sorted ascending by time
    my $i = -1;

    #foreach my $i (@intAtSort) {
    while ( ++$i < $n ) {

        #$tim = $intAt{$i}{TRIGGERTIME};
        $tim = $intAtA[$i]->{TRIGGERTIME};
        if ( $tim - gettimeofday() > $minCoverWait ) {

            #next;
        }

        #if ( $intAt{$i}{FN} eq "freezemon_ProcessTimer" ) {
        if ( $intAtA[$i]->{FN} eq "freezemon_ProcessTimer" ) {
            next;
        }

        #$fn = $intAt{$i}{FN};
        $fn = $intAtA[$i]->{FN};

        if ( ref($fn) ne "" ) {
            $cv     = svref_2object($fn);
            $fnname = $cv->GV->NAME;

            #$ret .= $intAt{$i}{TRIGGERTIME} . "-" . $fnname;
            $ret .= $intAtA[$i]->{TRIGGERTIME} . "-" . $fnname;
            Log3 $name, 5, "[Freezemon] $name Reference found: " . ref($fn) . "/$fnname/$fn";
        }
        else {
            #$ret .= $intAt{$i}{TRIGGERTIME} . "-" . $fn;
            $ret .= $intAtA[$i]->{TRIGGERTIME} . "-" . $fn;
        }

        #$arg = $intAt{$i}{ARG};
        $arg = $intAtA[$i]->{ARG};

        $shortarg = ( defined($arg) ? $arg : "" );
        if ( ref($shortarg) eq "HASH" ) {
            if ( !defined( $shortarg->{NAME} ) ) {
                if ( AttrVal( $name, "fm_extDetail", 0 ) == 1 ) {
                    if ( $fn eq "BlockingKill" or $fn eq "BlockingStart" ) {
                        $shortarg = $shortarg->{abortArg}{NAME};
                        Log3 $name, 5, "[Freezemon] $name found $fn " . Dumper($shortarg);
                    }
                    elsif ( $fn eq "HttpUtils_Err" ) {
                        $shortarg = $shortarg->{hash}{hash}{NAME};
                    }
                    else {
                        Log3 $name, 5, "[Freezemon] $name found something without a name $fn" . Dumper($shortarg);
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
                my $deref = ${$arg};  #seems like $arg is a reference to a scalar which in turm is a reference to a hash
                $shortarg = $deref->{'hash'}{NAME};    #at least in DOIF_TimerTrigger
            }
            else {
                Log3 $name, 5, "[Freezemon] $name  found a REF $fn " . Dumper( ${$arg} );
            }
        }
        else {
        #Log3 $name, 3, "[Freezemon] $name found something that's not a HASH $fn ".ref($shortarg)." ".Dumper($shortarg);
            $shortarg = "N/A";
        }
        if ( !$shortarg ) {
            Log3 $name, 5, "Freezemon: something went wrong $fn " . Dumper($arg);
            $shortarg = "";
        }
        else {
            ( $shortarg, undef ) = split( /:|;/, $shortarg, 2 );
        }
        $ret .= ":" . $shortarg . " ";
    }
    if (%prioQueues) {

        foreach my $prio ( keys %prioQueues ) {
            foreach my $entry ( @{ $prioQueues{$prio} } ) {

                #Log3 $name, 5, "Freezemon: entry is ".Dumper($entry);
                $cv     = svref_2object( $entry->{fn} );
                $fnname = $cv->GV->NAME;
                $ret .= "prio-" . $fnname;

                $shortarg = ( defined( $entry->{arg} ) ? $entry->{arg} : "" );

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
                $ret .= ":" . $shortarg . " ";

                #Log3 $name, 5, "Freezemon: found a prioQueue, returning $ret";
            }
        }
    }

    return $ret;
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
sub freezemon_install_log_wrapper($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $name = "FreezeMon" unless defined($name);
    my $status = Log3( "", 99, "" );
    if ( !defined($status) || $status ne "already wrapped" ) {
        Log3( "", 0, "[FREEZEMON] $name: Wrapping Log3" );
        $hash->{helper}{Log3} = \&Log3;
        *main::Log3 = freezemon_wrap_Log3( \&Log3 );
    }
    else {
        Log3( "", 0, "[FREEZEMON] $name: Log3 is already wrapped" );
        Log3( "", 0, "[FREEZEMON] $name: status=$status" );
    }
}
###################################
sub freezemon_purge_log_before($$) {
    my ( $hash, $before ) = @_;
    my $name = $hash->{NAME};
    my @t    = localtime($before);
    my $tim  = sprintf( "%04d.%02d.%02d %02d:%02d:%02d.%03d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], 0 );

    #Log3 $hash, 5, "[FREEZEMON] $name: purging log entries before $tim.";
    my $cnt = 0;
    while ( scalar @logqueue > 0 && $logqueue[0]->[0] < $before ) {
        shift @logqueue;
        $cnt += 1;
    }

    #Log3 $hash, 5, "[FREEZEMON] $name: $cnt entries purged from logqueue, size is now ".(scalar @logqueue);
}
###################################
sub freezemon_dump_log($$$) {
    my ( $hash, $start, $msg ) = @_;
    return unless scalar @logqueue;
    my $name = $hash->{NAME};

    my ( $seconds, $microseconds ) = gettimeofday();
    my @t = localtime($seconds);
    my $currlogfile = ResolveDateWildcards( AttrVal( $name, "fm_logFile", undef ), @t );

    return unless defined($currlogfile) && $currlogfile ne "";
    Log3 $hash, 3, "[FREEZEMON] $name: dumping " . ( scalar @logqueue ) . " log entries to $currlogfile";

    open( fm_LOG, ">>$currlogfile" ) || return ("Can't open $currlogfile: $!");

    print fm_LOG "=========================================================\n";
    print fm_LOG $msg . "\n";
    my $last_ts;
    foreach my $entry (@logqueue) {
        my ( $ts, $dev, $loglevel, $text ) = @$entry;
        my $seconds = int($ts);
        my $microseconds = int( 1e6 * ( $ts - $seconds ) );
        $dev = $dev->{NAME} if ( defined($dev) && ref($dev) eq "HASH" );
        next if ( defined($dev) && ( $dev eq $name ) );

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
    my $ret = FW_pH( "$FW_ME/fhem?cmd=" . urlEncode("get $name log $link"), " [Log]", 1, "", 1, 1 );
    return $ret;
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
		<li>inactive: disables the device (similar to attribute "disable", however without the need to save</li>
		<li>active: reactivates the device after it was set inactive</li>
		<li>clear: clears all readings (including the list of the last 20 freezes.)</li>
	</ul>
  </ul>	
<a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
	<ul>
		<li>freeze: returns the last 20 (in compact view, like in state) - This is for a quick overview. For detailed analysis the data should be logged.</li>
		<li>log: provides direct access to the logfiles written when fm_logFile is active</li>
	</ul>
  </ul>
  
 <a name="freezemonReadings"></a>
  <b>Readings</b>
		<ul>
			<ul>
				<li>freezeTime: Duration of the freeze</li>
				<li>freezeDevice: List of functions(Devices) that possibly caused the freeze</li>
				<li>fcDay: cumulated no. of freezes per day</li>
				<li>ftDay: cumulated duration of freezes per day</li>
				<li>fcDayLast: stores cumulated no. of freezes of the last day (for daily plots)</li>
				<li>fcDayLast: stores cumulated duration of freezes of the last day (for daily plots)</li>
				<li>state: s:&lt;startTime&gt; e:&lt;endTime&gt; f:&lt;Duration&gt; d:&lt;Devices&gt;</li>;
			</ul>
		</ul>

<a name="freezemonAttributes"></a>
  <b>Attributes</b>
		<ul>
			<ul>
				<li>fm_extDetail: provides in some cases extended details for recognized freezes. In some cases it was reported that FHEM crashes, so please be careful.</li>
				<li>fm_freezeThreshold: Value in seconds (Default: 1) - Only freezes longer than fm_freezeThreshold will be considered as a freeze</li>
				<li>fm_forceApptime: When FREEZEMON is active, apptime will automatically be started (if not yet active)</li>
				<li>fm_ignoreDev: list of comma separated Device names. If all devices possibly causing a freeze are in the list, the freeze will be ignored (not logged)</li>
				<li>fm_ignoreMode: takes the values off,single or all. If you have added devices to fm_ignoreDev then ignoreMode acts as follows: <br>
				all: A freeze will only be ignored, if all devices probably causing the freeze are part of the ignore list. This might result in more freezes being logged than expected.<br>
				single: A freeze will be ignored as soon as one device possibly causing the freeze is listed in the ignore list. With this setting you might miss freezes.<br>
				off: All freezes will be logged.<br>
				If the attribute is not set, while the ignore list is maintained, mode "all" will be used.</li>
				<li>fm_log: dynamic loglevel, takes a string like 10:1 5:2 1:3 , which means: freezes > 10 seconds will be logged with loglevel 1 , >5 seconds with loglevel 2 etc...</li>
				<li>fm_logFile: takes a valid file name (like e.g. ./log/freeze-%Y%m%d-%H%M%S.log). If set, logs messages of loglevel 5 (even if global loglevel is < 5) before a freeze in separate file.</li>
				<li>fm_logExtraSeconds: defines how much seconds before the freeze are logged (if fm_logFile is set)</li>
				<li>disable: activate/deactivate freeze detection</li>
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
		FREEZEMON Überwacht - Ähnlich wie PERFMON mögliche Freezes, allerdings ist FREEZEMON ein echtes Modul und hat daher:<br>
		<ul>
		<li>Readings - die geloggt werden können und damit viel einfacher ausgewertet werden können</li>
		<li>Attribute - mit denen das Verhalten von freezemon beeinflusst werden kann</li>
		<li>zusÃ¤tzliche Funktionalität - die versucht das den Freeze verursachende Device zu identifizieren</li>
		</ul>
		Ich würde empfehlen, PERFMON zu deaktivieren, wenn FREEZEMON aktiv ist, da beide auf die selbe Art Freezes erkennen und dann nur alles doppelt kommt.
		<b>Bitte beachten!</b> FREEZEMON versucht nur intelligent zu erraten, welches Device einen freeze verursacht haben könnte (basierend auf den Timern die laufen sollten). Es gibt eine Menge anderer Faktoren (intern oder extern) die einen Freeze verursachen können. FREEZEMON ersetzt keine detaillierte Analyse. Das Modul versucht nur Hinweise zu geben, was optimiert werden könnte.<br><br>
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
		<li>inactive: deaktiviert das Device (identisch zum Attribut "disable", aber ohne die Notwendigkeit su "saven".</li>
		<li>active: reaktiviert das Device nachdem es auf inactive gesetzt wurde</li>
		<li>clear: Löscht alle readings (inklusive der Liste der letzten 20 Freezes).</li>
	</ul>

  </ul>	
  <a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
	<ul>
		<li>freeze: gibt die letzten 20 freezes zurück (in Kompakter Darstellung, wie im state) - Dies dient einem schnellen Überblick, für detailliertere Auswertungen empfehle ich die Daten zu loggen.</li>
		<li>log: gibt Zugriff auf die Logfiles die geschrieben werden, wenn fm_logFile aktiv ist</li>
	</ul>
  </ul>
  
  <a name="freezemonReadings"></a>
  <b>Readings</b>
  <ul>
		<ul>
			<li>freezeTime: Dauer des Freezes</li>
			<li>freezeDevice: Liste von möglicherweise den Freeze auslösenden Funktionen(Devices)</li>
			<li>fcDay: kumulierte Anzahl der Freezes pro Tag</li>
			<li>ftDay: kumulierte Dauer der Freezes pro Tag </li>
			<li>fcDayLast: speichert die kumulierte Anzahl der Freezes des vergangenen Tages (um tageweise plots zu erstellen)</li>
			<li>fcDayLast: speichert die kumulierte Dauer der Freezes des vergangenen Tages (um tageweise plots zu erstellen)</li>
			<li>state: s:&lt;StartZeit&gt; e:&lt;EndeZeit&gt; f:&lt;Dauer&gt; d:&lt;Devices&gt;</li>
		</ul>
  </ul>
 
<a name="freezemonAttributes"></a>
  <b>Attribute</b>
  <ul>
		<ul>
			<li>fm_extDetail: stellt in einigen Fällen zusätzliche Details bei erkannten Freezes zur Verfügung. In wenigen Fällen wurde berichtet, dass FHEM crasht, also vorsichtig verwenden.</li>
			<li>fm_freezeThreshold: Wert in Sekunden (Default: 1) - Nur Freezes länger als fm_freezeThreshold werden als Freeze betrachtet </li>
			<li>fm_forceApptime: Wenn FREEZEMON aktiv ist wird automatisch apptime gestartet (falls nicht aktiv)</li>
			<li>fm_ignoreDev: Liste von Komma-getrennten Devices. Wenn einzelne möglicherweise einen Freeze verursachenden Device in dieser Liste sind, wird der Freeze ignoriert (nicht geloggt). Bitte das Attribut fm_ignoreMode beachten</li>
			<li>fm_ignoreMode: Kann die Werte off,single oder all annehmen. Wenn in fm_ignoreDev Devices angegeben sind wirken sich der ignoreMode wie folgt aus: <br>
					all: Ein Freeze wird nur dann ignoriert, wenn alle möglicherweise den Freeze verursachenden Devices in der Ignore-Liste enthalten sind. Dies führt unter Umständen dazu, dass mehr Freezes geloggt werden als erwartet.<br>
					single: Ein Freeze wird ignoriert, sobald ein möglicher Verursacher in der Ignorierliste enthalten ist. Dies führt möglicherweise dazu, dass Freezes übersehen werden.<br>
					off: Alle Freezes werden geloggt.<br>
					Sofern das Attribut nicht gesetzt ist, aber Ignore-Devices angegeben sind, wird im Modus "all" ignoriert.</li>
			<li>fm_log: dynamischer Loglevel, nimmt einen String der Form 10:1 5:2 1:3 entgegen, was bedeutet: Freezes > 10 Sekunden werden mit Loglevel 1 geloggt, >5 Sekunden mit Loglevel 2 usw...</li>
			<li>fm_logFile: ist ein gültiger Filename (wie z.B. ./log/freeze-%Y%m%d-%H%M%S.log). Wenn gesetzt, werdn Meldungen auf Loglevel 5 (auch wenn global Loglevel < 5 ist) vor einem Freeze in einem seperaten File geloggt.</li>
			<li>fm_logExtraSeconds: definiert wieviele Sekunden vor dem Freeze geloggt werden (wenn fm logFile gesetzt ist)</li>
			
			<li>disable: aktivieren/deaktivieren der Freeze-Erkennung</li>
		</ul>
  </ul>
  
</ul>
</div> 

=end html_DE
=cut

