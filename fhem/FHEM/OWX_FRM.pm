########################################################################################
#
# OWX_FRM.pm
#
# FHEM module providing hardware dependent functions for the FRM interface of OWX
#
# Norbert Truchsess
#
# $Id: 11_OWX_FRM.pm 2013-03 - ntruchsess $
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
use Time::HiRes qw(gettimeofday tv_interval);

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
  $self->{delayed} = {};
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

sub Disconnect($)
{
  my ($hash) = @_;
  $hash->{STATE} = "disconnected";
};

sub FRM_OWX_observer
{
  my ( $data, $self ) = @_;
  my $command = $data->{command};
COMMAND_HANDLER: {
    $command eq "READ_REPLY" and do {
      my $id = $data->{id};
      my $request = ( defined $id ) ? $self->{requests}->{$id} : undef;
      unless ( defined $request ) {
        return unless ( defined $data->{device} );
        my $owx_device = FRM_OWX_firmata_to_device( $data->{device} );
        my %requests   = %{ $self->{requests} };
        foreach my $key ( keys %requests ) {
          if ( $requests{$key}->{device} eq $owx_device ) {
            $request = $requests{$key};
            $id      = $key;
            last;
          };
        };
      };
      return unless ( defined $request );
      my $owx_data   = pack "C*", @{ $data->{data} };
      my $owx_device = $request->{device};
      my $context    = $request->{context};
      my $reqcommand = $request->{command};
      my $writedata  = pack "C*", @{ $reqcommand->{'write'} } if ( defined $reqcommand->{'write'} );
      main::OWX_ASYNC_AfterExecute( $self->{hash}, $context, 1, $reqcommand->{'reset'}, $owx_device, $writedata, $reqcommand->{'read'}, $owx_data);
      delete $self->{requests}->{$id};
      last;
    };
    ( $command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY" ) and do {
      my @owx_devices = ();
      foreach my $device ( @{ $data->{devices} } ) {
        push @owx_devices, FRM_OWX_firmata_to_device($device);
      };
      if ( $command eq "SEARCH_REPLY" ) {
        $self->{devs} = \@owx_devices;
        main::OWX_ASYNC_AfterSearch( $self->{hash}, \@owx_devices );
      } else {
        $self->{alarmdevs} = \@owx_devices;
        main::OWX_ASYNC_AfterAlarms( $self->{hash}, \@owx_devices );
      };
      last;
    };
  };
};

########### functions implementing interface to OWX ##########

sub FRM_OWX_device_to_firmata
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

sub FRM_OWX_firmata_to_device
{
  my $device = shift;
  return sprintf( "%02X.%02X%02X%02X%02X%02X%02X.%02X", $device->{family}, @{ $device->{identity} }, $device->{crc} );
}

########################################################################################
#
# asynchronous methods search, alarms and execute
#
########################################################################################

sub discover($) {
  my ( $self, $hash ) = @_;
  my $success = undef;
  eval {
    if ( my $firmata = main::FRM_Client_FirmataDevice($hash) and my $pin = $self->{pin} ) {
      $firmata->onewire_search($pin);
      $success = 1;
    };
  };
  if ($@) {
    main::Log( 5, $@ );
    $self->exit($hash);
  };
  return $success;
};

sub alarms($) {
  my ( $self, $hash ) = @_;
  my $success = undef;
  eval {
    if ( my $firmata = main::FRM_Client_FirmataDevice($hash) and my $pin = $self->{pin} ) {
      $firmata->onewire_search_alarms($pin);
      $success = 1;
    };
  };
  if ($@) {
    $self->exit($hash);
  };
  return $success;
};

sub execute($$$$$$$) {
  my ( $self, $hash, $context, $reset, $owx_dev, $data, $numread, $delay ) = @_;

  my $delayed = $self->{delayed};
  my $queue = $delayed->{$owx_dev} if defined $owx_dev;

  if ( $queue and @{$queue->{items}} ) {
    if ( $context or $reset or $data or $numread or $delay ) {
      push @{$queue->{items}}, {
        context => $context,
        'reset' => $reset,
        device  => $owx_dev,
        data    => $data,
        numread => $numread,
        delay   => $delay
        };
    };
    if (!( defined $queue->{'until'} ) or ( tv_interval( $queue->{'until'} ) >= 0 ) ) {
      my $item = shift @{$queue->{items}};
      $context = $item->{context};
      $reset   = $item->{'reset'};
      $data    = $item->{data};
      $numread = $item->{numread};
      $delay   = $item->{delay};
    } else {
      return 1;
    }
  }
  return 1 unless ( $context or $reset or $data or $numread or $delay );

  my $success = undef;

  eval {
    if (  my $firmata = main::FRM_Client_FirmataDevice($hash) and my $pin = $self->{pin} ) {
      my @data = unpack "C*", $data if defined $data;
      my $id = $self->{id} if ($numread);
      my $ow_command = {
        'reset'  => $reset,
        'skip'   => defined($owx_dev) ? undef : 1,
        'select' => defined($owx_dev) ? FRM_OWX_device_to_firmata($owx_dev) : undef,
        'read'  => $numread,
        'write' => @data ? \@data : undef,
        'delay' => undef,
        'id'    => $numread ? $id : undef
      };
      if ($numread) {
        $owx_dev = '00.000000000000.00' unless defined $owx_dev;
        $self->{requests}->{$id} = {
          context => $context,
          command => $ow_command,
          device  => $owx_dev
        };
        $self->{id} = ( ( $id + 1 ) & 0xFFFF );
      };
      $firmata->onewire_command_series( $pin, $ow_command );
      $success = 1;
    };
  };
  if ($@) {
    main::Log3 $hash->{NAME},1,"OWX_FRM: $@";
    #$self->exit($hash);
  };

  if ($delay and $success) {
    unless ($queue) {
      $queue = { items => [] } ;
      $delayed->{$owx_dev} = $queue;
    }
    my ( $seconds, $micros ) = gettimeofday;
    my $len = length($delay);    #delay is millis, tv_address works with [sec,micros]
    if ( $len > 3 ) {
      $seconds += substr( $delay, 0, $len - 3 );
      $micros += ( substr( $delay, $len - 3 ) * 1000 );
    } else {
      $micros += ( $delay * 1000 );
    }
    $queue->{'until'} = [ $seconds, $micros ];
    main::InternalTimer( "$seconds.$micros", "OWX_ASYNC_Poll", $hash, 0 );
  } else {
    if ($queue) {
      if (@{$queue->{items}}) {
        delete( $queue->{'until'} );
      } else {
        delete $delayed->{$owx_dev};
      }
    }
  }
  unless ($numread) {
    main::OWX_ASYNC_AfterExecute( $hash, $context, $success, $reset, $owx_dev, $data, $numread, "" );
  }
  return $success;
};

sub exit($) {
  my ( $self, $hash ) = @_;
  main::OWX_ASYNC_Disconnected($hash);
};

sub poll($) {
  my ( $self, $hash ) = @_;
  if ( my $frm = $hash->{IODev} ) {
    main::FRM_poll($frm);
    foreach my $address ( keys %{$self->{delayed}} ) {
      $self->execute( $hash, undef, undef, $address, undef, undef, undef );
      main::FRM_poll($frm);
    }
  }
};

#sub printqueues($$) {
#  my ($self,$hash,$calledfrom) = @_;
#  my $name = $hash->{NAME};
#  main::Log3 $name,5,"OWX_ASYNC all queues, called from :".$calledfrom;
#  my $delayed = $self->{delayed};
#  
#  foreach my $address ( keys %$delayed ) {
#    my $msg = $address.": until: ";
#    $msg .= $delayed->{$address}->{'until'} ? $delayed->{$address}->{'until'}->[0].",".$delayed->{$address}->{'until'}->[1] : "---";
#    $msg .= " items: [";
#    foreach my $item (@{$delayed->{$address}->{'items'}}) {
#      $msg .= $item->{context}.",";
#    }
#    $msg .= "]";
#    main::Log3 $name,5,$msg;
#  }
#}

1;
