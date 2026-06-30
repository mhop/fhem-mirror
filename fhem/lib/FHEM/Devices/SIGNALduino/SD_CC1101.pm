# $Id$
# The file is part of the SIGNALduino project.
# Client functions for SIGNALduino device.

package FHEM::Devices::SIGNALduino::SD_CC1101;

use strict;
use warnings;
use Carp;
use Exporter qw(import);

use constant {
  SDUINO_VERSION => '4.0.0', 
};

our @EXPORT_OK = qw(
  SetPatable
  SetRegisters
  SetRegistersUser
  SetDataRate
  CalcDataRate
  SetDeviatn
  SetFreq
  setrAmpl
  GetRegister
  CalcbWidthReg
  SetSens
  %cc1101_register
  %cc1101_status_register
  %patable
  @ampllist
  %cc1101_version
);
# Not used outside



our %EXPORT_TAGS = (
    'all' => \@EXPORT_OK,
);
# Predeclare used symbols from main package (to be imported or accessed via full path)
# Assuming main::SIGNALduino_AddSendQueue and main::SIGNALduino_WriteInit exist and are exported or accessible.

our %cc1101_status_register = ( # for get ccreg 30-3D status registers
  '30' => 'PARTNUM       ',
  '31' => 'VERSION       ',
  '32' => 'FREQEST       ',
  '33' => 'LQI           ',
  '34' => 'RSSI          ',
  '35' => 'MARCSTATE     ',
  '36' => 'WORTIME1      ',
  '37' => 'WORTIME0      ',
  '38' => 'PKTSTATUS     ',
  '39' => 'VCO_VC_DAC    ',
  '3A' => 'TXBYTES       ',
  '3B' => 'RXBYTES       ',
  '3C' => 'RCCTRL1_STATUS',
  '3D' => 'RCCTRL0_STATUS',
);

our %cc1101_version = ( # Status register 0x31 (0xF1): VERSION – Chip ID
  '03' => 'CC1100',
  '04' => 'CC1101',
  '14' => 'CC1101',
  '05' => 'CC1100E',
  '07' => 'CC110L',
  '17' => 'CC110L',
  '08' => 'CC113L',
  '18' => 'CC113L',
  '15' => 'CC115L',
);

our %cc1101_register = (          # for get ccreg 99 and set cc1101_reg
  '00' => 'IOCFG2   - 0x0D',      # ! the values with spaces for output get ccreg 99 !
  '01' => 'IOCFG1   - 0x2E',
  '02' => 'IOCFG0   - 0x2D',
  '03' => 'FIFOTHR  - 0x47',
  '04' => 'SYNC1    - 0xD3',
  '05' => 'SYNC0    - 0x91',
  '06' => 'PKTLEN   - 0x3D',
  '07' => 'PKTCTRL1 - 0x04',
  '08' => 'PKTCTRL0 - 0x32',
  '09' => 'ADDR     - 0x00',
  '0A' => 'CHANNR   - 0x00',
  '0B' => 'FSCTRL1  - 0x06',
  '0C' => 'FSCTRL0  - 0x00',
  '0D' => 'FREQ2    - 0x10',
  '0E' => 'FREQ1    - 0xB0',
  '0F' => 'FREQ0    - 0x71',
  '10' => 'MDMCFG4  - 0x57',
  '11' => 'MDMCFG3  - 0xC4',
  '12' => 'MDMCFG2  - 0x30',
  '13' => 'MDMCFG1  - 0x23',
  '14' => 'MDMCFG0  - 0xB9',
  '15' => 'DEVIATN  - 0x00',
  '16' => 'MCSM2    - 0x07',
  '17' => 'MCSM1    - 0x00',
  '18' => 'MCSM0    - 0x18',
  '19' => 'FOCCFG   - 0x14',
  '1A' => 'BSCFG    - 0x6C',
  '1B' => 'AGCCTRL2 - 0x07',
  '1C' => 'AGCCTRL1 - 0x00',
  '1D' => 'AGCCTRL0 - 0x91',
  '1E' => 'WOREVT1  - 0x87',
  '1F' => 'WOREVT0  - 0x6B',
  '20' => 'WORCTRL  - 0xF8',
  '21' => 'FREND1   - 0xB6',
  '22' => 'FREND0   - 0x11',
  '23' => 'FSCAL3   - 0xE9',
  '24' => 'FSCAL2   - 0x2A',
  '25' => 'FSCAL1   - 0x00',
  '26' => 'FSCAL0   - 0x1F',
  '27' => 'RCCTRL1  - 0x41',
  '28' => 'RCCTRL0  - 0x00',
  '29' => 'FSTEST   - N/A ',
  '2A' => 'PTEST    - N/A ',
  '2B' => 'AGCTEST  - N/A ',
  '2C' => 'TEST2    - N/A ',
  '2D' => 'TEST1    - N/A ',
  '2E' => 'TEST0    - N/A ',
);


our %patable = (
  '433' =>
  {
    '-30_dBm'  => '12',
    '-20_dBm'  => '0E',
    '-15_dBm'  => '1D',
    '-10_dBm'  => '34',
    '-5_dBm'   => '68',
    '0_dBm'    => '60',
    '5_dBm'    => '84',
    '7_dBm'    => 'C8',
    '10_dBm'   => 'C0',
  },
  '868' =>
  {
    '-30_dBm'  => '03',
    '-20_dBm'  => '0F',
    '-15_dBm'  => '1E',
    '-10_dBm'  => '27',
    '-5_dBm'   => '67',
    '0_dBm'    => '50',
    '5_dBm'    => '81',
    '7_dBm'    => 'CB',
    '10_dBm'   => 'C2',
  },
);

our @ampllist = (24, 27, 30, 33, 36, 38, 40, 42);    # rAmpl(dB)

############################# package cc1101
#### for set function to change the patable for 433 or 868 Mhz supported
#### 433.05–434.79 MHz, 863–870 MHz
sub SetPatable {
  my ($hash,@a) = @_;
  my $paFreq = main::AttrVal($hash->{NAME},'cc1101_frequency','433');
  $paFreq = 433 if ($paFreq >= 433 && $paFreq <= 435);
  $paFreq = 868 if ($paFreq >= 863 && $paFreq <= 870);
  if ( exists($patable{$paFreq}) && exists $patable{$paFreq}{$a[1]} )
  {
    my $pa = "x" . $patable{$paFreq}{$a[1]};
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetPatable, Setting patable $paFreq $a[1] $pa");

    main::SIGNALduino_AddSendQueue($hash,$pa);
    main::SIGNALduino_WriteInit($hash);
    return ;
  } else {
    return "$hash->{NAME}: Frequency $paFreq MHz not supported (supported frequency ranges: 433.05-434.79 MHz, 863.00-870.00 MHz).";
  }
}

############################# package cc1101
sub SetRegisters  {
  my ($hash, @a) = @_;

  ## check for four hex digits
  my @nonHex = grep (!/^[0-9A-Fa-f]{4}$/,@a[1..$#a]) ;
  return "$hash->{NAME} ERROR: wrong parameter value @nonHex, only hexadecimal ​​four digits allowed" if (@nonHex);

  ## check allowed register position
  my (@wrongRegisters) = grep { !exists($cc1101_register{uc(substr($_,0,2))}) } @a[1..$#a] ;
  return "$hash->{NAME} ERROR: unknown register position ".substr($wrongRegisters[0],0,2) if (@wrongRegisters);

  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: SetRegisters, cc1101_reg @a[1..$#a]");
  my @tmpSendQueue=();
  foreach my $argcmd (@a[1..$#a]) {
    $argcmd = sprintf("W%02X%s",hex(substr($argcmd,0,2)) + 2,substr($argcmd,2,2));
    main::SIGNALduino_AddSendQueue($hash,$argcmd);
  }
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub SetRegistersUser  {
  my ($hash) = @_;

  my $cc1101User = main::AttrVal($hash->{NAME}, 'cc1101_reg_user', undef);

  ## look, user defined self default register values via attribute
  if (defined $cc1101User) {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetRegistersUser, write CC1101 defaults from attribute");
    $cc1101User = '0815,'.$cc1101User; # for SetRegisters, value for register starts on pos 1 in array
    SetRegisters($hash, split(',', $cc1101User) );
  }
  return ;
}

############################# package cc1101
sub SetDataRate  {
  my ($hash, @a) = @_;
  my $arg = $a[1];

  if (exists($hash->{ucCmd}->{cmd}) && $hash->{ucCmd}->{cmd} eq 'set_dataRate' && $a[0] =~ /^C10\s=\s([A-Fa-f0-9]{2})$/) {
    my ($ob1,$ob2) = CalcDataRate($hash,$1,$hash->{ucCmd}->{arg});
    main::SIGNALduino_AddSendQueue($hash,"W12$ob1");
    main::SIGNALduino_AddSendQueue($hash,"W13$ob2");
    main::SIGNALduino_WriteInit($hash);
    return ("Setting MDMCFG4..MDMCFG3 to $ob1 $ob2 = $hash->{ucCmd}->{arg} kHz" ,undef);
  } else {
    if ($arg !~ m/\d/) { return qq[$hash->{NAME}: ERROR, unsupported DataRate value]; }
    if ($arg > 1621.83) { $arg = 1621.83; }     # max 1621.83      kBaud DataRate
    if ($arg < 0.0247955) { $arg = 0.0247955; } # min    0.0247955 kBaud DataRate

    GetRegister($hash,10);                      # Get Register 10

    $hash->{ucCmd}->{cmd}         = 'set_dataRate';
    $hash->{ucCmd}->{arg}         = $arg;                            # ZielDataRate
    $hash->{ucCmd}->{responseSub} = \&SetDataRate;                  # Callback auf sich selbst setzen
    $hash->{ucCmd}->{asyncOut}    = $hash->{CL} if (defined($hash->{CL}));
    $hash->{ucCmd}->{timenow}     = time();
  }
  return ;
}

############################# package cc1101
sub CalcDataRate {
  # register 0x10 3:0 & register 0x11 7:0
  my ($hash, $ob10, $dr) = @_;
  $ob10 = hex($ob10) & 0xf0;

  my $DRATE_E = ($dr*1000) * (2**20) / 26000000;
  $DRATE_E = log($DRATE_E) / log(2);
  $DRATE_E = int($DRATE_E);

  my $DRATE_M = (($dr*1000) * (2**28) / (26000000 * (2**$DRATE_E))) - 256;
  my $DRATE_Mr = FHEM::Core::Utils::Math::round($DRATE_M,0);
  $DRATE_M = int($DRATE_M);

  my $datarate0 = ( ((256+$DRATE_M)*(2**($DRATE_E & 15 )))*26000000/(2**28) / 1000);
  my $DRATE_M1 = $DRATE_M + 1;
  my $DRATE_E1 = $DRATE_E;

  if ($DRATE_M1 == 256) {
    $DRATE_M1 = 0;
    $DRATE_E1++;
  }

  my $datarate1 = ( ((256+$DRATE_M1)*(2**($DRATE_E1 & 15 )))*26000000/(2**28) / 1000);

  if ($DRATE_Mr != $DRATE_M) {
    $DRATE_M = $DRATE_M1;
    $DRATE_E = $DRATE_E1;
  }

  my $ob11 = sprintf("%02x",$DRATE_M);
  $ob10 = sprintf("%02x", $ob10+$DRATE_E);

  $hash->{logMethod}->($hash->{NAME}, 5, qq[$hash->{NAME}: CalcDataRate, DataRate $hash->{ucCmd}->{arg} kHz step from $datarate0 to $datarate1 kHz]);
  $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: CalcDataRate, DataRate MDMCFG4..MDMCFG3 to $ob10 $ob11 = $hash->{ucCmd}->{arg} kHz]);

  return ($ob10,$ob11);
}

############################# package cc1101
sub SetDeviatn {
  my ($hash, @a) = @_;
  my $arg = $a[1];

  if ($arg !~ m/\d/) { return qq[$hash->{NAME}: ERROR, unsupported Deviation value]; }
  if ($arg > 380.859375) { $arg = 380.859375; }   # max 380.859375 kHz Deviation
  if ($arg < 1.586914) { $arg = 1.586914; }       # min   1.586914 kHz Deviation

  my $deviatn_val;
  my $bits;
  my $devlast = 0;
  my $bitlast = 0;

  CalcDeviatn:
  for (my $DEVIATION_E=0; $DEVIATION_E<8; $DEVIATION_E++) {
    for (my $DEVIATION_M=0; $DEVIATION_M<8; $DEVIATION_M++) {
      $deviatn_val = (8+$DEVIATION_M)*(2**$DEVIATION_E) *26000/(2**17);
      $bits = $DEVIATION_M + ($DEVIATION_E << 4);
      if ($arg > $deviatn_val) {
        $devlast = $deviatn_val;
        $bitlast = $bits;
      } else {
        if (($deviatn_val - $arg) < ($arg - $devlast)) {
          $devlast = $deviatn_val;
          $bitlast = $bits;
        }
        last CalcDeviatn;
      }
    }
  }

  my $reg15 = sprintf("%02x",$bitlast);
  my $deviatn_str =  sprintf("% 5.2f",$devlast);
  $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: SetDeviatn, Setting DEVIATN (15) to $reg15 = $deviatn_str kHz]);

  main::SIGNALduino_AddSendQueue($hash,"W17$reg15");
  main::SIGNALduino_WriteInit($hash);

  return;
}

############################# package cc1101
sub SetFreq  {
  my ($hash, @a) = @_;

  my $arg = $a[1];
  if (!defined($arg)) {
    $arg = main::AttrVal($hash->{NAME},'cc1101_frequency', 433.92);
  }
  my $f = $arg/26*65536;
  my $f2 = sprintf("%02x", $f / 65536);
  my $f1 = sprintf("%02x", int($f % 65536) / 256);
  my $f0 = sprintf("%02x", $f % 256);
  $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetFreq, Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz");
  main::SIGNALduino_AddSendQueue($hash,"W0F$f2");
  main::SIGNALduino_AddSendQueue($hash,"W10$f1");
  main::SIGNALduino_AddSendQueue($hash,"W11$f0");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub setrAmpl  {
  my ($hash, @a) = @_;
  return "$hash->{NAME}: A numerical value between 24 and 42 is expected." if($a[1] !~ m/^\d+$/ || $a[1] < 24 ||$a[1] > 42);
  my $v;
  for($v = 0; $v < @ampllist; $v++) {
    last if($ampllist[$v] > $a[1]);
  }
  $v = sprintf("%02d", $v-1);
  my $w = $ampllist[$v];
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: setrAmpl, Setting AGCCTRL2 (1B) to $v / $w dB");
  main::SIGNALduino_AddSendQueue($hash,"W1D$v");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub GetRegister {
  my ($hash, $reg) = @_;
  main::SIGNALduino_AddSendQueue($hash,'C'.$reg);
  return ;
}

############################# package cc1101
sub CalcbWidthReg {
  my ($hash, $reg10, $bWith) = @_;
  # Beispiel Rückmeldung, mit Ergebnis von Register 10: C10 = 57
  my $ob = hex($reg10) & 0x0f;
  my ($bits, $bw) = (0,0);
  OUTERLOOP:
  for (my $e = 0; $e < 4; $e++) {
    for (my $m = 0; $m < 4; $m++) {
      $bits = ($e<<6)+($m<<4);
      $bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
      last OUTERLOOP if($bWith >= $bw);
    }
  }
  $ob = sprintf("%02x", $ob+$bits);

  return ($ob,$bw);
}

############################# package cc1101
sub SetSens {
  my ($hash, @a) = @_;

  # Todo: Abfrage in Grep auf Array ändern
  return 'a numerical value between 4 and 16 is expected' if($a[1] !~ m/^\d+$/ || $a[1] < 4 || $a[1] > 16);
  my $w = int($a[1]/4)*4;
  my $v = sprintf("9%d",$a[1]/4-1);
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetSens, Setting AGCCTRL0 (1D) to $v / $w dB");
  main::SIGNALduino_AddSendQueue($hash,"W1F$v");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

1;