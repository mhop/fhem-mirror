# $Id$

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use FHEM::UConv;
use Data::Dumper;

sub Unit_Initialize() {
}

my $scales_m = {
    autoscale => {
        '0'     => { format => '%i',   scale => 1000, },
        '0.001' => { format => '%i',   scale => 1000, },
        '0.1'   => { format => '%.1f', scale => 1, },
        '10'    => { format => '%i',   scale => 1, },
        '1.0e3' => { format => '%.1f', scale => 0.001, },
        '2.0e3' => { format => '%i',   scale => 0.001, },
        '1.0e6' => { format => '%.1f', scale => 0.001, },
        '2.0e6' => { format => '%i',   scale => 0.001, },
    },

    '1.0e-12' => {
        'scale_txt_m'      => 'p',
        'scale_txt_long_m' => {
            de => 'Piko',
            en => 'Pico',
            fr => 'Pico',
            nl => 'Pico',
            pl => 'Pico',
        },
    },

    '1.0e-9' => {
        'scale_txt_m'      => 'n',
        'scale_txt_long_m' => {
            de => 'Nano',
            en => 'Nano',
            fr => 'Nano',
            nl => 'Nano',
            pl => 'Nano',
        },
    },

    '1.0e-6' => {
        'scale_txt_m'      => 'μ',
        'scale_txt_long_m' => {
            de => 'Mikro',
            en => 'Micro',
            fr => 'Micro',
            nl => 'Micro',
            pl => 'Micro',
        },
    },

    '1.0e-3' => {
        'scale_txt_m'      => 'm',
        'scale_txt_long_m' => {
            de => 'Milli',
            en => 'Mili',
            fr => 'Mili',
            nl => 'Mili',
            pl => 'Mili',
        },
    },

    '1.0e-2' => {
        'scale_txt_m'      => 'c',
        'scale_txt_long_m' => {
            de => 'Zenti',
            en => 'Centi',
            fr => 'Centi',
            nl => 'Centi',
            pl => 'Centi',
        },
    },

    '1.0e-1' => {
        'scale_txt_m'      => 'd',
        'scale_txt_long_m' => {
            de => 'Dezi',
            en => 'Deci',
            fr => 'Deci',
            nl => 'Deci',
            pl => 'Deci',
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
            en => 'Deca',
            fr => 'Deca',
            nl => 'Deca',
            pl => 'Deca',
        },
    },

    '1.0e2' => {
        'scale_txt_m'      => 'h',
        'scale_txt_long_m' => {
            de => 'Hekto',
            en => 'Hecto',
            fr => 'Hecto',
            nl => 'Hecto',
            pl => 'Hecto',
        },
    },

    '1.0e3' => {
        'scale_txt_m'      => 'k',
        'scale_txt_long_m' => {
            de => 'Kilo',
            en => 'Kilo',
            fr => 'Kilo',
            nl => 'Kilo',
            pl => 'Kilo',
        },
    },

    '1.0e6' => {
        'scale_txt_m'      => 'M',
        'scale_txt_long_m' => {
            de => 'Mega',
            en => 'Mega',
            fr => 'Mega',
            nl => 'Mega',
            pl => 'Mega',
        },
    },
};

my $scales_sq = {
    'scale_txt_sq'      => '2',
    'scale_txt_long_sq' => {
        de => 'Quadrat',
        en => 'Square',
        fr => 'Square',
        nl => 'Square',
        pl => 'Square',
    },
};

my $scales_cu = {
    'scale_txt_cu'      => '3',
    'scale_txt_long_cu' => {
        de => 'Kubik',
        en => 'Cubic',
        fr => 'Cubic',
        nl => 'Cubic',
        pl => 'Cubic',
    },
};

my $scales_t = {
    '1'        => {},
    '60'       => {},
    '3600'     => {},
    '86400'    => {},
    '604800'   => {},
    '2592000'  => {},
    '31536000' => {},
};

my $rtype_base = {

  # based on https://de.wikipedia.org/wiki/Liste_physikalischer_Gr%C3%B6%C3%9Fen

    0 => {
        dimension        => 'L',
        formula_symbol   => 'l',
        rtype_base       => 'm',
        base_description => {
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
        dimension        => 'M',
        formula_symbol   => 'm',
        rtype_base       => 'kg',
        base_description => {
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
        dimension        => 'T',
        formula_symbol   => 't',
        rtype_base       => 's',
        base_description => {
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
        dimension        => 'I',
        formula_symbol   => 'i',
        rtype_base       => 'a',
        base_description => {
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
        dimension        => 'θ',
        formula_symbol   => 'T',
        rtype_base       => 'k',
        base_description => {
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
        dimension        => 'N',
        formula_symbol   => 'n',
        rtype_base       => 'mol',
        base_description => {
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
        dimension        => 'J',
        formula_symbol   => 'Iv',
        rtype_base       => 'cd',
        base_description => {
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
        dimension        => 'M L^2 T^−2',
        formula_symbol   => 'E',
        rtype_base       => 'j',
        base_description => {
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
        dimension        => 'T^−1',
        formula_symbol   => 'f',
        rtype_base       => 'hz',
        base_description => {
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
        dimension        => 'M L^2 T^−3',
        formula_symbol   => 'P',
        rtype_base       => 'w',
        base_description => {
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
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'p',
        rtype_base       => 'pa',
        base_description => {
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
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'pabs',
        rtype_base       => 'pabs',
        base_description => {
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
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'pamb',
        rtype_base       => 'pamb',
        base_description => {
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
        dimension        => 'M L^2 T^−3 I^−1',
        formula_symbol   => 'U',
        rtype_base       => 'v',
        base_description => {
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
        dimension        => '1',
        formula_symbol   => '',
        rtype_base       => 'rad',
        base_description => {
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
        dimension        => 'L T^−1',
        formula_symbol   => 'v',
        rtype_base       => 'kmh',
        base_description => {
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
        dimension        => 'L^−2 J',
        formula_symbol   => 'Ev',
        rtype_base       => 'lx',
        base_description => {
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
        dimension        => 'J',
        formula_symbol   => 'F',
        rtype_base       => 'lm',
        base_description => {
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
        dimension        => 'L^3',
        formula_symbol   => 'V',
        rtype_base       => 'm3',
        base_description => {
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
        dimension        => '1',
        formula_symbol   => 'B',
        rtype_base       => 'b',
        base_description => {
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
        dimension        => 'I T',
        formula_symbol   => 'C',
        rtype_base       => 'coul',
        base_description => {
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
        dimension        => '',
        formula_symbol   => 'F',
        rtype_base       => 'far',
        base_description => {
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
        dimension        => '',
        formula_symbol   => 'F',
        rtype_base       => 'far',
        base_description => {
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
        dimension        => 'L^2',
        formula_symbol   => 'A',
        rtype_base       => 'm2',
        base_description => {
            de => 'Flächeninhalt',
            en => 'surface area',
            fr => 'surface area',
            nl => 'surface area',
            pl => 'surface area',
        },
        format => '%i',
        scope  => { min => 0 },
    },

    24 => {
        base_description => {
            de => 'Währung',
            en => 'currency',
            fr => 'currency',
            nl => 'currency',
            pl => 'currency',
        },
        format => '%.2f',
        scope  => '^[0-9]*(?:\.[0-9]*)?$',
        tmpl   => '%value% %symbol%',
    },

    25 => {
        base_description => {
            de => 'Zahlen',
            en => 'Numbering',
            fr => 'Numbering',
            nl => 'Numbering',
            pl => 'Numbering',
        },
        tmpl => '%value%',
    },

    26 => {
        base_description => {
            de => 'Logische Operatoren',
            en => 'Logical operators',
            fr => 'Logical operators',
            nl => 'Logical operators',
            pl => 'Logical operators',
        },
        tmpl => '%value%',
    },

    900 => {
        base_description => 'FHEM Builtin Readings Type',
        tmpl             => '%value%',
    },

    999 => {
        base_description => 'FHEM User Defined Readings Type',
        tmpl             => '%value%',
    },
};

my $rtypes = {

    # others
    url => {
        ref_base          => 900,
        rtype_description => 'General URL including protocol prefix',
        tmpl              => '<html><a href="%value%">%value%</a></html>',
    },

    url_http => {
        ref_base          => 900,
        rtype_description => 'HTTP/S URL w/ or w/o protocol prefix',
        tmpl              => '<html><a href="%value%">%value%</a></html>',
    },

    trend => {
        ref_base => 900,
        txt      => [ '=', '+', '-' ],
        txt_long => {
            de => [ 'gleichbleibend', 'steigend',  'fallend' ],
            en => [ 'steady',         'rising',    'falling' ],
            fr => [ 'stable',         'croissant', 'décroissant' ],
            nl => [ 'stabiel',        'stijgend',  'dalend' ],
            pl => [ 'stabilne',       'rośnie',   'spada' ],
        },
        scope             => [ '^(=|0)$', '^(+|1)$', '^(-|2)$' ],
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => 'Trend',
    },

    oknok => {
        ref_base => 900,
        txt      => {
            de => [ 'Fehler', 'ok', 'Warnung' ],
            en => [ 'error',  'ok', 'warning' ],
            fr => [ 'error',  'ok', 'warning' ],
            nl => [ 'error',  'ok', 'warning' ],
            pl => [ 'error',  'ok', 'warning' ],
        },
        scope => [
            '^(nok|error|dead|0)$',   '^(ok|alive|1)$',
            '^(warning|warn|low|2)$', '^(.*)$'
        ],
        rtype_description => {
            de =>
'Fehlerstatus; siehe RType roknok, sofern 0<>1 vertauschte Bedeutung haben',
            en => 'error state',
            fr => 'error state',
            nl => 'error state',
            pl => 'error state',
        },
    },

    roknok => {
        ref_base => 900,
        txt      => {
            de => [ 'Fehler', 'ok', 'Warnung' ],
            en => [ 'error',  'ok', 'warning' ],
            fr => [ 'error',  'ok', 'warning' ],
            nl => [ 'error',  'ok', 'warning' ],
            pl => [ 'error',  'ok', 'warning' ],
        },
        scope => [
            '^(nok|error|dead|1)$',   '^(ok|alive|0)$',
            '^(warning|warn|low|2)$', '^(.*)$'
        ],
        rtype_description => {
            de =>
'verdrehter Fehlerstatus, bei dem 0=ok und 1=Fehler bedeutet; Gegenteil von RType oknok',
            en => 'reversed error state',
            fr => 'reversed error state',
            nl => 'reversed error state',
            pl => 'reversed error state',
        },
    },

    onoff => {
        ref_base => 900,
        txt      => {
            de => [ 'aus', 'an', 'nicht verfügbar' ],
            en => [ 'off', 'on', 'absent' ],
            fr => [ 'off', 'on', 'absent' ],
            nl => [ 'off', 'on', 'absent' ],
            pl => [ 'off', 'on', 'absent' ],
        },
        scope =>
          [ '^(off|no|standby|0)$', '^(on|yes|1)$', '^(absent|offline|2)$', ],
        rtype_description => {
            de => 'Schaltstatus',
            en => 'Switch state',
            fr => 'Switch state',
            nl => 'Switch state',
            pl => 'Switch state',
        },
    },

    presence => {
        ref_base => 900,
        txt      => {
            de => [ 'nicht verfügbar', 'verfügbar' ],
            en => [ 'absent',           'present' ],
            fr => [ 'absent',           'present' ],
            nl => [ 'absent',           'present' ],
            pl => [ 'absent',           'present' ],
        },
        scope => [
            '^(unavailable|absent|disappeared|false|no|0)$',
            '^(available|present|appeared|true|yes|1)$'
        ],
        rtype_description => {
            de => 'Verfügbarkeit',
            en => 'availability',
            fr => 'availability',
            nl => 'availability',
            pl => 'availability',
        },
    },

    epoch => {
        ref_base          => 900,
        scope             => { min => 0 },
        rtype_description => {
            de => 'Unix Epoche in s seit 1970-01-01T00:00:00Z',
            en => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            fr => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            nl => 'Unix epoch in s since 1970-01-01T00:00:00Z',
            pl => 'Unix epoch in s since 1970-01-01T00:00:00Z',
        },
    },

    weekday => {
        ref_base => 900,
        symbol   => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa' ],
            en => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            fr => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            nl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            pl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
        },
        txt => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa' ],
            en => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            fr => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            nl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            pl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
        },
        txt_long => {
            de => [
                'Sonntag',    'Montag',  'Dienstag', 'Mittwoch',
                'Donnerstag', 'Freitag', 'Samstag'
            ],
            en => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            fr => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            nl => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            pl => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
        },
        scope => [
            '^(Sun|Su|Sunday|0)$',   '^(Mon|Mo|Monday|1)$',
            '^(Tue|Tu|Tuesday|2)$',  '^(Wed|We|Wednesday|3)$',
            '^(Thu|Th|Thursday|4)$', '^(Fri|Fr|Friday|5)$',
            '^(Sat|Sa|Saturday|6)$'
        ],
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Wochentag nach englisch-amerikanischer Annahme des Wochenstarts am Sonntag',
            en =>
'Day of the week according to english assumption for the week to start on sunday',
            fr =>
'Day of the week according to english assumption for the week to start on sunday',
            nl =>
'Day of the week according to english assumption for the week to start on sunday',
            pl =>
'Day of the week according to english assumption for the week to start on sunday',
        },
    },

    weekday_iso => {
        ref_base => 900,
        symbol   => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa' ],
            en => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            fr => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            nl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            pl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
        },
        txt => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa' ],
            en => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            fr => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            nl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
            pl => [ 'Sun', 'Mon', 'Tus', 'Wed', 'Thu', 'Fri', 'Sat' ],
        },
        txt_long => {
            de => [
                'Sonntag',    'Montag',  'Dienstag', 'Mittwoch',
                'Donnerstag', 'Freitag', 'Samstag'
            ],
            en => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            fr => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            nl => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
            pl => [
                'Sunday',   'Monday', 'Tuesday', 'Wednesday',
                'Thursday', 'Friday', 'Saturday'
            ],
        },
        scope => [
            '^(Sun|Su|Sunday|6)$',   '^(Mon|Mo|Monday|0)$',
            '^(Tue|Tu|Tuesday|1)$',  '^(Wed|We|Wednesday|2)$',
            '^(Thu|Th|Thursday|3)$', '^(Fri|Fr|Friday|4)$',
            '^(Sat|Sa|Saturday|5)$'
        ],
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de => 'Wochentag nach ISO-Standard, Woche beginnend mit Montag',
            en =>
'Day of the week according to ISO standard, week beginning on Mondays',
            fr =>
'Day of the week according to ISO standard, week beginning on Mondays',
            nl =>
'Day of the week according to ISO standard, week beginning on Mondays',
            pl =>
'Day of the week according to ISO standard, week beginning on Mondays',
        },
    },

    weekday_night => {
        ref_base => 900,
        symbol   => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            fr =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            nl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            pl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
        },
        txt => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            fr =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            nl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            pl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
        },
        txt_long => {
            de => [
                'Sonntag Nacht',
                'Montag Nacht',
                'Dienstag Nacht',
                'Mittwoch Nacht',
                'Donnerstag Nacht',
                'Freitag Nacht',
                'Samstag Nacht'
            ],
            en => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            fr => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            nl => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            pl => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
        },
        scope => [
            '^(\s*(Night|Na)?\s*(Sun|Su|Sunday|0)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Mon|Mo|Monday|1)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Tue|Tu|Tuesday|2)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Wed|We|Wednesday|3)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Thu|Th|Thursday|4)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Fri|Fr|Friday|5)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Sat|Sa|Saturday|6)\s*(Night|Na)?\s*)$'
        ],
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Nächtlicher Wochentag nach englisch-amerikanischer Standard des Wochenstarts am Sonntag',
            en =>
'Nightly day of the week according to english standard for the week to start on sunday',
            fr =>
'Nightly day of the week according to english standard for the week to start on sunday',
            nl =>
'Nightly day of the week according to english standard for the week to start on sunday',
            pl =>
'Nightly day of the week according to english standard for the week to start on sunday',
        },
    },

    weekday_night_iso => {
        ref_base => 900,
        symbol   => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            fr =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            nl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            pl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
        },
        txt => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            fr =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            nl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
            pl =>
              [ 'Sun N', 'Mon N', 'Tus N', 'Wed N', 'Thu N', 'FriN ', 'Sat N' ],
        },
        txt_long => {
            de => [
                'Sonntag Nacht',
                'Montag Nacht',
                'Dienstag Nacht',
                'Mittwoch Nacht',
                'Donnerstag Nacht',
                'Freitag Nacht',
                'Samstag Nacht'
            ],
            en => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            fr => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            nl => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
            pl => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
        },
        scope => [
            '^(\s*(Night|Na)?\s*(Sun|Su|Sunday|6)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Mon|Mo|Monday|0)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Tue|Tu|Tuesday|1)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Wed|We|Wednesday|2)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Thu|Th|Thursday|3)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Fri|Fr|Friday|4)\s*(Night|Na)?\s*)$',
            '^(\s*(Night|Na)?\s*(Sat|Sa|Saturday|5)\s*(Night|Na)?\s*)$'
        ],
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Nächtlicher Wochentag nach ISO-Standard, Woche beginnend mit Montag',
            en =>
'Nightly day of the week according to ISO standard, week beginning on Mondays',
            fr =>
'Nightly day of the week according to ISO standard, week beginning on Mondays',
            nl =>
'Nightly day of the week according to ISO standard, week beginning on Mondays',
            pl =>
'Nightly day of the week according to ISO standard, week beginning on Mondays',
        },
    },

    time => {
        ref_base          => 900,
        scope             => '^(([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9]))$',
        rtype_description => {
            de => 'Uhrzeit hh:mm',
            en => 'time hh:mm',
            fr => 'time hh:mm',
            nl => 'time hh:mm',
            pl => 'time hh:mm',
        },
        tmpl_long => {
            de => '%value% Uhr',
            en => '%value%',
            fr => '%value%',
            nl => '%value%',
            pl => '%value%',
        }
    },

    datetime => {
        ref_base => 900,
        scope =>
'^(([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9]))$',
        rtype_description => {
            de => 'Datum+Uhrzeit YYYY-mm-dd hh:mm',
            en => 'date+time YYYY-mm-dd hh:mm',
            fr => 'date+time YYYY-mm-dd hh:mm',
            nl => 'date+time YYYY-mm-dd hh:mm',
            pl => 'date+time YYYY-mm-dd hh:mm',
        },
    },

    timesec => {
        ref_base => 900,
        scope    => '^(([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9]):([0-5]?[0-9]))$',
        rtype_description => {
            de => 'Uhrzeit hh:mm:ss',
            en => 'time hh:mm:ss',
            fr => 'time hh:mm:ss',
            nl => 'time hh:mm:ss',
            pl => 'time hh:mm:ss',
        },
    },

    datetimesec => {
        ref_base => 900,
        scope =>
'^(([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9]):(0?[1-9]|[1-5][0-9]))$',
        rtype_description => {
            de => 'Datum+Uhrzeit YYYY-mm-dd hh:mm:ss',
            en => 'date+time YYYY-mm-dd hh:mm:ss',
            fr => 'date+time YYYY-mm-dd hh:mm:ss',
            nl => 'date+time YYYY-mm-dd hh:mm:ss',
            pl => 'date+time YYYY-mm-dd hh:mm:ss',
        },
    },

    direction => {
        ref_base          => 900,
        formula_symbol    => 'Dir',
        ref               => 'gon',
        scope             => { min => 0, max => 360 },
        rtype_description => {
            de => 'Richtungsangabe',
            en => 'direction',
            fr => 'direction',
            nl => 'direction',
            pl => 'direction',
        },
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
                'Norden', 'Nord-Nordost',  'Nordost',  'Ost-Nordost',
                'Osten',  'Ost-Südost',   'Südost',  'Süd-Südost',
                'Süden', 'Süd-Südwest', 'Südwest', 'West-Südwest',
                'Westen', 'West-Nordwest', 'Nordwest', 'Nord-Nordwest'
            ],
            en => [
                'North',     'North-Northeast',
                'Northeast', 'East-Northeast',
                'East',      'East-Southeast',
                'Southeast', 'South-Southeast',
                'South',     'South-Southwest',
                'Southwest', 'West-Southwest',
                'West',      'West-Northwest',
                'Northwest', 'North-Northwest'
            ],
            nl => [
                'North',     'North-Northeast',
                'Northeast', 'East-Northeast',
                'East',      'East-Southeast',
                'Southeast', 'South-Southeast',
                'South',     'South-Southwest',
                'Southwest', 'West-Southwest',
                'West',      'West-Northwest',
                'Northwest', 'North-Northwest'
            ],
            fr => [
                'North',     'North-Northeast',
                'Northeast', 'East-Northeast',
                'East',      'East-Southeast',
                'Southeast', 'South-Southeast',
                'South',     'South-Southwest',
                'Southwest', 'West-Southwest',
                'West',      'West-Northwest',
                'Northwest', 'North-Northwest'
            ],
            pl => [
                'North',     'North-Northeast',
                'Northeast', 'East-Northeast',
                'East',      'East-Southeast',
                'Southeast', 'South-Southeast',
                'South',     'South-Southwest',
                'Southwest', 'West-Southwest',
                'West',      'West-Northwest',
                'Northwest', 'North-Northwest'
            ],
        },

        #TODO: integrate gradiants into scope regex
        #   if ($azimuth      < 22.5) {
        #      $compassPoint = "north";
        #   } elsif ($azimuth < 45)   {
        #      $compassPoint = "north-northeast";
        #   } elsif ($azimuth < 67.5) {
        #      $compassPoint = "northeast";
        #   } elsif ($azimuth < 90)   {
        #      $compassPoint = "east-northeast";
        #   } elsif ($azimuth < 112.5){
        #      $compassPoint = "east";
        #   } elsif ($azimuth < 135)  {
        #      $compassPoint = "east-southeast";
        #   } elsif ($azimuth < 157.5){
        #     $compassPoint = "southeast";
        #   } elsif ($azimuth < 180)  {
        #     $compassPoint = "south-southeast";
        #   } elsif ($azimuth < 202.5){
        #     $compassPoint = "south";
        #   } elsif ($azimuth < 225)  {
        #     $compassPoint = "south-southwest";
        #   } elsif ($azimuth < 247.5){
        #     $compassPoint = "southwest";
        #   } elsif ($azimuth < 270)  {
        #     $compassPoint = "west-southwest";
        #   } elsif ($azimuth < 292.5){
        #     $compassPoint = "west";
        #   } elsif ($azimuth < 315)  {
        #     $compassPoint = "west-northwest";
        #   } elsif ($azimuth < 337.5){
        #     $compassPoint = "northwest";
        #   } elsif ($azimuth <= 361)  {
        #     $compassPoint = "north-northwest";
        #   }

        scope => [
            '^(N|North|2[0-2]\.?[0-4]\d*|[01]?[0-9]\.?\d*)$',
'^(NNE|North-Northeast|4[0-4]\.?\d*|3[0-9]\.?\d*|2[3-9]|\.?\d*22\.?5\d*)$',
            '^(NE|Northeast|67\.[0-4]\d*|67|6[0-6]\.?\d*|5[0-9]\.?\d*|4[5-9])$',
'^(ENE|East-Northeast|89\.\d*|[78][0-9]\.?\d*|6[8-9]\.?\d*|67\.[5-9]\d*)$',
            '^(E|East|4)$',
            '^(ESE|East-Southeast|5)$',
            '^(SE|Southeast|6)$',
            '^(SSE|South-Southeast|7)$',
            '^(S|South|8)$',
            '^(SSW|South-Southwest|9)$',
            '^(SW|Southwest|10)$',
            '^(WSW|West-Southwest|11)$',
            '^(W|West|12)$',
            '^(WNW|West-Northwest|13)$',
            '^(NW|Northwest|14)$',
            '^(NNW|North-Northwest|15)$'
        ],
        rtype_description => {
            de => 'Himmelsrichtung',
            en => 'point of the compass',
            fr => 'point of the compass',
            nl => 'point of the compass',
            pl => 'point of the compass',
        },
        tmpl_long => '%txt_long%',
    },

    closure => {
        ref_base => 900,
        txt      => {
            de => [ 'geschlossen', 'offen', 'gekippt' ],
            en => [ 'closed',      'open',  'tilted' ],
            fr => [ 'closed',      'open',  'tilted' ],
            nl => [ 'closed',      'open',  'tilted' ],
            pl => [ 'closed',      'open',  'tilted' ],
        },
        scope             => [ '^(closed|0)$', '^(open|1)$', '^(tilted|2)$' ],
        rtype_description => {
            de => 'Status für Fenster und Türen',
            en => 'state for windows and doors',
            fr => 'state for windows and doors',
            nl => 'state for windows and doors',
            pl => 'state for windows and doors',
        },
    },

    condition_weather => {
        ref_base => 900,
        txt      => {
            de => [ 'klar',  'sonnig ', 'bewölkt', 'Regen' ],
            en => [ 'clear', 'sunny',   'cloudy',   'rain' ],
            fr => [ 'clear', 'sunny',   'cloudy',   'rain' ],
            nl => [ 'clear', 'sunny',   'cloudy',   'rain' ],
            pl => [ 'clear', 'sunny',   'cloudy',   'rain' ],
        },
        scope => [ '^(clear|0)$', '^(sunny|1)$', '^(cloudy|2)$', '^(rain|3)$' ],
        rtype_description => {
            de => 'Wetterbedingung',
            en => 'weather condition',
            fr => 'weather condition',
            nl => 'weather condition',
            pl => 'weather condition',
        },
    },

    condition_hum => {
        ref_base => 900,
        txt      => {
            de => [ 'trocken', 'niedrig', 'optimal', 'hoch', 'feucht' ],
            en => [ 'dry',     'low',     'optimal', 'high', 'wet' ],
            fr => [ 'dry',     'low',     'optimal', 'high', 'wet' ],
            nl => [ 'dry',     'low',     'optimal', 'high', 'wet' ],
            pl => [ 'dry',     'low',     'optimal', 'high', 'wet' ],
        },
        scope => [
            '^(dry|0)$', '^(low|1)$', '^(optimal|2)$', '^(high|3)$',
            '^(wet|4)$'
        ],
        rtype_description => {
            de => 'Feuchtigkeitsbedingung',
            en => 'humidity condition',
            fr => 'humidity condition',
            nl => 'humidity condition',
            pl => 'humidity condition',
        },
    },

    condition_uvi => {
        ref_base => 900,
        txt      => {
            de => [ 'niedrig', 'moderat',  'hoch', 'sehr hoch', 'extrem' ],
            en => [ 'low',     'moderate', 'high', 'very high', 'extreme' ],
            fr => [ 'low',     'moderate', 'high', 'very high', 'extreme' ],
            nl => [ 'low',     'moderate', 'high', 'very high', 'extreme' ],
            pl => [ 'low',     'moderate', 'high', 'very high', 'extreme' ],
        },
        scope => [
            '^(low|0)$',  '^(moderate|1)$',
            '^(high|2)$', '^(veryhigh|3)$',
            '^(extreme|4)$'
        ],
        rtype_description => {
            de => 'UV Bedingung',
            en => 'UV condition',
            fr => 'UV condition',
            nl => 'UV condition',
            pl => 'UV condition',
        },
    },

    # logical operators
    bool => {
        ref_base => 26,
        txt      => {
            de => [ 'falsch', 'wahr' ],
            en => [ 'false',  'true' ],
            fr => [ 'false',  'true' ],
            nl => [ 'false',  'true' ],
            pl => [ 'false',  'true' ],
        },
        scope             => [ '^(false|no|0)$', '^(true|yes|1)$' ],
        rtype_description => {
            de => 'Boolesch wahr/falsch',
            en => 'Boolean true/false',
            fr => 'Boolean true/false',
            nl => 'Boolean true/false',
            pl => 'Boolean true/false',
        },
    },

    yesno => {
        ref_base => 26,
        txt      => {
            de => [ 'nein', 'ja' ],
            en => [ 'no',   'yes' ],
            fr => [ 'no',   'yes' ],
            nl => [ 'no',   'yes' ],
            pl => [ 'no',   'yes' ],
        },
        scope             => [ '^(no|n|false|0)$', '^(yes|y|true|1)$' ],
        rtype_description => {
            de => 'Boolesch ja/nein',
            en => 'Boolean ja/nein',
            fr => 'Boolean ja/nein',
            nl => 'Boolean ja/nein',
            pl => 'Boolean ja/nein',
        },
    },

    # numbering
    short => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl zwischen -32768 und 32767',
            en => 'Integer between -32768 and 32767',
            fr => 'Integer between -32768 and 32767',
            nl => 'Integer between -32768 and 32767',
            pl => 'Integer between -32768 and 32767',
        },
        scope => { min => -32768, max => 32767 },
    },

    rshort => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl zwischen -32768 und 32767',
            en => 'rounded integer between -32768 and 32767',
            fr => 'rounded integer between -32768 and 32767',
            nl => 'rounded integer between -32768 and 32767',
            pl => 'rounded integer between -32768 and 32767',
        },
        scope => { min => -32768, max => 32767 },
    },

    long => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl zwischen -2147483648 und 214748364',
            en => 'Integer between -2147483648 and 214748364',
            fr => 'Integer between -2147483648 and 214748364',
            nl => 'Integer between -2147483648 and 214748364',
            pl => 'Integer between -2147483648 and 214748364',
        },
        scope => { min => -2147483648, max => 214748364 },
    },

    rlong => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl zwischen -2147483648 und 214748364',
            en => 'rounded integer between -2147483648 and 214748364',
            fr => 'rounded integer between -2147483648 and 214748364',
            nl => 'rounded integer between -2147483648 and 214748364',
            pl => 'rounded integer between -2147483648 and 214748364',
        },
        scope => { min => -2147483648, max => 214748364 },
    },

    integer => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl',
            en => 'Integer',
            fr => 'Integer',
            nl => 'Integer',
            pl => 'Integer',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    rinteger => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl',
            en => 'rounded integer',
            fr => 'rounded integer',
            nl => 'rounded integer',
            pl => 'rounded integer',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    float => {
        ref_base          => 25,
        format            => '%.2f',
        rtype_description => {
            de => 'Fließkommazahl',
            en => 'floating number',
            fr => 'floating number',
            nl => 'floating number',
            pl => 'floating number',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    pct => {
        ref_base => 25,
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

    # currency
    euro => {
        ref_base => 24,
        format   => '%.2f',
        symbol   => '€',
        suffix   => 'EUR',
        txt      => 'Euro',
        scope    => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    pound_uk => {
        ref_base => 24,
        format   => '%.2f',
        symbol   => '£',
        suffix   => 'GBP',
        txt      => {
            de => 'Pfund',
            en => 'Pound',
            fr => 'Pound',
            nl => 'Pound',
            pl => 'Pound',
        },
        txt_long => {
            de => 'Britische Pfund',
            en => 'British Pound',
            fr => 'British Pound',
            nl => 'British Pound',
            pl => 'British Pound',
        },
        scope     => '^([0-9]*(?:\.[0-9]*)?)$',
        tmpl_long => '%txt_long%',
    },

    dollar_us => {
        ref_base  => 24,
        format    => '%.2f',
        symbol    => '$',
        suffix    => 'USD',
        txt       => 'Dollar',
        txt_long  => 'US Dollar',
        tmpl      => '%symbol%%value%',
        scope     => '^([0-9]*(?:\.[0-9]*)?)$',
        tmpl_long => '%txt_long%',
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
        ref_base => 4,
        symbol   => chr(0xC2) . chr(0xB0) . 'C',
        suffix   => 'C',
        txt      => {
            de => 'Grad Celsius',
            en => 'Degree Celsius',
            fr => 'Degree Celsius',
            nl => 'Degree Celsius',
            pl => 'Degree Celsius',
        },
        txt_pl => {
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
        ref_base => 4,
        symbol   => chr(0xC2) . chr(0xB0) . 'F',
        suffix   => 'F',
        txt      => {
            de => 'Grad Fahrenheit',
            en => 'Degree Fahrenheit',
            fr => 'Degree Fahrenheit',
            nl => 'Degree Fahrenheit',
            pl => 'Degree Fahrenheit',
        },
        txt_pl => {
            de => 'Grad Fahrenheit',
            en => 'Degrees Fahrenheit',
            fr => 'Degrees Fahrenheit',
            nl => 'Degrees Fahrenheit',
            pl => 'Degrees Fahrenheit',
        },
        tmpl  => '%value% %symbol%',
        scope => { min => -459.67 },
    },

    k => {
        ref_base => 4,
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
        tmpl      => '%value% mph',
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
        ref_base => 900,
        suffix   => 'UVI',
        txt      => {
            de => 'UV-Index',
            en => 'UV-Index',
            fr => 'UV-Index',
            nl => 'UV-Index',
            pl => 'UV-Index',
        },
        tmpl      => '%suffix% %value%',
        tmpl_long => '%txt% %value%',
        format    => '%i',
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
        format    => '%.0f',
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
        format    => '%.0f',
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
        format    => '%.0f',
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
        format    => '%.0f',
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
        format    => '%.0f',
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
        format    => '%.0f',
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
    global => {
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
            rtype => 'yesno',
        },
        dewpoint => {
            aliasname => 'dewpoint_c',      # alias only
        },
        dewpoint_c => {
            rtype => 'c',
        },
        elevation => {
            rtype => 'gon',
        },
        feelslike => {
            aliasname => 'feelslike_c',     # alias only
        },
        feelslike_c => {
            rtype => 'c',
        },
        humidity => {
            rtype          => 'pct',
            formula_symbol => 'H',
        },
        humidityabs => {
            aliasname => 'humidityabs_c',    # alias only
        },
        humidityabs_c => {
            rtype          => 'c',
            formula_symbol => 'H',
        },
        humidityabs_f => {
            rtype          => 'f',
            formula_symbol => 'H',
        },
        humidityabs_k => {
            rtype          => 'k',
            formula_symbol => 'H',
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
        indoorhumidity => {
            rtype          => 'pct',
            formula_symbol => 'H',
        },
        indoorhumidityabs => {
            aliasname => 'indoorhumidityabs_c',    # alias only
        },
        indoorhumidityabs_c => {
            rtype => 'c',
        },
        indoortemperature => {
            aliasname => 'indoortemperature_c',    # alias only
        },
        indoortemperature_c => {
            rtype => 'c',
        },
        israining => {
            rtype => 'yesno',
        },
        level => {
            rtype => 'pct',
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
            aliasname => 'pressureabs_psia',
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
        rain_day => {
            aliasname => 'rain_day_mm',    # alias only
        },
        rain_day_mm => {
            rtype => 'mm',
        },
        rain_night => {
            aliasname => 'rain_night_mm',    # alias only
        },
        rain_night_mm => {
            rtype => 'mm',
        },
        rain_week => {
            aliasname => 'rain_week_mm',     # alias only
        },
        rain_week_mm => {
            rtype => 'mm',
        },
        rain_month => {
            aliasname => 'rain_month_mm',    # alias only
        },
        rain_month_mm => {
            rtype => 'mm',
        },
        rain_year => {
            aliasname => 'rain_year_mm',     # alias only
        },
        rain_year_mm => {
            rtype => 'mm',
        },
        snow => {
            aliasname => 'snow_cm',          # alias only
        },
        snow_cm => {
            rtype => 'cm',
        },
        snow_day => {
            aliasname => 'snow_day_cm',      # alias only
        },
        snow_day_cm => {
            rtype => 'cm',
        },
        snow_night => {
            aliasname => 'snow_night_cm',    # alias only
        },
        snow_night_cm => {
            rtype => 'cm',
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
        temperature => {
            aliasname => 'temperature_c',     # alias only
        },
        temperature_c => {
            rtype => 'c',
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
        wind_chill => {
            aliasname => 'wind_chill_c',      # alias only
        },
        wind_chill_c => {
            rtype => 'c',
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
            aliasname => 'wind_compasspoint',    # alias only
        },
        wind_dir => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        winddir => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        winddirection => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        wind_gust => {
            aliasname => 'wind_gust_kmh',        # alias only
        },
        wind_gust_kmh => {
            rtype => 'kmh',
        },
        wind_speed => {
            aliasname => 'wind_speed_kmh',       # alias only
        },
        wind_speed_kmh => {
            rtype => 'kmh',
        },
    }
};

# Find rtype through reading name
sub rname2rtype ($$@) {
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
    if ( !$readingsDB->{global}{ lc($r) } ) {
        $r =~ s/^([A-Z])(.*)/\l$1$2/;
        $r =~ s/([A-Z][a-z0-9]+)[\/\|\-_]?/_$1/g;
    }

    $r = lc($r);

    # known aliasname reading names
    if ( $readingsDB->{global}{$r}{aliasname} ) {
        my $dr = $readingsDB->{global}{$r}{aliasname};
        $return{aliasname} = $dr;
        $return{shortname} = $readingsDB->{global}{$dr}{shortname};
        $rt                = (
              $readingsDB->{global}{$dr}{rtype}
            ? $readingsDB->{global}{$dr}{rtype}
            : "-"
        );
    }

    # known standard reading names
    elsif ( $readingsDB->{global}{$r}{shortname} ) {
        $return{aliasname} = $reading;
        $return{shortname} = $readingsDB->{global}{$r}{shortname};
        $rt                = (
              $readingsDB->{global}{$r}{rtype}
            ? $readingsDB->{global}{$r}{rtype}
            : "-"
        );
    }

    # just guessing the rtype from reading name format
    elsif ( $r =~ /^.*_([A-Za-z0-9]+)$/i ) {
        $return{guess} = 1;
        $rt = $1;
    }

    return $rt if ( $rt && $rtypes->{$rt} );
}

######################################
# package main
#
package main;

# Get value + rtype combined string
sub replaceTemplate ($$$$;$) {
    my ( $device, $reading, $odesc, $lang, $value ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    my $txt;
    my $txt_long;
    my $r = $defs{$device}{READINGS} if ($device);

    return
      if ( !$odesc || ref($odesc) ne "HASH" );

    $value = $odesc->{value}
      if ( !defined($value) && defined( $odesc->{value} ) );

    return $value
      if ( !defined($value) || $value eq "" );

    # clone
    my $desc;
    foreach ( keys %{$odesc} ) {
        $desc->{$_} = $odesc->{$_};
    }

    ##########
    # language support
    #

    # keep only defined language if set
    foreach ( keys %{$desc} ) {
        if (   defined( $desc->{$_} )
            && ref( $desc->{$_} ) eq "HASH"
            && defined( $desc->{$_}{$l} ) )
        {
            my $v;
            $v = $desc->{$_}{$l};
            delete $desc->{$_};
            $desc->{$_} = $v if ( defined($v) );
        }
    }

    # handle textual types after language normalisation
    if ( defined( $desc->{value_num} ) ) {
        if ( ref( $desc->{txt} ) eq "ARRAY"
            && $desc->{txt}[ $desc->{value_num} ] )
        {
            my $v = $desc->{txt}[ $desc->{value_num} ];
            delete $desc->{txt};
            $desc->{txt} = $v;
        }

        if ( ref( $desc->{txt_pl} ) eq "ARRAY"
            && $desc->{txt_pl}[ $desc->{value_num} ] )
        {
            my $v = $desc->{txt_pl}[ $desc->{value_num} ];
            delete $desc->{txt_pl};
            $desc->{txt_pl} = $v;
        }

        if ( ref( $desc->{txt_long} ) eq "ARRAY"
            && $desc->{txt_long}[ $desc->{value_num} ] )
        {
            my $v = $desc->{txt_long}[ $desc->{value_num} ];
            delete $desc->{txt_long};
            $desc->{txt_long} = $v;
        }

        if ( ref( $desc->{txt_long_pl} ) eq "ARRAY"
            && $desc->{txt_long_pl}[ $desc->{value_num} ] )
        {
            my $v = $desc->{txt_long_pl}[ $desc->{value_num} ];
            delete $desc->{txt_long_pl};
            $desc->{txt_long_pl} = $v;
        }
    }

    ##########
    # template support
    #

    # add metric name to suffix
    $desc->{suffix} = $desc->{scale_txt_m} . $desc->{suffix}
      if ( $desc->{suffix}
        && $desc->{scale_txt_m} );
    $desc->{txt} = $desc->{scale_txt_long_m} . lc( $desc->{txt} )
      if ( $desc->{txt}
        && $desc->{scale_txt_long_m} );

    # add square information to suffix and txt
    # if no separate suffix_sq and txt_sq was found
    $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_sq}
      if (!$desc->{suffix_sq}
        && $desc->{scale_txt_sq} );
    $desc->{txt} = $desc->{scale_txt_long_sq} . lc( $desc->{txt} )
      if (!$desc->{txt_sq}
        && $desc->{scale_txt_long_sq} );

    # add cubic information to suffix and txt
    # if no separate suffix_cu and txt_cu was found
    $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_cu}
      if (!$desc->{suffix_cu}
        && $desc->{scale_txt_cu} );
    $desc->{txt} = $desc->{scale_txt_long_cu} . lc( $desc->{txt} )
      if (!$desc->{txt_cu}
        && $desc->{scale_txt_long_cu} );

    # add metric name to suffix_sq
    $desc->{suffix_sq} = $desc->{scale_txt_m_sq} . $desc->{suffix_sq}
      if ( $desc->{suffix_sq}
        && $desc->{scale_txt_m_sq}
        && $desc->{suffix_sq} !~ /$desc->{scale_txt_m_sq}/ );
    $desc->{txt_sq} = $desc->{scale_txt_long_m_sq} . lc( $desc->{txt_sq} )
      if ( $desc->{txt_sq}
        && $desc->{scale_txt_long_m_sq} );

    # # add square information to suffix_sq
    $desc->{suffix_sq} = $desc->{suffix_sq} . $desc->{scale_txt_sq}
      if ( $desc->{suffix_sq}
        && $desc->{scale_txt_sq} );
    $desc->{txt_sq} = $desc->{scale_txt_long_sq} . lc( $desc->{txt_sq} )
      if ( $desc->{txt_sq}
        && $desc->{scale_txt_long_sq} );

    # add metric name to suffix_cu
    $desc->{suffix_cu} = $desc->{scale_txt_m_cu} . $desc->{suffix_cu}
      if ( $desc->{suffix_cu}
        && $desc->{scale_txt_m_cu} );
    $desc->{txt_cu} = $desc->{scale_txt_long_m_cu} . lc( $desc->{txt_cu} )
      if ( $desc->{txt_cu}
        && $desc->{scale_txt_long_m_cu} );

    # add cubic information to suffix_cu
    $desc->{suffix_cu} = $desc->{suffix_cu} . $desc->{scale_txt_cu}
      if ( $desc->{suffix_cu}
        && $desc->{scale_txt_cu} );
    $desc->{txt_cu} = $desc->{scale_txt_long_cu} . lc( $desc->{txt_cu} )
      if ( $desc->{txt_cu}
        && $desc->{scale_txt_long_cu} );

    # short
    $txt = '%value% %suffix%';
    $txt = $desc->{tmpl} if ( $desc->{tmpl} );
    if ( $r && $reading && $r->{$reading} ) {
        foreach my $k ( keys %{ $r->{$reading} } ) {
            $txt =~ s/%$k%/$r->{$reading}{$k}/g;
        }
    }
    foreach my $k ( keys %{$desc} ) {
        $txt =~ s/%$k%/$desc->{$k}/g;
    }

    return ($txt) if ( !wantarray );

    # long plural
    if (   looks_like_number($value)
        && ( $value eq "0" || $value > 1 )
        && $desc->{txt_long_pl} )
    {
        $txt_long = '%value% %txt_long_pl%';
        $txt_long = $desc->{tmpl_long_pl}
          if ( $desc->{tmpl_long_pl} );
    }
    elsif (looks_like_number($value)
        && ( $value eq "0" || $value > 1 )
        && $desc->{txt_pl} )
    {
        $txt_long = '%value% %txt_pl%';
        $txt_long = $desc->{tmpl_long_pl}
          if ( $desc->{tmpl_long_pl} );
    }

    # long singular
    elsif ( $desc->{txt_long} ) {
        $txt_long = '%value% %txt_long%';
        $txt_long = $desc->{tmpl_long}
          if ( $desc->{tmpl_long} );
    }
    elsif ( $desc->{txt} ) {
        $txt_long = '%value% %txt%';
        $txt_long = $desc->{tmpl_long}
          if ( $desc->{tmpl_long} );
    }

    if ($txt_long) {
        if ( $r && $reading && $r->{$reading} ) {
            foreach my $k ( keys %{ $r->{$reading} } ) {
                $txt_long =~ s/%$k%/$r->{$reading}{$k}/g;
            }
        }
        foreach my $k ( keys %{$desc} ) {
            $txt_long =~ s/%$k%/$desc->{$k}/g;
        }
    }

    return ( $txt, $txt_long );
}

# format a number according to desc and optional format.
sub formatValue($$$;$$$$) {
    my ( $device, $reading, $value, $desc, $format, $scope, $lang ) = @_;
    $lang = "en" if ( !$lang );
    my $value_num;

    return $value if ( !defined($value) || ref($value) );

    $desc = readingsDesc( $device, $reading )
      if ( !$desc || !ref($desc) );
    return $value
      if ( !$format && ( !$desc || ref($desc) ne 'HASH' )
        || keys %{$desc} < 1 );

    my $llvl = ( defined( $desc->{verbose} ) ? $desc->{verbose} : 4 );
    $lang = $desc->{lang} if ( $desc->{lang} );

    $value *= $desc->{factor} if ( $desc && $desc->{factor} );
    $format = $desc->{format} if ( !$format && $desc );

    # $format = $scales_m->{autoscale} if ( !$format );

    $scope = $desc->{scope} if ( !$scope && $desc );

    # scope
    #
    if ( ref($scope) eq 'CODE' && &$scope ) {
        ( $value, $value_num ) = $scope->($value);
    }

    elsif ( ref($scope) eq 'HASH' ) {
        my $log;
        if ( !looks_like_number($value) ) {
            $log = "'$value' is not a number"
              if ( !$scope->{empty} && !$scope->{empty_replace} );
            $value = "0" if ( !$scope->{keep} && !$scope->{empty_replace} );
            $value = $scope->{empty_replace}
              if ( defined( $scope->{empty_replace} ) );
        }
        elsif ( $scope->{min} && $scope->{max} ) {
            if ( $value < $scope->{min} ) {
                $value = $scope->{min}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is smaller than $scope->{min}";
            }
            if ( $value > $scope->{max} ) {
                $value = $scope->{max}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is higher than $scope->{max}";
            }
        }
        elsif ( $scope->{lt} && $scope->{gt} ) {
            if ( $value < $scope->{lt} ) {
                $value = $scope->{lt}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is less than $scope->{lt}";
            }
            if ( $value > $scope->{gt} ) {
                $value = $scope->{gt}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is greater than $scope->{gt}";
            }
        }
        elsif ( $scope->{le} && $scope->{ge} ) {
            if ( $value <= $scope->{le} ) {
                $value = $scope->{le}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is less or equal than $scope->{le}";
            }
            if ( $value >= $scope->{ge} ) {
                $value = $scope->{ge}
                  if ( !$scope->{keep} || $scope->{strict} );
                $log = "$value is geater or qual than $scope->{ge}";
            }
        }
        elsif ( $scope->{min} && $value < $scope->{min} ) {
            $value = $scope->{min} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is smaller than $scope->{min}";
        }
        elsif ( $scope->{lt} && $value < $scope->{lt} ) {
            $value = $scope->{lt} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is less than $scope->{lt}";
        }
        elsif ( $scope->{max} && $value > $scope->{max} ) {
            $value = $scope->{max} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is higher than $scope->{max}";
        }
        elsif ( $scope->{gt} && $value > $scope->{gt} ) {
            $value = $scope->{gt} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is greater than $scope->{gt}";
        }
        elsif ( $scope->{ge} && $value >= $scope->{ge} ) {
            $value = $scope->{ge} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is greater or equal than $scope->{ge}";
        }
        elsif ( $scope->{le} && $value <= $scope->{le} ) {
            $value = $scope->{le} if ( !$scope->{keep} || $scope->{strict} );
            $log = "$value is less or equal than $scope->{le}";
        }

        Log3 $device, $llvl,
"formatValue($device:$reading,rtype=$desc->{rtype}) out of scope: $log"
          if ($log);
    }

    elsif ( ref($scope) eq 'ARRAY' ) {
        if (   looks_like_number($value)
            && defined( $scope->[$value] )
            && $value =~ /$scope->[$value]/gmi )
        {
            $value_num = $value;
            if (   ref( $desc->{txt} ) eq "HASH"
                && ref( $desc->{txt}{$lang} ) eq "ARRAY"
                && defined( $desc->{txt}{$lang}[$value] ) )
            {
                $value = $desc->{txt}{$lang}[$value];
            }
            elsif (ref( $desc->{txt} ) eq "HASH"
                && ref( $desc->{txt}{en} ) eq "ARRAY"
                && defined( $desc->{txt}{en}[$value] ) )
            {
                $value = $desc->{txt}{en}[$value];
            }
            elsif ( ref( $desc->{txt} ) eq "ARRAY"
                && defined( $desc->{txt}[$value] ) )
            {
                $value = $desc->{txt}[$value];
            }
            else {
                $value = $1 if ( defined($1) );
                $value = $scope->[$value] if ( !defined($1) );
            }
        }

        else {
            my $i = 0;
            foreach ( @{$scope} ) {
                if ( $value =~ /^$_$/gmi ) {
                    $value_num = $i;
                    if ( ref( $desc->{txt}{$lang} ) eq "ARRAY"
                        && defined( $desc->{txt}{$lang}[$i] ) )
                    {
                        $value = $desc->{txt}{$lang}[$i];
                    }
                    elsif ( ref( $desc->{txt}{en} ) eq "ARRAY"
                        && defined( $desc->{txt}{en}[$i] ) )
                    {
                        $value = $desc->{txt}{en}[$i];
                    }
                    elsif ( ref( $desc->{txt} ) eq "ARRAY"
                        && defined( $desc->{txt}[$i] ) )
                    {
                        $value = $desc->{txt}[$i];
                    }
                    elsif ( !ref( $desc->{txt} ) && defined( $desc->{txt} ) ) {
                        $value = $desc->{txt};
                    }
                    else {
                        $value = $1 if ( defined($1) );
                        if ( !defined($1) ) {
                            Log3 $device, $llvl,
"formatValue($device:$reading:$desc->{rtype}) out of scope: "
                              . "missing txt value or regex output";
                            $value = $scope->[$i];
                        }
                    }
                    last;
                }
                $i++;
            }
        }
    }

    elsif ( defined($scope) && $scope ne "" && $value =~ /$scope/gmi ) {
        $value = $1 if ( defined($1) );
    }

    # format
    #
    if ( $format && !looks_like_number($value) ) {
        Log3 $device, $llvl,
"formatValue($device:$reading,$desc->{rtype}) cannot re-format: $value is not a number"
          if ( !$scope->{empty} && !$scope->{empty_replace} );
    }

    elsif ( ref($format) eq 'CODE' && &$format ) {
        $value = $format->($value);
    }

    elsif ( ref($format) eq 'HASH' ) {
        my $v = abs($value);
        foreach my $l ( sort { $b <=> $a } keys( %{$format} ) ) {
            next
              if ( ref( $format->{$l} ) ne 'HASH'
                || !$format->{$l}{rescale} );
            if ( $v >= $l ) {
                my $rescale = $format->{$l}{rescale};

                $value *= $rescale if ($rescale);
                $value = sprintf( $format->{$l}{format}, $value )
                  if ( $format->{$l}{format} );
                last;
            }
        }
    }

    elsif ( ref($format) eq 'ARRAY' ) {
        Log3 $device, $llvl, "formatValue($device:$reading:$desc->{rtype})"
          . " format not implemented: ARRAY";
    }

    elsif ($format) {
        my $rescale = $desc->{rescale};
        $value *= $rescale if ($rescale);
        $value = sprintf( $format, $value );
    }

    $desc->{value}{$lang} = $value;
    $desc->{value_num} = $value_num if ( defined($value_num) );

    my ( $txt, $txt_long ) = replaceTemplate( $device, $reading, $desc, $lang );

    $desc->{value_txt}{$lang} = $txt;
    $desc->{value_txt_long}{$lang} = $txt_long if ( defined($txt_long) );
    delete $desc->{value_txt_long}{$lang}
      if ( !defined($txt_long) && defined( $desc->{value_txt_long}{$lang} ) );

    return ( $txt, $txt_long, $value, $value_num ) if (wantarray);
    return $value
      if ( defined( $desc->{showUnits} ) && $desc->{showUnits} eq "0" );
    return $txt_long
      if ( $desc->{showLong} && !$desc->{showShort} );
    return $txt;
}

# find desc and optional format for device:reading
sub readingsDesc($;$) {
    my ( $device, $reading ) = @_;
    my $desc = getCombinedKeyValAttr( $device, "readingsDesc", $reading );

    my $rtype;
    $rtype = $desc->{rtype} if ( $desc->{rtype} );

    if ( $rtype && defined( $rtypes->{$rtype} ) ) {

        # copy information from other hashes until 3rd level
        foreach my $k ( keys %{ $rtypes->{$rtype} } ) {
            if ( ref( $rtypes->{$rtype}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $rtypes->{$rtype}{$k} } ) {

                    if ( ref( $rtypes->{$rtype}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $rtypes->{$rtype}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $rtypes->{$rtype}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $rtypes->{$rtype}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$k} if ( $desc->{$k} );
                $desc->{$k} = $rtypes->{$rtype}{$k};
            }
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

        $desc->{ref_base} = 999 if ( !defined( $desc->{ref_base} ) );
        my $ref = $desc->{ref_base};
        foreach my $k ( keys %{ $rtype_base->{$ref} } ) {
            $desc->{$k} = $rtype_base->{$ref}{$k}
              if ( !defined( $desc->{$k} ) );
        }
    }

    return $desc;
}

#format device:reading with optional default value and optional desc and optional format
sub formatReading($$;$$$$$) {
    my ( $device, $reading, $default, $desc, $format, $scope, $lang ) = @_;

    $desc = readingsDesc( $device, $reading ) if ( !$desc );
    my $value = ReadingsVal( $device, $reading, undef );
    $value = $default if ( !defined($value) );

    return formatValue( $device, $reading, $value, $desc, $format, $scope,
        $lang );
}

# return unit symbol for device:reading
sub readingsUnit($$;$$$) {
    my ( $device, $reading, $long, $combined, $desc ) = @_;
    $desc = readingsDesc( $device, $reading ) if ( !$desc );

    return (
        $desc->{suffix} ? $desc->{suffix} : undef,
        $desc->{symbol} ? $desc->{symbol} : undef,
        $desc->{txt}    ? $desc->{txt}    : undef
    ) if (wantarray);

    my ( $txt, $txt_long, $value, $value_num ) =
      formatReading( $device, $reading, "", $desc );

    $txt =~ s/\s*$value\s*//;
    $txt_long =~ s/\s*$value\s*//;

    return "$txt_long ($txt)"
      if ( $combined
        && defined($txt_long)
        && $txt_long ne ""
        && defined($txt)
        && $txt ne "" );
    return $txt_long if ( $long && defined($txt_long) && $txt_long ne "" );
    return $txt if ( defined($txt) && $txt ne "" );
    return '';
}

# return dimension symbol for device:reading
sub readingsShortname($$) {
    my ( $device, $reading ) = @_;

    if ( my $desc = readingsDesc( $device, $reading ) ) {
        return $desc->{formula_symbol} if ( $desc->{formula_symbol} );
        return $desc->{dimension}
          if ( $desc->{dimension} && $desc->{dimension} =~ /^[A-Z]+$/ );
        return $desc->{symbol} if ( $desc->{symbol} );
    }

    return $reading;
}

# format device STATE readings according to stateFormat and optional units
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
sub getCombinedKeyValAttr($;$$) {
    my ( $name, $attribute, $reading ) = @_;
    my $d = $defs{$name} if ( $defs{$name} );
    my $m = $modules{ $d->{TYPE} } if ( $d && $d->{TYPE} );
    my $g = $defs{"global"};

    # join hashes until 3rd level

    my $desc;
    if ( $m && $m->{$attribute} && ref( $m->{$attribute} ) eq "HASH" ) {
        foreach my $k ( keys %{ $m->{$attribute} } ) {
            if ( ref( $m->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $m->{$attribute}{$k} } ) {
                    if ( ref( $m->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $m->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $m->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $m->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $m->{$attribute}{$k};
            }
        }
    }

    if ( $g && $g->{$attribute} && ref( $g->{$attribute} ) eq "HASH" ) {
        foreach my $k ( keys %{ $g->{$attribute} } ) {
            if ( ref( $g->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $g->{$attribute}{$k} } ) {
                    if ( ref( $g->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $g->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $g->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $g->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $g->{$attribute}{$k};
            }
        }
    }

    if ( $d && $d->{$attribute} && ref( $d->{$attribute} ) eq "HASH" ) {
        foreach my $k ( keys %{ $d->{$attribute} } ) {
            if ( ref( $d->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $d->{$attribute}{$k} } ) {
                    if ( ref( $d->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $d->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $d->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $d->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $d->{$attribute}{$k};
            }
        }
    }

    return
      if (
        keys %{$desc} < 1
        || (
            $reading
            && (  !defined( $desc->{$reading} )
                || keys %{ $desc->{$reading} } < 1 )
        )
      );
    return $desc->{$reading} if ($reading);
    return $desc;
}

# save key/value pair to device attribute
sub setKeyValAttr($$$$$) {
    my ( $name, $attribute, $reading, $key, $value ) = @_;
    my $d = $defs{$name} if ( $defs{$name} );
    my $ret;

    return
      if (
        !$d
        || (   defined( $d->{$attribute} )
            && defined( $d->{$attribute}{$reading} )
            && defined( $d->{$attribute}{$reading}{$key} )
            && $d->{$attribute}{$reading}{$key} eq $value )
      );

    # rtype
    if ( $key =~ /^rtype$/i ) {
        $key = lc($key);

        # Show all possible values
        if ( $value && $value eq "?" ) {
            return "CURRENTLY KNOWN READING TYPES\n\n"
              . PrintHash( $rtypes, 0 );
        }

        # find rtype based on reading name
        elsif ( !defined($value) || $value eq "" ) {
            $value = rname2rtype( $name, $reading );
            $ret =
              "Set auto-detected $key for device $name $reading: " . $value
              if ($value);
        }

        my $curr;
        no strict "refs";
        $curr = &$attribute( $name, $reading ) if (&$attribute);
        use strict "refs";

        return
          if (
               !defined($value)
            || $value eq ""
            || (   defined($curr)
                && defined( $curr->{$key} )
                && $curr->{$key} eq $value )
            || (   defined( $d->{$attribute} )
                && defined( $d->{$attribute}{$reading} )
                && defined( $d->{$attribute}{$reading}{$key} )
                && $d->{$attribute}{$reading}{$key} eq $value )
          );

        return
"Invalid value $value for $key: Cannot be assigned to device $name $reading"
          if ( !defined( $rtypes->{$value} ) );

        $ret =
            "Changed value $key='"
          . $d->{$attribute}{$reading}{$key}
          . "' for device $name $reading to: "
          . $value
          if ( defined( defined( $d->{$attribute} ) )
            && defined( $d->{$attribute}{$reading} )
            && defined( $d->{$attribute}{$reading}{$key} )
            && $d->{$attribute}{$reading}{$key} ne $value );
    }

    $d->{$attribute}{$reading}{$key} = $value;

    # write attribute
    $Data::Dumper::Terse    = 1;
    $Data::Dumper::Sortkeys = 1;
    my $txt = Dumper( $d->{$attribute} );
    $Data::Dumper::Terse    = 0;
    $Data::Dumper::Sortkeys = 0;
    $txt =~ s/(=>\s*\{|['"],?)\s*\n\s*/$1 /gsm;
    CommandAttr( undef, "$name $attribute $txt" );
    return $ret;
}

sub deleteKeyValAttr($$$;$) {
    my ( $name, $attribute, $reading, $key ) = @_;
    my $d = $defs{$name} if ( $defs{$name} );
    my $rt;

    return
      if ( !$d
        || !defined( $d->{$attribute} )
        || !defined( $d->{$attribute}{$reading} )
        || ( $key && !defined( $d->{$attribute}{$reading}{$key} ) ) );

    if ($key) {
        $rt = " $key=" . $d->{$attribute}{$reading}{$key};
        delete $d->{$attribute}{$reading}{$key};
    }

    delete $d->{$attribute}{$reading}
      if ( !$key || keys %{ $d->{$attribute}{$reading} } < 1 );

    # delete attribute
    if ( keys %{ $d->{$attribute} } < 1 ) {
        CommandDeleteAttr( undef, "$name $attribute" );
    }

    # write attribute
    else {
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;
        my $txt = Dumper( $d->{$attribute} );
        $Data::Dumper::Terse    = 0;
        $Data::Dumper::Sortkeys = 0;
        $txt =~ s/(=>\s*\{|[\'\"0-9],?)\s*\n\s*/$1 /gsm;
        CommandAttr( undef, "$name $attribute $txt" );
    }

    return "Removed $reading$rt from attribute $name $attribute";
}

################################################################
#
# Wrappers for commonly used core functions in device-specific modules.
#
################################################################

# Generalized function for DbLog rtype support
sub Unit_DbLog_split($$) {
    my ( $event, $name ) = @_;
    my ( $reading, $value, $unit ) = "";

    # exclude any multi-value events
    if ( $event =~ /(.*: +.*: +.*)+/ ) {
        Log3 $name, 5,
          "Unit_DbLog_split $name: Ignoring multi-value event $event";
        return undef;
    }

    # exclude sum/cum and avg events
    elsif ( $event =~ /^.*(min|max|avg|sum|cum|avg\d+m|sum\d+m|cum\d+m): +.*/ )
    {
        Log3 $name, 5, "Unit_DbLog_split $name: Ignoring sum/avg event $event";
        return undef;
    }

    # automatic text conversions through reading type
    elsif ( $event =~ /^(.+): +(\S+) *(.*)/ ) {
        $reading = $1;

        my ( $txt, $txt_long, $val, $val_num ) =
          formatReading( $name, $reading, "" );

        if ( defined($txt) && defined($reading) && defined($val) ) {
            $txt =~ s/\s*$val\s*//;
            $txt_long =~ s/\s*$val\s*//;
            $value = defined($val_num) ? $val_num : $val;
            $unit = "$txt_long ($txt)" if ($txt_long);
            $unit = "$txt"             if ( !$txt_long );
        }
    }

    # general event handling
    if (   !defined($value)
        && $event =~ /^(.+): +(\S+) *[\[\{\(]? *([\w\°\%\^\/\\]*).*/
        && defined($1)
        && defined($2) )
    {
        $reading = $1;
        $value   = ReadingsNum( $name, $1, $2 );
        $unit    = defined($3) ? $3 : "";
    }

    if ( !looks_like_number($value) ) {
        Log3 $name, 5,
"Unit_DbLog_split $name: Ignoring event $event: value $value does not look like a number";
        return undef;
    }

    Log3 $name, 5,
"Unit_DbLog_split $name: Splitting event $event > reading=$reading value=$value unit=$unit";

    return ( $reading, $value, $unit );
}

################################################################
#
# User commands
#
################################################################

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
    my $last;
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
                  setKeyValAttr( $name, $attribute, $a->[1], $_, $h->{$_} );
                push @rets, $ret if ( defined($ret) );
                $last = 1 if ( $h->{$_} eq "?" || $h->{$_} eq "" );
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
                  setKeyValAttr( $name, $attribute, $reading, $_, $h->{$_} );
                push @rets, $ret if ( defined($ret) );
                $last = 1 if ( $h->{$_} eq "?" || $h->{$_} eq "" );
            }
        }

        last if ($last);
    }
    return join( "\n", @rets );
}

# command: deletereadingdesc
my %deletereadingdeschash = (
    Fn => "CommandDeleteReadingDesc",
    Hlp =>
      "<devspec> <readingspec> [<keyspec>],delete key for <devspec> <reading>",
);
$cmds{deletereadingdesc} = \%deletereadingdeschash;

sub CommandDeleteReadingDesc($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsDesc";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> and <keyspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );
    $a->[2] = ".*" if ( !$a->[2] );

    return
      "Usage: deletereadingdesc <devspec> <readingspec> [<keyspec>]\n$namedef"
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
            keys %{ $defs{$name}{$attribute} }
          )
        {
            my $keyspec = '^' . $a->[2] . '$';
            foreach my $key (
                grep { /$keyspec/ }
                keys %{ $defs{$name}{$attribute}{$reading} }
              )
            {
                my $ret = deleteKeyValAttr( $name, $attribute, $reading, $key );
                push @rets, $ret if ( defined($ret) );
            }
        }
    }
    return join( "\n", @rets );
}

1;
