###############################################################################
# $Id$
package main;
sub UConv_Initialize() { }

package UConv;
use Scalar::Util qw(looks_like_number);
use Data::Dumper;

####################
# Translations

my %compasspoint_txt = (
    "en" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "de" => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "nl" => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
        'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "fr" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
    ],
    "pl" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
);

my %wdays_txt_en = (
    "en" => {
        'Mon' => 'Mon',
        'Tue' => 'Tue',
        'Wed' => 'Wed',
        'Thu' => 'Thu',
        'Fri' => 'Fri',
        'Sat' => 'Sat',
        'Sun' => 'Sun',
    },
    "de" => {
        'Mon' => 'Mo',
        'Tue' => 'Di',
        'Wed' => 'Mi',
        'Thu' => 'Do',
        'Fri' => 'Fr',
        'Sat' => 'Sa',
        'Sun' => 'So',
    },
    "nl" => {
        'Mon' => 'Maa',
        'Tue' => 'Din',
        'Wed' => 'Woe',
        'Thu' => 'Don',
        'Fri' => 'Vri',
        'Sat' => 'Zat',
        'Sun' => 'Zon',
    },
    "fr" => {
        'Mon' => 'Lun',
        'Tue' => 'Mar',
        'Wed' => 'Mer',
        'Thu' => 'Jeu',
        'Fri' => 'Ven',
        'Sat' => 'Sam',
        'Sun' => 'Dim',
    },
    "pl" => {
        'Mon' => 'Pon',
        'Tue' => 'Wt',
        'Wed' => 'Śr',
        'Thu' => 'Czw',
        'Fri' => 'Pt',
        'Sat' => 'Sob',
        'Sun' => 'Nie',
    },
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
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.621, $rnd );
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
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.609344, $rnd );
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

#################################
### Angular conversions
###

# convert direction in degree to point of the compass
sub direction2compasspoint($;$) {
    my ( $azimuth, $lang ) = @_;

    my $directions_txt_i18n;

    if ( $lang && defined( $compasspoint_txt{$lang} ) ) {
        $directions_txt_i18n = $compasspoint_txt{$lang};
    }
    else {
        $directions_txt_i18n = $compasspoint_txt{en};
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
### Textual unit conversions
###

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

#TODO rewrite for Unit.pm
sub fmtTime($) {
    my ($val) = @_;
    my $suffix = ' s';

    if ( $val >= 60 ) {
        $val = sprintf( "%.1f", $val / 60 );
        $suffix = ' min';

        if ( $val >= 60 ) {
            $val = sprintf( "%.1f", $val / 60 );
            $suffix = ' h';
        }
    }

    return ( $val, $suffix ) if (wantarray);
    return $val . $suffix;
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
