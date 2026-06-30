# $Id$
package FHEM::Devices::SIGNALduino::SD_Utils;

use strict;
use warnings;
use Carp;
use Exporter qw(import);

our @EXPORT_OK = qw(
  _limit_to_number
  _limit_to_hex
  SIGNALduino_Log3
  SIGNALduino_createLogCallback
  SIGNALduino_callsub
);
our %EXPORT_TAGS = (
    'all' => \@EXPORT_OK,
);


############################# package FHEM::Devices::SIGNALduino::SD_Utils, candidate for fhem core utility lib
sub _limit_to_number {
  my $number = shift // return;
  return $number if ($number =~ /^[0-9]+$/);
  return ;
}


############################# package FHEM::Devices::SIGNALduino::SD_Utils, candidate for fhem core utility lib
sub _limit_to_hex {
  my $hex = shift // return;
  return $hex if ($hex =~ /^[0-9A-F]+$/i);
  return;
}

############################# package FHEM::Devices::SIGNALduino::SD_Utils
# the new Log with integrated loglevel checking
sub SIGNALduino_Log3 {
  my ($dev, $loglevel, $text) = @_;
  my $name =$dev;
  $name= $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");

  my $textEventlogging = $text;

  ### DoTrigger for eventlogging event
  #DoTrigger($dev,"$name $loglevel: $text");
  #2020-07-14_12:47:01 sduino_USB_SB_Test sduino_USB_SB_Test 4: sduino_USB_SB_Test: HandleWriteQueue, called

  #DoTrigger($dev,"$loglevel: $text");
  #2020-07-14_12:47:01 sduino_USB_SB_Test 4: sduino_USB_SB_Test: HandleWriteQueue, called

  ### $text may not be changed for return value
  if ($textEventlogging =~ /^$dev:\s/) {
    my $textCut = length($dev)+2;                            # length receivername and ': "
    $textEventlogging = substr($textEventlogging,$textCut);  # cut $textCut from $textEventlogging
  }

  ### DoTrigger for eventlogging event with adapted structure
  main::DoTrigger($dev,"$loglevel: $textEventlogging");
  #2020-07-16_12:40:07 sduino_USB_SB_Test 4: HandleWriteQueue, called

  ### return for normal logfile | unchangeable
  #2020.07.16 11:35:40.676 4: sduino_USB_SB_Test: HandleWriteQueue, called
  return main::Log3($name,$loglevel,$text);
}

############################# package FHEM::Devices::SIGNALduino::SD_Utils
# Helper to create a individual callback per definition which can receive log output from perl modules
sub SIGNALduino_createLogCallback {
  my $hash = shift // return ;
  (ref $hash ne 'HASH') // return ;

  return sub  {
    my $message = shift // carp 'message must be provided';
    my $level = shift // 0;

    $hash->{logMethod}->($hash->{NAME}, $level,qq[$hash->{NAME}: $message]);
  };
};

############################# package FHEM::Devices::SIGNALduino::SD_Utils, test exists
sub SIGNALduino_callsub {
  my $obj=shift; #comatibility thing
  my $funcname =shift // carp 'to less arguments,functionname is required';;
  my $method = shift // undef;
  my $evalFirst = shift // undef;
  my $name = shift // carp 'to less arguments, name is required';

  my @args = @_;

  my $hash = $main::defs{$name};
  if ( defined $method && defined &$method )
  {
    if (defined($evalFirst) && $evalFirst)
    {
      eval( $method->($obj,$name, @args));
      if($@) {
        $hash->{logMethod}->($name, 5, "$name: callsub, Error: $funcname, has an error and will not be executed: $@ please report at github.");
        return (0,undef);
      }
    }
    #my $subname = @{[eval {&$method}, $@ =~ /.*/]};
    $hash->{logMethod}->($hash, 5, "$name: callsub, applying $funcname, value before: @args"); # method $subname"

    my ($rcode, @returnvalues) = $method->($obj,$name, @args) ;

    if (@returnvalues && defined($returnvalues[0])) {
      $hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, modified value after $funcname: @returnvalues");
    } else {
      $hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, after calling $funcname");
    }
    return ($rcode, @returnvalues);
  } elsif (defined $method ) {
    $hash->{logMethod}->($name, 5, "$name: callsub, Error: Unknown method $funcname pease report at github");
    return (0,undef);
  }
  return (1,@args);
}

1;