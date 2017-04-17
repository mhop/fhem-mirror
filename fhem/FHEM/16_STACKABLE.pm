##############################################
# $Id$
package main;
use strict;
use warnings;

#####################################
sub
STACKABLE_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^\\*";
  $hash->{DefFn}     = "STACKABLE_Define";
  $hash->{UndefFn}   = "STACKABLE_Undef";
  $hash->{ParseFn}   = "STACKABLE_Parse";
  $hash->{NotifyFn}  = "STACKABLE_Notify";
  $hash->{AttrList}  = "IODev ignore:1,0 binary:1,0 writePrefix";

  $hash->{noRawInform} = 1;     # Our message was already sent as raw.
  $hash->{noAutocreatedFilelog} = 1;

  $hash->{IOOpenFn}  = "STACKABLE_IOOpenFn";
  $hash->{IOReadFn}  = "STACKABLE_IOReadFn";
  $hash->{IOWriteFn} = "STACKABLE_IOWriteFn";
}


#####################################
sub
STACKABLE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> STACKABLE baseDevice"
    if(int(@a) != 3);

  my $io = $defs{$a[2]};
  return "$a[2] is not a valid device"
    if(!$io);
  return "$io->{NAME} already has a stacked device: $io->{STACKED}"
    if($io->{STACKED});

  $io->{STACKED} = $hash->{NAME};
  $hash->{IODev} = $io;
  delete($io->{".clientArray"}); # Force a recompute
  $hash->{STATE} = "Defined";
  notifyRegexpChanged($hash, $a[2]);

  return undef;
}

#####################################
sub
STACKABLE_Parse($$)
{
  my ($iohash,$msg) = @_;

  return "UNDEFINED $iohash->{NAME}_STACKABLE STACKABLE $iohash->{NAME}"
    if(!$iohash->{STACKED});

  my $name = $iohash->{STACKED};
  return "" if(IsIgnored($name));

  $msg =~ s/^.//; # Cut off prefix *
  my $sh = $defs{$name};

  my $ch = $sh->{".clientHash"};
  if($ch) {
    delete $ch->{IOReadFn};
    $ch->{IODevRxBuffer} = (AttrVal($name,"binary",0) ?
                                pack("H*",$msg) : $msg."\n");
    CallFn($ch->{NAME}, "ReadFn", $ch);
    $ch->{IOReadFn} = "STACKABLE_IOReadFn";
  } else {
    Log 1, "$name: no client device assigned";
  }
  return "";
}

sub
STACKABLE_Undef($$)
{
  my ($hash, $arg) = @_;
  delete $hash->{IODev}{STACKED};
  return undef;
}

sub
STACKABLE_Notify($$)
{
  my ($me, $src) = @_;

  my $eva = deviceEvents($src,0);
  return undef if(!$eva || !@$eva);
  my $evt = $eva->[0];
  my $tgt = $me->{".clientHash"};

  if($evt eq "DISCONNECTED") {
    DevIo_Disconnected($tgt);
    my ($dev, undef) = split("@", $tgt->{DeviceName});
    delete $readyfnlist{"$tgt->{NAME}.$dev"}; # no polling by child devices
    delete $tgt->{DevIoJustClosed};

  } elsif($evt eq "CONNECTED") {
    CallFn($tgt->{NAME}, "ReadyFn", $tgt);

  }
  return undef;
}

sub
STACKABLE_IOOpenFn($)
{
  my ($hash) = @_;
  $hash->{FD} = $hash->{IODev}{IODev}{FD};     # Lets fool the client
  $hash->{IODev}{".clientHash"} = $hash;
  $hash->{IOReadFn} = "STACKABLE_IOReadFn";
  return 1;
}

sub
STACKABLE_IOReadFn($) # used by synchronuous get
{
  my ($hash) = @_;
  my $me = $hash->{IODev};
  my $buf = "";
  if($me->{IODev} && $me->{IODev}{PARTIAL}) {
    $buf = $me->{IODev}{PARTIAL};
    $me->{IODev}{PARTIAL} = "";
  }
  while($buf !~ m/\n/) {
    my $ret = DevIo_SimpleReadWithTimeout($me->{IODev}, 1); # may block
    return undef if(!defined($ret));
    $buf .= $ret;
  }

  my $mName = $me->{NAME};
  Log3 $mName, 5, "$mName read: $buf";
  my @l = split("\n", $buf);
  $buf = join("\n", grep { $_ =~ m/^\*/ } @l)."\n";

  $buf =~ s/^\*//gsm;
  if(AttrVal($me->{NAME},"binary",0)) {
    $buf =~ s/[\r\n]//g;
    return pack("H*",$buf);
  } else {
    return $buf;
  }
}

sub
STACKABLE_IOWriteFn($$)
{
  my ($hash, $msg) = @_;
  my $myhash = $hash->{IODev};
  my $myname = $myhash->{NAME};

  my $prf = AttrVal($myname,"writePrefix","*");
  if(AttrVal($myname,"binary",0)) {
    return IOWrite($myhash, "", $prf.unpack("H*",$msg));
  } else {
    $msg =~ s/[\r\n]//g;
    return IOWrite($myhash, "", $prf.$msg);
  }
}

1;


=pod
=item summary    Module for stacked IO devices like the Busware SCC
=item summary_DE Modul fuer gestapelte IO Ger&auml;te wie das Busware SCC
=begin html

<a name="STACKABLE"></a>
<h3>STACKABLE</h3>
<ul>
  This module is a more generic version of the STACKABLE_CC module, and is used
  for stacked IO devices like the Busware SCC. It works by adding/removing a
  prefix (default is *) to the command, and redirecting the output to the
  module, which is using it.

  <a name="STACKABLEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; STACKABLE &lt;baseDevice&gt;</code> <br>
    <br>
    &lt;baseDevice&gt; is the name of the unterlying device.<br>
    Example:
    <ul><code>
      define CUL_1 CUL /dev/ttyAMA0@38400<br>
      attr   CUL_1 rfmode SlowRF<br><br>
      define CUL_1_SCC STACKABLE CUL1<br>
      define CUL_2 CUL FHEM:DEVIO:CUL_1_SCC:9600 0000<br>
      attr   CUL_2 rfmode HomeMatic<br><br>
      define CUL_2_SCC STACKABLE CUL2<br>
      define CUL_3 ZWCUL FHEM:DEVIO:CUL_2_SCC:9600 12345678 01<br>
    </code></ul>
    <b>Note:</b>If you rename the base CUL or a STACKABLE, which is a base for
    another one, the definition of the next one has to be adjusted, and FHEM
    has to be restarted.
  </ul>

  <a name="STACKABLEset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="STACKABLEget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="STACKABLEattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="#writePrefix">writePrefix</a><br>
      The prefix used when writing data, default is *.
      "readPrefix" is hardcoded to *.
      </li><br>

    <li><a name="#binary">binary</a><br>
      If set to true, read data is converted to binary from hex before offering
      it to the client IO device (e.g. TCM). Default is 0 (off).
      </li><br>
  </ul>
</ul>

=end html


=cut
