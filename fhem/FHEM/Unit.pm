# $Id$

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use UConv;

sub Unit_Initialize() {
}

###########################################
# Functions used to make fhem-oneliners more readable,
# but also recommended to be used by modules

sub ReadingsUnit($$@) {
    my ( $d, $n, $default, $lang, $format ) = @_;
    my $ud;
    $default = "" if ( !$default );
    return ""
      if ( !defined( $defs{$d}{READINGS}{$n} ) );

    addToAttrList("unitFromReading");

    my $unitFromReading =
      AttrVal( $d, "unitFromReading",
        AttrVal( "global", "unitFromReading", undef ) );

    # unit defined with reading
    if ( defined( $defs{$d}{READINGS}{$n}{U} ) ) {
        $ud = Unit::GetDetails( $defs{$d}{READINGS}{$n}{U}, $lang );
    }

    # calculate unit from readingname
    elsif ( $unitFromReading && $unitFromReading ne "0" ) {
        $ud = Unit::GetDetailsFromReadingname( $n, $lang );
    }

    return $ud->{unit_symbol}
      if ( !$format && defined( $ud->{unit_symbol} ) );
    return $ud->{unit} if ( !$format && defined( $ud->{unit} ) );
    return $ud->{unit_long}
      if ( $format && $format eq "1" && defined( $ud->{unit_long} ) );
    return $ud->{unit_abbr}
      if ( $format && $format eq "2" && defined( $ud->{unit_abbr} ) );
    return $default;
}

sub ReadingsUnitLong($$@) {
    my ( $d, $n, $default, $lang ) = @_;
    $lang = "en" if ( !$lang );
    return ReadingsUnit( $d, $n, $default, $lang, 1 );
}

sub ReadingsUnitAbbr($$@) {
    my ( $d, $n, $default, $lang ) = @_;
    $lang = "en" if ( !$lang );
    return ReadingsUnit( $d, $n, $default, $lang, 2 );
}

sub ReadingsValUnit($$$@) {
    my ( $d, $n, $default, $lang, $format ) = @_;
    my $v = ReadingsVal( $d, $n, $default );
    my $u = ReadingsUnitAbbr( $d, $n );
    return Unit::GetValueWithUnit( $v, $u, $lang, $format );
}

sub ReadingsValUnitLong($$$@) {
    my ( $d, $n, $default, $lang ) = @_;
    return ReadingsValUnit( $d, $n, $default, $lang, 1 );
}

################################################################
# Functions used by modules.

sub setReadingsUnit($$@) {
    my ( $hash, $rname, $unit ) = @_;
    my $name = $hash->{NAME};
    my $unitDetails;

    return "Cannot assign unit to undefined reading $rname for device $name"
      if ( !$hash->{READINGS}{$rname}
        || !defined( $hash->{READINGS}{$rname} ) );

    # check unit database for unit_abbr
    if ($unit) {
        $unitDetails = Unit::GetDetails($unit);
    }

    # find unit based on reading name
    else {
        $unitDetails = Unit::GetDetailsFromReadingname($rname);
        return
          if ( !$unitDetails || !defined( $unitDetails->{"unit_abbr"} ) );
    }

    return
"$unit is not a registered unit abbreviation and cannot be assigned to reading $name: $rname"
      if ( !$unitDetails || !defined( $unitDetails->{"unit_abbr"} ) );

    if (
        !$unit
        && ( !defined( $hash->{READINGS}{$rname}{U} )
            || $hash->{READINGS}{$rname}{U} ne $unitDetails->{"unit_abbr"} )
      )
    {
        $hash->{READINGS}{$rname}{U} = $unitDetails->{"unit_abbr"};
        return "Set auto-detected unit for reading $name $rname: "
          . $unitDetails->{"unit_abbr"};
    }

    $hash->{READINGS}{$rname}{U} = $unitDetails->{"unit_abbr"};
    return;
}

sub removeReadingsUnit($$) {
    my ( $hash, $rname ) = @_;
    my $name = $hash->{NAME};

    return "Cannot remove unit from undefined reading $rname for device $name"
      if ( !$hash->{READINGS}{$rname}
        || !defined( $hash->{READINGS}{$rname} ) );

    if ( defined( $hash->{READINGS}{$rname}{U} ) ) {
        my $u = $hash->{READINGS}{$rname}{U};
        delete $hash->{READINGS}{$rname}{U};
        return "Removed unit $u from reading $rname of device $name";
    }

    return;
}

sub getMultiValStatus($$;$$) {
    my ( $d, $rlist, $lang, $format ) = @_;
    my $txt = "";

    if ( !$format ) {
        $format = "-1";
    }
    else {
        $format--;
    }

    foreach ( split( /\s+/, $rlist ) ) {
        $_ =~ /^(\w+):?(\w+)?$/;
        my $v = (
            $format > -1
            ? ReadingsValUnit( $d, $1, "", $lang, $format )
            : ReadingsVal( $d, $1, "" )
        );
        my $n = ( $2 ? $2 : Unit::GetShortReadingname($1) );

        if ( $v ne "" ) {
            $txt .= " " if ( $txt ne "" );
            $txt .= "$n: $v";
        }
    }

    return $txt;
}

################################################################
#
# Wrappers for commonly used core functions in device-specific modules.
#
################################################################

sub readingsUnitSingleUpdate($$$$$) {
    my ( $hash, $reading, $value, $unit, $dotrigger ) = @_;
    readingsUnitBeginUpdate($hash);
    my $rv = readingsUnitBulkUpdate( $hash, $reading, $value, $unit );
    readingsUnitEndUpdate( $hash, $dotrigger );
    return $rv;
}

sub readingsUnitSingleUpdateIfChanged($$$$$) {
    my ( $hash, $reading, $value, $unit, $dotrigger ) = @_;
    return undef if ( $value eq ReadingsVal( $hash->{NAME}, $reading, "" ) );
    readingsUnitBeginUpdate($hash);
    my $rv = readingsUnitBulkUpdate( $hash, $reading, $value, $unit );
    readingsUnitEndUpdate( $hash, $dotrigger );
    return $rv;
}

sub readingsUnitBulkUpdateIfChanged($$$@) {
    my ( $hash, $reading, $value, $unit, $changed ) = @_;
    return undef if ( $value eq ReadingsVal( $hash->{NAME}, $reading, "" ) );
    return readingsUnitBulkUpdate( $hash, $reading, $value, $unit, $changed );
}

sub readingsUnitBulkUpdate($$$@) {
    my ( $hash, $reading, $value, $unit, $changed ) = @_;
    my $name = $hash->{NAME};

    return if ( !defined($reading) || !defined($value) );

    # sanity check
    if ( !defined( $hash->{".updateTimestamp"} ) ) {
        Log 1,
          "readingsUnitUpdate($name,$reading,$value,$unit) missed to call "
          . "readingsUnitBeginUpdate first.";
        return;
    }

    my $return = readingsBulkUpdate( $hash, $reading, $value, $changed );
    return $return if !$return;

    $return = setReadingsUnit( $hash, $reading, $unit );
    return $return;
}

# wrapper function for original readingsBeginUpdate
sub readingsUnitBeginUpdate($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    if ( !$name ) {
        Log 1, "ERROR: empty name in readingsUnitBeginUpdate";
        stacktrace();
        return;
    }
    return readingsBeginUpdate($hash);
}

# wrapper function for original readingsEndUpdate
sub readingsUnitEndUpdate($$) {
    my ( $hash, $dotrigger ) = @_;
    my $name = $hash->{NAME};
    return readingsEndUpdate( $hash, $dotrigger );
}

# Generalized function for DbLog unit support
sub Unit_DbLog_split($$) {
    my ( $event, $device ) = @_;
    my ( $reading, $value, $unit ) = "";

    # exclude any multi-value events
    if ( $event =~ /(.*: +.*: +.*)+/ ) {
        Log3 $device, 5,
          "Unit_DbLog_split $device: Ignoring multi-value event $event";
        return undef;
    }

    # exclude sum/cum and avg events
    elsif ( $event =~ /^(.*_sum[0-9]+m|.*_cum[0-9]+m|.*_avg[0-9]+m): +.*/ ) {
        Log3 $device, 5,
          "Unit_DbLog_split $device: Ignoring sum/avg event $event";
        return undef;
    }

    # text conversions
    elsif ( $event =~ /^(pressure_trend_sym): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = UConv::sym2pressuretrend($2);
    }
    elsif ( $event =~ /^(UVcondition): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = UConv::uvcondition2log($2);
    }
    elsif ( $event =~ /^(Activity): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = UConv::activity2log($2);
    }
    elsif ( $event =~ /^(condition): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = UConv::weathercondition2log($2);
    }
    elsif ( $event =~ /^(.*[Hh]umidity[Cc]ondition): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = UConv::humiditycondition2log($2);
    }

    # general event handling
    elsif ( $event =~ /^(.+): +(\S+) *[\[\{\(]? *([\w\°\%\^\/\\]*).*/ ) {
        $reading = $1;
        $value   = ReadingsNum( $device, $1, $2 );
        $unit    = ReadingsUnit( $device, $1, $3 );
    }

    if ( !Scalar::Util::looks_like_number($value) ) {
        Log3 $device, 5,
"Unit_DbLog_split $device: Ignoring event $event: value does not look like a number";
        return undef;
    }

    Log3 $device, 5,
"Unit_DbLog_split $device: Splitting event $event > reading=$reading value=$value unit=$unit";

    return ( $reading, $value, $unit );
}

################################################################
#
# User commands
#
################################################################

my %unithash = (
    Fn  => "CommandUnit",
    Hlp => "[<devspec>] [<readingspec>],get unit for <devspec> <reading>",
);
$cmds{unit} = \%unithash;

sub CommandUnit($$) {
    my ( $cl, $def ) = @_;
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my @a = split( " ", $def, 2 );
    return "Usage: unit [<name>] [<readingspec>]\n$namedef"
      if ( $a[0] && $a[0] eq "?" );
    $a[0] = ".*" if ( !$a[0] || $a[0] eq "" );
    $a[1] = ".*" if ( !$a[1] || $a[1] eq "" );

    my @rets;
    foreach my $sdev ( devspec2array( $a[0], $cl ) ) {
        if ( !defined( $defs{$sdev} ) ) {
            push @rets, "Please define $sdev first";
            next;
        }

        my $readingspec = '^' . $a[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$sdev}{READINGS} }
          )
        {
            my $ret = ReadingsUnit( $sdev, $reading, undef, undef, 2 );
            push @rets,
              "$sdev $reading unit: $ret ("
              . ReadingsValUnit( $sdev, $reading, "" ) . ")"
              if ($ret);
        }
    }
    return join( "\n", @rets );
}

my %setunithash = (
    Fn  => "CommandSetunit",
    Hlp => "<devspec> <readingspec> [<unit>],set unit for <devspec> <reading>",
);
$cmds{setunit} = \%setunithash;

sub CommandSetunit($$$) {
    my ( $cl, $def ) = @_;
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my @a = split( " ", $def, 3 );

    if ( $a[0] && $a[0] eq "?" ) {
        $namedef .= "\n\n";
        my $list = Unit::GetList( "en", $a[1] );
        $namedef .= Dumper($list);
    }

    return "Usage: setunit <name> [<readingspec>] [<unit>]\n$namedef"
      if ( @a < 1 || ( $a[0] && $a[0] eq "?" ) );
    $a[1] = ".*" if ( !$a[1] || $a[1] eq "" );

    my @rets;
    foreach my $sdev ( devspec2array( $a[0], $cl ) ) {
        if ( !defined( $defs{$sdev} ) ) {
            push @rets, "Please define $sdev first";
            next;
        }

        my $readingspec = '^' . $a[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$sdev}{READINGS} }
          )
        {
            my $ret = setReadingsUnit( $defs{$sdev}, $reading, $a[2] );
            push @rets, $ret if ($ret);
        }
    }
    return join( "\n", @rets );
}

my %deleteunithash = (
    Fn  => "CommandDeleteunit",
    Hlp => "<devspec> [<readingspec>],delete unit for <devspec> <reading>",
);
$cmds{deleteunit} = \%deleteunithash;

sub CommandDeleteunit($$$) {
    my ( $cl, $def ) = @_;
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my @a = split( " ", $def, 3 );
    return "Usage: deleteunit <name> [<readingspec>]\n$namedef"
      if ( @a < 1 || ( $a[0] && $a[0] eq "?" ) );
    $a[1] = ".*" if ( !$a[1] || $a[1] eq "" );

    my @rets;
    foreach my $sdev ( devspec2array( $a[0], $cl ) ) {
        if ( !defined( $defs{$sdev} ) ) {
            push @rets, "Please define $sdev first";
            next;
        }

        my $readingspec = '^' . $a[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$sdev}{READINGS} }
          )
        {
            my $ret = removeReadingsUnit( $defs{$sdev}, $reading );
            push @rets, $ret if ($ret);
        }
    }
    return join( "\n", @rets );
}

####################
# Package: Unit

package Unit;

my %autoscale = (
    '0'     => { format => '%i',   scale => 1000, },
    '0.001' => { format => '%i',   scale => 1000, },
    '0.1'   => { format => '%.1f', scale => 1, },
    '10'    => { format => '%i',   scale => 1, },
    '1.0e3' => { format => '%.1f', scale => 0.001, },
    '2.0e3' => { format => '%i',   scale => 0.001, },
    '1.0e6' => { format => '%.1f', scale => 0.001, },
    '2.0e6' => { format => '%i',   scale => 0.001, },
);

my %scales_m = (
    '1.0e-12' => {
        'scale'      => 'p',
        'scale_long' => {
            de => 'Piko',
            en => 'pico',
            fr => 'pico',
            nl => 'pico',
            pl => 'pico',
        },
    },

    '1.0e-9' => {
        'scale'      => 'n',
        'scale_long' => {
            de => 'Nano',
            en => 'nano',
            fr => 'nano',
            nl => 'nano',
            pl => 'nano',
        },
    },

    '1.0e-6' => {
        'scale'      => 'μ',
        'scale_long' => {
            de => 'Mikro',
            en => 'micro',
            fr => 'micro',
            nl => 'micro',
            pl => 'micro',
        },
    },

    '1.0e-3' => {
        'scale'      => 'm',
        'scale_long' => {
            de => 'Milli',
            en => 'mili',
            fr => 'mili',
            nl => 'mili',
            pl => 'mili',
        },
    },

    '1.0e-2' => {
        'scale'      => 'c',
        'scale_long' => {
            de => 'Zenti',
            en => 'centi',
            fr => 'centi',
            nl => 'centi',
            pl => 'centi',
        },
    },

    '1.0e-1' => {
        'scale'      => 'd',
        'scale_long' => {
            de => 'Dezi',
            en => 'deci',
            fr => 'deci',
            nl => 'deci',
            pl => 'deci',
        },
    },

    '1.0e0' => {
        'scale'      => '',
        'scale_long' => '',
    },

    '1.0e1' => {
        'scale'      => 'da',
        'scale_long' => {
            de => 'Deka',
            en => 'deca',
            fr => 'deca',
            nl => 'deca',
            pl => 'deca',
        },
    },

    '1.0e2' => {
        'scale'      => 'h',
        'scale_long' => {
            de => 'Hekto',
            en => 'hecto',
            fr => 'hecto',
            nl => 'hecto',
            pl => 'hecto',
        },
    },

    '1.0e3' => {
        'scale'      => 'k',
        'scale_long' => {
            de => 'Kilo',
            en => 'kilo',
            fr => 'kilo',
            nl => 'kilo',
            pl => 'kilo',
        },
    },

    '1.0e6' => {
        'scale'      => 'M',
        'scale_long' => {
            de => 'Mega',
            en => 'mega',
            fr => 'mega',
            nl => 'mega',
            pl => 'mega',
        },
    },
);

my %scales_sq = (
    'scale'      => '2',
    'scale_long' => {
        de => 'Quadrat',
        en => 'square',
        fr => 'square',
        nl => 'square',
        pl => 'square',
    },
);

my %scales_cu = (
    'scale'      => '3',
    'scale_long' => {
        de => 'Kubik',
        en => 'cubic',
        fr => 'cubic',
        nl => 'cubic',
        pl => 'cubic',
    },
);

my %unit_base = (

  # based on https://de.wikipedia.org/wiki/Liste_physikalischer_Gr%C3%B6%C3%9Fen

    0 => {
        dimension      => 'L',
        formula_symbol => 'l',
        base_unit      => 'm',
        base_parameter => {
            de => 'Länge',
            en => 'length',
            fr => 'length',
            nl => 'length',
            pl => 'length',
        },
    },

    1 => {
        dimension      => 'M',
        formula_symbol => 'm',
        base_unit      => 'kg',
        base_parameter => {
            de => 'Masse',
            en => 'mass',
            fr => 'mass',
            nl => 'mass',
            pl => 'mass',
        },
    },

    2 => {
        dimension      => 'T',
        formula_symbol => 't',
        base_unit      => 's',
        base_parameter => {
            de => 'Zeit',
            en => 'time',
            fr => 'time',
            nl => 'time',
            pl => 'time',
        },
    },

    3 => {
        dimension      => 'I',
        formula_symbol => 'i',
        base_unit      => 'a',
        base_parameter => {
            de => 'elektrische Stromstärke',
            en => 'electric current',
            fr => 'electric current',
            nl => 'electric current',
            pl => 'electric current',
        },
    },

    4 => {
        dimension      => 'θ',
        formula_symbol => 'T',
        base_unit      => 'k',
        base_parameter => {
            de => 'absolute Temperatur',
            en => 'absolute temperature',
            fr => 'absolute temperature',
            nl => 'absolute temperature',
            pl => 'absolute temperature',
        },
    },

    5 => {
        dimension      => 'N',
        formula_symbol => 'n',
        base_unit      => 'mol',
        base_parameter => {
            de => 'Stoffmenge',
            en => 'amount of substance',
            fr => 'amount of substance',
            nl => 'amount of substance',
            pl => 'amount of substance',
        },
    },

    6 => {
        dimension      => 'J',
        formula_symbol => 'Iv',
        base_unit      => 'cd',
        base_parameter => {
            de => 'Lichtstärke',
            en => 'luminous intensity',
            fr => 'luminous intensity',
            nl => 'luminous intensity',
            pl => 'luminous intensity',
        },
    },

    7 => {
        dimension      => 'M L^2 T^−2',
        formula_symbol => 'E',
        base_unit      => 'j',
        base_parameter => {
            de => 'Energie',
            en => 'energy',
            fr => 'energy',
            nl => 'energy',
            pl => 'energy',
        },
    },

    8 => {
        dimension      => 'T^−1',
        formula_symbol => 'f',
        base_unit      => 'hz',
        base_parameter => {
            de => 'Frequenz',
            en => 'frequency',
            fr => 'frequency',
            nl => 'frequency',
            pl => 'frequency',
        },
    },

    9 => {
        dimension      => 'M L^2 T^−3',
        formula_symbol => 'P',
        base_unit      => 'w',
        base_parameter => {
            de => 'Leistung',
            en => 'power',
            fr => 'power',
            nl => 'power',
            pl => 'power',
        },
    },

    10 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'p',
        base_unit      => 'pa',
        base_parameter => {
            de => 'Druck',
            en => 'pressure',
            fr => 'pressure',
            nl => 'pressure',
            pl => 'pressure',
        },
    },

    11 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'pabs',
        base_unit      => 'pabs',
        base_parameter => {
            de => 'absoluter Druck',
            en => 'absolute pressure',
            fr => 'absolute pressure',
            nl => 'absolute pressure',
            pl => 'absolute pressure',
        },
    },

    12 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'pamb',
        base_unit      => 'pamb',
        base_parameter => {
            de => 'Luftdruck',
            en => 'air pressure',
            fr => 'air pressure',
            nl => 'air pressure',
            pl => 'air pressure',
        },
    },

    13 => {
        dimension      => 'M L^2 T^−3 I^−1',
        formula_symbol => 'U',
        base_unit      => 'v',
        base_parameter => {
            de => 'elektrische Spannung',
            en => 'electric voltage',
            fr => 'electric voltage',
            nl => 'electric voltage',
            pl => 'electric voltage',
        },
    },

    14 => {
        dimension      => '1',
        formula_symbol => '',
        base_unit      => 'rad',
        base_parameter => {
            de => 'ebener Winkel',
            en => 'plane angular',
            fr => 'plane angular',
            nl => 'plane angular',
            pl => 'plane angular',
        },
    },

    15 => {
        dimension      => 'L T^−1',
        formula_symbol => 'v',
        base_unit      => 'kmh',
        base_parameter => {
            de => 'Geschwindigkeit',
            en => 'speed',
            fr => 'speed',
            nl => 'speed',
            pl => 'speed',
        },
    },

    16 => {
        dimension      => 'L^−2 J',
        formula_symbol => 'Ev',
        base_unit      => 'lx',
        base_parameter => {
            de => 'Beleuchtungsstärke',
            en => 'illumination intensity',
            fr => 'illumination intensity',
            nl => 'illumination intensity',
            pl => 'illumination intensity',
        },
    },

    17 => {
        dimension      => 'J',
        formula_symbol => 'F',
        base_unit      => 'lm',
        base_parameter => {
            de => 'Lichtstrom',
            en => 'luminous flux',
            fr => 'luminous flux',
            nl => 'luminous flux',
            pl => 'luminous flux',
        },
    },

    18 => {
        dimension      => 'L^3',
        formula_symbol => 'V',
        base_unit      => 'm3',
        base_parameter => {
            de => 'Volumen',
            en => 'volume',
            fr => 'volume',
            nl => 'volume',
            pl => 'volume',
        },
    },

    19 => {
        dimension      => '1',
        formula_symbol => 'B',
        base_unit      => 'b',
        base_parameter => {
            de => 'Logarithmische Größe',
            en => 'logarithmic level',
            fr => 'logarithmic level',
            nl => 'logarithmic level',
            pl => 'logarithmic level',
        },
    },

    20 => {
        dimension      => 'I T',
        formula_symbol => 'C',
        base_unit      => 'coul',
        base_parameter => {
            de => 'elektrische Ladung',
            en => 'electric charge',
            fr => 'electric charge',
            nl => 'electric charge',
            pl => 'electric charge',
        },
    },

    21 => {
        dimension      => '',
        formula_symbol => 'F',
        base_unit      => 'far',
        base_parameter => {
            de => 'elektrische Kapazität',
            en => 'electric capacity',
            fr => 'electric capacity',
            nl => 'electric capacity',
            pl => 'electric capacity',
        },
    },

    22 => {
        dimension      => '',
        formula_symbol => 'F',
        base_unit      => 'far',
        base_parameter => {
            de => 'elektrische Widerstand',
            en => 'electric resistance',
            fr => 'electric resistance',
            nl => 'electric resistance',
            pl => 'electric resistance',
        },
    },
);

#TODO really translate all languages
my %unitsDB = (

    pct => {

        unit_symbol => '%',
        unit_long   => {
            de => 'Prozent',
            en => 'percent',
            fr => 'percent',
            nl => 'percent',
            pl => 'percent',
        },

        txt_format => '%value% %unit_symbol%',
    },

    gon => {

        base_ref    => 14,
        unit_symbol => '°',
        unit        => 'gon',
        unit_long   => {
            de => 'Grad',
            en => 'gradians',
            fr => 'gradians',
            nl => 'gradians',
            pl => 'gradians',
        },
        txt_format => '%value%%unit_symbol%',
    },

    rad => {
        base_ref  => 14,
        unit      => 'rad',
        unit_long => {
            de => 'Radiant',
            en => 'radiant',
            fr => 'radiant',
            nl => 'radiant',
            pl => 'radiant',
        },
    },

    # temperature
    c => {
        base_ref    => 2,
        unit_symbol => chr(0xC2) . chr(0xB0) . 'C',
        unit        => 'C',
        unit_long   => {
            de => 'Grad Celsius',
            en => 'Degrees Celsius',
            fr => 'Degrees Celsius',
            nl => 'Degrees Celsius',
            pl => 'Degrees Celsius',
        },
        txt_format => '%value%%unit_symbol%',
    },

    f => {
        base_ref    => 2,
        unit_symbol => chr(0xC2) . chr(0xB0) . 'F',
        unit        => 'F',
        unit_long   => {
            de => 'Grad Fahrenheit',
            en => 'Degree Fahrenheit',
            fr => 'Degree Fahrenheit',
            nl => 'Degree Fahrenheit',
            pl => 'Degree Fahrenheit',
        },
        txt_format => '%value% %unit_symbol%',
    },

    k => {
        base_ref  => 2,
        unit      => 'K',
        unit_long => {
            de => 'Kelvin',
            en => 'Kelvin',
            fr => 'Kelvin',
            nl => 'Kelvin',
            pl => 'Kelvin',
        },
    },

    # pressure
    bar => {
        base_ref     => 10,
        unit_scale_m => '1.0e0',
        unit         => 'bar',
        unit_long    => {
            de => 'Bar',
            en => 'Bar',
            fr => 'Bar',
            nl => 'Bar',
            pl => 'Bar',
        },
    },

    mbar => {
        unit_ref     => 'bar',
        unit_scale_m => '1.0e-3',
    },

    pa => {
        base_ref     => 10,
        unit_scale_m => '1.0e0',
        unit         => 'Pa',
        unit_long    => {
            de => 'Pascal',
            en => 'Pascal',
            fr => 'Pascal',
            nl => 'Pascal',
            pl => 'Pascal',
        },
    },

    hpa => {
        unit_ref     => 'pa',
        unit_scale_m => '1.0e2',
    },

    pamb => {
        base_ref     => 12,
        unit_scale_m => '1.0e0',
        unit         => 'Pa',
        unit_long    => {
            de => 'Pascal',
            en => 'Pascal',
            fr => 'Pascal',
            nl => 'Pascal',
            pl => 'Pascal',
        },
    },

    hpamb => {
        unit_ref     => 'pamb',
        unit_scale_m => '1.0e2',
    },

    inhg => {
        base_ref  => 12,
        unit      => 'inHg',
        unit_long => {
            de => 'Zoll Quecksilbersäule',
            en => 'Inches of Mercury',
            fr => 'Inches of Mercury',
            nl => 'Inches of Mercury',
            pl => 'Inches of Mercury',
        },
    },

    mmhg => {
        base_ref  => 12,
        unit      => 'mmHg',
        unit_long => {
            de => 'Millimeter Quecksilbersäule',
            en => 'Milimeter of Mercury',
            fr => 'Milimeter of Mercury',
            nl => 'Milimeter of Mercury',
            pl => 'Milimeter of Mercury',
        },
    },

    # length
    km => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e3',
    },

    hm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e2',
    },

    dam => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e1',
    },

    m => {
        base_ref     => 0,
        unit_scale_m => '1.0e0',
        unit         => 'm',
        unit_long    => {
            de => 'Meter',
            en => 'meter',
            fr => 'meter',
            nl => 'meter',
            pl => 'meter',
        },
    },

    dm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-1',
    },

    cm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-2',
    },

    mm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-3',
    },

    um => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-6',
    },

    nm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-9',
    },

    pm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-12',
    },

    fm => {
        unit_ref     => 'm',
        unit_scale_m => '1.0e-15',
    },

    in => {
        base_ref    => 4,
        unit_symbol => '″',
        unit        => 'in',
        unit_long   => {
            de => 'Zoll',
            en => 'inch',
            fr => 'inch',
            nl => 'inch',
            pl => 'inch',
        },
        unit_long_pl => {
            de => 'Zoll',
            en => 'inches',
            fr => 'inches',
            nl => 'inches',
            pl => 'inches',
        },
        txt_format         => '%value%%unit_symbol%',
        txt_format_long    => '%value% %unit_long%',
        txt_format_long_pl => '%value% %unit_long_pl%',
    },

    ft => {
        base_ref    => 0,
        unit_symbol => '′',
        unit        => 'ft',
        unit_long   => {
            de => 'Fuss',
            en => 'foot',
            fr => 'foot',
            nl => 'foot',
            pl => 'foot',
        },
        unit_long_pl => {
            de => 'Fuss',
            en => 'feet',
            fr => 'feet',
            nl => 'feet',
            pl => 'feet',
        },
        txt_format         => '%value%%unit_symbol%',
        txt_format_long    => '%value% %unit_long%',
        txt_format_long_pl => '%value% %unit_long_pl%',
    },

    yd => {
        base_ref  => 0,
        unit      => 'yd',
        unit_long => {
            de => 'Yard',
            en => 'yard',
            fr => 'yard',
            nl => 'yard',
            pl => 'yard',
        },
        unit_long_pl => {
            de => 'Yards',
            en => 'yards',
            fr => 'yards',
            nl => 'yards',
            pl => 'yards',
        },
    },

    mi => {
        base_ref  => 0,
        unit      => 'mi',
        unit_long => {
            de => 'Meilen',
            en => 'miles',
            fr => 'miles',
            nl => 'miles',
            pl => 'miles',
        },
    },

    # time
    sec => {
        base_ref     => 2,
        unit_scale_t => '1',
        unit         => {
            de => 's',
            en => 's',
            fr => 's',
            nl => 'sec',
            pl => 'sec',
        },
        unit_long => {
            de => 'Sekunde',
            en => 'second',
            fr => 'second',
            nl => 'second',
            pl => 'second',
        },
        unit_long_pl => {
            de => 'Sekunden',
            en => 'seconds',
            fr => 'seconds',
            nl => 'seconds',
            pl => 'seconds',
        },
    },

    min => {
        base_ref     => 2,
        unit_scale_t => '60',
        unit         => {
            de => 'Min',
            en => 'min',
            fr => 'min',
            nl => 'min',
            pl => 'min',
        },
        unit_long => {
            de => 'Minute',
            en => 'minute',
            fr => 'minute',
            nl => 'minute',
            pl => 'minute',
        },
        unit_long_pl => {
            de => 'Minuten',
            en => 'minutes',
            fr => 'minutes',
            nl => 'minutes',
            pl => 'minutes',
        },
    },

    hr => {
        base_ref     => 2,
        unit_scale_t => '3600',
        unit         => 'h',
        unit_long    => {
            de => 'Stunde',
            en => 'hour',
            fr => 'hour',
            nl => 'hour',
            pl => 'hour',
        },
        unit_long_pl => {
            de => 'Stunden',
            en => 'hours',
            fr => 'hours',
            nl => 'hours',
            pl => 'hours',
        },
    },

    d => {
        base_ref     => 2,
        unit_scale_t => '86400',
        unit         => {
            de => 'T',
            en => 'd',
            fr => 'd',
            nl => 'd',
            pl => 'd',
        },
        unit_long => {
            de => 'Tag',
            en => 'day',
            fr => 'day',
            nl => 'day',
            pl => 'day',
        },
        unit_long_pl => {
            de => 'Tage',
            en => 'days',
            fr => 'days',
            nl => 'days',
            pl => 'days',
        },
    },

    w => {
        base_ref     => 2,
        unit_scale_t => '604800',
        unit         => {
            de => 'W',
            en => 'w',
            fr => 'w',
            nl => 'w',
            pl => 'w',
        },
        unit_long => {
            de => 'Woche',
            en => 'week',
            fr => 'week',
            nl => 'week',
            pl => 'week',
        },
        unit_long_pl => {
            de => 'Wochen',
            en => 'weeks',
            fr => 'weeks',
            nl => 'weeks',
            pl => 'weeks',
        },
    },

    mon => {
        base_ref     => 2,
        unit_scale_t => '2592000',
        unit         => {
            de => 'M',
            en => 'm',
            fr => 'm',
            nl => 'm',
            pl => 'm',
        },
        unit_long => {
            de => 'Monat',
            en => 'month',
            fr => 'month',
            nl => 'month',
            pl => 'month',
        },
        unit_long_pl => {
            de => 'Monate',
            en => 'Monat',
            fr => 'Monat',
            nl => 'Monat',
            pl => 'Monat',
        },
    },

    y => {
        base_ref     => 2,
        unit_scale_t => '31536000',
        unit         => {
            de => 'J',
            en => 'y',
            fr => 'y',
            nl => 'y',
            pl => 'y',
        },
        unit_long => {
            de => 'Jahr',
            en => 'year',
            fr => 'year',
            nl => 'year',
            pl => 'year',
        },
        unit_long_pl => {
            de => 'Jahre',
            en => 'years',
            fr => 'years',
            nl => 'years',
            pl => 'years',
        },
    },

    # speed
    bft => {
        base_ref  => 15,
        unit      => 'bft',
        unit_long => {
            de => 'Windstärke',
            en => 'wind force',
            fr => 'wind force',
            nl => 'wind force',
            pl => 'wind force',
        },
        txt_format_long => '%unit_long% %value%',
    },

    kn => {
        base_ref  => 15,
        unit      => 'kn',
        unit_long => {
            de => 'Knoten',
            en => 'knots',
            fr => 'knots',
            nl => 'knots',
            pl => 'knots',
        },
    },

    fts => {
        base_ref        => 15,
        unit_ref        => 'ft',
        unit_ref_t      => 'sec',
        txt_format      => '%value% %unit%/%unit_t%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    mph => {
        base_ref        => 15,
        unit_ref        => 'mi',
        unit_ref_t      => 'hr',
        txt_format      => '%value% %unit%/%unit_t%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    kmh => {
        base_ref        => 15,
        unit_ref        => 'm',
        unit_ref_t      => 'hr',
        unit_scale_m    => '1.0e3',
        txt_format      => '%value% %unit%/%unit_t%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    mps => {
        base_ref        => 15,
        unit_ref        => 'm',
        unit_ref_t      => 'sec',
        unit_scale_m    => '1.0e0',
        txt_format      => '%value% %unit%/%unit_t%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    # weight
    mol => {
        base_ref => 5,
        unit     => 'mol',
    },

    pg => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-12",
    },

    ng => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-9",
    },

    ug => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-6",
    },

    mg => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-3",
    },

    cg => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-2",
    },

    dg => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e-1",
    },

    g => {
        base_ref     => 1,
        unit_scale_m => "1.0e0",
        unit         => 'g',
        unit_long    => {
            de => 'Gramm',
            en => 'gram',
            fr => 'gram',
            nl => 'gram',
            pl => 'gram',
        },
    },

    kg => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e3",
    },

    t => {
        unit_ref     => 'g',
        unit_scale_m => "1.0e6",
        unit         => 't',
        unit_long    => {
            de => 'Tonne',
            en => 'ton',
            fr => 'ton',
            nl => 'ton',
            pl => 'ton',
        },
        unit_long_pl => {
            de => 'Tonnen',
            en => 'tons',
            fr => 'tons',
            nl => 'tons',
            pl => 'tons',
        },
    },

    lb => {
        base_ref  => 1,
        unit      => 'lb',
        unit_long => {
            de => 'Pfund',
            en => 'pound',
            fr => 'pound',
            nl => 'pound',
            pl => 'pound',
        },
    },

    lbs => {
        base_ref  => 1,
        unit      => 'lbs',
        unit_long => {
            de => 'Pfund',
            en => 'pound',
            fr => 'pound',
            nl => 'pound',
            pl => 'pound',
        },
    },

    # luminous intensity
    cd => {
        base_ref  => 6,
        unit      => 'cd',
        unit_long => {
            de => 'Candela',
            en => 'Candela',
            fr => 'Candela',
            nl => 'Candela',
            pl => 'Candela',
        },
    },

    # illumination intensity
    lx => {
        base_ref  => 16,
        unit      => 'lx',
        unit_long => {
            de => 'Lux',
            en => 'Lux',
            fr => 'Lux',
            nl => 'Lux',
            pl => 'Lux',
        },
    },

    # luminous flux
    lm => {
        base_ref  => 17,
        unit      => 'lm',
        unit_long => {
            de => 'Lumen',
            en => 'Lumen',
            fr => 'Lumen',
            nl => 'Lumen',
            pl => 'Lumen',
        },
    },

    uvi => {
        unit      => 'UVI',
        unit_long => {
            de => 'UV-Index',
            en => 'UV-Index',
            fr => 'UV-Index',
            nl => 'UV-Index',
            pl => 'UV-Index',
        },
        txt_format         => '%unit% %value%',
        txt_format_long    => '%unit_long% %value%',
        txt_format_long_pl => '%unit_long% %value%',
    },

    # volume
    cm3 => {
        base_ref      => 18,
        unit_ref      => 'm',
        unit_scale_cu => '1.0e-2',
    },

    m3 => {
        base_ref      => 18,
        unit_ref      => 'm',
        unit_scale_cu => '1.0e0',
    },

    ml => {
        unit_ref     => 'l',
        unit_scale_m => '1.0e-3',
    },

    l => {
        base_ref  => 18,
        unit      => 'l',
        unit_long => {
            de => 'Liter',
            en => 'liter',
            fr => 'liter',
            nl => 'liter',
            pl => 'liter',
        },
        unit_long_pl => {
            de => 'Liter',
            en => 'liters',
            fr => 'liters',
            nl => 'liters',
            pl => 'liters',
        },
    },

    hl => {
        unit_ref     => 'l',
        unit_scale_m => '1.0e2',
    },

    b => {
        base_ref     => 19,
        unit_scale_m => '1.0e0',
        unit         => 'B',
        unit_long    => {
            de => 'Bel',
            en => 'Bel',
            fr => 'Bel',
            nl => 'Bel',
            pl => 'Bel',
        },
    },

    db => {
        unit_ref     => 'b',
        unit_scale_m => '1.0e-1',
    },

    ua => {
        unit_ref     => 'a',
        unit_scale_m => '1.0e-6',
    },

    ma => {
        unit_ref     => 'a',
        unit_scale_m => '1.0e-3',
    },

    a => {
        base_ref     => 3,
        unit_scale_m => '1.0e0',
        unit         => 'A',
        unit_long    => {
            de => 'Ampere',
            en => 'Ampere',
            fr => 'Ampere',
            nl => 'Ampere',
            pl => 'Ampere',
        },
    },

    uv => {
        unit_ref     => 'v',
        unit_scale_m => '1.0e-6',
    },

    mv => {
        unit_ref     => 'v',
        unit_scale_m => '1.0e-3',
    },

    v => {
        base_ref     => 13,
        unit_scale_m => '1.0e0',
        unit         => 'V',
        unit_long    => {
            de => 'Volt',
            en => 'Volt',
            fr => 'Volt',
            nl => 'Volt',
            pl => 'Volt',
        },
    },

    uj => {
        unit_ref     => 'j',
        unit_scale_m => '1.0e-6',
    },

    mj => {
        unit_ref     => 'j',
        unit_scale_m => '1.0e-3',
    },

    j => {
        base_ref     => 7,
        unit_scale_m => '1.0e0',
        unit         => 'J',
        unit_long    => {
            de => 'Joule',
            en => 'Joule',
            fr => 'Joule',
            nl => 'Joule',
            pl => 'Joule',
        },
    },

    uw => {
        unit_ref     => 'j',
        unit_scale_m => '1.0e-6',
    },

    mw => {
        unit_ref     => 'j',
        unit_scale_m => '1.0e-3',
    },

    w => {
        base_ref     => 9,
        unit_scale_m => '1.0e0',
        unit         => 'Watt',
        unit_long    => {
            de => 'Watt',
            en => 'Watt',
            fr => 'Watt',
            nl => 'Watt',
            pl => 'Watt',
        },
    },

    va => {
        unit_ref => 'w',
    },

    uwpscm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e-6',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e-2',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    uwpsm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e-6',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e0',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    mwpscm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e-3',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e-2',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    mwpsm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e-3',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e0',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    wpscm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e0',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e-2',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    wpsm => {
        unit_ref        => 'w',
        unit_scale_m    => '1.0e0',
        unit_ref_sq     => 'm',
        unit_scale_sq   => '1.0e0',
        txt_format      => '%value% %unit%/%unit_sq%',
        txt_format_long => {
            de => '%value% %unit_long% pro %unit_long_t%',
            en => '%value% %unit_long% per %unit_long_t%',
            fr => '%value% %unit_long% per %unit_long_t%',
            nl => '%value% %unit_long% per %unit_long_t%',
            pl => '%value% %unit_long% per %unit_long_t%',
        },
        txt_format_long_pl => {
            de => '%value% %unit_long_pl% pro %unit_long_t%',
            en => '%value% %unit_long_pl% per %unit_long_t%',
            fr => '%value% %unit_long_pl% per %unit_long_t%',
            nl => '%value% %unit_long_pl% per %unit_long_t%',
            pl => '%value% %unit_long_pl% per %unit_long_t%',
        },
    },

    coul => {
        base_ref  => 20,
        unit      => 'C',
        unit_long => {
            de => 'Coulomb',
            en => 'Coulomb',
            fr => 'Coulomb',
            nl => 'Coulomb',
            pl => 'Coulomb',
        },
    },

    far => {
        base_ref  => 21,
        unit      => 'F',
        unit_long => {
            de => 'Farad',
            en => 'Farad',
            fr => 'Farad',
            nl => 'Farad',
            pl => 'Farad',
        },
    },

    ohm => {
        base_ref    => 22,
        unit_symbol => 'Ω',
        unit        => 'Ohm',
        unit_long   => {
            de => 'Ohm',
            en => 'Ohm',
            fr => 'Ohm',
            nl => 'Ohm',
            pl => 'Ohm',
        },
    },

);

my %readingsDB = (
    airpress => {
        unified => 'pressure_hpa',    # link only
    },
    azimuth => {
        short => 'AZ',
        unit  => 'gon',
    },
    compasspoint => {
        short => 'CP',
    },
    dewpoint => {
        unified => 'dewpoint_c',      # link only
    },
    dewpoint_c => {
        short => 'D',
        unit  => 'c',
    },
    dewpoint_f => {
        short => 'Df',
        unit  => 'f',
    },
    dewpoint_k => {
        short => 'Dk',
        unit  => 'k',
    },
    elevation => {
        short => 'EL',
        unit  => 'gon',
    },
    feelslike => {
        unified => 'feelslike_c',    # link only
    },
    feelslike_c => {
        short => 'Tf',
        unit  => 'c',
    },
    feelslike_f => {
        short => 'Tff',
        unit  => 'f',
    },
    heat_index => {
        unified => 'heat_index_c',    # link only
    },
    heat_index_c => {
        short => 'HI',
        unit  => 'c',
    },
    heat_index_f => {
        short => 'HIf',
        unit  => 'f',
    },
    high => {
        unified => 'high_c',          # link only
    },
    high_c => {
        short => 'Th',
        unit  => 'c',
    },
    high_f => {
        short => 'Thf',
        unit  => 'f',
    },
    humidity => {
        short => 'H',
        unit  => 'pct',
    },
    humidityabs => {
        unified => 'humidityabs_c',    # link only
    },
    humidityabs_c => {
        short => 'Ha',
        unit  => 'c',
    },
    humidityabs_f => {
        short => 'Haf',
        unit  => 'f',
    },
    humidityabs_k => {
        short => 'Hak',
        unit  => 'k',
    },
    horizon => {
        short => 'HORIZ',
        unit  => 'gon',
    },
    indoordewpoint => {
        unified => 'indoordewpoint_c',    # link only
    },
    indoordewpoint_c => {
        short => 'Di',
        unit  => 'c',
    },
    indoordewpoint_f => {
        short => 'Dif',
        unit  => 'f',
    },
    indoordewpoint_k => {
        short => 'Dik',
        unit  => 'k',
    },
    indoorhumidity => {
        short => 'Hi',
        unit  => 'pct',
    },
    indoorhumidityabs => {
        unified => 'indoorhumidityabs_c',    # link only
    },
    indoorhumidityabs_c => {
        short => 'Hai',
        unit  => 'c',
    },
    indoorhumidityabs_f => {
        short => 'Haif',
        unit  => 'f',
    },
    indoorhumidityabs_k => {
        short => 'Haik',
        unit  => 'k',
    },
    indoortemperature => {
        unified => 'indoortemperature_c',    # link only
    },
    indoortemperature_c => {
        short => 'Ti',
        unit  => 'c',
    },
    indoortemperature_f => {
        short => 'Tif',
        unit  => 'f',
    },
    indoortemperature_k => {
        short => 'Tik',
        unit  => 'k',
    },
    israining => {
        short => 'IR',
    },
    level => {
        short => 'LVL',
        unit  => 'pct',
    },
    low => {
        unified => 'low_c',    # link only
    },
    low_c => {
        short => 'Tl',
        unit  => 'c',
    },
    low_f => {
        short => 'Tlf',
        unit  => 'f',
    },
    luminosity => {
        short => 'L',
        unit  => 'lx',
    },
    pct => {
        short => 'PCT',
        unit  => 'pct',
    },
    pressure => {
        unified => 'pressure_hpa',    # link only
    },
    pressure_hpa => {
        short => 'P',
        unit  => 'hpamb',
    },
    pressure_in => {
        short => 'Pin',
        unit  => 'inhg',
    },
    pressure_mm => {
        short => 'Pmm',
        unit  => 'mmhg',
    },
    pressure_psi => {
        short => 'Ppsi',
        unit  => 'psi',
    },
    pressure_psig => {
        short => 'Ppsi',
        unit  => 'psig',
    },
    pressureabs => {
        unified => 'pressureabs_hpamb',    # link only
    },
    pressureabs_hpa => {
        short => 'Pa',
        unit  => 'hpamb',
    },
    pressureabs_in => {
        short => 'Pain',
        unit  => 'inhg',
    },
    pressureabs_mm => {
        short => 'Pamm',
        unit  => 'mmhg',
    },
    pressureabs_psi => {
        short => 'Ppsia',
        unit  => 'psia',
    },
    pressureabs_psia => {
        short => 'Ppsia',
        unit  => 'psia',
    },
    rain => {
        unified => 'rain_mm',    # link only
    },
    rain_mm => {
        short => 'R',
        unit  => 'mm',
    },
    rain_in => {
        short => 'Rin',
        unit  => 'in',
    },
    rain_day => {
        unified => 'rain_day_mm',    # link only
    },
    rain_day_mm => {
        short => 'Rd',
        unit  => 'mm',
    },
    rain_day_in => {
        short => 'Rdin',
        unit  => 'in',
    },
    rain_night => {
        unified => 'rain_night_mm',    # link only
    },
    rain_night_mm => {
        short => 'Rn',
        unit  => 'mm',
    },
    rain_night_in => {
        short => 'Rnin',
        unit  => 'in',
    },
    rain_week => {
        unified => 'rain_week_mm',     # link only
    },
    rain_week_mm => {
        short => 'Rw',
        unit  => 'mm',
    },
    rain_week_in => {
        short => 'Rwin',
        unit  => 'in',
    },
    rain_month => {
        unified => 'rain_month_mm',    # link only
    },
    rain_month_mm => {
        short => 'Rm',
        unit  => 'mm',
    },
    rain_month_in => {
        short => 'Rmin',
        unit  => 'in',
    },
    rain_year => {
        unified => 'rain_year_mm',     # link only
    },
    rain_year_mm => {
        short => 'Ry',
        unit  => 'mm',
    },
    rain_year_in => {
        short => 'Ryin',
        unit  => 'in',
    },
    snow => {
        unified => 'snow_cm',          # link only
    },
    snow_cm => {
        short => 'S',
        unit  => 'cm',
    },
    snow_in => {
        short => 'Sin',
        unit  => 'in',
    },
    snow_day => {
        unified => 'snow_day_cm',      # link only
    },
    snow_day_cm => {
        short => 'Sd',
        unit  => 'cm',
    },
    snow_day_in => {
        short => 'Sdin',
        unit  => 'in',
    },
    snow_night => {
        unified => 'snow_night_cm',    # link only
    },
    snow_night_cm => {
        short => 'Sn',
        unit  => 'cm',
    },
    snow_night_in => {
        short => 'Snin',
        unit  => 'in',
    },
    sunshine => {
        unified => 'solarradiation',    # link only
    },
    solarradiation => {
        short => 'SR',
        unit  => 'wpsm',
    },
    temp => {
        unified => 'temperature_c',     # link only
    },
    temp_c => {
        unified => 'temperature_c',     # link only
    },
    temp_f => {
        unified => 'temperature_f',     # link only
    },
    temp_k => {
        unified => 'temperature_k',     # link only
    },
    temperature => {
        unified => 'temperature_c',     # link only
    },
    temperature_c => {
        short => 'T',
        unit  => 'c',
    },
    temperature_f => {
        short => 'Tf',
        unit  => 'f',
    },
    temperature_k => {
        short => 'Tk',
        unit  => 'k',
    },
    uv => {
        unified => 'uvi',    # link only
    },
    uvi => {
        short => 'UV',
        unit  => 'uvi',
    },
    uvr => {
        short => 'UVR',
        unit  => 'uwpscm',
    },
    valvedesired => {
        unified => 'valve',    # link only
    },
    valvepos => {
        unified => 'valve',    # link only
    },
    valveposition => {
        unified => 'valve',    # link only
    },
    valvepostc => {
        unified => 'valve',    # link only
    },
    valve => {
        short => 'VAL',
        unit  => 'pct',
    },
    visibility => {
        unified => 'visibility_km',    # link only
    },
    visibility_km => {
        short => 'V',
        unit  => 'km',
    },
    visibility_mi => {
        short => 'Vmi',
        unit  => 'mi',
    },
    wind_chill => {
        unified => 'wind_chill_c',     # link only
    },
    wind_chill_c => {
        short => 'Wc',
        unit  => 'c',
    },
    wind_chill_f => {
        short => 'Wcf',
        unit  => 'f',
    },
    wind_chill_k => {
        short => 'Wck',
        unit  => 'k',
    },
    wind_compasspoint => {
        short => 'Wdc',
    },
    windspeeddirection => {
        unified => 'wind_compasspoint',    # link only
    },
    winddirectiontext => {
        unified => 'wind_compasspoint',    # link only
    },
    wind_direction => {
        short => 'Wd',
        unit  => 'gon',
    },
    wind_dir => {
        unified => 'wind_direction',       # link only
    },
    winddir => {
        unified => 'wind_direction',       # link only
    },
    winddirection => {
        unified => 'wind_direction',       # link only
    },
    wind_gust => {
        unified => 'wind_gust_kmh',        # link only
    },
    wind_gust_kmh => {
        short => 'Wg',
        unit  => 'kmh',
    },
    wind_gust_bft => {
        short => 'Wgbft',
        unit  => 'bft',
    },
    wind_gust_fts => {
        short => 'Wgfts',
        unit  => 'fts',
    },
    wind_gust_kn => {
        short => 'Wgkn',
        unit  => 'kn',
    },
    wind_gust_mph => {
        short => 'Wgmph',
        unit  => 'mph',
    },
    wind_gust_mps => {
        short => 'Wgmps',
        unit  => 'mps',
    },
    wind_speed => {
        unified => 'wind_speed_kmh',    # link only
    },
    wind_speed_kmh => {
        short => 'Ws',
        unit  => 'kmh',
    },
    wind_speed_bft => {
        short => 'Wsbft',
        unit  => 'bft',
    },
    wind_speed_fts => {
        short => 'Wsfts',
        unit  => 'fts',
    },
    wind_speed_kn => {
        short => 'Wskn',
        unit  => 'kn',
    },
    wind_speed_mph => {
        short => 'Wsmph',
        unit  => 'mph',
    },
    wind_speed_mps => {
        short => 'Wsmps',
        unit  => 'mps',
    },
);

# Get unit list in local language as hash
sub GetList (@) {
    my ( $lang, $type ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    my %list;

    foreach my $u ( keys %unitsDB ) {
        my $details = GetDetails( $u, $lang );
        my $tn = (
              $details->{base_parameter}
            ? $details->{base_parameter}
            : "others"
        );
        $list{$tn}{$u} = $details
          if ( !$type || lc($type) eq $tn );
    }

    return \%list;
}

# Get unit details in local language as hash
sub GetDetails ($@) {
    my ( $unit, $lang ) = @_;
    my $u = lc($unit);
    my $l = ( $lang ? lc($lang) : "en" );
    my %details;

    return {} if ( !$unit || $unit eq "" );

    if ( defined( $unitsDB{$u} ) ) {
        foreach my $k ( keys %{ $unitsDB{$u} } ) {
            $details{$k} = $unitsDB{$u}{$k};
        }
        $details{unit_abbr} = $u;

        foreach ( 'unit_ref', 'unit_ref_t', 'unit_ref_sq', 'unit_ref_cu' ) {
            my $suffix = $_;
            $suffix =~ s/^[a-z]+_[a-z]+//;
            if ( defined( $details{$_} ) ) {
                my $ref = $details{$_};
                if ( !defined( $unitsDB{$ref} ) ) {
                    ::Log 1, "Unit::GetDetails($unit) broken reference $_";
                    next;
                }
                foreach my $k ( keys %{ $unitsDB{$ref} } ) {
                    next if ( $k =~ /^unit_scale/ );
                    if ( !defined( $details{$k} ) ) {
                        $details{$k} = $unitsDB{$ref}{$k};
                    }
                    else {
                        $details{ $k . $suffix } = $unitsDB{$ref}{$k}
                          if ( !defined( $details{ $k . $suffix } ) );
                    }
                }
            }
        }

        if ( $details{unit_scale_m} ) {
            my $ref = $details{unit_scale_m};
            foreach my $k ( keys %{ $scales_m{$ref} } ) {
                $details{ $k . '_m' } = $scales_m{$ref}{$k}
                  if ( !defined( $details{ $k . '_m' } ) );
            }
        }
        if ( $details{unit_scale_sq} ) {
            foreach my $k ( keys %scales_sq ) {
                $details{ $k . "_sq" } = $scales_sq{$k}
                  if ( !defined( $details{ $k . "_sq" } ) );
            }
        }
        if ( $details{unit_scale_cu} ) {
            foreach my $k ( keys %scales_cu ) {
                $details{ $k . "_cu" } = $scales_cu{$k}
                  if ( !defined( $details{ $k . "_cu" } ) );
            }
        }

        if ( defined( $details{base_ref} ) ) {
            my $ref = $details{base_ref};
            foreach my $k ( keys %{ $unit_base{$ref} } ) {
                $details{$k} = $unit_base{$ref}{$k}
                  if ( !defined( $details{$k} ) );
            }
        }

        if ($lang) {
            $details{"lang"} = $l;
            foreach ( keys %details ) {
                if ( $details{$_}
                    && ref( $details{$_} ) eq "HASH" )
                {
                    my $v;
                    $v = $details{$_}{$l}
                      if ( $details{$_}{$l} );
                    delete $details{$_};
                    $details{$_} = $v if ($v);
                }
            }

            $details{unit} = $details{scale_m} . $details{unit}
              if ( $details{scale_m} );
            $details{unit_long} =
              $details{scale_long_m} . lc( $details{unit_long} )
              if ( $details{scale_long_m} );

            $details{unit_sq} = $details{unit_sq} . $details{scale_sq}
              if ( $details{scale_sq} );
            $details{unit_long_sq} =
              $details{scale_long_sq} . lc( $details{unit_long_sq} )
              if ( $details{scale_long_sq} );

            $details{unit_cu} = $details{unit_cu} . $details{scale_cu}
              if ( $details{scale_cu} );
            $details{unit_long_cu} =
              $details{scale_long_cu} . lc( $details{unit_long_cu} )
              if ( $details{scale_long_cu} );
        }

        return \%details;
    }
}

# Get unit details in local language from reading name as hash
sub GetDetailsFromReadingname ($@) {
    my ( $reading, $lang ) = @_;
    my $details;
    my $r = $reading;
    my $l = ( $lang ? lc($lang) : "en" );
    my $u;
    my %return;

    # remove some prefix or other values to
    # flatten reading name
    $r =~ s/^fc\d+_//i;
    $r =~ s/_(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)_/_/i;
    $r =~ s/^(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)_//i;
    $r =~ s/_(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)$//i;
    $r =~ s/.*[-_](temp)$/$1/i;

    # rename capital letter containing readings
    if ( !$readingsDB{ lc($r) } ) {
        $r =~ s/^([A-Z])(.*)/\l$1$2/;
        $r =~ s/([A-Z][a-z0-9]+)[\/\|\-_]?/_$1/g;
    }

    $r = lc($r);

    # known alias reading names
    if ( $readingsDB{$r}{"unified"} ) {
        my $dr = $readingsDB{$r}{"unified"};
        $return{"unified"} = $dr;
        $return{"short"}   = $readingsDB{$dr}{"short"};
        $u                 = (
              $readingsDB{$dr}{"unit"}
            ? $readingsDB{$dr}{"unit"}
            : "-"
        );
    }

    # known standard reading names
    elsif ( $readingsDB{$r}{"short"} ) {
        $return{"unified"} = $reading;
        $return{"short"}   = $readingsDB{$r}{"short"};
        $u                 = (
              $readingsDB{$r}{"unit"}
            ? $readingsDB{$r}{"unit"}
            : "-"
        );
    }

    # just guessing the unit from reading name format
    elsif ( $r =~ /_([a-z]+)$/ ) {
        $u = lc($1);
    }

    return {} if ( !%return && !$u );
    return \%return if ( !$u );

    my $unitDetails = GetDetails( $u, $l );

    if ( ref($unitDetails) eq "HASH" ) {
        $return{"unified"}    = $reading if ( !$return{"unified"} );
        $return{"unit_guess"} = "1"      if ( !$return{"short"} );
        foreach my $k ( keys %{$unitDetails} ) {
            $return{$k} = $unitDetails->{$k};
        }
    }

    return \%return;
}

# Get value + unit combined string
sub GetValueWithUnit ($$@) {
    my ( $value, $unit, $lang, $format ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    my $return = GetDetails( $unit, $l );
    my $txt;
    return $value if ( !$return->{"unit"} );

    $return->{"value"} = $value;

    # long plural
    if (   $format
        && Scalar::Util::looks_like_number($value)
        && $value > 1
        && $return->{"unit_long_pl"} )
    {
        $txt = '%value% %unit_long_pl%';
        $txt = $return->{"txt_format_long_pl"}
          if ( $return->{"txt_format_long_pl"} );
    }

    # long singular
    elsif ( $format && $return->{"unit_long"} ) {
        $txt = '%value% %unit_long%';
        $txt = $return->{"txt_format_long"}
          if ( $return->{"txt_format_long"} );
    }

    # short
    else {
        $txt = '%value% %unit%';
        $txt = $return->{"txt_format"} if ( $return->{"txt_format"} );
    }

    foreach my $k ( keys %{$return} ) {
        $txt =~ s/%$k%/$return->{$k}/g;
    }

    return $txt;
}

# Get reading short name from reading name
sub GetShortReadingname($) {
    my ($reading) = @_;
    my $r = lc($reading);

    if ( $readingsDB{$r}{"short"} ) {
        return $readingsDB{$r}{"short"};
    }
    elsif ( $readingsDB{$r}{"unified"} ) {
        my $dr = $readingsDB{$r}{"unified"};
        return $readingsDB{$dr}{"short"};
    }

    return $reading;
}

1;
