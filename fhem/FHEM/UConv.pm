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

my %compasspoints = (
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

#################################
### Inner metric conversions
###

# Temperature: convert Celsius to Kelvin
sub c2k($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data + 273.15, $rnd );
}

# Temperature: convert Kelvin to Celsius
sub k2c($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data - 273.15, $rnd );
}

# Speed: convert km/h (kilometer per hour) to m/s (meter per second)
sub kph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 3.6, $rnd );
}

# Speed: convert m/s (meter per second) to km/h (kilometer per hour)
sub mps2kph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 3.6, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to mmHg (milimeter of Mercury)
sub hpa2mmhg($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.00750061561303, $rnd );
}

#################################
### Metric to angloamerican conversions
###

# Temperature: convert Celsius to Fahrenheit
sub c2f($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.8 + 32, $rnd );
}

# Temperature: convert Kelvin to Fahrenheit
sub k2f($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 273.15 ) * 1.8 + 32, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to in (inches of Mercury)
sub hpa2inhg($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.02952998751, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to PSI (Pound force per square inch)
sub hpa2psi($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 100.00014504, $rnd );
}

# Speed: convert km/h (kilometer per hour) to mph (miles per hour)
sub kph2mph($;$) {
    return km2mi(@_);
}

# Speed: convert m/s (meter per seconds) to mph (miles per hour)
sub mps2mph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( kph2mph( mps2kph( $data, 9 ), 9 ), $rnd );
}

# Length: convert mm (milimeter) to in (inch)
sub mm2in($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.039370, $rnd );
}

# Length: convert cm (centimeter) to in (inch)
sub cm2in($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.39370, $rnd );
}

# Length: convert m (meter) to ft (feet)
sub m2ft($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 3.2808, $rnd );
}

# Length: convert km (kilometer) to miles (mi)
sub km2mi($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.621371192, $rnd );
}

#################################
### Inner Angloamerican conversions
###

# Speed: convert mph (miles per hour) to ft/s (feet per second)
sub mph2fts($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.467, $rnd );
}

# Speed: convert ft/s (feet per second) to mph (miles per hour)
sub fts2mph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 1.467, $rnd );
}

#################################
### Angloamerican to Metric conversions
###

# Temperature: convert Fahrenheit to Celsius
sub f2c($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 32 ) * 0.5556, $rnd );
}

# Temperature: convert Fahrenheit to Kelvin
sub f2k($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 32 ) / 1.8 + 273.15, $rnd );
}

# Pressure: convert in (inches of Mercury) to hPa (hecto Pascal)
sub inhg2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 33.8638816, $rnd );
}

# Pressure: convert PSI (Pound force per square inch) to hPa (hecto Pascal)
sub psi2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 100.00014504, $rnd );
}

# Speed: convert mph (miles per hour) to km/h (kilometer per hour)
sub mph2kph($;$) {
    return mi2km(@_);
}

# Speed: convert mph (miles per hour) to m/s (meter per seconds)
sub mph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( kph2mps( mph2kph( $data, 9 ), 9 ), $rnd );
}

# Length: convert in (inch) to mm (milimeter)
sub in2mm($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 25.4, $rnd );
}

# Length: convert in (inch) to cm (centimeter)
sub in2cm($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 0.39370, $rnd );
}

# Length: convert ft (feet) to m (meter)
sub ft2m($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 3.2808, $rnd );
}

# Length: convert mi (miles) to km (kilometer)
sub mi2km($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.609344, $rnd );
}

#################################
### Angular conversions
###

# convert direction in degree to point of the compass
sub direction2compasspoint($;$) {
    my ( $azimuth, $lang ) = @_;
    my $directions_txt_i18n;

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
    return roundX( ( ( $data - 100 ) / 450 + 1 ), $rnd );
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
    return roundX( $data / 126.7, $rnd );
}

# Power: convert W/m2 to lux
sub wpsm2lux($;$) {
    my ( $data, $rnd ) = @_;

    # Forum topic,44403.msg501704.html#msg501704
    return roundX( $data * 126.7, $rnd );
}

#################################
### Nautic unit conversions
###

# Speed: convert km/h to knots
sub kph2kn($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.539956803456, $rnd );
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

sub distance($$$$;$) {
    my ( $lat1, $lng1, $lat2, $lng2, $miles ) = @_;
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

    return ( $miles ? km2mi($km) : $km );
}

#################################
### Textual unit conversions
###

######## %hr_formats #########################################
# What  : used by functions humanReadable and machineReadable
my %hr_formats = (

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
      $attr{global}{humanReadable} ? $attr{global}{humanReadable}
      : (
        $attr{global}{language} ? $attr{global}{language}
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
    if ( ( $delim eq "\x{202F}" || $delim eq " " ) && length( $p[1] ) >= $min )
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

    my $year = shift;
    if ( !$year || $year !~ /^[1-2]\d{3}$/ ) {
        my (
            $tsec,  $tmin,  $thour, $tmday, $tmon,
            $tyear, $twday, $tyday, $tisdst
        ) = GetTimeinfo($year);
        $year = $tyear + 1900;
    }

    # If $year is not evenly divisible by 4, it is
    #     not a leap year; therefore, we return the
    #     value 0 and do no further calculations in
    #     this subroutine. ("$year % 4" provides the
    #     remainder when $year is divided by 4.
    #     If there is a remainder then $year is
    #     not evenly divisible by 4.)

    return 0 if $year % 4;

    # At this point, we know $year is evenly divisible
    #     by 4. Therefore, if it is not evenly
    #     divisible by 100, it is a leap year --
    #     we return the value 1 and do no further
    #     calculations in this subroutine.

    return 1 if $year % 100;

    # At this point, we know $year is evenly divisible
    #     by 4 and also evenly divisible by 100. Therefore,
    #     if it is not also evenly divisible by 400, it is
    #     not leap year -- we return the value 0 and do no
    #     further calculations in this subroutine.

    return 0 if $year % 400;

    # Now we know $year is evenly divisible by 4, evenly
    #     divisible by 100, and evenly divisible by 400.
    #     We return the value 1 because it is a leap year.

    return 1;
}

sub IsDst (;$) {
    my (
        $sec,      $min,  $hour, $mday,    $month,
        $monthISO, $year, $week, $weekISO, $wday,
        $wdayISO,  $yday, $isdst
    ) = GetCalendarInfo(@_);
    return $isdst;
}

sub IsWeekend (;$) {
    my (
        $sec,      $min,  $hour,  $mday,    $month,
        $monthISO, $year, $week,  $weekISO, $wday,
        $wdayISO,  $yday, $isdst, $iswe
    ) = GetCalendarInfo(@_);
    return $iswe;
}

sub IsHoliday (;$) {
    my (
        $sec,            $min,     $hour,
        $mday,           $month,   $monthISO,
        $year,           $week,    $weekISO,
        $wday,           $wdayISO, $yday,
        $isdst,          $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    ) = GetCalendarInfo(@_);
    return $isHolidayToday;
}

sub IsHolidayTomorrow (;$) {
    my (
        $sec,            $min,     $hour,
        $mday,           $month,   $monthISO,
        $year,           $week,    $weekISO,
        $wday,           $wdayISO, $yday,
        $isdst,          $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    ) = GetCalendarInfo(@_);
    return $isHolidayTomorrow;
}

sub IsHolidayYesterday (;$) {
    my (
        $sec,            $min,     $hour,
        $mday,           $month,   $monthISO,
        $year,           $week,    $weekISO,
        $wday,           $wdayISO, $yday,
        $isdst,          $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    ) = GetCalendarInfo(@_);
    return $isHolidayYesterday;
}

sub GetCalendarInfo(;$$) {
    my ( $time, $holidayDev ) = @_;

    my @t;
    @t = localtime($time) if ($time);
    @t = localtime() unless ($time);
    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst ) = @t;
    my $monthISO = $month + 1;
    $year += 1900;

    # ISO 8601 weekday as number with Monday as 1 (1-7)
    my $wdayISO = strftime( '%u', @t );

    # Week number with the first Sunday as the first day of week one (00-53)
    my $week = strftime( '%U', @t );

    # ISO 8601 week number (00-53)
    my $weekISO = strftime( '%V', @t );

    my $iswe = ( $wday == 0 || $wday == 6 ) ? 1 : 0;
    my $isHolidayYesterday;
    my $isHolidayToday;
    my $isHolidayTomorrow;

    $holidayDev = undef unless ( main::IsDevice( $holidayDev, "holiday" ) );
    $holidayDev = $main::attr{global}{holiday2we}
      if ( !$holidayDev
        && main::IsDevice( $main::attr{global}{holiday2we}, "holiday" ) );

    if ($holidayDev) {
        if ( main::ReadingsVal( $holidayDev, "state", "none" ) ne "none" ) {
            $iswe           = 1;
            $isHolidayToday = 1;
        }
        $isHolidayYesterday = 1
          if (
            main::ReadingsVal( $holidayDev, "yesterday", "none" ) ne "none" );
        $isHolidayTomorrow = 1
          if ( main::ReadingsVal( $holidayDev, "tomorrow", "none" ) ne "none" );
    }

    return (
        $sec,            $min,     $hour,
        $mday,           $month,   $monthISO,
        $year,           $week,    $weekISO,
        $wday,           $wdayISO, $yday,
        $isdst,          $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    );
}

# Get current stage of the daytime based on temporal hours
# https://de.wikipedia.org/wiki/Temporale_Stunden
sub GetDaytimeStage(@) {
    my ( $date, $totalTemporalHours, @srParams ) = @_;
    $date               = time unless ($date);
    $totalTemporalHours = 12   unless ($totalTemporalHours);

    # today
    my (
        $sec,            $min,     $hour,
        $mday,           $month,   $monthISO,
        $year,           $week,    $weekISO,
        $wday,           $wdayISO, $yday,
        $isdst,          $iswe,    $isHolidayYesterday,
        $isHolidayToday, $isHolidayTomorrow
    ) = GetCalendarInfo($date);

    # tomorrow
    my (
        $tsec,            $tmin,     $thour,
        $tmday,           $tmonth,   $tmonthISO,
        $tyear,           $tweek,    $tweekISO,
        $twday,           $twdayISO, $tyday,
        $tisdst,          $tiswe,    $tisHolidayYesterday,
        $tisHolidayToday, $tisHolidayTomorrow
    ) = GetCalendarInfo( $date + 24 * 60 * 60 );

    my $secSr = hms2s( main::sunrise_abs_dat( $date, @srParams ) );
    my $secSs     = hms2s( main::sunset_abs_dat( $date, @srParams ) );
    my $secNow    = hms2s("$hour:$min:$sec") - $secSr;
    my $dlength   = $secSs - $secSr;
    my $slength   = $dlength / $totalTemporalHours;
    my $currStage = int( $secNow / $slength );

    my $dateSr = main::time_str2num("$year-$monthISO-$mday 00:00:00") + $secSr;
    my %events;
    my $i = 0;
    until ( $i == $totalTemporalHours ) {
        $events{$i}{timestamp} = int( $dateSr + 0.5 );
        $i++;
        $dateSr += $slength;
    }
    $events{$totalTemporalHours}{timestamp} = int(
        main::time_str2num("$year-$monthISO-$mday 00:00:00") + $secSs + 0.5 );

    my $dateSrTomorrow =
      main::time_str2num("$tyear-$tmonthISO-$tmday 00:00:00") +
      hms2s( main::sunrise_abs_dat( $date + 86400, @srParams ) );
    my %eventsTomorrow;
    $i = 0;
    until ( $i == $totalTemporalHours ) {
        $eventsTomorrow{$i}{timestamp} = int( $dateSrTomorrow + 0.5 );
        $i++;
        $dateSrTomorrow += $slength;
    }

    # early day after midnight
    if ( $currStage < 0 ) {
        return ( $totalTemporalHours, $slength, \%events )
          if (wantarray);
        return $totalTemporalHours;
    }

    # late day before midnight
    elsif ( $currStage > $totalTemporalHours ) {
        return ( $totalTemporalHours, $slength, \%eventsTomorrow )
          if (wantarray);
        return $totalTemporalHours;
    }

    # daytime
    return ( $currStage, $slength, \%events ) if (wantarray);
    return $currStage;
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

sub roundX($;$) {
    my ( $val, $n ) = @_;
    $n = 1 unless ( defined($n) );
    return sprintf( "%.${n}f", $val );
}

1;
