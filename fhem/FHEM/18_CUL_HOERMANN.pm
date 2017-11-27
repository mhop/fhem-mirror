##############################################
# $Id$
package main;

use strict;
use warnings;

sub
CUL_HOERMANN_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^R..........\$";
  $hash->{DefFn}     = "CUL_HOERMANN_Define";
  $hash->{ParseFn}   = "CUL_HOERMANN_Parse";
  $hash->{SetFn}     = "CUL_HOERMANN_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 ".
                       "disable:0,1 disabledForIntervals ";
}

#############################
sub
CUL_HOERMANN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> CUL_HOERMANN housecode " .
                        "addr [fg addr] [lm addr] [gm FF]";

  return "wrong syntax: define <name> CUL_HOERMANN 10-digit-hex-code"
        if(int(@a) != 3 || $a[2] !~ m/^[a-f0-9]{10}$/i);

  $modules{CUL_HOERMANN}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";
  AssignIoPort($hash);
  return undef;
}

sub
CUL_HOERMANN_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: R0123456789
  my $cde = substr($msg, 1, 10);
  my $def = $modules{CUL_HOERMANN}{defptr}{$cde};

  if($def) {
    my $name = $def->{NAME};
    $def->{CHANGED}[0] = "toggle";
    $def->{READINGS}{state}{TIME} = TimeNow();
    $def->{READINGS}{state}{VAL} = "toggle";
    Log3 $name, 4, "CUL_HOERMANN $name toggle";
    return $name;

  } else {
    Log3 $hash, 3, "CUL_HOERMANN Unknown device $cde, please define it";
    return "UNDEFINED CUL_HOERMANN_$cde CUL_HOERMANN $cde";
  }
}

sub
CUL_HOERMANN_Set($@)
{
  my ($hash, @a) = @_;

  return "no set argument specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of toggle:noArg"
    if($a[1] ne "toggle");

  return if(IsDisabled($hash->{NAME}));

  IOWrite($hash, "", "hn".$hash->{DEF})
}

1;

=pod
=item summary    Hoermann Garage door opener
=item summary_DE Hoermann Garagenfernbedienung
=begin html

<a name="CUL_HOERMANN"></a>
<h3>CUL_HOERMANN</h3>
<ul>
  The CUL_HOERMANN module registers the 868MHz Hoermann Garage-Door-Opener
  signals received by the CUL. <b>Note</b>: As the structure of this signal is
  not understood, no checksum is verified, so it is likely to receive bogus
  messages.
  <br><br>

  <a name="CUL_HOERMANNdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_HOERMANN &lt;10-digit-hex-code&gt;</code>
    <br>
  </ul>
  <br>

  <a name="CUL_HOERMANNset"></a>
  <b>Set</b>
  <ul>
    <li>toggle<br>
        Send a signal, which, depending on the status of the door, opens it,
        closes it or stops the current movement. NOTE: needs culfw 1.67+
        </li>
  </ul><br>

  <a name="CUL_HOERMANNget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_HOERMANNattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul>
  <br>
</ul>


=end html
=cut
