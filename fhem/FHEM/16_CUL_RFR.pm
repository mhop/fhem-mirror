##############################################
# $Id$
package main;

use strict;
use warnings;

#####################################
sub
CUL_RFR_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^[0-9A-F]{4}U.";
  $hash->{DefFn}     = "CUL_RFR_Define";
  $hash->{FingerprintFn} = "RFR_FingerprintFn";
  $hash->{UndefFn}   = "CUL_RFR_Undef";
  $hash->{ParseFn}   = "CUL_RFR_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 model:CUL,CUN,CUR " .
                       "ignore:0,1 addvaltrigger";

  $hash->{WriteFn}   = "CUL_RFR_Write";
  $hash->{GetFn}     = "CUL_Get";
  $hash->{SetFn}     = "CUL_Set";
  $hash->{noRawInform} = 1;     # Our message was already sent as raw.
  $hash->{AddPrefix} = "CUL_RFR_AddPrefix"; 
  $hash->{DelPrefix} = "CUL_RFR_DelPrefix"; 
  $hash->{noAutocreatedFilelog} = 1;
}


sub
RFR_FingerprintFn($$)
{
  my ($name, $msg) = @_;
 
  # Store only the "relevant" part, as the CUL won't compute the checksum
  $msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);
 
  return ($name, $msg);
}

#####################################
sub
CUL_RFR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_RFR <id> <routerid>"
            if(int(@a) != 4 ||
               $a[2] !~ m/[0-9A-F]{2}/i ||
               $a[3] !~ m/[0-9A-F]{2}/i);
  $hash->{ID} = $a[2];
  $hash->{ROUTERID} = $a[3];
  $modules{CUL_RFR}{defptr}{"$a[2]$a[3]"} = $hash;
  $hash->{STATE} = "Defined";
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_RFR_Write($$)
{
  my ($hash,$fn,$msg) = @_;

  ($fn, $msg) = CUL_WriteTranslate($hash, $fn, $msg);
  return if(!defined($fn));
  $msg = $hash->{ID} . $hash->{ROUTERID} . $fn . $msg;
  IOWrite($hash, "u", $msg);
}

#####################################
sub
CUL_RFR_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_RFR}{defptr}{$hash->{ID} . $hash->{ROUTERID}});
  return undef;
}

#####################################
sub
CUL_RFR_Parse($$)
{
  my ($iohash,$msg) = @_;

  # 0123456789012345678
  # E01012471B80100B80B -> Type 01, Code 01, Cnt 10
  $msg =~ m/^([0-9AF]{2})([0-9AF]{2})U(.*)/;
  my ($rid, $id, $smsg) = ($1,$2,$3);
  my $cde = "${id}${rid}";

  if(!$modules{CUL_RFR}{defptr}{$cde}) {
    Log3 $iohash, 1, "CUL_RFR detected, Id $id, Router $rid, MSG $smsg";
    return "UNDEFINED CUL_RFR_$id CUL_RFR $id $rid";
  }
  my $hash = $modules{CUL_RFR}{defptr}{$cde};
  my $name = $hash->{NAME};
  return "" if(IsIgnored($name));

  $hash->{Clients}   = $iohash->{Clients};
  $hash->{MatchList} = $iohash->{MatchList};

  my @m = split(";", $smsg, -1);  # process only messages terminated with ;
  for(my $i = 0; $i < $#m; $i++) {
    my $m = $m[$i];

    # Compressed FHT messages
    while($m =~ m/^T(....)(..)(..)(..)(..)(..)(.*)(..)$/) {
      my ($fhtid, $cmd, $source, $val, $cmd2, $val2, $rest, $rssi) =
         ($1, $2, $3, $4, $5, $6, $7, $8);
      my $firstmsg = "T$fhtid$cmd$source$val$rssi";
      $m = "T$fhtid$cmd2$source$val2$rest$rssi";
      CUL_Parse($hash, $iohash, $hash->{NAME}, $firstmsg, "X21");
    }

    CUL_Parse($hash, $iohash, $hash->{NAME}, $m, "X21");
       if($m =~ m/^T/) { $hash->{NR_TMSG}++ }
    elsif($m =~ m/^F/) { $hash->{NR_FMSG}++ }
    elsif($m =~ m/^E/) { $hash->{NR_EMSG}++ }
    elsif($m =~ m/^K/) { $hash->{NR_KMSG}++ }
    else               { $hash->{NR_RMSG}++ }
  }
  return "";
}

sub
CUL_RFR_DelPrefix($$)
{
  my ($hash, $msg) = @_;
  $msg = $1 if($msg =~ m/^\d{4}U(.*)$/);
  $msg =~ s/;([\r\n]*)$/$1/; # ???
  return $msg;
}

sub
CUL_RFR_AddPrefix($$)
{
  my ($hash, $msg) = @_;
  return "u" . $hash->{ID} . $hash->{ROUTERID} . $msg;
}

1;


=pod
=begin html

<a name="CUL_RFR"></a>
<h3>CUL_RFR</h3>
<ul>
  <table>
  <tr><td>
  The CUL_RFR  module is used to "attach" a second CUL to your base CUL, and
  use it as a repeater / range extender. RFR is shorthand for RF_ROUTER.
  Transmission of the data uses the CC1101 packet capabilities with GFSK
  modulation at 250kBaud after pinging the base CUL at the usual 1kBaud. When
  configured, the RFR device can be used like another CUL connected directly to
  fhem.


  <br><br>
  Before you can use this feature in fhem, you have to enable/configure RF
  ROUTING in both CUL's:
  <ul>
    <li>First give your base CUL (which remains connected to the PC) an RFR ID
    by issuing the fhem command "set MyCUL raw ui0100". With this command
    the base CUL will get the ID 01, and it will not relay messages to other
    CUL's (as the second number is 00).</li>
    <li>Now replace the base CUL with the RFR CUL, and set its id by issuing
    the fhem command "set MyCUL raw ui0201". Now remove this CUL and attach the
    original, base CUL again. The RFR CUL got the id 02, and will relay every
    message to the base CUL with id 01.</li>
    <li>Take the RFR CUL, and attach it to an USB power supply, as seen on
    the image. As the configured base id is not 00, it will activate RF
    reception on boot, and will start sending messages to the base CUL.</li>
    <li>Now you have to define this RFR cul as a fhem device:</li>
  </ul>

  </td><td>
  <img src="cul_rfr.jpg"/>
  </td></tr>
  </table>
  <br>

  <a name="CUL_RFRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_RFR &lt;own-id&gt; &lt;base-id&gt;</code> <br>
    <br>
    &lt;own-id&gt; is the id of the RFR CUL <b>not</b> connected to the PC,
    &lt;base-id&gt; is the id of the CUL connected to the PC. Both parameters
    have two characters, each representing a one byte hex number.<br>
    Example:
    <ul>
      <code>set MyCUL raw ui0100</code><br>
      # Now replace the base CUL with the RFR CUL<br>
      <code>set MyCUL raw ui0201</code><br>
      # Reattach the base CUL to the PC and attach the RFR CUL to a
      USB power supply<br>
      <code>define MyRFR CUL_RFR 02 01</code><br>
    </ul>
    </ul> <br>

  <a name="CUL_RFRset"></a>
  <b>Set</b> <ul>Same as for the <a href="#CULset">CUL</a>.</ul><br>

  <a name="CUL_RFRget"></a>
  <b>Get</b> <ul>Same as for the <a href="#CULget">CUL</a>.</ul><br>

  <a name="CUL_RFRattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#IODev">IODev</a></li><br>
    The rest of the attributes is the same as for the <a href="#CUL">CUL</a>.</ul><br>
  </ul>
  <br>

=end html
=cut
