# $Id$
##############################################################################
#
#     59_Twilight.pm
#     Copyright by Sebastian Stuecker
#     erweitert von Dietmar Ortmann
#     Orphan module, maintained by Beta-User since 09-2020
#
#     used algorithm see:          http://lexikon.astronomie.info/zeitgleichung/
#
#     Sun position computing
#     Copyright (C) 2013 Julian Pawlowski, julian.pawlowski AT gmail DOT com
#     based on Twilight.tcl  http://www.homematic-wiki.info/mw/index.php/TCLScript:twilight
#     With contribution from http://www.ip-symcon.de/forum/threads/14925-Sonnenstand-berechnen-(Azimut-amp-Elevation)
#
#     e-mail: omega at online dot de
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

package FHEM::Twilight;    ## no critic 'Package declaration'

use strict;
use warnings;

use Math::Trig;
use Time::Local qw(timelocal_nocheck);
use List::Util qw(max min);
use Scalar::Util qw(looks_like_number);
use GPUtils qw(GP_Import);
#use POSIX qw(strftime);
use FHEM::Meta;
use FHEM::Core::Timer::Register qw(:ALL);

#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          defs
          attr
          init_done
          DAYSECONDS
          HOURSECONDS
          MINUTESECONDS
          CommandAttr
          CommandModify
          devspec2array
          notifyRegexpChanged
          deviceEvents
          readingFnAttributes
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          AttrVal
          ReadingsVal
          ReadingsNum
          ReadingsAge
          InternalVal
          IsDisabled
          Log3
          InternalTimer
          FmtTime
          FmtDateTime
          perlSyntaxCheck
          EvalSpecials
          AnalyzePerlCommand
          AnalyzeCommandChain
          stacktrace
          sr_alt
          hms2h
          h2hms_fmt
          )
    );
}

sub ::Twilight_Initialize { goto &Initialize }
sub ::twilight { goto &twilight }


################################################################################
sub Initialize {
    my $hash = shift // return;

    # Consumer
    $hash->{DefFn}    = \&Twilight_Define;
    $hash->{UndefFn}  = \&Twilight_Undef;
    $hash->{GetFn}    = \&Twilight_Get;
    $hash->{NotifyFn} = \&Twilight_Notify;
    $hash->{AttrFn}   = \&Twilight_Attr;
    $hash->{AttrList} = "$readingFnAttributes useExtWeather";
    $hash->{parseParams} = 1;
    return FHEM::Meta::InitMod( __FILE__, $hash );
}

################################################################################
sub Twilight_Define {
    my $hash = shift;
    my $aref = shift;
    my $href = shift;
    return if !defined $aref && !defined $href;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    return 'syntax: define <name> Twilight [<latitude> <longitude>] [indoorHorizon=... ] [weatherDevice=<device:reading>]'
      if int(@$aref) < 2 || int(@$aref) > 6;

    my $DEFmayChange = int(@$aref) == 6 ? 1 : 0;

    my $weather = q{none};
    $weather = pop @$aref if int(@$aref) == 6 || int(@$aref) == 4 && !looks_like_number($$aref[3]);
    $weather = $$href{weatherDevice} // $weather; ##hashes don't work yet...

    my $indoor_horizon = q{none};
    $indoor_horizon = pop @$aref if int(@$aref) == 5 || int(@$aref) == 3;
    $hash->{STATE} = '0';
    my $name      = shift @$aref;
    my $type      = shift @$aref;
    my $latitude  = shift @$aref // AttrVal( 'global', 'latitude', 50.112 );
    my $longitude = shift @$aref // AttrVal( 'global', 'longitude', 8.686 );

    if ($indoor_horizon eq 'none') { $indoor_horizon = $$href{indoorHorizon} // 3 }; ##hashes don't work yet...

    return 'Argument Latitude is not a valid number'
      if !looks_like_number($latitude);
    return 'Argument Longitude is not a valid number'
      if !looks_like_number($longitude);
    return 'Argument Indoor_Horizon is not a valid number'
      if !looks_like_number($indoor_horizon);

    $latitude  = min( 90,  max( -90,  $latitude ) );
    $longitude = min( 180, max( -180, $longitude ) );
    $indoor_horizon =
      min( 20, max( -6, $indoor_horizon ) );

    $hash->{WEATHER_HORIZON} = $indoor_horizon;
    $hash->{INDOOR_HORIZON} = $indoor_horizon; 
    $hash->{helper}{'.LATITUDE'}        = $latitude;
    $hash->{helper}{'.LONGITUDE'}       = $longitude;
    $hash->{helper}{'.startuptime'}     = time;
    $hash->{SUNPOS_OFFSET} = 5 * 60;

    $attr{$name}{verbose} = 4 if ( $name =~ m/^tst.*$/x );

    Log3( $hash, 1, "[$hash->{NAME}] Note: Twilight formerly used weather info from yahoo, but source is offline. Using a guessed Weather type device instead if available!"
    ) if looks_like_number($weather);

    my $useTimer = looks_like_number($weather) || ( $DEFmayChange && $latitude  == AttrVal( 'global', 'latitude', 50.112 ) && $longitude == AttrVal( 'global', 'longitude', 8.686 ) ) ? 1 : 0;

    $hash->{DEFINE} = $weather ? $weather : 'none';
    InternalTimer(time, \&Twilight_Change_DEF,$hash,0) if $useTimer;

    return InternalTimer( time+$useTimer, \&Twilight_Firstrun,$hash,0) if !$init_done || $useTimer;
    return Twilight_Firstrun($hash);
}

################################################################################
sub Twilight_Undef {
    my $hash = shift;
    my $arg = shift // return;

    deleteAllRegIntTimer($hash);

    notifyRegexpChanged( $hash, "" );
    for my $key ( keys %{ $hash->{helper}{extWeather} } ) {
        delete $hash->{helper}{extWeather}{$key};
    }
    delete $hash->{helper}{extWeather};

    return;
}


################################################################################
sub Twilight_Change_DEF {
    my $hash  = shift // return;
    my $name = $hash->{NAME};
    my $newdef = "";
    my $weather = $hash->{DEFINE};
    $weather = "" if $weather eq 'none';
    if (looks_like_number($weather)) {
        my @wd = devspec2array("TYPE=Weather|PROPLANTA");
        my ($err, $wreading);
        ($err, $wreading) = Twilight_disp_ExtWeather($hash, $wd[0]) if $wd[0];
        $weather = $err ? "" : $wd[0] ;
    }
    $newdef = "$hash->{helper}{'.LATITUDE'} $hash->{helper}{'.LONGITUDE'}" if $hash->{helper}{'.LATITUDE'} != AttrVal( 'global', 'latitude', 50.112 ) || $hash->{helper}{'.LONGITUDE'} != AttrVal( 'global', 'longitude', 8.686 );
    $newdef .= " $hash->{INDOOR_HORIZON} $weather";
    $hash->{DEF} = $newdef;
    return;
}

################################################################################
sub Twilight_Notify {
    my $hash  = shift;
    my $whash = shift // return;

    return if !exists $hash->{helper}{extWeather};

    my $name = $hash->{NAME};
    return if(IsDisabled($name));

    my $wname = $whash->{NAME};
    my $events = deviceEvents( $whash, 1 );

    my $re = $hash->{helper}{extWeather}{regexp} // q{unknown};

    return if(!$events); # Some previous notify deleted the array.
    my $max = int(@{$events});
    my $ret = "";
    for (my $i = 0; $i < $max; $i++) {
        my $s = $events->[$i] // q{''};
        #$s = "" if(!defined($s));
        my $found = ($wname =~ m{\A$re\z}x || "$wname:$s" =~ m{\A$re\z}sx);

        return Twilight_HandleWeatherData( $hash, 1) if $found;
    }
    return;
}

sub Twilight_HandleWeatherData {
    my $hash     = shift // return;
    my $inNotify = shift // 0;
    my $wname = $hash->{helper}{extWeather}{Device} // q{none};
    my $name = $hash->{NAME};
    my ($extWeather, $sr_extWeather, $ss_extWeather);
    my $dispatch = defined $hash->{helper}{extWeather} && defined $hash->{helper}{extWeather}{dispatch} ? 1 : 0;

    if (!$dispatch 
        || $dispatch && !defined $hash->{helper}{extWeather}{dispatch}{function} && !defined $hash->{helper}{extWeather}{dispatch}{userfunction} )
    {
        $extWeather = ReadingsNum($wname, $hash->{helper}{extWeather}{Reading},-1);
    } elsif (defined $hash->{helper}{extWeather}{dispatch}{function} ) {
        #Log3( $hash, 5, "[$hash->{NAME}] before dispatch" );
        return if ref $hash->{helper}{extWeather}{dispatch}->{function} ne 'CODE';
        ( $extWeather, $sr_extWeather, $ss_extWeather ) = $hash->{helper}{extWeather}{dispatch}->{function}->($hash, $wname);
        Log3( $hash, 5, "[$hash->{NAME}] after dispatch. results: $extWeather $sr_extWeather $ss_extWeather" );

    } elsif (defined $hash->{helper}{extWeather}{dispatch}{userfunction} ) {
        #Log3( $hash, 5, "[$hash->{NAME}] before dispatch" );
        my %specials = (
                    '$W_DEVICE'  => $extWeather,
                    '$W_READING' => $hash->{helper}{extWeather}{trigger}
                       );
        my $evalcode = $hash->{helper}{extWeather}{dispatch}{userfunction};
        #map { my $key =  $_; $key =~ s{\$}{\\\$}gxms;
        #    my $val = $specials{$_};
        #    $evalcode =~ s{$key}{$val}gxms
        #} keys %specials;
        for my $key (keys %specials) {
            my $val = $specials{$key};
            $evalcode =~ s{\Q$key\E}{$val}gxms;
        }
        my $ret = AnalyzePerlCommand( $hash, $evalcode );
        Log3( $hash, 4, "[$hash->{NAME}] external code result: $ret" );
        ( $extWeather, $sr_extWeather, $ss_extWeather ) = 
            split m{:}x, $ret;
        return if !looks_like_number($extWeather);
        $sr_extWeather = 50 if !looks_like_number($sr_extWeather);
        $ss_extWeather = 50 if !looks_like_number($ss_extWeather);
    }

    my $lastcc = ReadingsNum($name, 'cloudCover', -1);

    #here we have to split up for extended forecast handling... 
    $inNotify ? Log3( $hash, 5, "[$name] NotifyFn called, reading is $extWeather, last is $lastcc" ) 
              : Log3( $hash, 5, "[$name] timer based weather update called, reading is $extWeather, last is $lastcc" );

    return if $inNotify && (abs($lastcc - $extWeather) <6 && !defined $hash->{helper}{extWeather}{dispatch} || ReadingsAge($name, 'cloudCover', 4000) < 3575 && defined $hash->{helper}{extWeather}{dispatch});

    my $weather_horizon = Twilight_getWeatherHorizon( $hash, $extWeather, 1);

    my ($sr, $ss) = Twilight_calc( $hash, $weather_horizon, '7' ); #these are numbers
    my ($sr_wh,$ss_wh);
    if (defined $ss_extWeather) {
        Log3( $hash, 5, "[$name] ss_extWeather exists" );
        $sr_wh = Twilight_getWeatherHorizon( $hash, $sr_extWeather, 0);
        $ss_wh = Twilight_getWeatherHorizon( $hash, $ss_extWeather, 0);
        my ($srt_wh, $sst_wh) = Twilight_calc( $hash, $sr_wh, "7" );
        $sr = $srt_wh;
        ($srt_wh, $sst_wh) = Twilight_calc( $hash, $ss_wh, "7" );
        $ss = $sst_wh;
    }

    my $now = time;
    Log3( $hash, 5, "[$name] extW-update fn: calc sr_w is ".FmtTime( $sr) .", ss_w is ".FmtTime( $ss) );

    #done for today?
    return if $inNotify && $now > min($ss , $hash->{TW}{ss_weather}{TIME});
    Log3( $hash, 5, "[$name] not yet done for today" );
    
    #set potential dates in the past to now
    my $sr_passed = 0;
    my $ss_passed = 0;
    if ($inNotify) { 
        $sr = max( $sr, $now - 0.01 );
        $ss = max( $ss, $now - 0.01 );
        $sr_passed = $hash->{TW}{sr_weather}{TIME} > $sr ? 1 : 0;
        $ss_passed = $hash->{TW}{ss_weather}{TIME} > $ss ? 1 : 0;
    }

    #renew dates and timers?, fire events?
    my $nextevent = ReadingsVal($name,'nextEvent','none');            
    my $nextEventTime = FmtTime( $sr );

    readingsBeginUpdate( $hash );
    readingsBulkUpdate( $hash, 'cloudCover', $extWeather );
    readingsBulkUpdate( $hash, 'cloudCover_sr', $sr_extWeather ) if $sr_wh && $now < $sr;
    readingsBulkUpdate( $hash, 'cloudCover_ss', $ss_extWeather ) if $ss_wh && $now < $ss;

    if ( $now < $sr ) {
        $hash->{TW}{sr_weather}{TIME} = $sr;
        resetRegIntTimer( 'sr_weather', $sr, \&Twilight_fireEvent, $hash, 0 );
        readingsBulkUpdate( $hash, 'sr_weather', $nextEventTime ) if $inNotify;
        readingsBulkUpdate( $hash, 'nextEventTime', $nextEventTime ) if $nextevent eq 'sr_weather';
    } elsif ( $sr_passed ) {
        deleteSingleRegIntTimer( 'sr_weather', $hash );
        readingsBulkUpdate( $hash, 'sr_weather', $nextEventTime );
        if ( $nextevent eq 'sr_weather' ) {
            readingsBulkUpdate( $hash, 'nextEvent', 'ss_weather' ) ;
            readingsBulkUpdate( $hash, 'nextEventTime', FmtTime( $ss ) ) ;
            readingsBulkUpdate( $hash, 'state', '6' );
            readingsBulkUpdate( $hash, 'light', '6' );
            readingsBulkUpdate( $hash, 'aktEvent', 'sr_weather' );
            resetRegIntTimer( 'ss_weather', $ss, \&Twilight_fireEvent, $hash, 0 );
        }
    } 

    if ( $now < $ss ) {
        $nextEventTime = FmtTime( $ss );
        $hash->{TW}{ss_weather}{TIME} = $ss;
        resetRegIntTimer( 'ss_weather', $ss, \&Twilight_fireEvent, $hash, 0 );
        readingsBulkUpdate( $hash, 'ss_weather', $nextEventTime ) if $inNotify;
        readingsBulkUpdate( $hash, 'nextEventTime', $nextEventTime ) if $nextevent eq 'ss_weather' && !$ss_passed;
    } elsif ( $ss_passed ) {
        deleteSingleRegIntTimer( 'ss_weather', $hash );
        readingsBulkUpdate( $hash, 'ss_weather', $nextEventTime );
        if ( $nextevent eq 'ss_weather' ) {
            readingsBulkUpdate( $hash, 'nextEvent', 'ss_indoor' ) ;
            readingsBulkUpdate( $hash, 'nextEventTime', FmtTime( $hash->{TW}{ss_indoor}{TIME} ) ) ;
            readingsBulkUpdate( $hash, 'aktEvent', 'ss_weather' );
            #readingsBulkUpdate( $hash, 'state', '8' );
            #readingsBulkUpdate( $hash, 'light', '4' );
            readingsBulkUpdate( $hash, 'state', '7' );
            readingsBulkUpdate( $hash, 'light', '5' );
        }
    }

    readingsEndUpdate( $hash, defined( $hash->{LOCAL} ? 0 : 1 ) );
    resetRegIntTimer('sunpos', $now+1, \&Twilight_sunpos, $hash, 0);
    return;
}

sub Twilight_Firstrun {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    my $attrVal = AttrVal( $name,'useExtWeather', $hash->{DEFINE});
    $attrVal = "$hash->{helper}{extWeather}{Device}:$hash->{helper}{extWeather}{Reading}" if !$attrVal && defined $hash->{helper} && defined $hash->{helper}{extWeather}{Device} && defined $hash->{helper}{extWeather}{Reading};
    $attrVal = "$hash->{helper}{extWeather}{Device}:$hash->{helper}{extWeather}{trigger}" if !$attrVal && defined $hash->{helper} && defined $hash->{helper}{extWeather}{Device} && defined $hash->{helper}{extWeather}{trigger};

    my $extWeatherVal = 0;

    if ($attrVal && $attrVal ne 'none') {
        Twilight_init_ExtWeather_usage( $hash, $attrVal );
        my $ewr = $hash->{helper}{extWeather}{Reading}  // $hash->{helper}{extWeather}{dispatch}{trigger} // $hash->{helper}{extWeather}{trigger}; 
        $extWeatherVal = ReadingsNum( $name, 'cloudCover', ReadingsNum( $hash->{helper}{extWeather}{Device}, $ewr, 0 ) );
        readingsSingleUpdate ( $hash, 'cloudCover', $extWeatherVal, 0 ) if $extWeatherVal;
    }
    Twilight_getWeatherHorizon( $hash, $extWeatherVal );
    
    my $fnHash = { HASH => $hash };
    Twilight_sunpos($fnHash) if !$attrVal || $attrVal eq 'none';
    Twilight_Midnight($fnHash, 1);

    delete $hash->{DEFINE};

    return;
}

################################################################################
sub Twilight_Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    return if (!$init_done);
    my $hash = $defs{$name};

    if ( $attrName eq 'useExtWeather' ) {
        if ($cmd eq 'set') {
            return "External weather device already in use, most likely assigned by define" if defined $hash->{helper} && defined $hash->{helper}{extWeather} && defined $hash->{helper}{extWeather}{regexp} && $hash->{helper}{extWeather}{regexp} =~ m{$attrVal}xms;
            return Twilight_init_ExtWeather_usage($hash, $attrVal); 
        } elsif ($cmd eq 'del') {
            notifyRegexpChanged( $hash, q{} );
            for my $key ( keys %{ $hash->{helper}{extWeather} } ) {
               delete $hash->{helper}{extWeather}{$key};
            }
            delete $hash->{helper}{extWeather};
        }
    }
    return;
}

sub Twilight_init_ExtWeather_usage {
    my $hash = shift // return;
    my $devreading = shift // 1000;
    my $useTimer = shift // 0;
    my ($extWeather, $extWReading, $err);
    my @parts;
    if (!looks_like_number($devreading)) {
        @parts = split m{\s}x, $devreading, 2;
        ($extWeather, $extWReading) = split m{:}x, $parts[0]; 
        return 'External weather device seems not to exist' if !defined $defs{$extWeather} && $init_done;
        
        ### This is the place to allow external dispatch functions...
        if ($parts[1] ) { #&& 0 to disable this part atm...
            my %specials = (
                '$W_DEV'     => $extWeather,
                '$W_READING' => $extWReading
            );
            $err = perlSyntaxCheck( $parts[1] );
            return $err if ( $err );
        }
    } else {
        #conversion code, try to guess the ext. weather device to replace yahoo
        my @devices=devspec2array(q{TYPE=Weather}); 
        return 'No Weather-Type device found' if !$devices[0];
        $extWeather = $devices[0];
    }
    
    ($err, $extWReading) = Twilight_disp_ExtWeather($hash, $extWeather) if !$extWReading; 
    return $err if $err;
    my $extWregex = qq($extWeather:$extWReading:.*);
    notifyRegexpChanged($hash, $extWregex);
    $hash->{helper}{extWeather}{regexp} = $extWregex;
    $hash->{helper}{extWeather}{Device} = $extWeather;
    $hash->{helper}{extWeather}{Reading} = $extWReading if !$parts[1] && !exists  $hash->{helper}{extWeather}{dispatch};
    if ($parts[1]) {
        $hash->{helper}{extWeather}{trigger} = $extWReading ;
        $parts[1] = qq ({ $parts[1] }) if $parts[1] !~ m/^[{].*}$/xms;
        $hash->{helper}{extWeather}{dispatch}{userfunction} = $parts[1];
    }
    return InternalTimer( time, \&Twilight_Firstrun,$hash,0) if $init_done && $useTimer;
    return;
}

sub Twilight_disp_ExtWeather {
    my $hash = shift;
    my $extWeather = shift //return;
    my ( $err, $extWReading );
    my $wtype = InternalVal( $extWeather, 'TYPE', undef );
    return ('No type info about extWeather available!', 'none') if !$wtype;
    for my $key ( keys %{ $hash->{helper}{extWeather} } ) {
        delete $hash->{helper}{extWeather}{$key};
    }
    delete $hash->{helper}{extWeather}{dispatch};

    my $dispatch = {
        Weather => {
            trigger => 'cloudCover', 
            function => \&getwTYPE_Weather 
         },
        PROPLANTA => { 
            trigger => 'fc0_cloud06',
            function => \&getwTYPE_PROPLANTA 
        }
    };
    if (ref $dispatch->{$wtype} eq 'HASH') {
        $extWReading =  $dispatch->{$wtype}{trigger};
        $hash->{helper}{extWeather}{dispatch} = $dispatch->{$wtype};
    } else {
        $extWReading = "none"; 
    }
    $err = $extWReading eq 'none' ? "No cloudCover reading assigned to $wtype, has to be implemented first; use dedicated form in define or attribute" : undef ;
    return $err, $extWReading;
}

################################################################################
sub Twilight_Get {
    my ( $hash, $aref, $href ) = @_;
    return 'argument is missing' if ( int(@$aref) != 2 );

    my $reading = @$aref[1];
    my $value;

    if ( defined( $hash->{READINGS}{$reading} ) ) {
        $value = $hash->{READINGS}{$reading}{VAL};
    }
    else {
        return "no such reading: $reading";
    }
    return "@$aref[0] $reading => $value";
}


################################################################################
sub secondsSinceMidnight {
    my $now  = shift // time;
    my @time = localtime($now);
    my $secs = ( $time[2] * 3600 ) + ( $time[1] * 60 ) + $time[0];
    return $secs;
}

################################################################################
sub Twilight_calc {
    my $hash = shift;
    my $deg  = shift;
    my $idx  = shift // return;
    my $now  = shift // time;
    
    my $midnight = $now - secondsSinceMidnight( $now );
    my $lat      = $hash->{helper}{'.LATITUDE'};
    my $long     = $hash->{helper}{'.LONGITUDE'};

    my $sr =
      sr_alt( $now, 1, 0, 0, 0, "Horizon=$deg", undef, undef, undef, $lat,
        $long );

    my $ss =
      sr_alt( $now, 0, 0, 0, 0, "Horizon=$deg", undef, undef, undef, $lat,
        $long );

    my ( $srhour, $srmin, $srsec ) = split m{:}x, $sr;
    $srhour -= 24 if ( $srhour >= 24 );
    my ( $sshour, $ssmin, $sssec ) = split m{:}x, $ss;
    $sshour -= 24 if ( $sshour >= 24 );

    my $sr1 = $midnight + 3600 * $srhour + 60 * $srmin + $srsec;
    my $ss1 = $midnight + 3600 * $sshour + 60 * $ssmin + $sssec;

    return ( 0, 0 ) if ( abs( $sr1 - $ss1 ) < 30 );
    return ( $sr1 + 0.01 * $idx ), ( $ss1 - 0.01 * $idx );
}

################################################################################
sub Twilight_TwilightTimes {
    my $hash = shift;
    my $whitchTimes = shift // return;
    my $firstrun = shift // 0;

    my $name = $hash->{NAME};

    my $swip    = $firstrun;

    my $lat  = $hash->{helper}{'.LATITUDE'};
    my $long = $hash->{helper}{'.LONGITUDE'};

# ------------------------------------------------------------------------------
    my $idx      = -1;

    my @horizons = (
        "_astro:-18", "_naut:-12", "_civil:-6", ":0",
        "_indoor:$hash->{INDOOR_HORIZON}",
        "_weather:$hash->{WEATHER_HORIZON}"
    );
    for my $horizon (@horizons) {
        $idx++;
        next if $whitchTimes eq 'weather' && $horizon !~ m{weather}x;

        my ( $sxname, $deg ) = split m{:}x, $horizon;
        my $sr = "sr$sxname";
        my $ss = "ss$sxname";
        $hash->{TW}{$sr}{NAME}  = $sr;
        $hash->{TW}{$ss}{NAME}  = $ss;
        $hash->{TW}{$sr}{DEG}   = $deg;
        $hash->{TW}{$ss}{DEG}   = $deg;
        $hash->{TW}{$sr}{LIGHT} = $idx + 1;
        $hash->{TW}{$ss}{LIGHT} = $idx;
        $hash->{TW}{$sr}{STATE} = $idx + 1;
        $hash->{TW}{$ss}{STATE} = 12 - $idx;
        $hash->{TW}{$sr}{SWIP}  = $swip;
        $hash->{TW}{$ss}{SWIP}  = $swip;

        ( $hash->{TW}{$sr}{TIME}, $hash->{TW}{$ss}{TIME} ) =
          Twilight_calc( $hash, $deg, $idx );

        if ( $hash->{TW}{$sr}{TIME} == 0 ) {
            Log3( $hash, 4, "[$name] hint: $hash->{TW}{$sr}{NAME},  $hash->{TW}{$ss}{NAME} are not defined(HORIZON=$deg)" );
        }
    }

# ------------------------------------------------------------------------------
    readingsBeginUpdate($hash);
    for my $ereignis ( keys %{ $hash->{TW} } ) {
        next if $whitchTimes eq 'weather' && $ereignis !~ m{weather}x;
        readingsBulkUpdate( $hash, $ereignis,
            !defined $hash->{TW}{$ereignis}{TIME} || $hash->{TW}{$ereignis}{TIME} == 0
            ? 'undefined'
            : FmtTime( $hash->{TW}{$ereignis}{TIME} ) );
    }

    readingsEndUpdate( $hash, defined $hash->{LOCAL} ? 0 : 1 );

# ------------------------------------------------------------------------------
    my @horizonsOhneDeg =
      map { my ( $e, $deg ) = split m{:}x, $_; "$e" } @horizons;
    my @ereignisse = (
        ( map { "sr$_" } @horizonsOhneDeg ),
        ( map { "ss$_" } reverse @horizonsOhneDeg ),
        "sr$horizonsOhneDeg[0]"
    );
    map { $hash->{TW}{ $ereignisse[$_] }{NAMENEXT} = $ereignisse[ $_ + 1 ] }
      0 .. $#ereignisse - 1;

# ------------------------------------------------------------------------------
    my $now              = time;

    for my $ereignis ( sort keys %{ $hash->{TW} } ) {
        next if ( $whitchTimes eq 'weather' && $ereignis !~ m{weather}x );

        deleteSingleRegIntTimer( $ereignis, $hash );
        
        if ( defined $hash->{TW}{$ereignis}{TIME} && ($hash->{TW}{$ereignis}{TIME} > $now || $firstrun) ) { # had been > 0
            setRegIntTimer( $ereignis, $hash->{TW}{$ereignis}{TIME},
                \&Twilight_fireEvent, $hash, 0 );
        }
    }
    

# ------------------------------------------------------------------------------
    return 1;
}
################################################################################
sub Twilight_fireEvent {
    my $fnHash = shift // return;
    
    my ($hash, $modifier) = ($fnHash->{HASH}, $fnHash->{MODIFIER});

    return if ( !defined $hash );
    
    my $name = $hash->{NAME};

    my $event = $modifier;
    my $myHash =$hash->{TW}{$modifier};
    my $deg   = $myHash->{DEG};
    my $light = $myHash->{LIGHT};
    my $state = $myHash->{STATE};
    my $swip  = $myHash->{SWIP};
    $swip = 0 if time - $hash->{helper}{'.startuptime'} < 60;
    
    my $eventTime = $myHash->{TIME};
    my $nextEvent = $myHash->{NAMENEXT};

    my $delta = int( $eventTime - time );
    my $oldState = ReadingsVal( $name, 'state', '0' );

    my $nextEventTime =
      ( $hash->{TW}{$nextEvent}{TIME} > 0 )
      ? FmtTime( $hash->{TW}{$nextEvent}{TIME} )
      : 'undefined';

    my $doTrigger = !( defined( $hash->{LOCAL} ) )
      && ( abs($delta) < 6 || $swip && $state gt $oldState );

    Log3(
        $hash, 4,
        sprintf( "[$hash->{NAME}] %-10s %-19s  ",
            $event, FmtDateTime($eventTime) )
          . sprintf( "(%2d/$light/%+5.1f°/$doTrigger)   ", $state, $deg )
          . sprintf( "===> %-10s %-19s  ", $nextEvent, $nextEventTime )
    );
    deleteSingleRegIntTimer($modifier, $hash, 1);

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'state',         $state );
    readingsBulkUpdate( $hash, 'light',         $light );
    readingsBulkUpdate( $hash, 'horizon',       $deg );
    readingsBulkUpdate( $hash, 'aktEvent',      $event );
    readingsBulkUpdate( $hash, 'nextEvent',     $nextEvent );
    readingsBulkUpdate( $hash, 'nextEventTime', $nextEventTime );

    return readingsEndUpdate( $hash, $doTrigger );

}

################################################################################
sub Twilight_Midnight {
    my $fnHash = shift // return;
    my $firstrun = shift // 0;
    
    my ($hash, $modifier) = ($fnHash->{HASH}, $fnHash->{MODIFIER});
    
    return if !defined $hash;
    
    if (!defined $hash->{helper}{extWeather}{Device}) {
        Twilight_TwilightTimes( $hash, 'mid', $firstrun);
        Twilight_sunpos({HASH => $hash});
    } else {
        Twilight_HandleWeatherData( $hash, 0);
        Twilight_TwilightTimes( $hash, 'mid', $firstrun); 
    }
    my $now = time;
    my $midnight = $now - secondsSinceMidnight( $now ) + DAYSECONDS + 1;
    my $daylightsavingdelta = (localtime ( $now - 2 * HOURSECONDS ) )[2] - ( localtime( $now + 22 * HOURSECONDS ) )[2]; 
    $midnight -= 19 * HOURSECONDS if $daylightsavingdelta == 1 && (localtime)[2] < 2;
    $midnight -= 20 * HOURSECONDS if $daylightsavingdelta == -1 && (localtime)[2] < 3;
    
    return resetRegIntTimer( 'Midnight', $midnight, \&Twilight_Midnight, $hash, 0 );

}



################################################################################
sub Twilight_sunposTimerSet {
    my $hash = shift // return;

    return resetRegIntTimer( 'sunpos', time + $hash->{SUNPOS_OFFSET}, \&Twilight_sunpos, $hash, 0 );
}

################################################################################
sub Twilight_getWeatherHorizon {
    my $hash        = shift;
    my $result      = shift // return;
    my $setInternal = shift // 1;
    
    return $hash->{INDOOR_HORIZON} if !looks_like_number($result) || $result < 0 || $result > 100;
    my $weather_horizon = $result / 12.5; 
    $hash->{WEATHER_CORRECTION} = $weather_horizon if $setInternal;
    $weather_horizon += $hash->{INDOOR_HORIZON};
    #my $doy = strftime("%j",localtime);
    my $doy = (localtime)[7]+1;
    my $declination =  0.4095*sin(0.016906*($doy-80.086));
    
    $weather_horizon = min( 89-$hash->{helper}{'.LATITUDE'}+$declination, $weather_horizon );
    $hash->{WEATHER_HORIZON}    = $weather_horizon if $setInternal;

    return $weather_horizon;
}

################################################################################
sub Twilight_sunpos {
    my $fnHash = shift // return;

    my ($hash, $modifier) = ($fnHash->{HASH}, $fnHash->{MODIFIER});

    #my $hash = Twilight_GetHashIndirekt( $fnHash, ( caller(0) )[3] );
    return if ( !defined($hash) );

    my $hashName = $hash->{NAME};
    return if(IsDisabled($hashName));

    my (
        $dSeconds, $dMinutes, $dHours, $iDay, $iMonth,
        $iYear,    $wday,     $yday,   $isdst
    ) = gmtime(time);
    $iMonth++;
    $iYear += 100;

    my $dLongitude = $hash->{helper}{'.LONGITUDE'};
    my $dLatitude  = $hash->{helper}{'.LATITUDE'};
    Log3( $hash, 5,
        "Compute sunpos for latitude $dLatitude , longitude $dLongitude" )
      if $dHours == 0 && $dMinutes <= 6;

    my $pi                = 3.14159265358979323846;
    my $twopi             = ( 2 * $pi );
    my $rad               = ( $pi / 180 );
    my $dEarthMeanRadius  = 6371.01;                  # In km
    my $dAstronomicalUnit = 149597890;                # In km

    # Calculate difference in days between the current Julian Day
    # and JD 2451545.0, which is noon 1 January 2000 Universal Time

    # Calculate time of the day in UT decimal hours
    my $dDecimalHours = $dHours + $dMinutes / 60.0 + $dSeconds / 3600.0;

    # Calculate current Julian Day
    my $iYfrom2000 = $iYear;                        #expects now as YY ;
    my $iA         = ( 14 - ($iMonth) ) / 12;
    my $iM         = ($iMonth) + 12 * $iA - 3;
    my $liAux3     = ( 153 * $iM + 2 ) / 5;
    my $liAux4     = 365 * ( $iYfrom2000 - $iA );
    my $liAux5     = ( $iYfrom2000 - $iA ) / 4;
    my $dElapsedJulianDays =
      ( $iDay + $liAux3 + $liAux4 + $liAux5 + 59 ) + -0.5 +
      $dDecimalHours / 24.0;

    # Calculate ecliptic coordinates (ecliptic longitude and obliquity of the
    # ecliptic in radians but without limiting the angle to be less than 2*Pi
    # (i.e., the result may be greater than 2*Pi)

    my $dOmega = 2.1429 - 0.0010394594 * $dElapsedJulianDays;
    my $dMeanLongitude =
      4.8950630 + 0.017202791698 * $dElapsedJulianDays;    # Radians
    my $dMeanAnomaly = 6.2400600 + 0.0172019699 * $dElapsedJulianDays;
    my $dEclipticLongitude =
      $dMeanLongitude +
      0.03341607 * sin($dMeanAnomaly) +
      0.00034894 * sin( 2 * $dMeanAnomaly ) - 0.0001134 -
      0.0000203 * sin($dOmega);
    my $dEclipticObliquity =
      0.4090928 - 6.2140e-9 * $dElapsedJulianDays + 0.0000396 * cos($dOmega);

    # Calculate celestial coordinates ( right ascension and declination ) in radians
    # but without limiting the angle to be less than 2*Pi (i.e., the result may be
    # greater than 2*Pi)

    my $dSin_EclipticLongitude = sin($dEclipticLongitude);
    my $dY1             = cos($dEclipticObliquity) * $dSin_EclipticLongitude;
    my $dX1             = cos($dEclipticLongitude);
    my $dRightAscension = atan2( $dY1, $dX1 );
    if ( $dRightAscension < 0.0 ) {
        $dRightAscension = $dRightAscension + $twopi;
    }
    my $dDeclination =
      asin( sin($dEclipticObliquity) * $dSin_EclipticLongitude );

    # Calculate local coordinates ( azimuth and zenith angle ) in degrees
    my $dGreenwichMeanSiderealTime =
      6.6974243242 + 0.0657098283 * $dElapsedJulianDays + $dDecimalHours;

    my $dLocalMeanSiderealTime =
      ( $dGreenwichMeanSiderealTime * 15 + $dLongitude ) * $rad;
    my $dHourAngle         = $dLocalMeanSiderealTime - $dRightAscension;
    my $dLatitudeInRadians = $dLatitude * $rad;
    my $dCos_Latitude      = cos($dLatitudeInRadians);
    my $dSin_Latitude      = sin($dLatitudeInRadians);
    my $dCos_HourAngle     = cos($dHourAngle);
    my $dZenithAngle       = (
        acos(
            $dCos_Latitude * $dCos_HourAngle * cos($dDeclination) +
              sin($dDeclination) * $dSin_Latitude
        )
    );
    my $dY = -sin($dHourAngle);
    my $dX =
      tan($dDeclination) * $dCos_Latitude - $dSin_Latitude * $dCos_HourAngle;
    my $dAzimuth = atan2( $dY, $dX );
    if ( $dAzimuth < 0.0 ) { $dAzimuth = $dAzimuth + $twopi }
    $dAzimuth = $dAzimuth / $rad;

    # Parallax Correction
    my $dParallax =
      ( $dEarthMeanRadius / $dAstronomicalUnit ) * sin($dZenithAngle);
    $dZenithAngle = ( $dZenithAngle + $dParallax ) / $rad;
    my $dElevation = 90 - $dZenithAngle;

    my $twilight = int( ( $dElevation + 12.0 ) / 18.0 * 1000 ) / 10;
    $twilight = 100 if ( $twilight > 100 );
    $twilight = 0   if ( $twilight < 0 );

    my $twilight_weather;

    if (!defined $hash->{helper}{extWeather}{Device}) {
        $twilight_weather =
          int( ( $dElevation - $hash->{WEATHER_HORIZON} + 12.0 ) / 18.0 * 1000 )
          / 10;
        Log3( $hash, 5, "[$hashName] Original weather readings" );
    } else {
        my $extWeatherHorizont = ReadingsNum($hashName,'cloudCover' , -1 );
        if ( $extWeatherHorizont >= 0 ) {
            $extWeatherHorizont = min (100, $extWeatherHorizont);
            Log3( $hash, 5,
                    "[$hashName] Using cloudCover value $extWeatherHorizont" );
            $twilight_weather = $twilight -
              int( 0.007 * ( $extWeatherHorizont**2 ) )
              ;    ## SCM: 100% clouds => 30% light (rough estimation)
        } 
        else {
            $twilight_weather =
              int( ( $dElevation - $hash->{WEATHER_HORIZON} + 12.0 ) / 18.0 *
                  1000 ) / 10;
            Log3( $hash, 3,
                    "[$hashName] No useable cloudCover value available: ${extWeatherHorizont}, taking existant weather horizon." );
        }
    }

    $twilight_weather =
      min( 100, max( $twilight_weather, 0 ) );

    #  set readings
    $dAzimuth   = int( 100 * $dAzimuth ) / 100;
    $dElevation = int( 100 * $dElevation ) / 100;

    my $compassPoint = Twilight_CompassPoint($dAzimuth);

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'azimuth',          $dAzimuth );
    readingsBulkUpdate( $hash, 'elevation',        $dElevation );
    readingsBulkUpdate( $hash, 'twilight',         $twilight );
    readingsBulkUpdate( $hash, 'twilight_weather', $twilight_weather );
    readingsBulkUpdate( $hash, 'compasspoint',     $compassPoint );
    readingsEndUpdate( $hash, defined( $hash->{LOCAL} ? 0 : 1 ) );

    Twilight_sunposTimerSet($hash);

    return;
}
################################################################################
sub Twilight_CompassPoint {
    my $azimuth = shift // return;

    return 'unknown' if !looks_like_number($azimuth) || $azimuth < 0;
    return 'north' if $azimuth < 22.5;
    return 'north-northeast' if $azimuth < 45;
    return 'northeast'       if $azimuth < 67.5;
    return 'east-northeast'  if $azimuth < 90;
    return 'east'            if $azimuth < 112.5;
    return 'east-southeast'  if $azimuth < 135;
    return 'southeast'       if $azimuth < 157.5;
    return 'south-southeast' if $azimuth < 180;
    return 'south'           if $azimuth < 202.5;
    return 'south-southwest' if $azimuth < 225;
    return 'southwest'       if $azimuth < 247.5;
    return 'west-southwest'  if $azimuth < 270;
    return 'west'            if $azimuth < 292.5;
    return 'west-northwest'  if $azimuth < 315;
    return 'northwest'       if $azimuth < 337.5;
    return 'north-northwest' if $azimuth <= 361;
    return 'unknown';
}

sub twilight {
    my ( $twilight, $reading, $min, $max, $cloudCover ) = @_;
    my $hash = $defs{$twilight};
    return "unknown device $twilight" if !defined $hash;
    
    my $t;
    
    $t = hms2h( ReadingsVal( $twilight, $reading, 0 ) ) if $reading ne 'sr_tomorrow' and $reading ne 'ss_tomorrow';

    if ($reading eq 'sr_tomorrow' or $reading eq 'ss_tomorrow') {
        my $wh = Twilight_getWeatherHorizon( $hash, $cloudCover // 50, 0);
        my ($sr, $ss) = Twilight_calc( $hash, $wh, '7', time + DAYSECONDS );
        $t = hms2h( FmtTime( $reading eq 'sr_tomorrow' ? $sr : $ss ) );
    }

    $t = hms2h($min) if ( defined($min) && ( hms2h($min) > $t ) );
    $t = hms2h($max) if ( defined($max) && ( hms2h($max) < $t ) );

    return h2hms_fmt($t);
}

###########
# Dispatch functions

sub getTwilightHours {
    my $hash    = shift // return;
    my $hour    = ( localtime )[2];
    my $sr_hour = defined $hash->{TW}{sr_weather}{TIME} ? ( localtime( $hash->{TW}{sr_weather}{TIME} ))[2] : 7;
    my $ss_hour = defined $hash->{TW}{ss_weather}{TIME} ? ( localtime( $hash->{TW}{ss_weather}{TIME} ))[2] : 18; 
    return $hour,$sr_hour,$ss_hour;
}

sub getwTYPE_Weather {
    my $hash  = shift // return;
    
    my @ret;
    my $extDev  = $hash->{helper}{extWeather}{Device};
    my ($hour, $sr_hour, $ss_hour) = getTwilightHours($hash); 
    
    my $rAge = int(ReadingsAge($extDev,'cloudCover',0)/3600);
    
    $ret[0] = $rAge < 24 ? ReadingsNum($extDev,'cloudCover',0) : 50;
    Log3( $hash, 5, "[$hash->{NAME}] function is called, cc is $ret[0], hours sr: $sr_hour, ss: $ss_hour" );
    
    my $lastestFcHourVal = -1;
    
    for (my $i=28; $i>-1; $i--) {
      $lastestFcHourVal = ReadingsNum($extDev,"hfc${i}_cloudCover",-1);
      last if $lastestFcHourVal > -1;
    }
    
    $lastestFcHourVal = 0 if $lastestFcHourVal == -1;
    
    my $hfc_sr = max( 0 , $sr_hour - $hour ) + $rAge; #remark: needs some additionals logic for midnight updates! (ReadingsAge()?)
    my $hfc_ss = max( 0 , $ss_hour - $hour ) + $rAge;
    
    $ret[1] = $hfc_sr && $rAge < 24 ? ReadingsNum($extDev,"hfc${hfc_sr}_cloudCover",$lastestFcHourVal) : $ret[0];
    $ret[2] = $hfc_ss && $rAge < 24 ? ReadingsNum($extDev,"hfc${hfc_ss}_cloudCover",$lastestFcHourVal) : $ret[0];

    return @ret;
}


sub getwTYPE_PROPLANTA {
    my $hash   = shift // return;
    
    my $extDev = $hash->{helper}{extWeather}{Device};
    my @hour  = getTwilightHours($hash); 
    
    my $fc_day0 = secondsSinceMidnight( time ) > 60 ? 0 : 1;
    my $fc_day1 = $fc_day0 + 1;
    
    my @ret;
    for (my $i = 0; $i < 3 ; $i++) {
        $hour[$i] <  4 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud03",0) : (
        $hour[$i] <  7 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud06",0) : (
        $hour[$i] < 10 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud09",0) : (
        $hour[$i] < 13 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud12",0) : (
        $hour[$i] < 16 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud15",0) : (
        $hour[$i] < 19 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud18",0) : (
        $hour[$i] < 22 ? $ret[$i] = ReadingsNum($extDev,"fc${fc_day0}_cloud21",0) :
        $ret[$i] = ReadingsNum($extDev,"fc${fc_day1}_cloud00",0)))))));
    }
    #Log3( $hash, 4, "[$hash->{NAME}] Proplanta data: hours $hour[0]-$hour[1]-$hour[2], fc_day0 $fc_day0, data $ret[0]-$ret[1]-$ret[2]");
    return @ret;
}
1;

__END__


=pod
=encoding utf8
=item helper
=item summary generate twilight & sun related events; check alternative Astro.
=item summary_DE liefert Dämmerungs Sonnen basierte Events. Alternative: Astro
=begin html

<a id="Twilight"></a>
<h3>Twilight</h3>
<ul>
  <br>
  <a id="Twilight-general"></a>
  <b>General Remarks</b><br>
  This module profited much from the use of the yahoo weather API. Unfortunately, this service is no longer available, so Twilight functionality is very limited nowerdays. To some extend, the use of <a href="#Twilight-attr-useExtWeather">useExtWeather</a> may compensate to dect cloudy skys. If you just want to have astronomical data available, consider using Astro instead.<br><br>
  <a id="Twilight-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Twilight [&lt;latitude&gt; &lt;longitude&gt;] [&lt;indoor_horizon&gt; [&lt;weatherDevice[:Reading]&gt;]]</code><br>
    <br>
    Defines a virtual device for Twilight calculations <br><br>

  <b>latitude, longitude</b>
  <br>
    The parameters <b>latitude</b> and <b>longitude</b> are decimal numbers which give the position on earth for which the twilight states shall be calculated. They are optional, but in case if set, you have to set both of them. If not set, global values will be used instead (global itself defaults to Frankfurt/Main).
    <br>
    <br>
  <b>indoor_horizon</b>
  <br>
    The parameter <b>indoor_horizon</b> gives a virtual horizon, that shall be used for calculation of indoor twilight. Minimal value -6 means indoor values are the same like civil values.
    indoor_horizon 0 means indoor values are the same as real values. indoor_horizon > 0 means earlier indoor sunset resp. later indoor sunrise.
    <br>
    Defaults to 3 if not set.
    <br><br>
  <b>weatherDevice:Reading</b>
  <br>
    The parameter <b>weatherDevice:Reading</b> can be used to point to a device providing cloud coverage information to calculate <b>twilight_weather</b>.<br/>
    The reading used shoud be in the range of 0 to 100 like the reading <b>c_clouds</b> in an <b><a href="#openweathermap">openweathermap</a></b> device, where 0 is clear sky and 100 are overcast clouds.<br/> Example: MyWeather:cloudCover
    <br><br>
    NOTE 1: using useExtWeather attribute may override settings in DEF.
    <br>
    <br>
    NOTE 2: If weatherDevice-type is known, <Reading> is optional (atm only "Weather" or "PROPLANTA" type devices are supported).
    <br>
    A Twilight device periodically calculates the times of different twilight phases throughout the day.
    It calculates a virtual "light" element, that gives an indicator about the amount of the current daylight.
    Besides the location on earth it is influenced by a so called "indoor horizon" (e.g. if there are high buildings, mountains) as well as by weather conditions. Very bad weather conditions lead to a reduced daylight for nearly the whole day.
    The light calculated spans between 0 and 6, where the values mean the following:
 <br><br>
  <b>light</b>
  <br>
    <code>0 - total night, sun is at least -18 degree below horizon</code><br>
    <code>1 - astronomical twilight, sun is between -12 and -18 degree below horizon</code><br>
    <code>2 - nautical twilight, sun is between -6 and -12 degree below horizon</code><br>
    <code>3 - civil twilight, sun is between 0 and -6 degree below horizon</code><br>
    <code>4 - indoor twilight, sun is between the indoor_horizon and 0 degree below horizon (not used if indoor_horizon=0)</code><br>
    <code>5 - weather twilight, sun is between indoor_horizon and a virtual weather horizon (the weather horizon depends on weather conditions (optional)</code><br>
    <code>6 - maximum daylight</code><br>
    <br>
    <b>state</b> will reflect the current virtual "day phase" (0 = after midnight, 1 = sr_astro has passed, ...12 = ss_astro has passed)<br>
    
 <b>Azimut, Elevation, Twilight</b>
 <br>
   The module calculates additionally the <b>azimuth</b> and the <b>elevation</b> of the sun. The values can be used to control a roller shutter.
   <br><br>
   As a new (twi)light value the reading <b>Twilight</b> ist added. It is derived from the elevation of the sun with the formula: (Elevation+12)/18 * 100). The value allows a more detailed
   control of any lamp during the sunrise/sunset phase. The value ist betwenn 0% and 100% when the elevation is between -12&deg; and 6&deg;.
   <br><br>
   You must know, that depending on the latitude, the sun will not reach any elevation. In june/july the sun never falls in middle europe
   below -18&deg;. In more northern countries(norway ...) the sun may not go below 0&deg;.
   <br><br>
   Any control depending on the value of Twilight must
   consider these aspects.
     <br><br>

    Examples:
    <pre>
      define myTwilight Twilight 49.962529  10.324845 3 localWeather:clouds
    </pre>
    <pre>
      define myTwilight2 Twilight 4 localWeather
    </pre>
  </ul>
  <br>

  <a id="Twilight-set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>


  <a id="Twilight-get"></a>
  <b>Get</b>
  <ul>

    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>
    <table>
    <tr><td><b>light</b></td><td>the current virtual daylight value</td></tr>
    <tr><td><b>nextEvent</b></td><td>the name of the next event</td></tr>
    <tr><td><b>nextEventTime</b></td><td>the time when the next event will probably happen (during light phase 5 and 6 this is updated when weather conditions change</td></tr>
    <tr><td><b>sr_astro</b></td><td>time of astronomical sunrise</td></tr>
    <tr><td><b>sr_naut</b></td><td>time of nautical sunrise</td></tr>
    <tr><td><b>sr_civil</b></td><td>time of civil sunrise</td></tr>
    <tr><td><b>sr</b></td><td>time of sunrise</td></tr>
    <tr><td><b>sr_indoor</b></td><td>time of indoor sunrise</td></tr>
    <tr><td><b>sr_weather</b></td><td>time of weather sunrise</td></tr>
    <tr><td><b>ss_weather</b></td><td>time of weather sunset</td></tr>
    <tr><td><b>ss_indoor</b></td><td>time of indoor sunset</td></tr>
    <tr><td><b>ss</b></td><td>time of sunset</td></tr>
    <tr><td><b>ss_civil</b></td><td>time of civil sunset</td></tr>
    <tr><td><b>ss_nautic</b></td><td>time of nautic sunset</td></tr>
    <tr><td><b>ss_astro</b></td><td>time of astro sunset</td></tr>
    <tr><td><b>azimuth</b></td><td>the current azimuth of the sun 0&deg; ist north 180&deg; is south</td></tr>
    <tr><td><b>compasspoint</b></td><td>a textual representation of the compass point</td></tr>
    <tr><td><b>elevation</b></td><td>the elevaltion of the sun</td></tr>
    <tr><td><b>twilight</b></td><td>a percetal value of a new (twi)light value: (elevation+12)/18 * 100) </td></tr>
    <tr><td><b>twilight_weather</b></td><td>a percetal value of a new (twi)light value: (elevation-WEATHER_HORIZON+12)/18 * 100). So if there is weather, it
                                     is always a little bit darker than by fair weather</td></tr>
    <tr><td><b>condition</b></td><td>the yahoo condition weather code</td></tr>
    <tr><td><b>condition_txt</b></td><td>the yahoo condition weather code as textual representation</td></tr>
    <tr><td><b>horizon</b></td><td>value auf the actual horizon 0&deg;, -6&deg;, -12&deg;, -18&deg;</td></tr>
    </table>

  </ul>
  <br>

  <a id="Twilight-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Twilight-attr-useExtWeather"></a>
    <li><b>useExtWeather &lt;device&gt;[:&lt;reading&gt;] [&lt;usercode&gt;]</b></li>
    use data from other devices to calculate <b>twilight_weather</b>.<br/>
    The reading used shoud be in the range of 0 to 100 like the reading <b>c_clouds</b>    in an <b><a href="#openweathermap">openweathermap</a></b> device, where 0 is clear sky and 100 are overcast clouds.<br/>
    Note: Atm. additional weather effects like heavy rain or thunderstorms are neglegted for the calculation of the <b>twilight_weather</b> reading.<br/>
    
    By adding <b>usercode</b>, (Note: experimental feature! May work or not or lead to crashes etc....) you may get more realistic results for sr_weather and ss_weather calculation. Just return - besides the actual cloudCover reading value additional predicted values for corresponding indoor times, seperated by ":"<br>
    <pre>
      Value_A:Value_B:Value_C
    </pre>
    Value_A representing the actual cloudCover value, Value_B at sr_indoor and Value_C at ss_indoor (all values in 0-100 format).<br>
    Example:
    <pre>
      attr myTwilight useExtWeather MyWeather:cloudCover { myCloudCoverAnalysis("MyWeather") }
    </pre>
    with corresponding code for myUtils:
    <pre>
    sub myCloudCoverAnalysis {
        my $weatherName = shift;
        my $ret = ReadingsVal($weatherName,"cloudCover",50);
        $ret .= ":".ReadingsVal($weatherName,"cloudCover_morning",55);
        $ret .= ":".ReadingsVal($weatherName,"cloudCover_evening",65);
        return $ret; 
    }
  </ul>
  <br>

  <a id="Twilight-func"></a>
  <b>Functions</b>
  <ul>
     <li><b>twilight</b>(<b>$twilight</b>, <b>$reading</b>, <b>$min</b>, <b>$max</b>)</li> - implements a routine to compute the twilighttimes like sunrise with min max values.<br><br>
     <table>
     <tr><td><b>$twilight</b></td><td>name of the twilight instance</td></tr>
     <tr><td><b>$reading</b></td><td>name of the reading to use example: ss_astro, ss_weather ...</td></tr>
     <tr><td><b>$min</b></td><td>parameter min time - optional</td></tr>
     <tr><td><b>$max</b></td><td>parameter max time - optional</td></tr>
     </table>
  </ul>
  <br>
Example:
<pre>
    define BlindDown at *{twilight("myTwilight","sr_indoor","7:30","9:00")} set xxxx position 100
    # xxxx is a defined blind
</pre>

</ul>

=end html

=begin html_DE

<a id="Twilight"></a>
<h3>Twilight</h3>
<ul>
  <b>Allgemeine Hinweise</b><br>
  Dieses Modul nutzte früher Daten von der Yahoo Wetter API. Diese ist leider nicht mehr verfügbar, daher ist die heutige Funktionalität deutlich eingeschränkt. Dies kann zu einem gewissen Grad kompensiert werden, indem man im define oder das Attribut <a href="#Twilightattr">useExtWeather</a> ein externes Wetter-Device setzt, um Bedeckungsgrade mit Wolken zu berücksichtigen. Falls Sie nur Astronomische Daten benötigen, wäre Astro hierfür eine genauere Alternative.<br><br>

  <br>

  <a id="Twilight-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Twilight [&lt;latitude&gt; &lt;longitude&gt;] [&lt;indoor_horizon&gt; [&lt;weatherDevice[:Reading]&gt;]]</code><br>
    <br>
    Erstellt ein virtuelles Device f&uuml;r die D&auml;mmerungsberechnung (Zwielicht)<br><br>

  <b>latitude, longitude (geografische L&auml;nge & Breite)</b>
  <br>
    Die Parameter <b>latitude</b> und <b>longitude</b> sind Dezimalzahlen welche die Position auf der Erde bestimmen, für welche der Dämmerungs-Status berechnet werden soll. Sie sind optional, wenn nicht vorhanden, werden die Angaben in global berücksichtigt, bzw. ohne weitere Angaben die Daten von Frankfurt/Main. Möchte man andere als die in global gesetzten Werte setzen, müssen zwingend beide Werte angegeben werden.
    <br><br>
  <b>indoor_horizon</b>
  <br>
     Der Parameter <b>indoor_horizon</b> bestimmt einen virtuellen Horizont, der für die Berechnung der Dämmerung innerhalb von Räumen genutzt werden kann. Minimalwert ist -6 (ergibt gleichen Wert wie Zivile Dämmerung). Bei 0 fallen indoor- und realer Dämmerungswert zusammen. Werte größer 0 ergeben frühere Werte für den Abend bzw. spätere für den Morgen.
    <br><br>
  <b>weatherDevice:Reading</b>
  <br>
    Der Parameter <b>weatherDevice:Reading</b> kann genutzt werden, um &uumlber ein anderes Device an den Bedeckungsgrad f&uumlr die Berechnung von <b>twilight_weather</b> bereitzustellen.<br/>
    Das Reading sollte sich im Intervall zwischen 0 und 100 bewegen, z.B. das Reading <b>c_clouds</b> in einem <b><a href="#openweathermap">openweathermap</a></b> device, bei dem 0 heiteren und 100 bedeckten Himmel bedeuten.
    <br>Beispiel: MyWeather:cloudCover
    <br><br>
    Hinweis 1: Eventuelle Angaben im useExtWeather-Attribut &uumlberschreiben die Angaben im define.
    <br>
    Hinweis 2: Bei bekannten Wetter-Device-Typen (im Moment ausschließlich: Weather oder PROPLANTA) ist die Angabe des Readings optional.
    <br>
    <br>
    Ein Twilight-Device berechnet periodisch die D&auml;mmerungszeiten und -phasen w&auml;hrend des Tages.
    Es berechnet ein virtuelles "Licht"-Element das einen Indikator f&uuml;r die momentane Tageslichtmenge ist.
    Neben der Position auf der Erde wird es vom sog. "indoor horizon" (Beispielsweise hohe Gebäude oder Berge)
    und dem Wetter beeinflusst. Schlechtes Wetter f&uuml;hrt zu einer Reduzierung des Tageslichts f&uuml;r den ganzen Tag.
    Das berechnete Licht liegt zwischen 0 und 6 wobei die Werte folgendes bedeuten:<br><br>
  <b>light</b>
  <br>
    <code>0 - Totale Nacht, die Sonne ist mind. -18 Grad hinter dem Horizont</code><br>
    <code>1 - Astronomische D&auml;mmerung, die Sonne ist zw. -12 und -18 Grad hinter dem Horizont</code><br>
    <code>2 - Nautische D&auml;mmerung, die Sonne ist zw. -6 and -12 Grad hinter dem Horizont</code><br>
    <code>3 - Zivile/B&uuml;rgerliche D&auml;mmerung, die Sonne ist zw. 0 and -6 hinter dem Horizont</code><br>
    <code>4 - "indoor twilight", die Sonne ist zwischen dem Wert indoor_horizon und 0 Grad hinter dem Horizont (wird nicht verwendet wenn indoor_horizon=0)</code><br>
    <code>5 - Wetterbedingte D&auml;mmerung, die Sonne ist zwischen indoor_horizon und einem virtuellen Wetter-Horizonz (der Wetter-Horizont ist Wetterabh&auml;ngig (optional)</code><br>
    <code>6 - Maximales Tageslicht</code><br>
    <br>
    <b>state</b> entspricht der aktuellen virtuellen "Tages-Phase" (0 = nach Mitternacht, 1 = nach sr_astro, ...12 = nach ss_astro)<br>
    
 <b>Azimut, Elevation, Twilight (Seitenwinkel, Höhenwinkel, D&auml;mmerung)</b>
 <br>
   Das Modul berechnet zus&auml;tzlich Azimuth und Elevation der Sonne. Diese Werte k&ouml;nnen zur Rolladensteuerung verwendet werden.<br><br>

Das Reading <b>Twilight</b> wird als neuer "(twi)light" Wert hinzugef&uuml;gt. Er wird aus der Elevation der Sonne mit folgender Formel abgeleitet: (Elevation+12)/18 * 100). Das erlaubt eine detailliertere Kontrolle der Lampen w&auml;hrend Sonnenauf - und untergang. Dieser Wert ist zwischen 0% und 100% wenn die Elevation zwischen -12&deg; und 6&deg;

   <br><br>
Wissenswert dazu ist, dass die Sonne, abh&auml;gnig vom Breitengrad, bestimmte Elevationen nicht erreicht. Im Juni und Juli liegt die Sonne in Mitteleuropa nie unter -18&deg;. In n&ouml;rdlicheren Gebieten (Norwegen, ...) kommt die Sonne beispielsweise nicht &uuml;ber 0&deg.
   <br><br>
   All diese Aspekte m&uuml;ssen ber&uuml;cksichtigt werden bei Schaltungen die auf Twilight basieren.
     <br><br>

    Beispiel:
    <pre>
      define myTwilight Twilight 49.962529 10.324845 4.5 MeinWetter:cloudCover
    </pre>
  </ul>
  <br>

  <a id="Twilight-set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>


  <a id="Twilight-get"></a>
  <b>Get</b>
  <ul>

    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>
    <table>
    <tr><td><b>light</b></td><td>der aktuelle virtuelle Tageslicht-Wert</td></tr>
    <tr><td><b>nextEvent</b></td><td>Name des n&auml;chsten Events</td></tr>
    <tr><td><b>nextEventTime</b></td><td>die Zeit wann das n&auml;chste Event wahrscheinlich passieren wird; (w&auml;hrend Lichtphase 5 und 6 wird dieser Wert aktualisiert wenn sich das Wetter &auml;ndert)</td></tr>
    <tr><td><b>sr_astro</b></td><td>Zeit des astronomitschen Sonnenaufgangs</td></tr>
    <tr><td><b>sr_naut</b></td><td>Zeit des nautischen Sonnenaufgangs</td></tr>
    <tr><td><b>sr_civil</b></td><td>Zeit des zivilen/b&uuml;rgerlichen Sonnenaufgangs</td></tr>
    <tr><td><b>sr</b></td><td>Zeit des Sonnenaufgangs</td></tr>
    <tr><td><b>sr_indoor</b></td><td>Zeit des "indoor" Sonnenaufgangs</td></tr>
    <tr><td><b>sr_weather</b></td><td>"Zeit" des wetterabhängigen Sonnenaufgangs</td></tr>
    <tr><td><b>ss_weather</b></td><td>"Zeit" des wetterabhängigen Sonnenuntergangs</td></tr>
    <tr><td><b>ss_indoor</b></td><td>Zeit des "indoor" Sonnenuntergangs</td></tr>
    <tr><td><b>ss</b></td><td>Zeit des Sonnenuntergangs</td></tr>
    <tr><td><b>ss_civil</b></td><td>Zeit des zivilen/b&uuml;rgerlichen Sonnenuntergangs</td></tr>
    <tr><td><b>ss_nautic</b></td><td>Zeit des nautischen Sonnenuntergangs</td></tr>
    <tr><td><b>ss_astro</b></td><td>Zeit des astro. Sonnenuntergangs</td></tr>
    <tr><td><b>azimuth</b></td><td>aktueller Azimuth der Sonne. 0&deg; ist Norden 180&deg; ist S&uuml;den</td></tr>
    <tr><td><b>compasspoint</b></td><td>Ein Wortwert des Kompass-Werts</td></tr>
    <tr><td><b>elevation</b></td><td>the elevaltion of the sun</td></tr>
    <tr><td><b>twilight</b></td><td>Prozentualer Wert eines neuen "(twi)light" Wertes: (elevation+12)/18 * 100) </td></tr>
    <tr><td><b>twilight_weather</b></td><td>Prozentualer Wert eines neuen "(twi)light" Wertes: (elevation-WEATHER_HORIZON+12)/18 * 100). Wenn ein Wetterwert vorhanden ist, ist es immer etwas dunkler als bei klarem Wetter.</td></tr>
    <tr><td><b>condition</b></td><td>Yahoo! Wetter code</td></tr>
    <tr><td><b>condition_txt</b></td><td>Yahoo! Wetter code als Text</td></tr>
    <tr><td><b>horizon</b></td><td>Wert des aktuellen Horizont 0&deg;, -6&deg;, -12&deg;, -18&deg;</td></tr>
    </table>

  </ul>
  <br>

  <a id="Twilight-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Twilight-attr-useExtWeather"></a>
    <li><b>useExtWeather &lt;device&gt;:&lt;reading&gt; [&lt;usercode&gt;]</b>
    Nutzt Daten von einem anderen Device um <b>twilight_weather</b> zu berechnen.<br/>
    Das Reading sollte sich im Intervall zwischen 0 und 100 bewegen, z.B. das Reading <b>c_clouds</b> in einem<b> <a href="#openweathermap">openweathermap</a></b> device, bei dem 0 heiteren und 100 bedeckten Himmel bedeuten.
    Wettereffekte wie Starkregen oder Gewitter k&umlnnen derzeit f&uumlr die Berechnung von <b>twilight_weather</b> nicht mehr herangezogen werden.<br>
    Durch Angabe von <b>usercode</b> (Achtung: experimentelles feature! Kann auch schiefgehen...) kann die Berechnung der sr_weather und ss_weather-Zeiten verbessert werden, indem die zum jeweils zugehörigen indoor-Zeitpunkt gehörenden Vorhersage-Werte zurückgegeben werden. Das Rückgabe-Format der Funktion muss sein:<br>
    <pre>
      Wert_A:Wert_B:Wert_C
    </pre>
    wobei Wert_A der aktuelle cloudCover-Wert ist, Wert_B der zum Zeitpunt für sr_indoor und Wert_C für ss_indoor (alle Werte nummerisch im Bereich 0-100).<br>
    Beispiel:
    <pre>
      attr myTwilight useExtWeather MeinWetter:cloudCover { myCloudCoverAnalysis("MeinWetter") }
    </pre>
    mit folgendem (wenig sinnvollen) Code für myUtils:
    <pre>
    sub myCloudCoverAnalysis {
        my $weatherName = shift;
        my $ret = ReadingsVal($weatherName,"cloudCover",50);
        $ret .= ":".ReadingsVal($weatherName,"cloudCover_morning",55);
        $ret .= ":".ReadingsVal($weatherName,"cloudCover_evening",65);
        return $ret; 
    }
    </li>
  </ul>
  <br>

  <a id="Twilight-func"></a>
  <b>Functions</b>
  <ul>
     <li><b>twilight</b>(<b>$twilight</b>, <b>$reading</b>, <b>$min</b>, <b>$max</b>)</li> - implementiert eine Routine um die D&auml;mmerungszeiten wie Sonnenaufgang mit min und max Werten zu berechnen.<br><br>
     <table>
     <tr><td><b>$twilight</b></td><td>Name der twiligh Instanz</td></tr>
     <tr><td><b>$reading</b></td><td>Name des zu verwendenden Readings. Beispiel: ss_astro, ss_weather ...</td></tr>
     <tr><td><b>$min</b></td><td>Parameter min time - optional</td></tr>
     <tr><td><b>$max</b></td><td>Parameter max time - optional</td></tr>
     </table>
     <br><br>
     Optional ist es möglich, auch die morgigen sr_weather bzw. ss_weather abzufragen, dafür werden die "fiktiven" Reading-Namen "sr_tomorrow" bzw. "ss_tomorrow" verwendet. Als Bedeckungsgrad wird dabei ein fiktiver Wert von "50" angenommen, dieser kann mit (optionalem) 5. Parameter auch abweichend (Bereich: 0-100) angegeben werden. Beispiel:<br>
     <code>{ twilight('tw_test1','sr_tomorrow','08:00','09:10',100) }</code>
  </ul>
  <br>
Anwendungsbeispiel:
<pre>
    define BlindDown at *{twilight("myTwilight","sr_indoor","7:30","9:00")} set xxxx position 100
    # xxxx ist ein definiertes Rollo
</pre>

</ul>

=end html_DE

=for :application/json;q=META.json 59_Twilight.pm
{
   "abstract" : "generate twilight & sun related events; check alternative Astro.",
   "author" : [
      "Beta-User <>",
      "orphan <>"
   ],
   "keywords" : [
      "Timer",
      "light",
      "twlight",
      "Dämmerung",
      "Helligkeit",
      "Wetter",
      "weather"
   ],
   "name" : "FHEM::Twilight",
   "prereqs" : {
      "runtime" : {
         "requires" : {
            "FHEM::Meta" : "0",
            "GPUtils" : "0",
            "List::Util" : "0",
            "Math::Trig" : "0",
            "Time::Local" : "0",
            "strict" : "0",
            "warnings" : "0"
         }
      }
   },
   "x_fhem_maintainer" : [
      "Beta-User",
      "orphan"
   ],
   "x_lang" : {
      "de" : {
         "abstract" : "liefert Dämmerungs- und Sonnenstands-basierte Events. Alternative: Astro"
      }
   }
}
=end :application/json;q=META.json

=cut
