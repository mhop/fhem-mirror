# $Id$

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use FHEM::UConv;
use JSON;

sub Unit_Initialize() {
}

my $autoscale_m = {
    '0'     => { format => '%i',   scale => 1000, },
    '0.001' => { format => '%i',   scale => 1000, },
    '0.1'   => { format => '%.1f', scale => 1, },
    '10'    => { format => '%i',   scale => 1, },
    '1.0e3' => { format => '%.1f', scale => 0.001, },
    '2.0e3' => { format => '%i',   scale => 0.001, },
    '1.0e6' => { format => '%.1f', scale => 0.001, },
    '2.0e6' => { format => '%i',   scale => 0.001, },
};

my $scales_m = {
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
};

my $scales_sq = {
    'scale_txt_sq'      => '2',
    'scale_txt_long_sq' => {
        de => 'Quadrat',
        en => 'square',
        fr => 'square',
        nl => 'square',
        pl => 'square',
    },
};

my $scales_cu = {
    'scale_txt_cu'      => '3',
    'scale_txt_long_cu' => {
        de => 'Kubik',
        en => 'cubic',
        fr => 'cubic',
        nl => 'cubic',
        pl => 'cubic',
    },
};

my $rtype_base = {

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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        format => '%.0f',
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
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
        scope  => { min => 0 },
    },

    23 => {
        dimension      => 'L^2',
        formula_symbol => 'A',
        si_base        => 'm2',
        txt_base       => {
            de => 'Flächeninhalt',
            en => 'surface area',
            fr => 'surface area',
            nl => 'surface area',
            pl => 'surface area',
        },
        format => '%i',
        scope  => { min => 0 },
    },

    900 => {
        txt_base  => 'FHEM Readings Type',
        tmpl      => '%value%',
        tmpl_long => '%value%',
    },
};

my $rtypes = {

    # others
    oknok => {
        ref_base => 900,
        txt      => {
            de => [ 'Fehler', 'ok' ],
            en => [ 'error',  'ok' ],
            fr => [ 'error',  'on' ],
            nl => [ 'error',  'on' ],
            pl => [ 'error',  'on' ],
        },
        scope => [ 'nok', 'ok' ],
    },

    onoff => {
        ref_base => 900,
        txt      => {
            de => [ 'aus', 'an' ],
            en => [ 'off', 'on' ],
            fr => [ 'off', 'on' ],
            nl => [ 'off', 'on' ],
            pl => [ 'off', 'on' ],
        },
        scope => [ 'off', 'on' ],
    },

    bool => {
        ref_base => 900,
        txt      => {
            de => 'wahr/falsch',
            en => 'true/false',
            fr => 'true/false',
            nl => 'true/false',
            pl => 'true/false',
        },
        scope => [ 'false', 'true' ],
    },

    epoch => {
        ref_base => 900,
        txt      => {
            de => 'Unix Epoche in s seit 1970-01-01T00:00:00Z',
            en => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            fr => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            nl => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            pl => 'Unix epoch in s since 1970-01-01T00:00:00Z',
        },
        scope => { min => 0 },
    },

    time => {
        ref_base => 900,
        txt      => {
            de => 'Uhrzeit hh:mm',
            en => 'time hh:mm',
            fr => 'time hh:mm',
            nl => 'time hh:mm',
            pl => 'time hh:mm',
        },
        scope => '^([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9])$',
    },

    datetime => {
        ref_base => 900,
        txt      => 'YYYY-mm-dd hh:mm',
        scope =>
'^([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9])$',
    },

    timesec => {
        ref_base => 900,
        txt      => {
            de => 'Uhrzeit hh:mm:ss',
            en => 'time hh:mm:ss',
            fr => 'time hh:mm:ss',
            nl => 'time hh:mm:ss',
            pl => 'time hh:mm:ss',
        },
        scope => '^([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9]):([0-5]?[0-9])$',
    },

    datetimesec => {
        ref_base => 900,
        txt      => 'YYYY-mm-dd hh:mm:ss',
        scope =>
'^([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9]):(0?[1-9]|[1-5][0-9])$',
    },

    direction => {
        ref_base       => 900,
        formula_symbol => 'Dir',
        ref            => 'gon',
        scope          => { min => 0, max => 360 },
    },

    compasspoint => {
        ref_base       => 900,
        formula_symbol => 'CP',
        txt            => {
            de => [
                'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
                'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
            ],
            en => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
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
        },
        txt_long => {
            de => [
                'Norden', 'NNO', 'NO',     'ONO', 'Osten', 'OSO',
                'SO',     'SSO', 'Süden', 'SSW', 'SW',    'WSW',
                'Westen', 'WNW', 'NW',     'NNW'
            ],
            en => [
                'North', 'NNE', 'NE',    'ENE', 'East', 'ESE',
                'SE',    'SSE', 'South', 'SSW', 'SW',   'WSW',
                'West',  'WNW', 'NW',    'NNW'
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
        },
        scope => [
            'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
            'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
        ],
    },

    closure => {
        ref_base => 900,
        txt      => {
            de => 'offen/geschlossen/gekippt',
            en => 'open/closed/tilted',
            fr => 'open/closed/tilted',
            nl => 'open/closed/tilted',
            pl => 'open/closed/tilted',
        },
        scope => [ 'closed', 'open', 'tilted' ],
    },

    condition_hum => {
        ref_base => 900,
        txt      => {
            de => 'Feuchtigkeitsbedingung',
            en => 'humidity condition',
            fr => 'humidity condition',
            nl => 'humidity condition',
            pl => 'humidity condition',
        },
        scope => [ 'dry', 'low', 'optimal', 'high', 'wet' ],
    },

    condition_uvi => {
        ref_base => 900,
        txt      => {
            de => 'UV Bedingung',
            en => 'UV condition',
            fr => 'UV condition',
            nl => 'UV condition',
            pl => 'UV condition',
        },
        scope => [ 'low', 'moderate', 'high', 'veryhigh', 'extreme' ],
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
        tmpl  => '%value% %symbol%',
        scope => { min => 0, max => 100 },
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
        tmpl  => '%value%%symbol%',
        scope => { min => 0 },
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
        scope => { min => 0 },
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
        tmpl  => '%value%%symbol%',
        scope => { min => -273.15 },
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
        tmpl  => '%value% %symbol%',
        scope => { min => -459.67 },
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

    # surface area
    cm2 => {
        ref_base => 23,
        ref      => 'm',
        scale_m  => '1.0e-2',
        scale_sq => 1,
    },

    m2 => {
        ref_base => 23,
        ref      => 'm',
        scale_m  => '1.0e0',
        scale_sq => 1,
    },

    # volume
    cm3 => {
        ref_base => 18,
        ref      => 'm',
        scale_m  => '1.0e-2',
        scale_cu => 1,
    },

    m3 => {
        ref_base => 18,
        ref      => 'm',
        scale_m  => '1.0e0',
        scale_cu => 1,
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
        ref     => 'w',
        scale_m => '1.0e-6',
    },

    mw => {
        ref     => 'w',
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
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
        },
    },

    uwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-6',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
        },
    },

    mwpscm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
        },
    },

    mwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
        },
    },

    wpscm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
        },
    },

    wpsm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        tmpl      => '%value% %suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value% %txt% pro %txt_sq%',
            en => '%value% %txt% per %txt_sq%',
            fr => '%value% %txt% per %txt_sq%',
            nl => '%value% %txt% per %txt_sq%',
            pl => '%value% %txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value% %txt_pl% pro %txt_sq%',
            en => '%value% %txt_pl% per %txt_sq%',
            fr => '%value% %txt_pl% per %txt_sq%',
            nl => '%value% %txt_pl% per %txt_sq%',
            pl => '%value% %txt_pl% per %txt_sq%',
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

};

my $readingsDB = {
    airpress => {
        aliasname => 'pressure_hpa',    # alias only
    },
    azimuth => {
        rtype => 'gon',
    },
    compasspoint => {
        rtype => 'compasspoint'
    },
    daylight => {
        rtype => 'bool',
    },
    dewpoint => {
        aliasname => 'dewpoint_c',      # alias only
    },
    dewpoint_c => {
        rtype => 'c',
    },
    dewpoint_f => {
        rtype => 'f',
    },
    dewpoint_k => {
        rtype => 'k',
    },
    elevation => {
        rtype => 'gon',
    },
    feelslike => {
        aliasname => 'feelslike_c',    # alias only
    },
    feelslike_c => {
        rtype => 'c',
    },
    feelslike_f => {
        rtype => 'f',
    },
    heat_index => {
        aliasname => 'heat_index_c',    # alias only
    },
    heat_index_c => {
        rtype => 'c',
    },
    heat_index_f => {
        rtype => 'f',
    },
    high_c => {
        rtype => 'c',
    },
    high_f => {
        rtype => 'f',
    },
    humidity => {
        rtype => 'pct',
    },
    humidityabs => {
        aliasname => 'humidityabs_c',    # alias only
    },
    humidityabs_c => {
        rtype => 'c',
    },
    humidityabs_f => {
        rtype => 'f',
    },
    humidityabs_k => {
        rtype => 'k',
    },
    horizon => {
        rtype => 'gon',
    },
    indoordewpoint => {
        aliasname => 'indoordewpoint_c',    # alias only
    },
    indoordewpoint_c => {
        rtype => 'c',
    },
    indoordewpoint_f => {
        rtype => 'f',
    },
    indoordewpoint_k => {
        rtype => 'k',
    },
    indoorhumidity => {
        rtype => 'pct',
    },
    indoorhumidityabs => {
        aliasname => 'indoorhumidityabs_c',    # alias only
    },
    indoorhumidityabs_c => {
        rtype => 'c',
    },
    indoorhumidityabs_f => {
        rtype => 'f',
    },
    indoorhumidityabs_k => {
        rtype => 'k',
    },
    indoortemperature => {
        aliasname => 'indoortemperature_c',    # alias only
    },
    indoortemperature_c => {
        rtype => 'c',
    },
    indoortemperature_f => {
        rtype => 'f',
    },
    indoortemperature_k => {
        rtype => 'k',
    },
    israining => {
        rtype => 'bool',
    },
    level => {
        rtype => 'pct',
    },
    low_c => {
        rtype => 'c',
    },
    low_f => {
        rtype => 'f',
    },
    luminosity => {
        rtype => 'lx',
    },
    pct => {
        rtype => 'pct',
    },
    pressure => {
        aliasname => 'pressure_hpa',    # alias only
    },
    pressure_hpa => {
        rtype => 'hpamb',
    },
    pressure_in => {
        rtype => 'inhg',
    },
    pressure_mm => {
        rtype => 'mmhg',
    },
    pressure_psi => {
        rtype => 'psi',
    },
    pressure_psig => {
        rtype => 'psig',
    },
    pressureabs => {
        aliasname => 'pressureabs_hpamb',    # alias only
    },
    pressureabs_hpamb => {
        rtype => 'hpamb',
    },
    pressureabs_in => {
        rtype => 'inhg',
    },
    pressureabs_mm => {
        rtype => 'mmhg',
    },
    pressureabs_psi => {
        rtype => 'psia',
    },
    pressureabs_psia => {
        rtype => 'psia',
    },
    rain => {
        aliasname => 'rain_mm',    # alias only
    },
    rain_mm => {
        rtype => 'mm',
    },
    rain_in => {
        rtype => 'in',
    },
    rain_day => {
        aliasname => 'rain_day_mm',    # alias only
    },
    rain_day_mm => {
        rtype => 'mm',
    },
    rain_day_in => {
        rtype => 'in',
    },
    rain_night => {
        aliasname => 'rain_night_mm',    # alias only
    },
    rain_night_mm => {
        rtype => 'mm',
    },
    rain_night_in => {
        rtype => 'in',
    },
    rain_week => {
        aliasname => 'rain_week_mm',     # alias only
    },
    rain_week_mm => {
        rtype => 'mm',
    },
    rain_week_in => {
        rtype => 'in',
    },
    rain_month => {
        aliasname => 'rain_month_mm',    # alias only
    },
    rain_month_mm => {
        rtype => 'mm',
    },
    rain_month_in => {
        rtype => 'in',
    },
    rain_year => {
        aliasname => 'rain_year_mm',     # alias only
    },
    rain_year_mm => {
        rtype => 'mm',
    },
    rain_year_in => {
        rtype => 'in',
    },
    snow => {
        aliasname => 'snow_cm',          # alias only
    },
    snow_cm => {
        rtype => 'cm',
    },
    snow_in => {
        rtype => 'in',
    },
    snow_day => {
        aliasname => 'snow_day_cm',      # alias only
    },
    snow_day_cm => {
        rtype => 'cm',
    },
    snow_day_in => {
        rtype => 'in',
    },
    snow_night => {
        aliasname => 'snow_night_cm',    # alias only
    },
    snow_night_cm => {
        rtype => 'cm',
    },
    snow_night_in => {
        rtype => 'in',
    },
    sunshine => {
        aliasname => 'solarradiation',    # alias only
    },
    solarradiation => {
        rtype => 'wpsm',
    },
    temp => {
        aliasname => 'temperature_c',     # alias only
    },
    temp_c => {
        aliasname => 'temperature_c',     # alias only
    },
    temp_f => {
        aliasname => 'temperature_f',     # alias only
    },
    temp_k => {
        aliasname => 'temperature_k',     # alias only
    },
    temperature => {
        aliasname => 'temperature_c',     # alias only
    },
    temperature_c => {
        rtype => 'c',
    },
    temperature_f => {
        rtype => 'f',
    },
    temperature_k => {
        rtype => 'k',
    },
    uv => {
        aliasname => 'uvi',               # alias only
    },
    uvi => {
        rtype => 'uvi',
    },
    uvr => {
        rtype => 'uwpscm',
    },
    valvedesired => {
        aliasname => 'valve',             # alias only
    },
    valvepos => {
        aliasname => 'valve',             # alias only
    },
    valveposition => {
        aliasname => 'valve',             # alias only
    },
    valvepostc => {
        aliasname => 'valve',             # alias only
    },
    valve => {
        rtype => 'pct',
    },
    visibility => {
        aliasname => 'visibility_km',     # alias only
    },
    visibility_km => {
        rtype => 'km',
    },
    visibility_mi => {
        rtype => 'mi',
    },
    wind_chill => {
        aliasname => 'wind_chill_c',      # alias only
    },
    wind_chill_c => {
        rtype => 'c',
    },
    wind_chill_f => {
        rtype => 'f',
    },
    wind_chill_k => {
        rtype => 'k',
    },
    wind_compasspoint => {
        rtype => 'compasspoint'
    },
    windspeeddirection => {
        aliasname => 'wind_compasspoint',    # alias only
    },
    winddirectiontext => {
        aliasname => 'wind_compasspoint',    # alias only
    },
    wind_direction => {
        rtype => 'direction',
    },
    wind_dir => {
        aliasname => 'wind_direction',       # alias only
    },
    winddir => {
        aliasname => 'wind_direction',       # alias only
    },
    winddirection => {
        aliasname => 'wind_direction',       # alias only
    },
    wind_gust => {
        aliasname => 'wind_gust_kmh',        # alias only
    },
    wind_gust_kmh => {
        rtype => 'kmh',
    },
    wind_gust_bft => {
        rtype => 'bft',
    },
    wind_gust_fts => {
        rtype => 'fts',
    },
    wind_gust_kn => {
        rtype => 'kn',
    },
    wind_gust_mph => {
        rtype => 'mph',
    },
    wind_gust_mps => {
        rtype => 'mps',
    },
    wind_speed => {
        aliasname => 'wind_speed_kmh',    # alias only
    },
    wind_speed_kmh => {
        rtype => 'kmh',
    },
    wind_speed_bft => {
        rtype => 'bft',
    },
    wind_speed_fts => {
        rtype => 'fts',
    },
    wind_speed_kn => {
        rtype => 'kn',
    },
    wind_speed_mph => {
        rtype => 'mph',
    },
    wind_speed_mps => {
        rtype => 'mps',
    },
};

# Get rtype details in local language from reading name as hash
sub GetDetailsFromReadingname ($$@) {
    my ( $name, $reading, $lang ) = @_;
    my $details;
    my $r = $reading;
    my $l = ( $lang ? lc($lang) : "en" );
    my $rt;
    my $guess;
    my %return;

    # remove some prefix or other values to
    # flatten reading name
    $r =~ s/^fc\d+_//i;
    $r =~ s/_(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)_/_/i;
    $r =~ s/^(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)_//i;
    $r =~ s/_(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m)$//i;
    $r =~ s/.*[-_](temp)$/$1/i;

    # rename capital letter containing readings
    if ( !$readingsDB->{ lc($r) } ) {
        $r =~ s/^([A-Z])(.*)/\l$1$2/;
        $r =~ s/([A-Z][a-z0-9]+)[\/\|\-_]?/_$1/g;
    }

    $r = lc($r);

    # known aliasname reading names
    if ( $readingsDB->{$r}{aliasname} ) {
        my $dr = $readingsDB->{$r}{aliasname};
        $return{aliasname} = $dr;
        $return{shortname} = $readingsDB->{$dr}{shortname};
        $rt                = (
              $readingsDB->{$dr}{rtype}
            ? $readingsDB->{$dr}{rtype}
            : "-"
        );
    }

    # known standard reading names
    elsif ( $readingsDB->{$r}{shortname} ) {
        $return{aliasname} = $reading;
        $return{shortname} = $readingsDB->{$r}{shortname};
        $rt                = (
              $readingsDB->{$r}{rtype}
            ? $readingsDB->{$r}{rtype}
            : "-"
        );
    }

    # just guessing the rtype from reading name format
    elsif ( $r =~ /^.*_([A-Za-z]+)$/i ) {
        $guess = 1;
        $rt    = $1;
    }

    return if ( !%return && !$rt );
    return \%return if ( !$rt );

    my $rdetails = GetDetails( $name, $rt, $l );

    if ( ref($rdetails) eq "HASH" ) {
        $return{rtype_guess} = "1" if ($guess);
        foreach my $k ( keys %{$rdetails} ) {
            $return{$k} = $rdetails->{$k};
        }
    }

    return \%return;
}

# # Get rtype list in local language as hash
# sub GetList (@) {
#     my ( $name, $lang, $rtype ) = @_;
#     my $l = ( $lang ? lc($lang) : "en" );
#     my %list;
#
#     my %DB = %rtypes;
#     my $getKeyValueAttr = ::getKeyValueAttr( $name, "readingsFormat" );
#
#     foreach ( keys %{$getKeyValueAttr} ) {
#         $DB{$_} = $getKeyValueAttr->{$_};
#     }
#
#     foreach my $rt ( keys %DB ) {
#         my $details = GetDetails( $name, $rt, $lang );
#         my $tn = (
#               $details->{txt_base}
#             ? $details->{txt_base}
#             : "others"
#         );
#         $list{$tn}{$rt} = $details
#           if ( !$rtype || lc($rtype) eq $tn );
#     }
#
#     return \%list;
# }
#
# # Get rtype details in local language as hash
# sub GetDetails ($$@) {
#     my ( $name, $rtype, $lang ) = @_;
#     my $l = ( $lang ? lc($lang) : "en" );
#     my %details;
#     my $attribute = "readingsFormat";
#
#     my %DB = %rtypes;
#     my $getKeyValueAttr = ::getKeyValueAttr( $name, "readingsFormat" );
#
#     foreach ( keys %{$getKeyValueAttr} ) {
#         $DB{$_} = $getKeyValueAttr->{$_};
#     }
#
#     if ( defined( $DB{$rtype} ) ) {
#         foreach my $k ( keys %{ $DB{$rtype} } ) {
#             delete $details{$k} if ( $details{$k} );
#             $details{$k} = $DB{$rtype}{$k};
#         }
#         $details{rtype} = $rtype;
#
#         foreach ( 'ref', 'ref_t', 'ref_sq', 'ref_cu' ) {
#             my $suffix = $_;
#             $suffix =~ s/^[a-z]+//;
#             if ( defined( $details{$_} ) ) {
#                 my $ref = $details{$_};
#                 if ( !defined( $DB{$ref} ) ) {
#                     ::Log 1, "GetDetails($rtype) broken reference $_";
#                     next;
#                 }
#                 foreach my $k ( keys %{ $DB{$ref} } ) {
#                     next
#                       if ( $k =~ /^scale/ )
#                       ;    # exclude scales from referenced rtype
#                     if ( !defined( $details{$k} ) ) {
#                         $details{$k} = $DB{$ref}{$k};
#                     }
#                     else {
#                         $details{ $k . $suffix } = $DB{$ref}{$k}
#                           if ( !defined( $details{ $k . $suffix } ) );
#                     }
#                 }
#             }
#         }
#
#         if ( $details{scale_m} ) {
#             my $ref = $details{scale_m};
#             foreach my $k ( keys %{ $scales_m{$ref} } ) {
#                 $details{$k} = $scales_m{$ref}{$k}
#                   if ( !defined( $details{$k} ) );
#             }
#         }
#         if ( $details{scale_sq} ) {
#             foreach my $k ( keys %scales_sq ) {
#                 $details{$k} = $scales_sq{$k}
#                   if ( !defined( $details{$k} ) );
#             }
#             my $ref = $details{scale_sq};
#             foreach my $k ( keys %{ $scales_m{$ref} } ) {
#                 $details{ $k . "_sq" } = $scales_m{$ref}{$k}
#                   if ( !defined( $details{ $k . "_sq" } ) );
#             }
#         }
#         if ( $details{scale_cu} ) {
#             foreach my $k ( keys %scales_cu ) {
#                 $details{$k} = $scales_cu{$k}
#                   if ( !defined( $details{$k} ) );
#             }
#             my $ref = $details{scale_cu};
#             foreach my $k ( keys %{ $scales_m{$ref} } ) {
#                 $details{ $k . "_cu" } = $scales_m{$ref}{$k}
#                   if ( !defined( $details{ $k . "_cu" } ) );
#             }
#         }
#
#         if ( defined( $details{ref_base} ) ) {
#             my $ref = $details{ref_base};
#             foreach my $k ( keys %{ $rtype_base{$ref} } ) {
#                 $details{$k} = $rtype_base{$ref}{$k}
#                   if ( !defined( $details{$k} ) );
#             }
#         }
#
#         if ($lang) {
#
#             # keep only defined language if set
#             $l = $details{lang} if ( $details{lang} );
#             $details{lang} = $l if ( !$details{lang} );
#             foreach ( keys %details ) {
#                 if ( $details{$_}
#                     && ref( $details{$_} ) eq "HASH" )
#                 {
#                     my $v;
#                     $v = $details{$_}{$l}
#                       if ( $details{$_}{$l} );
#                     delete $details{$_};
#                     $details{$_} = $v if ($v);
#                 }
#             }
#
#             # add metric name to suffix
#             $details{suffix} = $details{scale_txt_m} . $details{suffix}
#               if ( $details{suffix} && $details{scale_txt_m} );
#             $details{txt} = $details{scale_txt_long_m} . lc( $details{txt} )
#               if ( $details{txt} && $details{scale_txt_long_m} );
#
#             # add square information to suffix and txt
#             # if no separate suffix_sq and txt_sq was found
#             $details{suffix} = $details{suffix} . $details{scale_txt_sq}
#               if ( !$details{suffix_sq} && $details{scale_txt_sq} );
#             $details{txt} = $details{scale_txt_long_sq} . lc( $details{txt} )
#               if ( !$details{txt_sq} && $details{scale_txt_long_sq} );
#
#             # add cubic information to suffix and txt
#             # if no separate suffix_cu and txt_cu was found
#             $details{suffix} = $details{suffix} . $details{scale_txt_cu}
#               if ( !$details{suffix_cu} && $details{scale_txt_cu} );
#             $details{txt} = $details{scale_txt_long_cu} . lc( $details{txt} )
#               if ( !$details{txt_cu} && $details{scale_txt_long_cu} );
#
#             # add metric name to suffix_sq
#             $details{suffix_sq} = $details{scale_txt_m_sq} . $details{suffix_sq}
#               if ( $details{suffix_sq} && $details{scale_txt_m_sq} );
#             $details{txt_sq} =
#               $details{scale_txt_long_m_sq} . lc( $details{txt_sq} )
#               if ( $details{txt_sq} && $details{scale_txt_long_m_sq} );
#
#             # add square information to suffix_sq
#             $details{suffix_sq} = $details{suffix_sq} . $details{scale_txt_sq}
#               if ( $details{suffix_sq} && $details{scale_txt_sq} );
#             $details{txt_sq} =
#               $details{scale_txt_long_sq} . lc( $details{txt_sq} )
#               if ( $details{txt_sq} && $details{scale_txt_long_sq} );
#
#             # add metric name to suffix_cu
#             $details{suffix_cu} = $details{scale_txt_m_cu} . $details{suffix_cu}
#               if ( $details{suffix_cu} && $details{scale_txt_m_cu} );
#             $details{txt_cu} =
#               $details{scale_txt_long_m_cu} . lc( $details{txt_cu} )
#               if ( $details{txt_cu} && $details{scale_txt_long_m_cu} );
#
#             # add cubic information to suffix_cu
#             $details{suffix_cu} = $details{suffix_cu} . $details{scale_txt_cu}
#               if ( $details{suffix_cu} && $details{scale_txt_cu} );
#             $details{txt_cu} =
#               $details{scale_txt_long_cu} . lc( $details{txt_cu} )
#               if ( $details{txt_cu} && $details{scale_txt_long_cu} );
#         }
#
#         return \%details;
#     }
# }

######################################
# package main
#
package main;

# Get value + rtype combined string
sub replaceTemplate ($@) {
    my ( $value, $desc ) = @_;
    my $txt;
    my $txt_long;
    return $value
      if (!$value
        || $value eq ""
        || !$desc
        || ref($desc) ne "HASH"
        || ( !$desc->{suffix} && !$desc->{symbol} ) );

    $desc->{value} = $value;

    # shortname
    $txt = '%value% %suffix%';
    $txt = $desc->{tmpl} if ( $desc->{tmpl} );
    foreach my $k ( keys %{$desc} ) {
        $txt =~ s/%$k%/$desc->{$k}/g;
    }

    return ($txt) if ( !wantarray );

    # long plural
    if (   Scalar::Util::looks_like_number($value)
        && $value > 1
        && $desc->{txt_pl} )
    {
        $txt_long = '%value% %txt_pl%';
        $txt_long = $desc->{tmpl_long_pl}
          if ( $desc->{tmpl_long_pl} );
    }

    # long singular
    elsif ( $desc->{txt} ) {
        $txt_long = '%value% %txt%';
        $txt_long = $desc->{tmpl_long}
          if ( $desc->{tmpl_long} );
    }

    if ($txt_long) {
        foreach my $k ( keys %{$desc} ) {
            $txt_long =~ s/%$k%/$desc->{$k}/g;
        }
    }

    return ( $txt, $txt_long );
}

# format a number according to desc and optional format.
sub formatValue($$;$$) {
    my ( $value, $desc, $format, $lang ) = @_;

    return $value if ( !defined($value) );

    $desc = GetDetails( undef, $desc, $lang ) if ( $desc && !ref($desc) );
    return $value if ( !$format && ( !$desc || ref($desc) ne 'HASH' ) );

    $value *= $desc->{factor} if ( $desc && $desc->{factor} );
    $format = $desc->{format} if ( !$format && $desc );
    $format = $autoscale_m if ( !$format );

    if ( ref($format) eq 'CODE' ) {
        $value = $format->($value);
    }
    elsif ( ref($format) eq 'HASH' && looks_like_number($value) ) {
        my $v = abs($value);
        foreach my $l ( sort { $b <=> $a } keys( %{$format} ) ) {
            next if ( ref( $format->{$l} ) ne 'HASH' || !$format->{$l}{scale} );
            if ( $v >= $l ) {
                my $scale = $format->{$l}{scale};

                $value *= $scale if ($scale);
                $value = sprintf( $format->{$l}{format}, $value )
                  if ( $format->{$l}{format} );

                # if ($scale) {
                #     if ( my $scale = $scales->{$scale} ) {
                #         $suffix .= $scale;
                #     }
                # }
                last;
            }
        }
    }
    elsif ( ref($format) eq 'ARRAY' ) {

    }
    elsif ($format) {
        my $scale = $desc->{scale};

        $value *= $scale if ($scale);

        #        $value = sprintf( $format, $value );

        # if ($scale) {
        #     if ( my $scale = $scales->{$scale} ) {
        #         $suffix .= $scale;
        #     }
        # }
    }

    my ( $txt, $txt_long ) = replaceTemplate( $value, $desc );

    return ( $txt, $txt_long ) if (wantarray);
    return $txt;
}

# find desc and optional format for device:reading
sub readingsDesc($;$$) {
    my ( $device, $reading, $lang ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    my $fdesc = getKeyValueAttr( $device, "readingsDesc" );
    my $desc;
    $desc = $fdesc->{$reading}
      if ( $reading && defined( $fdesc->{$reading} ) );
    $desc = $fdesc
      if ( !$reading );

    my $rtype;
    $rtype = $desc->{rtype} if ( $desc->{rtype} );

    if ( $rtype && defined( $rtypes->{$rtype} ) ) {
        foreach my $k ( keys %{ $rtypes->{$rtype} } ) {
            delete $desc->{$k} if ( $desc->{$k} );
            $desc->{$k} = $rtypes->{$rtype}{$k};
        }

        foreach ( 'ref', 'ref_t', 'ref_sq', 'ref_cu' ) {
            my $suffix = $_;
            $suffix =~ s/^[a-z]+//;
            if ( defined( $desc->{$_} ) ) {
                my $ref = $desc->{$_};
                if ( !defined( $rtypes->{$ref} ) ) {
                    Log 1, "readingsDesc($rtype) broken reference $_";
                    next;
                }
                foreach my $k ( keys %{ $rtypes->{$ref} } ) {
                    next
                      if ( $k =~ /^scale/ )
                      ;    # exclude scales from referenced rtype
                    if ( !defined( $desc->{$k} ) ) {
                        $desc->{$k} = $rtypes->{$ref}{$k};
                    }
                    else {
                        $desc->{ $k . $suffix } = $rtypes->{$ref}{$k}
                          if ( !defined( $desc->{ $k . $suffix } ) );
                    }
                }
            }
        }

        if ( $desc->{scale_m} ) {
            my $ref = $desc->{scale_m};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{$k} = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{$k} ) );
            }
        }
        if ( $desc->{scale_sq} ) {
            foreach my $k ( keys %{$scales_sq} ) {
                $desc->{$k} = $scales_sq->{$k}
                  if ( !defined( $desc->{$k} ) );
            }
            my $ref = $desc->{scale_sq};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{ $k . "_sq" } = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{ $k . "_sq" } ) );
            }
        }
        if ( $desc->{scale_cu} ) {
            foreach my $k ( keys %{$scales_cu} ) {
                $desc->{$k} = $scales_cu->{$k}
                  if ( !defined( $desc->{$k} ) );
            }
            my $ref = $desc->{scale_cu};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{ $k . "_cu" } = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{ $k . "_cu" } ) );
            }
        }

        if ( defined( $desc->{ref_base} ) ) {
            my $ref = $desc->{ref_base};
            foreach my $k ( keys %{ $rtype_base->{$ref} } ) {
                $desc->{$k} = $rtype_base->{$ref}{$k}
                  if ( !defined( $desc->{$k} ) );
            }
        }

        # keep only defined language if set
        foreach ( keys %{$desc} ) {
            if ( $desc->{$_}
                && ref( $desc->{$_} ) eq "HASH" )
            {
                my $v;
                $v = $desc->{$_}{$l}
                  if ( $desc->{$_}{$l} );
                delete $desc->{$_};
                $desc->{$_} = $v if ($v);
            }
        }

        # add metric name to suffix
        $desc->{suffix} = $desc->{scale_txt_m} . $desc->{suffix}
          if ( $desc->{suffix}
            && $desc->{scale_txt_m}
            && $desc->{suffix} !~ /^$desc->{scale_txt_m}/ );
        $desc->{txt} = $desc->{scale_txt_long_m} . lc( $desc->{txt} )
          if ( $desc->{txt}
            && $desc->{scale_txt_long_m}
            && $desc->{txt} !~ /^$desc->{scale_txt_long_m}/ );

        # add square information to suffix and txt
        # if no separate suffix_sq and txt_sq was found
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_sq}
          if (!$desc->{suffix_sq}
            && $desc->{scale_txt_sq}
            && $desc->{suffix} !~ /$desc->{scale_txt_sq}/ );
        $desc->{txt} = $desc->{scale_txt_long_sq} . lc( $desc->{txt} )
          if (!$desc->{txt_sq}
            && $desc->{scale_txt_long_sq}
            && $desc->{suffix} !~ /$desc->{scale_txt_long_sq}/ );

        # add cubic information to suffix and txt
        # if no separate suffix_cu and txt_cu was found
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_cu}
          if (!$desc->{suffix_cu}
            && $desc->{scale_txt_cu}
            && $desc->{suffix} !~ /$desc->{scale_txt_cu}/ );
        $desc->{txt} = $desc->{scale_txt_long_cu} . lc( $desc->{txt} )
          if (!$desc->{txt_cu}
            && $desc->{scale_txt_long_cu}
            && $desc->{txt} !~ /$desc->{scale_txt_long_cu}/ );

        # add metric name to suffix_sq
        $desc->{suffix_sq} = $desc->{scale_txt_m_sq} . $desc->{suffix_sq}
          if ( $desc->{suffix_sq}
            && $desc->{scale_txt_m_sq}
            && $desc->{suffix_sq} !~ /$desc->{scale_txt_m_sq}/ );
        $desc->{txt_sq} = $desc->{scale_txt_long_m_sq} . lc( $desc->{txt_sq} )
          if ( $desc->{txt_sq}
            && $desc->{scale_txt_long_m_sq}
            && $desc->{txt_sq} !~ /$desc->{scale_txt_long_m_sq}/ );

        # # add square information to suffix_sq
        $desc->{suffix_sq} = $desc->{suffix_sq} . $desc->{scale_txt_sq}
          if ( $desc->{suffix_sq}
            && $desc->{scale_txt_sq}
            && $desc->{suffix_sq} !~ /$desc->{scale_txt_sq}/ );
        $desc->{txt_sq} = $desc->{scale_txt_long_sq} . lc( $desc->{txt_sq} )
          if ( $desc->{txt_sq}
            && $desc->{scale_txt_long_sq}
            && $desc->{txt_sq} !~ /$desc->{scale_txt_long_sq}/ );

        # add metric name to suffix_cu
        $desc->{suffix_cu} = $desc->{scale_txt_m_cu} . $desc->{suffix_cu}
          if ( $desc->{suffix_cu}
            && $desc->{scale_txt_m_cu}
            && $desc->{suffix_cu} !~ /$desc->{scale_txt_m_cu}/ );
        $desc->{txt_cu} = $desc->{scale_txt_long_m_cu} . lc( $desc->{txt_cu} )
          if ( $desc->{txt_cu}
            && $desc->{scale_txt_long_m_cu}
            && $desc->{txt_cu} !~ /$desc->{scale_txt_long_m_cu}/ );

        # add cubic information to suffix_cu
        $desc->{suffix_cu} = $desc->{suffix_cu} . $desc->{scale_txt_cu}
          if ( $desc->{suffix_cu}
            && $desc->{scale_txt_cu}
            && $desc->{suffix_cu} !~ /$desc->{scale_txt_cu}/ );
        $desc->{txt_cu} = $desc->{scale_txt_long_cu} . lc( $desc->{txt_cu} )
          if ( $desc->{txt_cu}
            && $desc->{scale_txt_long_cu}
            && $desc->{txt_cu} !~ /$desc->{scale_txt_long_cu}/ );
    }

    ######################
    my $fformat = getKeyValueAttr( $device, "readingsFormat" );
    my $format;
    $format = $fformat->{$reading}
      if ( $reading && defined( $fformat->{$reading} ) );
    $format = $format->{$reading} if ( ref($format) eq 'HASH' );

    return ( $desc, $format ) if (wantarray);
    return $desc;
}

#format device:reading with optional default value and optional desc and optional format
sub formatReading($$;$$$$) {
    my ( $device, $reading, $default, $desc, $format, $lang ) = @_;

    $desc = readingsDesc( $device, $reading, $lang ) if ( !$desc && $format );
    ( $desc, $format ) = readingsDesc( $device, $reading, $lang )
      if ( !$desc && !$format );

    my $value = ReadingsVal( $device, $reading, undef );

    $value = $default if ( !defined($value) );
    return formatValue( $value, $desc, $format );
}

# return unit symbol for device:reading
sub readingsUnit($$) {
    my ( $device, $reading ) = @_;

    if ( my $desc = readingsDesc( $device, $reading ) ) {
        return $desc->{symbol} if ( $desc->{symbol} );
        return $desc->{suffix} if ( $desc->{suffix} );
    }

    return '';
}

# return dimension symbol for device:reading
sub readingsShortname($$) {
    my ( $device, $reading ) = @_;

    if ( my $desc = readingsDesc( $device, $reading ) ) {
        return $desc->{dimension}      if ( $desc->{dimension} && $desc->{dimension} =~ /^[A-Z]+$/ );
        return $desc->{formula_symbol} if ( $desc->{formula_symbol} );
    }

    return $reading;
}

#format device STATE readings according to stateFormat and optional units
sub makeSTATE($;$$) {
    my ( $device, $stateFormat, $withUnits ) = @_;
    $stateFormat = '' if ( !$stateFormat );

    my $hash = $defs{$device};
    return $stateFormat if ( !$hash );

    $stateFormat = AttrVal( $device, 'stateFormat', undef )
      if ( !$stateFormat );
    return '' if ( !$stateFormat );

    if ( $stateFormat =~ m/^{(.*)}$/ ) {
        $stateFormat = eval $1;
        if ($@) {
            $stateFormat = "Error evaluating $device stateFormat: $@";
            Log 1, $stateFormat;
        }

    }
    else {
        my $r = $hash->{READINGS};
        if ($withUnits) {
            $stateFormat =~
s/\b([A-Za-z\d_\.-]+)\b/($r->{$1} ? readingsShortname($device,$1). ": ". formatReading($device,$1) : $1)/ge;
        }
        else {
            $stateFormat =~
s/\b([A-Za-z\d_\.-]+)\b/($r->{$1} ? readingsShortname($device,$1). ": ". (formatReading($device,$1))[0] : $1)/ge;
        }

    }

    return $stateFormat;
}

# get combined hash for settings from module, device, global and device attributes
sub getKeyValueAttr($;$$) {
    my ( $name, $attribute, $reading ) = @_;
    my $d          = $defs{$name};
    my $m          = $modules{ $d->{TYPE} } if ( $d && $d->{TYPE} );
    my $globalDesc = decode_attribute( "global", $attribute ) if ($attribute);
    my $attrDesc   = decode_attribute( $name, $attribute )
      if ( $name ne "global" && $attribute );

    my %desc;

    # module device specific
    if ( $d && $d->{$attribute} ) {
        %desc = %{ $d->{$attribute} };
    }

    # module general
    elsif ( $m && $m->{$attribute} ) {
        %desc = %{ $m->{$attribute} };
    }

    # global user overwrite
    if ($globalDesc) {
        foreach ( keys %{$globalDesc} ) {
            delete $desc{$_} if ( $desc{$_} );
            $desc{$_} = $globalDesc->{$_};
        }
    }

    # device user overwrite
    if ($attrDesc) {
        foreach ( keys %{$attrDesc} ) {
            delete $desc{$_} if ( $desc{$_} );
            $desc{$_} = $attrDesc->{$_};
        }
    }

    return if ( $reading && !defined( $desc{$reading} ) );
    return $desc{$reading} if ($reading);
    return \%desc;
}

# save key/value pair to device attribute
sub setKeyValueAttr($$$$$) {
    my ( $name, $attribute, $reading, $desc, $value ) = @_;
    my $ret;
    my $getKeyValueAttr = getKeyValueAttr( $name, $attribute );

    return
      if ( $getKeyValueAttr->{$reading}{$desc}
        && $getKeyValueAttr->{$reading}{$desc} eq $value );

    # rtype
    if ( $desc =~ /^rtype$/i ) {
        my $rdetails;
        $desc = lc($desc);

        # check database for correct rtype
        if ( $value && $value ne "?" ) {
            $rdetails = GetDetails( $name, $value );
        }

        # find rtype based on reading name
        else {
            $rdetails = GetDetailsFromReadingname( $name, $reading );
            return
              if ( !$rdetails || !defined( $rdetails->{rtype} ) );
        }

        return
"Invalid value $value for $desc: Cannot be assigned to device $name $reading"
          if ( !$rdetails || !defined( $rdetails->{rtype} ) );

        return
          if ( $getKeyValueAttr->{$reading}{$desc}
            && $getKeyValueAttr->{$reading}{$desc} eq $rdetails->{rtype} );

        $ret =
            "Changed value $desc='"
          . $getKeyValueAttr->{$reading}{$desc}
          . "' for device $name $reading to: "
          . $rdetails->{rtype}
          if ( $getKeyValueAttr->{$reading}{$desc}
            && $getKeyValueAttr->{$reading}{$desc} ne $rdetails->{rtype} );

        $ret =
          "Set auto-detected $desc for device $name $reading: "
          . $rdetails->{rtype}
          if ( !$value && !$getKeyValueAttr->{$reading}{$desc} );

        $value = $rdetails->{rtype};
    }

    # update attribute
    my $attrDesc = decode_attribute( $name, $attribute );
    $attrDesc->{$reading}{$desc} = $value;
    encode_attribute( $name, $attribute, $attrDesc );
    return $ret;
}

sub deleteKeyValueAttr($$$;$) {
    my ( $name, $attribute, $reading, $desc ) = @_;
    my $rt;
    my $attrDesc = decode_attribute( $name, $attribute );

    return
      if ( !defined( $attrDesc->{$reading} )
        || ( $desc && !defined( $attrDesc->{$reading}{$desc} ) ) );

    if ($desc) {
        $rt = " $desc=" . $attrDesc->{$reading}{$desc};
        delete $attrDesc->{$reading}{$desc};
    }

    delete $attrDesc->{$reading}
      if ( !$desc || keys %{ $attrDesc->{$reading} } < 1 );

    # update attribute
    encode_attribute( $name, $attribute, $attrDesc );
    return "Removed $reading$rt from attribute $name $attribute";
}

sub encode_attribute ($$$) {
    my ( $name, $attribute, $data ) = @_;
    my $json;
    my $js;

    if ( !$data || keys %{$data} < 1 ) {
        CommandDeleteAttr( undef, "$name $attribute" );

        # empty cache
        delete $defs{$name}{'.attrCache'}
          if ( defined( $defs{$name}{'.attrCache'} ) );
        return;
    }

    eval {
        $json =
          JSON::PP->new->utf8->indent->indent_length(1)
          ->canonical->allow_nonref;
        1;
    };
    return $@ if ($@);

    eval { $js = $json->encode($data); 1 };
    return $@ if ( $@ || !$js || $js eq "" );

    # use Data::Dumper;
    # $Data::Dumper::Terse = 1;
    # my $js2 = Dumper($data);
    # Log 1,
    #   "DEBUG \n $js2";

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
        my $data;
        eval { $data = decode_json( $attr{$name}{$attribute} ); 1 };
        return if ( $@ || !$data || $data eq "" );
        $defs{$name}{'.attrCache'}{$attribute} = $data;
    }

    return $defs{$name}{'.attrCache'}{$attribute};
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
            ? formatReading( $d, $1, "", undef, undef, $lang )
            : ReadingsVal( $d, $1, "" )
        );
        my $n = ( $2 ? $2 : readingsShortname( $d, $1 ) );

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

# Generalized function for DbLog rtype support
sub Unit_DbLog_split($$) {
    my ( $event, $name ) = @_;
    my ( $reading, $value, $rtype ) = "";

    # exclude any multi-value events
    if ( $event =~ /(.*: +.*: +.*)+/ ) {
        Log3 $name, 5,
          "Unit_DbLog_split $name: Ignoring multi-value event $event";
        return undef;
    }

    # exclude sum/cum and avg events
    elsif ( $event =~ /^(.*_sum[0-9]+m|.*_cum[0-9]+m|.*_avg[0-9]+m): +.*/ ) {
        Log3 $name, 5, "Unit_DbLog_split $name: Ignoring sum/avg event $event";
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
        $value   = ReadingsNum( $name, $1, $2 );
        $rtype   = ReadingsFormated( $name, $1, $3 );
    }

    if ( !Scalar::Util::looks_like_number($value) ) {
        Log3 $name, 5,
"Unit_DbLog_split $name: Ignoring event $event: value does not look like a number";
        return undef;
    }

    Log3 $name, 5,
"Unit_DbLog_split $name: Splitting event $event > reading=$reading value=$value rtype=$rtype";

    return ( $reading, $value, $rtype );
}

################################################################
#
# User commands
#
################################################################

# command: rtype
my %rtypehash = (
    Fn  => "CommandType",
    Hlp => "[<devspec>] [<readingspec>],get rtype for <devspec> <reading>",
);
$cmds{rtype} = \%rtypehash;

sub CommandType($$) {
    my ( $cl, $def ) = @_;
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my @a = split( " ", $def, 2 );
    return "Usage: rtype [<name>] [<readingspec>]\n$namedef"
      if ( $a[0] && $a[0] eq "?" );

    $a[0] = "global" if ( !$a[0] || $a[0] eq "" );
    $a[1] = ".*"     if ( !$a[1] || $a[1] eq "" );

    my @rets;
    foreach my $name ( devspec2array( $a[0], $cl ) ) {
        if ( !defined( $defs{$name} ) ) {
            push @rets, "Please define $name first";
            next;
        }

        if ( $a[0] eq "global" ) {
            my $ret = Dumper( GetList( undef, undef ) );
            push @rets, $ret
              if ($ret);
            last;
        }

        my $readingspec = '^' . $a[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{READINGS} }
          )
        {
            my $ret = Dumper( GetList( $name, undef ) );
            push @rets, $ret
              if ($ret);
        }
    }
    return join( "\n", @rets );
}

# command: setreadingdesc
my %setreadingdeschash = (
    Fn => "CommandSetReadingDesc",
    Hlp =>
"<devspec> <readingspec> [noCheck] <key>=[<value>|?],set reading rtype information for <devspec> <reading>",
);
$cmds{setreadingdesc} = \%setreadingdeschash;

sub CommandSetReadingDesc($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsDesc";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );

    return
"Usage: setreadingdesc <devspec> <readingspec> [noCheck] <key>=[<value>|?]\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" || !%{$h} );

    my @rets;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        if ( !defined( $defs{$name} ) ) {
            push @rets, "Please define $name first";
            next;
        }

        # do not check for existing reading
        if ( $name eq "global"
            || ( defined( $a->[2] ) && $a->[2] =~ /nocheck/i ) )
        {
            foreach ( keys %$h ) {
                my $ret =
                  setKeyValueAttr( $name, $attribute, $a->[1], $_, $h->{$_} );
                push @rets, $ret if ($ret);
            }
            next;
        }

        # check for existing reading
        my $readingspec = '^' . $a->[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{READINGS} }
          )
        {
            foreach ( keys %$h ) {
                my $ret =
                  setKeyValueAttr( $name, $attribute, $reading, $_, $h->{$_} );
                push @rets, $ret if ($ret);
            }
        }
    }
    return join( "\n", @rets );
}

# command: deletereadingdesc
my %deletereadingdeschash = (
    Fn  => "CommandDeleteReadingDesc",
    Hlp => "<devspec> <readingspec> [<key>],delete key for <devspec> <reading>",
);
$cmds{deletereadingdesc} = \%deletereadingdeschash;

sub CommandDeleteReadingDesc($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsDesc";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );

    return "Usage: deletereadingdesc <devspec> <readingspec> [<key>]\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" );

    my @rets;
    my $last;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        if ( !defined( $defs{$name} ) ) {
            push @rets, "Please define $name first";
            next;
        }

        my $readingspec = '^' . $a->[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{READINGS} }
          )
        {
            my $i = $a;
            shift @{$i};
            shift @{$i};
            $i->[0] = 0 if ( !$i->[0] );
            foreach ( @{$i} ) {
                my $ret = deleteKeyValueAttr( $name, $attribute, $reading, $_ );
                push @rets, $ret if ($ret);
            }
        }
    }
    return join( "\n", @rets );
}

# command: setreadingformat
my %setreadingformathash = (
    Fn => "CommandSetReadingFormat",
    Hlp =>
"<devspec> <readingspec> <key>=<value>,set rtype format definition for <devspec> <reading>",
);
$cmds{setreadingformat} = \%setreadingformathash;

sub CommandSetReadingFormat($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsFormat";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );

    return
      "Usage: setreadingformat <devspec> <readingspec> <key>=<value\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" );

    my @rets;
    my $last;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        if ( !defined( $defs{$name} ) ) {
            push @rets, "Please define $name first";
            next;
        }

        foreach ( keys %$h ) {
            my $ret =
              setKeyValueAttr( $name, $attribute, $a->[1], $_, $h->{$_} );
            push @rets, $ret if ($ret);
        }
        next;
    }
    return join( "\n", @rets );
}

# command: deletereadingformat
my %deletereadingformathash = (
    Fn  => "CommandDeleteReadingFormat",
    Hlp => "<devspec> <readingspec> [<key>],delete key for <devspec> <reading>",
);
$cmds{deletereadingformat} = \%deletereadingformathash;

sub CommandDeleteReadingFormat($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsFormat";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );

    return "Usage: deletereadingdesc <devspec> <readingspec> [<key>]\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" );

    my @rets;
    my $last;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        if ( !defined( $defs{$name} ) ) {
            push @rets, "Please define $name first";
            next;
        }

        my $readingspec = '^' . $a->[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{READINGS} }
          )
        {
            my $i = $a;
            shift @{$i};
            shift @{$i};
            $i->[0] = 0 if ( !$i->[0] );
            foreach ( @{$i} ) {
                my $ret = deleteKeyValueAttr( $name, $attribute, $reading, $_ );
                push @rets, $ret if ($ret);
            }
        }
    }
    return join( "\n", @rets );
}

1;
