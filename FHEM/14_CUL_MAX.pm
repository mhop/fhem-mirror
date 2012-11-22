##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
use Data::Dumper;

sub CUL_MAX_SendDeviceCmd($$);

sub
CUL_MAX_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^Z";
  $hash->{DefFn}     = "CUL_MAX_Define";
  $hash->{UndefFn}   = "CUL_MAX_Undef";
  $hash->{ParseFn}   = "CUL_MAX_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6";
}

#############################
sub
CUL_MAX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_MAX <srdAddr>" if(@a<2);

  $hash->{addr} = $a[1];
  $hash->{STATE} = "Defined";
  $hash->{cnt} = 0;
  Log 4, "CUL_MAX defined";
  AssignIoPort($hash);

  #This interface is shared with 00_MAXLAN.pm
  $hash->{SendDeviceCmd} = \&MAXLAN_SendDeviceCmd;

  return undef;
}

#####################################
sub
CUL_MAX_Undef($$)
{
  my ($hash, $name) = @_;
  return undef;
}

###################################
my @culHmCmdFlags = ("WAKEUP", "WAKEMEUP", "BCAST", "Bit3",
                     "BURST", "BIDI", "RPTED", "RPTEN");
sub
CUL_MAX_Parse($$)
{
  my ($hash, $msg) = @_;
  $msg =~ m/Z(..)(..)(..)(..)(......)(......)(.*)/;
  my ($len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p) = ($1,$2,$3,$4,$5,$6,$7);
  Log 1, "CUL_MAX_Parse: len mismatch" . (length($msg)/2-1) . " != ". hex($len) if(hex($len) != length($msg)/2-1);
  my $msgFlLong = "";
  for(my $i = 0; $i < @culHmCmdFlags; $i++) {
      $msgFlLong .= ",$culHmCmdFlags[$i]" if(hex($msgFlag) & (1<<$i));
  }
  Log 5, "CUL_MAX_Parse: len $len, msgcnt $msgcnt, msgflag $msgFlLong, msgType $msgType, src $src, dst $dst, payload $p";
  return undef;
}

sub CUL_MAX_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;

  my $srcAddr = AttrVal($hash->{NAME},"srcAddrMAX","123456");

  $hash->{cnt} += 1;
  substr($payload,3,3) = pack("H6",$srcAddr);
  substr($payload,1,0) = pack("C",$hash->{cnt});
  $payload = pack("C",length($payload)) . $payload;

  Log 5, "CUL_MAX_SendDeviceCmd: ". unpack("H*",$payload);
}

1;


=pod
=begin html

<a name="CUL_MAX"></a>
<h3>CUL_MAX</h3>
<ul>
  The CUL_MAX module interprets MAX! messages received by the CUL. It will be automatically created by autocreate, just make sure
  that you set the right rfmode like <code>attr CUL0 rfmode MAX</code>.<br>
  You should also set a (random) source address for this module by <code>attr CUL0 srcAddrMAX <6-digit-hex></code>
  <br><br>

  <a name="CUL_MAXdefine"></a>
  <b>Define</b>
  <ul>N/A</ul>
  <br>

  <a name="CUL_MAXset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
  </ul>
  <br>

  <a name="CUL_MAXevents"></a>
  <b>Generated events:</b>
  <ul>N/A</ul>
  <br>

</ul>


=end html
=cut
