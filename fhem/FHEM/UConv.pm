###############################################################################
# $Id$
package main;
sub UConv_Initialize() { }

package UConv;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);
use Data::Dumper;

####################
# Translations

our %compasspointss = (
    en => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    de => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    nl => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
        'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
    ],
    fr => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
    ],
    pl => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
);

our %hr_formats = (

    # 1 234 567.89
    std => {
        delim => "\x{2009}",
        sep   => ".",
    },

    # 1 234 567,89
    'std-fr' => {
        delim => "\x{2009}",
        sep   => ",",
    },

    # 1,234,567.89
    'old-english' => {
        delim => ",",
        sep   => ".",
    },

    # 1.234.567,89
    'old-european' => {
        delim => ".",
        sep   => ",",
    },

    # 1'234'567.89
    ch => {
        delim => "'",
        sep   => ".",
    },

    ### lang ref ###
    #

    en => {
        ref => "std",
    },

    de => {
        ref => "std-fr",
    },

    de_at => {
        ref => "std-fr",
        min => 4,
    },

    de_ch => {
        ref => "std",
    },

    nl => {
        ref => "std-fr",
    },

    fr => {
        ref => "std-fr",
    },

    pl => {
        ref => "std-fr",
    },

    ### number ref ###
    #

    0 => {
        ref => "std",
    },
    1 => {
        ref => "std-fr",
    },
    2 => {
        ref => "old-english",
    },
    3 => {
        ref => "old-european",
    },
    4 => {
        ref => "ch",
    },
    5 => {
        ref => "std-fr",
        min => 4,
    },

);

our %daytimes = (
    en => [
        "morning", "midmorning", "noon", "afternoon",
        "evening", "midevening", "night",
    ],
    de => [
        "Morgen",   "Vormittag", "Mittag", "Nachmittag",
        "Vorabend", "Abend",     "Nacht",
    ],
    icons => [
        "weather_sunrise", "scene_day",
        "weather_sun",     "weather_summer",
        "weather_sunset",  "scene_night",
        "weather_moon_phases_8",
    ],
);

our %sdt2daytimes = (

    # User overwrite format:
    # <SeasonSrc><SeasonIndex><DST><daytimeStage>:<daytime>
    # M000:0
    # M001:0
    # M002:0
    # M003:1
    # M004:1
    # M005:2
    # M006:2
    # M007:3
    # M008:3
    # M009:3
    # M0010:3
    # M0011:4
    # M0012:5
    #
    # M010:0
    # M011:0
    # M012:0
    # M013:1
    # M014:1
    # M015:2
    # M016:2
    # M017:3
    # M018:3
    # M019:3
    # M0110:3
    # M0111:4
    # M0112:5

    # SPRING SEASON
    0 => {

        # DST = no
        0 => {
            1  => 0,
            4  => 1,
            6  => 2,
            8  => 3,
            12 => 4,
        },

        # DST = yes
        1 => {
            1  => 0,
            4  => 1,
            6  => 2,
            8  => 3,
            12 => 4,
        },
    },

    # SUMMER SEASON
    1 => {

        # DST = yes
        1 => {
            1  => 0,
            4  => 1,
            6  => 2,
            7  => 3,
            10 => 4,
            12 => 5,
        }
    },

    # AUTUMN SEASON
    2 => {

        # DST = no
        0 => {
            1  => 0,
            4  => 1,
            6  => 2,
            7  => 3,
            11 => 4,
        },

        # DST = yes
        1 => {
            1  => 0,
            4  => 1,
            6  => 2,
            7  => 3,
            11 => 4,
        },
    },

    # WINTER SEASON
    3 => {

        # DST = no
        0 => {
            1 => 0,
            3 => 1,
            6 => 2,
            8 => 3,

            #            12 => 4,
        },
    },
);

our %seasons = (
    en    => [ "Spring",    "Summer", "Autumn", "Winter", ],
    de    => [ "Frühling", "Sommer", "Herbst", "Winter", ],
    pheno => [ 2,           4,        7,        9 ],
);

our %seasonsPheno = (
    en => [
        "Early Spring",
        "First Spring",
        "Spring",
        "Early Summer",
        "Summer",
        "Late Summer",
        "Early Autumn",
        "Autumn",
        "Late Autumn",
        "Winter",
    ],
    de => [
        "Vorfrühling", "Erstfrühling", "Vollfrühling", "Frühsommer",
        "Hochsommer",   "Spätsommer",   "Frühherbst",   "Vollherbst",
        "Spätherbst",  "Winter",
    ],
);

our %dst = (
    en => [ "standard",   "daylight" ],
    de => [ "Normalzeit", "Sommerzeit" ],
);

our %daystages = (
    en => [ "weekday",   "weekend",    "holiday",  "vacation", ],
    de => [ "Wochentag", "Wochenende", "Feiertag", "Urlaubstag", ],
);

our %reldays = (
    en => [ "yesterday", "today", "tomorrow" ],
    de => [ "Gestern",   "Heute", "Morgen" ],
);

our %monthss = (
    en => [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
        "Sep", "Oct", "Nov", "Dec", "Jan"
    ],
    de => [
        "Jan", "Feb", "Mar", "Apr", "Mai", "Jun", "Jul", "Aug",
        "Sep", "Okt", "Nov", "Dez", "Jan"
    ],
);

our %months = (
    en => [
        "January",   "Febuary", "March",    "April",
        "May",       "June",    "July",     "August",
        "September", "October", "November", "December",
        "January"
    ],
    de => [
        "Januar",    "Februar", "März",    "April",
        "Mai",       "Juni",    "Juli",     "August",
        "September", "Oktober", "November", "Dezember",
        "Januar"
    ],
);

our %dayss = (
    en => [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" ],
    de => [ "So",  "Mo",  "Di",  "Mi",  "Do",  "Fr",  "Sa",  "So" ],
);

our %days = (
    en => [
        "Sunday",   "Monday", "Tuesday",  "Wednesday",
        "Thursday", "Friday", "Saturday", "Sunday"
    ],
    de => [
        "Sonntag",    "Montag",  "Dienstag", "Mittwoch",
        "Donnerstag", "Freitag", "Samstag",  "Sonntag"
    ],
);

our %dateformats = (
    en => '%wday_long%, %mon_long% %mday%',
    de => '%wday_long%, %mday%. %mon_long%',
);

our %dateformatss = (
    en => '%mon_long% %mday%',
    de => '%mday%. %mon_long%',
);

#################################
### Inner metric conversions
###

# Temperature: convert Celsius to Kelvin
sub c2k($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data + 273.15, $rnd );
}

# Temperature: convert Kelvin to Celsius
sub k2c($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data - 273.15, $rnd );
}

# Speed: convert km/h (kilometer per hour) to m/s (meter per second)
sub kph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data / 3.6, $rnd );
}

# Speed: convert m/s (meter per second) to km/h (kilometer per hour)
sub mps2kph($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 3.6, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to mmHg (milimeter of Mercury)
sub hpa2mmhg($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.00750061561303, $rnd );
}

#################################
### Metric to angloamerican conversions
###

# Temperature: convert Celsius to Fahrenheit
sub c2f($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 1.8 + 32, $rnd );
}

# Temperature: convert Kelvin to Fahrenheit
sub k2f($;$) {
    my ( $data, $rnd ) = @_;
    return _round( ( $data - 273.15 ) * 1.8 + 32, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to in (inches of Mercury)
sub hpa2inhg($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.02952998751, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to PSI (Pound force per square inch)
sub hpa2psi($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 100.00014504, $rnd );
}

# Speed: convert km/h (kilometer per hour) to mph (miles per hour)
sub kph2mph($;$) {
    return km2mi(@_);
}

# Speed: convert m/s (meter per seconds) to mph (miles per hour)
sub mps2mph($;$) {
    my ( $data, $rnd ) = @_;
    return _round( kph2mph( mps2kph( $data, 9 ), 9 ), $rnd );
}

# Length: convert mm (milimeter) to in (inch)
sub mm2in($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.039370, $rnd );
}

# Length: convert cm (centimeter) to in (inch)
sub cm2in($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.39370, $rnd );
}

# Length: convert m (meter) to ft (feet)
sub m2ft($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 3.2808, $rnd );
}

# Length: convert km (kilometer) to miles (mi)
sub km2mi($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.621371192, $rnd );
}

#################################
### Inner Angloamerican conversions
###

# Speed: convert mph (miles per hour) to ft/s (feet per second)
sub mph2fts($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 1.467, $rnd );
}

# Speed: convert ft/s (feet per second) to mph (miles per hour)
sub fts2mph($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data / 1.467, $rnd );
}

#################################
### Angloamerican to Metric conversions
###

# Temperature: convert Fahrenheit to Celsius
sub f2c($;$) {
    my ( $data, $rnd ) = @_;
    return _round( ( $data - 32 ) * 0.5556, $rnd );
}

# Temperature: convert Fahrenheit to Kelvin
sub f2k($;$) {
    my ( $data, $rnd ) = @_;
    return _round( ( $data - 32 ) / 1.8 + 273.15, $rnd );
}

# Pressure: convert in (inches of Mercury) to hPa (hecto Pascal)
sub inhg2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 33.8638816, $rnd );
}

# Pressure: convert PSI (Pound force per square inch) to hPa (hecto Pascal)
sub psi2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data / 100.00014504, $rnd );
}

# Speed: convert mph (miles per hour) to km/h (kilometer per hour)
sub mph2kph($;$) {
    return mi2km(@_);
}

# Speed: convert mph (miles per hour) to m/s (meter per seconds)
sub mph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return _round( kph2mps( mph2kph( $data, 9 ), 9 ), $rnd );
}

# Length: convert in (inch) to mm (milimeter)
sub in2mm($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 25.4, $rnd );
}

# Length: convert in (inch) to cm (centimeter)
sub in2cm($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data / 0.39370, $rnd );
}

# Length: convert ft (feet) to m (meter)
sub ft2m($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data / 3.2808, $rnd );
}

# Length: convert mi (miles) to km (kilometer)
sub mi2km($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 1.609344, $rnd );
}

#################################
### Angular conversions
###

# convert direction in degree to point of the compass
sub direction2compasspoint($;$) {
    my ( $azimuth, $lang ) = @_;
    my $directions_txt_i18n;

    $lang = $main::attr{global}{language} ? $main::attr{global}{language} : "EN"
      unless ($lang);

    if ( $lang && defined( $compasspointss{ lc($lang) } ) ) {
        $directions_txt_i18n = $compasspointss{ lc($lang) };
    }
    else {
        $directions_txt_i18n = $compasspointss{en};
    }

    return @$directions_txt_i18n[
      int( ( ( $azimuth + 11.25 ) % 360 ) / 22.5 )
    ];
}

#################################
### Solar conversions
###

# Power: convert uW/cm2 (micro watt per square centimeter) to UV-Index
sub uwpscm2uvi($;$) {
    my ( $data, $rnd ) = @_;

    return 0 unless ($data);

    # Forum topic,44403.msg501704.html#msg501704
    return int( ( $data - 100 ) / 450 + 1 ) unless ( defined($rnd) );

    $rnd = 0 unless ( defined($rnd) );
    return _round( ( ( $data - 100 ) / 450 + 1 ), $rnd );
}

# Power: convert UV-Index to uW/cm2 (micro watt per square centimeter)
sub uvi2uwpscm($) {
    my ($data) = @_;

    return 0 unless ($data);
    return ( $data * ( 450 + 1 ) ) + 100;
}

# Power: convert lux to W/m2 (watt per square meter)
sub lux2wpsm($;$) {
    my ( $data, $rnd ) = @_;

    # Forum topic,44403.msg501704.html#msg501704
    return _round( $data / 126.7, $rnd );
}

# Power: convert W/m2 to lux
sub wpsm2lux($;$) {
    my ( $data, $rnd ) = @_;

    # Forum topic,44403.msg501704.html#msg501704
    return _round( $data * 126.7, $rnd );
}

#################################
### Nautic unit conversions
###

# Speed: convert smi (statute miles) to nmi (nautical miles)
sub smi2nmi($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.8684, $rnd );
}

# Speed: convert km (kilometer) to nmi (nautical miles)
sub km2nmi($;$) {
    my ( $data, $rnd ) = @_;
    return _round( smi2nmi( km2mi( $data, 9 ), 9 ), $rnd );
}

# Speed: convert km/h to knots
sub kph2kn($;$) {
    my ( $data, $rnd ) = @_;
    return _round( $data * 0.539956803456, $rnd );
}

# Speed: convert km/h to Beaufort wind force scale
sub kph2bft($) {
    my ($data) = @_;
    my $val = "0";

    if ( $data >= 118 ) {
        $val = "12";
    }
    elsif ( $data >= 103 ) {
        $val = "11";
    }
    elsif ( $data >= 89 ) {
        $val = "10";
    }
    elsif ( $data >= 75 ) {
        $val = "9";
    }
    elsif ( $data >= 62 ) {
        $val = "8";
    }
    elsif ( $data >= 50 ) {
        $val = "7";
    }
    elsif ( $data >= 39 ) {
        $val = "6";
    }
    elsif ( $data >= 29 ) {
        $val = "5";
    }
    elsif ( $data >= 20 ) {
        $val = "4";
    }
    elsif ( $data >= 12 ) {
        $val = "3";
    }
    elsif ( $data >= 6 ) {
        $val = "2";
    }
    elsif ( $data >= 1 ) {
        $val = "1";
    }

    if (wantarray) {
        my ( $cond, $rgb, $warn ) = bft2condition($val);
        return ( $val, $rgb, $cond, $warn );
    }
    return $val;
}

# Speed: convert mph (miles per hour) to Beaufort wind force scale
sub mph2bft($) {
    my ($data) = @_;
    my $val = "0";

    if ( $data >= 73 ) {
        $val = "12";
    }
    elsif ( $data >= 64 ) {
        $val = "11";
    }
    elsif ( $data >= 55 ) {
        $val = "10";
    }
    elsif ( $data >= 47 ) {
        $val = "9";
    }
    elsif ( $data >= 39 ) {
        $val = "8";
    }
    elsif ( $data >= 32 ) {
        $val = "7";
    }
    elsif ( $data >= 25 ) {
        $val = "6";
    }
    elsif ( $data >= 19 ) {
        $val = "5";
    }
    elsif ( $data >= 13 ) {
        $val = "4";
    }
    elsif ( $data >= 8 ) {
        $val = "3";
    }
    elsif ( $data >= 4 ) {
        $val = "2";
    }
    elsif ( $data >= 1 ) {
        $val = "1";
    }

    if (wantarray) {
        my ( $cond, $rgb, $warn ) = bft2condition($val);
        return ( $val, $rgb, $cond, $warn );
    }
    return $val;
}

#################################
### Differential conversions
###

sub distance($$$$;$$) {
    my ( $lat1, $lng1, $lat2, $lng2, $rnd, $unit ) = @_;
    return "0.0" if ( $lat1 eq $lat2 && $lng1 eq $lng2 );

    use constant M_PI => 4 * atan2( 1, 1 );
    my $pi80 = M_PI / 180;
    $lat1 *= $pi80;
    $lng1 *= $pi80;
    $lat2 *= $pi80;
    $lng2 *= $pi80;

    my $r    = 6372.797;        # mean radius of Earth in km
    my $dlat = $lat2 - $lat1;
    my $dlng = $lng2 - $lng1;
    my $a =
      sin( $dlat / 2 ) * sin( $dlat / 2 ) +
      cos($lat1) * cos($lat2) * sin( $dlng / 2 ) * sin( $dlng / 2 );
    my $c = 2 * atan2( sqrt($a), sqrt( 1 - $a ) );
    my $km = $r * $c;

    return _round(
        ( $unit eq "nmi" ? km2nmi($km) : ( $unit ? km2mi($km) : $km ) ), $rnd );
}

#################################
### Textual unit conversions
###

######## humanReadable #########################################
# What  : Formats a number or text string to be more readable for humans
# Syntax: { humanReadable( <value>, [ <format> ] ) }
# Call  : { humanReadable(102345.6789) }
#         { humanReadable(102345.6789, 3) }
#         { humanReadable(102345.6789, "DE") }
#         { humanReadable(102345.6789, "si-fr") }
#         { humanReadable(102345.6789, {
#                      group=>3, delim=>".", sep=>"," } ) }
#         { humanReadable("DE44500105175407324931", {
#                      group=>4, rev=>0 } ) }
# Source: https://en.wikipedia.org/wiki/Decimal_mark
#         https://de.wikipedia.org/wiki/Schreibweise_von_Zahlen
#         https://de.wikipedia.org/wiki/Dezimaltrennzeichen
#         https://de.wikipedia.org/wiki/Zifferngruppierung
sub humanReadable($;$) {
    my ( $v, $f ) = @_;
    my $l =
      $main::attr{global}{humanReadable} ? $main::attr{global}{humanReadable}
      : (
        $main::attr{global}{language} ? $main::attr{global}{language}
        : "EN"
      );

    my $h =
      !$f || ref($f) || !$hr_formats{$f} ? $f
      : (
          $hr_formats{$f}{ref} ? $hr_formats{ $hr_formats{$f}{ref} }
        : $hr_formats{$f}
      );
    my $min =
      ref($h)
      && defined( $h->{min} )
      ? $h->{min}
      : ( !ref($f) && $hr_formats{$f}{min} ? $hr_formats{$f}{min} : 5 );
    my $group =
      ref($h)
      && defined( $h->{group} )
      ? $h->{group}
      : ( !ref($f) && $hr_formats{$f}{group} ? $hr_formats{$f}{group} : 3 );
    my $delim =
      ref($h)
      && $h->{delim}
      ? $h->{delim}
      : $hr_formats{ ( $l =~ /^de|nl|fr|pl/i ? "std-fr" : "std" ) }{delim};
    my $sep =
      ref($h)
      && $h->{sep}
      ? $h->{sep}
      : $hr_formats{ ( $l =~ /^de|nl|fr|pl/i ? "std-fr" : "std" ) }{sep};
    my $reverse = ref($h) && defined( $h->{rev} ) ? $h->{rev} : 1;

    my @p = split( /\./, $v, 2 );

    if ( length( $p[0] ) < $min && length( $p[1] ) < $min ) {
        $v =~ s/\./$sep/g;
        return $v;
    }

    $v =~ s/\./\*/g;

    # digits after thousands separator
    if ( ( $delim eq "\x{202F}" || $delim eq " " )
        && length( $p[1] ) >= $min )
    {
        $v =~ s/(\w{$group})(?=\w)(?!\w*\*)/$1$delim/g;
    }

    # digits before thousands separator
    if ( length( $p[0] ) >= $min ) {
        $v = reverse $v if ($reverse);
        $v =~ s/(\w{$group})(?=\w)(?!\w*\*)/$1$delim/g;
        if ($reverse) {
            $v =~ s/\*/$sep/g;
            return scalar reverse $v;
        }
    }

    $v =~ s/\*/$sep/g;
    return $v;
}

# ######## machineReadable #########################################
# # What  : find the first matching number in a string and make it
# #         machine readable.
# # Syntax: { machineReadable( <value>, [ <global>, [ <format> ]] ) }
# # Call  : { machineReadable("102 345,6789") }
# sub machineReadable($;$) {
#     my ( $v, $g ) = @_;
#
#     sub mrVal($$) {
#         my ( $n, $n2 ) = @_;
#         $n .= "." . $n2 if ($n2);
#         $n =~ s/[^\d\.]//g;
#         return $n;
#     }
#
#
#     foreach ( "std", "std-fr" ) {
#         my $delim = '\\' . $hr_formats{$_}{delim};
#         $delim .= ' ' if ($_ =~ /^std/);
#
#         if (   $g
#             && $v =~
# s/((-?)((?:\d+(?:[$delim]\d)*)+)([\.\,])((?:\d+(?:[$delim]\d)*)+)?)/$2.mrVal($3, $5)/eg
#           )
#         {
#             last;
#         }
#         elsif ( $v =~
#             m/^((\-?)((?:\d(?:[$delim]\d)*)+)(?:([\.\,])((?:\d(?:[$delim]\d)*)+))?)/ )
#         {
#             $v = $2 . mrVal( $3, $5 );
#             last;
#         }
#     }
#
#     return $v;
# }

# Condition: convert temperature (Celsius) to temperature condition
sub c2condition($;$) {
    my ( $data, $indoor ) = @_;
    my $val = "freeze";
    my $rgb = "0055BB";

    if ($indoor) {
        $data -= 5 if ( $data < 22.5 );
        $data += 5 if ( $data > 25 );
    }

    if ( $data >= 35 ) {
        $val = "hot";
        $rgb = "C72A23";
    }
    elsif ( $data >= 30 ) {
        $val = "high";
        $rgb = "E7652B";
    }
    elsif ( $data >= 14 ) {
        $val = "ideal";
        $rgb = "4C9329";
    }
    elsif ( $data >= 5 ) {
        $val = "low";
        $rgb = "009999";
    }
    elsif ( $data >= 2.5 || $indoor ) {
        $val = "cold";
        $rgb = "0066CC";
    }

    return ( $val, $rgb ) if (wantarray);
    return $val;
}

# Condition: convert humidity (percent) to humidity condition
sub humidity2condition($;$) {
    my ( $data, $indoor ) = @_;
    my $val = "dry";
    my $rgb = "C72A23";

    if ( $data >= 80 ) {
        $val = "wet";
        $rgb = "0066CC";
    }
    elsif ( $data >= 70 ) {
        $val = "high";
        $rgb = "009999";
    }
    elsif ( $data >= 50 ) {
        $val = "ideal";
        $rgb = "4C9329";
    }
    elsif ( $data >= 40 ) {
        $val = "low";
        $rgb = "E7652B";
    }

    return ( $val, $rgb ) if (wantarray);
    return $val;
}

# Condition: convert UV-Index to UV condition
sub uvi2condition($) {
    my ($data) = @_;
    my $val    = "low";
    my $rgb    = "4C9329";

    if ( $data > 11 ) {
        $val = "extreme";
        $rgb = "674BC4";
    }
    elsif ( $data > 8 ) {
        $val = "veryhigh";
        $rgb = "C72A23";
    }
    elsif ( $data > 6 ) {
        $val = "high";
        $rgb = "E7652B";
    }
    elsif ( $data > 3 ) {
        $val = "moderate";
        $rgb = "F4E54C";
    }

    return ( $val, $rgb ) if (wantarray);
    return $val;
}

# Condition: convert Beaufort to wind condition
sub bft2condition($) {
    my ($data) = @_;
    my $rgb    = "FEFEFE";
    my $cond   = "calm";
    my $warn   = " ";

    if ( $data == 12 ) {
        $rgb  = "E93323";
        $cond = "hurricane_force";
        $warn = "hurricane_force";
    }
    elsif ( $data == 11 ) {
        $rgb  = "EB4826";
        $cond = "violent_storm";
        $warn = "storm_force";
    }
    elsif ( $data == 10 ) {
        $rgb  = "E96E2C";
        $cond = "storm";
        $warn = "storm_force";
    }
    elsif ( $data == 9 ) {
        $rgb  = "F19E38";
        $cond = "strong_gale";
        $warn = "gale_force";
    }
    elsif ( $data == 8 ) {
        $rgb  = "F7CE46";
        $cond = "gale";
        $warn = "gale_force";
    }
    elsif ( $data == 7 ) {
        $rgb  = "FFFF54";
        $cond = "near_gale";
        $warn = "high_winds";
    }
    elsif ( $data == 6 ) {
        $rgb  = "D6FD51";
        $cond = "strong_breeze";
        $warn = "high_winds";
    }
    elsif ( $data == 5 ) {
        $rgb  = "B1FC4F";
        $cond = "fresh_breeze";
    }
    elsif ( $data == 4 ) {
        $rgb  = "B1FC7B";
        $cond = "moderate_breeze";
    }
    elsif ( $data == 3 ) {
        $rgb  = "B1FCA3";
        $cond = "gentle_breeze";
    }
    elsif ( $data == 2 ) {
        $rgb  = "B1FCD0";
        $cond = "light_breeze";
    }
    elsif ( $data == 1 ) {
        $rgb  = "D6FEFE";
        $cond = "light_air";
    }

    return ( $cond, $rgb, $warn ) if (wantarray);
    return $cond;
}

sub values2weathercondition($$$$$) {
    my ( $temp, $hum, $light, $isday, $israining ) = @_;
    my $val = "clear";

    if ($israining) {
        $val = "rain";
    }
    elsif ( $light > 40000 ) {
        $val = "sunny";
    }
    elsif ($isday) {
        $val = "cloudy";
    }

    $val = "nt_" . $val unless ($isday);
    return $val;
}

#################################
### Chronological conversions
###

sub hms2s($) {
    my $in = shift;
    my @a = split( ":", $in );
    return 0 if ( scalar @a < 2 || $in !~ m/^[\d:]*$/ );
    return $a[0] * 3600 + $a[1] * 60 + ( $a[2] ? $a[2] : 0 );
}

sub hms2m($) {
    return hms2s(@_) / 60;
}

sub hms2h($) {
    return hms2m(@_) / 60;
}

sub s2hms($) {
    my ($in) = @_;
    my ( $h, $m, $s );
    $h = int( $in / 3600 );
    $m = int( ( $in - $h * 3600 ) / 60 );
    $s = int( $in - $h * 3600 - $m * 60 );
    return ( $h, $m, $s ) if (wantarray);
    return sprintf( "%02d:%02d:%02d", $h, $m, $s );
}

sub m2hms($) {
    my ($in) = @_;
    my ( $h, $m, $s );
    $h = int( $in / 60 );
    $m = int( $in - $h * 60 );
    $s = int( 60 * ( $in - $h * 60 - $m ) );
    return ( $h, $m, $s ) if (wantarray);
    return sprintf( "%02d:%02d:%02d", $h, $m, $s );
}

sub h2hms($) {
    my ($in) = @_;
    my ( $h, $m, $s );
    $h = int($in);
    $m = int( 60 * ( $in - $h ) );
    $s = int( 3600 * ( $in - $h ) - 60 * $m );
    return ( $h, $m, $s ) if (wantarray);
    return sprintf( "%02d:%02d:%02d", $h, $m, $s );
}

sub IsLeapYear (;$) {

    # Either the value 0 or the value 1 is returned.
    #     If 0, it is not a leap year. If 1, it is a
    #     leap year. (Works for Julian calendar,
    #     established in 1582)

    my $y = shift;

    return undef
      unless ( !$y || $y =~ /^\d{10}(?:\.\d+)?$/ || $y =~ /^[1-2]\d{3}$/ );

    if ( !$y || $y !~ /^[1-2]\d{3}$/ ) {
        my $today = _time($y);
        $y = $today->{year};
    }

    # If $year is not evenly divisible by 4, it is
    #     not a leap year; therefore, we return the
    #     value 0 and do no further calculations in
    #     this subroutine. ("$year % 4" provides the
    #     remainder when $year is divided by 4.
    #     If there is a remainder then $year is
    #     not evenly divisible by 4.)

    return 0 if $y % 4;

    # At this point, we know $year is evenly divisible
    #     by 4. Therefore, if it is not evenly
    #     divisible by 100, it is a leap year --
    #     we return the value 1 and do no further
    #     calculations in this subroutine.

    return 1 if $y % 100;

    # At this point, we know $year is evenly divisible
    #     by 4 and also evenly divisible by 100. Therefore,
    #     if it is not also evenly divisible by 400, it is
    #     not leap year -- we return the value 0 and do no
    #     further calculations in this subroutine.

    return 0 if $y % 400;

    # Now we know $year is evenly divisible by 4, evenly
    #     divisible by 100, and evenly divisible by 400.
    #     We return the value 1 because it is a leap year.

    return 1;
}

sub IsDst(;$) {
    my ($time) = @_;
    my $ret = _time($time);
    return $ret->{isdst};
}

sub IsWeekend(;$) {
    my ($time) = @_;
    my $ret = _time($time);
    return $ret->{iswe};
}

sub IsHoliday(;$) {
    my ($time) = @_;
    my $ret = _time($time);
    return $ret->{isholiday};
}

# Get current stage of the daytime based on temporal hours
# https://de.wikipedia.org/wiki/Temporale_Stunden
sub GetDaytime(;$$$$) {
    my ( $time, $totalTemporalHours, $lang, $params ) = @_;
    $lang = (
          $main::attr{global}{language}
        ? $main::attr{global}{language}
        : "EN"
    ) unless ($lang);

    my $ret = ref($time) eq "HASH" ? $time : _time( $time, $lang, 1, $params );
    return undef unless ( ref($ret) eq "HASH" );

    $ret->{daytimeStages} = $totalTemporalHours
      && $totalTemporalHours =~ m/^\d+$/ ? $totalTemporalHours : 12;

    # TODO: consider srParams
    $ret->{sunrise}   = main::sunrise_abs_dat( $ret->{time_t} );
    $ret->{sunrise_s} = hms2s( $ret->{sunrise} );
    $ret->{sunrise_t} = $ret->{midnight_t} + $ret->{sunrise_s};
    $ret->{sunset}    = main::sunset_abs_dat( $ret->{time_t} );
    $ret->{sunset_s}  = hms2s( $ret->{sunset} );
    $ret->{sunset_t}  = $ret->{midnight_t} + $ret->{sunset_s};
    $ret->{isday}     = $ret->{time_t} >= $ret->{sunrise_t}
      && $ret->{time_t} < $ret->{sunset_t} ? 1 : 0;

    $ret->{daytimeRel_s} =
      hms2s("$ret->{hour}:$ret->{min}:$ret->{sec}") - $ret->{sunrise_s};
    $ret->{daytimeRel} = s2hms( $ret->{daytimeRel_s} );
    $ret->{daytimeT_s} = $ret->{sunset_s} - $ret->{sunrise_s};
    $ret->{daytimeT}   = s2hms( $ret->{daytimeT_s} );
    $ret->{daytimeStageLn_s} =
      $ret->{daytimeT_s} / $ret->{daytimeStages};
    $ret->{daytimeStageLn} = s2hms( $ret->{daytimeStageLn_s} );
    $ret->{daytimeStage_float} =
      $ret->{daytimeRel_s} / $ret->{daytimeStageLn_s};
    $ret->{daytimeStage} =
      int( ( ( $ret->{daytimeRel_s} + 1 ) / $ret->{daytimeStageLn_s} ) + 1 );
    $ret->{daytimeStage} = 0
      if ( $ret->{daytimeStage} < 1
        || $ret->{daytimeStage} > $ret->{daytimeStages} );

    # include season data
    $ret = GetSeason( $ret, $lang );

#$ret = GetSeasonPheno( $ret, $lang );
#$ret = GetSeasonSocial( $ret, $lang ); #TODO https://de.wikipedia.org/wiki/F%C3%BCnfte_Jahreszeit

    # change midnight event when season changes
    $ret->{events}{ $ret->{midnight_t} }{VALUE} = 1
      if ( $ret->{seasonMeteoChng} && $ret->{seasonMeteoChng} == 1 );
    $ret->{events}{ $ret->{midnight_t} }{DESC} .=
      ", Begin meteorological $ret->{seasonMeteo_long} season"
      if ( $ret->{seasonMeteoChng} && $ret->{seasonMeteoChng} == 1 );
    $ret->{events}{ $ret->{midnight_t} }{VALUE} = 2
      if ( $ret->{seasonAstroChng} && $ret->{seasonAstroChng} == 1 );
    $ret->{events}{ $ret->{midnight_t} }{DESC} .=
      ", Begin astronomical $ret->{seasonAstro_long} season"
      if ( $ret->{seasonAstroChng} && $ret->{seasonAstroChng} == 1 );

    # calculate daytime from daytimeStage, season and DST
    my $ds = $ret->{daytimeStage};
    while ( !defined( $ret->{daytime} ) ) {

        #TODO let user define %sdt2daytimes through attribute
        $ret->{daytime} =
          $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }{$ds}
          if (
               $sdt2daytimes{ $ret->{seasonMeteo} }
            && $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }
            && defined(
                $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }{$ds}
            )
          );
        $ds--;

        # when no relation was found
        unless ( defined( $ret->{daytime} ) || $ds > -1 ) {

            # assume midevening after sunset
            if ( $ret->{time_s} >= $ret->{sunset_s} ) {
                $ret->{daytime} = 5;
            }

            # assume night before sunrise
            else {
                $ret->{daytime} = 6;
            }
        }
    }

    # daytime during evening and night
    unless ( $ret->{daytimeStage} ) {
        $ret->{daytime} = 4 unless ( $ret->{daytime} > 4 );
        $ret->{daytime} = 5 unless ( $ret->{daytime} > 5 || $ret->{isday} );
        $ret->{daytime} = 6 if ( $ret->{time_s} < $ret->{sunrise_s} );
    }

    $ret->{daytime_long} = $daytimes{en}[ $ret->{daytime} ];

    my @langs = ('EN');
    push @langs, $lang unless ( $lang =~ /^EN/i );
    foreach (@langs) {
        my $l = lc($_);
        $l =~ s/^([a-z]+).*/$1/g;
        next unless ( $daytimes{$l} );
        my $h = $l eq "en" ? $ret : \%{ $ret->{$_} };

        $h->{daytime_long} = $daytimes{$l}[ $ret->{daytime} ];
    }

    # calculate daily schedule
    #

    # Midnight
    $ret->{events}{ $ret->{midnight_t} }{TYPE} = "dayshift";
    $ret->{events}{ $ret->{midnight_t} }{TIME} =
      main::FmtDateTime( $ret->{midnight_t} );
    $ret->{events}{ $ret->{midnight_t} }{DESC} =
      "Begin of night time and new calendar day";
    $ret->{events}{ $ret->{1}{midnight_t} }{TYPE} = "dayshift";
    $ret->{events}{ $ret->{1}{midnight_t} }{TIME} = $ret->{date} . " 24:00:00";
    $ret->{events}{ $ret->{1}{midnight_t} }{DESC} =
      "End of calendar day and begin night time";

    # Holidays
    $ret->{events}{ $ret->{midnight_t} }{DESC} .=
      ", $daystages{en}[2]: $ret->{day_desc}"
      if ( $ret->{isholiday} );
    $ret->{events}{ $ret->{1}{midnight_t} }{DESC} .=
      ", $daystages{en}[2]: $ret->{1}{day_desc}"
      if ( $ret->{1}{isholiday} );

    # DST change
    #FIXME TODO
    if ( $ret->{dstchange} && $ret->{dstchange} == 1 ) {
        my $t = $ret->{midnight_t} + 2 * 60 * 60;
        $ret->{events}{$t}{TYPE}  = "dstshift";
        $ret->{events}{$t}{VALUE} = $ret->{isdst};
        $ret->{events}{$t}{TIME}  = main::FmtDateTime($t);
        $ret->{events}{$t}{DESC}  = "Begin of standard time (-1h)"
          unless ( $ret->{isdst} );
        $ret->{events}{$t}{DESC} = "Begin of daylight saving time (+1h)"
          if ( $ret->{isdst} );
    }

    # daytime stage event forecast for today
    my $i = 1;
    my $b = $ret->{sunrise_t};
    while ( $i <= $ret->{daytimeStages} + 1 ) {

        # find daytime
        my $daytime;
        $daytime = $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }{$i}
          if (
               $sdt2daytimes{ $ret->{seasonMeteo} }
            && $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }
            && defined(
                $sdt2daytimes{ $ret->{seasonMeteo} }{ $ret->{isdst} }{$i}
            )
          );

        # create event
        my $t = int( $b + 0.5 );
        $ret->{events}{$t}{TIME} = main::FmtDateTime($t);
        if ( $i == $ret->{daytimeStages} + 1 ) {
            $ret->{events}{$t}{TYPE}  = "daytime";
            $ret->{events}{$t}{VALUE} = "midevening";
            $ret->{events}{$t}{DESC} =
              "End of daytime";
        }
        else {
            $ret->{events}{$t}{TYPE}  = "daytimeStage";
            $ret->{events}{$t}{VALUE} = $i;
            $ret->{events}{$t}{DESC}  = "Begin of daytime stage $i"
              unless ($daytime);
            if ( defined($daytime) ) {
                $ret->{events}{$t}{TYPE}  = "daytime";
                $ret->{events}{$t}{VALUE} = $daytimes{en}[$daytime];
                $ret->{events}{$t}{DESC} =
                  "Begin of $daytimes{en}[$daytime] time and daytime stage $i";
            }
        }
        $i++;
        $b += $ret->{daytimeStageLn_s};
    }

    return $ret;
}

sub GetSeason (;$$$);

sub GetSeason (;$$$) {
    my ( $time, $lang, $meteo ) = @_;
    $lang = (
          $main::attr{global}{language}
        ? $main::attr{global}{language}
        : "EN"
    ) unless ($lang);

    my $ret;
    my $wanthash = 0;

    if ( !$time ) {
        $time = time;
    }
    elsif ( ref($time) eq "HASH" ) {
        $ret      = $time;
        $wanthash = 1;
    }
    elsif ( $time =~ /^(?:0|1|2|3)$/ ) {
        return $seasons{ lc($lang) }
          ? $seasons{ lc($lang) }[$time]
          : $seasons{en}[$time];
    }
    elsif ( $time =~ /[A-Za-z]/ ) {
        my $index =
          $seasons{ lc($lang) }
          ? _GetIndexFromArray( $time, $seasons{ lc($lang) } )
          : undef;
        return $index;
    }
    elsif ( $time !~ /^\d{10}(?:\.\d+)?$/ ) {
        return undef;
    }
    else {
        $ret = _time($time);
    }

    my $index = 0;
    $index = 3 if ( $ret->{mon} <= 1 );
    $index++ if ( $ret->{mon} >= 5 );
    $index++ if ( $ret->{mon} >= 8 );
    $index++ if ( $ret->{mon} == 11 );
    $ret->{seasonMeteo} = $index;

    $index = 0;
    $index = 3 if ( $ret->{yday} < ( 80 + $ret->{isly} ) );
    $index++ if ( $ret->{yday} >= ( 173 + $ret->{isly} ) );
    $index++ if ( $ret->{yday} >= ( 265 + $ret->{isly} ) );
    $index++ if ( $ret->{yday} >= ( 356 + $ret->{isly} ) );
    $ret->{seasonAstro} = $index;

    unless (wantarray) {
        ( $ret->{'-1'}{seasonMeteo}, $ret->{'-1'}{seasonAstro} ) =
          GetSeason( $ret->{'-1'}{time_t}, $lang );
        ( $ret->{1}{seasonMeteo}, $ret->{1}{seasonAstro} ) =
          GetSeason( $ret->{1}{time_t}, $lang );
    }

    # text strings
    my @langs = ('EN');
    push @langs, $lang unless ( $lang =~ /^EN/i );
    foreach (@langs) {
        my $l = lc($_);
        $l =~ s/^([a-z]+).*/$1/g;
        next unless ( $seasons{$l} );
        my $h = $l eq "en" ? $ret : \%{ $ret->{$_} };

        $h->{seasonMeteo_long} = $seasons{$l}[ $ret->{seasonMeteo} ];
        $h->{seasonAstro_long} = $seasons{$l}[ $ret->{seasonAstro} ];
    }

    if ( $ret->{seasonMeteo} ne $ret->{1}{seasonMeteo} ) {
        $ret->{seasonMeteoChng} = 2;
    }

    if (   $ret->{'-1'}
        && defined( $ret->{'-1'}{seasonMeteo} )
        && defined( $ret->{'-1'}{seasonAstro} )
        && $ret->{1}
        && defined( $ret->{1}{seasonMeteo} )
        && defined( $ret->{1}{seasonAstro} ) )
    {
        $ret->{'-1'}{seasonMeteoChng} = 0;
        $ret->{seasonMeteoChng}       = 0;
        $ret->{1}{seasonMeteoChng}    = 0;

        if ( $ret->{seasonMeteo} ne $ret->{1}{seasonMeteo} ) {
            $ret->{seasonMeteoChng} = 2;
            $ret->{1}{seasonMeteoChng} = 1;
        }
        elsif ( $ret->{seasonMeteo} ne $ret->{'-1'}{seasonMeteo} ) {
            $ret->{'-1'}{seasonMeteoChng} = 2;
            $ret->{seasonMeteoChng} = 1;
        }

        $ret->{'-1'}{seasonAstroChng} = 0;
        $ret->{seasonAstroChng}       = 0;
        $ret->{1}{seasonAstroChng}    = 0;

        if ( $ret->{seasonAstro} ne $ret->{1}{seasonAstro} ) {
            $ret->{seasonAstroChng} = 2;
            $ret->{1}{seasonAstroChng} = 1;
        }
        elsif ( $ret->{seasonAstro} ne $ret->{'-1'}{seasonAstro} ) {
            $ret->{'-1'}{seasonAstroChng} = 2;
            $ret->{seasonAstroChng} = 1;
        }
    }

    return $ret if ($wanthash);
    return ( $ret->{seasonMeteo}, $ret->{seasonAstro} ) if (wantarray);
    return $ret->{$lang}{seasonMeteo_long}
      ? $ret->{$lang}{seasonMeteo_long}
      : $ret->{seasonMeteo_long}
      if ($meteo);
    return $ret->{$lang}{seasonAstro_long}
      ? $ret->{$lang}{seasonAstro_long}
      : $ret->{seasonAstro_long};
}

# Estimate phenologic season from astro and meteo season
# https://de.wikipedia.org/wiki/Ph%C3%A4nologie#Ph.C3.A4nologischer_Kalender
sub GetSeasonPheno (;$$) {
    $lang = (
          $main::attr{global}{language}
        ? $main::attr{global}{language}
        : "EN"
    ) unless ($lang);

    if ( !$time ) {
        $time = time;
    }
    elsif ( $time =~ /^(?:0|1|2|3|4|5|6|7|8|9|10|11)$/ ) {
        return $seasonsPheno{ lc($lang) }
          ? $seasonsPheno{ lc($lang) }[$time]
          : $seasonsPheno{en}[$time];
    }
    elsif ( $time =~ /[A-Za-z]/ ) {
        my $index =
          $seasonsPheno{ lc($lang) }
          ? _GetIndexFromArray( $time, $seasonsPheno{ lc($lang) } )
          : undef;
        return $index;
    }
    elsif ( $time !~ /^\d{10}(?:\.\d+)?$/ ) {
        return undef;
    }

    my (
        $sec,            $min,     $hour,
        $mday,           $mdayrem, $month,
        $monthISO,       $year,    $week,
        $weekISO,        $wday,    $wdayISO,
        $yday,           $ydayrem, $isdst,
        $isLeapYear,     $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    ) = GetDaySchedule($time);

    my ( $seasonAstro, $seasonAstroIndex, $seasonAstroChng ) = GetSeason($time);
    my ( $seasonMeteo, $seasonMeteoIndex, $seasonMeteoChng ) =
      GetSeason( $time, "en", 1 );

    # stick to astro season first
    my $index = $seasons{pheno}[$seasonAstro];

    # meteos say it's spring time
    if ( $seasonMeteo == 0 ) {
        $index = 0;
    }

    # meteos say it's summer time
    elsif ( $seasonMeteo == 1 ) {
        $index = 3;
    }

    # meteos say it's autumn time
    elsif ( $seasonMeteo == 2 ) {
        $index = 6;
    }

    # meteos say it's winter time
    elsif ( $seasonMeteo == 3 ) {
        $index = 9;
    }

    # if we know our position and spring is ahead
    if (   ( $index == 0 || $index == 1 )
        && $main::attr{global}{latitude}
        && $main::attr{global}{longitude} )
    {
        # it starts in south-west Portugal
        my $dist = distance(
            $main::attr{global}{latitude},
            $main::attr{global}{longitude},
            37.136633, -8.817837
        );

        # TODO: let begin of early spring be set by user
        my $earlySpringBegin = main::time_str2num("$year-02-28 00:00:00");
        my $days = ( $time - $earlySpringBegin ) / ( 60 * 60 * 24 );

        # comes with 40km per day
        my $currDist = $dist - ( $days * 40 );

        # when season reached location
        if ( $currDist <= 0 ) {
            $index = 2;
        }

        # when season made 60% of it's way
        elsif ( $currDist <= $dist * 0.4 ) {
            $index = 1;
        }
    }

    # assume spring progress from calendar
    elsif ( ( $index == 0 || $index == 1 ) ) {
        $index = 1 if ( $monthISO == 4 );
        $index = 2 if ( $monthISO == 5 );
    }

    # assume summer progress from calendar
    elsif ( $index == 3 ) {
        $index = 4 if ( $monthISO == 7 );
        $index = 5 if ( $monthISO == 8 );
    }

    # if we know our position and autumn is ahead
    elsif (( $index == 6 || $index == 7 )
        && $main::attr{global}{latitude}
        && $main::attr{global}{longitude} )
    {
        # it starts in Helsinki
        my $dist = distance(
            $main::attr{global}{latitude},
            $main::attr{global}{longitude},
            60.161880, 24.937267
        );

        # TODO: let begin of early autumn be set by user
        my $earlySpringBegin = main::time_str2num("$year-09-01 00:00:00");
        my $days = ( $time - $earlySpringBegin ) / ( 60 * 60 * 24 );

        # comes with 40km per day
        my $currDist = $dist - ( $days * 40 );

        # when season reached location
        if ( $currDist <= 0 ) {
            $index = 8;
        }

        # when season made 60% of it's way
        elsif ( $currDist <= $dist * 0.4 ) {
            $index = 7;
        }
    }

    # assume autumn progress from calendar
    elsif ( ( $index == 6 || $index == 7 ) ) {
        $index = 7 if ( $monthISO == 10 );
        $index = 8 if ( $monthISO == 11 );
    }

    my $seasonPheno =
      defined($index)
      && $index{ lc($lang) }
      ? $seasonsPheno{ lc($lang) }[$index]
      : $seasonsPheno{en}[$index];

    return ( $seasonPheno, $index ) if (wantarray);
    return ($seasonPheno);
}

####################
# HELPER FUNCTIONS

sub decimal_mark ($$) {
    my ( $val, $f ) = @_;
    return $val unless ( looks_like_number($val) && $f );

    my $text = reverse $val;
    if ( $f eq "2" ) {
        $text =~ s:\.:,:g;
        $text =~ s/(\d\d\d)(?=\d)(?!\d*,)/$1./g;
    }
    else {
        $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    }
    return scalar reverse $text;
}

sub _round($;$) {
    my ( $val, $n ) = @_;
    $n = 1 unless ( defined($n) );
    return sprintf( "%.${n}f", $val );
}

sub _time(;$$$$);

sub _time(;$$$$) {
    my ( $time, $lang, $dayOffset, $params ) = @_;
    $dayOffset = 1 if ( !defined($dayOffset) || $dayOffset !~ /^-?\d+$/ );
    $lang = (
          $main::attr{global}{language}
        ? $main::attr{global}{language}
        : "EN"
    ) unless ($lang);

    return undef
      unless ( !$time || $time =~ /^\d{10}(?:\.\d+)?$/ );

    my %ret;
    $ret{time_t} = $time if ($time);
    $ret{time_t} = time unless ($time);
    $ret{params} = $params if ($params);

    my @t = localtime( $ret{time_t} );
    (
        $ret{sec},  $ret{min},  $ret{hour}, $ret{mday}, $ret{mon},
        $ret{year}, $ret{wday}, $ret{yday}, $ret{isdst}
    ) = @t;
    $ret{monISO} = $ret{mon} + 1;
    $ret{year} += 1900;

    $ret{date} =
      sprintf( "%04d-%02d-%02d", $ret{year}, $ret{monISO}, $ret{mday} );
    $ret{time} = sprintf( "%02d:%02d", $ret{hour}, $ret{min} );
    $ret{time_hms} =
      sprintf( "%02d:%02d:%02d", $ret{hour}, $ret{min}, $ret{sec} );
    $ret{time_s}     = hms2s( $ret{time_hms} );            #FIXME for DST change
    $ret{datetime}   = $ret{date} . " " . $ret{time_hms};
    $ret{midnight_t} = $ret{time_t} - $ret{time_s};        #FIXME for DST change

    # get leap year status
    $ret{isly} = IsLeapYear( $ret{year} );

    # remaining monthdays
    $ret{mdayrem} = 0;
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 1 );
    $ret{mdayrem} = 28 + $ret{isly} - $ret{mday}
      if ( $ret{monISO} == 2 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 3 );
    $ret{mdayrem} = 30 - $ret{mday} if ( $ret{monISO} == 4 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 5 );
    $ret{mdayrem} = 30 - $ret{mday} if ( $ret{monISO} == 6 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 7 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 8 );
    $ret{mdayrem} = 30 - $ret{mday} if ( $ret{monISO} == 9 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 10 );
    $ret{mdayrem} = 30 - $ret{mday} if ( $ret{monISO} == 11 );
    $ret{mdayrem} = 31 - $ret{mday} if ( $ret{monISO} == 12 );

    # remaining yeardays
    $ret{ydayrem} = 365 + $ret{isly} - $ret{yday};

    # ISO 8601 weekday as number with Monday as 1 (1-7)
    $ret{wdaynISO} = strftime( '%u', @t );

    # Week number with the first Sunday as the first day of week one (00-53)
    $ret{week} = strftime( '%U', @t );

    # ISO 8601 week number (00-53)
    $ret{weekISO} = strftime( '%V', @t );

    # weekend
    $ret{iswe} = ( $ret{wday} == 0 || $ret{wday} == 6 ) ? 1 : 0;

    # text strings
    my @langs = ('EN');
    push @langs, $lang unless ( $lang =~ /^EN/i );
    foreach (@langs) {
        my $l = lc($_);
        $l =~ s/^([a-z]+).*/$1/g;
        next unless ( $months{$l} );
        my $h = $l eq "en" ? \%ret : \%{ $ret{$_} };

        $h->{dst_long}   = $dst{$l}[ $ret{isdst} ];
        $h->{rday_long}  = $reldays{$l}[1];
        $h->{day_desc}   = $daystages{$l}[ $ret{iswe} ];
        $h->{wday_long}  = $days{$l}[ $ret{wday} ];
        $h->{wday_short} = $dayss{$l}[ $ret{wday} ];
        $h->{mon_long}   = $months{$l}[ $ret{mon} ];
        $h->{mon_short}  = $monthss{$l}[ $ret{mon} ];

        $h->{date_long} =
          _ReplaceStringByHashKey( \%ret, $dateformats{$l}, $_ );
        $h->{date_short} =
          _ReplaceStringByHashKey( \%ret, $dateformatss{$l}, $_ );
    }

    # holiday
    if ($dayOffset) {
        $ret{'-1'}{isholiday} = 0;
        $ret{1}{isholiday}    = 0;
    }
    $ret{isholiday} = 0;

    my $holidayDev =
      $main::attr{global}{holiday2we}
      && main::IsDevice( $main::attr{global}{holiday2we}, "holiday" )
      ? $main::attr{global}{holiday2we}
      : undef;
    if ($holidayDev) {
        my $date = sprintf( "%02d-%02d", $ret{monISO}, $ret{mday} );
        $tod = main::holiday_refresh( $holidayDev, $date );
        if ($dayOffset) {
            $date =
              sprintf( "%02d-%02d", $ret{'-1'}{monISO}, $ret{'-1'}{mday} );
            $ytd = main::holiday_refresh( $holidayDev, $date );
            $date = sprintf( "%02d-%02d", $ret{1}{monISO}, $ret{1}{mday} );
            $tom = main::holiday_refresh( $holidayDev, $date );
        }

        if ( $tod ne "none" ) {
            $ret{iswe} += 2;
            $ret{isholiday} = 1;
            $ret{day_desc}  = $tod;

            foreach (@langs) {
                my $l = lc($_);
                $l =~ s/^([a-z]+).*/$1/g;
                next unless ( $months{$l} );
                my $h = $l eq "en" ? \%ret : \%{ $ret{$_} };

                $h->{day_desc} = $tod;
            }
        }
        if ($dayOffset) {
            if ( $ytd ne "none" && $ret{'-1'} ) {
                $ret{'-1'}{isholiday} = 1;
                $ret{'-1'}{day_desc}  = $ytd;

                foreach (@langs) {
                    my $l = lc($_);
                    $l =~ s/^([a-z]+).*/$1/g;
                    next unless ( $months{$l} );
                    my $h = $l eq "en" ? $ret{'-1'} : \%{ $ret{'-1'}{$_} };

                    $h->{day_desc} = $ytd;
                }
            }
            if ( $tom ne "none" && $ret{1} ) {
                $ret{1}{isholiday} = 1;
                $ret{1}{day_desc}  = $tom;

                foreach (@langs) {
                    my $l = lc($_);
                    $l =~ s/^([a-z]+).*/$1/g;
                    next unless ( $months{$l} );
                    my $h = $l eq "en" ? $ret{1} : \%{ $ret{1}{$_} };

                    $h->{day_desc} = $tom;
                }
            }
        }
    }

    if (wantarray) {
        my @a;

        foreach (
            'sec',      'min',     'hour',   'mday',     'mon',
            'year',     'wday',    'wdayn',  'yday',     'isdst',
            'mdayrem',  'monISO',  'week',   'weekISO',  'wdayISO',
            'wdaynISO', 'ydayrem', 'time_t', 'datetime', 'date',
            'time_hms', 'time',    'isly',
          )
        {
            push @a, $ret{$_};
        }

        return @a;
    }

    elsif ($dayOffset) {
        my $i = $dayOffset * -1;
        while ( $i < $dayOffset + 1 ) {
            $ret{$i} = _time( $ret{time_t} + ( 24 * 60 * 60 * $i ), $lang, 0 )
              unless ( $i == 0 );

            foreach (@langs) {
                my $l = $_;
                $l =~ s/^([A-Z-a-z]+).*/$1/g;
                $l = lc($l);
                next if ( $i == 0 || !$reldays{$l} );
                my $h = $l eq "en" ? \%{ $ret{$i} } : \%{ $ret{$i}{$l} };

                if ( $i == -1 || $i == 1 ) {
                    $h->{rday_long} = $reldays{$l}[ $i + 1 ];
                }
                else {
                    delete $h->{rday_long};
                }
            }

            $i++;
        }

        # DST change
        $ret{'-1'}{dstchange} = 0;
        $ret{dstchange}       = 0;
        $ret{1}{dstchange}    = 0;

        if ( $ret{isdst} ne $ret{1}{isdst} ) {
            $ret{dstchange} = 2;
            $ret{1}{dstchange} = 1;
        }
        elsif ( $ret{isdst} ne $ret{'-1'}{isdst} ) {
            $ret{'-1'}{dstchange} = 2;
            $ret{dstchange} = 1;
        }
    }

    return \%ret;
}

sub _GetIndexFromArray($$) {
    my ( $string, $array ) = @_;
    return undef unless ( ref($array) eq "ARRAY" );
    my ($index) = grep { $array->[$_] =~ /^$string$/i } ( 0 .. @$array - 1 );
    return defined $index ? $index : undef;
}

sub _ReplaceStringByHashKey($$;$) {
    my ( $hash, $string, $sublvl ) = @_;
    return $string unless ( $hash && ref($hash) eq "HASH" );

    $string = _ReplaceStringByHashKey( $hash->{$sublvl}, $string )
      if ( $sublvl && $hash->{$sublvl} );

    foreach my $key ( keys %{$hash} ) {
        next if ( ref( $hash->{$key} ) );
        my $val = $hash->{$key};
        $string =~ s/%$key%/$val/gi;
        $string =~ s/\$$key/$val/g;
    }

    return $string;
}

1;
