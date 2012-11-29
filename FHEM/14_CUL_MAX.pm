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
  $hash->{Clients}   = ":MAX:";
  my %mc = (
    "1:MAX" => "^MAX",
  );
  $hash->{MatchList} = \%mc;
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

  return "wrong syntax: define <name> CUL_MAX <srdAddr>" if(@a<3);

  if(exists($modules{CUL_MAX}{defptr})) {
    Log 1, "There is already on CUL_MAX defined";
    return "There is already on CUL_MAX defined";
  }
  $modules{CUL_MAX}{defptr} = $hash;

  $hash->{addr} = $a[2];
  $hash->{STATE} = "Defined";
  $hash->{cnt} = 0;
  AssignIoPort($hash);

  #This interface is shared with 00_MAXLAN.pm
  $hash->{SendDeviceCmd} = \&CUL_MAX_SendDeviceCmd;

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

my %msgTypes = ( "02" => "Ack",
                 "30" => "ShutterContactState",
                 "60" => "HeatingThermostatState",
               );

sub
CUL_MAX_Parse($$)
{
  my ($hash, $rmsg) = @_;

  if(!exists($modules{CUL_MAX}{defptr})) {
      Log 5, "No CUL_MAX defined";
      return "UNDEFINED CULMAX0 CUL_MAX 123456";
  }
  my $shash = $modules{CUL_MAX}{defptr};

  $rmsg =~ m/Z(..)(..)(..)(..)(......)(......)(..)(.*)/;
  my ($len,$msgcnt,$msgFlag,$msgTypeRaw,$src,$dst,$zero,$payload) = ($1,$2,$3,$4,$5,$6,$7,$8);
  Log 1, "CUL_MAX_Parse: len mismatch" if(2*hex($len)+3 != length($rmsg)); #+3 = +1 for 'Z' and +2 for len field in hex
  Log 1, "CUL_MAX_Parse zero = $zero" if($zero != 0);

  my $msgFlLong = "";
  for(my $i = 0; $i < @culHmCmdFlags; $i++) {
      $msgFlLong .= ",$culHmCmdFlags[$i]" if(hex($msgFlag) & (1<<$i));
  }

  #convert adresses to lower case
  $src = lc($src);
  $dst = lc($dst);

  Log 5, "CUL_MAX_Parse: len $len, msgcnt $msgcnt, msgflag $msgFlLong, msgTypeRaw $msgTypeRaw, src $src, dst $dst, payload $payload";
  if(exists($msgTypes{$msgTypeRaw})) {
    my $msgType = $msgTypes{$msgTypeRaw};
    if($msgType eq "Ack") {
      Log 5, "Got Ack";
    } else {
      Dispatch($shash, "MAX,$msgType,$src,$payload", {RAWMSG => $rmsg});
    }
  } else {
    Log 2, "Got unhandled message type $msgTypeRaw";
  }
  return undef;
}

sub
CUL_MAX_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;

  $hash->{cnt} += 1;
  substr($payload,3,3) = pack("H6",$hash->{addr});
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
  <br><br>

  <a name="CUL_MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_MAX &lt;addr&gt;</code>
      <br><br>

      Defines an CUL_MAX device of type &lt;type&gt; and rf address &lt;addr&gt. The rf address
      must not be in use by any other MAX device.
  </ul>
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
