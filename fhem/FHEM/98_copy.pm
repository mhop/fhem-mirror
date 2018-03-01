
# $Id$
package main;

use strict;
use warnings;

sub CommandCopy($$);

sub
copy_Initialize($)
{
  my %lhash = ( Fn=>"CommandCopy",
                Hlp=>"<orig name> <copy name> [<type dependent arguments>]" );
  $cmds{copy} = \%lhash;
}

sub
CommandCopy($$)
{
  my ($hash, $param) = @_;

  my @args = split(/ +/,$param);

  return "Usage: copy <orig name> <copy name> [<type dependent arguments>]" if (@args < 2);

  my $d = $defs{$args[0]};
  return "$args[0] not defined" if( !$d );

  my $cmd = "$args[1] $d->{TYPE}";
  if( $args[2] ) {
    $cmd .= ' '. join( ' ', @args[2..@args-1]);
  } else {
    $cmd .= " $d->{DEF}" if( $d->{DEF} );
  }

  my $ret = CommandDefine($hash, $cmd );
  return $ret if( $ret );

  my $a = 'userattr';
  if( $attr{$args[0]} && $attr{$args[0]}{$a} ) {
    CommandAttr($hash, "$args[1] $a $attr{$args[0]}{$a}");
  }

  foreach my $a (keys %{$attr{$args[0]}}) {
    next if( $a eq 'userattr' );
    CommandAttr($hash, "$args[1] $a $attr{$args[0]}{$a}");
  }

  CallFn($args[1], "CopyFn", $args[0], $args[1]);
}

1;

=pod
=item command
=item summary    copy a fhem device
=item summary_DE kopiert ein FHEM Ger&auml;t
=begin html

<a name="copy"></a>
<h3>copy</h3>
<ul>
  <code>copy &lt;orig name&gt; &lt;copy name&gt; [&lt;type dependent arguments&gt;]</code><br>
  <br>
    Create a copy of device &lt;orig name&gt; with the name &lt;copy name&gt;.<br>
    If &lt;type dependent arguments&gt; are given they will replace the DEF of &lt;orig name&gt; for the creation of &lt;copy name&gt;.
</ul>

=end html

=begin html_DE

<a name="copy"></a>
<h3>copy</h3>
<ul>
  <code>copy &lt;orig name&gt; &lt;copy name&gt; [&lt;type dependent arguments&gt;]</code><br>
  <br>
    Erzeugt eine Kopie des Device &lt;orig name&gt; mit dem namen &lt;copy name&gt;.<br>
    Wenn &lt;type dependent arguments&gt; angegeben sind ersetzen die die DEF von &lt;orig name&gt; beim anlegen von &lt;copy name&gt;.
</ul>

=end html_DE
=cut
