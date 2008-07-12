##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Lirc::Client;
use IO::Select;

my $def;

#####################################
# Note: we are a data provider _and_ a consumer at the same time
sub
LIRC_Initialize($)
{
  my ($hash) = @_;
  Log 1, "LIRC_Initialize";

# Provider
  $hash->{ReadFn}  = "LIRC_Read";
  $hash->{Clients} = ":LIRC:";

# Consumer
  $hash->{DefFn}   = "LIRC_Define";
  $hash->{UndefFn} = "LIRC_Undef";
}

#####################################
sub
LIRC_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE} = "Initialized";

  delete $hash->{LircObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $config = $a[2];

  Log 3, "LIRC opening LIRC device $config";
  my $lirc = Lirc::Client->new({
        prog    => 'fhem',
        rcfile  => "$config", 
        debug   => 0,
        fake    => 0,
    });
  return "Can't open $config: $!\n" if(!$lirc);
  Log 3, "LIRC opened $name device $config";

  my $select = IO::Select->new();
  $select->add( $lirc->sock );

  $hash->{LircObj} = $lirc;
  $hash->{FD} = $lirc->sock;
  $hash->{SelectObj} = $select;
  $hash->{DeviceName} = $name;    
  $hash->{STATE} = "Opened";

  return undef;
}

#####################################
sub
LIRC_Undef($$)
{
  my ($hash, $arg) = @_;

  $hash->{LircObj}->close() if($hash->{LircObj});
  return undef;
}

#####################################
sub
LIRC_Read($)
{
  my ($hash) = @_;

  my $lirc= $hash->{LircObj};
  my $select= $hash->{SelectObj};

  if( my @ready = $select->can_read(0) ){ 
    # an ir event has been received (if you are tracking other filehandles, you need to make sure it is lirc)
    my @codes = $lirc->next_codes;    # should not block
    for my $code (@codes){
      Log 3, "LIRC code: $code\n";
      DoTrigger($code, "toggle");
    }
  }

}

1;
