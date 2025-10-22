# === Initialize ===
sub MHI_Heavy_Initialize {
}

# Enter your functions below _this_ line.
###################################################

package MHI_Heavy;
use strict;
use warnings;
use MIME::Base64 qw(decode_base64 encode_base64);
use List::Util qw(first);

# === statische Tabellen ===
our @outdoorTempList = (-50.0, -50.0, -50.0, -50.0, -50.0, -48.9, -46.0, -44.0, -42.0, -41.0, -39.0, -38.0, -37.0, -36.0, -35.0, -34.0, -33.0, -32.0, -31.0, -30.0, -29.0, -28.5, -28.0, -27.0, -26.0, -25.5, -25.0, -24.0, -23.5, -23.0, -22.5, -22.0, -21.5, -21.0, -20.5, -20.0, -19.5, -19.0, -18.5, -18.0, -17.5, -17.0, -16.5, -16.0, -15.5, -15.0, -14.6, -14.3, -14.0, -13.5, -13.0, -12.6, -12.3, -12.0, -11.5, -11.0, -10.6, -10.3, -10.0, -9.6, -9.3, -9.0, -8.6, -8.3, -8.0, -7.6, -7.3, -7.0, -6.6, -6.3, -6.0, -5.6, -5.3, -5.0, -4.6, -4.3, -4.0, -3.7, -3.5, -3.2, -3.0, -2.6, -2.3, -2.0, -1.7, -1.5, -1.2, -1.0, -0.6, -0.3, 0.0, 0.2, 0.5, 0.7, 1.0, 1.3, 1.6, 2.0, 2.2, 2.5, 2.7, 3.0, 3.2, 3.5, 3.7, 4.0, 4.2, 4.5, 4.7, 5.0, 5.2, 5.5, 5.7, 6.0, 6.2, 6.5, 6.7, 7.0, 7.2, 7.5, 7.7, 8.0, 8.2, 8.5, 8.7, 9.0, 9.2, 9.5, 9.7, 10.0, 10.2, 10.5, 10.7, 11.0, 11.2, 11.5, 11.7, 12.0, 12.2, 12.5, 12.7, 13.0, 13.2, 13.5, 13.7, 14.0, 14.2, 14.4, 14.6, 14.8, 15.0, 15.2, 15.5, 15.7, 16.0, 16.2, 16.5, 16.7, 17.0, 17.2, 17.5, 17.7, 18.0, 18.2, 18.5, 18.7, 19.0, 19.2, 19.4, 19.6, 19.8, 20.0, 20.2, 20.5, 20.7, 21.0, 21.2, 21.5, 21.7, 22.0, 22.2, 22.5, 22.7, 23.0, 23.2, 23.5, 23.7, 24.0, 24.2, 24.5, 24.7, 25.0, 25.2, 25.5, 25.7, 26.0, 26.2, 26.5, 26.7, 27.0, 27.2, 27.5, 27.7, 28.0, 28.2, 28.5, 28.7, 29.0, 29.2, 29.5, 29.7, 30.0, 30.2, 30.5, 30.7, 31.0, 31.3, 31.6, 32.0, 32.2, 32.5, 32.7, 33.0, 33.2, 33.5, 33.7, 34.0, 34.3, 34.6, 35.0, 35.2, 35.5, 35.7, 36.0, 36.3, 36.6, 37.0, 37.2, 37.5, 37.7, 38.0, 38.3, 38.6, 39.0, 39.3, 39.6, 40.0, 40.3, 40.6, 41.0, 41.3, 41.6, 42.0, 42.3, 42.6, 43.0);

our @indoorTempList = (-30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -30.0, -29.0, -28.0, -27.0, -26.0, -25.0, -24.0, -23.0, -22.5, -22.0, -21.0, -20.0, -19.5, -19.0, -18.0, -17.5, -17.0, -16.5, -16.0, -15.0, -14.5, -14.0, -13.5, -13.0, -12.5, -12.0, -11.5, -11.0, -10.5, -10.0, -9.5, -9.0, -8.6, -8.3, -8.0, -7.5, -7.0, -6.5, -6.0, -5.6, -5.3, -5.0, -4.5, -4.0, -3.6, -3.3, -3.0, -2.6, -2.3, -2.0, -1.6, -1.3, -1.0, -0.5, 0.0, 0.3, 0.6, 1.0, 1.3, 1.6, 2.0, 2.3, 2.6, 3.0, 3.2, 3.5, 3.7, 4.0, 4.3, 4.6, 5.0, 5.3, 5.6, 6.0, 6.3, 6.6, 7.0, 7.2, 7.5, 7.7, 8.0, 8.3, 8.6, 9.0, 9.2, 9.5, 9.7, 10.0, 10.3, 10.6, 11.0, 11.2, 11.5, 11.7, 12.0, 12.3, 12.6, 13.0, 13.2, 13.5, 13.7, 14.0, 14.2, 14.5, 14.7, 15.0, 15.3, 15.6, 16.0, 16.2, 16.5, 16.7, 17.0, 17.2, 17.5, 17.7, 18.0, 18.2, 18.5, 18.7, 19.0, 19.2, 19.5, 19.7, 20.0, 20.2, 20.5, 20.7, 21.0, 21.2, 21.5, 21.7, 22.0, 22.2, 22.5, 22.7, 23.0, 23.2, 23.5, 23.7, 24.0, 24.2, 24.5, 24.7, 25.0, 25.2, 25.5, 25.7, 26.0, 26.2, 26.5, 26.7, 27.0, 27.2, 27.5, 27.7, 28.0, 28.2, 28.5, 28.7, 29.0, 29.2, 29.5, 29.7, 30.0, 30.2, 30.5, 30.7, 31.0, 31.3, 31.6, 32.0, 32.2, 32.5, 32.7, 33.0, 33.2, 33.5, 33.7, 34.0, 34.2, 34.5, 34.7, 35.0, 35.3, 35.6, 36.0, 36.2, 36.5, 36.7, 37.0, 37.2, 37.5, 37.7, 38.0, 38.3, 38.6, 39.0, 39.2, 39.5, 39.7, 40.0, 40.3, 40.6, 41.0, 41.2, 41.5, 41.7, 42.0, 42.3, 42.6, 43.0, 43.2, 43.5, 43.7, 44.0, 44.3, 44.6, 45.0, 45.3, 45.6, 46.0, 46.2, 46.5, 46.7, 47.0, 47.3, 47.6, 48.0, 48.3, 48.6, 49.0, 49.3, 49.6, 50.0, 50.3, 50.6, 51.0, 51.3, 51.6, 52.0);

# === Mappings für die Ausgabe ===
our %POWER_MODES = (
    0 => 'on',
    1 => 'off');

our %OPERATION_MODES = (
    0 => 'auto',
    1 => 'cool',
    2 => 'heat',
    3 => 'fan',
    4 => 'dry'
);

# Betriebsmodus
our %COOLHOTJUDGE_MODES = (
    0 => 'auto',
    1 => 'cooling',
    2 => 'haeting');

our %AIRFLOW = (
    0 => 'auto',
    1 => 'lowest',
    2 => 'low',
    3 => 'high',
    4 => 'highest'
);

our %HORIZONTAL_POSITIONS = (
    0 => 'auto',
    1 => 'left-left',
    2 => 'left-center',
    3 => 'center-center',
    4 => 'center-right',
    5 => 'right-right',
    6 => 'left-right',
    7 => 'right-left'
);

our %VERTICAL_POSITIONS = (
    0 => 'auto',
    1 => 'highest',
    2 => 'middle',
    3 => 'normal',
    4 => 'lowest'
);


# === Konstruktor ===
sub new {
    my ($class) = @_;
    my $self = {
        airFlow            => -1,
        coolHotJudge        => 0,
        electric            => 0,
        entrust             => 0,
        errorCode           => '',
        indoorTemp          => undef,
        isAutoHeating       => 0,
        isSelfCleanOperation=> 0,
        isSelfCleanReset    => 0,
        isVacantProperty    => 0,
        modelNo             => 0,
        operation           => 0,
        operationMode       => undef,
        outdoorTemp         => undef,
        presetTemp          => undef,
        windDirectionLR     => -1,
        windDirectionUD     => -1
    };
    bless $self, $class;
    return $self;
}

# === Hilfsfunktionen ===
sub zeroPad {
    my ($num, $places) = @_;
    return sprintf("%0${places}d", $num);
}

sub wosoFindMatch {
    my ($value, $posVals, $p) = @_;
    $p //= 0;
    for (my $i = 0; $i < @$posVals; $i++) {
        return $i + $p if $posVals->[$i] == $value;
    }
    return -1;
}

# === CRC16-CCITT ===
sub crc16ccitt {
    my ($data_ref) = @_;
    my $crc = 0xFFFF;
    foreach my $b (@$data_ref) {
        $b += 256 if $b < 0;
        for my $bit (0 .. 7) {
            my $z  = (($crc >> 15) & 1) == 1;
            my $z2 = (($b >> (7 - $bit)) & 1) == 1;
            $crc <<= 1;
            $crc &= 0xFFFF;
            $crc ^= 0x1021 if ($z != $z2);
        }
    }
    return $crc & 0xFFFF;
}

# === Base64 → Objekt ===
sub fromBase64 {
    my ($class, $base64) = @_;
    $base64 =~ s/\n//g;
    my $binary = decode_base64($base64);
    my @bytes = map {
        my $h = ord($_);
        ($h > 127) ? -1 * (256 - $h) : $h;
    } split //, $binary;

    my $self = $class->new();

    my $r3 = 18;
    my $dataStart  = $bytes[$r3] * 4 + 21;
    my $dataLength = scalar(@bytes) - 2;
    my @data = @bytes[$dataStart .. $dataLength - 1];
    my $code = $data[6] & 127;

    $self->{operation}      = $POWER_MODES{((3 & $data[2]) == 1) ? 1 : 0};
    $self->{presetTemp}     = $data[4] / 2.0;
    $self->{operationMode}  = $OPERATION_MODES{wosoFindMatch((60 & $data[2]), [8,16,12,4], 1)};
    $self->{airFlow}        = $AIRFLOW{wosoFindMatch((15 & $data[3]), [7,0,1,2,6])};
    $self->{windDirectionUD}= $VERTICAL_POSITIONS{((192 & $data[2]) == 64) ? 0 :
                              wosoFindMatch((240 & $data[3]), [0,16,32,48], 1)};
    $self->{windDirectionLR}= $HORIZONTAL_POSITIONS{((3 & $data[12]) == 1) ? 0 :
                              wosoFindMatch((31 & $data[11]), [0,1,2,3,4,5,6], 1)};
    $self->{entrust}        = ((12 & $data[12]) == 4) ? 1 : 0;
    $self->{coolHotJudge}   = $COOLHOTJUDGE_MODES{((8 & $data[8]) <= 0) ? 1 : 0};
    $self->{modelNo}        = wosoFindMatch((127 & $data[0]), [0,1,2]);
    $self->{isVacantProperty}= (1 & $data[10]);

    if ($code == 0) {
        $self->{errorCode} = "00";
    } elsif (($data[6] & -128) <= 0) {
        $self->{errorCode} = "M" . zeroPad($code, 2);
    } else {
        $self->{errorCode} = "E" . $code;
    }

    # … hier folgt noch die Temperatur- und Electric-Verarbeitung aus JS …
my $c = 0;
my @vals;

# Kopiere Werte aus bytes in vals (wie im JS-Code)
for (my $i = $dataStart + 19; $i < scalar(@bytes) - 2; $i++) {
    $vals[$c] = $bytes[$i];
#    print "Value $c : $vals[$c]\n";
    $c++;
}

for (my $i = 0; $i < scalar(@vals); $i += 4) {

    # Outdoor-Temperatur
    if ($vals[$i] == -128 && $vals[$i + 1] == 16) {
        my $index = $vals[$i + 2] & 0xFF;
#        print "Index outdoorTemp : $index\n"; 
       $self->{outdoorTemp} = $outdoorTempList[$index];
    }

    # Indoor-Temperatur
    if ($vals[$i] == -128 && $vals[$i + 1] == 32) {
        my $index = $vals[$i + 2] & 0xFF;
#        print "Index indoorTemp : $index\n"; 
        $self->{indoorTemp} = $indoorTempList[$index];
    }

    # Elektrizität (Watt oder ähnlicher Messwert)
    if ($vals[$i] == -108 && $vals[$i + 1] == 16) {
        my @bytes = ($vals[$i + 2], $vals[$i + 3], 0, 0);
        # Bytes in eine 32-Bit-Zahl umwandeln (Little Endian)
        my $uint = unpack('L', pack('C4', @bytes));
        $self->{electric} = $uint * 0.25;
    }
}

    return $self;
}

# Beende das Modul und kehre zum globalen Paket zurück
1; # Dies ist notwendig, damit das Modul korrekt geladen wird
