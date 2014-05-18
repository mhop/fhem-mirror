
# $Id$
package main;

use strict;
use warnings;

sub CommandCopy($$);

sub
copy_Initialize($)
{
  my %lhash = ( Fn=>"CommandCopy",
                Hlp=>"<orig name> <copy name>" );
  $cmds{copy} = \%lhash;
}

sub
CommandCopy($$)
{
  my ($hash, $param) = @_;

  my @args = split(/ +/,$param);

  return "Usage: copy <orig name> <copy name>" if (@args != 2);

  my $d = $defs{$args[0]};
  return "$args[0] not defined" if( !$d );

  my $cmd = "$args[1] $d->{TYPE}";
  $cmd .= " $d->{DEF}" if( $d->{DEF} );
  my $ret = CommandDefine($hash, $cmd );
  return $ret if( $ret );

  foreach my $a (keys %{$attr{$args[0]}}) {
    CommandAttr($hash, "$args[1] $a $attr{$args[0]}{$a}");
  }
}

1;

=pod
=begin html

<a name="copy"></a>
<h3>copy</h3>
<ul>
  <code>copy &lt;orig name&gt; &lt;copy name&gt;</code><br>
  <br>
    Create a copy of device &lt;orig name&gt; with the name &lt;copy name&gt;.
</ul>

=end html

=begin html_DE

<a name="copy"></a>
<h3>copy</h3>
<ul>
  <code>copy &lt;orig name&gt; &lt;copy name&gt;</code><br>
  <br>
    Erzeugt eine Kopie des Device &lt;orig name&gt; mit dem namen &lt;copy name&gt;.
</ul>

=end html_DE
=cut
