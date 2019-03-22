###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use Time::Local;

require RESIDENTStk;

# module variables ############################################################
my %stateSecurity = (
    en => [ 'unlocked', 'locked', 'protected', 'secured', 'guarded' ],
    de =>
      [ 'unverriegelt', 'verriegelt', 'geschützt', 'gesichert', 'überwacht' ],
    icons => [
        'status_open@yellow', 'status_standby@yellow@green',
        'status_night@green', 'status_locked@green',
        'building_security@green'
    ],
);

my %stateOnoff = (
    en => [ 'off', 'on' ],
    de => [ 'aus', 'an' ],
);

my %readingsMap = (
    date_long      => 'calTod',
    date_short     => 'calTodS',
    daytime_long   => 'daytime',
    daytimeStage   => 'daytimeStage',
    daytimeStageLn => 'calTodDaytimeStageLn',
    daytimeT       => 'calTodDaytimeT',
    day_desc       => 'calTodDesc',

    # dstchange        => 'calTodDSTchng',

    dst_long         => 'calTodDST',
    isholiday        => 'calTodHoliday',
    isly             => 'calTodLeapyear',
    iswe             => 'calTodTodWeekend',
    mday             => 'calTodMonthday',
    mdayrem          => 'calTodMonthdayRem',
    monISO           => 'calTodMonthN',
    mon_long         => 'calTodMonth',
    mon_short        => 'calTodMonthS',
    rday_long        => 'calTodRel',
    seasonAstroChng  => 'calTodSAstroChng',
    seasonAstro_long => 'calTodSAstro',
    seasonMeteoChng  => 'calTodSMeteoChng',
    seasonMeteo_long => 'calTodSMeteo',
    seasonPheno_long => 'calTodSPheno',
    sunrise          => 'calTodSunrise',
    sunset           => 'calTodSunset',
    daytimeStages    => 'daytimeStages',
    wdaynISO         => 'calTodWeekdayN',
    wday_long        => 'calTodWeekday',
    wday_short       => 'calTodWeekdayS',
    weekISO          => 'calTodWeek',
    yday             => 'calTodYearday',
    ydayrem          => 'calTodYeardayRem',
    year             => 'calTodYear',
);

my %readingsMap_tom = (
    date_long      => 'calTom',
    date_short     => 'calTomS',
    daytimeStageLn => 'calTomDaytimeStageLn',
    daytimeT       => 'calTomDaytimeT',
    day_desc       => 'calTomDesc',

    # dstchange        => 'calTomDSTchng',

    dst_long         => 'calTomDST',
    isholiday        => 'calTomHoliday',
    isly             => 'calTomLeapyear',
    iswe             => 'calTomWeekend',
    mday             => 'calTomMonthday',
    mdayrem          => 'calTomMonthdayRem',
    monISO           => 'calTomMonthN',
    mon_long         => 'calTomMonth',
    mon_short        => 'calTomMonthS',
    rday_long        => 'calTomRel',
    seasonAstroChng  => 'calTomSAstroChng',
    seasonAstro_long => 'calTomSAstro',
    seasonMeteoChng  => 'calTomSMeteoChng',
    seasonMeteo_long => 'calTomSMeteo',
    seasonPheno_long => 'calTodSPheno',
    sunrise          => 'calTomSunrise',
    sunset           => 'calTomSunset',
    wdaynISO         => 'calTomWeekdayN',
    wday_long        => 'calTomWeekday',
    wday_short       => 'calTomWeekdayS',
    weekISO          => 'calTomWeek',
    yday             => 'calTomYearday',
    ydayrem          => 'calTomYeardayRem',
    year             => 'calTomYear',
);

# initialize ##################################################################
sub HOMESTATEtk_Initialize($) {
    my ($hash) = @_;

    $hash->{InitDevFn}   = "HOMESTATEtk_InitializeDev";
    $hash->{DefFn}       = "HOMESTATEtk_Define";
    $hash->{UndefFn}     = "HOMESTATEtk_Undefine";
    $hash->{SetFn}       = "HOMESTATEtk_Set";
    $hash->{GetFn}       = "HOMESTATEtk_Get";
    $hash->{AttrFn}      = "HOMESTATEtk_Attr";
    $hash->{NotifyFn}    = "HOMESTATEtk_Notify";
    $hash->{parseParams} = 1;

    $hash->{AttrList} =
        "disable:1,0 disabledForIntervals do_not_notify:1,0 "
      . $readingFnAttributes
      . " Lang:EN,DE DebugDate ";

    my $holidayFilter =
      $attr{global}{holiday2we}
      ? ":FILTER=NAME!=" . $attr{global}{holiday2we}
      : "";
    $hash->{AttrList} .=
      " HolidayDevices:multiple,"
      . join( ",", devspec2array( "TYPE=holiday" . $holidayFilter ) );
    $hash->{AttrList} .= " ResidentsDevices:multiple,"
      . join( ",", devspec2array("TYPE=RESIDENTS,TYPE=ROOMMATE,TYPE=GUEST") );
}

# module Fn ####################################################################
sub HOMESTATEtk_InitializeDev($) {
    my ($hash) = @_;
    $hash = $defs{$hash} unless ( ref($hash) );
    my $name    = $hash->{NAME};
    my $TYPE    = $hash->{TYPE};
    my $changed = 0;
    my $lang =
      lc( AttrVal( $name, "Lang", AttrVal( "global", "language", "EN" ) ) );
    my $langUc = uc($lang);
    my @error;

    delete $hash->{NEXT_EVENT};
    RemoveInternalTimer($hash);

    no strict "refs";
    &{ $TYPE . "_Initialize" }( \%{ $modules{$TYPE} } ) if ($init_done);
    use strict "refs";

    # NOTIFYDEV
    my $NOTIFYDEV = "global,$name";
    $NOTIFYDEV .= "," . HOMESTATEtk_findHomestateSlaves($hash);
    unless ( defined( $hash->{NOTIFYDEV} ) && $hash->{NOTIFYDEV} eq $NOTIFYDEV )
    {
        $hash->{NOTIFYDEV} = $NOTIFYDEV;
        $changed = 1;
    }

    my $time = time;
    my $debugDate = AttrVal( $name, "DebugDate", "" );
    if ( $debugDate =~
        m/^((?:\d{4}\-)?\d{2}-\d{2})(?: (\d{2}:\d{2}(?::\d{2})?))?$/ )
    {
        my $date = "$1";
        $date .= " $2" if ($2);
        my ( $sec, $min, $hour, $mday, $mon, $year ) = UConv::_time();

        $date = "$year-$date" unless ( $date =~ /^\d{4}-/ );
        $date .= "00:00:00" unless ( $date =~ /\d{2}:\d{2}:\d{2}$/ );
        $date .= ":00"      unless ( $date =~ /\d{2}:\d{2}:\d{2}$/ );
        $time = time_str2num($date);
        push @error, "WARNING: DebugDate in use ($date)";
    }

    delete $hash->{'.events'};
    delete $hash->{'.t'};
    $hash->{'.t'} = HOMESTATEtk_GetDaySchedule( $hash, $time, undef, $lang );
    $hash->{'.events'} = $hash->{'.t'}{events};

    ## begin reading updates
    #
    readingsBeginUpdate($hash);

    foreach ( sort keys %{ $hash->{'.t'} } ) {
        next if ( ref( $hash->{'.t'}{$_} ) );
        my $r = $readingsMap{$_} ? $readingsMap{$_} : undef;
        my $v = $hash->{'.t'}{$_};

        readingsBulkUpdateIfChanged( $hash, $r, $v )
          if ( defined($r) );

        $r = $readingsMap_tom{$_} ? $readingsMap_tom{$_} : undef;
        $v = $hash->{'.t'}{1}{$_} ? $hash->{'.t'}{1}{$_} : undef;

        readingsBulkUpdateIfChanged( $hash, $r, $v )
          if ( defined($r) && defined($v) );
    }

    unless ( $lang =~ /^en/i || !$hash->{'.t'}{$lang} ) {
        foreach ( sort keys %{ $hash->{'.t'}{$lang} } ) {
            next if ( ref( $hash->{'.t'}{$lang}{$_} ) );
            my $r = $readingsMap{$_} ? $readingsMap{$_} . "_$langUc" : undef;
            my $v = $hash->{'.t'}{$lang}{$_};

            readingsBulkUpdateIfChanged( $hash, $r, $v )
              if ( defined($r) );

            $r =
              $readingsMap_tom{$_} ? $readingsMap_tom{$_} . "_$langUc" : undef;
            $v =
              $hash->{'.t'}{1}{$lang}{$_} ? $hash->{'.t'}{1}{$lang}{$_} : undef;

            readingsBulkUpdateIfChanged( $hash, $r, $v )
              if ( defined($r) && defined($v) );
        }
    }

    # TODO: seasonSocial
    #
    # TODO: höchster Sonnenstand
    #       > Trend Sonne aufgehend, abgehend?
    #       > temperaturmaximum 14h / 15h bei DST

    # error
    if ( scalar @error ) {
        readingsBulkUpdateIfChanged( $hash, "error", join( "; ", @error ) );
    }
    else {
        delete $hash->{READINGS}{error};
    }

    HOMESTATEtk_UpdateReadings($hash);
    readingsEndUpdate( $hash, 1 );

    #
    ## end reading updates

    # schedule next timer
    foreach ( sort keys %{ $hash->{'.events'} } ) {
        next if ( $_ < $time );
        $hash->{NEXT_EVENT} =
          $hash->{'.events'}{$_}{TIME} . " - " . $hash->{'.events'}{$_}{DESC};
        InternalTimer( $_, "HOMESTATEtk_InitializeDev", $hash );
        last;
    }

    return 0 unless ($changed);
    return undef;
}

sub HOMESTATEtk_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = shift @$a;
    my $TYPE = shift @{$a};
    my $name_attr;

    $hash->{MOD_INIT}  = 1;
    $hash->{NOTIFYDEV} = "global";
    delete $hash->{NEXT_EVENT};
    RemoveInternalTimer($hash);

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        HOMESTATEtk_Attr( "init", $name, "Lang" );

        $attr{$name}{room} = "Homestate";
        $attr{$name}{devStateIcon} =
          '{(HOMESTATEtk_devStateIcon($name),"toggle")}';

        $attr{$name}{icon} = "control_building_control"
          if ( $TYPE eq "HOMESTATE" );
        $attr{$name}{icon} = "control_building_eg"
          if ( $TYPE eq "SECTIONSTATE" );
        $attr{$name}{icon} = "floor"
          if ( $TYPE eq "ROOMSTATE" );

        # find HOMESTATE device
        if ( $TYPE eq "ROOMSTATE" || $TYPE eq "SECTIONSTATE" ) {
            my @homestates = devspec2array("TYPE=HOMESTATE");
            if ( scalar @homestates ) {
                $attr{$name}{"HomestateDevices"} = $homestates[0];
                $attr{$name}{room} = $attr{ $homestates[0] }{room}
                  if ( $attr{ $homestates[0] }
                    && $attr{ $homestates[0] }{room} );
                $attr{$name}{"Lang"} = $attr{ $homestates[0] }{Lang}
                  if ( $attr{ $homestates[0] }
                    && $attr{ $homestates[0] }{Lang} );

                HOMESTATEtk_Attr( "set", $name, "Lang", $attr{$name}{"Lang"} )
                  if $attr{$name}{"Lang"};
            }
            else {
                my $n = "Home";
                my $i = "";
                while ( IsDevice( $n . $i ) ) {
                    $i = 0 if ( $i eq "" );
                    $i++;
                }
                CommandDefine( undef, "$n HOMESTATE" );
                $attr{$n}{comment} =
                  "Auto-created by $TYPE module for use with HOMESTATE Toolkit";
                $attr{$name}{"HomestateDevices"} = $n;
                $attr{$name}{room}               = $attr{$n}{room};
                $attr{$name}{"Lang"}             = $attr{ $homestates[0] }{Lang}
                  if ( $attr{ $homestates[0] }
                    && $attr{ $homestates[0] }{Lang} );

                HOMESTATEtk_Attr( "set", $name, "Lang", $attr{$name}{"Lang"} )
                  if $attr{$name}{"Lang"};
            }
        }

        # find ROOMSTATE device
        if ( $TYPE eq "SECTIONSTATE" ) {
            my @roomstates = devspec2array("TYPE=ROOMSTATE");
            unless ( scalar @roomstates ) {
                my $n = "Room";
                my $i = "";
                while ( IsDevice( $n . $i ) ) {
                    $i = 0 if ( $i eq "" );
                    $i++;
                }
                CommandDefine( undef, "$n ROOMSTATE" );
                $attr{$n}{comment} =
                  "Auto-created by $TYPE module for use with HOMESTATE Toolkit";
                $attr{$name}{room} = $attr{$n}{room};
                $attr{$name}{"Lang"} = $attr{ $roomstates[0] }{Lang}
                  if ( $attr{ $roomstates[0] }
                    && $attr{ $roomstates[0] }{Lang} );

                HOMESTATEtk_Attr( "set", $name, "Lang", $attr{$name}{"Lang"} )
                  if $attr{$name}{"Lang"};
            }
        }

        # find RESIDENTS device
        if ( $TYPE eq "HOMESTATE" ) {
            my @residents = devspec2array("TYPE=RESIDENTS,TYPE=ROOMMATE");
            if ( scalar @residents ) {
                $attr{$name}{"ResidentsDevices"} = $residents[0];
                $attr{$name}{room} = $attr{ $residents[0] }{room}
                  if ( $attr{ $residents[0] } && $attr{ $residents[0] }{room} );
                $attr{$name}{"Lang"} = $attr{ $residents[0] }{rgr_lang}
                  if ( $attr{ $residents[0] }
                    && $attr{ $residents[0] }{rgr_lang} );
                $attr{$name}{"Lang"} = $attr{ $residents[0] }{rr_lang}
                  if ( $attr{ $residents[0] }
                    && $attr{ $residents[0] }{rr_lang} );

                HOMESTATEtk_Attr( "set", $name, "Lang", $attr{$name}{"Lang"} )
                  if $attr{$name}{"Lang"};
            }
            else {
                my $n = "rgr_Residents";
                my $i = "";
                while ( IsDevice( $n . $i ) ) {
                    $i = 0 if ( $i eq "" );
                    $i++;
                }
                CommandDefine( undef, "$n RESIDENTS" );
                $attr{$n}{comment} =
                  "Auto-created by $TYPE module for use with HOMESTATE Toolkit";
                $attr{$name}{"ResidentsDevices"} = $n;
                $attr{$n}{room} = $attr{$name}{room};

                HOMESTATEtk_Attr( "set", $name, "Lang", $attr{$name}{"Lang"} )
                  if $attr{$name}{"Lang"};

                $attr{$name}{group} = $attr{$n}{group};
            }
        }
    }

    return undef;
}

sub HOMESTATEtk_Undefine($$) {
    my ( $hash, $name ) = @_;
    delete $hash->{NEXT_EVENT};
    RemoveInternalTimer($hash);
    return undef;
}

sub HOMESTATEtk_Set($$$);

sub HOMESTATEtk_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $TYPE = $hash->{TYPE};
    my $name = shift @$a;
    my $lang =
      lc( AttrVal( $name, "Lang", AttrVal( "global", "language", "EN" ) ) );
    my $langUc   = uc($lang);
    my $state    = ReadingsVal( $name, "state", "" );
    my $mode     = ReadingsVal( $name, "mode", "" );
    my $security = ReadingsVal( $name, "security", "" );
    my $autoMode =
      HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "autoMode", "on" ),
        $stateOnoff{en} );
    my $silent = 0;
    my %rvals;

    return undef if ( IsDisabled($name) );
    return "No argument given" unless (@$a);

    my $cmd = shift @$a;

    my $usage  = "toggle:noArg";
    my $usageL = "";

    # usage: mode
    my $i =
      $autoMode && ReadingsVal( $name, "daytime", "night" ) ne "night"
      ? HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "daytime", 0 ),
        $UConv::daytimes{en} )
      : 0;
    $usage  .= " mode:";
    $usageL .= " mode_$langUc:";
    while ( $i < scalar @{ $UConv::daytimes{en} } ) {
        last
          if ( $autoMode
            && $i == 6
            && ReadingsVal( $name, "daytime", "night" ) !~
            m/^evening|midevening|night$/ );
        if (   $autoMode
            && ReadingsVal( $name, "daytime", "night" ) eq "night"
            && $i > 3
            && $i != 6 )
        {
            $i++;
        }
        else {
            $usage  .= $UConv::daytimes{en}[$i];
            $usageL .= $UConv::daytimes{$lang}[$i];
            $i++;
            unless ( $autoMode
                && $i == 6
                && ReadingsVal( $name, "daytime", "night" ) !~
                m/^evening|midevening|night$/ )
            {
                $usage .= "," unless ( $i == scalar @{ $UConv::daytimes{en} } );
                $usageL .= ","
                  unless ( $i == scalar @{ $UConv::daytimes{$lang} } );
            }
        }
    }

    # usage: autoMode
    $usage .= " autoMode:" . join( ",", @{ $stateOnoff{en} } );
    $usageL .= " autoMode_$langUc:" . join( ",", @{ $stateOnoff{$lang} } );

    $usage .= " $usageL" unless ( $lang eq "en" );
    return "Set usage: choose one of $usage"
      unless ( $cmd && $cmd ne "?" );

    return
      "Device is currently $security and cannot be controlled at this state"
      unless ( $security =~ m/^unlocked|locked$/ );

    # mode
    if (   $cmd eq "state"
        || $cmd eq "mode"
        || $cmd eq "state_$langUc"
        || $cmd eq "mode_$langUc"
        || grep ( m/^$cmd$/i, @{ $UConv::daytimes{en} } )
        || grep ( /^$cmd$/i,  @{ $UConv::daytimes{$lang} } ) )
    {
        $cmd = shift @$a
          if ( $cmd eq "state"
            || $cmd eq "mode"
            || $cmd eq "state_$langUc"
            || $cmd eq "mode_$langUc" );

        my $i = HOMESTATEtk_GetIndexFromArray( $cmd, $UConv::daytimes{en} );
        $i = HOMESTATEtk_GetIndexFromArray( $cmd, $UConv::daytimes{$lang} )
          unless ( $lang eq "en" || defined($i) );
        $i = $cmd
          if ( !defined($i)
            && $cmd =~ /^\d+$/
            && defined( $UConv::daytimes{en}[$cmd] ) );

        return "Invalid argument $cmd"
          unless ( defined($i) );

        my $id =
          HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "daytime", 0 ),
            $UConv::daytimes{en} );

        if ($autoMode) {

            # during daytime, one cannot go back in time...
            $i = $id
              if ( ReadingsVal( $name, "daytime", "night" ) ne "night"
                && $i < $id );

            # evening is latest until evening itself was reached
            $i = $id if ( $i >= 6 && $id <= 3 );

            # afternoon is latest until morning was reached
            $i = 6 if ( $i >= 4 && $i != 6 && $id == 6 );
            $i = 0 if ( $i > 6 && $id == 6 );
        }

        Log3 $name, 2, "$TYPE set $name mode " . $UConv::daytimes{en}[$i];
        $rvals{mode} = $UConv::daytimes{en}[$i];
    }

    # toggle
    elsif ( $cmd eq "toggle" ) {
        my $i = HOMESTATEtk_GetIndexFromArray( $mode, $UConv::daytimes{en} );
        my $id =
          HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "daytime", 0 ),
            $UConv::daytimes{en} );

        $i++;
        $i = 0 if ( $i == 7 );

        if ($autoMode) {

            # during daytime, one cannot go back in time...
            $i = $id
              if ( ReadingsVal( $name, "daytime", "night" ) ne "night"
                && $i < $id );

            # evening is latest until evening itself was reached
            $i = $id if ( $i >= 6 && $id <= 3 );

            # afternoon is latest until morning was reached
            $i = 6 if ( $i >= 4 && $i != 6 && $id == 6 );
            $i = 0 if ( $i > 6 && $id == 6 );
        }

        Log3 $name, 2, "$TYPE set $name mode " . $UConv::daytimes{en}[$i];
        $rvals{mode} = $UConv::daytimes{en}[$i];
    }

    # autoMode
    elsif ( $cmd eq "autoMode" || $cmd eq "autoMode_$langUc" ) {
        my $p1 = shift @$a;

        my $i = HOMESTATEtk_GetIndexFromArray( $p1, $stateOnoff{en} );
        $i = HOMESTATEtk_GetIndexFromArray( $p1, $stateOnoff{$lang} )
          unless ( $lang eq "en" || defined($i) );
        $i = $cmd
          if ( !defined($i)
            && $cmd =~ /^\d+$/
            && defined( $stateOnoff{en}[$cmd] ) );

        return "Invalid argument $cmd"
          unless ( defined($i) );

        Log3 $name, 2, "$TYPE set $name autoMode " . $stateOnoff{en}[$i];
        $rvals{autoMode} = $stateOnoff{en}[$i];
    }

    # usage
    else {
        return "Unknown set command $cmd, choose one of $usage";
    }

    readingsBeginUpdate($hash);

    # if autoMode changed
    if ( defined( $rvals{autoMode} ) ) {
        readingsBulkUpdateIfChanged( $hash, "autoMode", $rvals{autoMode} );
        readingsBulkUpdateIfChanged(
            $hash,
            "autoMode_$langUc",
            $stateOnoff{$lang}[
              HOMESTATEtk_GetIndexFromArray(
                  $rvals{autoMode}, $stateOnoff{en}
              )
            ]
        ) unless ( $lang eq "en" );

        if ( $rvals{autoMode} eq "on" ) {
            my $im =
              HOMESTATEtk_GetIndexFromArray( $mode, $UConv::daytimes{en} );
            my $id =
              HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "daytime", 0 ),
                $UConv::daytimes{en} );

            $rvals{mode} = $UConv::daytimes{en}[$id]
              if ( $im < $id || ( $im == 6 && $id < 6 ) )
              ;    #TODO check when switching during evening and midevening time
        }
    }

    # if mode changed
    if ( defined( $rvals{mode} ) && $rvals{mode} ne $mode ) {
        my $modeL = ReadingsVal( $name, "mode_$langUc", "" );
        readingsBulkUpdate( $hash, "lastMode", $mode ) if ( $mode ne "" );
        readingsBulkUpdate( $hash, "lastMode_$langUc", $modeL )
          if ( $modeL ne "" );
        $mode = $rvals{mode};
        $modeL =
          $UConv::daytimes{$lang}
          [ HOMESTATEtk_GetIndexFromArray( $rvals{mode}, $UConv::daytimes{en} )
          ];
        readingsBulkUpdate( $hash, "mode",         $mode );
        readingsBulkUpdate( $hash, "mode_$langUc", $modeL )
          unless ( $lang eq "en" );
    }

    HOMESTATEtk_UpdateReadings($hash);
    readingsEndUpdate( $hash, 1 );

    return undef;
}

sub HOMESTATEtk_Get($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = shift @$a;
    my $lang =
      lc( AttrVal( $name, "Lang", AttrVal( "global", "language", "EN" ) ) );
    my $langUc = uc($lang);

    return "No argument given" unless (@$a);

    my $cmd = shift @$a;

    my $usage = "Unknown argument $cmd, choose one of schedule";

    # schedule
    if ( $cmd eq "schedule" ) {
        my $date = shift @$a;
        my $time = shift @$a;

        if ($date) {
            return "invalid date format $date"
              unless ( !$date
                || $date =~ m/^\d{4}\-\d{2}-\d{2}$/
                || $date =~ m/^\d{2}-\d{2}$/
                || $date =~ m/^\d{10}$/ );
            return "invalid time format $time"
              unless ( !$time
                || $time =~ m/^\d{2}:\d{2}(:\d{2})?$/ );

            unless ( $date =~ m/^\d{10}$/ ) {
                my ( $sec, $min, $hour, $mday, $mon, $year ) = UConv::_time();
                $date = "$year-$date" if ( $date =~ m/^\d{2}-\d{2}$/ );
                $time .= ":00" if ( $time && $time =~ m/^\d{2}:\d{2}$/ );

                $date .= $time ? " $time" : " 00:00:00";

               # ( $year, $mon, $mday, $hour, $min, $sec ) =
               #   split( /[\s.:-]+/, $date );
               # $date = timelocal( $sec, $min, $hour, $mday, $mon - 1, $year );
                $date = time_str2num($date);
            }
        }

        #TODO timelocal? 03-26 results in wrong timestamp
        # return PrintHash(
        #     $date
        #     ? %{ HOMESTATEtk_GetDaySchedule( $hash, $date, undef, $lang ) }
        #       {events}
        #     : $hash->{helper}{events},
        #     3
        # );
        return PrintHash(
            $date
            ? HOMESTATEtk_GetDaySchedule( $hash, $date, undef, $lang )
            : $hash->{'.events'},
            3
        );
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

sub HOMESTATEtk_Attr(@) {
    my ( $cmd, $name, $attribute, $value ) = @_;
    my $hash     = $defs{$name};
    my $TYPE     = $hash->{TYPE};
    my $security = ReadingsVal( $name, "security", "" );

    return
"Device is currently $security and attributes cannot be changed at this state"
      unless ( !$init_done || $security =~ m/^unlocked|locked$/ );

    if ( $attribute eq "HomestateDevices" ) {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );

        delete $hash->{HOMESTATES};
        $hash->{HOMESTATES} = $value unless ( $cmd eq "del" );
    }

    elsif ( $attribute eq "FloorstateDevices" ) {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );

        delete $hash->{SECTIONSTATES};
        $hash->{SECTIONSTATES} = $value unless ( $cmd eq "del" );
    }

    elsif ( $attribute eq "RoomstateDevices" ) {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );

        delete $hash->{ROOMSTATES};
        $hash->{ROOMSTATES} = $value unless ( $cmd eq "del" );
    }

    elsif ( $attribute eq "ResidentsDevices" ) {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );

        delete $hash->{RESIDENTS};
        $hash->{RESIDENTS} = $value unless ( $cmd eq "del" );
    }

    elsif ( $attribute eq "HolidayDevices" ) {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );
    }

    elsif ( $attribute eq "DebugDate" ) {
        return
            "Invalid format for $attribute. Can be:\n"
          . "\nYYYY-MM-DD"
          . "\nYYYY-MM-DD HH:MM"
          . "\nYYYY-MM-DD HH:MM:SS"
          . "\nMM-DD"
          . "\nMM-DD HH:MM"
          . "\nMM-DD HH:MM:SS"
          unless ( $cmd eq "del"
            || $value =~
            m/^((?:\d{4}\-)?\d{2}-\d{2})(?: (\d{2}:\d{2}(?::\d{2})?))?$/ );
    }

    elsif ( !$init_done ) {
        return undef;
    }

    elsif ( $attribute eq "disable" ) {
        if ( $value and $value == 1 ) {
            $hash->{STATE} = "disabled";
        }
        elsif ( $cmd eq "del" or !$value ) {
            evalStateFormat($hash);
        }
    }

    elsif ( $attribute eq "Lang" ) {
        my $lang =
          $cmd eq "set"
          ? lc($value)
          : lc( AttrVal( "global", "language", "EN" ) );
        my $langUc = uc($lang);

        # for initial define, ensure fallback to EN
        $lang = "en"
          if ( $cmd eq "init" && $lang !~ /^en|de$/i );

        if ( $lang eq "de" ) {
            $attr{$name}{alias} = "Modus"
              if ( !defined( $attr{$name}{alias} )
                || $attr{$name}{alias} eq "Mode" );
            $attr{$name}{webCmd} = "mode_$langUc"
              if ( !defined( $attr{$name}{webCmd} )
                || $attr{$name}{webCmd} eq "mode" );

            if ( $TYPE eq "HOMESTATE" ) {
                $attr{$name}{group} = "Zuhause Status"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Home State" );
            }
            if ( $TYPE eq "SECTIONSTATE" ) {
                $attr{$name}{group} = "Bereichstatus"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Section State" );
            }
            if ( $TYPE eq "ROOMSTATE" ) {
                $attr{$name}{group} = "Raumstatus"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Room State" );
            }
        }

        elsif ( $lang eq "en" ) {
            $attr{$name}{alias} = "Mode"
              if ( !defined( $attr{$name}{alias} )
                || $attr{$name}{alias} eq "Modus" );
            $attr{$name}{webCmd} = "mode"
              if ( !defined( $attr{$name}{webCmd} )
                || $attr{$name}{webCmd} =~ /^mode_[A-Z]{2}$/ );

            if ( $TYPE eq "HOMESTATE" ) {
                $attr{$name}{group} = "Home State"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Zuhause Status" );
            }
            if ( $TYPE eq "SECTIONSTATE" ) {
                $attr{$name}{group} = "Section State"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Bereichstatus" );
            }
            if ( $TYPE eq "ROOMSTATE" ) {
                $attr{$name}{group} = "Room State"
                  if ( !defined( $attr{$name}{group} )
                    || $attr{$name}{group} eq "Raumstatus" );
            }
        }
        else {
            return "Unsupported language $langUc";
        }

        $attr{$name}{$attribute} = $value if ( $cmd eq "set" );
        evalStateFormat($hash);
    }

    return undef;
}

sub HOMESTATEtk_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name    = $hash->{NAME};
    my $TYPE    = $hash->{TYPE};
    my $devName = $dev->{NAME};
    my $devType = GetType($devName);

    if ( $devName eq "global" ) {
        my $events = deviceEvents( $dev, 1 );
        return "" unless ($events);

        foreach ( @{$events} ) {

            next if ( $_ =~ m/^[A-Za-z\d_-]+:/ );

            # module and device initialization
            if ( $_ =~ m/^INITIALIZED|REREADCFG$/ ) {
                if ( !defined( &{'DoInitDev'} ) ) {
                    if ( $_ eq "REREADCFG" ) {
                        delete $modules{$devType}{READY};
                        delete $modules{$devType}{INIT};
                    }
                    RESIDENTStk_DoInitDev(
                        devspec2array("TYPE=$TYPE:FILTER=MOD_INIT=.+") );
                }
            }

            # if any of our monitored devices was modified,
            # recalculate monitoring status
            elsif ( $_ =~
                m/^(DEFINED|MODIFIED|RENAMED|DELETED)\s+([A-Za-z\d_-]+)$/ )
            {
                if ( defined( &{'DoInitDev'} ) ) {

                    # DELETED would normally be handled by fhem.pl and imply
                    # DoModuleTrigger instead of DoInitDev to update module
                    # init state
                    next if ( $_ =~ /^DELETED/ );
                    DoInitDev($name);
                }
                else {

                    # for DELETED, we normally would want to use
                    # DoModuleTrigger() but we miss the deleted
                    # device's TYPE at this state :-(
                    RESIDENTStk_DoInitDev($name);
                }
            }

            # only process attribute events
            next
              unless ( $_ =~
m/^((?:DELETE)?ATTR)\s+([A-Za-z\d._]+)\s+([A-Za-z\d_\.\-\/]+)(?:\s+(.*)\s*)?$/
              );

            my $cmd  = $1;
            my $d    = $2;
            my $attr = $3;
            my $val  = $4;
            my $type = GetType($d);

            # filter attributes to be processed
            next
              unless ( $attr =~ /[Dd]evices?$/
                || $attr eq "DebugDate" );

            # when own attributes were changed
            if ( $d eq $name ) {
                if ( defined( &{'DoInitDev'} ) ) {
                    delete $hash->{NEXT_EVENT};
                    RemoveInternalTimer($hash);
                    InternalTimer( gettimeofday() + 0.5, "DoInitDev", $hash );
                }
                else {
                    delete $hash->{NEXT_EVENT};
                    RemoveInternalTimer($hash);
                    InternalTimer( gettimeofday() + 0.5,
                        "RESIDENTStk_DoInitDev", $hash );
                }
                return "";
            }
        }

        return "";
    }

    return "" if ( IsDisabled($name) or IsDisabled($devName) );

    # process events from RESIDENTS, ROOMMATE or GUEST devices
    # only when they hit HOMESTATE devices
    if (   $TYPE ne $devType
        && $devType =~
        m/^HOMESTATE|SECTIONSTATE|ROOMSTATE|RESIDENTS|ROOMMATE|GUEST$/ )
    {

        my $events = deviceEvents( $dev, 1 );
        return "" unless ($events);

        foreach my $event ( @{$events} ) {
            next unless ( defined($event) );

            # state changed
            if (   $event !~ /^[a-zA-Z\d._]+:/
                || $event =~ /^state:/
                || $event =~ /^presence:/
                || $event =~ /^mode:/
                || $event =~ /^security:/
                || $event =~ /^wayhome:/
                || $event =~ /^wakeup:/ )
            {
                if ( defined( &{'DoInitDev'} ) ) {
                    DoInitDev($name);
                }
                else {
                    RESIDENTStk_DoInitDev($name);
                }
            }
        }

        return "";
    }

    # process own events
    elsif ( $devName eq $name ) {
        my $events = deviceEvents( $dev, 1 );
        return "" unless ($events);

        foreach my $event ( @{$events} ) {
            next unless ( defined($event) );

        }

        return "";
    }

    return "";
}

sub HOMESTATEtk_GetIndexFromArray($$) {
    my ( $string, $array ) = @_;
    return undef unless ( ref($array) eq "ARRAY" );
    my ($index) = grep { $array->[$_] =~ /^$string$/i } ( 0 .. @$array - 1 );
    return defined $index ? $index : undef;
}

sub HOMESTATEtk_findHomestateSlaves($;$) {
    my ( $hash, $ret ) = @_;
    my @slaves;

    if ( $hash->{TYPE} eq "HOMESTATE" ) {

        my @SECTIONSTATES;
        foreach ( devspec2array("TYPE=SECTIONSTATE") ) {
            next
              unless (
                defined( $defs{$_}{SECTIONSTATES} )
                && grep { $hash->{NAME} eq $_ }
                split( /,/, $defs{$_}{SECTIONSTATES} )
              );
            push @SECTIONSTATES, $_;
        }

        if ( scalar @SECTIONSTATES ) {
            $hash->{SECTIONSTATES} = join( ",", @SECTIONSTATES );
        }
        elsif ( $hash->{SECTIONSTATES} ) {
            delete $hash->{SECTIONSTATES};
        }

        if ( $hash->{SECTIONSTATES} ) {
            $ret .= "," if ($ret);
            $ret .= $hash->{SECTIONSTATES};
        }
    }

    if ( $hash->{TYPE} eq "HOMESTATE" || $hash->{TYPE} eq "SECTIONSTATE" ) {

        my @ROOMSTATES;
        foreach ( devspec2array("TYPE=ROOMSTATE") ) {
            next
              unless (
                (
                    defined( $defs{$_}{HOMESTATES} )
                    && grep { $hash->{NAME} eq $_ }
                    split( /,/, $defs{$_}{HOMESTATES} )
                )
                || (
                    defined( $defs{$_}{SECTIONSTATES} )
                    && grep { $hash->{NAME} eq $_ }
                    split( /,/, $defs{$_}{SECTIONSTATES} )
                )
              );
            push @ROOMSTATES, $_;
        }

        if ( scalar @ROOMSTATES ) {
            $hash->{ROOMSTATES} = join( ",", @ROOMSTATES );
        }
        elsif ( $hash->{ROOMSTATES} ) {
            delete $hash->{ROOMSTATES};
        }

        if ( $hash->{ROOMSTATES} ) {
            $ret .= "," if ($ret);
            $ret .= $hash->{ROOMSTATES};
        }
    }

    if ( $hash->{RESIDENTS} ) {
        $ret .= "," if ($ret);
        $ret .= $hash->{RESIDENTS};
    }

    return HOMESTATEtk_findDummySlaves( $hash, $ret );
}

sub HOMESTATEtk_findDummySlaves($;$);

sub HOMESTATEtk_findDummySlaves($;$) {
    my ( $hash, $ret ) = @_;
    $ret = "" unless ($ret);

    return $ret;
}

sub HOMESTATEtk_devStateIcon($) {
    my ($hash) = @_;
    $hash = $defs{$hash} if ( ref($hash) ne 'HASH' );

    return undef if ( !$hash );
    my $name = $hash->{NAME};
    my $lang =
      lc( AttrVal( $name, "Lang", AttrVal( "global", "language", "EN" ) ) );
    my $langUc = uc($lang);
    my @devStateIcon;

    # mode
    my $i = 0;
    foreach ( @{ $UConv::daytimes{en} } ) {
        push @devStateIcon, "$_:$UConv::daytimes{icons}[$i++]:toggle";
    }
    unless ( $lang eq "en" && defined( $UConv::daytimes{$lang} ) ) {
        $i = 0;
        foreach ( @{ $UConv::daytimes{$lang} } ) {
            push @devStateIcon, "$_:$UConv::daytimes{icons}[$i++]:toggle";
        }
    }

    # security
    $i = 0;
    foreach ( @{ $stateSecurity{en} } ) {
        push @devStateIcon, "$_:$stateSecurity{icons}[$i++]";
    }
    unless ( $lang eq "en" && defined( $UConv::daytimes{$lang} ) ) {
        $i = 0;
        foreach ( @{ $stateSecurity{$lang} } ) {
            push @devStateIcon, "$_:$stateSecurity{icons}[$i++]";
        }
    }

    return join( " ", @devStateIcon );
}

sub HOMESTATEtk_GetDaySchedule($;$$$$$) {
    my ( $hash, $time, $totalTemporalHours, $lang, @srParams ) = @_;
    my $name = $hash->{NAME};
    $lang = (
          $attr{global}{language}
        ? $attr{global}{language}
        : "EN"
    ) unless ($lang);

    return undef
      unless ( !$time || $time =~ /^\d{10}(?:\.\d+)?$/ );

    my $ret = UConv::GetDaytime( $time, $totalTemporalHours, $lang, @srParams );

    # consider user defined vacation days
    my $holidayDevs = AttrVal( $name, "HolidayDevices", "" );
    foreach my $holidayDev ( split( /,/, $holidayDevs ) ) {
        next
          unless ( IsDevice( $holidayDev, "holiday" )
            && AttrVal( "global", "holiday2we", "" ) ne $holidayDev );

        my $date = sprintf( "%02d-%02d", $ret->{monISO}, $ret->{mday} );
        my $tod = holiday_refresh( $holidayDev, $date );
        $date =
          sprintf( "%02d-%02d", $ret->{'-1'}{monISO}, $ret->{'-1'}{mday} );
        my $ytd = holiday_refresh( $holidayDev, $date );
        $date = sprintf( "%02d-%02d", $ret->{1}{monISO}, $ret->{1}{mday} );
        my $tom = holiday_refresh( $holidayDev, $date );

        if ( $tod ne "none" ) {
            $ret->{iswe}      += 3;
            $ret->{isholiday} += 2;
            $ret->{day_desc} = $tod unless ( $ret->{isholiday} == 3 );
            $ret->{day_desc} .= ", $tod" if ( $ret->{isholiday} == 3 );
        }
        if ( $ytd ne "none" ) {
            $ret->{'-1'}{isholiday} += 2;
            $ret->{'-1'}{day_desc} = $ytd
              unless ( $ret->{'-1'}{isholiday} == 3 );
            $ret->{'-1'}{day_desc} .= ", $ytd"
              if ( $ret->{'-1'}{isholiday} == 3 );
        }
        if ( $tom ne "none" ) {
            $ret->{1}{isholiday} += 2;
            $ret->{1}{day_desc} = $tom;
            $ret->{1}{day_desc} = $tom unless ( $ret->{1}{isholiday} == 3 );
            $ret->{1}{day_desc} .= ", $tom"
              if ( $ret->{1}{isholiday} == 3 );
        }
    }

    return $ret;
}

sub HOMESTATEtk_UpdateReadings (@) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $TYPE   = $hash->{TYPE};
    my $t      = $hash->{'.t'};
    my $state    = ReadingsVal( $name, "state",    "" );
    my $security = ReadingsVal( $name, "security", "" );
    my $daytime  = ReadingsVal( $name, "daytime",  "" );
    my $mode     = ReadingsVal( $name, "mode",     "" );
    my $autoMode =
      HOMESTATEtk_GetIndexFromArray( ReadingsVal( $name, "autoMode", "on" ),
        $stateOnoff{en} );
    my $lang =
      lc( AttrVal( $name, "Lang", AttrVal( "global", "language", "EN" ) ) );
    my $langUc = uc($lang);

    # presence
    my $state_home      = 0;
    my $state_gotosleep = 0;
    my $state_asleep    = 0;
    my $state_awoken    = 0;
    my $state_absent    = 0;
    my $state_gone      = 0;
    my $wayhome         = 0;
    my $wayhomeDelayed  = 0;
    my $wakeup          = 0;
    foreach my $internal ( "RESIDENTS", "SECTIONSTATES", "ROOMSTATES" ) {
        next unless ( $hash->{$internal} );
        foreach my $presenceDev ( split( /,/, $hash->{$internal} ) ) {
            my $state = ReadingsVal( $presenceDev, "state", "gone" );
            $state_home++      if ( $state eq "home" );
            $state_gotosleep++ if ( $state eq "gotosleep" );
            $state_asleep++    if ( $state eq "asleep" );
            $state_awoken++    if ( $state eq "awoken" );
            $state_absent++    if ( $state eq "absent" );
            $state_gone++      if ( $state eq "gone" || $state eq "none" );

            my $wayhome = ReadingsVal( $presenceDev, "wayhome", 0 );
            $wayhome++ if ($wayhome);
            $wayhomeDelayed++ if ( $wayhome == 2 );

            my $wakeup = ReadingsVal( $presenceDev, "wakeup", 0 );
            $wakeup++ if ($wakeup);
        }
    }
    $state_home = 1
      unless ( $hash->{RESIDENTS}
        || $hash->{SECTIONSTATES}
        || $hash->{ROOMSTATES} );

    # autoMode
    if ( $autoMode && $mode ne $daytime ) {
        my $im = HOMESTATEtk_GetIndexFromArray( $mode, $UConv::daytimes{en} );
        my $id =
          HOMESTATEtk_GetIndexFromArray( $daytime, $UConv::daytimes{en} );

        if (
            $mode eq "" || (

                # follow daymode throughout the day until midnight
                ( $im < $id && $id != 6 )

                # first change after midnight
                || ( $im >= 4 && $id == 6 )

                # morning
                || ( $im == 6 && $id >= 0 && $id <= 3 )
            )
          )
        {
            readingsBulkUpdate( $hash, "lastMode", $mode ) if ( $mode ne "" );
            $mode = $daytime;
            readingsBulkUpdate( $hash, "mode", $mode );
            unless ( $lang eq "en" ) {
                my $modeL    = ReadingsVal( $name, "mode_$langUc",    "" );
                my $daytimeL = ReadingsVal( $name, "daytime_$langUc", "" );
                readingsBulkUpdate( $hash, "lastMode_$langUc", $modeL )
                  if ( $modeL ne "" );
                readingsBulkUpdate( $hash, "mode_$langUc", $daytimeL )
                  if ( $daytimeL ne "" );
            }
        }
    }

    #
    # security calculation
    #
    my $newsecurity;

    # unsecured
    if ( $state_home > 0 && $mode !~ /^night|midevening$/ ) {
        $newsecurity = "unlocked";
    }

    # locked
    elsif ($state_home > 0
        || $state_awoken > 0
        || $state_gotosleep > 0
        || $wakeup > 0 )
    {
        $newsecurity = "locked";
    }

    # night
    elsif ( $state_asleep > 0 ) {
        $newsecurity = "protected";
    }

    # secured
    elsif ( $state_absent > 0 || $wayhome > 0 ) {
        $newsecurity = "secured";
    }

    # extended
    else {
        $newsecurity = "guarded";
    }

    if ( $newsecurity ne $security ) {
        readingsBulkUpdate( $hash, "lastSecurity", $security )
          if ( $security ne "" );
        $security = $newsecurity;
        readingsBulkUpdate( $hash, "security", $security );

        unless ( $lang eq "en" ) {
            my $securityL = ReadingsVal( $name, "security_$langUc", "" );
            readingsBulkUpdate( $hash, "lastSecurity_$langUc", $securityL )
              if ( $securityL ne "" );
            $securityL =
              $stateSecurity{$lang}
              [ HOMESTATEtk_GetIndexFromArray( $security, $stateSecurity{en} )
              ];
            readingsBulkUpdate( $hash, "security_$langUc", $securityL );
        }
    }

    #
    # state calculation:
    # combine security and mode
    #
    my $newstate;
    my $statesrc;

    # mode
    if ( $security =~ m/^unlocked|locked/ ) {
        $newstate = $mode;
        $statesrc = "mode";
    }

    # security
    else {
        $newstate = $security;
        $statesrc = "security";
    }

    if ( $newstate ne $state ) {
        readingsBulkUpdate( $hash, "lastState", $state ) if ( $state ne "" );
        $state = $newstate;
        readingsBulkUpdate( $hash, "state", $state );

        unless ( $lang eq "en" ) {
            my $stateL = ReadingsVal( $name, "state_$langUc", "" );
            readingsBulkUpdate( $hash, "lastState_$langUc", $stateL )
              if ( $stateL ne "" );
            $stateL = ReadingsVal( $name, $statesrc . "_$langUc", "" );
            readingsBulkUpdate( $hash, "state_$langUc", $stateL );
        }
    }

}

1;

=for :application/json;q=META.json HOMESTATEtk.pm
{
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "keywords": [
    "RESIDENTS"
  ]
}
=end :application/json;q=META.json
