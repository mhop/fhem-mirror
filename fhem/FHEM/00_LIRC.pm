##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Lirc::Client;
use IO::Select;

#####################################
# Note: we are a data provider _and_ a consumer at the same time
sub
LIRC_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "LIRC_Read";
  $hash->{ReadyFn} = "LIRC_Ready";
  $hash->{Clients} = ":LIRC:";

# Consumer
  $hash->{DefFn}   = "LIRC_Define";
  $hash->{UndefFn} = "LIRC_Undef";
  $hash->{AttrList}= "";
}

#####################################
sub
LIRC_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE} = "Initialized";

  $hash->{LircObj}->clean_up() if($hash->{LircObj});
  delete $hash->{LircObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $config = $a[2];

  Log3 $name, 3, "LIRC opening $name device $config";
  my $lirc = Lirc::Client->new({
        prog    => 'fhem',
        rcfile  => "$config", 
        debug   => 0,
        fake    => 0,
    });
  return "Can't open $config: $!\n" if(!$lirc);
  Log3 $name, 3, "LIRC opened $name device $config";

  my $select = IO::Select->new();
  $select->add( $lirc->sock );

  $hash->{LircObj} = $lirc;
  
  $hash->{FD} = $lirc->{sock};       # is not working and sets timeout to undefined 
  $selectlist{"$name"} = $hash;      # 
  $readyfnlist{"$name"} = $hash;     # thats why we start polling
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

  $hash->{LircObj}->clean_up() if($hash->{LircObj});
  delete $hash->{LircObj};
  delete $hash->{FD};

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
    my $name = $hash->{NAME};
    for my $code (@codes){
      Log3 $name, 3, "LIRC $name $code";
      DoTrigger($name, $code);
    }
  }

}

#####################################
sub
LIRC_Ready($)
{
  my ($hash) = @_;

  my $select= $hash->{SelectObj};

  return $select->can_read(0);
}

1;

=pod
=begin html

<a name="LIRC"></a>
<h3>LIRC</h3>
<ul>
  Generate FHEM-events when an LIRC device receives infrared signals.
  <br><br>
  Note: this module needs the Lirc::Client perl module.
  <br><br>

  <a name="LIRCdefine"></a>
  <b>Define</b>
  <ul>
    define &lt;name&gt; LIRC &lt;lircrc_file&gt;<br>
    Example:<br>
    <ul>
     define Lirc LIRC /etc/lirc/lircrc
    </ul>
    Note: In the lirc configuration file you have to define each possible event.
    If you have this configuration
    <pre>
    begin
      prog = fhem
      button = pwr
      config = IrPower
    end</pre>
    and you press the pwr button the IrPower toggle event occures at fhem.
    <pre>
    define IrPower01 notify Lirc:IrPower set lamp toggle</pre>
    turns the lamp on and off.
    If you want a faster reaction to keypresses you have to change the
    defaultvalue of readytimeout from 5 seconds to e.g. 1 second in fhem.pl
  </ul>
  <br>

  <a name="LIRCset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="LIRCget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="LIRCattr"></a>
  <b>Attributes</b>
  <ul>
  </ul><br>
</ul>

=end html
=cut
