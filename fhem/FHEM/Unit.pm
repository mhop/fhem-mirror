# $Id$

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use UConv;
use JSON;

sub Unit_Initialize() {
}

###########################################
# Functions used to make fhem-oneliners more readable,
# but also recommended to be used by modules

sub ReadingsUnit($$@) {
    my ( $name, $reading, $default, $lang, $format ) = @_;
    my $ud;
    $default = "" if ( !$default );
    return ""
      if ( !defined( $defs{$name}{READINGS}{$reading} ) );

    addToAttrList("unitFromReading");

    my $unitFromReading =
      AttrVal( $name, "unitFromReading",
        AttrVal( "global", "unitFromReading", undef ) );

    my $readingsDesc = readingsDesc( $name, $reading );

    # unit defined with reading
    if ( defined( $readingsDesc->{unit} ) ) {
        $ud = Unit::GetDetails( $readingsDesc->{unit}, $lang );
    }

    # calculate unit from readingname
    elsif ( $unitFromReading && $unitFromReading ne "0" ) {
        $ud = Unit::GetDetailsFromReadingname( $reading, $lang );
    }

    return $ud->{symbol}
      if ( !$format && defined( $ud->{symbol} ) );
    return $ud->{suffix} if ( !$format && defined( $ud->{suffix} ) );
    return $ud->{txt}
      if ( $format && $format eq "1" && defined( $ud->{txt} ) );
    return $ud->{abbr}
      if ( $format && $format eq "2" && defined( $ud->{abbr} ) );

    return $default;
}

sub ReadingsUnitLong($$@) {
    my ( $name, $reading, $default, $lang ) = @_;
    $lang = "en" if ( !$lang );
    return ReadingsUnit( $name, $reading, $default, $lang, 1 );
}

sub ReadingsUnitAbbr($$@) {
    my ( $name, $reading, $default, $lang ) = @_;
    $lang = "en" if ( !$lang );
    return ReadingsUnit( $name, $reading, $default, $lang, 2 );
}

sub ReadingsValUnit($$$@) {
    my ( $name, $reading, $default, $lang, $format ) = @_;
    my $val = ReadingsVal( $name, $reading, $default );
    my $unit = ReadingsUnitAbbr( $name, $reading );
    return Unit::GetValueWithUnit( $val, $unit, $lang, $format );
}

sub ReadingsValUnitLong($$$@) {
    my ( $name, $reading, $default, $lang ) = @_;
    return ReadingsValUnit( $name, $reading, $default, $lang, 1 );
}

#format a number according to desc and optional format.
sub formatValue($$;$) {
    my ( $value, $desc, $format ) = @_;

    return $value if ( !defined($value) );

    $desc = Unit::GetDetails($desc) if ( $desc && !ref($desc) );
    return $value if ( !$format && ( !$desc || ref($desc) ne 'HASH' ) );

    $value *= $desc->{factor} if ( $desc && $desc->{factor} );

    $format = $desc->{format} if ( !$format && $desc );
    $format = $Unit::autoscale if ( !$format );

    if ( ref($format) eq 'CODE' ) {
        $value = $format->($value);
    }
    elsif ( ref($format) eq 'HASH' ) {
        my $v = abs($value);
        foreach my $l ( sort { $b <=> $a } keys( %{$format} ) ) {
            next if ( ref( $format->{$l} ne 'HASH' ) );
            if ( $v >= $l ) {
                my $scale = $format->{$l}{scale};

                $value *= $scale if ($scale);
                $value = sprintf( $format->{$l}{format}, $value )
                  if ( $format->{$l}{format} );
                last;
            }
        }
    }
    elsif ($format) {
        my $scale = $desc->{scale};

        $value *= $scale if ($scale);
        $value = sprintf( $format, $value );
    }

    return ( $value, $desc->{suffix} ) if (wantarray);

    return $value;
}

#find desc and optional format for device:reading
sub readingsDesc($;$) {
    my ( $name, $reading ) = @_;
    my $d          = $defs{$name};
    my $m          = $modules{ $d->{TYPE} } if ($d);
    my $attrDesc   = decode_attribute( $name, "readingsDesc" );
    my $globalDesc = decode_attribute( "global", "readingsDesc" );

    my %desc;

    # module device specific
    if ( $d && $d->{readingsDesc} ) {
        %desc = %{ $d->{readingsDesc} };
    }

    # module general
    elsif ( $m && $m->{readingsDesc} ) {
        %desc = %{ $m->{readingsDesc} };
    }

    # global user overwrite
    foreach ( keys %{$globalDesc} ) {
        $desc{$_} = $globalDesc->{$_};
    }

    # device user overwrite
    foreach ( keys %{$attrDesc} ) {
        $desc{$_} = $attrDesc->{$_};
    }

    return {} if ( $reading && !defined( $desc{$reading} ) );
    return $desc{$reading} if ($reading);
    return \%desc;
}

#format device:reading with optional default value and optional desc and optional format
#TODO adapt to Unit.pm
sub formatReading($$;$$$) {
    my ( $name, $reading, $default, $desc, $format ) = @_;

    $desc = readingsDesc( $name, $reading ) if ( !$desc && $format );
    ( $desc, $format ) = readingsDesc( $name, $reading )
      if ( !$desc && !$format );

    my $value = ReadingsVal( $name, $reading, undef );

    #return $default if( !defined($value) && !looks_like_number($default) );
    $value = $default if ( !defined($value) );
    return $value if ( !looks_like_number($value) );

    return formatValue( $value, $desc, $format );
}

# return dimension symbol for device:reading
#TODO adapt to Unit.pm
sub readingsDimension($$) {
    my ( $name, $reading ) = @_;

    if ( my $desc = readingsDesc( $name, $reading ) ) {
        ;
        return $desc->{dimension} if ( $desc->{dimension} );
    }

    return '';
}

################################################################
# Functions used by modules.

sub setReadingsUnit($$@) {
    my ( $name, $reading, $unit ) = @_;
    my $unitDetails;
    my $ret;
    my $readingsDesc = readingsDesc($name);

    return
      if ( $unit
        && $readingsDesc->{$reading}{unit}
        && $readingsDesc->{$reading}{unit} eq $unit );

    # check unit database for correct abbr
    if ($unit) {
        $unitDetails = Unit::GetDetails($unit);
    }

    # find unit based on reading name
    else {
        $unitDetails = Unit::GetDetailsFromReadingname($reading);
        return
          if ( !$unitDetails || !defined( $unitDetails->{abbr} ) );
    }

    return
"$unit is not a registered unit abbreviation and cannot be assigned to reading $reading of device $name"
      if ( !$unitDetails || !defined( $unitDetails->{abbr} ) );

    return
      if ( $readingsDesc->{$reading}{unit}
        && $readingsDesc->{$reading}{unit} eq $unitDetails->{abbr} );

    my $attrDesc = decode_attribute( $name, "readingsDesc" );

    $ret =
      "Set auto-detected unit for device $name $reading: "
      . $unitDetails->{abbr}
      if ( !$unit && !defined( $attrDesc->{$reading}{unit} ) );

    $attrDesc->{$reading}{unit} = $unitDetails->{abbr};
    encode_attribute( $name, "readingsDesc", $attrDesc );

    return $ret;
}

sub removeReadingsUnit($$) {
    my ( $name, $reading ) = @_;
    my $ret;
    my $attrDesc = decode_attribute( $name, "readingsDesc" );

    if ( defined( $attrDesc->{$reading}{unit} ) ) {
        my $u = $attrDesc->{$reading}{unit};
        delete $attrDesc->{$reading}{unit};
        delete $attrDesc->{$reading}
          if ( keys %{ $attrDesc->{$reading} } < 1 );

        encode_attribute( $name, "readingsDesc", $attrDesc );
        return "Removed unit $u from reading $reading of device $name";
    }
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

sub encode_attribute ($$$) {
    my ( $name, $attribute, $data ) = @_;
    if ( !$data || keys %{$data} < 1 ) {
        CommandDeleteAttr( undef, "$name $attribute" );

        # empty cache
        delete $defs{$name}{'.attrCache'}
          if ( defined( $defs{$name}{'.attrCache'} ) );
        return;
    }

    my $json =
      JSON::PP->new->utf8->indent->indent_length(1)->canonical->allow_nonref;
    my $js = $json->encode($data);
    $js =~ s/(:\{|",?)\n\s+/$1 /gsm;
    addToAttrList("$attribute:textField-long");

    CommandAttr( undef, "$name $attribute $js" );

    # empty cache
    delete $defs{$name}{'.attrCache'}{$attribute}
      if ( defined( $defs{$name}{'.attrCache'}{$attribute} ) );
}

sub decode_attribute ($$) {
    my ( $name, $attribute ) = @_;

    # force empty cache if attribute was deleted
    if ( !$attr{$name}{$attribute} ) {
        delete $defs{$name}{'.attrCache'} if ( $defs{$name}{'.attrCache'} );
        return;
    }

    # cache attr
    if ( !defined( $defs{$name}{'.attrCache'}{$attribute} ) ) {
        my $data = decode_json( $attr{$name}{$attribute} );
        return if ( $@ || !$data || $data eq "" );
        $defs{$name}{'.attrCache'}{$attribute} = $data;
    }

    return $defs{$name}{'.attrCache'}{$attribute};
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
    return undef
      if ( $value eq ReadingsVal( $hash->{NAME}, $reading, "" ) );
    readingsUnitBeginUpdate($hash);
    my $rv = readingsUnitBulkUpdate( $hash, $reading, $value, $unit );
    readingsUnitEndUpdate( $hash, $dotrigger );
    return $rv;
}

sub readingsUnitBulkUpdateIfChanged($$$@) {
    my ( $hash, $reading, $value, $unit, $changed ) = @_;
    return undef
      if ( $value eq ReadingsVal( $hash->{NAME}, $reading, "" ) );
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

    $return = setReadingsUnit( $name, $reading, $unit );
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
            my $ret = setReadingsUnit( $sdev, $reading, $a[2] );
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
            my $ret = removeReadingsUnit( $sdev, $reading );
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
        'scale_txt_m'      => 'p',
        'scale_txt_long_m' => {
            de => 'Piko',
            en => 'pico',
            fr => 'pico',
            nl => 'pico',
            pl => 'pico',
        },
    },

    '1.0e-9' => {
        'scale_txt_m'      => 'n',
        'scale_txt_long_m' => {
            de => 'Nano',
            en => 'nano',
            fr => 'nano',
            nl => 'nano',
            pl => 'nano',
        },
    },

    '1.0e-6' => {
        'scale_txt_m'      => 'μ',
        'scale_txt_long_m' => {
            de => 'Mikro',
            en => 'micro',
            fr => 'micro',
            nl => 'micro',
            pl => 'micro',
        },
    },

    '1.0e-3' => {
        'scale_txt_m'      => 'm',
        'scale_txt_long_m' => {
            de => 'Milli',
            en => 'mili',
            fr => 'mili',
            nl => 'mili',
            pl => 'mili',
        },
    },

    '1.0e-2' => {
        'scale_txt_m'      => 'c',
        'scale_txt_long_m' => {
            de => 'Zenti',
            en => 'centi',
            fr => 'centi',
            nl => 'centi',
            pl => 'centi',
        },
    },

    '1.0e-1' => {
        'scale_txt_m'      => 'd',
        'scale_txt_long_m' => {
            de => 'Dezi',
            en => 'deci',
            fr => 'deci',
            nl => 'deci',
            pl => 'deci',
        },
    },

    '1.0e0' => {
        'scale_txt_m'      => '',
        'scale_txt_long_m' => '',
    },

    '1.0e1' => {
        'scale_txt_m'      => 'da',
        'scale_txt_long_m' => {
            de => 'Deka',
            en => 'deca',
            fr => 'deca',
            nl => 'deca',
            pl => 'deca',
        },
    },

    '1.0e2' => {
        'scale_txt_m'      => 'h',
        'scale_txt_long_m' => {
            de => 'Hekto',
            en => 'hecto',
            fr => 'hecto',
            nl => 'hecto',
            pl => 'hecto',
        },
    },

    '1.0e3' => {
        'scale_txt_m'      => 'k',
        'scale_txt_long_m' => {
            de => 'Kilo',
            en => 'kilo',
            fr => 'kilo',
            nl => 'kilo',
            pl => 'kilo',
        },
    },

    '1.0e6' => {
        'scale_txt_m'      => 'M',
        'scale_txt_long_m' => {
            de => 'Mega',
            en => 'mega',
            fr => 'mega',
            nl => 'mega',
            pl => 'mega',
        },
    },
);

my %scales_sq = (
    'scale_txt_sq'      => '2',
    'scale_txt_long_sq' => {
        de => 'Quadrat',
        en => 'square',
        fr => 'square',
        nl => 'square',
        pl => 'square',
    },
);

my %scales_cu = (
    'scale_txt_cu'      => '3',
    'scale_txt_long_cu' => {
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
        si_base        => 'm',
        txt_base       => {
            de => 'Länge',
            en => 'length',
            fr => 'length',
            nl => 'length',
            pl => 'length',
        },
        format => '%.1f',
    },

    1 => {
        dimension      => 'M',
        formula_symbol => 'm',
        si_base        => 'kg',
        txt_base       => {
            de => 'Masse',
            en => 'mass',
            fr => 'mass',
            nl => 'mass',
            pl => 'mass',
        },
        format => '%.1f',
    },

    2 => {
        dimension      => 'T',
        formula_symbol => 't',
        si_base        => 's',
        txt_base       => {
            de => 'Zeit',
            en => 'time',
            fr => 'time',
            nl => 'time',
            pl => 'time',
        },
        format => \&UConv::fmtTime,
    },

    3 => {
        dimension      => 'I',
        formula_symbol => 'i',
        si_base        => 'a',
        txt_base       => {
            de => 'elektrische Stromstärke',
            en => 'electric current',
            fr => 'electric current',
            nl => 'electric current',
            pl => 'electric current',
        },
        format => '%.1f',
    },

    4 => {
        dimension      => 'θ',
        formula_symbol => 'T',
        si_base        => 'k',
        txt_base       => {
            de => 'absolute Temperatur',
            en => 'absolute temperature',
            fr => 'absolute temperature',
            nl => 'absolute temperature',
            pl => 'absolute temperature',
        },
        format => '%.1f',
    },

    5 => {
        dimension      => 'N',
        formula_symbol => 'n',
        si_base        => 'mol',
        txt_base       => {
            de => 'Stoffmenge',
            en => 'amount of substance',
            fr => 'amount of substance',
            nl => 'amount of substance',
            pl => 'amount of substance',
        },
        format => '%.1f',
    },

    6 => {
        dimension      => 'J',
        formula_symbol => 'Iv',
        si_base        => 'cd',
        txt_base       => {
            de => 'Lichtstärke',
            en => 'luminous intensity',
            fr => 'luminous intensity',
            nl => 'luminous intensity',
            pl => 'luminous intensity',
        },
        format => '%.1f',
    },

    7 => {
        dimension      => 'M L^2 T^−2',
        formula_symbol => 'E',
        si_base        => 'j',
        txt_base       => {
            de => 'Energie',
            en => 'energy',
            fr => 'energy',
            nl => 'energy',
            pl => 'energy',
        },
        format => '%.1f',
    },

    8 => {
        dimension      => 'T^−1',
        formula_symbol => 'f',
        si_base        => 'hz',
        txt_base       => {
            de => 'Frequenz',
            en => 'frequency',
            fr => 'frequency',
            nl => 'frequency',
            pl => 'frequency',
        },
        format => '%i',
    },

    9 => {
        dimension      => 'M L^2 T^−3',
        formula_symbol => 'P',
        si_base        => 'w',
        txt_base       => {
            de => 'Leistung',
            en => 'power',
            fr => 'power',
            nl => 'power',
            pl => 'power',
        },
        format => '%.1f',
    },

    10 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'p',
        si_base        => 'pa',
        txt_base       => {
            de => 'Druck',
            en => 'pressure',
            fr => 'pressure',
            nl => 'pressure',
            pl => 'pressure',
        },
        format => '%i',
    },

    11 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'pabs',
        si_base        => 'pabs',
        txt_base       => {
            de => 'absoluter Druck',
            en => 'absolute pressure',
            fr => 'absolute pressure',
            nl => 'absolute pressure',
            pl => 'absolute pressure',
        },
        format => '%i',
    },

    12 => {
        dimension      => 'M L^−1 T^−2',
        formula_symbol => 'pamb',
        si_base        => 'pamb',
        txt_base       => {
            de => 'Luftdruck',
            en => 'air pressure',
            fr => 'air pressure',
            nl => 'air pressure',
            pl => 'air pressure',
        },
        format => '%i',
    },

    13 => {
        dimension      => 'M L^2 T^−3 I^−1',
        formula_symbol => 'U',
        si_base        => 'v',
        txt_base       => {
            de => 'elektrische Spannung',
            en => 'electric voltage',
            fr => 'electric voltage',
            nl => 'electric voltage',
            pl => 'electric voltage',
        },
        format => '%.1f',
    },

    14 => {
        dimension      => '1',
        formula_symbol => '',
        si_base        => 'rad',
        txt_base       => {
            de => 'ebener Winkel',
            en => 'plane angular',
            fr => 'plane angular',
            nl => 'plane angular',
            pl => 'plane angular',
        },
        format => '%i',
    },

    15 => {
        dimension      => 'L T^−1',
        formula_symbol => 'v',
        si_base        => 'kmh',
        txt_base       => {
            de => 'Geschwindigkeit',
            en => 'speed',
            fr => 'speed',
            nl => 'speed',
            pl => 'speed',
        },
        format => '%i',
    },

    16 => {
        dimension      => 'L^−2 J',
        formula_symbol => 'Ev',
        si_base        => 'lx',
        txt_base       => {
            de => 'Beleuchtungsstärke',
            en => 'illumination intensity',
            fr => 'illumination intensity',
            nl => 'illumination intensity',
            pl => 'illumination intensity',
        },
        format => '%i',
    },

    17 => {
        dimension      => 'J',
        formula_symbol => 'F',
        si_base        => 'lm',
        txt_base       => {
            de => 'Lichtstrom',
            en => 'luminous flux',
            fr => 'luminous flux',
            nl => 'luminous flux',
            pl => 'luminous flux',
        },
        format => '%i',
    },

    18 => {
        dimension      => 'L^3',
        formula_symbol => 'V',
        si_base        => 'm3',
        txt_base       => {
            de => 'Volumen',
            en => 'volume',
            fr => 'volume',
            nl => 'volume',
            pl => 'volume',
        },
        format => '%i',
    },

    19 => {
        dimension      => '1',
        formula_symbol => 'B',
        si_base        => 'b',
        txt_base       => {
            de => 'Logarithmische Größe',
            en => 'logarithmic level',
            fr => 'logarithmic level',
            nl => 'logarithmic level',
            pl => 'logarithmic level',
        },
        format => '%.1f',
    },

    20 => {
        dimension      => 'I T',
        formula_symbol => 'C',
        si_base        => 'coul',
        txt_base       => {
            de => 'elektrische Ladung',
            en => 'electric charge',
            fr => 'electric charge',
            nl => 'electric charge',
            pl => 'electric charge',
        },
        format => '%.1f',
    },

    21 => {
        dimension      => '',
        formula_symbol => 'F',
        si_base        => 'far',
        txt_base       => {
            de => 'elektrische Kapazität',
            en => 'electric capacity',
            fr => 'electric capacity',
            nl => 'electric capacity',
            pl => 'electric capacity',
        },
        format => '%.1f',
    },

    22 => {
        dimension      => '',
        formula_symbol => 'F',
        si_base        => 'far',
        txt_base       => {
            de => 'elektrische Widerstand',
            en => 'electric resistance',
            fr => 'electric resistance',
            nl => 'electric resistance',
            pl => 'electric resistance',
        },
        format => '%.1f',
    },

    900 => {
        txt_base => 'FHEM',
    },
);

#TODO really translate all languages
my %unitsDB = (

    # others
    closure => {
        ref_base => 900,
        format   => [ 'closed', 'open', 'tilted' ],
        suffix   => 'lock',
        txt      => {
            de => 'offen/geschlossen/gekippt',
            en => 'open/closed/tilted',
            fr => 'open/closed/tilted',
            nl => 'open/closed/tilted',
            pl => 'open/closed/tilted',
        },
    },

    oknok => {
        ref_base => 900,
        format   => [ 'nok', 'ok' ],
        suffix   => 'oknok',
        txt      => {
            de => 'ok/nok',
            en => 'ok/nok',
            fr => 'ok/nok',
            pl => 'ok/nok',
        },
    },

    onoff => {
        ref_base => 900,
        format   => [ 'off', 'on' ],
        suffix   => 'onoff',
        txt      => {
            de => 'an/aus',
            en => 'on/off',
            fr => 'on/off',
            nl => 'on/off',
            pl => 'on/off',
        },
    },

    bool => {
        ref_base => 900,
        format   => [ 'false', 'true' ],
        suffix   => 'bool',
        txt      => {
            de => 'wahr/falsch',
            en => 'true/false',
            fr => 'true/false',
            nl => 'true/false',
            pl => 'true/false',
        },
    },

    pct => {
        ref_base => 900,
        format   => '%i',
        symbol   => '%',
        suffix   => 'pct',
        txt      => {
            de => 'Prozent',
            en => 'percent',
            fr => 'percent',
            nl => 'percent',
            pl => 'percent',
        },
        tmpl => '%value% %symbol%',
    },

    # plane angular
    gon => {
        ref_base => 14,
        symbol   => '°',
        suffix   => 'gon',
        txt      => {
            de => 'Grad',
            en => 'gradians',
            fr => 'gradians',
            nl => 'gradians',
            pl => 'gradians',
        },
        tmpl => '%value%%symbol%',
    },

    rad => {
        ref_base => 14,
        suffix   => 'rad',
        txt      => {
            de => 'Radiant',
            en => 'radiant',
            fr => 'radiant',
            nl => 'radiant',
            pl => 'radiant',
        },
    },

    # temperature
    c => {
        ref_base => 2,
        symbol   => chr(0xC2) . chr(0xB0) . 'C',
        suffix   => 'C',
        txt      => {
            de => 'Grad Celsius',
            en => 'Degrees Celsius',
            fr => 'Degrees Celsius',
            nl => 'Degrees Celsius',
            pl => 'Degrees Celsius',
        },
        tmpl => '%value%%symbol%',
    },

    f => {
        ref_base => 2,
        symbol   => chr(0xC2) . chr(0xB0) . 'F',
        suffix   => 'F',
        txt      => {
            de => 'Grad Fahrenheit',
            en => 'Degree Fahrenheit',
            fr => 'Degree Fahrenheit',
            nl => 'Degree Fahrenheit',
            pl => 'Degree Fahrenheit',
        },
        tmpl => '%value% %symbol%',
    },

    k => {
        ref_base => 2,
        suffix   => 'K',
        txt      => {
            de => 'Kelvin',
            en => 'Kelvin',
            fr => 'Kelvin',
            nl => 'Kelvin',
            pl => 'Kelvin',
        },
    },

    # pressure
    bar => {
        ref_base => 10,
        scale_m  => '1.0e0',
        suffix   => 'bar',
        txt      => {
            de => 'Bar',
            en => 'Bar',
            fr => 'Bar',
            nl => 'Bar',
            pl => 'Bar',
        },
    },

    mbar => {
        ref     => 'bar',
        scale_m => '1.0e-3',
    },

    pa => {
        ref_base => 10,
        scale_m  => '1.0e0',
        suffix   => 'Pa',
        txt      => {
            de => 'Pascal',
            en => 'Pascal',
            fr => 'Pascal',
            nl => 'Pascal',
            pl => 'Pascal',
        },
    },

    hpa => {
        ref     => 'pa',
        scale_m => '1.0e2',
    },

    pamb => {
        ref_base => 12,
        scale_m  => '1.0e0',
        suffix   => 'Pa',
        txt      => {
            de => 'Pascal',
            en => 'Pascal',
            fr => 'Pascal',
            nl => 'Pascal',
            pl => 'Pascal',
        },
    },

    hpamb => {
        ref     => 'pamb',
        scale_m => '1.0e2',
    },

    inhg => {
        ref_base => 12,
        suffix   => 'inHg',
        txt      => {
            de => 'Zoll Quecksilbersäule',
            en => 'Inches of Mercury',
            fr => 'Inches of Mercury',
            nl => 'Inches of Mercury',
            pl => 'Inches of Mercury',
        },
    },

    mmhg => {
        ref_base => 12,
        suffix   => 'mmHg',
        txt      => {
            de => 'Millimeter Quecksilbersäule',
            en => 'Milimeter of Mercury',
            fr => 'Milimeter of Mercury',
            nl => 'Milimeter of Mercury',
            pl => 'Milimeter of Mercury',
        },
    },

    # length
    km => {
        ref     => 'm',
        scale_m => '1.0e3',
    },

    hm => {
        ref     => 'm',
        scale_m => '1.0e2',
    },

    dam => {
        ref     => 'm',
        scale_m => '1.0e1',
    },

    m => {
        ref_base => 0,
        scale_m  => '1.0e0',
        suffix   => 'm',
        txt      => {
            de => 'Meter',
            en => 'meter',
            fr => 'meter',
            nl => 'meter',
            pl => 'meter',
        },
    },

    dm => {
        ref     => 'm',
        scale_m => '1.0e-1',
    },

    cm => {
        ref     => 'm',
        scale_m => '1.0e-2',
    },

    mm => {
        ref     => 'm',
        scale_m => '1.0e-3',
    },

    um => {
        ref     => 'm',
        scale_m => '1.0e-6',
    },

    nm => {
        ref     => 'm',
        scale_m => '1.0e-9',
    },

    pm => {
        ref     => 'm',
        scale_m => '1.0e-12',
    },

    fm => {
        ref     => 'm',
        scale_m => '1.0e-15',
    },

    in => {
        ref_base => 4,
        symbol   => '″',
        suffix   => 'in',
        txt      => {
            de => 'Zoll',
            en => 'inch',
            fr => 'inch',
            nl => 'inch',
            pl => 'inch',
        },
        txt_pl => {
            de => 'Zoll',
            en => 'inches',
            fr => 'inches',
            nl => 'inches',
            pl => 'inches',
        },
        tmpl         => '%value%%symbol%',
        tmpl_long    => '%value% %txt%',
        tmpl_long_pl => '%value% %txt_pl%',
    },

    ft => {
        ref_base => 0,
        symbol   => '′',
        suffix   => 'ft',
        txt      => {
            de => 'Fuss',
            en => 'foot',
            fr => 'foot',
            nl => 'foot',
            pl => 'foot',
        },
        txt_pl => {
            de => 'Fuss',
            en => 'feet',
            fr => 'feet',
            nl => 'feet',
            pl => 'feet',
        },
        tmpl         => '%value%%symbol%',
        tmpl_long    => '%value% %txt%',
        tmpl_long_pl => '%value% %txt_pl%',
    },

    yd => {
        ref_base => 0,
        suffix   => 'yd',
        txt      => {
            de => 'Yard',
            en => 'yard',
            fr => 'yard',
            nl => 'yard',
            pl => 'yard',
        },
        txt_pl => {
            de => 'Yards',
            en => 'yards',
            fr => 'yards',
            nl => 'yards',
            pl => 'yards',
        },
    },

    mi => {
        ref_base => 0,
        suffix   => 'mi',
        txt      => {
            de => 'Meilen',
            en => 'miles',
            fr => 'miles',
            nl => 'miles',
            pl => 'miles',
        },
    },

    # time
    sec => {
        ref_base => 2,
        scale_t  => '1',
        suffix   => {
            de => 's',
            en => 's',
            fr => 's',
            nl => 'sec',
            pl => 'sec',
        },
        txt => {
            de => 'Sekunde',
            en => 'second',
            fr => 'second',
            nl => 'second',
            pl => 'second',
        },
        txt_pl => {
            de => 'Sekunden',
            en => 'seconds',
            fr => 'seconds',
            nl => 'seconds',
            pl => 'seconds',
        },
    },

    min => {
        ref_base => 2,
        scale_t  => '60',
        suffix   => {
            de => 'Min',
            en => 'min',
            fr => 'min',
            nl => 'min',
            pl => 'min',
        },
        txt => {
            de => 'Minute',
            en => 'minute',
            fr => 'minute',
            nl => 'minute',
            pl => 'minute',
        },
        txt_pl => {
            de => 'Minuten',
            en => 'minutes',
            fr => 'minutes',
            nl => 'minutes',
            pl => 'minutes',
        },
    },

    hr => {
        ref_base => 2,
        scale_t  => '3600',
        suffix   => 'h',
        txt      => {
            de => 'Stunde',
            en => 'hour',
            fr => 'hour',
            nl => 'hour',
            pl => 'hour',
        },
        txt_pl => {
            de => 'Stunden',
            en => 'hours',
            fr => 'hours',
            nl => 'hours',
            pl => 'hours',
        },
    },

    d => {
        ref_base => 2,
        scale_t  => '86400',
        suffix   => {
            de => 'T',
            en => 'd',
            fr => 'd',
            nl => 'd',
            pl => 'd',
        },
        txt => {
            de => 'Tag',
            en => 'day',
            fr => 'day',
            nl => 'day',
            pl => 'day',
        },
        txt_pl => {
            de => 'Tage',
            en => 'days',
            fr => 'days',
            nl => 'days',
            pl => 'days',
        },
    },

    w => {
        ref_base => 2,
        scale_t  => '604800',
        suffix   => {
            de => 'W',
            en => 'w',
            fr => 'w',
            nl => 'w',
            pl => 'w',
        },
        txt => {
            de => 'Woche',
            en => 'week',
            fr => 'week',
            nl => 'week',
            pl => 'week',
        },
        txt_pl => {
            de => 'Wochen',
            en => 'weeks',
            fr => 'weeks',
            nl => 'weeks',
            pl => 'weeks',
        },
    },

    mon => {
        ref_base => 2,
        scale_t  => '2592000',
        suffix   => {
            de => 'M',
            en => 'm',
            fr => 'm',
            nl => 'm',
            pl => 'm',
        },
        txt => {
            de => 'Monat',
            en => 'month',
            fr => 'month',
            nl => 'month',
            pl => 'month',
        },
        txt_pl => {
            de => 'Monate',
            en => 'Monat',
            fr => 'Monat',
            nl => 'Monat',
            pl => 'Monat',
        },
    },

    y => {
        ref_base => 2,
        scale_t  => '31536000',
        suffix   => {
            de => 'J',
            en => 'y',
            fr => 'y',
            nl => 'y',
            pl => 'y',
        },
        txt => {
            de => 'Jahr',
            en => 'year',
            fr => 'year',
            nl => 'year',
            pl => 'year',
        },
        txt_pl => {
            de => 'Jahre',
            en => 'years',
            fr => 'years',
            nl => 'years',
            pl => 'years',
        },
    },

    # speed
    bft => {
        ref_base => 15,
        suffix   => 'bft',
        txt      => {
            de => 'Windstärke',
            en => 'wind force',
            fr => 'wind force',
            nl => 'wind force',
            pl => 'wind force',
        },
        tmpl_long => '%txt% %value%',
    },

    kn => {
        ref_base => 15,
        suffix   => 'kn',
        txt      => {
            de => 'Knoten',
            en => 'knots',
            fr => 'knots',
            nl => 'knots',
            pl => 'knots',
        },
    },

    fts => {
        ref_base  => 15,
        ref       => 'ft',
        ref_t     => 'sec',
        tmpl      => '%value% %suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    mph => {
        ref_base  => 15,
        ref       => 'mi',
        ref_t     => 'hr',
        tmpl      => '%value% %suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    kmh => {
        ref_base  => 15,
        ref       => 'm',
        ref_t     => 'hr',
        scale_m   => '1.0e3',
        tmpl      => '%value% %suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    mps => {
        ref_base  => 15,
        ref       => 'm',
        ref_t     => 'sec',
        scale_m   => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    # weight
    mol => {
        ref_base => 5,
        suffix   => 'mol',
    },

    pg => {
        ref     => 'g',
        scale_m => "1.0e-12",
    },

    ng => {
        ref     => 'g',
        scale_m => "1.0e-9",
    },

    ug => {
        ref     => 'g',
        scale_m => "1.0e-6",
    },

    mg => {
        ref     => 'g',
        scale_m => "1.0e-3",
    },

    cg => {
        ref     => 'g',
        scale_m => "1.0e-2",
    },

    dg => {
        ref     => 'g',
        scale_m => "1.0e-1",
    },

    g => {
        ref_base => 1,
        scale_m  => "1.0e0",
        suffix   => 'g',
        txt      => {
            de => 'Gramm',
            en => 'gram',
            fr => 'gram',
            nl => 'gram',
            pl => 'gram',
        },
    },

    kg => {
        ref     => 'g',
        scale_m => "1.0e3",
    },

    t => {
        ref     => 'g',
        scale_m => "1.0e6",
        suffix  => 't',
        txt     => {
            de => 'Tonne',
            en => 'ton',
            fr => 'ton',
            nl => 'ton',
            pl => 'ton',
        },
        txt_pl => {
            de => 'Tonnen',
            en => 'tons',
            fr => 'tons',
            nl => 'tons',
            pl => 'tons',
        },
    },

    lb => {
        ref_base => 1,
        suffix   => 'lb',
        txt      => {
            de => 'Pfund',
            en => 'pound',
            fr => 'pound',
            nl => 'pound',
            pl => 'pound',
        },
    },

    lbs => {
        ref_base => 1,
        suffix   => 'lbs',
        txt      => {
            de => 'Pfund',
            en => 'pound',
            fr => 'pound',
            nl => 'pound',
            pl => 'pound',
        },
    },

    # luminous intensity
    cd => {
        ref_base => 6,
        suffix   => 'cd',
        txt      => {
            de => 'Candela',
            en => 'Candela',
            fr => 'Candela',
            nl => 'Candela',
            pl => 'Candela',
        },
    },

    # illumination intensity
    lx => {
        ref_base => 16,
        suffix   => 'lx',
        txt      => {
            de => 'Lux',
            en => 'Lux',
            fr => 'Lux',
            nl => 'Lux',
            pl => 'Lux',
        },
    },

    # luminous flux
    lm => {
        ref_base => 17,
        suffix   => 'lm',
        txt      => {
            de => 'Lumen',
            en => 'Lumen',
            fr => 'Lumen',
            nl => 'Lumen',
            pl => 'Lumen',
        },
    },

    uvi => {
        suffix => 'UVI',
        txt    => {
            de => 'UV-Index',
            en => 'UV-Index',
            fr => 'UV-Index',
            nl => 'UV-Index',
            pl => 'UV-Index',
        },
        tmpl         => '%suffix% %value%',
        tmpl_long    => '%txt% %value%',
        tmpl_long_pl => '%txt% %value%',
    },

    # volume
    cm3 => {
        ref_base => 18,
        ref      => 'm',
        scale_cu => '1.0e-2',
    },

    m3 => {
        ref_base => 18,
        ref      => 'm',
        scale_cu => '1.0e0',
    },

    ml => {
        ref     => 'l',
        scale_m => '1.0e-3',
    },

    l => {
        ref_base => 18,
        suffix   => 'l',
        txt      => {
            de => 'Liter',
            en => 'liter',
            fr => 'liter',
            nl => 'liter',
            pl => 'liter',
        },
        txt_pl => {
            de => 'Liter',
            en => 'liters',
            fr => 'liters',
            nl => 'liters',
            pl => 'liters',
        },
    },

    hl => {
        ref     => 'l',
        scale_m => '1.0e2',
    },

    b => {
        ref_base => 19,
        scale_m  => '1.0e0',
        suffix   => 'B',
        txt      => {
            de => 'Bel',
            en => 'Bel',
            fr => 'Bel',
            nl => 'Bel',
            pl => 'Bel',
        },
    },

    db => {
        ref     => 'b',
        scale_m => '1.0e-1',
    },

    ua => {
        ref     => 'a',
        scale_m => '1.0e-6',
    },

    ma => {
        ref     => 'a',
        scale_m => '1.0e-3',
    },

    a => {
        ref_base => 3,
        scale_m  => '1.0e0',
        suffix   => 'A',
        txt      => {
            de => 'Ampere',
            en => 'Ampere',
            fr => 'Ampere',
            nl => 'Ampere',
            pl => 'Ampere',
        },
    },

    uv => {
        ref     => 'v',
        scale_m => '1.0e-6',
    },

    mv => {
        ref     => 'v',
        scale_m => '1.0e-3',
    },

    v => {
        ref_base => 13,
        scale_m  => '1.0e0',
        suffix   => 'V',
        txt      => {
            de => 'Volt',
            en => 'Volt',
            fr => 'Volt',
            nl => 'Volt',
            pl => 'Volt',
        },
    },

    uj => {
        ref     => 'j',
        scale_m => '1.0e-6',
    },

    mj => {
        ref     => 'j',
        scale_m => '1.0e-3',
    },

    j => {
        ref_base => 7,
        scale_m  => '1.0e0',
        suffix   => 'J',
        txt      => {
            de => 'Joule',
            en => 'Joule',
            fr => 'Joule',
            nl => 'Joule',
            pl => 'Joule',
        },
    },

    uw => {
        ref     => 'j',
        scale_m => '1.0e-6',
    },

    mw => {
        ref     => 'j',
        scale_m => '1.0e-3',
    },

    w => {
        ref_base => 9,
        scale_m  => '1.0e0',
        suffix   => 'Watt',
        txt      => {
            de => 'Watt',
            en => 'Watt',
            fr => 'Watt',
            nl => 'Watt',
            pl => 'Watt',
        },
    },

    va => {
        ref => 'w',
    },

    uwpscm => {
        ref       => 'w',
        scale_m   => '1.0e-6',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    uwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-6',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    mwpscm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    mwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    wpscm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    wpsm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_t%',
            en => '%value% %txt% per %txt_t%',
            fr => '%value% %txt% per %txt_t%',
            nl => '%value% %txt% per %txt_t%',
            pl => '%value% %txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_t%',
            en => '%value% %txt_pl% per %txt_t%',
            fr => '%value% %txt_pl% per %txt_t%',
            nl => '%value% %txt_pl% per %txt_t%',
            pl => '%value% %txt_pl% per %txt_t%',
        },
    },

    coul => {
        ref_base => 20,
        suffix   => 'C',
        txt      => {
            de => 'Coulomb',
            en => 'Coulomb',
            fr => 'Coulomb',
            nl => 'Coulomb',
            pl => 'Coulomb',
        },
    },

    far => {
        ref_base => 21,
        suffix   => 'F',
        txt      => {
            de => 'Farad',
            en => 'Farad',
            fr => 'Farad',
            nl => 'Farad',
            pl => 'Farad',
        },
    },

    ohm => {
        ref_base => 22,
        symbol   => 'Ω',
        suffix   => 'Ohm',
        txt      => {
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
              $details->{txt_base}
            ? $details->{txt_base}
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
        $details{abbr} = $u;

        foreach ( 'ref', 'ref_t', 'ref_sq', 'ref_cu' ) {
            my $suffix = $_;
            $suffix =~ s/^[a-z]+//;
            if ( defined( $details{$_} ) ) {
                my $ref = $details{$_};
                if ( !defined( $unitsDB{$ref} ) ) {
                    ::Log 1, "Unit::GetDetails($unit) broken reference $_";
                    next;
                }
                foreach my $k ( keys %{ $unitsDB{$ref} } ) {
                    next
                      if ( $k =~ /^scale/ )
                      ;    # exclude scales from referenced unit
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

        if ( $details{scale_m} ) {
            my $ref = $details{scale_m};
            foreach my $k ( keys %{ $scales_m{$ref} } ) {
                $details{$k} = $scales_m{$ref}{$k}
                  if ( !defined( $details{$k} ) );
            }
        }
        if ( $details{scale_sq} ) {
            foreach my $k ( keys %scales_sq ) {
                $details{$k} = $scales_sq{$k}
                  if ( !defined( $details{$k} ) );
            }
        }
        if ( $details{scale_cu} ) {
            foreach my $k ( keys %scales_cu ) {
                $details{$k} = $scales_cu{$k}
                  if ( !defined( $details{$k} ) );
            }
        }

        if ( $details{ref_base} ) {
            my $ref = $details{ref_base};
            foreach my $k ( keys %{ $unit_base{$ref} } ) {
                $details{$k} = $unit_base{$ref}{$k}
                  if ( !defined( $details{$k} ) );
            }
        }

        if ($lang) {
            $details{lang} = $l;
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

            $details{suffix} = $details{scale_txt_m} . $details{suffix}
              if ( $details{suffix} && $details{scale_txt_m} );
            $details{txt} = $details{scale_txt_long_m} . lc( $details{txt} )
              if ( $details{txt} && $details{scale_txt_long_m} );

            $details{unit_sq} = $details{unit_sq} . $details{scale_txt_sq}
              if ( $details{unit_sq} && $details{scale_txt_sq} );
            $details{txt_sq} =
              $details{scale_txt_long_sq} . lc( $details{txt_sq} )
              if ( $details{txt_sq} && $details{scale_txt_long_sq} );

            $details{unit_cu} = $details{unit_cu} . $details{scale_txt_cu}
              if ( $details{unit_cu} && $details{scale_txt_cu} );
            $details{txt_cu} =
              $details{scale_txt_long_cu} . lc( $details{txt_cu} )
              if ( $details{txt_cu} && $details{scale_txt_long_cu} );
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
    if ( $readingsDB{$r}{unified} ) {
        my $dr = $readingsDB{$r}{unified};
        $return{unified} = $dr;
        $return{short}   = $readingsDB{$dr}{short};
        $u               = (
              $readingsDB{$dr}{unit}
            ? $readingsDB{$dr}{unit}
            : "-"
        );
    }

    # known standard reading names
    elsif ( $readingsDB{$r}{short} ) {
        $return{unified} = $reading;
        $return{short}   = $readingsDB{$r}{short};
        $u               = (
              $readingsDB{$r}{unit}
            ? $readingsDB{$r}{unit}
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
        $return{unified}    = $reading if ( !$return{unified} );
        $return{unit_guess} = "1"      if ( !$return{short} );
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
    my $details = GetDetails( $unit, $l );
    my $txt;
    return $value if ( !$details->{suffix} && !$details->{symbol} );

    $details->{value} = $value;

    # long plural
    if (   $format
        && Scalar::Util::looks_like_number($value)
        && $value > 1
        && $details->{txt_pl} )
    {
        $txt = '%value% %txt_pl%';
        $txt = $details->{tmpl_long_pl}
          if ( $details->{tmpl_long_pl} );
    }

    # long singular
    elsif ( $format && $details->{txt} ) {
        $txt = '%value% %txt%';
        $txt = $details->{tmpl_long}
          if ( $details->{tmpl_long} );
    }

    # short
    else {
        $txt = '%value% %suffix%';
        $txt = $details->{tmpl} if ( $details->{tmpl} );
    }

    foreach my $k ( keys %{$details} ) {
        $txt =~ s/%$k%/$details->{$k}/g;
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

#TODO rename
sub numeric {
    my $obj = shift;

    no warnings "numeric";
    return length( $obj & "" );
}

1;
