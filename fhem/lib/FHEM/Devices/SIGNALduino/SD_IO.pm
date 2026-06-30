# $Id$
# The file is part of the SIGNALduino project.
# Client functions for SIGNALduino device.

package FHEM::Devices::SIGNALduino::SD_IO;

use strict;
use warnings;
use Carp;
use Exporter qw(import);
use Time::HiRes qw(gettimeofday);
#use FHEM::Core::Timer::Helper;
#use DevIo;

our @EXPORT_OK = qw(
  SIGNALduino_Connect
  SIGNALduino_Shutdown
  SIGNALduino_ResetDevice
  SIGNALduino_CloseDevice
  SIGNALduino_DoInit
  SIGNALduino_SimpleWrite_XQ
  SIGNALduino_StartInit
  SIGNALduino_CheckVersionResp
  SIGNALduino_KeepAlive
  SIGNALduino_SimpleWrite
  SIGNALduino_WriteInit
  SDUINO_KEEPALIVE_TIMEOUT
  SDUINO_KEEPALIVE_MAXRETRY
);
our %EXPORT_TAGS = (
    'all' => \@EXPORT_OK,
);

use constant {
  SDUINO_INIT_WAIT_XQ             => 1.5,     # wait disable device
  SDUINO_INIT_WAIT                => 2,
  SDUINO_INIT_MAXRETRY            => 3,
  SDUINO_CMD_TIMEOUT              => 10,
  SDUINO_KEEPALIVE_TIMEOUT        => 60,
  SDUINO_KEEPALIVE_MAXRETRY       => 3,
};

# Assuming main::Log3, main::readingsSingleUpdate, main::SIGNALduino_SimpleWrite, etc. are available
# or need to be imported/fully qualified.

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_Connect {
  my ($hash, $err) = @_;
  # damit wird die err-msg nur einmal ausgegeben
  if (!defined($hash->{disConnFlag}) && $err) {
    $hash->{logMethod}->($hash, 3, "$hash->{NAME}: Connect, ${err}");
    $hash->{disConnFlag} = 1;
  }
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_Shutdown {
  my ($hash) = @_;
  #DevIo_SimpleWrite($hash, "XQ\n",2);
  SIGNALduino_SimpleWrite($hash, 'XQ');   # Switch reception off, it may hang up the SIGNALduino
  return ;
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_ResetDevice {
  my $hash = shift;
  my $name = $hash->{NAME};

  if (!defined($hash->{helper}{resetInProgress})) {
    my $hardware = main::AttrVal($name,'hardware','');
    $hash->{logMethod}->($name, 3, "$name: ResetDevice, $hardware");

    if (main::IsDummy($name)) { # for dummy device
      $hash->{DevState} = 'initialized';
      main::readingsSingleUpdate($hash, 'state', 'opened', 1);
      return ;
    }

    main::DevIo_CloseDev($hash);
    if ($hardware eq 'radinoCC1101' && $^O eq 'linux') {
      # The reset is triggered when the Micro's virtual (CDC) serial / COM port is opened at 1200 baud and then closed.
      # When this happens, the processor will reset, breaking the USB connection to the computer (meaning that the virtual serial / COM port will disappear).
      # After the processor resets, the bootloader starts, remaining active for about 8 seconds.
      # The bootloader can also be initiated by pressing the reset button on the Micro.
      # Note that when the board first powers up, it will jump straight to the user sketch, if present, rather than initiating the bootloader.
      my ($dev, $baudrate) = split("@", $hash->{DeviceName});
      $hash->{logMethod}->($name, 3, "$name: ResetDevice, forcing special reset for $hardware on $dev");
      # Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen
      system("stty -F $dev ospeed 1200 ispeed 1200");
      $hash->{helper}{resetInProgress}=1;
      FHEM::Core::Timer::Helper::addTimer($name,gettimeofday()+10,\&SIGNALduino_ResetDevice,$hash);
      
      $hash->{logMethod}->($name, 3, "$name: ResetDevice, reopen delayed for 10 second");
      return ;
    }
  } else {
    delete($hash->{helper}{resetInProgress});
  }
  main::DevIo_OpenDev($hash, 0, \&SIGNALduino_DoInit, \&SIGNALduino_Connect);
  return ;
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_CloseDevice {
  my ($hash) = @_;

  $hash->{logMethod}->($hash->{NAME}, 2, "$hash->{NAME}: CloseDevice, closed");
  FHEM::Core::Timer::Helper::removeTimer($hash->{NAME});
  main::DevIo_CloseDev($hash);
  main::readingsSingleUpdate($hash, 'state', 'closed', 1);

  return ;
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_DoInit {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my ($ver, $try) = ('', 0);
  #Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing
  $hash->{logMethod}->($hash, 1, "$name: DoInit, called");
  delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});

  # FHEM::Core::Timer::Helper::removeTimer($name,\&main::SIGNALduino_HandleWriteQueue,"HandleWriteQueue:$name"); # Todo: Cross-Dependency
  FHEM::Core::Timer::Helper::removeTimer($name,\&main::SIGNALduino_HandleWriteQueue,"HandleWriteQueue:$name");

  @{$hash->{QUEUE}} = ();
  $hash->{sendworking} = 0;

  if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
  {
    $hash->{logMethod}->($hash, 1, "$name: DoInit, ".$hash->{DEF});
    $hash->{initretry} = 0;
    FHEM::Core::Timer::Helper::removeTimer($name,undef,$hash); # What timer should be removed here is not clear

    #SIGNALduino_SimpleWrite($hash, 'XQ'); # Disable receiver
    
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT_XQ, \&SIGNALduino_SimpleWrite_XQ, $hash, 0);
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT, \&SIGNALduino_StartInit, $hash, 0);
  }
  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return;
}

############################# package FHEM::Device::SIGNALduino::SD_IO
# Disable receiver
sub SIGNALduino_SimpleWrite_XQ {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{logMethod}->($hash, 3, "$name: SimpleWrite_XQ, disable receiver (XQ)");
  SIGNALduino_SimpleWrite($hash, 'XQ');
}

############################# package FHEM::Device::SIGNALduino::SD_IO, test exists
sub SIGNALduino_StartInit {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{version} = undef;

  $hash->{logMethod}->($name,3 , "$name: StartInit, get version, retry = " . $hash->{initretry});
  if ($hash->{initretry} >= SDUINO_INIT_MAXRETRY) {
    $hash->{DevState} = 'INACTIVE';
    # einmaliger reset, wenn danach immer noch 'init retry count reached', dann SIGNALduino_CloseDevice()
    if (!defined($hash->{initResetFlag})) {
      $hash->{logMethod}->($name,2 , "$name: StartInit, retry count reached. Reset");
      $hash->{initResetFlag} = 1;
      SIGNALduino_ResetDevice($hash);
    } else {
      $hash->{logMethod}->($name,2 , "$name: StartInit, init retry count reached. Closed");
      SIGNALduino_CloseDevice($hash);
    }
    return;
  }
  else {
    $hash->{ucCmd}->{cmd} = 'version';
    $hash->{ucCmd}->{responseSub} = \&SIGNALduino_CheckVersionResp;
    $hash->{ucCmd}->{timenow} = time();
    SIGNALduino_SimpleWrite($hash, 'V');
    #DevIo_SimpleWrite($hash, "V\n",2);
    $hash->{DevState} = 'waitInit';
    FHEM::Core::Timer::Helper::removeTimer($name);
    FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_CMD_TIMEOUT, \&SIGNALduino_CheckVersionResp, $hash, 0);
  }
}

############################# package FHEM::Device::SIGNALduino::SD_IO, test exists
sub SIGNALduino_CheckVersionResp {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  ### ToDo, manchmal kommen Mu Nachrichten in $msg und somit ist keine Version feststellbar !!!
  if (defined($msg)) {
    $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, called with $msg");
    # Accessing %gets from main package
    if ($msg =~ m/($main::gets{$hash->{ucCmd}->{cmd}}[4])/ ) {
       $hash->{version} = $1;
       $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, version $hash->{version}");
    } else {
      delete $hash->{version};
    }
  } else {
    $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, called without msg");
    # Aufruf durch Timeout!
    $msg='undef';
    delete($hash->{ucCmd});
  }

  if (!defined($hash->{version}) ) {
    $msg = "$name: CheckVersionResp, Not an SIGNALduino device, got for V: $msg";
    $hash->{logMethod}->($hash, 1, $msg);
    main::readingsSingleUpdate($hash, 'state', 'no SIGNALduino found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
    $hash->{initretry} ++;
    SIGNALduino_StartInit($hash);
  } elsif($hash->{version} =~ m/^V 3\.1\./) {
    $msg = "$name: CheckVersionResp, Version of your arduino is not compatible, please flash new firmware. (device closed) Got for V: $msg";
    main::readingsSingleUpdate($hash, 'state', 'unsupported firmware found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
    $hash->{logMethod}->($hash, 1, $msg);
    $hash->{DevState} = 'INACTIVE';
    SIGNALduino_CloseDevice($hash);
  } else {
    if (exists($hash->{DevState}) && $hash->{DevState} eq 'waitInit') {
      FHEM::Core::Timer::Helper::removeTimer($name);
    }

    main::readingsSingleUpdate($hash, 'state', 'opened', 1);
    $hash->{logMethod}->($name, 2, "$name: CheckVersionResp, initialized " . main::SDUINO_VERSION());
    delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
    SIGNALduino_SimpleWrite($hash, 'XE'); # Enable receiver
    $hash->{logMethod}->($hash, 3, "$name: CheckVersionResp, enable receiver (XE) ");
    delete($hash->{initretry});
    # initialize keepalive
    $hash->{keepalive}{ok}    = 0;
    $hash->{keepalive}{retry} = 0;
    FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, \&SIGNALduino_KeepAlive, $hash, 0);
    if ($hash->{version} =~ m/cc1101/) {
      $hash->{cc1101_available} = 1;
      $hash->{logMethod}->($name, 5, "$name: CheckVersionResp, cc1101 available");
      main::SIGNALduino_Get($hash, $name,'ccconf');
      main::SIGNALduino_Get($hash, $name,'ccpatable');
    } else {
      # connect device without cc1101 to port where a device with cc1101 was previously connected (example DEF with /dev/ttyUSB0@57600) #
      $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, delete old READINGS from cc1101 device");
      if ( exists($hash->{cc1101_available}) ) {
        delete($hash->{cc1101_available});
      };

      for my $readingName  ( qw(cc1101_config cc1101_config_ext cc1101_patable) ) {
        main::readingsDelete($hash,$readingName);
      }
    }
    $hash->{DevState} = 'initialized';
    $msg = $hash->{version};
  }
  return ($msg,undef);
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_KeepAlive{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if ($hash->{DevState} eq 'disconnected');

  #SIGNALduino_Log3 $name,4 , "$name: KeepAliveOk, " . $hash->{keepalive}{ok};
  if (!$hash->{keepalive}{ok}) {
    delete($hash->{ucCmd});
    if ($hash->{keepalive}{retry} >= SDUINO_KEEPALIVE_MAXRETRY) {
      $hash->{logMethod}->($name,3 , "$name: KeepAlive, not ok, retry count reached. Reset");
      $hash->{DevState} = 'INACTIVE';
      SIGNALduino_ResetDevice($hash);
      return;
    } else {
      my $logLevel = 3;
      $hash->{keepalive}{retry} ++;
      if ($hash->{keepalive}{retry} == 1) {
        $logLevel = 4;
      }
      $hash->{logMethod}->($name, $logLevel, "$name: KeepAlive, not ok, retry = " . $hash->{keepalive}{retry} . ' -> get ping');
      $hash->{ucCmd}->{cmd} = 'ping';
      $hash->{ucCmd}->{timenow} = time();
      $hash->{ucCmd}->{responseSub} = \&main::SIGNALduino_GetResponseUpdateReading;
      main::SIGNALduino_AddSendQueue($hash, 'P');
    }
  }
  else {
    $hash->{logMethod}->($name,4 , "$name: KeepAlive, ok, retry = " . $hash->{keepalive}{retry});
  }
  $hash->{keepalive}{ok} = 0;

  FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, \&SIGNALduino_KeepAlive, $hash);
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_SimpleWrite {
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq 'SIGNALduino_RFR') {
    # Prefix $msg with RRBBU and return the corresponding SIGNALduino hash.
    ($hash, $msg) = main::SIGNALduino_RFR_AddPrefix($hash, $msg);
  }

  my $name = $hash->{NAME};
  $hash->{logMethod}->($name, 5, "$name: SimpleWrite, $msg");

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

############################# package FHEM::Device::SIGNALduino::SD_IO
sub SIGNALduino_WriteInit {
  my ($hash) = @_;

  # todo: ist dies so ausreichend, damit die Aenderungen uebernommen werden?
  main::SIGNALduino_AddSendQueue($hash,'WS36');   # SIDLE, Exit RX / TX, turn off frequency synthesizer
  main::SIGNALduino_AddSendQueue($hash,'WS3A');   # SFRX, Flush the RX FIFO buffer. Only issue SFRX in IDLE or RXFIFO_OVERFLOW states.
  main::SIGNALduino_AddSendQueue($hash,'WS34');   # SRX, Enable RX. Perform calibration first if coming from IDLE and MCSM0.FS_AUTOCAL=1.
}

1;
