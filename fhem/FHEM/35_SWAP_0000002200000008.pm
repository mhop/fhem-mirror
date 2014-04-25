
# $Id$
package main;

use strict;
use warnings;

use constant { REG_DESIRED => '0D',
               REG_TEXT => '0E', };

sub
SWAP_0000002200000008_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/34_SWAP.pm";

  $hash->{SWAP_SetFn}     = "SWAP_0000002200000008_Set";
  $hash->{SWAP_SetList}   = { desired => 1,
                              text => undef, };
  #$hash->{SWAP_GetFn}     = "SWAP_0000002200000008_Get";
  #$hash->{SWAP_GetList}   = { };
  #$hash->{SWAP_ParseFn}   = "SWAP_0000002200000008_Parse";

  my $ret = SWAP_Initialize($hash);

  return $ret;
}

sub
SWAP_0000002200000008_Parse($$$$)
{
  my ($hash, $reg, $func, $data) = @_;
  my $name = $hash->{NAME};
}

sub
SWAP_0000002200000008_Set($@)
{
  my ($hash, $name, $cmd, $arg, $arg2, $arg3) = @_;

  if( $cmd eq "desired" ) {
    $arg += 50;
    $arg *= 10;
    my $value = sprintf( "%04X", int($arg) );
    return( "regSet", REG_DESIRED, $value );
  } elsif( $cmd eq "text" ) {
    my $text = "000000000000000000000000000000000000000000000000";
    $arg .= " ". $arg2 if( defined($arg2) );
    $arg .= " ". $arg3 if( defined($arg3) );
    for( my $i = 0; $i < length($arg); ++$i) {
      last if( $i >= 18 );
      substr( $text, 2*$i, 2, sprintf( "%02X", ord(substr($arg, $i, 1) ) ) );
    }

    return( "regSet", REG_TEXT, "FFFE" . "02" . $text );
  }

  return undef;
}

sub
SWAP_0000002200000008_Get($@)
{
  my ($hash, $name, $cmd, @a) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="SWAP_0000002200000008"></a>
<h3>SWAP_0000002200000008</h3>
<ul>

  <tr><td>
  Module for the justme version of the panstamp indoor multi sensor board (sketch product code 0000002200000008).

  <br><br>

  <a name="SWAP_0000002200000008_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SWAP_0000002200000008 &lt;ID&gt; 0000002200000008</code> <br>
    <br>
  </ul>
  <br>

  <a name="SWAP_0000002200000008_Set"></a>
  <b>Set </b>
  all SWAP set commands and:
  <ul>
    <li>desired &lt;value&gt;<br>
        sets the desired temperature to &lt;value&gt;</li>
    <li>text &lt;text&gt;<br>
        displays text</li>
  </ul><br>

  <a name="SWAP_0000002200000008_Get"></a>
  <b>Get</b>
  all SWAP get commands and:
  <ul>
  </ul><br>

  <a name="SWAP_0000002200000008_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>ProductCode<br>
      must be 0000002200000008</li><br>
  </ul><br>
</ul>

=end html
=cut
