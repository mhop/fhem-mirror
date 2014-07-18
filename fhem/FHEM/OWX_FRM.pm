########################################################################################
#
# OWX_FRM.pm
#
# FHEM module providing hardware dependent functions for the FRM interface of OWX
#
# Norbert Truchsess
#
# $Id$
#
########################################################################################
#
# Provides the following methods for OWX
#
# Define
# Init
# Verify #TODO refactor Verify...
# search
# alarms
# execute
#
########################################################################################

package OWX_FRM;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
  if ( !grep( /FHEM\/lib$/, @INC ) ) {
    foreach my $inc ( grep( /FHEM$/, @INC ) ) {
      push @INC, $inc . "/lib";
    };
  };
};

use Device::Firmata::Constants qw/ :all /;
use Time::HiRes qw( gettimeofday );
use ProtoThreads;
no warnings 'deprecated';

sub new() {
  my ($class) = @_;

  return bless {
    interface => "firmata",

    #-- module version
    version => 4.0
  }, $class;
}

sub Define($$) {
  my ( $self, $hash, $def ) = @_;

  my @a = split( "[ \t][ \t]*", $def );
  my $u = "wrong syntax: define <name> FRM_XXX pin";
  return $u unless int(@a) > 0;
  $self->{pin} = $a[2];
  $self->{id}  = 0;
  $self->{name} = $hash->{NAME};
  $self->{hash} = $hash;
  return undef;
}

########################################################################################
#
# Init - Initialize the 1-wire device
#
# Parameter hash = hash of bus master
#
# Return 1 or Errormessage : not OK
#        0 or undef : OK
#
########################################################################################

sub initialize($)
{
  my ( $self, $hash ) = @_;

  main::LoadModule("FRM");
  my $pin = $self->{pin};
  my $ret = main::FRM_Init_Pin_Client( $hash, [$pin], PIN_ONEWIRE );
  die $ret if ( defined $ret );
  my $firmata = main::FRM_Client_FirmataDevice($hash);
  $firmata->observe_onewire( $pin, \&FRM_OWX_observer, $self );
  $self->{devs} = [];
  if ( main::AttrVal( $hash->{NAME}, "buspower", "" ) eq "parasitic" ) {
    $firmata->onewire_config( $pin, 1 );
  }
  $firmata->onewire_search($pin);
  return $self;
}

sub exit()
{
  my ($self) = @_;
  #TODO implement deconfigure onewire in firmata.
};

sub FRM_OWX_observer
{
  my ( $data, $self ) = @_;
  my $command = $data->{command};
COMMAND_HANDLER: {
    $command eq "READ_REPLY" and do {
      $self->{responses}->{$data->{id}} = $data->{data}; # // $data->{device} // "defaultid"}
      main::Log3 ($self->{name},5,"FRM_OWX_observer: READ_REPLY $data->{id}: ".join " ",map sprintf("%02X",$_),@{$data->{data}}) if $self->{debug};
      last;
    };
    ( $command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY" ) and do {
      my @owx_devices = ();
      foreach my $device ( @{ $data->{devices} } ) {
        push @owx_devices, firmata_to_device($device);
      };
      if ( $command eq "SEARCH_REPLY" ) {
        $self->{devs} = \@owx_devices;
        main::Log3 ($self->{name},5,"FRM_OWX_observer: SEARCH_REPLY: ".join ",",@owx_devices) if $self->{debug};
        $self->{devs_timestamp} = gettimeofday();
        #TODO avoid OWX_ASYNC_AfterSearch to be called twice
        main::OWX_ASYNC_AfterSearch($self->{hash},\@owx_devices);
      } else {
        $self->{alarmdevs} = \@owx_devices;
        main::Log3 ($self->{name},5,"FRM_OWX_observer: SEARCH_ALARMS_REPLY: ".join ",",@owx_devices) if $self->{debug};
        $self->{alarmdevs_timestamp} = gettimeofday();
        #TODO avoid OWX_ASYNC_AfterAlarms to be called twice
        main::OWX_ASYNC_AfterAlarms($self->{hash},\@owx_devices);
      };
      last;
    };
  };
  main::OWX_ASYNC_RunTasks($self->{hash});
};

########### functions implementing interface to OWX ##########

sub device_to_firmata
{
  my @device;
  foreach my $hbyte ( unpack "A2xA2A2A2A2A2A2xA2", shift ) {
    push @device, hex $hbyte;
  }
  return {
    family   => shift @device,
    crc      => pop @device,
    identity => \@device,
  }
}

sub firmata_to_device
{
  my $device = shift;
  return sprintf( "%02X.%02X%02X%02X%02X%02X%02X.%02X", $device->{family}, @{ $device->{identity} }, $device->{crc} );
}

########################################################################################
#
# factory methods for protothreads running discover, search, alarms and execute
#
########################################################################################

########################################################################################
#
# Discover - Find devices on the 1-Wire bus
#
# Parameter hash = hash of bus master
#
# Return 1, if alarmed devices found, 0 otherwise.
#
########################################################################################

sub get_pt_discover() {
  my ($self) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    delete $self->{devs};
    main::FRM_Client_FirmataDevice($self->{hash})->onewire_search($self->{pin});
    PT_WAIT_UNTIL(defined $self->{devs});
    PT_EXIT($self->{devs});
    PT_END;
  });
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return number of alarmed devices
#
########################################################################################

sub get_pt_alarms() {
  my ($self) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    delete $self->{alarmdevs};
    main::FRM_Client_FirmataDevice($self->{hash})->onewire_search_alarms($self->{pin});
    PT_WAIT_UNTIL(defined $self->{alarmdevs});
    PT_EXIT($self->{alarmdevs});
    PT_END;
  });
}

sub get_pt_verify($) {
  my ($self,$dev) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    delete $self->{devs};
    main::FRM_Client_FirmataDevice($self->{hash})->onewire_search($self->{pin});
    PT_WAIT_UNTIL(defined $self->{devs});
    PT_EXIT(scalar(grep {$dev eq $_} @{$self->{devs}}));
    PT_END;
  });
}

########################################################################################
# 
# Complex - Send match ROM, data block and receive bytes as response
#
# Parameter hash    = hash of bus master, 
#           owx_dev = ROM ID of device
#           data    = string to send
#           numread = number of bytes to receive
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub get_pt_execute($$$$) {
  my ($self, $reset, $owx_dev, $writedata, $numread) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    
    PT_BEGIN($thread);

    if (  my $firmata = main::FRM_Client_FirmataDevice($self->{hash}) and my $pin = $self->{pin} ) {
      my @data = unpack "C*", $writedata if defined $writedata;
      my $id = $self->{id};
      my $ow_command = {
        'reset'  => $reset,
        'skip'   => defined($owx_dev) ? undef : 1,
        'select' => defined($owx_dev) ? device_to_firmata($owx_dev) : undef,
        'read'  => $numread,
        'write' => @data ? \@data : undef,
        'delay' => undef,
        'id'    => $numread ? $id : undef
      };
      main::Log3 ($self->{name},5,"FRM_OWX_Execute: $id: $owx_dev [".join(" ",(map sprintf("%02X",$_),@data))."] numread: ".(defined $numread ? $numread : 0)) if $self->{debug};
      $firmata->onewire_command_series( $pin, $ow_command );
      if ($numread) {
        $thread->{id} = $id;
        $self->{id} = ( $id + 1 ) & 0xFFFF;
        delete $self->{responses}->{$id};
        PT_WAIT_UNTIL(defined $self->{responses}->{$thread->{id}});
        my $ret = pack "C*", @{$self->{responses}->{$thread->{id}}};
        delete $self->{responses}->{$thread->{id}};
        PT_EXIT($ret);
      };
    };
    PT_END;
  });
};

sub poll($) {
  my ( $self, $hash ) = @_;
  if ( my $frm = $hash->{IODev} ) {
    main::FRM_poll($frm);
  }
};

1;
